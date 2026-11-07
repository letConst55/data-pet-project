{{
    config(
        materialized='incremental',
        unique_key='repair_sk',
        schema='core'
    )
}}

with new_repairs_raw as (
    select * from {{ ref('stg_external_repair_completed') }}
    
    {% if is_incremental() %}
        -- Extracting new events from the time of the last increment
        where event_datetime > (select coalesce(max(event_datetime), '1900-01-01'::timestamp) from {{ this }})
    {% endif %}
),

-- Deduplication of raw events
new_repairs as (
    select distinct on (repair_id)
        *
    from new_repairs_raw
    order by repair_id, event_datetime desc, loaded_at desc
),

final as (
    select
        -- Technical pipeline fields
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,
        
        -- Surrogate primary key for the fact (PK)
        {{ dbt_utils.generate_surrogate_key(['r.repair_id']) }} as repair_sk,

        -- Degenerate Dimensions (DD)
        r.repair_id,
        r.order_id,          -- Can be NULL if no spare parts were purchased

        -- Foreign keys
        c.client_sk,         -- SCD2
        e.employee_sk,       -- SCD2
        cr.carrier_sk,       -- SCD1
        ls.location_sk as location_shop_sk,   -- SCD1 (the shop that received the bike)
        lg.location_sk as location_garage_sk, -- SCD1 (the repair workshop)

        -- Repair details
        r.bike_name,

        -- Repair pipeline dates
        r.transportation_start_date,
        r.repair_start_date,
        r.repair_end_date,
        r.transportation_end_date,
        r.event_datetime,

        -- Metrics
        r.invoice_total_amount,
        r.invoice_discount_amount

    from new_repairs r

    -- 1. SCD2 Lookup: Client at the time of the event
    left join {{ ref('dim_client') }} c
      on r.client_id = c.client_natural_key
     and r.event_datetime >= c.row_effective_date
     and r.event_datetime < coalesce(c.row_expiration_date, '9999-12-31 23:59:59'::timestamp)

    -- 2. SCD2 Lookup: Employee (who accepted the bike) at the time of the event
    left join {{ ref('dim_employee') }} e
      on r.employee_id = e.employee_natural_key
     and r.event_datetime >= e.row_effective_date
     and r.event_datetime < coalesce(e.row_expiration_date, '9999-12-31 23:59:59'::timestamp)

    -- 3. SCD1 Lookup: Carrier
    left join {{ ref('dim_carrier') }} cr
      on r.carrier_id = cr.carrier_natural_key

    -- 4. SCD1 Lookup: Location (Drop-off shop)
    left join {{ ref('dim_location') }} ls
      on r.location_shop_id = ls.location_natural_key

    -- 5. SCD1 Lookup: Location (Repair workshop)
    left join {{ ref('dim_location') }} lg
      on r.location_garage_id = lg.location_natural_key
)

-- Filtering out Unknown Members (if any slipped through)
select * from final
--where client_sk is not null 
  --and employee_sk is not null