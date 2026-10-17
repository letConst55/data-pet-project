with fct as (
    select * from {{ ref('fct_repair') }}
),
dim_emp as (
    select * from {{ ref('dim_employee') }}
),
dim_loc as (
    select * from {{ ref('dim_location') }}
),

-- 1. Хронология пайплайна ремонта
test_date_chronology as (
    select
        repair_sk,
        'invalid_date_chronology' as error_reason
    from fct
    where transportation_start_date > repair_start_date
       or repair_start_date > repair_end_date
       or repair_end_date > transportation_end_date
),

-- 2. Проверка адекватности финансов
test_financials as (
    select
        repair_sk,
        'invalid_financial_amounts' as error_reason
    from fct
    where coalesce(invoice_total_amount, 0) < 0
       or coalesce(invoice_discount_amount, 0) < 0
       or coalesce(invoice_discount_amount, 0) > coalesce(invoice_total_amount, 0)
),

-- 3. Допуски сотрудников (право принимать байк в ремонт)
test_employee_flags as (
    select
        f.repair_sk,
        'employee_cannot_repair' as error_reason
    from fct f
    left join dim_emp e on f.employee_sk = e.employee_sk
    where e.can_workshop_repair_flg = false
),

-- 4. Статусы локаций (приемка в магазине, ремонт в гараже)
test_location_flags as (
    select
        f.repair_sk,
        'invalid_location_roles' as error_reason
    from fct f
    left join dim_loc shop on f.location_shop_sk = shop.location_sk
    left join dim_loc garage on f.location_garage_sk = garage.location_sk
    where shop.is_shop_flag = false
       or garage.is_garage_flag = false
)

-- Объединяем все проверки
select * from test_date_chronology
union all
select * from test_financials
union all
select * from test_employee_flags
union all
select * from test_location_flags