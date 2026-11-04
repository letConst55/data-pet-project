{{
    config(
        materialized='table',
        schema='aggregations'
    )
}}

with fleet_monthly as (
    select
        report_month,
        count(distinct bike_natural_key) as total_fleet_bikes,
        count(distinct case when mtd_rented_days > 0 then bike_natural_key end) as active_bikes_cnt,
        sum(mtd_rented_days) as total_rented_bike_days,
        sum(days_in_month) as total_available_bike_days,
        sum(mtd_mileage) as total_fleet_mileage_km,
        sum(mtd_field_services) as total_field_services_cnt,
        sum(mtd_service_cost_usd) as total_field_service_cost_usd,
        round(avg(end_of_month_condition_score), 2) as avg_fleet_condition_score
    from {{ ref('stats_by_bikes') }}
    group by 1
),

inventory_monthly as (
    select
        report_month,
        sum(weekly_snapshots_cnt) as total_snapshot_records,
        sum(out_of_stock_weeks_cnt) as total_out_of_stock_records,
        sum(mtd_sold_qty) as total_sold_units,
        round(avg(avg_stock_qty), 2) as avg_stock_per_sku,
        round(avg(inventory_turnover_ratio), 4) as avg_sku_turnover_ratio,
        sum(mtd_procurement_spend) as total_procurement_spend_usd,
        round(
            sum(avg_procurement_lead_time_days * mtd_shipments_cnt)::decimal 
            / nullif(sum(mtd_shipments_cnt), 0), 
            2
        ) as avg_procurement_lead_time_days
    from {{ ref('stats_by_inventory') }}
    group by 1
),

repairs_monthly as (
    select
        date_trunc('month', transportation_start_date)::date as report_month,
        count(repair_id) as external_repairs_cnt,
        sum(invoice_total_amount) as external_repair_revenue_usd,
        round(avg(transportation_end_date - transportation_start_date), 2) as avg_repair_total_lead_time_days,
        round(avg(repair_end_date - repair_start_date), 2) as avg_workshop_work_days
    from {{ ref('fct_repair') }}
    where transportation_end_date is not null
    group by 1
)

select
    f.report_month::date as report_month,

    -- 1. Утилизация и техническое здоровье парка (North Star Операционки)
    f.total_fleet_bikes::int as total_fleet_bikes,
    f.active_bikes_cnt::int as active_bikes_cnt,
    f.total_rented_bike_days::int as total_rented_bike_days,
    f.total_available_bike_days::int as total_available_bike_days,
    round(
        f.total_rented_bike_days::decimal / nullif(f.total_available_bike_days, 0), 
        4
    )::numeric as fleet_utilization_rate,
    f.avg_fleet_condition_score::numeric as avg_fleet_condition_score,

    -- 2. Полевой сервис и аварийность на дорогах
    f.total_fleet_mileage_km::numeric as total_fleet_mileage_km,
    f.total_field_services_cnt::int as total_field_services_cnt,
    f.total_field_service_cost_usd::numeric as total_field_service_cost_usd,
    round(
        (f.total_field_services_cnt * 1000.0)::decimal / nullif(f.total_fleet_mileage_km, 0), 
        2
    )::numeric as field_services_per_1000km,

    -- 3. Складской учет и Цепочка поставок
    round(
        i.total_out_of_stock_records::decimal / nullif(i.total_snapshot_records, 0), 
        4
    )::numeric as warehouse_out_of_stock_rate,
    i.avg_sku_turnover_ratio::numeric as avg_sku_turnover_ratio,
    coalesce(i.total_procurement_spend_usd, 0)::numeric as total_procurement_spend_usd,
    i.avg_procurement_lead_time_days::numeric as avg_procurement_lead_time_days,

    -- 4. Внешние ремонты в мастерских (Lead Time)
    coalesce(r.external_repairs_cnt, 0)::int as external_repairs_cnt,
    coalesce(r.external_repair_revenue_usd, 0)::numeric as external_repair_revenue_usd,
    r.avg_repair_total_lead_time_days::numeric as avg_repair_total_lead_time_days,
    r.avg_workshop_work_days::numeric as avg_workshop_work_days

from fleet_monthly f
left join inventory_monthly i on f.report_month = i.report_month
left join repairs_monthly r on f.report_month = r.report_month
order by f.report_month desc