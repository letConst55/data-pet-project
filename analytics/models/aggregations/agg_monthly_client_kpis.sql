{{
    config(
        materialized='table',
        schema='aggregations'
    )
}}

with active_clients as (
    select
        report_month,
        client_natural_key,
        loyalty_segment_at_month,
        lifetime_total_amount,
        mtd_rentals,
        mtd_successful_rentals,
        mtd_rental_amount,
        mtd_shop_amount,
        mtd_repair_amount
    from {{ ref('stats_by_clients') }}
    -- Include only those who made any transaction in the current month
    where mtd_rentals > 0 
       or mtd_shop_amount > 0 
       or mtd_repair_amount > 0
)

select
    report_month,
    
    -- Audience metrics
    count(client_natural_key) as total_active_clients,
    count(case when loyalty_segment_at_month = 'new_customer' and mtd_rentals > 0 then client_natural_key end) as new_clients_count,
    
    -- Revenue metrics
    sum(mtd_rental_amount + mtd_shop_amount + mtd_repair_amount) as total_monthly_revenue,
    coalesce(round(avg(lifetime_total_amount), 2), 0) as avg_active_client_ltv,
    
    -- North Star Metric (Honest ratio calculated strictly for this month)
    round(
        sum(mtd_successful_rentals)::decimal / nullif(sum(mtd_rentals), 0), 
        4
    ) as monthly_trouble_free_ratio

from active_clients
group by 1
order by report_month desc