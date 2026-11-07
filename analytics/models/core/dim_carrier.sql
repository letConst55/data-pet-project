{{
    config(
        materialized='table',
        schema='core'
    )
}}

with source as (
    -- seed file
    select * from {{ ref('df_carriers') }}
),

final as (
    select
        -- technical fields
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,

        -- Surrogate primary key (PK)
        {{ dbt_utils.generate_surrogate_key(['carrier_id']) }} as carrier_sk,
        
        -- Natural key (NK)
        carrier_id as carrier_natural_key,

        -- Carrier attributes
        carrier_name,
        is_external_carrier_flag,
        carrier_type,
        carrier_score,
        carrier_status
    from source
)

select * from final