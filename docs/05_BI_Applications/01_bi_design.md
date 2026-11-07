# BI Applications Design & Aggregation Paradigms

Our approach to the visualization and BI (Business Intelligence) layer is built on the principle of minimizing complex logic on the client-side tool (Tableau). All heavy mathematical computations, segment calculations, and metric derivations are executed at the database level via dbt within a dedicated `aggregations` schema. This guarantees a single source of truth, rigorous version control of the logic (Git), and the flexibility to seamlessly migrate to another BI tool in the future.

All aggregations in the warehouse are logically partitioned into 4 business domains:
1.  **Customer Intelligence:** Focuses on behavior, LTV, cohorts, and segmentation.
2.  **Asset & Operations Management:** Focuses on fleet utilization, workshop load, and repair logistics.
3.  **Retail & Revenue Performance:** Focuses on shop sales structure, demand elasticity, and spare parts margins.
4.  **Workforce & HR Analytics:** Focuses on mechanic/salesperson performance evaluation and staff turnover.

Within each domain, we implement two data mart design paradigms: the "Sandbox Mart" and the "Reporting Mart."

## Paradigm 1: "Sandbox Mart"
This is the foundational mart for a domain, featuring the maximum level of aggregated granularity before non-additive metrics appear (e.g., aggregating at the `client + month` level).
*   **Purpose:** Designed for Exploratory Data Analysis (EDA). Business users and analysts can connect this mart as a single data source in Tableau (or Excel) for ad-hoc querying, filtering, and insight discovery.
*   **Key Feature:** Metrics within this mart are strictly additive (e.g., sum of sales, count of rentals). This allows the BI tool to accurately roll them up to a yearly or company-wide level without mathematical distortion. Counting unique entities (e.g., distinct clients) also functions flawlessly, as the granularity preserves the client ID.

## Paradigm 2: "Reporting Mart"
These are heavily aggregated data marts (e.g., rolled up to just `month` or `month + segment`), custom-built to power specific charts or metric blocks on a fixed dashboard.
*   **Purpose:** Serves as the data source for scheduled, read-only executive reporting.
*   **Key Feature:** These marts pre-calculate complex non-additive metrics (ratios, conversion rates, averages) that cannot be simply summed up by a BI tool. Offloading this logic to dbt relieves Tableau from heavy computations, drastically accelerates dashboard rendering times, and allows us to store the calculation logic for core business KPIs (e.g., `monthly_trouble_free_ratio`) in SQL under version control.

## Role-Playing Dimensions (Subset Dimensions)
To streamline the user experience within the BI tool, we heavily utilize Kimball's Role-Playing Dimensions pattern, specifically in the form of Subset Dimensions.

Instead of forcing analysts to filter a massive locations table (`dim_location`) or employee roster (`dim_employee`) directly within Tableau, we created logical views inside the `aggregations` schema. We have implemented 7 such dimensions. Examples include:
*   `v_field_mechanic`: A subset of employees exclusively holding the `can_field_service_flg = true` flag. The key is aliased to `field_mechanic_sk` to ensure unambiguous joins.
*   `v_garage_location`: A subset of locations physically featuring a workshop (`is_garage_flag = true`), keyed by `garage_location_sk`.
*   `v_shop_location`: A subset of locations operating a retail store (`is_shop_flag = true`), keyed by `shop_location_sk`.

This approach abstracts the technical complexity of the base dimensions away from the business user, providing them with clean, pre-filtered, and intuitively named reference tables tailored for specific business processes.