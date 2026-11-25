{{ config(materialized='view') }}

with source as (
    select * from {{ source('raw_data', 'ods_hr_events') }}
    where event_type = 'employee_profile_updated'
),
renamed as (
    select
        event_id,
        event_timestamp,
        
        {{ json_extract('payload', 'employee_id', 'varchar') }} as employee_id,
        {{ json_extract('payload', 'full_name', 'varchar') }} as full_name,
        {{ json_extract('payload', 'phone', 'varchar') }} as phone,
        {{ json_extract('payload', 'email', 'varchar') }} as email,
        {{ json_extract('payload', 'department', 'varchar') }} as department,
        {{ json_extract('payload', 'position_title', 'varchar') }} as position_title,
        {{ json_extract('payload', 'grade_level', 'varchar') }} as grade_level,
        {{ json_extract('payload', 'assigned_location_id', 'varchar') }} as assigned_location_id,
        {{ json_extract('payload', 'manager_employee_id', 'varchar') }} as manager_employee_id,
        {{ json_extract('payload', 'can_dispense_return_flg', 'boolean') }} as can_dispense_return_flg,
        {{ json_extract('payload', 'can_field_service_flg', 'boolean') }} as can_field_service_flg,
        {{ json_extract('payload', 'can_workshop_repair_flg', 'boolean') }} as can_workshop_repair_flg,
        {{ json_extract('payload', 'can_sell_retail_flg', 'boolean') }} as can_sell_retail_flg,
        {{ json_extract('payload', 'is_active', 'boolean') }} as is_active_flg,
        
        loaded_at
    from source
)
select * from renamed