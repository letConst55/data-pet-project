{{ config(materialized='view') }}

with source as (
    select * from {{ source('raw_data', 'ods_mechanic_events') }}
    where event_type = 'bike_returned'
),
renamed as (
    select
        event_id,
        event_timestamp,
        (payload->>'rental_id')::varchar as rental_id,
        (payload->>'employee_return_id')::varchar as employee_return_id, -- Изменено
        (payload->>'location_return_id')::varchar as location_return_id, -- Изменено
        (payload->>'fact_end_date')::date as fact_end_date,
        (payload->>'fact_end_datetime')::timestamp as fact_end_datetime, -- Новое
        (payload->>'actual_end_mileage')::numeric(10, 2) as actual_end_mileage,
        (payload->>'fuel_end_percent')::numeric(10, 2) as fuel_end_percent,
        (payload->>'post_rental_condition_score')::int as post_rental_condition_score,
        (payload->>'helmet_damage_flag')::boolean as helmet_damage_flag,
        (payload->>'field_service_flag')::boolean as field_service_flag,
        (payload->>'rent_extend_flag')::boolean as rent_extend_flag,
        (payload->>'bike_exchange_flag')::boolean as bike_exchange_flag, -- Новое
        (payload->>'deposit_deducted_amount')::numeric(10, 2) as deposit_deducted_amount,
        (payload->>'deduction_reason_code')::varchar as deduction_reason_code,
        (payload->>'total_amount')::numeric(10, 2) as total_amount,
        loaded_at
    from source
)
select * from renamed