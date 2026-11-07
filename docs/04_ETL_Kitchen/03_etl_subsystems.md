# 34 Kimball ETL Subsystems: Project Mapping

## Introduction
In his methodology, Ralph Kimball identifies 34 independent subsystems that must be present in a robust and scalable "ETL back room". In practice—especially with the advent of modern ELT tools like dbt and cloud architectures—many of these subsystems physically "collapse" into unified processes or are delegated to the database engine.

For our bike rental project, we designed a pipeline that incorporates the functionality of the vast majority of these subsystems. Even though this is a pet project, the architectural decisions laid down make the pipeline effectively Production-ready.

Below is the distribution of the classic 34 subsystems across 4 primary macro-categories, describing exactly how they are implemented in our project.

---

## 1. Extracting: Getting Data into the Data Warehouse
*Covers Subsystems 1–3 (Profiling, CDC, Extract System)*

In classic ETL, a massive amount of resources is spent on this stage. In our ELT approach, extraction is heavily simplified and decoupled from transformations.

*   **Subsystem 3: Extract System:** Implemented via a Kafka consumer (`consumer_s3.py`), which continuously reads business events from Redpanda broker topics and dumps them into S3 (MinIO) in NDJSON format.
*   **Subsystem 2: Change Data Capture (CDC) System:** Because we utilize the Event Sourcing pattern (the generator emits every event as an immutable fact to Kafka), we don't need a classic CDC tool (like Debezium) reading database WAL logs. Every event is natively a change delta. Incremental loading is guaranteed in the `s3_to_postgres.py` script via `INSERT ... ON CONFLICT DO NOTHING`.

---

## 2. Cleaning and Conforming Data
*Covers Subsystems 4–8 (Cleaning, Error Schema, Audit, Deduplication, Conforming)*

Cleaning in the ELT paradigm is shifted inside the warehouse (PostgreSQL) and executed by dbt.

*   **Subsystem 7: Deduplication System:** Implemented at the dbt Core layer. For instance, in `dim_client` and `dim_employee`, we use `DISTINCT ON (natural_key, event_timestamp)` to strip duplicate events arriving within a single micro-batch.
*   **Subsystem 4: Data Cleansing System:** The Staging layer (e.g., `stg_bike_dispensed`) handles cleansing and foundational typing. There, raw strings from `JSONB` are strictly cast to relational types (numbers, dates, booleans).
*   **Subsystem 6: Audit Dimension Assembler:** We built a custom system to load dbt execution results (`upload_dbt_results.py`). Model and test metrics are stored in the `audit` schema, allowing us to track when and how data was generated.

---

## 3. Delivering: Prepare for Presentation
*Covers Subsystems 9–21 (SCD Management, Surrogate Keys, Fact Building, Aggregates, etc.)*

This is the beating heart of our dbt project, where the logical dimensional model (Star Schema) takes shape.

*   **Subsystem 9: SCD Manager:** Fully implemented via incremental dbt models for `dim_client` and `dim_employee`. We automatically calculate version chronology (`row_effective_date`, `row_expiration_date`) using the `LEAD()` window function.
*   **Subsystem 10: Surrogate Key Generator:** Instead of classic Sequences or IDENTITY columns—which are notoriously difficult to maintain in distributed systems—we use deterministic hashing (e.g., `md5(natural_key || '_' || row_effective_date::varchar)`). This keeps the pipeline idempotent and restartable at any time.
*   **Subsystem 12: Special Dimensions Manager:** Junk Dimensions are handled in the `fct_client_bike_rent` fact table using the `dbt_utils.generate_surrogate_key` macro over low-cardinality flags (bike/helmet damage).
*   **Subsystem 13: Fact Table Builders:** Implemented via SQL queries in dbt. A prime example is the `fct_client_bike_rent` accumulating snapshot, which extracts data from 3 different staging tables (booking, dispense, return) and stitches them together via `LEFT JOIN`, simultaneously executing a Point-in-Time Lookup for SCD2 keys (to tie the rental to the employee profile version active *at the time of the event*).
*   **Subsystem 19: Aggregate Builder:** Offloaded to a dedicated Aggregation Marts layer in dbt (Customer 360, Fleet Utilization, etc.) to pre-calculate heavy metrics for Tableau dashboards.

---

## 4. Managing the ETL Environment
*Covers Subsystems 22–34 (Scheduler, Recovery, Monitoring, Parallelism, Security)*

The pipeline management environment is mission-critical for reliability (Observability & Orchestration).

*   **Subsystem 22: Job Scheduler:** Implemented using Apache Airflow. The `elt_pipeline_s3_to_dwh` DAG orchestrates the entire process every 15 minutes, controlling execution order (Extract -> Branching -> dbt Run -> Audit Upload).
*   **Subsystem 24: Recovery and Restart System:** The pipeline is designed to be fully restartable in the event of a crash. Loading into PostgreSQL is idempotent (`ON CONFLICT DO NOTHING`), and dbt can execute a `--full-refresh` at any time, dropping and recalculating the entire warehouse from scratch based on the raw data in the Data Lake.
*   **Subsystem 27: Workflow Monitor & Subsystem 30: Problem Escalation System:** A combination of built-in dbt Data Quality Tests and Grafana. Test results are extracted by our custom parser and visualized on a dashboard. In a real-world scenario, Grafana alerts trigger webhooks (e.g., to Slack or Telegram) to escalate incidents to engineers.
*   **Subsystem 25: Version Control System:** All dbt project code (SQL queries, tests, YAML contract definitions), generator code, and infrastructure configurations (Docker) are tracked in Git, cementing Infrastructure as Code (IaC) and Analytics as Code (AaC) practices.

---

## Summary
Using modern tools like dbt, Airflow, and Kafka allows us to "package" Kimball's 34 classic ETL subsystems into elegant, readable code. We haven't skipped a single key stage: extraction is crash-proof (Kafka + S3), cleaning is guaranteed by data contracts (Staging), history is preserved deterministically (SCD2 + MD5), and orchestration and data quality monitoring are transparent (Airflow + Grafana).

This architecture scales effortlessly from a local pet project to a HighLoad enterprise data warehouse.