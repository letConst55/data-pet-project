#!/bin/bash
echo "🧊 Загружаем финальный слепок из S3 в PostgreSQL..."
source venv/bin/activate
python3 s3_to_postgres.py

echo "🛑 Останавливаем тяжелые фоновые сервисы (Airflow, Generator, Consumer, Redpanda, MinIO)..."
pkill -f "data_generator/main.py" 2>/dev/null
pkill -f "consumer_s3.py" 2>/dev/null
pkill -f "airflow" 2>/dev/null
rm -f .generator.pid .consumer.pid .airflow.pid

docker stop local_redpanda local_minio local_grafana 2>/dev/null

echo "✅ В работе остался только PostgreSQL (~150 МБ RAM)!"
echo "Теперь можно спокойно писать dbt-модели, работать в DBeaver/Jupyter и выгружать данные для Tableau."