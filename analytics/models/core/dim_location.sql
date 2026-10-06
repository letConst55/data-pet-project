{{
    config(
        materialized='table',
        schema='core'
    )
}}

with source as (
    select * from {{ ref('df_locations') }}
),

final as (
    select
        -- Технические поля пайплайна
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,

        -- Суррогатный первичный ключ локации (PK)
        {{ dbt_utils.generate_surrogate_key(['location_id']) }} as location_id,

        -- Натуральный бизнес-ключ локации (NK)
        location_id::varchar as location_natural_key,

        -- Атрибуты локации
        title::varchar as title,
        full_address::varchar as full_address,
        post_index::varchar as post_index,

        -- Флаги принадлежности точки к отделам бизнеса
        is_garage_flag::boolean as is_garage_flag,
        is_shop_flag::boolean as is_shop_flag,
        is_warehouse_flag::boolean as is_warehouse_flag
    from source
)

select * from final