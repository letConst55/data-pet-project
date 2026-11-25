{{ config(materialized='view') }}

with source as (
    select * from {{ source('raw_data', 'ods_mechanic_events') }}
    where event_type = 'bike_returned'
),
renamed as (
    select
        event_id,
        event_timestamp,
        {{ json_extract('payload', 'rental_id', 'varchar') }} as rental_id,
        {{ json_extract('payload', 'employee_return_id', 'varchar') }} as employee_return_id,
        {{ json_extract('payload', 'location_return_id', 'varchar') }} as location_return_id,
        {{ json_extract('payload', 'fact_end_date', 'date') }} as fact_end_date,
        {{ json_extract('payload', 'fact_end_datetime', 'timestamp') }} as fact_end_datetime,
        {{ json_extract('payload', 'actual_end_mileage', 'numeric(10, 2)') }} as actual_end_mileage,
        {{ json_extract('payload', 'fuel_end_percent', 'numeric(10, 2)') }} as fuel_end_percent,
        {{ json_extract('payload', 'post_rental_condition_score', 'int') }} as post_rental_condition_score,
        {{ json_extract('payload', 'helmet_damage_flag', 'boolean') }} as helmet_damage_flag,
        {{ json_extract('payload', 'field_service_flag', 'boolean') }} as field_service_flag,
        {{ json_extract('payload', 'rent_extend_flag', 'boolean') }} as rent_extend_flag,
        {{ json_extract('payload', 'bike_exchange_flag', 'boolean') }} as bike_exchange_flag,
        {{ json_extract('payload', 'deposit_deducted_amount', 'numeric(10, 2)') }} as deposit_deducted_amount,
        {{ json_extract('payload', 'deduction_reason_code', 'varchar') }} as deduction_reason_code,
        {{ json_extract('payload', 'total_amount', 'numeric(10, 2)') }} as total_amount,
        loaded_at
    from source
)
select * from renamed