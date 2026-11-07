{{
    config(
        materialized='table',
        schema='core'
    )
}}

with source as (
    select * from {{ ref('df_bikes') }}
),

final as (
    select
        -- technical fields
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,

        -- Surrogate primary key (PK)
        {{ dbt_utils.generate_surrogate_key(['bike_id']) }} as bike_sk,
        
        -- Natural key (NK)
        bike_id::text as bike_natural_key,

        -- Bike attributes
        "WIN_number" as win_number,
        plate_number,
        title,
        type,
        model_year,
        color,
        brand,
        hourse_power,
        "engine_volume (cc)" as engine_volume_cc,
        gearbox_type,
        usb_charging_availability,
        procurement_price
    from source
)

select * from final