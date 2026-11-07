{{ config(materialized='view') }}

with source as (
    select * from {{ source('raw_data', 'ods_mechanic_events') }}
    where event_type = 'bike_dispensed'
),
renamed as (
    select
        event_id,
        event_timestamp,
        (payload->>'rental_id')::varchar as rental_id,
        (payload->>'employee_disp_id')::varchar as employee_disp_id, 
        (payload->>'location_dis_id')::varchar as location_dis_id,    
        (payload->>'fact_start_date')::date as fact_start_date,
        (payload->>'fact_start_datetime')::timestamp as fact_start_datetime, 
        (payload->>'actual_start_mileage')::numeric(10, 2) as actual_start_mileage,
        (payload->>'fuel_start_percent')::numeric(10, 2) as fuel_start_percent,
        (payload->>'pre_rental_condition_score')::int as pre_rental_condition_score,
        (payload->>'helmets_issued_qty')::int as helmets_issued_qty,
        loaded_at
    from source
)
select * from renamed