import os
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator

# Путь к корню проекта
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../'))

default_args = {
    'owner': 'data-engineer',
    'start_date': datetime(2026, 9, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=1),
}

with DAG(
    dag_id='elt_pipeline_s3_to_dwh',
    default_args=default_args,
    description='ELT: Загрузка из MinIO и сборка витрин через dbt',
    schedule='*/15 * * * *',
    catchup=False,
    tags=['pet-project', 'dbt', 'data-quality']
) as dag:

    # Задача 1: Высадка сырых данных (Extract & Load)
    run_load_script = BashOperator(
        task_id='load_s3_to_postgres',
        bash_command=f"cd {PROJECT_ROOT} && {PROJECT_ROOT}/venv/bin/python3 s3_to_postgres.py"
    )

    # ВРЕМЕННО ОТКЛЮЧЕНО: dbt модели будут спроектированы заново под новую архитектуру
    # run_dbt_model = BashOperator(
    #     task_id='run_dbt_models',
    #     bash_command=f"cd {PROJECT_ROOT}/analytics && {PROJECT_ROOT}/venv/bin/dbt run"
    # )
    # 
    # test_dbt_model = BashOperator(
    #     task_id='test_dbt_models',
    #     bash_command=f"cd {PROJECT_ROOT}/analytics && {PROJECT_ROOT}/venv/bin/dbt test"
    # )

    # Оставляем в пайплайне только загрузку
    run_load_script # >> run_dbt_model >> test_dbt_model