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
        (payload->>'mechanic_id')::varchar as mechanic_id,
        (payload->>'location_id')::varchar as location_id,
        (payload->>'fact_start_date')::date as fact_start_date,
        (payload->>'fuel_level_percent')::numeric(10, 2) as fuel_level_percent,
        (payload->>'helmets_issued_qty')::int as helmets_issued_qty,
        (payload->>'actual_start_mileage')::numeric(10, 2) as actual_start_mileage,
        (payload->>'actual_payment_method')::varchar as actual_payment_method,
        (payload->>'pre_rental_condition_score')::int as pre_rental_condition_score,
        loaded_at
    from source
)
select * from renamed