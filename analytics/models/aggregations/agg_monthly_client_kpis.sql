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
    -- Include only those who made any transaction in the current month
    where mtd_rentals > 0 
       or mtd_shop_amount > 0 
       or mtd_repair_amount > 0
)

select
    report_month,
    
    -- Audience metrics
    count(client_natural_key) as cnt_total_clients,
    count(case when loyalty_segment_at_month = 'new_customer' and mtd_rentals > 0 then client_natural_key end) as cnt_new_clients,
    
    -- Revenue metrics
    sum(mtd_rental_amount) as sum_rental_amount,
    sum(mtd_shop_amount) as sum_shop_amount,
    sum(mtd_repair_amount) as sum_repair_amount,
    sum(mtd_rental_amount + mtd_shop_amount + mtd_repair_amount) as sum_total_amount,
    coalesce(round(avg(lifetime_total_amount), 2), 0) as avg_client_ltv,
    sum(mtd_rentals) as cnt_total_rentals,
    sum(mtd_successful_rentals) as cnt_successful_rentals,
    sum(mtd_sum_rental_mileage) as sum_total_rental_mileage,
    
    -- North Star Metric (Honest ratio calculated strictly for this month)
    round(
        sum(mtd_successful_rentals)::decimal / nullif(sum(mtd_rentals), 0), 
        4
    ) as trouble_free_ratio,

    round(
        count(case when mtd_rentals > 0 and (mtd_shop_amount > 0 or mtd_repair_amount > 0) then client_natural_key end)::decimal 
        / nullif(count(case when mtd_rentals > 0 then client_natural_key end), 0), 
        4
    ) as cross_sell_penetration_rate

from active_clients
group by 1
order by report_month desc