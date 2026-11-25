{{ config(materialized='view') }}

with source as (
    select * from {{ source('raw_data', 'ods_shop_events') }}
    where event_type = 'item_purchased'
),
renamed as (
    select
        event_id,
        event_timestamp,
        
        {{ json_extract('payload', 'order_id', 'varchar') }} as order_id,
        {{ json_extract('payload', 'client_id', 'varchar') }} as client_id,
        {{ json_extract('payload', 'employee_id', 'varchar') }} as employee_id,
        {{ json_extract('payload', 'location_id', 'varchar') }} as location_id,
        {{ json_extract('payload', 'product_id', 'varchar') }} as product_id,
        {{ json_extract('payload', 'order_date', 'date') }} as order_date,
        {{ json_extract('payload', 'order_datetime', 'timestamp') }} as order_datetime,
        {{ json_extract('payload', 'cnt_products', 'integer') }} as cnt_products,
        {{ json_extract('payload', 'basic_amount', 'numeric(10, 2)') }} as basic_amount,
        {{ json_extract('payload', 'discount_amount', 'numeric(10, 2)') }} as discount_amount,
        {{ json_extract('payload', 'total_amount', 'numeric(10, 2)') }} as total_amount,
        
        loaded_at
    from source
)
select * from renamed