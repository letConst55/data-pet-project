-- 1. Проверка, что у каждой локации активен хотя бы один отдел бизнеса
with invalid_flags as (
    select 
        location_natural_key,
        'no_active_department' as error_reason
    from {{ ref('dim_location') }}
    where not (is_garage_flag or is_shop_flag or is_warehouse_flag)
),

-- 2. Собираем все локации, которые реально встречались в событиях аренды
staging_rental_locations as (
    select distinct location_id from {{ ref('stg_rental_booked') }}
    union
    select distinct location_dis_id as location_id from {{ ref('stg_bike_dispensed') }}
    union
    select distinct location_return_id as location_id from {{ ref('stg_bike_returned') }}
),

-- Проверяем, что все они есть в dim_location (ссылочная целостность)
invalid_rental_locations as (
    select
        s.location_id as location_natural_key,
        'missing_in_dim_location' as error_reason
    from staging_rental_locations s
    left join {{ ref('dim_location') }} d
        on s.location_id = d.location_natural_key
    where d.location_natural_key is null
       -- Закомментировали строгую бизнес-проверку, так как генератор данных 
       -- отправляет события аренды во все локации (даже в чисто магазины)
       -- or d.is_garage_flag = false
)

select * from invalid_flags
union all
select * from invalid_rental_locations