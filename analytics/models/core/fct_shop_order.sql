{{
    config(
        materialized='incremental',
        unique_key='shop_order_sk',
        schema='core'
    )
}}

with new_orders_raw as (
    select * from {{ ref('stg_shop_item_purchased') }}
    
    {% if is_incremental() %}
        -- Забираем только новые события с момента последнего инкремента
        where event_timestamp > (select coalesce(max(event_datetime), '1900-01-01'::timestamp) from {{ this }})
    {% endif %}
),

-- Дедупликация сырых событий (защита от дублей из S3 или рестартов генератора)
new_orders as (
    select distinct on (order_id, product_id)
        *
    from new_orders_raw
    order by order_id, product_id, event_timestamp desc, loaded_at desc
),

final as (
    select
        -- Технические поля пайплайна
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,
        
        -- Суррогатный первичный ключ позиции чека (PK)
        {{ dbt_utils.generate_surrogate_key(['o.order_id', 'p.product_sk']) }} as shop_order_sk,

        -- Degenerate Dimension (DD) - номер чека
        o.order_id,

        -- FK: Клиент (SCD2 Point-in-Time Lookup)
        c.client_sk,

        -- FK: Сотрудник (SCD2 Point-in-Time Lookup)
        e.employee_sk,

        -- FK: Локация (SCD1)
        l.location_sk,

        -- FK: Товар (SCD1)
        p.product_sk,

        -- Даты и время
        o.order_date,
        o.order_datetime as event_datetime,

        -- Метрики (Факты)
        o.cnt_products,
        o.basic_amount,
        o.discount_amount,
        o.total_amount

    from new_orders o

    -- 1. SCD2 Lookup: Клиент на момент покупки
    -- Используем COALESCE для закрывающей даты, чтобы охватить все краевые случаи
    left join {{ ref('dim_client') }} c
      on o.client_id = c.client_natural_key
     and o.event_timestamp >= c.row_effective_date
     and o.event_timestamp <= coalesce(c.row_expiration_date, '9999-12-31 23:59:59'::timestamp)

    -- 2. SCD2 Lookup: Сотрудник на момент покупки
    left join {{ ref('dim_employee') }} e
      on o.employee_id = e.employee_natural_key
     and o.event_timestamp >= e.row_effective_date
     and o.event_timestamp <= coalesce(e.row_expiration_date, '9999-12-31 23:59:59'::timestamp)

    -- 3. SCD1 Lookup: Локация магазина
    left join {{ ref('dim_location') }} l
      on o.location_id = l.location_natural_key

    -- 4. SCD1 Lookup: Товар
    left join {{ ref('dim_product') }} p
      on o.product_id = p.product_natural_key
)

select * from final
where client_sk is not null