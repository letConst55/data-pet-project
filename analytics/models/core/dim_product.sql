{{
    config(
        materialized='table',
        schema='core'
    )
}}

with source as (
    -- Обращаемся к загруженному seed-файлу
    select * from {{ ref('df_products') }}
),

final as (
    select
        -- Технические поля пайплайна
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,

        -- Суррогатный первичный ключ (PK) 
        {{ dbt_utils.generate_surrogate_key(['product_id']) }} as product_id,
        
        -- Натуральный бизнес-ключ (NK)
        product_id as product_natural_key,

        -- Атрибуты товаров
        title,
        level1_category,
        level2_category,
        manufactory,
        vendor,
        is_spare_flag,
        is_tuning_flag
    from source
)
select 
    * 
from final