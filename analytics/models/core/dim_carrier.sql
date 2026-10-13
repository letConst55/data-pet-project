{{
    config(
        materialized='table',
        schema='core'
    )
}}

with source as (
    -- Обращаемся к загруженному seed-файлу
    select * from {{ ref('df_carriers') }}
),

final as (
    select
        -- Технические поля пайплайна
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,

        -- Суррогатный первичный ключ (PK) по схеме
        {{ dbt_utils.generate_surrogate_key(['carrier_id']) }} as carrier_id,
        
        -- Натуральный бизнес-ключ (NK)
        carrier_id as carrier_natural_key,

        -- Атрибуты перевозчика
        carrier_name,
        is_external_carrier_flag,
        carrier_type,
        carrier_score,
        carrier_status
    from source
)

select * from final