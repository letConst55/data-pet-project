# Aggregation Layer Models

This document provides technical documentation for the data marts residing in the `aggregations` schema. Currently, the first block is documented — **Customer Intelligence**, implemented according to the previously outlined "Sandbox" and "Reporting" paradigms.

## 1. stats_by_clients (Sandbox Mart)
The foundational data mart for the customer analytics domain. Granularity: `Reporting Month + Client` (every client has a record for every month, starting from their first activity). This is the optimal source for ad-hoc analytics in Tableau, as it contains both Month-to-Date (MTD) and cumulative (Lifetime) client metrics, alongside their computed segment status at the end of that specific month.

| Column Name | Data Type | Description |
| :--- | :--- | :--- |
| `report_month` | `date` | Reporting month (the 1st day of the month) |
| `client_natural_key` | `text` | Client natural key |
| `loyalty_segment_at_month` | `text` | Loyalty segment (new_customer, loyal_customer, vip_customer, danger_customer) |
| `rider_profile_segment_at_month` | `text` | Rider profile (Beginner, City_rider, Traveller_rider, Pro_rider) |
| `mtd_rentals` | `int` | Count of rentals in the current month |
| `mtd_successful_rentals` | `int` | Count of trouble-free rentals (no penalties, breakdowns, or mechanic dispatches) in the month |
| `mtd_rental_amount` | `numeric` | Total rental revenue generated in the month |
| `mtd_shop_amount` | `numeric` | Total retail shop revenue generated in the month |
| `mtd_repair_amount` | `numeric` | Total paid repair revenue generated in the month |
| `mtd_sum_rental_mileage` | `int` | Total cumulative mileage driven by the client in the month |
| `lifetime_rentals` | `int` | Cumulative count of rentals since the client's first touchpoint |
| `lifetime_total_amount` | `numeric` | Cumulative Lifetime Value (LTV) as of the end of the month |
| `trouble_free_days_ratio` | `numeric` | The ratio of trouble-free rental days across the client's entire history |

*(Note: The mart also includes demographic data such as `gender`, `nationality`, and details regarding the client's `first_rent_bike`)*.

## 2. agg_monthly_client_kpis (Reporting Mart)
A highly aggregated data mart tailored for high-level Executive Dashboards. Granularity: `Reporting Month`. This mart filters for clients who were actively engaged during the given month and pre-calculates complex macro-indicators.

| Column Name | Data Type | Description |
| :--- | :--- | :--- |
| `report_month` | `date` | Reporting month |
| `total_active_clients` | `int` | Total count of unique active clients in the month |
| `new_clients_count` | `int` | Count of newly acquired clients in the month |
| `total_monthly_revenue` | `numeric` | Total combined revenue (rentals + shop + service) |
| `avg_active_client_ltv` | `numeric` | Average historical LTV among the clients active in this specific month |
| `monthly_trouble_free_ratio` | `numeric` | North Star Metric: The ratio of trouble-free rentals strictly within this month |

## 3. agg_monthly_client_segments (Reporting Mart)
A data mart specifically engineered to power client base structure charts (e.g., 100% Stacked Bar Charts) in Tableau. Granularity: `Month + Rider Profile + Loyalty Segment + Nationality`.

| Column Name | Data Type | Description |
| :--- | :--- | :--- |
| `report_month` | `date` | Reporting month |
| `rider_profile_segment_at_month` | `text` | Sliced by rider profile |
| `loyalty_segment_at_month` | `text` | Sliced by loyalty status |
| `nationality` | `text` | Sliced by nationality |
| `unique_clients_count` | `int` | Segment size (count of unique clients) |
| `sum_rental_amount` | `numeric` | Segment rental revenue (used for structure composition analysis) |
| `sum_shop_amount` | `numeric` | Segment retail shop revenue |
| `segment_trouble_free_ratio` | `numeric` | The ratio of trouble-free rentals within the specific segment |
| `avg_trip_mileage` | `numeric` | Average trip mileage within the segment (a proxy for equipment wear and tear) |