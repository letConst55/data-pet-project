{{
    config(
        materialized='table',
        schema='aggregations'
    )
}}

select
    report_month::date as report_month,
    brand::varchar as brand,
    bike_type::varchar as bike_type,
    bike_title::varchar as bike_title,

    -- Model fleet size
    count(distinct bike_natural_key)::int as bikes_in_model_cnt,

    -- Time utilization
    sum(mtd_rented_days)::int as sum_rented_days,
    sum(mtd_idle_days)::int as sum_idle_days,
    sum(days_in_month)::int as sum_available_days,
    round(
        sum(mtd_rented_days)::numeric(18, 4) / nullif(sum(days_in_month), 0),
        4
    )::numeric(10, 4) as model_utilization_rate,

    -- Mileage and technical condition
    sum(mtd_mileage)::numeric(18, 2) as sum_monthly_mileage_km,
    round(avg(current_odometer_km), 0)::numeric(18, 0) as avg_odometer_km,
    round(avg(end_of_month_condition_score), 2)::numeric(10, 2) as avg_condition_score,

    -- Service workload and model economics
    sum(mtd_field_services)::int as sum_field_services,
    sum(mtd_rental_revenue)::numeric(18, 2) as sum_rental_revenue,
    sum(mtd_service_cost_usd)::numeric(18, 2) as sum_service_cost_usd,
    sum(mtd_net_operating_income)::numeric(18, 2) as sum_net_operating_income,
    round(avg(lifetime_roi_ratio), 4)::numeric(18, 4) as avg_model_roi_ratio

from {{ ref('stats_by_bikes') }}
group by 1, 2, 3, 4