{{
    config(
        materialized='table',
        schema='core'
    )
}}

with source as (
    -- seeeeeeeeeeeeed file
    select * from {{ ref('df_vendors') }}
),

final as (
    select
        -- technical fields
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,

        -- Surrogate primary key (PK)
        {{ dbt_utils.generate_surrogate_key(['vendor_id']) }} as vendor_sk,
        
        -- Natural key (NK)
        vendor_id as vendor_natural_key,

        -- Vendor attributes
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