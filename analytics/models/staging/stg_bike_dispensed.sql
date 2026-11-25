{{ config(materialized='view') }}

with source as (
    select * from {{ source('raw_data', 'ods_mechanic_events') }}
    where event_type = 'bike_dispensed'
),
renamed as (
    select
        event_id,
        event_timestamp,
        {{ json_extract('payload', 'rental_id', 'varchar') }} as rental_id,
        {{ json_extract('payload', 'employee_disp_id', 'varchar') }} as employee_disp_id,
        {{ json_extract('payload', 'location_dis_id', 'varchar') }} as location_dis_id,
        {{ json_extract('payload', 'fact_start_date', 'date') }} as fact_start_date,
        {{ json_extract('payload', 'fact_start_datetime', 'timestamp') }} as fact_start_datetime,
        {{ json_extract('payload', 'actual_start_mileage', 'numeric(10, 2)') }} as actual_start_mileage,
        {{ json_extract('payload', 'fuel_start_percent', 'numeric(10, 2)') }} as fuel_start_percent,
        {{ json_extract('payload', 'pre_rental_condition_score', 'int') }} as pre_rental_condition_score,
        {{ json_extract('payload', 'helmets_issued_qty', 'int') }} as helmets_issued_qty,
        loaded_at
    from source
)
select * from renamed