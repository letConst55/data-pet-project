{{ config(materialized='view') }}

with source as (
    select * from {{ source('raw_data', 'ods_inventory_events') }}
    where event_type = 'procurement_created'
),
renamed as (
    select
        event_id,
        event_timestamp,
        
        -- ID
        (payload->>'shipment_id')::varchar as shipment_id,
        (payload->>'product_id')::varchar as product_id,
        (payload->>'vendor_id')::varchar as vendor_id,
        (payload->>'carrier_id')::varchar as carrier_id,
        (payload->>'arrival_location_id')::varchar as arrival_location_id,
        
        -- Pipeline dates
        (payload->>'order_date')::date as order_date,
        (payload->>'shipment_departure_date')::date as shipment_departure_date,
        (payload->>'shipment_arrival_date')::date as shipment_arrival_date,
        
        -- Financial and quantitative indicators
        (payload->>'vendor_invoice_number')::varchar as vendor_invoice_number,
        (payload->>'payment_check_number')::varchar as payment_check_number,
        (payload->>'payment_amount')::numeric(10, 2) as payment_amount,
        (payload->>'product_quantity')::integer as product_quantity,
        
        loaded_at
    from source
)
select * from renamed