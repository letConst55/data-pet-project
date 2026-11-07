{{
    config(
        materialized='incremental',
        unique_key='service_event_sk',
        schema='core'
    )
}}

with new_service_events_raw as (
    select * from {{ ref('stg_field_service_performed') }}
    
    {% if is_incremental() %}
        -- Incremental load based on the event date
        where event_datetime > (select coalesce(max(event_datetime), '1900-01-01'::timestamp) from {{ this }})
    {% endif %}
),

-- Deduplication of raw events (protection against duplicates from Kafka/S3)
new_service_events as (
    select distinct on (service_event_id)
        *
    from new_service_events_raw
    order by service_event_id, event_datetime desc, loaded_at desc
),

final as (
    select
        -- Technical pipeline fields
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,
        
        -- Surrogate primary key for the event (PK)
        {{ dbt_utils.generate_surrogate_key(['s.service_event_id']) }} as service_event_sk,

        -- Degenerate Dimensions (DD)
        s.service_event_id,
        s.rental_id,

        -- FK: Client (SCD2 Point-in-Time Lookup)
        c.client_sk,

        -- FK: Mechanic (SCD2 Point-in-Time Lookup)
        e.employee_sk,

        -- FK: Bike (SCD1)
        b.bike_sk,

        -- Dates and times
        s.event_date,
        s.event_datetime,

        -- Fact attributes (Metrics and Categories)
        s.issue_category,
        s.resolution_action,
        s.client_fault_flag,
        s.service_cost_usd

    from new_service_events s

    -- 1. SCD2 Lookup: Client at the time the mechanic was called
    left join {{ ref('dim_client') }} c
      on s.client_id = c.client_natural_key
     and s.event_datetime >= c.row_effective_date
     and s.event_datetime < coalesce(c.row_expiration_date, '9999-12-31 23:59:59'::timestamp)

    -- 2. SCD2 Lookup: Mechanic at the time of dispatch
    left join {{ ref('dim_employee') }} e
      on s.employee_id = e.employee_natural_key
     and s.event_datetime >= e.row_effective_date
     and s.event_datetime < coalesce(e.row_expiration_date, '9999-12-31 23:59:59'::timestamp)

    -- 3. SCD1 Lookup: Bike
    left join {{ ref('dim_bike') }} b
      on s.bike_id = b.bike_natural_key
)

-- Temporarily filtering out broken joins caused by generator bugs
select * 
from final
--where client_sk is not null 
  --and employee_sk is not null