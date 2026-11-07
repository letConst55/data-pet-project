#!/bin/bash
echo "Loading the final snapshot from S3 into PostgreSQL..."
source venv/bin/activate
python3 s3_to_postgres.py

echo "Stopping resource-intensive background services (Airflow, Generator, Consumer, Redpanda, MinIO)..."
pkill -f "data_generator/main.py" 2>/dev/null
pkill -f "consumer_s3.py" 2>/dev/null
pkill -f "airflow" 2>/dev/null
rm -f .generator.pid .consumer.pid .airflow.pid

docker stop local_redpanda local_minio local_grafana 2>/dev/null

echo "Only PostgreSQL remains in use."