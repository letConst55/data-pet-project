{{ config(materialized='view') }}

with source as (
    select * from {{ source('raw_data', 'ods_shop_events') }}
    where event_type = 'item_purchased'
),
renamed as (
    select
        event_id,
        event_timestamp,
        
        -- ID
        (payload->>'order_id')::varchar as order_id,
        (payload->>'client_id')::varchar as client_id,
        (payload->>'employee_id')::varchar as employee_id,
        (payload->>'location_id')::varchar as location_id,
        (payload->>'product_id')::varchar as product_id,
        
        -- Date time
        (payload->>'order_date')::date as order_date,
        (payload->>'order_datetime')::timestamp as order_datetime,
        
        -- Financial metrics and quantities
        (payload->>'cnt_products')::integer as cnt_products,
        (payload->>'basic_amount')::numeric(10, 2) as basic_amount,
        (payload->>'discount_amount')::numeric(10, 2) as discount_amount,
        (payload->>'total_amount')::numeric(10, 2) as total_amount,
        
        loaded_at
    from source
)
select * from renamed