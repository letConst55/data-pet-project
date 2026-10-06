-- Тест проверяет, что:
-- 1. Все клиенты из стейджинга попали в витрину
-- 2. У каждого клиента в витрине есть ровно 1 активная запись (current_row_indicator = true)

with stg_clients as (
    select distinct client_id as client_natural_key
    from {{ ref('stg_client_profile_updated') }}
),

dim_summary as (
    select
        client_natural_key,
        count(*) filter (where current_row_indicator = true) as active_rows_cnt
    from {{ ref('dim_client') }}
    group by client_natural_key
)

select
    coalesce(s.client_natural_key, d.client_natural_key) as client_natural_key,
    s.client_natural_key as in_staging,
    d.client_natural_key as in_dim,
    coalesce(d.active_rows_cnt, 0) as active_rows_cnt
from stg_clients s
full outer join dim_summary d
    on s.client_natural_key = d.client_natural_key
where s.client_natural_key is null          -- Клиент есть в витрине, но нет в стейджинге
   or d.client_natural_key is null          -- Клиент потерялся по пути из стейджинга в витрину
   or d.active_rows_cnt != 1                -- У клиента 0 или >1 открытых версий