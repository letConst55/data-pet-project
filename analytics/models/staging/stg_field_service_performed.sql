{{ config(materialized='view') }}

with source as (
    select * from {{ source('raw_data', 'ods_mechanic_events') }}
    where event_type = 'field_service_performed'
),
renamed as (
    select
        event_id,
        event_timestamp,
        {{ json_extract('payload', 'service_event_id', 'varchar') }} as service_event_id,
        {{ json_extract('payload', 'rental_id', 'varchar') }} as rental_id,
        {{ json_extract('payload', 'client_id', 'varchar') }} as client_id,
        {{ json_extract('payload', 'bike_id', 'varchar') }} as bike_id,
        {{ json_extract('payload', 'location_id', 'varchar') }} as location_id,
        {{ json_extract('payload', 'event_date', 'date') }} as event_date,
        {{ json_extract('payload', 'event_datetime', 'timestamp') }} as event_datetime,
        {{ json_extract('payload', 'employee_id', 'varchar') }} as employee_id,
        {{ json_extract('payload', 'issue_category', 'varchar') }} as issue_category,
        {{ json_extract('payload', 'resolution_action', 'varchar') }} as resolution_action,
        {{ json_extract('payload', 'service_cost_usd', 'numeric(10, 2)') }} as service_cost_usd,
        {{ json_extract('payload', 'client_fault_flag', 'boolean') }} as client_fault_flag,
        loaded_at
    from source
)
select * from renamed