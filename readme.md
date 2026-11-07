# What is this project all about?

This project is an open sandbox designed to clearly demonstrate what the implementation process of a full data pipeline would look like in a small but fast-growing startup. Within this project, we assume that our fictional business has absolutely no "ETL kitchen" for data integration, which means we have to walk the entire path from collecting raw events from a client app to building ready-made aggregated data marts and analytics dashboards. In doing so, we will adhere to core industry standards, and as our key philosophical paradigm, we will rely on the following great quote:

 - There is no reason to tolerate an unstructured approach. 

Indeed, any complex task requires careful planning and preparation, which is exactly what we will try to emphasize in this project.

So, let's assume we are dealing with a growing startup called Top Bikes, which provides bike (scooter) rental services in Bangkok, and also operates a chain of accessory and motorcycle spare parts shops. Our task is to create a reliable and scalable system capable of collecting and analyzing raw data, ultimately transforming it into a full-fledged business strategy. As our starting point, we have a hypothetical mobile app for clients and other master systems generating data on shop receipts, goods procurement, and more.

![](docs/images/adv_350.png)

# Planning and Strategy

To avoid drowning in a sea of tools and losing sight of the final deliverable, we need a clear plan for executing such a massive task. And this plan will, one way or another, align with the following framework (Kimball Lifecycle diagram):

![](docs/images/Kimball_Lifecycle_diagram.jpeg)

Next, we will move step-by-step through each block of the diagram, diving deep into every stage. You could say this schema represents the very first, high-level decomposition of integrating a data project into a company. 

## Documentation Structure (Kimball Lifecycle)

The project documentation is structured strictly in accordance with the Kimball Lifecycle shown above and is divided into 6 logical blocks:

* **[01. Business Requirements & Planning](https://github.com/letConst55/data-pet-project/tree/main/docs/01_Business_Requirements_and_Planning)**
  Description of the bike rental startup's business model, stakeholder interviews, and target KPI definition.
* **[02. Technical Architecture](https://github.com/letConst55/data-pet-project/tree/main/docs/02_Technical_Architecture)**
  Justification of the tech stack choice (Redpanda, MinIO, PostgreSQL, dbt, Airflow) and an overview of the raw event generator emulator.
* **[03. Dimensional Modeling](https://github.com/letConst55/data-pet-project/tree/main/docs/03_Dimensional_Modeling)**
  Enterprise Data Warehouse Bus Matrix, logical model design (Star Schema), and physical deployment strategy.
* **[04. ETL Kitchen & Data Quality](https://github.com/letConst55/data-pet-project/tree/main/docs/04_ETL_Kitchen)**
  Implementation of ELT pipelines (Kafka -> S3 -> PostgreSQL -> dbt), mapping to Kimball's 34 subsystems, and a built-in data quality testing framework with audit logs pushed to Grafana.
* **[05. BI Applications](https://github.com/letConst55/data-pet-project/tree/main/docs/05_BI_Applications)**
  Design of the pre-calculated aggregation layer and specifications for analytical dashboards (Customer Intelligence, Fleet Utilization).
* **[06. Deployment & Operations](https://github.com/letConst55/data-pet-project/tree/main/docs/06_Deployment_and_Operations)**
  Orchestration of ELT processes via Apache Airflow and Bash automation scripts for infrastructure lifecycle management (start/stop pipeline).


### *Service Access*

- To start everything up:

`./start_pipeline.sh`

- Once the history is loaded, you can stop the background processes:

`./freeze_dwh.sh`

- To shut everything down:

`./stop_pipeline.sh`

MinIO Admin credentials (http://localhost:9001/):

 - login: minioadmin
 - password: miniopassword

Airflow (http://localhost:8080/):

 - login: admin
 - password: 1234

Grafana (http://localhost:3000/):

 - login: admin
 - password: 1234