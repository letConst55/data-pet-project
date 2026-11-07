/*
-------------------------------------------------------------------------------------------------------
Test Name: fct_shop_order_business_logic
Description: 
    Comprehensive business logic validation for the Transactional fact table tracking 
    retail store purchases and tuning services. This test consolidates 5 independent checks 
    into a single CTE-based script.

Business Rules Validated:
    1. Financial Mathematics: The basic amount must precisely equal the total amount paid plus 
       the applied discount. No negative amounts are allowed.
       - Failure Example: A cashier mistakenly enters a $200 discount on a $150 helmet, resulting 
         in a negative total payment and breaking daily revenue aggregations.
    2. Quantity Validations: The quantity of purchased items in a single receipt line must be > 0.
       - Failure Example: A barcode scanner glitches and registers 0 units of a product, creating 
         a dummy transaction that artificially inflates the store's conversion rate.
    3. Employee Permissions: The employee processing the transaction must possess the `can_sell_retail_flg`.
       - Failure Example: A mechanic rings up a customer using their own garage credentials instead 
         of the cashier's, messing up the sales commission reports.
    4. Location Roles: Retail purchases can only occur at locations designated as shops (`is_shop_flag` = true).
       - Failure Example: An inventory transfer between two remote garages is accidentally logged 
         as a retail customer purchase.
    5. Tuning Logic: By business definition, a tuning or installation service is performed on a single 
       asset at a time. The quantity for tuning services must strictly be 1.
       - Failure Example: A cashier bills "3 x Engine Upgrades" on a single receipt line instead of 
         itemizing them, breaking the workshop's capacity tracking.

Output: 
    Returns `shop_order_sk` and `order_id` alongside an `error_reason` flag for any violated rule.
-------------------------------------------------------------------------------------------------------
*/

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

-- 1. Financial mathematics check
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

-- 2. Item quantity check
test_quantities as (
    select
        shop_order_sk,
        order_id,
        'zero_or_negative_qty' as error_reason
    from fct
    where cnt_products <= 0
),

-- 3. Employee permissions check (authorization to sell)
test_employee_flags as (
    select
        f.shop_order_sk,
        f.order_id,
        'employee_cannot_sell' as error_reason
    from fct f
    left join dim_emp e on f.employee_sk = e.employee_sk
    where e.can_sell_retail_flg = false
),

-- 4. Location type check (must be a shop)
test_location_flags as (
    select
        f.shop_order_sk,
        f.order_id,
        'location_is_not_a_shop' as error_reason
    from fct f
    left join dim_loc l on f.location_sk = l.location_sk
    where l.is_shop_flag = false
),

-- 5. Tuning logic (the service is provided in a single instance per receipt line)
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

-- Combine all validation results
select * from test_financials
union all
select * from test_quantities
union all
select * from test_employee_flags
union all
select * from test_location_flags
union all
select * from test_tuning_logic