{{ config(materialized='view') }}

with source as (
    select * from {{ source('raw_data', 'ods_mechanic_events') }}
    where event_type = 'external_repair_completed'
),
renamed as (
    select
        event_id,
        event_timestamp,
        (payload->>'repair_id')::varchar as repair_id,
        (payload->>'order_id')::varchar as order_id,
        (payload->>'employee_id')::varchar as employee_id, 
        (payload->>'client_id')::varchar as client_id,
        (payload->>'carrier_id')::varchar as carrier_id,
        (payload->>'bike_name')::varchar as bike_name,
        (payload->>'location_shop_id')::varchar as location_shop_id,
        (payload->>'location_garage_id')::varchar as location_garage_id,
        (payload->>'transportation_start_date')::date as transportation_start_date,
        (payload->>'transportation_end_date')::date as transportation_end_date,
        (payload->>'repair_start_date')::date as repair_start_date,
        (payload->>'repair_end_date')::date as repair_end_date,
        (payload->>'invoice_total_amount')::numeric(10, 2) as invoice_total_amount,
        (payload->>'invoice_discount_amount')::numeric(10, 2) as invoice_discount_amount,
        (payload->>'event_datetime')::timestamp as event_datetime,
        loaded_at
    from source
)
select * from renamed