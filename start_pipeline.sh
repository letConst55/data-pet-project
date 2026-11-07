#!/bin/bash

echo "Launch Data Pet Project: Top Bikes..."

# 1. Launching the Docker application
echo "Spinning up containers (OrbStack/Docker)..."
docker compose up -d
sleep 5

# 2. Activating the virtual environment
source venv/bin/activate

# 3. Launching the data generator (our new "backend")
echo "Launching the event generator (Top Bikes)..."

export PYTHONPATH=$(pwd)/data_generator
python3 data_generator/main.py > logs_generator.txt 2>&1 &
GEN_PID=$!
echo $GEN_PID > .generator.pid
echo "The generator has been started (PID: $GEN_PID). Logs: logs_generator.txt"

# 4. Launching the consumer (descent Data Lake)
echo "(Kafka -> S3)..."
python3 consumer_s3.py > logs_consumer.txt 2>&1 &
CONSUMER_PID=$!
echo $CONSUMER_PID > .consumer.pid
echo "Consumer has been started (PID: $CONSUMER_PID). Logs: logs_consumer.txt"

# 5. Airflow
echo "Launching Airflow..."
export AIRFLOW_HOME=$(pwd)/airflow_home
airflow standalone > logs_airflow.txt 2>&1 &
AIRFLOW_PID=$!
echo $AIRFLOW_PID > .airflow.pid
echo "Airflow has been started (PID: $AIRFLOW_PID)"

echo "✅ All systems work properly!"
echo "MinIO (Data Lake): http://127.0.0.1:9001"
echo "Airflow: http://127.0.0.1:8080"