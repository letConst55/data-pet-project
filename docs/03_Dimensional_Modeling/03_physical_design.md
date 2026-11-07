# Physical Design & Update Strategy

## Introduction
This document outlines the physical implementation of our data warehouse. If the logical model (Bus Matrix and schema designs) answers the question *"What are we measuring?"*, the physical design answers the question *"How is data physically moved, stored, and updated?"*.

Below is a detailed breakdown of our end-to-end Data Supply Chain and pipeline orchestration strategy, tailored to the specific nature of our project's current implementation phase.

---

## 1. Data Supply Chain

Data movement is orchestrated following the classic ELT (Extract, Load, Transform) paradigm, where heavy transformations are executed directly inside the analytical database using dbt.

The pipeline consists of the following sequential stages:

1.  **Data Generator (Source):** The core business simulation engine written in Python. It generates purchase, rental, inventory movement, and repair transactions while holding state (fleet and warehouse conditions) in memory. It emits events in JSON format and routes them to the message broker.
2.  **Kafka (Redpanda):** The streaming layer. It buffers incoming event streams and routes them to dedicated topics (`client_app_events`, `shop_app_events`, `inventory_events`, etc.). It ensures fault tolerance during traffic spikes.
3.  **S3 (MinIO) - Data Lake:** The Raw data layer. A consumer reads topics from Kafka and writes them in micro-batches to object storage buckets in NDJSON format. Data is partitioned by date and topic (e.g., `events/shop_app_events/date=YYYY-MM-DD/`).
4.  **PostgreSQL ODS (Operational Data Store):** The DWH Bronze layer. A Python script fetches files from S3 and loads them into `ods_events` tables. Data is stored semi-structured: a unique key, event type, timestamp, and a `payload` in `JSONB` format. This shields the warehouse from breaking when upstream event schemas change.
5.  **PostgreSQL Staging Views:** The Silver layer. Implemented via views in dbt. Here, the `JSONB` payloads are unpacked into flat relational columns with strict type casting. This layer acts as a "data contract," filtering out garbage and preparing the data for dimensional modeling.
6.  **PostgreSQL Core (Logical Data Model):** The Gold layer. The physical manifestation of the Kimball logical model (facts and dimensions outlined in `02_logical_data_model.md`). Implemented as physical tables (SCD Type 2 dimensions, transactional and accumulating facts) built by dbt models.
7.  **PostgreSQL Aggregation Marts:** The Aggregation layer. Pre-calculated data marts for specific business domains (e.g., weekly fleet utilization, daily retail sales, ABC analysis). Built to reduce compute load on BI tools when rendering heavy dashboards. In this architecture, ready-to-use aggregate marts serve as one of the most effective DWH optimization techniques.
8.  **Tableau (BI Dashboards):** The visualization and data delivery layer for business users. Tableau connects directly to the Core and Aggregation layers to render analytical dashboards (Customer 360, Asset Management, Retail Performance).

---

## 2. Update Strategy

### Production Scenario (T-1 Batch Processing)
In real-world enterprise data warehouses, the classic approach is to load and recalculate data in a **T-1 (Batch Processing)** mode. This means pipelines run once every 24 hours (typically overnight), ingesting the delta of changes from the previous day. This approach conserves compute resources, reduces stress on source systems, and guarantees that business users receive a locked, immutable data snapshot at the start of their workday. (Note that two other common strategies exist: Intra-Day, updating several times a day, and Instantaneous, near real-time updates with minimal latency).

### Current Project Implementation (15-Minute Micro-Batches)
To facilitate rapid development, debugging, and fast feedback loops, we consciously bypassed the classic T-1 approach in favor of a highly accelerated pipeline cadence for this project. The entire process is orchestrated by a single Apache Airflow DAG (`elt_pipeline_s3_to_dwh`), which is scheduled to run **every 15 minutes** (`schedule='*/15 * * * *'`).

Key features of this update strategy:
*   **Idempotent ODS Loading:** On every execution, the S3 load script deletes all events for the current date from the ODS tables and re-ingests them from scratch (utilizing `INSERT ... ON CONFLICT DO NOTHING`). This entirely prevents duplication during frequent restarts and eliminates state consistency headaches during local development.
*   **Smart dbt Mode Selection:** At the start of the run, the DAG evaluates the warehouse's data presence (e.g., by checking row counts in `core.dim_client`). If the database is empty, Airflow routes execution to the `run_dbt_full_refresh` branch (running `dbt build --full-refresh`). If data exists, it routes to the `run_dbt_incremental` branch (`dbt build`). Without this logic, incrementally materialized dbt models would never populate properly, because stopping the project currently truncates the entire Postgres warehouse across all layers.
*   **Audit Log Flush and Update:** At the end of every 15-minute cycle, the pipeline clears (`TRUNCATE`) legacy logs from the previous run (tests and models) and loads fresh dbt execution results into the `audit.dbt_test_results` and `audit.dbt_model_results` tables.

**Why take this approach?**
For a sandbox and demonstration project, frequent full recalculations of the current day strike the perfect balance. It alleviates the burden of tracking "dirty" states while generating test data, allows engineers to see the impact of dbt model code changes instantly (near real-time), and ensures consistently updated data quality logs are fed to the Grafana observability layer.