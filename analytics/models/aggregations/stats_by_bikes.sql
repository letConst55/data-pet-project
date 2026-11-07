{{
    config(
        materialized='table',
        schema='aggregations'
    )
}}

-- 1. Define the historical boundaries based on rental facts
with date_bounds as (
    select
        coalesce(date_trunc('month', min(fact_start_date))::date, '2024-03-01'::date) as min_month,
        date_trunc('month', current_date)::date as max_month
    from {{ ref('fct_client_bike_rent') }}
),

-- 2. Build the calendar spine: each bike x each month
calendar_months as (
    select 
        distinct
        date_trunc('month', cal.date)::date as report_month,
        extract(day from (date_trunc('month', cal.date) + interval '1 month - 1 day'))::int as days_in_month
    from {{ ref('dim_calendar') }} cal
    cross join date_bounds b
    where cal.date >= b.min_month
      and cal.date <= b.max_month
),

bike_spine as (
    select
        m.report_month,
        m.days_in_month,
        b.bike_sk,
        b.bike_natural_key,
        b.title as bike_title,
        b.type as bike_type,
        b.brand,
        b.model_year,
        b.engine_volume_cc,
        b.procurement_price
    from calendar_months m
    cross join {{ ref('dim_bike') }} b
),

-- 3. Accurate calculation of rented days within each month (unrolling intervals by day, 
-- to prevent month-spanning rentals from yielding > 100% utilization)
bike_active_days as (
    select
        fbr.bike_sk,
        date_trunc('month', d.active_day)::date as event_month,
        count(distinct d.active_day) as mtd_rented_days
    from {{ ref('fct_client_bike_rent') }} fbr
    cross join lateral generate_series(
        fbr.fact_start_date,
        greatest(fbr.fact_start_date, (fbr.fact_end_date - interval '1 day')::date),
        '1 day'::interval
    ) as d(active_day)
    where fbr.fact_start_date is not null
      and fbr.fact_end_date is not null
    group by 1, 2
),

-- 4. Financial and technical metrics for completed rentals by return month
rental_monthly_metrics as (
    select
        fbr.bike_sk,
        date_trunc('month', fbr.fact_end_date)::date as event_month,
        count(fbr.rental_id) as mtd_completed_rentals,
        sum(fbr.actual_end_mileage - fbr.actual_start_mileage) as mtd_mileage,
        max(fbr.actual_end_mileage) as max_end_mileage_in_month,
        min(fbr.post_rental_condition_score) as min_condition_score_in_month,
        sum(fbr.total_amount) as mtd_rental_revenue,
        sum(coalesce(fbr.deposit_deducted_amount, 0)) as mtd_penalty_amount
    from {{ ref('fct_client_bike_rent') }} fbr
    where fbr.fact_end_date is not null
    group by 1, 2
),

-- 5. Field service dispatches and field repair costs for each bike
service_monthly_metrics as (
    select
        se.bike_sk,
        date_trunc('month', se.event_date)::date as event_month,
        count(se.service_event_id) as mtd_field_services,
        count(case when se.resolution_action = 'towed_to_shop' then 1 end) as mtd_towed_events,
        count(case when se.client_fault_flag = false then 1 end) as mtd_tech_wear_incidents,
        sum(se.service_cost_usd) as mtd_service_cost_usd
    from {{ ref('fct_service_events') }} se
    group by 1, 2
),

