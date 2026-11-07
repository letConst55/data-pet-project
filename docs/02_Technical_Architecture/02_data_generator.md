# Data Generator Engine

## Introduction
This document describes the synthetic data generation suite, which acts as a comprehensive transactional (OLTP) system for our Bangkok bike rental startup. 

Since there is no real flow of client transactions during the DWH development and implementation phase, the generator takes on the role of a mission-critical source. It doesn't merely produce random rows; it emulates the full lifecycle of a multi-tiered business, strictly preserving state (fleet condition, warehouse inventory, and open rentals) and chronological consistency.

---

## 1. Generator Architecture and Components

The generator is written in Python and designed using modular microservice architecture principles. The core engine manages a virtual clock, distributes business process weights, and routes generated events to an abstract publisher layer.

### 1.1 Module Structure
*   `main.py` — The main simulation orchestrator. It controls the global time loop, dynamically recalculates transaction probability weights based on seasons and cataclysms, and governs the flow rate (historical vs. real-time mode).
*   `core/state.py` (SimulationState) — The state manager. It stores in RAM and serializes to JSON (`generator_state.json`) all up-to-date business information: incremental ID counters, the client registry, busy/free bikes, current mileage, inventory balances, and open repairs.
*   `core/publisher.py` (EventPublisher) — An abstract event publisher. It supports two operational modes: `kafka` (sending to Redpanda with UTF-8 JSON serialization) and `pandas` (local memory accumulation for CSV debugging exports).
*   `core/world_context.py` (WorldContext) — The world context engine. It implements the organic growth of the startup, Bangkok's climate seasonality (high, hot, and rainy seasons), and the schedule of "Black Swans" (floods, logistics crises, festivals, heatwaves).
*   **Business Domain API Modules (`modules/`):**
    *   `rent_api.py` — Manages clients (SCD2 profiles), bookings, and the dispense/return of bikes (accounting for continuous rental extensions).
    *   `garage_api.py` — Mechanic field services (`fct_service_events`) and the drop-off/pickup of personal client bikes for repair (`fct_repair`).
    *   `shop_api.py` — Retail sales of gear, accessories, and tuning services in stores (`fct_shop_order`).
    *   `hr_api.py` — HR operations: hiring, transfers, and employee terminations (`dim_employee`, SCD2).
    *   `inventory_api.py` — Inventory management, automatic procurement triggering when stock drops (`fct_procurement`), and weekly snapshots (`fct_inventory_snapshot`).

---

## 2. Key Engineering Features

### 2.1 Time Machine and Historical Simulation (Time Travel)
The generator supports two operational modes:
1.  **Historical Mode (`HIST`):** Upon startup, the system sets a virtual starting point (March 1, 2024). On every tick, the `advance_time()` method shifts the clock forward by 1–10 hours (the step dynamically compresses during peak seasons and stretches during storms). This makes it possible to generate over two years of transaction history in just a few minutes.
2.  **Real-Time Mode (`LIVE`):** Once the virtual clock catches up to the server's system time, the simulator switches to real-time mode, emitting events at intervals of 2 to 5 seconds.

### 2.2 Seasonality and "Black Swan" Simulation
To imitate real business behavior, the `WorldContext` calculates an overall traffic intensity coefficient (`total_traffic_mult`) at each step, comprising three components:
*   **Organic Growth:** A smooth company growth trend, scaling from `0.65x` at launch to `1.75x` by the end of 2026.
*   **Climate Seasonality:** Accounts for Bangkok's tourist season (November–February drives traffic up, while the June–October rainy season reduces ride activity).
*   **Cataclysms and Promos:** A deterministic schedule of anomalies. For example, during the Songkran festival (April), demand for bike rentals and protective gear skyrockets, whereas during tropical storms (`monsoon_flood`), bookings plummet while emergency mechanic dispatches and repairs surge.

### 2.3 Integrity Control and Fault Tolerance
*   **Incremental IDs and State:** All entities (clients, rentals, orders, procurements) receive unique incremental identifiers. Saving a snapshot to `generator_state.json` guarantees that if the system restarts, the bike fleet and accumulated mileage are not lost.
*   **Employee Role-Based Access Controls:** Modules verify the operational permissions of the staff (e.g., checking for the `can_sell_retail_flg` flag for cashiers or `can_field_service_flg` for mobile mechanics) before generating transactions, ensuring 100% consistency with the dbt fact tables.