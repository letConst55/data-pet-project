{{ config(materialized='view') }}

with source as (
    select * from {{ source('raw_data', 'ods_hr_events') }}
    where event_type = 'employee_profile_updated'
),
renamed as (
    select
        event_id,
        event_timestamp,
        
        -- Идентификатор
        (payload->>'employee_id')::varchar as employee_id,
        --(payload->>'employee_natural_key')::varchar as employee_natural_key,
        
        -- Персональные данные
        (payload->>'full_name')::varchar as full_name,
        (payload->>'phone')::varchar as phone,
        (payload->>'email')::varchar as email,
        
        -- Кадровая информация
        (payload->>'department')::varchar as department,
        (payload->>'position_title')::varchar as position_title,
        (payload->>'grade_level')::varchar as grade_level,
        (payload->>'assigned_location_id')::varchar as assigned_location_id,
        (payload->>'manager_employee_id')::varchar as manager_employee_id,
        
        -- Флаги операционных допусков
        (payload->>'can_dispense_return_flg')::boolean as can_dispense_return_flg,
        (payload->>'can_field_service_flg')::boolean as can_field_service_flg,
        (payload->>'can_workshop_repair_flg')::boolean as can_workshop_repair_flg,
        (payload->>'can_sell_retail_flg')::boolean as can_sell_retail_flg,
        
        -- Статус сотрудника (уволен / работает)
        (payload->>'is_active')::boolean as is_active_flg,
        
        loaded_at
    from source
)
select * from renamed