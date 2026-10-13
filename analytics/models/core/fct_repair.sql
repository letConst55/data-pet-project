{{
    config(
        materialized='incremental',
        unique_key='repair_sk',
        schema='core'
    )
}}

with new_repairs_raw as (
    select * from {{ ref('stg_external_repair_completed') }}
    
    {% if is_incremental() %}
        -- Забираем новые события с момента последнего инкремента
        where event_datetime > (select coalesce(max(event_datetime), '1900-01-01'::timestamp) from {{ this }})
    {% endif %}
),

-- Дедупликация сырых событий
new_repairs as (
    select distinct on (repair_id)
        *
    from new_repairs_raw
    order by repair_id, event_datetime desc, loaded_at desc
),

final as (
    select
        -- Технические поля пайплайна
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,
        
        -- Суррогатный первичный ключ факта (PK)
        {{ dbt_utils.generate_surrogate_key(['r.repair_id']) }} as repair_sk,

        -- Degenerate Dimensions (DD)
        r.repair_id,
        r.order_id,          -- Может быть NULL, если запчасти не покупались

        -- Внешние ключи
        c.client_sk,         -- SCD2
        e.employee_sk,       -- SCD2
        cr.carrier_sk,       -- SCD1
        ls.location_sk as location_shop_sk,   -- SCD1 (магазин, где приняли байк)
        lg.location_sk as location_garage_sk, -- SCD1 (мастерская)

        -- Детали ремонта
        r.bike_name,

        -- Даты пайплайна ремонта
        r.transportation_start_date,
        r.repair_start_date,
        r.repair_end_date,
        r.transportation_end_date,
        r.event_datetime,

        -- Метрики
        r.invoice_total_amount,
        r.invoice_discount_amount

    from new_repairs r

    -- 1. SCD2 Lookup: Клиент на момент события
    left join {{ ref('dim_client') }} c
      on r.client_id = c.client_natural_key
     and r.event_datetime >= c.row_effective_date
     and r.event_datetime <= coalesce(c.row_expiration_date, '9999-12-31 23:59:59'::timestamp)

    -- 2. SCD2 Lookup: Сотрудник (принимавший байк) на момент события
    left join {{ ref('dim_employee') }} e
      on r.employee_id = e.employee_natural_key
     and r.event_datetime >= e.row_effective_date
     and r.event_datetime <= coalesce(e.row_expiration_date, '9999-12-31 23:59:59'::timestamp)

    -- 3. SCD1 Lookup: Перевозчик
    left join {{ ref('dim_carrier') }} cr
      on r.carrier_id = cr.carrier_natural_key

    -- 4. SCD1 Lookup: Локация (Магазин приемки)
    left join {{ ref('dim_location') }} ls
      on r.location_shop_id = ls.location_natural_key

    -- 5. SCD1 Lookup: Локация (Мастерская ремонта)
    left join {{ ref('dim_location') }} lg
      on r.location_garage_id = lg.location_natural_key
)

-- Отсекаем Unknown Members (если таковые проскочили)
select * from final
where client_sk is not null 
  and employee_sk is not null