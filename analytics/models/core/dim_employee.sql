{{
    config(
        materialized='incremental',
        unique_key='employee_sk',
        schema='core'
    )
}}

with new_events as (
    select * from {{ ref('stg_hr_employee_profile_updated') }}
    
    {% if is_incremental() %}
        where event_timestamp > (select max(row_effective_date) from {{ this }})
    {% endif %}
),

-- Дедуплицируем новую пачку событий
deduped_new_events as (
    select distinct on (employee_id, event_timestamp)
        employee_id as employee_natural_key,
        full_name,
        phone,
        email,
        department,
        position_title,
        grade_level,
        assigned_location_id,
        manager_employee_id,
        can_dispense_return_flg,
        can_field_service_flg,
        can_workshop_repair_flg,
        can_sell_retail_flg,
        is_active_flg,
        event_timestamp as row_effective_date
    from new_events
    order by employee_natural_key, event_timestamp, loaded_at desc
),

{% if is_incremental() %}
-- Берем из УЖЕ существующей витрины dim_employee только открытые записи 
-- и ТОЛЬКО по тем сотрудникам, которые пришли в новой пачке событий
existing_active_records as (
    select
        employee_natural_key,
        full_name,
        phone,
        email,
        department,
        position_title,
        grade_level,
        assigned_location_id,
        manager_employee_id,
        can_dispense_return_flg,
        can_field_service_flg,
        can_workshop_repair_flg,
        can_sell_retail_flg,
        is_active_flg,
        row_effective_date
    from {{ this }}
    where current_row_indicator = true
      and employee_natural_key in (select distinct employee_natural_key from deduped_new_events)
),
{% endif %}

-- Объединяем открытые старые записи и новые события
combined_records as (
    select * from deduped_new_events
    {% if is_incremental() %}
    union all
    select * from existing_active_records
    {% endif %}
),

-- Считаем LEAD() только по затронутым сотрудникам
scd2_calculated as (
    select
        *,
        lead(row_effective_date) over (
            partition by employee_natural_key 
            order by row_effective_date
        ) as next_event_timestamp
    from combined_records
),

final as (
    select
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,

        -- Суррогатный ключ (PK) - хэш от натурального ключа и даты начала версии
        md5(employee_natural_key || '_' || row_effective_date::varchar) as employee_sk,
        
        -- Натуральный ключ (NK)
        employee_natural_key,

        -- Атрибуты сотрудника
        full_name,
        phone,
        email,
        position_title,
        grade_level,
        department,
        assigned_location_id,
        manager_employee_id, -- Указатель на босса (натуральный ключ)
        is_active_flg,       -- Флаг того, работает ли сотрудник сейчас
        
        -- Операционные допуски
        can_dispense_return_flg,
        can_field_service_flg,
        can_workshop_repair_flg,
        can_sell_retail_flg,

        -- Поля историчности SCD2
        row_effective_date,
        coalesce(next_event_timestamp, '9999-12-31 23:59:59'::timestamp) as row_expiration_date,
        case 
            when next_event_timestamp is null then true 
            else false 
        end as current_row_indicator
    from scd2_calculated
)

select * from final