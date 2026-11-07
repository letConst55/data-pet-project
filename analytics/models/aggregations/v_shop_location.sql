{{
    config(
        materialized='view',
        schema='aggregations'
    )
}}

select
    location_sk as shop_location_sk, -- Role key
    location_natural_key,
    title,
    full_address,
    post_index,
    is_garage_flag,
    is_shop_flag,
    is_warehouse_flag
from {{ ref('dim_location') }}
where is_shop_flag = true