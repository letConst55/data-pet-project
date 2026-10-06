{{ config(materialized='view') }}

with source as (
    select * from {{ source('raw_data', 'ods_mechanic_events') }}
    where event_type = 'field_service_performed'
),
renamed as (
    select
        event_id,
        event_timestamp,
        (payload->>'rental_id')::varchar as rental_id,
        (payload->>'client_id')::varchar as client_id,
        (payload->>'bike_id')::varchar as bike_id,
        (payload->>'event_date')::date as event_date,
        (payload->>'mechanic_id')::varchar as mechanic_id,
        (payload->>'service_cost_usd')::numeric(10, 2) as service_cost_usd,
        (payload->>'issue_category')::varchar as issue_category,
        (payload->>'client_fault_flag')::boolean as client_fault_flag,
        (payload->>'resolution_action')::varchar as resolution_action,
        loaded_at
    from source
)
select * from renamed