/*
-------------------------------------------------------------------------------------------------------
Test Name: fct_repair_business_logic
Description: 
    Comprehensive business logic validation for the Accumulating Snapshot fact table tracking 
    external client bike repairs. This test consolidates 4 independent checks into a single 
    CTE-based script for efficient execution.

Business Rules Validated:
    1. Pipeline Chronology: The repair lifecycle must strictly follow a chronological order: 
       inbound transport start <= active repair start <= active repair end <= outbound transport end.
       - Failure Example: A mechanic mistakenly logs a repair as finished on Thursday, but the inbound 
         carrier didn't actually deliver the bike to the garage until Friday.
    2. Financial Adequacy: The invoice total and applied discounts cannot be negative. Furthermore, 
       the discount amount cannot exceed the total invoice amount.
       - Failure Example: A promotional discount code of $50 is applied to a minor $30 repair, 
         resulting in a negative invoice total that breaks revenue aggregations.
    3. Employee Permissions: The employee responsible for accepting and handling the repair MUST possess 
       the `can_workshop_repair_flg`.
       - Failure Example: A retail sales assistant without mechanical certification signs off on a 
         complex engine overhaul intake form.
    4. Location Roles: Bikes must be dropped off at a retail shop (`is_shop_flag` = true) and 
       actually repaired in a dedicated workshop (`is_garage_flag` = true).
       - Failure Example: A client drops off their broken bike at a remote warehouse location that 
         has no retail storefront or customer reception area.

Output: 
    Returns `repair_sk` alongside an `error_reason` flag for any violated rule.
-------------------------------------------------------------------------------------------------------
*/

with fct as (
    select * from {{ ref('fct_repair') }}
),
dim_emp as (
    select * from {{ ref('dim_employee') }}
),
dim_loc as (
    select * from {{ ref('dim_location') }}
),

-- 1. Repair pipeline chronology
test_date_chronology as (
    select
        repair_sk,
        'invalid_date_chronology' as error_reason
    from fct
    where transportation_start_date > repair_start_date
       or repair_start_date > repair_end_date
       or repair_end_date > transportation_end_date
),

-- 2. Verification of financial adequacy
test_financials as (
    select
        repair_sk,
        'invalid_financial_amounts' as error_reason
    from fct
    where coalesce(invoice_total_amount, 0) < 0
       or coalesce(invoice_discount_amount, 0) < 0
       or coalesce(invoice_discount_amount, 0) > coalesce(invoice_total_amount, 0)
),

-- 3. Employee permissions (authorization to accept/perform repairs)
test_employee_flags as (
    select
        f.repair_sk,
        'employee_cannot_repair' as error_reason
    from fct f
    left join dim_emp e on f.employee_sk = e.employee_sk
    where e.can_workshop_repair_flg = false
),

-- 4. Location statuses (drop-off at a shop, repair in a garage)
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

-- Combine all validation results
select * from test_date_chronology
union all
select * from test_financials
union all
select * from test_employee_flags
union all
select * from test_location_flags