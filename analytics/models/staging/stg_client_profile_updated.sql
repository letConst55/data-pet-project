{{ config(materialized='view') }}

with source as (
    select * from {{ source('raw_data', 'ods_client_events') }}
    where event_type = 'client_profile_updated'
),
renamed as (
    select
        event_id,
        event_timestamp,
        {{ json_extract('payload', 'client_id', 'varchar') }} as client_id,
        {{ json_extract('payload', 'full_name', 'varchar') }} as full_name,
        {{ json_extract('payload', 'salutation', 'varchar') }} as salutation,
        {{ json_extract('payload', 'gender', 'varchar') }} as gender,
        {{ json_extract('payload', 'birthday', 'date') }} as birthday,
        {{ json_extract('payload', 'phone', 'varchar') }} as phone,
        {{ json_extract('payload', 'email', 'varchar') }} as email,
        {{ json_extract('payload', 'nationality', 'varchar') }} as nationality,
        {{ json_extract('payload', 'residential_address', 'varchar') }} as residential_address,
        {{ json_extract('payload', 'preferred_payment_method', 'varchar') }} as preferred_payment_method,
        {{ json_extract('payload', 'driving_experience_years', 'integer') }} as driving_experience_years,
        {{ json_extract('payload', 'drive_license_category', 'varchar') }} as drive_license_category,
        {{ json_extract('payload', 'drive_license_verified', 'boolean') }} as drive_license_verified,
        {{ json_extract('payload', 'rating_score', 'numeric(3, 1)') }} as rating_score,
        loaded_at
    from source
)
select * from renamed