{{
    config(
        materialized='table',
        schema='aggregations'
    )
}}

with active_clients as (
    select
        *
    from {{ ref('stats_by_clients') }}
    where mtd_rentals > 0 
       or mtd_shop_amount > 0 
       or mtd_repair_amount > 0
)

select
    report_month,
    rider_profile_segment_at_month,
    loyalty_segment_at_month,
    nationality,
    
    -- Segment size
    count(client_natural_key) as unique_clients_count,
    
    -- Revenue mix (for a 100% Stacked Bar chart)
    sum(mtd_rental_amount) as sum_rental_amount,
    sum(mtd_shop_amount) as sum_shop_amount,
    sum(mtd_repair_amount) as sum_repair_amount,
    
    -- Quality indicators broken down by segment
    round(
        sum(mtd_successful_rentals)::decimal / nullif(sum(mtd_rentals), 0), 
        4
    ) as segment_trouble_free_ratio,
    
    -- Physical metrics (equipment wear and tear)
    coalesce(round(
        sum(mtd_sum_rental_mileage)::decimal / nullif(sum(mtd_rentals), 0), 
        2
    ), 0) as avg_trip_mileage

from active_clients
group by 1, 2, 3, 4