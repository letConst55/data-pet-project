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
        -- Incremental logic based on the snapshot creation date
        where event_timestamp > (select coalesce(max(snapshot_datetime), '1900-01-01'::timestamp) from {{ this }})
    {% endif %}
),

-- Deduplication: guaranteeing only 1 record remains for a single Week+Product+Location combination
new_snapshots as (
    select distinct on (week_year, product_id, location_id)
        *
    from new_snapshots_raw
    order by week_year, product_id, location_id, event_timestamp desc, loaded_at desc
),

final as (
    select
        -- Technical pipeline fields
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,
        
        -- Surrogate primary key for the fact (PK)
        {{ dbt_utils.generate_surrogate_key(['s.week_year', 'p.product_sk', 'l.location_sk']) }} as inventory_snapshot_sk,

        -- Foreign keys
        p.product_sk,
        l.location_sk,
        
        -- Calendar link (FK) based on the snapshot creation date
        s.event_timestamp::date as snapshot_date_key,

        -- Degenerate Dimension (DD)
        s.week_year,

        -- Facts (Inventory metrics)
        s.product_quantity,

        -- Flags and statuses (Fact attributes)
        s.available_flag,
        s.isin_shipment_flag,
        s.planned_delivery_date,

        -- Technical field for the incremental load
        s.event_timestamp as snapshot_datetime

    from new_snapshots s

    -- SCD1 Lookup: Product
    left join {{ ref('dim_product') }} p
      on s.product_id = p.product_natural_key

    -- SCD1 Lookup: Location (Warehouse/Shop)
    left join {{ ref('dim_location') }} l
      on s.location_id = l.location_natural_key
)

-- Filtering out broken joins
select * from final
--where product_sk is not null 
  --and location_sk is not null