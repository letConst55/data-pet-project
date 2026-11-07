/*
-------------------------------------------------------------------------------------------------------
Test Name: assert_ops_lead_time_logic
Description: 
    Validates the mathematical consistency of operational time metrics (Utilization and Lead Times).
    This test ensures that the sum of granular duration stages strictly matches the total duration.

Business Rules Validated:
    1. Bike Utilization: The sum of `mtd_rented_days` and `mtd_idle_days` must exactly equal 
       the total calendar days in that month (`days_in_month`). Negative days are not allowed.
       - Failure Example: A bug in the generator causes a 30-day rental crossing two months to be 
         fully attributed to the first month, resulting in >100% utilization.
    2. Repair Lead Time: The total repair time must equal the sum of inbound transport, active repair, 
       and outbound transport times.
       - Failure Example: An external carrier loses a bike during outbound transport, leaving the 
         end date NULL, which breaks the average time calculation.
    3. Procurement Lead Time: The total procurement time must equal vendor processing time 
       plus carrier transit time.
       - Failure Example: A vendor retroactive edits the invoice date, making the processing time negative.

Output: 
    Returns rows where time metrics do not add up, tagged with a specific `error_reason`.
-------------------------------------------------------------------------------------------------------
*/

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