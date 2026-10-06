{{ config(materialized='view') }}

with source as (
    select * from {{ source('raw_data', 'ods_client_events') }}
    where event_type = 'client_profile_updated'
),
renamed as (
    select
        event_id,
        event_timestamp,
        -- Распаковка JSON payload с явным приведением типов
        (payload->>'client_id')::varchar as client_id,
        (payload->>'full_name')::varchar as full_name,
        (payload->>'salutation')::varchar as salutation,
        (payload->>'gender')::varchar as gender,
        (payload->>'birthday')::date as birthday,
        (payload->>'phone')::varchar as phone,
        (payload->>'email')::varchar as email,
        (payload->>'nationality')::varchar as nationality,
        (payload->>'residential_address')::varchar as residential_address,
        (payload->>'preferred_payment_method')::varchar as preferred_payment_method,
        (payload->>'driving_experience_years')::integer as driving_experience_years,
        (payload->>'drive_license_category')::varchar as drive_license_category,
        (payload->>'drive_license_verified')::boolean as drive_license_verified,
        (payload->>'rating_score')::numeric(3, 1) as rating_score,
        loaded_at
    from source
)
select * from renamed