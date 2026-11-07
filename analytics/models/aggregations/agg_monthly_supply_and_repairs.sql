{{
    config(
        materialized='table',
        schema='aggregations'
    )
}}

-- 1. Inventory metrics and supplies broken down by shop locations
with location_supply as (
    select
        report_month,
        location_natural_key,
        location_title,
        round(avg(avg_stock_qty), 2) as avg_location_stock_qty,
        round(
            sum(out_of_stock_weeks_cnt)::decimal / nullif(sum(weekly_snapshots_cnt), 0), 
            4
        ) as location_out_of_stock_rate,
        round(avg(inventory_turnover_ratio), 4) as avg_location_turnover_ratio,
        sum(mtd_sold_qty) as total_sold_qty,
        sum(mtd_procured_qty) as total_procured_qty,
        sum(mtd_procurement_spend) as total_procurement_spend,
        round(avg(avg_vendor_processing_days), 2) as avg_vendor_processing_days,
        round(avg(avg_carrier_transit_days), 2) as avg_carrier_transit_days,
        round(avg(avg_procurement_lead_time_days), 2) as avg_procurement_lead_time_days
    from {{ ref('stats_by_inventory') }}
    group by 1, 2, 3
),

-- 2. External repair time anatomy (fct_repair) by drop-off shop location
location_repairs as (
    select
        date_trunc('month', r.transportation_start_date)::date as report_month,
        l.location_natural_key,
        count(r.repair_id) as completed_repairs_cnt,
        sum(r.invoice_total_amount) as repair_revenue_usd,
        -- Stage 1: Wait time and transportation from the shop to the garage
        round(avg(r.repair_start_date - r.transportation_start_date), 2) as avg_inbound_transport_days,
        -- Stage 2: Direct work in the workshop (the bottleneck when facing parts shortages)
        round(avg(r.repair_end_date - r.repair_start_date), 2) as avg_active_repair_days,
        -- Stage 3: Return transportation from the garage back to the shop
        round(avg(r.transportation_end_date - r.repair_end_date), 2) as avg_outbound_transport_days,
        -- Full repair cycle (Lead Time)
        round(avg(r.transportation_end_date - r.transportation_start_date), 2) as avg_total_repair_lead_time_days
    from {{ ref('fct_repair') }} r
    inner join {{ ref('dim_location') }} l on r.location_shop_sk = l.location_sk
    where r.transportation_end_date is not null
    group by 1, 2
)

select
    s.report_month::date as report_month,
    s.location_natural_key::text as location_natural_key,
    s.location_title::text as location_title,

    -- Inventory and turnover metrics
    s.avg_location_stock_qty::numeric as avg_location_stock_qty,
    s.location_out_of_stock_rate::numeric as location_out_of_stock_rate,
    s.avg_location_turnover_ratio::numeric as avg_location_turnover_ratio,
    s.total_sold_qty::int as total_sold_qty,

    -- Procurement and delivery stage metrics
    s.total_procured_qty::int as total_procured_qty,
    s.total_procurement_spend::numeric as total_procurement_spend,
    s.avg_vendor_processing_days::numeric as avg_vendor_processing_days,
    s.avg_carrier_transit_days::numeric as avg_carrier_transit_days,
    s.avg_procurement_lead_time_days::numeric as avg_procurement_lead_time_days,

    -- Repair bottleneck metrics
    coalesce(r.completed_repairs_cnt, 0)::int as completed_repairs_cnt,
    coalesce(r.repair_revenue_usd, 0)::numeric as repair_revenue_usd,
    r.avg_inbound_transport_days::numeric as avg_inbound_transport_days,
    r.avg_active_repair_days::numeric as avg_active_repair_days,
    r.avg_outbound_transport_days::numeric as avg_outbound_transport_days,
    r.avg_total_repair_lead_time_days::numeric as avg_total_repair_lead_time_days

from location_supply s
left join location_repairs r
  on s.report_month = r.report_month
 and s.location_natural_key = r.location_natural_key