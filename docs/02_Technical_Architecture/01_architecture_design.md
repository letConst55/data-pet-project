# Data Architecture and Tech Stack Justification (Technical Architecture Design)

## Drafting the "Shopping List"

Choosing a tech stack for a data warehouse is comparable to going to the supermarket: if we go without a pre-planned shopping list based on actual needs, we risk buying flashy, expensive, but completely useless items while forgetting basics like bread and milk. 

In data engineering, architecture must be dictated by business requirements, data structure, and common sense, not by the hype surrounding new technologies. Our "shopping list" was curated based on the need to build a reliable, scalable, and fault-tolerant pipeline for a growing bike rental business. At this implementation stage, it requires a reasonable balance between Total Cost of Ownership (TCO) and headroom for future growth.

Below is the justification for our chosen stack, along with an analysis of the problems we would have faced with alternative solutions.

---

## 1. Message Broker: Redpanda (Kafka API)
For data streaming, we use Redpanda, which acts as the message broker for all business events (topics like `hr_app_events`, `client_app_events`, `shop_app_events`, etc.).

*   **Why this choice:** Redpanda is fully compatible with the Kafka API but is written in C++ and uses a thread-per-core streaming architecture. This ensures high performance without the need to deploy and maintain a JVM and ZooKeeper. It makes the infrastructure more lightweight and cheaper to maintain at the current implementation stage while preserving all enterprise patterns (partitioning, replication, delivery guarantees) for future scaling.
*   **Alternative - RabbitMQ:** RabbitMQ is a queue broker that, by default, deletes a message after it is consumed. For our analytics, the "Event Sourcing" pattern is critical: the event log must be immutable and capable of being replayed in case of a pipeline failure or a change in business logic.
*   **Alternative - Original Apache Kafka:** This would require significantly more infrastructure resources and DevOps engineering time to configure a Zookeeper/KRaft cluster, which is overkill for the product's current maturity stage.

## 2. Data Lake (Raw Layer): S3-compatible storage (MinIO / AWS S3)
Events from the broker topics are collected in micro-batches by a Python consumer and saved to the `raw-events` bucket in NDJSON format. The script supports an emergency buffer flush (`_emergency`) upon receiving system stop signals (`SIGTERM`/`SIGINT`), guaranteeing zero data loss.

*   **Why this choice:** Using S3 allows us to decouple storage from compute. Raw data lies immutable in an independent, low-cost layer. This enables us to rebuild the entire DWH from scratch at any time by replaying history, without putting any load on production systems or the message broker.
*   **Alternative - Direct write from Kafka to DWH:** During peak activity spikes (e.g., mass bike bookings during tourist season), direct writes would paralyze the analytical database with transaction locks. Furthermore, we would lose the "bronze" layer of raw files necessary for auditing.
*   **Alternative - HDFS (Hadoop):** HDFS is incredibly heavy, requires a complex cluster, and is completely unsuited for modern cloud architecture. S3 has become the de facto industry standard.

## 3. Database (DWH): PostgreSQL 15
We use PostgreSQL 15 as the unified storage engine for the ODS, Staging, and Core layers. The loading process (`s3_to_postgres.py`) reads files from S3 and idempotently loads them into the ODS layer using the `INSERT ... ON CONFLICT (event_id) DO NOTHING` statement.

*   **Why this choice:** PostgreSQL features native and highly performant support for the `JSONB` format. This gives us a Schemaless approach at the ODS level: if the business adds new attributes to the mobile app, the database won't crash due to a schema mismatch, and we won't have to execute an emergency `ALTER TABLE`. Additionally, a classic relational DB handles complex JOINs and UPDATEs exceptionally well, which is critical for implementing Accumulating Snapshots and Slowly Changing Dimensions (SCD strategies).
*   **Alternative - ClickHouse:** An excellent columnar database for logs, but it handles `UPDATE` and `DELETE` operations extremely poorly. Our Kimball model includes accumulating snapshots for pipelines (repairs, procurements) and SCD2 dimensions, which require pinpoint record updates. Doing this in ClickHouse would severely overcomplicate the project.
*   **Alternative - Snowflake or BigQuery:** Powerful Enterprise solutions, but their operational expenses (OPEX) can be unjustifiably high during the initial DWH formation phase. PostgreSQL gives us the flexibility to easily migrate to MPP systems in the future when data volumes genuinely demand distributed columnar storage.

## 4. Data Transformations: dbt (Data Build Tool)
We use dbt to transform raw JSON data from the ODS layer into relational models (Staging and Core).

*   **Why this choice:** dbt brings Software Engineering best practices into the SQL world: version control, the DRY (Don't Repeat Yourself) principle via Jinja macros, built-in modular tests for data quality, and auto-generated documentation (Lineage graphs). Effectively, dbt covers the vast majority of core data transformation procedures from the operational layer into a fully-fledged DWH data model, saving massive amounts of development and deployment time for new objects.
*   **Alternative - Airflow PostgresOperator / Stored Procedures:** If we wrote transformations directly within Airflow DAGs or inside the database, the logic would rapidly degrade into unreadable and untestable "spaghetti architecture." dbt clearly separates orchestration from transformation business logic.

## 5. Data Observability: Grafana + Custom Python Parser
To monitor the pipeline, we deployed Grafana, which connects directly to the audit layer in the DWH. A custom script (`upload_dbt_results.py`) parses dbt artifacts (`run_results.json`) and loads metrics (statuses, model execution times, test failures) into the `audit.dbt_test_results` and `audit.dbt_model_results` tables. Based on this data, we build a Grafana dashboard reflecting the results of each model run, while previous logs are overwritten to prevent bloating the audit schema.

*   **Why this choice:** We are building a completely transparent data quality control layer with no vendor lock-in. Integrating Grafana with dbt's built-in test results allows data engineers to view the "health" of the warehouse in real-time. This solution is scalable and easily customizable for new business rules.
*   **Alternative - Enterprise Data Observability services (Monte Carlo, etc.):** These tools are overkill at the startup stage and require a paid subscription. Our approach of parsing JSON dbt artifacts solves the quality monitoring task 100% while remaining entirely under the in-house team's control.