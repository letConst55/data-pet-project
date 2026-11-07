{{
    config(
        materialized='table',
        schema='aggregations'
    )
}}

select
    report_month::date as report_month,
    brand::text as brand,
    bike_type::text as bike_type,
    bike_title::text as bike_title,

    -- Model fleet size
    count(distinct bike_natural_key)::int as bikes_in_model_cnt,

    -- Time utilization
    sum(mtd_rented_days)::int as sum_rented_days,
    sum(mtd_idle_days)::int as sum_idle_days,
    sum(days_in_month)::int as sum_available_days,
    round(
        sum(mtd_rented_days)::decimal / nullif(sum(days_in_month), 0), 
        4
    )::numeric as model_utilization_rate,

    -- Mileage and technical condition
    sum(mtd_mileage)::numeric as sum_monthly_mileage_km,
    round(avg(current_odometer_km), 0)::numeric as avg_odometer_km,
    round(avg(end_of_month_condition_score), 2)::numeric as avg_condition_score,

    -- Service workload and model economics
    sum(mtd_field_services)::int as sum_field_services,
    sum(mtd_rental_revenue)::numeric as sum_rental_revenue,
    sum(mtd_service_cost_usd)::numeric as sum_service_cost_usd,
    sum(mtd_net_operating_income)::numeric as sum_net_operating_income,
    round(avg(lifetime_roi_ratio), 4)::numeric as avg_model_roi_ratio

from {{ ref('stats_by_bikes') }}
group by 1, 2, 3, 4