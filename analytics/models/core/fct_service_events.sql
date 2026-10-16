{{
    config(
        materialized='incremental',
        unique_key='service_event_sk',
        schema='core'
    )
}}

with new_service_events_raw as (
    select * from {{ ref('stg_field_service_performed') }}
    
    {% if is_incremental() %}
        -- Инкрементальная загрузка по дате события
        where event_datetime > (select coalesce(max(event_datetime), '1900-01-01'::timestamp) from {{ this }})
    {% endif %}
),

-- Дедупликация сырых событий (защита от дублей из Kafka/S3)
new_service_events as (
    select distinct on (service_event_id)
        *
    from new_service_events_raw
    order by service_event_id, event_datetime desc, loaded_at desc
),

final as (
    select
        -- Технические поля пайплайна
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,
        
        -- Суррогатный первичный ключ события (PK)
        {{ dbt_utils.generate_surrogate_key(['s.service_event_id']) }} as service_event_sk,

        -- Degenerate Dimensions (DD)
        s.service_event_id,
        s.rental_id,

        -- FK: Клиент (SCD2 Point-in-Time Lookup)
        c.client_sk,

        -- FK: Механик (SCD2 Point-in-Time Lookup)
        e.employee_sk,

        -- FK: Байк (SCD1)
        b.bike_sk,

        -- Даты и время
        s.event_date,
        s.event_datetime,

        -- Атрибуты факта (Метрики и Категории)
        s.issue_category,
        s.resolution_action,
        s.client_fault_flag,
        s.service_cost_usd

    from new_service_events s

    -- 1. SCD2 Lookup: Клиент на момент вызова механика
    left join {{ ref('dim_client') }} c
      on s.client_id = c.client_natural_key
     and s.event_datetime >= c.row_effective_date
     and s.event_datetime < coalesce(c.row_expiration_date, '9999-12-31 23:59:59'::timestamp)

    -- 2. SCD2 Lookup: Механик на момент выезда
    left join {{ ref('dim_employee') }} e
      on s.employee_id = e.employee_natural_key
     and s.event_datetime >= e.row_effective_date
     and s.event_datetime < coalesce(e.row_expiration_date, '9999-12-31 23:59:59'::timestamp)

    -- 3. SCD1 Lookup: Байк
    left join {{ ref('dim_bike') }} b
      on s.bike_id = b.bike_natural_key
)

-- Временно фильтруем битые джойны из-за багов генератора
select * 
from final
--where client_sk is not null 
  --and employee_sk is not null