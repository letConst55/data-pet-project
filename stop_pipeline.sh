#!/bin/bash

echo "🛑 Остановка Data Pet Project и сброс данных до чистого листа..."

# --- НАСТРОЙКИ ПРОЕКТА ---
PG_CONTAINER="local_postgres"
PG_USER="pet_user"
PG_DB="pet_dwh"
ODS_SCHEMA="ods_events"              # Укажи схему, где лежат ods_ таблицы (например, public или ods)

MINIO_CONTAINER="local_minio"
DBT_PROJECT_DIR="./analytics"              # Путь к папке с dbt_project.yml (например, "./dbt_project" или ".")
# -------------------------

# 1. Сначала останавливаем генератор, консьюмер и Airflow, чтобы новые данные перестали течь
echo "🔌 Остановка фоновых процессов (Generator, Consumer, Airflow)..."
if [ -f .generator.pid ]; then
    kill $(cat .generator.pid) 2>/dev/null
    rm .generator.pid
fi

if [ -f .consumer.pid ]; then
    kill $(cat .consumer.pid) 2>/dev/null
    rm .consumer.pid
fi

if [ -f .airflow.pid ]; then
    kill $(cat .airflow.pid) 2>/dev/null
    rm .airflow.pid
fi

pkill -f "data_generator/main.py" 2>/dev/null
pkill -f "consumer_s3.py" 2>/dev/null
pkill -f "airflow" 2>/dev/null
sleep 2

# 2. Очистка сырых таблиц ods_client_events и ods_mechanic_events (пока контейнер БД еще запущен)
echo "🗄 Очистка таблиц ods_client_events и ods_mechanic_events в PostgreSQL..."
docker exec -i "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -c \
    "TRUNCATE TABLE ${ODS_SCHEMA}.ods_client_events, ${ODS_SCHEMA}.ods_mechanic_events RESTART IDENTITY CASCADE;"

# 3. Полный пересчет dbt моделей (поверх пустых ODS таблиц витрины очистятся)
echo "🧱 Запуск dbt run --full-refresh..."
if [ -d "venv" ]; then
    source venv/bin/activate
fi

if [ -f "${DBT_PROJECT_DIR}/dbt_project.yml" ]; then
    dbt run --full-refresh --project-dir "$DBT_PROJECT_DIR"
else
    echo "⚠️ Файл dbt_project.yml не найден по пути '${DBT_PROJECT_DIR}'. Проверь переменную DBT_PROJECT_DIR в скрипте."
fi

# 4. Очистка файлов внутри бакетов S3 (MinIO), сохраняя сами бакеты
echo "🪣 Очистка сырых файлов из бакетов S3 (MinIO)..."
docker exec -i "$MINIO_CONTAINER" sh -c "rm -rf /data/*/* 2>/dev/null"

# 5. Остановка контейнеров (Redpanda очистится автоматически, а папки pg_data и minio_data сохранят структуру)
echo "📦 Остановка контейнеров Docker..."
docker compose down

rm -f data_generator/generator_state.json

echo "✅ Пайплайн успешно остановлен, ODS и S3 очищены, модели dbt сброшены!"