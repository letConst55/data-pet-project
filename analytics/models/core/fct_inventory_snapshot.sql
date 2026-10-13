{{
    config(
        materialized='incremental',
        unique_key='inventory_snapshot_sk',
        schema='core'
    )
}}

with new_snapshots_raw as (
    select * from {{ ref('stg_inventory_snapshot_taken') }}
    
    {% if is_incremental() %}
        -- Инкрементальная логика по дате создания снимка
        where event_timestamp > (select coalesce(max(snapshot_datetime), '1900-01-01'::timestamp) from {{ this }})
    {% endif %}
),

-- Дедупликация: гарантируем, что для одной комбинации Неделя+Товар+Локация останется только 1 запись
new_snapshots as (
    select distinct on (week_year, product_id, location_id)
        *
    from new_snapshots_raw
    order by week_year, product_id, location_id, event_timestamp desc, loaded_at desc
),

final as (
    select
        -- Технические поля пайплайна
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,
        
        -- Суррогатный первичный ключ факта (PK)
        {{ dbt_utils.generate_surrogate_key(['s.week_year', 'p.product_sk', 'l.location_sk']) }} as inventory_snapshot_sk,

        -- Внешние ключи
        p.product_sk,
        l.location_sk,
        
        -- Связь с календарем (FK) по дате создания снимка
        s.event_timestamp::date as snapshot_date_key,

        -- Degenerate Dimension (DD)
        s.week_year,

        -- Факты (Метрики остатков)
        s.product_quantity,

        -- Флаги и статусы (Атрибуты факта)
        s.available_flag,
        s.isin_shipment_flag,
        s.planned_delivery_date,

        -- Техническое поле для инкремента
        s.event_timestamp as snapshot_datetime

    from new_snapshots s

    -- SCD1 Lookup: Товар
    left join {{ ref('dim_product') }} p
      on s.product_id = p.product_natural_key

    -- SCD1 Lookup: Локация (Склад/Магазин)
    left join {{ ref('dim_location') }} l
      on s.location_id = l.location_natural_key
)

-- Фильтруем битые джойны
select * from final
where product_sk is not null 
  and location_sk is not null