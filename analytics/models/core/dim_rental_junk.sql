{{
    config(
        materialized='table',
        schema='core'
    )
}}

-- We define two possible states for the flag
with boolean_values as (
    select true as flag_value
    union all
    select false as flag_value
),

-- We generate all 16 possible combinations using a Cartesian product
combinations as (
    select
        h.flag_value as helmet_damage_flag,
        f.flag_value as field_service_flag,
        r.flag_value as rent_extend_flag,
        b.flag_value as bike_exchange_flag
    from boolean_values h
    cross join boolean_values f
    cross join boolean_values r
    cross join boolean_values b
),

final as (
    select
        -- technical fields
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,
        
        -- Surrogate primary key of flag combinations (PK)
        {{ dbt_utils.generate_surrogate_key([
            'helmet_damage_flag',
            'field_service_flag',
            'rent_extend_flag',
            'bike_exchange_flag'
        ]) }} as rental_junk_sk,
        
        -- Junk attributes
        helmet_damage_flag,
        field_service_flag,
        rent_extend_flag,
        bike_exchange_flag,
        
        case 
            when helmet_damage_flag or field_service_flag or bike_exchange_flag 
            then 'Problematic return' 
            else 'Normal return' 
        end as return_status_category
        
    from combinations
)

select * from final