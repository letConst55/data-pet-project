{{
    config(
        materialized='table',
        schema='aggregations'
    )
}}

-- 1. Aggregate weekly inventory snapshots (fct_inventory_snapshot) to the Month + Product + Location level.
-- Since a snapshot is taken every Sunday for all physical products and shops, it serves as an ideal Spine.
with snapshot_monthly as (
    select
        date_trunc('month', s.snapshot_date_key)::date as report_month,
        s.product_sk,
        s.location_sk,
        count(s.inventory_snapshot_sk) as weekly_snapshots_cnt,
        round(avg(s.product_quantity), 2) as avg_stock_qty,
        min(s.product_quantity) as min_stock_qty,
        max(s.product_quantity) as max_stock_qty,
        count(case when s.available_flag = false then 1 end) as out_of_stock_weeks_cnt,
        count(case when s.isin_shipment_flag = true then 1 end) as in_transit_weeks_cnt
    from {{ ref('fct_inventory_snapshot') }} s
    group by 1, 2, 3
),

-- 2. Sales of physical goods in retail stores (stock deduction)
shop_sales_monthly as (
    select
        date_trunc('month', o.order_date)::date as event_month,
        o.product_sk,
        o.location_sk,
        sum(o.cnt_products) as mtd_sold_qty,
        sum(o.total_amount) as mtd_sales_revenue
    from {{ ref('fct_shop_order') }} o
    inner join {{ ref('dim_product') }} p on o.product_sk = p.product_sk
    where p.is_tuning_flag = false
    group by 1, 2, 3
),

-- 3. Procurements and supply logistics (stock replenishment and Lead Time stages)
procurement_monthly as (
    select
        date_trunc('month', pr.order_date)::date as event_month,
        pr.product_sk,
        pr.arrival_location_sk as location_sk,
        count(distinct pr.shipment_id) as mtd_shipments_cnt,
        sum(pr.product_quantity) as mtd_procured_qty,
        sum(pr.payment_amount) as mtd_procurement_spend,
        round(avg(pr.shipment_departure_date - pr.order_date), 2) as avg_vendor_processing_days,
        round(avg(pr.shipment_arrival_date - pr.shipment_departure_date), 2) as avg_carrier_transit_days,
        round(avg(pr.shipment_arrival_date - pr.order_date), 2) as avg_procurement_lead_time_days
    from {{ ref('fct_procurement') }} pr
    group by 1, 2, 3
)

select
    sm.report_month::date as report_month,
    p.product_natural_key::text as product_natural_key,
    p.title::text as product_title,
    p.level1_category::text as level1_category,
    p.level2_category::text as level2_category,
    p.manufactory::text as manufactory,
    p.is_spare_flag::boolean as is_spare_flag,

    l.location_natural_key::text as location_natural_key,
    l.title::text as location_title,

    -- Inventory condition metrics
    sm.weekly_snapshots_cnt::int as weekly_snapshots_cnt,
    sm.avg_stock_qty::numeric as avg_stock_qty,
    sm.min_stock_qty::int as min_stock_qty,
    sm.max_stock_qty::int as max_stock_qty,
    sm.out_of_stock_weeks_cnt::int as out_of_stock_weeks_cnt,
    sm.in_transit_weeks_cnt::int as in_transit_weeks_cnt,
    round(
        sm.out_of_stock_weeks_cnt::decimal / nullif(sm.weekly_snapshots_cnt, 0), 
        4
    )::numeric as out_of_stock_rate,

    -- Outflow metrics (retail sales)
    coalesce(sh.mtd_sold_qty, 0)::int as mtd_sold_qty,
    coalesce(sh.mtd_sales_revenue, 0)::numeric as mtd_sales_revenue,

    -- Inflow metrics (procurements from suppliers)
    coalesce(pr.mtd_shipments_cnt, 0)::int as mtd_shipments_cnt,
    coalesce(pr.mtd_procured_qty, 0)::int as mtd_procured_qty,
    coalesce(pr.mtd_procurement_spend, 0)::numeric as mtd_procurement_spend,

    -- Lead Time anatomy
    pr.avg_vendor_processing_days::numeric as avg_vendor_processing_days,
    pr.avg_carrier_transit_days::numeric as avg_carrier_transit_days,
    pr.avg_procurement_lead_time_days::numeric as avg_procurement_lead_time_days,

    -- Monthly Inventory Turnover Ratio
    case
        when sm.avg_stock_qty > 0 then round(coalesce(sh.mtd_sold_qty, 0)::decimal / sm.avg_stock_qty, 4)
        else null
    end::numeric as inventory_turnover_ratio

from snapshot_monthly sm
inner join {{ ref('dim_product') }} p on sm.product_sk = p.product_sk
inner join {{ ref('dim_location') }} l on sm.location_sk = l.location_sk
left join shop_sales_monthly sh
  on sm.report_month = sh.event_month
 and sm.product_sk = sh.product_sk
 and sm.location_sk = sh.location_sk
left join procurement_monthly pr
  on sm.report_month = pr.event_month
 and sm.product_sk = pr.product_sk
 and sm.location_sk = pr.location_sk