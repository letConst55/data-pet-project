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
        (payload->>'mechanic_id')::varchar as mechanic_id,
        (payload->>'location_id')::varchar as location_id,
        (payload->>'fact_end_date')::date as fact_end_date,
        (payload->>'rent_extend_flag')::boolean as rent_extend_flag,
        (payload->>'total_amount')::numeric(10, 2) as total_amount,
        (payload->>'field_service_flag')::boolean as field_service_flag,
        (payload->>'helmet_damage_flag')::boolean as helmet_damage_flag,
        (payload->>'fuel_level_percent')::numeric(10, 2) as fuel_level_percent,
        (payload->>'deduction_reason_code')::varchar as deduction_reason_code,
        (payload->>'actual_end_mileage')::numeric(10, 2) as actual_end_mileage,
        (payload->>'deposit_deducted_amount')::numeric(10, 2) as deposit_deducted_amount,
        (payload->>'post_rental_condition_score')::int as post_rental_condition_score,
        loaded_at
    from source
)
select * from renamed