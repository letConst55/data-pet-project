{{
    config(
        materialized='incremental',
        unique_key='procurement_sk',
        schema='core'
    )
}}

with new_procurements_raw as (
    select * from {{ ref('stg_inventory_procurement_created') }}
    
    {% if is_incremental() %}
        -- Забираем только новые или обновленные события поставки
        where event_timestamp > (select coalesce(max(event_timestamp), '1900-01-01'::timestamp) from {{ this }})
    {% endif %}
),

-- Дедупликация (оставляем самую свежую версию пайплайна для каждой позиции в поставке)
new_procurements as (
    select distinct on (shipment_id, product_id)
        *
    from new_procurements_raw
    order by shipment_id, product_id, event_timestamp desc, loaded_at desc
),

final as (
    select
        -- Технические поля
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,
        
        -- Суррогатный первичный ключ факта (PK)
        {{ dbt_utils.generate_surrogate_key(['p.shipment_id', 'prod.product_sk']) }} as procurement_sk,

        -- Degenerate Dimensions (DD)
        p.shipment_id,
        p.vendor_invoice_number,
        p.payment_check_number,

        -- Внешние ключи (все справочники SCD1, поэтому простой JOIN без дат)
        prod.product_sk,
        v.vendor_sk,
        c.carrier_sk,
        l.location_sk as arrival_location_sk,

        -- Даты пайплайна поставки
        p.order_date,
        p.shipment_departure_date,
        p.shipment_arrival_date,
        
        -- Техническое поле для инкремента
        p.event_timestamp,

        -- Факты (Метрики)
        p.product_quantity,
        p.payment_amount

    from new_procurements p
    
    -- Лукапы SCD1
    left join {{ ref('dim_product') }} prod 
      on p.product_id = prod.product_natural_key
      
    left join {{ ref('dim_vendor') }} v 
      on p.vendor_id = v.vendor_natural_key
      
    left join {{ ref('dim_carrier') }} c 
      on p.carrier_id = c.carrier_natural_key
      
    left join {{ ref('dim_location') }} l 
      on p.arrival_location_id = l.location_natural_key
)

-- Временно отсекаем возможные битые ссылки (Unknown Members)
select * from final
where product_sk is not null 
  and vendor_sk is not null