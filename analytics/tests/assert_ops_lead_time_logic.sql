-- Проверка математической сходимости операционных метрик времени (утилизация и этапы Lead Time)

with bike_days_mismatch as (
    select
        report_month,
        bike_natural_key::text as entity_key,
        'bike_days_sum_mismatch' as error_reason
    from {{ ref('stats_by_bikes') }}
    where (mtd_rented_days + mtd_idle_days) != days_in_month
       or mtd_rented_days < 0
       or mtd_idle_days < 0
),

repair_stages_mismatch as (
    select
        report_month,
        location_natural_key as entity_key,
        'repair_lead_time_stages_mismatch' as error_reason
    from {{ ref('agg_monthly_supply_and_repairs') }}
    where completed_repairs_cnt > 0
      and (
          abs(
              (coalesce(avg_inbound_transport_days, 0) + coalesce(avg_active_repair_days, 0) + coalesce(avg_outbound_transport_days, 0))
              - coalesce(avg_total_repair_lead_time_days, 0)
          ) > 0.05
          or avg_total_repair_lead_time_days < 0
      )
),

procurement_stages_mismatch as (
    select
        report_month,
        location_natural_key as entity_key,
        'procurement_lead_time_stages_mismatch' as error_reason
    from {{ ref('agg_monthly_supply_and_repairs') }}
    where total_procured_qty > 0
      and (
          abs(
              (coalesce(avg_vendor_processing_days, 0) + coalesce(avg_carrier_transit_days, 0))
              - coalesce(avg_procurement_lead_time_days, 0)
          ) > 0.05
          or avg_procurement_lead_time_days < 0
      )
)

select * from bike_days_mismatch
union all
select * from repair_stages_mismatch
union all
select * from procurement_stages_mismatch