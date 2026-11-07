# Data Extraction & Load

## Introduction
This document describes the initial stages of our "ETL Kitchen" (in Kimball's architecture terms — Subsystem 3: Extract System). The process is divided into two independent steps, which allows us to decouple streaming data collection from batch loading into the analytical warehouse.

The goal of these stages is to reliably capture business events from source systems, preserve their original state (Raw Data), and transfer them to the Operational Data Store (ODS) layer for subsequent transformations.

---

## 1. Streaming and Data Lake Formation (Kafka -> S3)

**Implementation Script:** `consumer_s3.py`

The first stage is driven by a Kafka consumer, which acts as a bridge between the message broker (Redpanda/Kafka) and the Data Lake layer (S3 / MinIO). The consumer operates in a continuous streaming mode, ingesting generated business events.

### Data Scope
The script subscribes to a pool of core business topics covering all aspects of the startup's operations:
*   `client_app_events` (client actions, bookings, profile updates).
*   `shop_app_events` (retail purchases, tuning orders).
*   `mechanic_app_events` (field mechanic dispatches, repair statuses).
*   `hr_app_events` (personnel changes, grade promotions).
*   `inventory_events` (warehouse stock changes).

### Key Technical Features

*   **Micro-batching and Storage Format:** Events are not written to S3 one by one. The consumer accumulates them in memory and flushes them to object storage upon reaching a 50-record limit (`BATCH_SIZE = 50`). Data is saved in NDJSON (Newline Delimited JSON) format.
*   **Partitioning:** Files are distributed within the `raw-events` bucket following a strict hierarchy: `events/{topic_name}/date=YYYY-MM-DD/batch_{timestamp}.json`. This Hive-style partitioning allows for seamless future integration with tools like AWS Athena or Trino for direct SQL querying over the Data Lake.
*   **Fault Tolerance (Graceful Shutdown):** A key feature of the script is intercepting OS system signals (`SIGTERM` and `SIGINT`). If the container stops or the process is interrupted, the consumer isn't killed instantly; instead, it triggers the `flush_batch` function with the `is_emergency=True` flag. This guarantees zero data loss at batch boundaries: the remaining buffer is immediately flushed to S3 with an `_emergency` suffix in the filename. This shields the warehouse from "orphaned" events (e.g., when a bike return is saved, but its dispense event is lost in the RAM of a killed process).

---

## 2. ODS Layer Formation (S3 -> PostgreSQL)

**Implementation Script:** `s3_to_postgres.py`

The second step (Extract & Load) is orchestrated via Apache Airflow. The objective here is to fetch raw files from the S3 bucket for a target date and load them into a relational database (PostgreSQL), forming the Bronze Operational Data Store (ODS) layer.

### ODS Layer Architecture
An `ods_events` schema is created in PostgreSQL with dedicated tables for each topic (e.g., `ods_client_events`, `ods_shop_events`). 
These tables utilize a minimalist, semi-structured schema:
*   `event_id` (Primary Key) — Unique event identifier.
*   `event_type` — Event type (subsequently used in dbt for routing).
*   `event_timestamp` — Business timestamp of the event.
*   `payload` (`JSONB`) — The event body containing all attributes.
*   `loaded_at` — Technical timestamp of ingestion into the warehouse.

Using the binary `JSONB` format for the `payload` field allows the database to effortlessly digest any structural changes in incoming events (a Schemaless approach). If the data generator adds new fields, the table schema won't break, and the pipeline will continue running without requiring an emergency `ALTER TABLE`.

### Key Technical Features

*   **Data Lake Extraction:** The script scans S3 using the target date prefix (`date=YYYY-MM-DD`), downloads the files, reads the NDJSON line by line, and prepares tuples for database insertion.
*   **Idempotent Loading:** This is a mission-critical property of the pipeline, ensuring the load process can be restarted an infinite number of times without risking data duplication. It is implemented via a pre-cleaning pattern: before insertion, the script executes `DELETE FROM ods_events.{table_name} WHERE DATE(event_timestamp) = '{target_date}'`.
*   **Conflict Resolution (Upsert):** The array of events is inserted via the `execute_values` method utilizing the `INSERT ... ON CONFLICT (event_id) DO NOTHING` mechanism. If an event with the same ID already exists (e.g., arriving from an adjacent batch or duplicated at the source), it is ignored by the database at the Primary Key level, ensuring strict consistency in the ODS layer.

This strategy guarantees that raw data is completely and correctly overwritten in PostgreSQL for a given day, establishing a robust foundation for subsequent dbt transformations.