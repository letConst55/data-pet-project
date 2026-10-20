with max_date as (
    select max(fact_end_date) as current_max_date
    from {{ ref('fct_client_bike_rent') }}
),
-- Подтягиваем натуральный ключ клиента из dim_client и флаги из dim_rental_junk
fct_with_nk as (
    select 
        f.rental_id,
        f.client_sk,
        c.client_natural_key, -- Натуральный ключ
        f.bike_sk,
        f.fact_end_date,
        j.rent_extend_flag,   -- Флаг теперь живет в мусорном измерении
        coalesce(f.fact_start_date, f.planned_start_date) as start_date
    from {{ ref('fct_client_bike_rent') }} f
    left join {{ ref('dim_client') }} c on f.client_sk = c.client_sk
    left join {{ ref('dim_rental_junk') }} j on f.rental_junk_sk = j.rental_junk_sk
),
extended as (
    select *
    from fct_with_nk
    where rent_extend_flag = true
      and fact_end_date < (select current_max_date from max_date)
),
subsequent as (
    select *
    from fct_with_nk
)

select e.rental_id
from extended e
left join subsequent s
  -- ИСПРАВЛЕНИЕ: Ищем следующую аренду по неизменному натуральному ключу
  on e.client_natural_key = s.client_natural_key 
 and e.bike_sk = s.bike_sk
 and s.start_date >= e.fact_end_date
where s.rental_id is null