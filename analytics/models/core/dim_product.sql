{{
    config(
        materialized='table',
        schema='core'
    )
}}

with source as (
    -- seed file
    select * from {{ ref('df_products') }}
),

final as (
    select
        -- technical fields
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,

        -- Surrogate primary key (PK)
        {{ dbt_utils.generate_surrogate_key(['product_id']) }} as product_sk,
        
        -- Natural key (NK)
        product_id as product_natural_key,

        -- Product attributes
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