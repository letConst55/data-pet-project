import argparse
import os
import tempfile
from datetime import datetime
from pathlib import Path

import boto3
import snowflake.connector
from dotenv import load_dotenv

load_dotenv()

TOPICS_TO_TABLES = {
    "client_app_events": "ods_client_events",
    "mechanic_app_events": "ods_mechanic_events",
    "hr_app_events": "ods_hr_events",
    "shop_app_events": "ods_shop_events",
    "inventory_events": "ods_inventory_events",
}

BUCKET_NAME = "raw-events"


def get_s3_client():
    return boto3.client(
        "s3",
        endpoint_url=os.getenv("MINIO_ENDPOINT", "http://localhost:9000"),
        aws_access_key_id=os.getenv("MINIO_ACCESS_KEY", "minioadmin"),
        aws_secret_access_key=os.getenv("MINIO_SECRET_KEY", "miniopassword"),
        region_name="us-east-1",
    )


def get_snowflake_connection():
    conn_params = {
        "account": os.environ["SNOWFLAKE_ACCOUNT"],
        "user": os.environ["SNOWFLAKE_USER"],
        "role": os.getenv("SNOWFLAKE_ROLE", "TRANSFORMER_ROLE"),
        "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE", "TRANSFORM_WH"),
        "database": os.getenv("SNOWFLAKE_DATABASE", "TOP_BIKES_DWH"),
        "schema": os.getenv("SNOWFLAKE_SCHEMA", "ODS_EVENTS"),
    }
    authenticator = os.getenv("SNOWFLAKE_AUTHENTICATOR")
    if authenticator:
        conn_params["authenticator"] = authenticator
    else:
        conn_params["password"] = os.environ["SNOWFLAKE_PASSWORD"]

    return snowflake.connector.connect(**conn_params)


def list_all_keys(s3_client, prefix: str) -> list[str]:
    """Пагинированный обход MinIO (list_objects_v2 возвращает максимум 1000 ключей за вызов)."""
    keys = []
    paginator = s3_client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=BUCKET_NAME, Prefix=prefix):
        for obj in page.get("Contents", []):
            if obj["Key"].endswith(".json"):
                keys.append(obj["Key"])
    return keys


def ensure_ods_tables(cursor):
    for table_name in TOPICS_TO_TABLES.values():
        cursor.execute(f"""
            CREATE TABLE IF NOT EXISTS ODS_EVENTS.{table_name} (
                event_id VARCHAR(255),
                event_type VARCHAR(100),
                event_timestamp TIMESTAMP_NTZ,
                payload VARIANT,
                loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
            );
        """)


def load_topic(s3_client, cursor, topic: str, table_name: str, target_date: str | None):
    prefix = f"events/{topic}/date={target_date}/" if target_date else f"events/{topic}/"
    keys = list_all_keys(s3_client, prefix)

    if not keys:
        print(f"[{topic}] No files found for prefix '{prefix}'. Skipping.")
        return

    print(f"[{topic}] Found {len(keys)} file(s). Staging to Snowflake...")

    stage_path = f"@ODS_EVENTS.MINIO_LANDING_STAGE/{topic}"

    with tempfile.TemporaryDirectory() as tmp_dir:
        # 1. Скачиваем батч файлов из MinIO во временную папку
        for idx, key in enumerate(keys):
            local_file = Path(tmp_dir) / f"batch_{idx:06d}_{Path(key).name}"
            s3_client.download_file(BUCKET_NAME, key, str(local_file))

        # 2. Чистим старую временную папку в Internal Stage и заливаем свежий батч (авто-gzip)
        cursor.execute(f"REMOVE {stage_path}/;")
        local_glob = (Path(tmp_dir) / "*.json").as_posix()
        cursor.execute(
            f"PUT 'file://{local_glob}' {stage_path}/ AUTO_COMPRESS=TRUE OVERWRITE=TRUE PARALLEL=4;"
        )

    # 3. Загружаем во временную таблицу через нативный COPY INTO с парсингом JSON
    temp_table = f"ODS_EVENTS.tmp_{table_name}"
    cursor.execute(f"CREATE OR REPLACE TEMPORARY TABLE {temp_table} LIKE ODS_EVENTS.{table_name};")
    cursor.execute(f"""
        COPY INTO {temp_table} (event_id, event_type, event_timestamp, payload)
        FROM (
            SELECT
                $1:event_id::VARCHAR,
                $1:event_type::VARCHAR,
                $1:timestamp::TIMESTAMP_NTZ,
                $1:payload::VARIANT
            FROM {stage_path}/
        )
        FILE_FORMAT = (FORMAT_NAME = 'ODS_EVENTS.NDJSON_FORMAT')
        ON_ERROR = 'ABORT_STATEMENT';
    """)

    # 4. Идемпотентный MERGE с дедупликацией (аналог ON CONFLICT DO NOTHING)
    cursor.execute(f"""
        MERGE INTO ODS_EVENTS.{table_name} AS tgt
        USING (
            SELECT event_id, event_type, event_timestamp, payload, loaded_at
            FROM {temp_table}
            QUALIFY ROW_NUMBER() OVER (PARTITION BY event_id ORDER BY event_timestamp DESC) = 1
        ) AS src
        ON tgt.event_id = src.event_id
        WHEN NOT MATCHED THEN
            INSERT (event_id, event_type, event_timestamp, payload, loaded_at)
            VALUES (src.event_id, src.event_type, src.event_timestamp, src.payload, src.loaded_at);
    """)
    inserted_rows = cursor.fetchone()[0]

    # Чистим временные файлы в Stage, чтобы не платить за хранение дублей
    cursor.execute(f"REMOVE {stage_path}/;")
    print(f"✅ [{topic}] Merged into {table_name}: {inserted_rows} new rows inserted.")


def main():
    parser = argparse.ArgumentParser(description="Load NDJSON batches from MinIO into Snowflake ODS.")
    parser.add_argument("--date", type=str, default=None, help="Target date YYYY-MM-DD (default: today)")
    parser.add_argument("--all", action="store_true", help="Load all historical dates from MinIO")
    args = parser.parse_args()

    target_date = None if args.all else (args.date or datetime.now().strftime("%Y-%m-%d"))

    s3_client = get_s3_client()
    print("Connecting to Snowflake...")
    conn = get_snowflake_connection()

    try:
        cursor = conn.cursor()
        ensure_ods_tables(cursor)

        for topic, table_name in TOPICS_TO_TABLES.items():
            load_topic(s3_client, cursor, topic, table_name, target_date)

        cursor.close()
    finally:
        conn.close()
        print("Done. Connection closed.")


if __name__ == "__main__":
    main()