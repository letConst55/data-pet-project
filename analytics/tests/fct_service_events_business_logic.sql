with fct as (
    select * from {{ ref('fct_service_events') }}
),
dim_emp as (
    select * from {{ ref('dim_employee') }}
),
rent_fct as (
    select distinct rental_id from {{ ref('fct_client_bike_rent') }}
),

-- 1. Допуски сотрудников (право на выездной ремонт)
test_employee_flags as (
    select
        f.service_event_sk,
        f.service_event_id,
        'employee_cannot_field_service' as error_reason
    from fct f
    left join dim_emp e on f.employee_sk = e.employee_sk
    where e.can_field_service_flg = false
),

-- 2. Адекватность стоимости выезда
test_service_cost as (
    select
        service_event_sk,
        service_event_id,
        'invalid_service_cost' as error_reason
    from fct
    where coalesce(service_cost_usd, 0) <= 0
),

-- 3. Ссылочная целостность с таблицей аренды
-- (Выезд всегда привязан к конкретному факту аренды, который должен существовать)
test_rental_existence as (
    select
        f.service_event_sk,
        f.service_event_id,
        'orphan_rental_id' as error_reason
    from fct f
    left join rent_fct r on f.rental_id = r.rental_id
    where r.rental_id is null
),

-- 4. Консистентность категорий проблем и решений
test_valid_enums as (
    select
        service_event_sk,
        service_event_id,
        'invalid_category_or_action' as error_reason
    from fct
    where issue_category not in ('dead_battery', 'flat_tire', 'engine_check', 'lost_key')
       or resolution_action not in ('fixed_on_site', 'bike_replaced', 'towed_to_shop')
)

-- Объединяем все проверки
select * from test_employee_flags
union all
select * from test_service_cost
union all
select * from test_rental_existence
union all
select * from test_valid_enums