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
        -- Extracting only new or updated supply events
        where event_timestamp > (select coalesce(max(event_timestamp), '1900-01-01'::timestamp) from {{ this }})
    {% endif %}
),

-- Deduplication (keeping the freshest pipeline version for each item in the shipment)
new_procurements as (
    select distinct on (shipment_id, product_id)
        *
    from new_procurements_raw
    order by shipment_id, product_id, event_timestamp desc, loaded_at desc
),

final as (
    select
        -- Technical fields
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,
        
        -- Surrogate primary key for the fact (PK)
        {{ dbt_utils.generate_surrogate_key(['p.shipment_id', 'prod.product_sk']) }} as procurement_sk,

        -- Degenerate Dimensions (DD)
        p.shipment_id,
        p.vendor_invoice_number,
        p.payment_check_number,

        -- Foreign keys (all dimensions are SCD1, so simple JOINs without dates)
        prod.product_sk,
        v.vendor_sk,
        c.carrier_sk,
        l.location_sk as arrival_location_sk,

        -- Procurement pipeline dates
        p.order_date,
        p.shipment_departure_date,
        p.shipment_arrival_date,
        
        -- Technical field for the incremental load
        p.event_timestamp,

        -- Facts (Metrics)
        p.product_quantity,
        p.payment_amount

    from new_procurements p
    
    -- SCD1 Lookups
    left join {{ ref('dim_product') }} prod 
      on p.product_id = prod.product_natural_key
      
    left join {{ ref('dim_vendor') }} v 
      on p.vendor_id = v.vendor_natural_key
      
    left join {{ ref('dim_carrier') }} c 
      on p.carrier_id = c.carrier_natural_key
      
    left join {{ ref('dim_location') }} l 
      on p.arrival_location_id = l.location_natural_key
)

-- Temporarily filtering out potential broken links (Unknown Members)
select * from final
--where product_sk is not null 
  --and vendor_sk is not null