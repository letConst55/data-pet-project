{{ config(materialized='view') }}

with source as (
    select * from {{ source('raw_data', 'ods_mechanic_events') }}
    where event_type = 'external_repair_completed'
),
renamed as (
    select
        event_id,
        event_timestamp,
        {{ json_extract('payload', 'repair_id', 'varchar') }} as repair_id,
        {{ json_extract('payload', 'order_id', 'varchar') }} as order_id,
        {{ json_extract('payload', 'employee_id', 'varchar') }} as employee_id,
        {{ json_extract('payload', 'client_id', 'varchar') }} as client_id,
        {{ json_extract('payload', 'carrier_id', 'varchar') }} as carrier_id,
        {{ json_extract('payload', 'bike_name', 'varchar') }} as bike_name,
        {{ json_extract('payload', 'location_shop_id', 'varchar') }} as location_shop_id,
        {{ json_extract('payload', 'location_garage_id', 'varchar') }} as location_garage_id,
        {{ json_extract('payload', 'transportation_start_date', 'date') }} as transportation_start_date,
        {{ json_extract('payload', 'transportation_end_date', 'date') }} as transportation_end_date,
        {{ json_extract('payload', 'repair_start_date', 'date') }} as repair_start_date,
        {{ json_extract('payload', 'repair_end_date', 'date') }} as repair_end_date,
        {{ json_extract('payload', 'invoice_total_amount', 'numeric(10, 2)') }} as invoice_total_amount,
        {{ json_extract('payload', 'invoice_discount_amount', 'numeric(10, 2)') }} as invoice_discount_amount,
        {{ json_extract('payload', 'event_datetime', 'timestamp') }} as event_datetime,
        loaded_at
    from source
)
select * from renamed