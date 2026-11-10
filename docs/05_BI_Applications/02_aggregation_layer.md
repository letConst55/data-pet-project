# Aggregation Layer Models

This document provides technical documentation for the data marts residing in the `aggregations` schema. The aggregations are implemented according to the "Sandbox" (exploratory) and "Reporting" (highly aggregated) paradigms, and are divided into distinct business domains.

---

## Domain 1: Customer Intelligence

### 1. stats_by_clients (Sandbox Mart)
The foundational data mart for the customer analytics domain. Granularity: `Reporting Month + Client`. It acts as a comprehensive "Customer 360" view, retaining a record for each client for every month since their first interaction. It contains Month-to-Date (MTD) usage, cumulative Lifetime Value (LTV), and dynamically computed segmentation.

| Column Name | Data Type | Description |
| :--- | :--- | :--- |
| `report_month` | `date` | Reporting month (the 1st day of the month) |
| `client_natural_key` | `text` | Client natural key |
| `drive_license_verified` | `boolean` | Flag indicating a valid/verified license |
| `driving_experience_years` | `int` | Years of driving experience |
| `gender` / `nationality` | `text` | Client demographic attributes |
| `rating_score` | `int` | Internal client rating score |
| `first_rent_bike` / `first_rent_dis_location` | `text` | First rented bike model and dispense location (or 'never rent') |
| `mtd_rentals` / `mtd_successful_rentals` | `int` | Count of total and trouble-free rentals in the current month |
| `mtd_rental_amount` / `mtd_shop_amount` / `mtd_repair_amount` | `numeric` | Revenue generated across departments within the month |
| `mtd_sum_rental_mileage` | `int` | Total mileage driven by the client in the month |
| `lifetime_rentals` | `int` | Cumulative count of rentals since the client's first touchpoint |
| `lifetime_total_amount` | `numeric` | Cumulative Lifetime Value (LTV) across all departments |
| `trouble_free_days_ratio` | `numeric` | Ratio of trouble-free rental days across the client's entire history |
| `loyalty_segment_at_month` | `text` | Loyalty segment (new_customer, loyal_customer, vip_customer, danger_customer) |
| `rider_profile_segment_at_month` | `text` | Rider profile (Beginner, City_rider, Traveller_rider, Pro_rider) |

### 2. agg_monthly_client_kpis (Reporting Mart)
A highly aggregated data mart tailored for high-level Executive Dashboards. Granularity: `Reporting Month`. This mart filters for clients active during the given month and calculates complex macro-indicators and financial totals.

| Column Name | Data Type | Description |
| :--- | :--- | :--- |
| `report_month` | `date` | Reporting month |
| `cnt_total_clients` | `int` | Total count of unique active clients in the month |
| `cnt_new_clients` | `int` | Count of newly acquired clients in the month |
| `sum_rental_amount` / `sum_shop_amount` / `sum_repair_amount` | `numeric` | Revenue broken down by department |
| `sum_total_amount` | `numeric` | Total combined monthly revenue |
| `avg_client_ltv` | `numeric` | Average historical LTV among active clients |
| `trouble_free_ratio` | `numeric` | North Star Metric: The ratio of trouble-free rentals strictly within this month |
| `cross_sell_penetration_rate` | `numeric` | The ratio of active renters who also made a shop purchase or repair order |

### 3. agg_monthly_client_segments (Reporting Mart)
A data mart specifically engineered to power structure and mix charts (e.g., 100% Stacked Bar Charts) in Tableau. Granularity: `Month + Rider Profile + Loyalty Segment + Nationality`.

| Column Name | Data Type | Description |
| :--- | :--- | :--- |
| `report_month` | `date` | Reporting month |
| `rider_profile_segment_at_month` | `text` | Sliced by rider profile |
| `loyalty_segment_at_month` | `text` | Sliced by loyalty status |
| `nationality` | `text` | Sliced by nationality |
| `cnt_total_clients_segments` | `int` | Segment size (count of unique clients) |
| `sum_total_amount_segments` | `numeric` | Total segment revenue (across all departments) |
| `avg_client_ltv_segments` | `numeric` | Average historical LTV for the segment |
| `trouble_free_ratio_segments` | `numeric` | The ratio of trouble-free rentals strictly within the specific segment |
| `avg_trip_mileage_segments` | `numeric` | Average trip mileage within the segment (a proxy for equipment wear) |

---

## Domain 2: Asset & Operations Management

### 4. stats_by_bikes (Sandbox Mart)
The foundational data mart for fleet tracking. Granularity: `Reporting Month + Bike`. Acts as a comprehensive asset ledger, containing usage statistics, technical condition scores, penalty amounts, and ROI for every individual bike in the fleet.

