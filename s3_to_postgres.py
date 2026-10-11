import boto3
import json
import psycopg2
from psycopg2.extras import execute_values
from datetime import datetime

# 1. Настройки подключений
s3_client = boto3.client('s3',
    endpoint_url='http://localhost:9000',
    aws_access_key_id='minioadmin',
    aws_secret_access_key='miniopassword',
    region_name='us-east-1'
)
bucket_name = 'raw-events'

# Определяем логическую дату загрузки (за сегодня)
target_date = datetime.now().strftime('%Y-%m-%d')

# Маппинг: Топик (папка в S3) -> Таблица в PostgreSQL
topics_to_tables = {
    'client_app_events': 'ods_client_events',
    'mechanic_app_events': 'ods_mechanic_events',
    'hr_app_events': 'ods_hr_events',              # НОВОЕ
    'shop_app_events': 'ods_shop_events',          # НОВОЕ
    'inventory_events': 'ods_inventory_events'     # НОВОЕ
}

print(f"Подключение к PostgreSQL...")
conn = psycopg2.connect(
    dbname="pet_dwh", user="pet_user", password="pet_password", host="localhost", port="5432"
)
cursor = conn.cursor()

# 2. Создание ODS таблиц, если их еще нет

cursor.execute("CREATE SCHEMA IF NOT EXISTS ods_events;")

for table_name in topics_to_tables.values():
    cursor.execute(f"""
        CREATE TABLE IF NOT EXISTS ods_events.{table_name} (
            event_id VARCHAR(255) PRIMARY KEY,
            event_type VARCHAR(100),
            event_timestamp TIMESTAMP,
            payload JSONB,
            loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    """)
conn.commit()

# 3. Итерация по топикам и загрузка
for topic, table_name in topics_to_tables.items():
    prefix = f"events/{topic}/date={target_date}/"
    response = s3_client.list_objects_v2(Bucket=bucket_name, Prefix=prefix)
    
    if 'Contents' not in response:
        print(f"[{topic}] Нет данных для загрузки за {target_date}")
        continue

    all_events = []
    
    # Считываем все файлы за день
    for obj in response['Contents']:
        file_key = obj['Key']
        s3_object = s3_client.get_object(Bucket=bucket_name, Key=file_key)
        file_content = s3_object['Body'].read().decode('utf-8')
        
        for line in file_content.strip().split('\n'):
            if line:
                event = json.loads(line)
                # Конвертируем payload обратно в строку JSON для вставки в поле JSONB
                payload_json = json.dumps(event.get('payload', {}))
                all_events.append((
                    event.get('event_id'),
                    event.get('event_type'),
                    event.get('timestamp'),
                    payload_json
                ))

    if not all_events:
        continue

    print(f"[{topic}] Найдено {len(all_events)} событий. Загрузка в {table_name}...")

    # 4. Идемпотентная загрузка (DELETE + INSERT)
    try:
        cursor.execute(f"DELETE FROM ods_events.{table_name} WHERE DATE(event_timestamp) = '{target_date}'")
        
        insert_query = f"""
            INSERT INTO ods_events.{table_name} (event_id, event_type, event_timestamp, payload)
            VALUES %s
            ON CONFLICT (event_id) DO NOTHING
        """
        execute_values(cursor, insert_query, all_events)
        conn.commit()
        print(f"✅ [{topic}] Успешно загружено {len(all_events)} строк")
    except Exception as e:
        conn.rollback()
        print(f"❌ [{topic}] Ошибка загрузки: {e}")

cursor.close()
conn.close()