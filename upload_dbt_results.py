import json
import os
import psycopg2
from datetime import datetime

# Путь к файлу с результатами (адаптируй, если у тебя другая структура папок)
RESULTS_FILE = "analytics/target/run_results.json"
MANIFEST_FILE = "analytics/target/manifest.json"

def get_db_connection():
    return psycopg2.connect(
        dbname="pet_dwh", 
        user="pet_user", 
        password="pet_password", 
        host="localhost", 
        port="5432"
    )

def setup_database(conn):
    cursor = conn.cursor()
    # Создаем схему и таблицу, если их нет
    cursor.execute("CREATE SCHEMA IF NOT EXISTS audit;")
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS audit.dbt_test_results (
            run_id VARCHAR(255),
            test_name VARCHAR(255),
            status VARCHAR(50),
            failures INTEGER,
            execution_time_sec NUMERIC(10, 2),
            run_started_at TIMESTAMP,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    """)
    conn.commit()
    cursor.close()

def parse_and_upload():
    if not os.path.exists(RESULTS_FILE):
        print(f"Файл {RESULTS_FILE} не найден. Запусти сначала dbt test.")
        return

    with open(RESULTS_FILE, 'r') as f:
        run_results = json.load(f)

    # Проверяем, что это результаты именно тестов (или dbt build)
    is_test_run = any(res.get('unique_id', '').startswith('test.') for res in run_results.get('results', []))
    if not is_test_run:
        print("В файле нет результатов тестов. Пропуск загрузки.")
        return

    run_started_at = run_results['metadata']['generated_at']
    run_id = run_results['metadata']['invocation_id']
    
    conn = get_db_connection()
    setup_database(conn)
    cursor = conn.cursor()

    uploaded_count = 0
    for result in run_results.get('results', []):
        if result['unique_id'].startswith('test.'):
            test_name = result['unique_id'].split('.')[-1]
            status = result['status']
            failures = result.get('failures', 0)
            execution_time = result.get('execution_time', 0.0)

            cursor.execute("""
                INSERT INTO audit.dbt_test_results 
                (run_id, test_name, status, failures, execution_time_sec, run_started_at)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (run_id, test_name, status, failures, execution_time, run_started_at))
            uploaded_count += 1

    conn.commit()
    cursor.close()
    conn.close()
    print(f"✅ Успешно загружено {uploaded_count} результатов тестов в audit.dbt_test_results")

if __name__ == "__main__":
    parse_and_upload()