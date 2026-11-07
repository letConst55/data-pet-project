# Orchestration & Operations

## Introduction
Finally, let's examine the lifecycle management approach for our data warehouse. During the Deployment and Operations phase (according to the Kimball methodology), it is critical to have reliable pipeline orchestration tools and convenient mechanisms for starting and stopping the entire infrastructure.

In our project, these tasks are divided into two levels:
1.  **ELT Process Orchestration:** Executed within Apache Airflow.
2.  **Infrastructure Lifecycle Management (Operations):** Implemented via control Bash scripts.

---

## 1. Data Orchestration (Apache Airflow)

The primary data flow orchestrator in our project is Apache Airflow. Its task is to manage dependencies and schedule all ELT processes.

As detailed in the physical design section (`03_physical_design.md`), the entire process is governed by a single Directed Acyclic Graph (DAG) named `elt_pipeline_s3_to_dwh`. 
Airflow is responsible for:
*   Timely execution of the data extraction script (S3 to PostgreSQL) every 15 minutes.
*   Dynamic selection of the dbt transformation mode (Full Refresh or Incremental).
*   Triggering the data mart builds (`dbt build`).
*   Calling the log parser (`upload_dbt_results.py`) to load test results into the audit schema.

Airflow is completely isolated from the data generation and streaming (Kafka) phases, focusing exclusively on the batch processing of files staged in the Data Lake.

---

## 2. Infrastructure Management (Operations Scripts)

Because the project is a complex distributed system (Generator, Kafka Consumer, Docker containers, Airflow), starting each component manually carries a high risk of error. To automate deployment and ensure safe shutdowns (with an optional state reset), two root Bash scripts were developed.

### 2.1 Starting the Pipeline (`start_pipeline.sh`)
The `start_pipeline.sh` script sequentially initializes all system nodes, strictly adhering to dependencies:

1.  **Infrastructure spin-up:** Initializes Docker containers (PostgreSQL, Redpanda, MinIO, Grafana) in the background via `docker compose up -d`.
2.  **Environment activation:** Activates the project's Python virtual environment (`source venv/bin/activate`).
3.  **Data source start (Generator):** Launches the bike rental business simulator (`data_generator/main.py`). The process is pushed to the background (`&`), and its Process ID (PID) is saved in a hidden `.generator.pid` file for subsequent safe termination. Output is redirected to the `logs_generator.txt` file.
4.  **Streaming start (Consumer):** Launches the `consumer_s3.py` script, which begins intercepting Kafka topics and forming the Data Lake. Its PID is also logged in `.consumer.pid`.
5.  **Orchestrator start:** Runs `airflow standalone`, specifying the local `AIRFLOW_HOME` directory, saving logs and a PID file (`.airflow.pid`).
6.  **Reporting:** Outputs links to the MinIO and Airflow web interfaces for visual monitoring.

### 2.2 Stopping and Resetting the Warehouse (`stop_pipeline.sh`)
The `stop_pipeline.sh` script goes beyond merely stopping the project; it executes a **"Reset to Zero"** pattern (wiping the slate clean). This is crucial for development idempotency: upon the next launch, the pipeline will start in an absolutely clean and consistent environment.

Script execution steps:
1.  **Graceful Shutdown of background processes:** The script reads the PID files for the generator, consumer, and Airflow, safely terminating them using the `kill` command. Additionally, `pkill` is executed to guarantee no hung processes remain. *Note: As described earlier, upon receiving this signal, the consumer manages an emergency flush of its remaining buffer to S3.*
2.  **ODS layer cleanup:** The script connects to the PostgreSQL container (`local_postgres`) via `docker exec` and executes a `TRUNCATE TABLE` command for all tables in the `ods_events` schema (e.g., `ods_client_events`, `ods_mechanic_events`) using the `RESTART IDENTITY CASCADE` parameter.
3.  **Cascading data mart cleanup (dbt):** The `dbt run --full-refresh` command is executed. Because the ODS layer is already empty, dbt rebuilds all dimensional models (Staging and Core) "empty," effectively wiping all fact and dimension tables in the data warehouse.
4.  **Data Lake cleanup (S3 / MinIO):** The script enters the MinIO container and physically deletes all raw NDJSON files from the buckets (`rm -rf /data/*/*`), while preserving the bucket directories themselves for future runs.
5.  **Infrastructure shutdown:** Executes `docker compose down` to stop the databases and message broker.
6.  **Generator state reset:** Deletes the `generator_state.json` file so that upon the next start, the business simulation (clients, bike mileages, warehouse inventory) begins from ground zero.

Thus, these scripts automate data engineering routines and ensure reliable, predictable environment behavior during the pipeline development and testing stages.