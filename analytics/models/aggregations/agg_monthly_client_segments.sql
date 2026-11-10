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
    
    -- Audience metrics
    count(client_natural_key) as cnt_total_clients_segments,
    count(case when loyalty_segment_at_month = 'new_customer' and mtd_rentals > 0 then client_natural_key end) as cnt_new_clients_segments,
    
    -- Revenue metrics
    sum(mtd_rental_amount) as sum_rental_amount_segments,
    sum(mtd_shop_amount) as sum_shop_amount_segments,
    sum(mtd_repair_amount) as sum_repair_amount_segments,
    sum(mtd_rental_amount + mtd_shop_amount + mtd_repair_amount) as sum_total_amount_segments,
    coalesce(round(avg(lifetime_total_amount), 2), 0) as avg_client_ltv_segments,
    sum(mtd_rentals) as cnt_total_rentals_segments,
    sum(mtd_successful_rentals) as cnt_successful_rentals_segments,
    sum(mtd_sum_rental_mileage) as sum_total_rental_mileage_segments,
    
    -- North Star Metric (Honest ratio calculated strictly for this month)
    round(
        sum(mtd_successful_rentals)::decimal / nullif(sum(mtd_rentals), 0), 
        4
    ) as trouble_free_ratio_segments,

    round(
        count(case when mtd_rentals > 0 and (mtd_shop_amount > 0 or mtd_repair_amount > 0) then client_natural_key end)::decimal 
        / nullif(count(case when mtd_rentals > 0 then client_natural_key end), 0), 
        4
    ) as cross_sell_penetration_rate_segments,
    
    -- Physical metrics (equipment wear and tear)
    coalesce(round(
        sum(mtd_sum_rental_mileage)::decimal / nullif(sum(mtd_rentals), 0), 
        2
    ), 0) as avg_trip_mileage_segments

from active_clients
group by 1, 2, 3, 4