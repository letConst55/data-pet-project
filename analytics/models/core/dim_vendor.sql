{{
    config(
        materialized='table',
        schema='core'
    )
}}

with source as (
    -- Обращаемся к загруженному seed-файлу
    select * from {{ ref('df_vendors') }}
),

final as (
    select
        -- Технические поля пайплайна
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,

        -- Суррогатный первичный ключ (PK) 
        {{ dbt_utils.generate_surrogate_key(['vendor_id']) }} as vendor_sk,
        
        -- Натуральный бизнес-ключ (NK)
        vendor_id as vendor_natural_key,

        -- Атрибуты вендоров
        vendor_name,
        is_foreign_flag,
        vendor_score,
        vendor_zip_postal_code,
        vendor_address,
        vendor_mobile
    from source
)
select 
    * 
from final