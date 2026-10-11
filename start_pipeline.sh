#!/bin/bash

echo "🚀 Запуск Data Pet Project: Top Bikes..."

# 1. Запуск инфраструктуры Docker
echo "📦 Подъем контейнеров (OrbStack/Docker)..."
docker compose up -d
sleep 5

# 2. Активация виртуального окружения
source venv/bin/activate

# 3. Запуск генератора данных (наш новый "бэкенд")
echo "🏍 Запуск генератора событий (Top Bikes)..."
# Добавляем PYTHONPATH, чтобы питон корректно видел модули core и modules
export PYTHONPATH=$(pwd)/data_generator
python3 data_generator/main.py > logs_generator.txt 2>&1 &
GEN_PID=$!
echo $GEN_PID > .generator.pid
echo "Генератор запущен (PID: $GEN_PID). Логи: logs_generator.txt"

# 4. Запуск консьюмера (высадка в Data Lake)
echo "🎧 Запуск консьюмера (Kafka -> S3)..."
python3 consumer_s3.py > logs_consumer.txt 2>&1 &
CONSUMER_PID=$!
echo $CONSUMER_PID > .consumer.pid
echo "Консьюмер запущен (PID: $CONSUMER_PID). Логи: logs_consumer.txt"

# 5. Запуск Airflow (Оркестрация ELT)
echo "🌬 Запуск Airflow..."
export AIRFLOW_HOME=$(pwd)/airflow_home
airflow standalone > logs_airflow.txt 2>&1 &
AIRFLOW_PID=$!
echo $AIRFLOW_PID > .airflow.pid
echo "Airflow запущен (PID: $AIRFLOW_PID)"

echo "✅ Все системы работают!"
echo "MinIO (Data Lake): http://127.0.0.1:9001"
echo "Airflow (Оркестратор): http://127.0.0.1:8080"