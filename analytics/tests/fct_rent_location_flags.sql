-- Проверка, что выдача и возврат происходят только на локациях с warehouse флагом
with invalid_locations as (
    select 
        f.rental_id,
        ld.is_warehouse_flag as disp_warehouse_flag,
        lr.is_warehouse_flag as ret_warehouse_flag
    from {{ ref('fct_client_bike_rent') }} f
    left join {{ ref('dim_location') }} ld on f.location_dis_id = ld.location_sk
    left join {{ ref('dim_location') }} lr on f.location_return_id = lr.location_sk
    -- Исключаем неполные пайплайны (где возврата еще не было)
)

select rental_id 
from invalid_locations
where disp_warehouse_flag = false
   or ret_warehouse_flag = false