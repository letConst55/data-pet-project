import os
import psycopg2
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator, BranchPythonOperator

# Путь к корню проекта
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../'))

default_args = {
    'owner': 'data-engineer',
    'start_date': datetime(2026, 9, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=1),
}

def check_is_first_run():
    """Проверяет наличие данных в витрине. Если пусто или таблицы нет — нужен full-refresh."""
    try:
        conn = psycopg2.connect(dbname="pet_dwh", user="pet_user", password="pet_password", host="localhost", port="5432")
        cur = conn.cursor()
        cur.execute("SELECT count(*) FROM core.dim_client;")
        count = cur.fetchone()[0]
        cur.close()
        conn.close()
        return 'run_dbt_full_refresh' if count == 0 else 'run_dbt_incremental'
    except Exception:
        return 'run_dbt_full_refresh'

def truncate_audit_results():
    """Очищает логи предыдущего запуска перед вставкой новых для Grafana."""
    conn = psycopg2.connect(dbname="pet_dwh", user="pet_user", password="pet_password", host="localhost", port="5432")
    cur = conn.cursor()
    cur.execute("CREATE SCHEMA IF NOT EXISTS audit;")
    
    # Таблица для тестов
    cur.execute("""
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
    
    # НОВОЕ: Таблица для моделей
    cur.execute("""
        CREATE TABLE IF NOT EXISTS audit.dbt_model_results (
            run_id VARCHAR(255),
            model_name VARCHAR(255),
            status VARCHAR(50),
            execution_time_sec NUMERIC(10, 2),
            run_started_at TIMESTAMP,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    """)
    
    cur.execute("TRUNCATE TABLE audit.dbt_test_results;")
    cur.execute("TRUNCATE TABLE audit.dbt_model_results;") # Очищаем и модели тоже
    conn.commit()
    cur.close()
    conn.close()

with DAG(
    dag_id='elt_pipeline_s3_to_dwh',
    default_args=default_args,
    description='ELT: Загрузка из MinIO и сборка витрин через dbt',
    #schedule='*/15 * * * *',
    catchup=False,
    tags=['pet-project', 'dbt', 'data-quality']
) as dag:

    # 1. Высадка сырых данных (Extract & Load)
    load_s3_to_postgres = BashOperator(
        task_id='load_s3_to_postgres',
        bash_command=f"cd {PROJECT_ROOT} && {PROJECT_ROOT}/venv/bin/python3 s3_to_postgres.py"
    )

    # 2. Выбор режима запуска (Branching)
    branch_dbt_mode = BranchPythonOperator(
        task_id='branch_dbt_mode',
        python_callable=check_is_first_run
    )

    # 3a. Запуск dbt build (Full Refresh)
    run_dbt_full_refresh = BashOperator(
        task_id='run_dbt_full_refresh',
        bash_command=f"cd {PROJECT_ROOT}/analytics && {PROJECT_ROOT}/venv/bin/dbt build --full-refresh"
    )

    # 3b. Запуск dbt build (Инкрементально)
    run_dbt_incremental = BashOperator(
        task_id='run_dbt_incremental',
        bash_command=f"cd {PROJECT_ROOT}/analytics && {PROJECT_ROOT}/venv/bin/dbt build"
    )

    # 4. Очистка старых логов тестов 
    # trigger_rule позволяет таске выполниться после завершения любой из веток
    truncate_audit = PythonOperator(
        task_id='truncate_audit',
        python_callable=truncate_audit_results,
        trigger_rule='none_failed_min_one_success'
    )

    # 5. Выгрузка свежих результатов
    upload_dbt_results = BashOperator(
        task_id='upload_dbt_results',
        bash_command=f"cd {PROJECT_ROOT} && {PROJECT_ROOT}/venv/bin/python3 upload_dbt_results.py"
    )

    # Граф зависимостей
    load_s3_to_postgres >> branch_dbt_mode
    branch_dbt_mode >> [run_dbt_full_refresh, run_dbt_incremental]
    
    run_dbt_full_refresh >> truncate_audit
    run_dbt_incremental >> truncate_audit
    
    truncate_audit >> upload_dbt_results