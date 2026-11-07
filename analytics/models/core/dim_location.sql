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
        -- technical fields
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,

        -- Surrogate primary key (PK)
        {{ dbt_utils.generate_surrogate_key(['location_id']) }} as location_sk,

        -- Natural key (NK)
        location_id::varchar as location_natural_key,

        -- Location attributes
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