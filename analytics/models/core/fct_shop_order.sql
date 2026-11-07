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
        -- Extracting only new events since the last increment
        where event_timestamp > (select coalesce(max(event_datetime), '1900-01-01'::timestamp) from {{ this }})
    {% endif %}
),

-- Deduplication of raw events (protection against duplicates from S3 or generator restarts)
new_orders as (
    select distinct on (order_id, product_id)
        *
    from new_orders_raw
    order by order_id, product_id, event_timestamp desc, loaded_at desc
),

final as (
    select
        -- Technical pipeline fields
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,
        
        -- Surrogate primary key for the receipt item (PK)
        {{ dbt_utils.generate_surrogate_key(['o.order_id', 'p.product_sk']) }} as shop_order_sk,

        -- Degenerate Dimension (DD) - receipt number
        o.order_id,

        -- FK: Client (SCD2 Point-in-Time Lookup)
        c.client_sk,

        -- FK: Employee (SCD2 Point-in-Time Lookup)
        e.employee_sk,

        -- FK: Location (SCD1)
        l.location_sk,

        -- FK: Product (SCD1)
        p.product_sk,

        -- Dates and times
        o.order_date,
        o.order_datetime as event_datetime,

        -- Metrics (Facts)
        o.cnt_products,
        o.basic_amount,
        o.discount_amount,
        o.total_amount

    from new_orders o

    -- 1. SCD2 Lookup: Client at the time of purchase
    -- Using COALESCE for the closing date to cover all edge cases
    left join {{ ref('dim_client') }} c
      on o.client_id = c.client_natural_key
     and o.event_timestamp >= c.row_effective_date
     and o.event_timestamp < coalesce(c.row_expiration_date, '9999-12-31 23:59:59'::timestamp)

    -- 2. SCD2 Lookup: Employee at the time of purchase
    left join {{ ref('dim_employee') }} e
      on o.employee_id = e.employee_natural_key
     and o.event_timestamp >= e.row_effective_date
     and o.event_timestamp < coalesce(e.row_expiration_date, '9999-12-31 23:59:59'::timestamp)

    -- 3. SCD1 Lookup: Shop location
    left join {{ ref('dim_location') }} l
      on o.location_id = l.location_natural_key

    -- 4. SCD1 Lookup: Product
    left join {{ ref('dim_product') }} p
      on o.product_id = p.product_natural_key
)

select * from final
--where client_sk is not null