| Column Name | Data Type | Description |
| :--- | :--- | :--- |
| `report_month` | `date` | Reporting month (the 1st day of the month) |
| `bike_natural_key` | `int` | Unique bike identifier |
| `bike_title` / `brand` / `bike_type` | `text` | Bike physical attributes and class |
| `procurement_price` | `numeric` | Bike purchase cost (basis for ROI) |
| `mtd_rented_days` / `mtd_idle_days` | `int` | Count of days the bike was actively rented vs sitting idle |
| `utilization_rate` | `numeric` | Monthly utilization percentage (`mtd_rented_days` / `days_in_month`) |
| `mtd_rental_revenue` / `mtd_service_cost_usd` | `numeric` | Monthly revenue generated minus field service costs |
| `mtd_net_operating_income` | `numeric` | Net income generated by the bike in the month |
| `lifetime_mileage_ridden` | `numeric` | Cumulative mileage driven |
| `end_of_month_condition_score` | `int` | Technical condition score at the end of the month (1-10) |
| `lifetime_roi_ratio` | `numeric` | Cumulative ROI based on historical net income vs procurement price |
| `fleet_health_status` | `text` | Qualitative operational status based on the condition score |

### 5. stats_by_inventory (Sandbox Mart)
The foundational data mart for warehouse and retail inventory tracking. Granularity: `Reporting Month + Product + Location`. It tracks inbound shipments (procurement), stock holding levels, outbound sales, and lead time metrics per SKU.

| Column Name | Data Type | Description |
| :--- | :--- | :--- |
| `report_month` | `date` | Reporting month |
| `product_natural_key` / `product_title` | `text` | SKU identifier and name |
| `location_title` | `text` | Physical location (shop or garage) holding the stock |
| `avg_stock_qty` | `numeric` | Average quantity of the SKU held in stock during the month |
| `out_of_stock_rate` | `numeric` | Ratio of weeks where the SKU was completely out of stock |
| `mtd_sold_qty` / `mtd_sales_revenue` | `int` / `numeric` | Total retail sales outflow for the month |
| `mtd_procured_qty` / `mtd_procurement_spend` | `int` / `numeric` | Total inbound units and spend via vendor procurement |
| `avg_procurement_lead_time_days` | `numeric` | Average time (days) from vendor order placement to actual delivery |
| `inventory_turnover_ratio` | `numeric` | Monthly inventory turnover (`mtd_sold_qty` / `avg_stock_qty`) |

### 6. agg_monthly_ops_kpis (Reporting Mart)
The top-level Operations Executive Dashboard mart. Granularity: `Reporting Month`. Consolidates the health of the physical business across the fleet, field services, warehouse inventory, and external repair workflows.

| Column Name | Data Type | Description |
| :--- | :--- | :--- |
| `report_month` | `date` | Reporting month |
| `total_fleet_bikes` / `active_bikes_cnt` | `int` | Total registered fleet size vs bikes actually rented this month |
| `fleet_utilization_rate` | `numeric` | Global fleet utilization rate for the month |
| `avg_fleet_condition_score` | `numeric` | Average technical health score of the entire fleet |
| `field_services_per_1000km` | `numeric` | Frequency of field dispatches normalized per 1,000 kilometers driven |
| `warehouse_out_of_stock_rate` | `numeric` | Global out-of-stock rate across all locations and SKUs |
| `avg_sku_turnover_ratio` | `numeric` | Average inventory turnover speed |
| `external_repair_revenue_usd` | `numeric` | Total revenue from fixing external client bikes |
| `avg_repair_total_lead_time_days` | `numeric` | Average end-to-end duration for external client repairs |

### 7. agg_monthly_fleet_utilization (Reporting Mart)
A reporting mart designed to analyze fleet performance strictly grouped by bike model and brand. Granularity: `Month + Brand + Bike Type + Model`. 

| Column Name | Data Type | Description |
| :--- | :--- | :--- |
| `report_month` | `date` | Reporting month |
| `brand` / `bike_type` / `bike_title` | `text` | Bike model attributes |
| `bikes_in_model_cnt` | `int` | Fleet size for this specific model |
| `model_utilization_rate` | `numeric` | Utilization percentage aggregated at the model level |
| `avg_condition_score` | `numeric` | Average technical condition for this model |
| `sum_field_services` | `int` | Total on-road breakdowns for this model |
| `avg_model_roi_ratio` | `numeric` | Average Return on Investment generated by this specific model |

### 8. agg_monthly_supply_and_repairs (Reporting Mart)
A reporting mart linking warehouse inventory efficiency with the external repair pipeline (identifying logistical bottlenecks). Granularity: `Month + Location`.

| Column Name | Data Type | Description |
| :--- | :--- | :--- |
| `report_month` | `date` | Reporting month |
| `location_title` | `text` | Name of the location |
| `avg_location_stock_qty` | `numeric` | Average physical stock volume at this specific location |
| `location_out_of_stock_rate` | `numeric` | Out-of-stock frequency at this location |
| `avg_location_turnover_ratio` | `numeric` | Inventory turnover speed at this location |
| `avg_procurement_lead_time_days` | `numeric` | Average vendor delivery duration to this location |
| `avg_inbound_transport_days` | `numeric` | Average time to move a client's broken bike from the shop to the garage |
| `avg_active_repair_days` | `numeric` | Bottleneck metric: Pure workshop repair time |
| `avg_total_repair_lead_time_days` | `numeric` | End-to-end pipeline duration for an external bike repair |