-- 6. Assemble the flat table and calculate cumulative metrics of the bike's lifecycle
monthly_rollup as (
    select
        s.report_month,
        s.days_in_month,
        s.bike_natural_key,
        s.bike_title,
        s.bike_type,
        s.brand,
        s.model_year,
        s.engine_volume_cc,
        s.procurement_price,

        -- MTD usage metrics
        least(s.days_in_month, coalesce(bad.mtd_rented_days, 0)) as mtd_rented_days,
        coalesce(rm.mtd_completed_rentals, 0) as mtd_completed_rentals,
        coalesce(rm.mtd_mileage, 0) as mtd_mileage,
        coalesce(rm.mtd_rental_revenue, 0) as mtd_rental_revenue,
        coalesce(rm.mtd_penalty_amount, 0) as mtd_penalty_amount,

        -- MTD breakdown and service metrics
        coalesce(sm.mtd_field_services, 0) as mtd_field_services,
        coalesce(sm.mtd_towed_events, 0) as mtd_towed_events,
        coalesce(sm.mtd_tech_wear_incidents, 0) as mtd_tech_wear_incidents,
        coalesce(sm.mtd_service_cost_usd, 0) as mtd_service_cost_usd,

        -- Cumulative metrics since the bike was commissioned
        sum(least(s.days_in_month, coalesce(bad.mtd_rented_days, 0))) over (
            partition by s.bike_natural_key order by s.report_month
        ) as lifetime_rented_days,
        sum(coalesce(rm.mtd_mileage, 0)) over (
            partition by s.bike_natural_key order by s.report_month
        ) as lifetime_mileage_ridden,
        max(rm.max_end_mileage_in_month) over (
            partition by s.bike_natural_key order by s.report_month
        ) as current_odometer_km,
        coalesce(
            min(rm.min_condition_score_in_month) over (
                partition by s.bike_natural_key order by s.report_month
            ),
            10
        ) as end_of_month_condition_score,
        sum(coalesce(rm.mtd_rental_revenue, 0)) over (
            partition by s.bike_natural_key order by s.report_month
        ) as lifetime_rental_revenue,
        sum(coalesce(sm.mtd_service_cost_usd, 0)) over (
            partition by s.bike_natural_key order by s.report_month
        ) as lifetime_service_cost_usd

    from bike_spine s
    left join bike_active_days bad
      on s.bike_sk = bad.bike_sk and s.report_month = bad.event_month
    left join rental_monthly_metrics rm
      on s.bike_sk = rm.bike_sk and s.report_month = rm.event_month
    left join service_monthly_metrics sm
      on s.bike_sk = sm.bike_sk and s.report_month = sm.event_month
)

select
    report_month::date as report_month,
    bike_natural_key::int as bike_natural_key,
    bike_title::text as bike_title,
    bike_type::text as bike_type,
    brand::text as brand,
    model_year::int as model_year,
    engine_volume_cc::int as engine_volume_cc,
    procurement_price::numeric as procurement_price,

    days_in_month::int as days_in_month,
    mtd_rented_days::int as mtd_rented_days,
    (days_in_month - mtd_rented_days)::int as mtd_idle_days,
    round(mtd_rented_days::decimal / nullif(days_in_month, 0), 4)::numeric as utilization_rate,

    mtd_completed_rentals::int as mtd_completed_rentals,
    mtd_mileage::numeric as mtd_mileage,
    mtd_rental_revenue::numeric as mtd_rental_revenue,
    mtd_penalty_amount::numeric as mtd_penalty_amount,

    mtd_field_services::int as mtd_field_services,
    mtd_towed_events::int as mtd_towed_events,
    mtd_tech_wear_incidents::int as mtd_tech_wear_incidents,
    mtd_service_cost_usd::numeric as mtd_service_cost_usd,
    (mtd_rental_revenue - mtd_service_cost_usd)::numeric as mtd_net_operating_income,

    lifetime_rented_days::int as lifetime_rented_days,
    lifetime_mileage_ridden::numeric as lifetime_mileage_ridden,
    coalesce(current_odometer_km, 1000)::numeric as current_odometer_km,
    end_of_month_condition_score::int as end_of_month_condition_score,
    lifetime_rental_revenue::numeric as lifetime_rental_revenue,
    lifetime_service_cost_usd::numeric as lifetime_service_cost_usd,

    -- Bike ROI: ratio of cumulative net operating income to the bike purchase price
    -- (Note: procurement_price in the dictionary is in THB, so we divide by the exchange rate ~35 THB/USD)
    round(
        (lifetime_rental_revenue - lifetime_service_cost_usd)::decimal 
        / nullif(procurement_price / 35.0, 0), 
        4
    )::numeric as lifetime_roi_ratio,

    -- Operational fleet health status
    case
        when end_of_month_condition_score >= 8 then 'Optimal (Score 8-10)'
        when end_of_month_condition_score >= 5 then 'Standard Wear (Score 5-7)'
        when end_of_month_condition_score >= 3 then 'Needs Overhaul (Score 3-4)'
        else 'Critical / Decommission Risk (Score 1-2)'
    end::text as fleet_health_status

from monthly_rollup