{{ config(materialized='view') }}

with source as (
    select * from {{ source('raw_data', 'ods_client_events') }}
    where event_type = 'rental_booked'
),
renamed as (
    select
        event_id,
        event_timestamp,
        (payload->>'rental_id')::varchar as rental_id,
        (payload->>'client_id')::varchar as client_id, 
        (payload->>'bike_id')::varchar as bike_id,
        (payload->>'location_id')::varchar as location_id,
        (payload->>'planned_start_date')::date as planned_start_date,
        (payload->>'planned_end_date')::date as planned_end_date,
        (payload->>'rental_price_daily')::numeric(10, 2) as rental_price_daily,
        (payload->>'deposit_amount')::numeric(10, 2) as deposit_amount,
        (payload->>'discount_amount')::numeric(10, 2) as discount_amount,
        loaded_at
    from source
)
select * from renamed