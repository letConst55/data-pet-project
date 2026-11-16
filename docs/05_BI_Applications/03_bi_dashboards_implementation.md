# BI Dashboards Implementation: Tableau & Streamlit

## Introduction
Following the architectural principles outlined in `01_bi_design.md` and the data mart specifications in `02_aggregation_layer.md`, the presentation layer of the **Top Bikes Bangkok** DWH is intentionally split across two distinct BI paradigms:
1.  **Traditional Enterprise BI (Tableau):** Powers the **Customer Intelligence** domain, focusing on executive macro-trends, client segmentation, and North Star quality monitoring.
2.  **BI-as-Code Web Application (Streamlit + Plotly):** Powers the **Asset, Operations & Commercial** domain, providing an interactive Python-driven analytical portal with live PostgreSQL connectivity and standalone HTML report generation.

Combining these two tools in a single project demonstrates architectural versatility—showing how a well-modeled Kimball DWH (`core` + `aggregations` schemas in dbt) serves as a universal semantic foundation for both industry-standard GUI tools and modern code-first data applications.

---

## Part 1: Customer Intelligence Dashboard (Tableau)

🔗 **Live Interactive Dashboard:** [Top Bikes Startup Dashboard on Tableau Public](https://public.tableau.com/app/profile/konstantin3546/viz/Topbikesstartupdashboard/Overview)

### 1.1 Why Tableau? (Local Sandbox vs. Commercial Production)

*   **Efficiency in a Local Pet Project:** 
    During local development, Tableau Public / Desktop enables rapid visual prototyping and effortless ingestion of pre-computed dbt marts (`agg_monthly_client_kpis`, `agg_monthly_client_segments`, and `stats_by_clients`). Because all complex non-additive logic—such as cumulative LTV, dynamic monthly RFM segmentation, rider profiling, and the Trouble-Free Ratio—is pre-calculated in SQL via dbt, Tableau operates on lightweight, highly compressed datasets. This completely eliminates client-side calculation bottlenecks and allows multi-chart views to render instantaneously.
*   **Readiness for Enterprise Production:** 
    In a commercial production environment, Tableau is a gold-standard Enterprise BI platform powered by its proprietary VizQL engine. As the startup scales and migrates its storage from local PostgreSQL to cloud MPP warehouses (Snowflake, BigQuery, or Amazon Redshift), the exact same Tableau workbook can be seamlessly repointed to live cloud connections or scheduled Hyper extracts on Tableau Server / Tableau Cloud. Furthermore, Tableau provides native enterprise governance, including Row-Level Security (RLS), Role-Based Access Control (RBAC), and app-like multi-page navigation (`Navigation Objects`) that gives C-level executives a polished, zero-code analytical experience.

---

### 1.2 Dashboard Architecture & Visual Breakdown

The Tableau workbook is designed as an interactive multi-page web application with a custom left-hand navigation panel and is divided into three analytical views:

#### View 1: Top Bikes Overview (Executive Macro-Trends)
*   **Top-Level KPI Cards:** Displays current monthly performance across four headline indicators—**Revenue**, **Active Clients**, **Total Rentals**, and **Average LTV**—complete with Year-over-Year (`YoY %`) growth deltas.
*   **Dynamic Metric Switcher & Seasonal Time-Series Chart:** A parameter-driven line chart that allows users to toggle between 9 core business metrics on the fly (`Shop Revenue`, `Rental Revenue`, `Repair Revenue`, `Total Revenue`, `Count Active Clients`, `Count New Clients`, `Avg Client LTV`, `Count Total Rentals`, and `Cross-Sell Penetration`). The timeline is enriched with color-coded reference bands highlighting Bangkok's climate seasonality: **Storm / Monsoon Low Season** (red bands) and **Peak Tourist High Season** (green bands).
*   **Contextual Callout Cards:** Displays the active reporting month alongside a dynamically filtered **Top Beginner Bike Card** (`Honda Click 125i — Top choice for beginners`), derived from the `first_rent_bike` attribute in `stats_by_clients`.

#### View 2: Client Profiles (Demographics, Segmentation & Usage)
*   **Interactive Slicers:** Equipped with `Year` (`2024–2026`) and `Month` filters, plus a dynamic **Profile Switcher** that flips the entire dashboard view between `Rider Profile` and `RFM Loyalty Segment`.
*   **Rental Mileage Distribution (Box-and-Whisker Plot):** Evaluates trip mileage distributions across rider segments (`Beginner`, `City_rider`, `Pro_rider`, `Traveller_rider`) as a direct proxy for physical equipment wear. The plot clearly demonstrates that `Pro_rider` clients log substantially higher median and upper-quartile mileage per month compared to urban commuters (`City_rider`).
*   **Client Base Composition (Pie Chart):** Shows the proportional split of active customers, revealing that long-distance tourists (`Traveller_rider`, ~45%) and experienced enthusiasts (`Pro_rider`, ~25%) form the core of the active base, while ~11% of clients interact exclusively with the retail shop or workshop (`Shop_or_Garage_Only`).
*   **Geographic Value & Volume (Packed Bubble Chart):** Maps client nationalities (`German`, `American`, `Russian`, `Thai`, `British`, `French`), where bubble size represents average historical `LTV` and color intensity indicates rental frequency (`Cnt Rentals`).

#### View 3: North Star Intro & Revenue Distribution
*   **LTV vs. Driving Experience (Jittered Strip Plot):** Plots individual customer records with cumulative `Lifetime Total Amount` on the Y-axis against `Driving Experience Years` (`0–15 years`) on the X-axis, colored by `Rider Profile`. It highlights that while the highest concentration of customers has `0–4 years` of riding experience, high-LTV clients are distributed across all experience tiers.
*   **Trouble-Free Ratio by Segment (Horizontal Bar Chart):** Tracks our primary Customer Intelligence **North Star Metric**—the percentage of rentals completed without mechanic road dispatches or helmet damage—benchmarked against the company-wide average (`48.9%`). The chart validates a critical operational hypothesis: experienced segments (`Pro_rider` at `64.0%`, `Traveller_rider` at `56.1%`, and `City_rider` at `51.2%`) perform well above average, whereas `Beginner` riders drop to `26.9%`, generating the bulk of road incidents.
*   **Revenue by Department (100% Stacked Bar Chart):** Illustrates the revenue mix (`Rental` vs. `Shop` vs. `Repair`) across RFM loyalty cohorts. It confirms that bike rental is the primary acquisition touchpoint for `new_customer` (`51.7%` rental share), while `loyal_customer` and `vip_customer` cohorts spend nearly as much in the retail shop (`44.5%–48.1%`) as they do on rentals. Meanwhile, the `shop_only_customer` segment generates `72.8%` of its revenue in retail gear and `27.2%` in external workshop repairs.

---

### 1.3 Key Business Questions Answered by the Tableau Dashboard
1.  **Seasonality & Anomaly Impact:** How severely do tropical monsoon storms in Bangkok depress rental bookings, and how steeply do revenue and new client acquisition rebound during the November–February high season?
2.  **Fleet Acquisition for Novices:** Which specific scooter model serves as the #1 entry point for first-time riders (`Beginner`), and how should procurement prioritize this model ahead of tourist peaks?
3.  **Risk & Deposit Policy:** Which customer segments subject the fleet to the heaviest mileage wear and lowest Trouble-Free Ratio, justifying tiered security deposits or mandatory pre-ride safety briefings?
4.  **Cross-Department Monetization:** Are we successfully converting single-service rental tourists into multi-department VIP clients who purchase helmets, accessories, and tuning services in our retail stores?

---

## Part 2: Operations & Commercial Web Application (Streamlit + Plotly)

🔗 **Application Source Code:** [`streamlit/` Directory in GitHub Repository](https://github.com/letConst55/data-pet-project/tree/main/streamlit)

### 2.1 Why Streamlit? Advantages & Core Architectural Principles

To complement Tableau and showcase a modern **BI-as-Code** workflow, the second major analytical domain—**Asset, Operations & Commercial Management**—is implemented as a standalone web application using **Streamlit** and **Plotly** (`streamlit/app.py`).

#### Key Technical Advantages:
*   **100% Code-Driven & Git Versioned (`BI-as-Code`):** Unlike binary BI files, the entire dashboard—from SQL data fetching to layout grids and visual styling—is written in pure Python. Changes to charts are tracked via standard Git commits and pull requests alongside dbt models and Airflow DAGs.
*   **Live PostgreSQL Connectivity & Dynamic Schema Resolution:** Running locally on port `8501` (alongside Airflow on `8080` and Grafana on `3000`), the app connects directly to the `pet_dwh` PostgreSQL container via `psycopg2`. It features a left-hand **Database Connection Sidebar** where users can input credentials and run a live health check (`Test Connection`) with instant visual feedback. Helper functions automatically resolve target schemas (`core` vs. `aggregations`) via `information_schema.tables` and cache query results using `@st.cache_data`.
*   **Progressive On-Demand Rendering (`st.session_state`):** When the application first opens, the canvas remains clean to prevent overwhelming the user and avoid unnecessary database queries. Visualization sections are divided into 6 modular blocks, each unlocked sequentially via dedicated `Show plots` buttons backed by persistent `st.session_state` flags.
*   **Interactive Plotly Engine & Standalone HTML Report Exporter:** All charts are built with `Plotly` (`plotly.graph_objects`), offering rich hover tooltips, zoom/pan controls, dual Y-axes, and custom event overlays. Crucially, the top-right header features a **📥 Download HTML** button that dynamically compiles all currently expanded KPI cards and interactive Plotly charts (`include_plotlyjs='cdn'`) into a single, self-contained `.html` file. Business users can email or message this file to stakeholders, who can open it in any browser offline with full chart interactivity preserved.

---

### 2.2 Implemented Visualization Blocks & Analytical Insights

*(Note: To prevent incomplete current-month data from distorting time-series trends at the edge of the simulation, the app automatically filters out the open month via `max_complete_month = max(report_month) - 1 month`).*

#### Block 1: Business Scale & Asset KPIs (Summary Cards)
Queries live reference tables (`dim_location`, `dim_employee`, `dim_product`) and `agg_monthly_ops_kpis` to establish the physical scale of the business:
*   **📍 Total Business Locations:** `10` facilities (retail shops, workshops/garages, and rental hubs).
*   **🛵 Fleet Size & Active Share:** `55 bikes` total (`100.0%` active in operation during the latest closed month, with an average historical time utilization rate of `43.3%`).
*   **👥 Active Employees (excl. CEO):** `127` active operational staff members (`current_row_indicator = true AND is_active_flg = true` in the SCD2 employee dimension).
*   **📦 Unique Catalog Items:** `85 SKUs` (`81` physical retail/spare part goods and `4` tuning services).

#### Block 2: Fleet Utilization & Field Service Dynamics
Built on `agg_monthly_ops_kpis` with color-coded vertical bands marking **🌊 Monsoon Floods** (Sep 2024, Oct 2025) and **🚢 Supply Chain Crises** (Feb–Mar 2025, Jun 2026):
1.  **North Star: Fleet Utilization Rate (%):** Tracks the share of total available bike-days spent in active rental. Shows a strong upward trajectory driven by organic startup growth (climbing from `~10%` in early 2024 to `85–90%` during peak periods, averaging `43.3%`), with sharp temporary drops during tropical floods.
2.  **Breakdown Intensity (/1k km) & Field Service Cost ($):** A dual-axis chart combining mechanic road dispatches per 1,000 km (line) with monthly field service expenses in USD (bars). **Insight:** During monsoon flood months, breakdown intensity spikes dramatically (up to `~7.8 dispatches per 1,000 km`), driving heavy emergency towing and on-road repair costs.

#### Block 3: Supply Chain Lead Time & Inventory Efficiency
1.  **Pipeline Duration: Procurement & Repair Lead Time (days):** Compares vendor delivery duration (`avg_procurement_lead_time_days`) against external client repair turnaround (`avg_repair_total_lead_time_days`). **Insight:** During port logistics crises (orange bands), vendor procurement lead time jumps from a baseline of `~6–8 days` to **`19 days`**, which directly starves the workshop of spare parts and forces external repair lead times to spike from `~5 days` up to **`9–12 days`**.
2.  **Inventory Turnover (%) vs. Out-of-Stock Rate (%):** Tracks monthly inventory velocity against stockout frequency. **Insight:** Turnover surges during high-demand and post-storm repair peaks (reaching `~2.3%`), while high initial safety stock buffers across locations keep the global `Out-of-Stock Rate` at `0.0%`—indicating an opportunity to lean out excess working capital.

#### Block 4: Fleet ROI by Class & Technical Condition Evolution
Built on `agg_monthly_fleet_utilization` and `stats_by_bikes`:
1.  **Average Lifetime ROI by Bike Class:** Compares cumulative net operating income against bike acquisition cost across classes against a `100% Break-Even Threshold`. **Insight:** By late 2026, all three classes are highly profitable, led by **`city bike` (`429% ROI`)**, followed by **`offroad` (`237% ROI`)** and **`touring` (`157% ROI`)**.
2.  **Fleet Technical Condition Evolution (SCD4 Condition):** A 100% Stacked Area chart tracking the distribution of the 55-bike fleet across four health tiers (`Optimal Score 8-10`, `Standard Wear Score 5-7`, `Needs Overhaul Score 3-4`, and `Critical / Decommission Risk Score 1-2`). **Insight:** Demonstrates the natural aging curve of physical assets over 2.5 years of intensive rental usage—without major fleet renewal, bikes progressively migrate from green/yellow tiers into orange (`Needs Overhaul`) and red (`Critical`) zones.

#### Block 5: Bottleneck Anatomy in Repairs & Procurements
Built on `agg_monthly_supply_and_repairs`:
1.  **Repair Lead Time Breakdown by Month (Stacked Bar, days):** Decomposes the end-to-end external repair cycle (`fct_repair`) into three physical stages: `1. Inbound Transport (to Garage)`, `2. Active Workshop Repair`, and `3. Outbound Transport (to Shop)`. **Insight:** Internal pickup truck logistics (Inbound and Outbound transport) remain rock-solid at `~0.2–0.8 days` regardless of season. The entire delay during logistics crises occurs inside **Stage 2: Active Workshop Repair**, proving that spare parts waiting time in the garage is the true operational bottleneck.
2.  **Procurement Lead Time by Location (Vendor vs. Carrier, days):** A horizontal stacked bar chart comparing `Vendor Processing` (`~1.7–2.2 days`) and `Carrier Transit` (`~4.5–5.0 days`) across all 6 retail and warehouse locations, showing balanced logistics performance across the Bangkok network.

#### Block 6: Subcategory Turnover & Bike Model Efficiency Matrix
Built on `stats_by_inventory` and `stats_by_bikes`:
1.  **Avg Monthly Inventory Turnover by Product Subcategory:** Ranks all 19 `level2_category` groups by monthly turnover percentage and total units sold (`pcs`). **Insight:** High-frequency maintenance consumables and rider gear—such as `Protection & Accessories` (`0.9%`, 147 pcs), `Motor oils` (`0.7%`, 181 pcs), `Helmets & Visors` (`0.7%`, 197 pcs), and `Tires & Tubes` (`0.7%`, 150 pcs)—lead warehouse velocity, whereas `Consumables` and `Suspension & Steering` move slowest.
2.  **Model Efficiency Matrix — Repair Cost vs. Purchase Price (Bubble Chart):** Aggregates the 55 bikes to the **Bike Model (`bike_title`)** level, plotting **Avg Cumulative Repair Cost per Bike ($)** on the X-axis, **Bike Procurement Price ($ USD)** on the Y-axis, **Avg Monthly Rental Revenue per Bike ($/mo)** as bubble size, and **Bike Class** as color, divided into four quadrants by mean reference lines. **Insight:** Models located in the **top-right quadrant with smaller bubbles** (high acquisition cost, heavy cumulative repair expenses, and lower monthly revenue relative to capital—such as `Royal Enfield Classic 350` or `Honda Forza 350`) are immediately flagged as underperforming capital investments compared to affordable, low-maintenance workhorses in the bottom-left/center (`Honda Click 125i`, `Honda Wave 110i`, `Yamaha NMAX 155`).

---

### 2.3 Business User Scenarios (How Stakeholders Use the App)

*   **Scenario 1: Fleet CapEx & Decommissioning Review (COO / Head of Rentals)**
    *   *Workflow:* The Head of Rentals opens **Block 4** and **Block 6 (Bubble Matrix)**. Seeing that over 80% of the existing fleet has entered the `Critical` / `Needs Overhaul` tiers after 2.5 years of operation, they use the Bubble Matrix to plan the next procurement batch. They decide to decommission maintenance-heavy models in the top-right quadrant and reallocate capital toward `city bike` models (`Yamaha NMAX 155`, `Honda Click 125i`) that deliver a `429% ROI`.
*   **Scenario 2: Workshop SLA & Crisis Mitigation (Head of Maintenance / Chief Mechanic)**
    *   *Workflow:* When customer complaints rise regarding slow external bike repairs, the Chief Mechanic inspects **Block 3** and **Block 5**. By correlating the repair duration spike with the **Supply Chain Crisis** band and isolating **Active Workshop Repair** as the bottleneck stage, they prove that mechanics are not working slowly—rather, bikes are sitting disassembled waiting for delayed carrier shipments. They use this evidence to increase safety stock for top-moving repair parts before peak seasons.
*   **Scenario 3: Assortment & Working Capital Optimization (Retail & Procurement Manager)**
    *   *Workflow:* Reviewing **Block 3 (Out-of-Stock Rate at 0%)** alongside **Block 6 (Subcategory Turnover)**, the Retail Manager identifies that warehouse stock levels are overly conservative. They reduce reorder quantities for slow-moving subcategories (`Plastics & Body parts`, `Gloves`) while prioritizing shelf space and vendor SLAs for high-velocity items (`Motor oils`, `Helmets & Visors`, `Mirrors & Styling`).
*   **Scenario 4: Offline Board & Investor Reporting (Executive Team)**
    *   *Workflow:* Before a monthly strategy meeting, an analyst expands all 6 visualization blocks and clicks **📥 Download HTML**. The resulting standalone `.html` report is shared in the executive chat, allowing founders to interactively inspect every Plotly chart, zoom into crisis periods, and hover over individual bike models on their laptops or tablets without needing local DWH access.


### **[Check examples](https://github.com/letConst55/data-pet-project/blob/main/streamlit/dashboard_examples.md)**