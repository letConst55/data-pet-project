{{ config(materialized='view') }}

with source as (
    select * from {{ source('raw_data', 'ods_inventory_events') }}
    where event_type = 'procurement_created'
),
renamed as (
    select
        event_id,
        event_timestamp,
        
        {{ json_extract('payload', 'shipment_id', 'varchar') }} as shipment_id,
        {{ json_extract('payload', 'product_id', 'varchar') }} as product_id,
        {{ json_extract('payload', 'vendor_id', 'varchar') }} as vendor_id,
        {{ json_extract('payload', 'carrier_id', 'varchar') }} as carrier_id,
        {{ json_extract('payload', 'arrival_location_id', 'varchar') }} as arrival_location_id,
        {{ json_extract('payload', 'order_date', 'date') }} as order_date,
        {{ json_extract('payload', 'shipment_departure_date', 'date') }} as shipment_departure_date,
        {{ json_extract('payload', 'shipment_arrival_date', 'date') }} as shipment_arrival_date,
        {{ json_extract('payload', 'vendor_invoice_number', 'varchar') }} as vendor_invoice_number,
        {{ json_extract('payload', 'payment_check_number', 'varchar') }} as payment_check_number,
        {{ json_extract('payload', 'payment_amount', 'numeric(10, 2)') }} as payment_amount,
        {{ json_extract('payload', 'product_quantity', 'integer') }} as product_quantity,
        
        loaded_at
    from source
)
select * from renamed