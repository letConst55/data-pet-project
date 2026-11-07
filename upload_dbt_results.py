import json
import os
import psycopg2

RESULTS_FILE = "analytics/target/run_results.json"

def get_db_connection():
    return psycopg2.connect(
        dbname="pet_dwh", user="pet_user", password="pet_password", host="localhost", port="5432"
    )

def parse_and_upload():
    if not os.path.exists(RESULTS_FILE):
        return

    with open(RESULTS_FILE, 'r') as f:
        run_results = json.load(f)

    # Checking results
    is_dbt_run = any(res.get('unique_id', '').startswith(('test.', 'model.')) for res in run_results.get('results', []))
    if not is_dbt_run:
        print("There is nothing..(")
        return

    run_started_at = run_results['metadata']['generated_at']
    run_id = run_results['metadata']['invocation_id']
    
    conn = get_db_connection()
    cursor = conn.cursor()

    tests_count, models_count = 0, 0
    
    for result in run_results.get('results', []):
        unique_id = result['unique_id']
        status = result['status']
        execution_time = result.get('execution_time', 0.0)

        # Tests parsing
        if unique_id.startswith('test.'):
            test_name = unique_id.split('.')[-1]
            failures = result.get('failures', 0)
            cursor.execute("""
                INSERT INTO audit.dbt_test_results (run_id, test_name, status, failures, execution_time_sec, run_started_at)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (run_id, test_name, status, failures, execution_time, run_started_at))
            tests_count += 1
            
        # Models parsing
        elif unique_id.startswith('model.'):
            model_name = unique_id.split('.')[-1]
            cursor.execute("""
                INSERT INTO audit.dbt_model_results (run_id, model_name, status, execution_time_sec, run_started_at)
                VALUES (%s, %s, %s, %s, %s)
            """, (run_id, model_name, status, execution_time, run_started_at))
            models_count += 1

    conn.commit()
    cursor.close()
    conn.close()

if __name__ == "__main__":
    parse_and_upload()