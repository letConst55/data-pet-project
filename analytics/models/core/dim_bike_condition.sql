{{
    config(
        materialized='table',
        schema='core'
    )
}}

with source as (
    select * from {{ ref('df_bike_conditions') }}
),

final as (
    select
        -- Технические поля пайплайна
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,

        -- Первичный ключ мини-измерения (оценка от 1 до 10)
        rental_condition_score::int as rental_condition_score,

        -- Атрибуты состояния узлов по регламенту
        engine_condition::varchar as engine_condition,
        plastic_condition::varchar as plastic_condition,
        suspension_condition::varchar as suspension_condition,
        mileage_band::varchar as mileage_band
    from source
)

select * from final
order by rental_condition_score desc