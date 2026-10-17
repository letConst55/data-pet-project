with fct as (
    select * from {{ ref('fct_shop_order') }}
),
dim_emp as (
    select * from {{ ref('dim_employee') }}
),
dim_loc as (
    select * from {{ ref('dim_location') }}
),
dim_prod as (
    select * from {{ ref('dim_product') }}
),

-- 1. Проверка финансовой математики
test_financials as (
    select
        shop_order_sk,
        order_id,
        'math_mismatch' as error_reason
    from fct
    where abs(basic_amount - (total_amount + discount_amount)) > 0.01
       or total_amount < 0
       or discount_amount < 0
),

-- 2. Проверка количества товаров
test_quantities as (
    select
        shop_order_sk,
        order_id,
        'zero_or_negative_qty' as error_reason
    from fct
    where cnt_products <= 0
),

-- 3. Проверка допусков сотрудника (наличие прав продавать)
test_employee_flags as (
    select
        f.shop_order_sk,
        f.order_id,
        'employee_cannot_sell' as error_reason
    from fct f
    left join dim_emp e on f.employee_sk = e.employee_sk
    where e.can_sell_retail_flg = false
),

-- 4. Проверка типа локации (есть ли там магазин)
test_location_flags as (
    select
        f.shop_order_sk,
        f.order_id,
        'location_is_not_a_shop' as error_reason
    from fct f
    left join dim_loc l on f.location_sk = l.location_sk
    where l.is_shop_flag = false
),

-- 5. Логика тюнинга (услуга оказывается в единственном экземпляре в рамках позиции чека)
test_tuning_logic as (
    select
        f.shop_order_sk,
        f.order_id,
        'tuning_qty_exceeds_one' as error_reason
    from fct f
    left join dim_prod p on f.product_sk = p.product_sk
    where p.is_tuning_flag = true 
      and f.cnt_products > 1
)

-- Объединяем все проверки
select * from test_financials
union all
select * from test_quantities
union all
select * from test_employee_flags
union all
select * from test_location_flags
union all
select * from test_tuning_logic