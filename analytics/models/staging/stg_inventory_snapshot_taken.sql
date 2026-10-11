{{ config(materialized='view') }}

with source as (
    select * from {{ source('raw_data', 'ods_inventory_events') }}
    where event_type = 'inventory_snapshot_taken'
),
renamed as (
    select
        event_id,
        event_timestamp,
        
        -- Ключи
        (payload->>'week_year')::varchar as week_year,
        (payload->>'product_id')::varchar as product_id,
        (payload->>'location_id')::varchar as location_id,
        
        -- Показатели запасов
        (payload->>'product_quantity')::integer as product_quantity,
        (payload->>'available_flag')::boolean as available_flag,
        (payload->>'isin_shipment_flag')::boolean as isin_shipment_flag,
        (payload->>'planned_delivery_date')::date as planned_delivery_date,
        
        loaded_at
    from source
)
select * from renamed