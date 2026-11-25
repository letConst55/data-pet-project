{{
    config(
        materialized='table',
        schema='core'
    )
}}

with source as (
    select
        "bike_id" as bike_id,
        "WIN_number" as win_number,
        "plate_number" as plate_number,
        "title" as title,
        "type" as type,
        "model_year" as model_year,
        "color" as color,
        "brand" as brand,
        "hourse_power" as hourse_power,
        "engine_volume (cc)" as engine_volume_cc,
        "gearbox_type" as gearbox_type,
        "usb_charging_availability" as usb_charging_availability,
        "procurement_price" as procurement_price
    from {{ ref('df_bikes') }}
),

final as (
    select
        -- technical fields
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,

        -- Surrogate primary key (PK)
        {{ dbt_utils.generate_surrogate_key(['bike_id']) }} as bike_sk,

        -- Natural key (NK)
        bike_id::varchar as bike_natural_key,

        -- Bike attributes
        win_number,
        plate_number,
        title,
        type,
        model_year,
        color,
        brand,
        hourse_power,
        engine_volume_cc,
        gearbox_type,
        usb_charging_availability,
        procurement_price
    from source
)

select * from final