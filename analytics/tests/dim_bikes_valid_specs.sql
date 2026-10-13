-- Проверка адекватности технических характеристик и цен в справочнике байков
select
    bike_sk,
    bike_natural_key,
    model_year,
    hourse_power,
    engine_volume_cc,
    procurement_price
from {{ ref('dim_bike') }}
where procurement_price <= 0
   or engine_volume_cc <= 0
   or hourse_power <= 0
   or model_year < 1990
   or model_year > extract(year from current_date) + 1