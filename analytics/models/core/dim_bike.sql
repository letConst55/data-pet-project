{{
    config(
        materialized='table',
        schema='core'
    )
}}

with source as (
    -- Обращаемся к загруженному seed-файлу
    select * from {{ ref('df_bikes') }}
),

final as (
    select
        -- Технические поля пайплайна
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,

        -- Суррогатный первичный ключ (PK) по схеме
        {{ dbt_utils.generate_surrogate_key(['bike_id']) }} as bike_id,
        
        -- Натуральный бизнес-ключ (NK)
        bike_id as bike_natural_key,

        -- Атрибуты байка
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