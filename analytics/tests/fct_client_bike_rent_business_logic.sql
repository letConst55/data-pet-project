/*
-------------------------------------------------------------------------------------------------------
Test Name: fct_client_bike_rent_business_logic
Description: 
    Comprehensive business logic validation for the main Accumulating Snapshot fact table 
    (Bike Rentals). Consolidates 7 independent checks into a single CTE-based script for efficient 
    debugging and root-cause analysis.

Business Rules Validated:
    1. Timeline Chronology: Planned start date must precede or equal planned end date.
       Actual end date cannot be earlier than actual start date.
       - Failure Example: A mechanic mistakenly logs a bike return before it was officially dispensed.
    2. Location Types: Dispense and return locations must strictly have the `is_warehouse_flag` = true.
       - Failure Example: A bike is dropped off at a pure retail shop (no parking/garage space).
    3. Employee Permissions: Employees who dispense or receive bikes must possess the 
       `can_dispense_return_flg`.
       - Failure Example: A retail cashier without technical training processes a bike return.
    4. Financial Integrity: The total rental amount must perfectly match the formula: 
       (Days * Daily Rate) - Discount + Penalty.
       - Failure Example: A discount is applied incorrectly, resulting in a negative total amount.
    5. Odometer Logic: Actual end mileage cannot be less than actual start mileage.
       - Failure Example: A typo in the mechanic's app records 15,000 km at start and 1,500 km at return.
    6. Condition Scoring: The assigned condition score (1-10) must not exceed the maximum allowed 
       score for the bike's current mileage band.
       - Failure Example: A bike with 70,000 km is rated '10 (Factory New)', which violates the 
         maintenance standard.
    7. Deposit Deductions: If no deposit was deducted ($0), the reason code MUST be 'none'.
       - Failure Example: The reason is logged as 'helmet_damage', but the client was fully refunded.

Output: 
    Returns `rental_id` alongside an `error_reason` flag for any violated business rule.
-------------------------------------------------------------------------------------------------------
*/

with fct as (
    select * from {{ ref('fct_client_bike_rent') }}
),
dim_emp as (
    select * from {{ ref('dim_employee') }}
),
dim_loc as (
    select * from {{ ref('dim_location') }}
),

-- 1. Date Chronology Check
test_dates_logic as (
    select
        rental_id,
        'invalid_date_chronology' as error_reason
    from fct
    where planned_start_date > planned_end_date
       or (fact_start_date is not null 
           and fact_end_date is not null 
           and fact_start_date > fact_end_date)
),

-- 2. Location Roles Check (Must be a warehouse/rental point)
test_location_flags as (
    select 
        f.rental_id,
        'invalid_location_role' as error_reason
    from fct f
    left join dim_loc ld on f.location_dis_id = ld.location_sk
    left join dim_loc lr on f.location_return_id = lr.location_sk
    where ld.is_warehouse_flag = false
       or lr.is_warehouse_flag = false
),

-- 3. Employee Permissions Check
test_employee_flags as (
    select 
        f.rental_id,
        'employee_lacks_permissions' as error_reason
    from fct f
    left join dim_emp ed on f.employee_disp_id = ed.employee_sk
    left join dim_emp er on f.employee_return_id = er.employee_sk
    where ed.can_dispense_return_flg = false
       or er.can_dispense_return_flg = false
),

-- 4. Financial Calculations Check
test_financial_logic as (
    select 
        rental_id,
        'financial_math_mismatch' as error_reason
    from fct
    where fact_end_date is not null
      and total_amount != greatest(
          0.0, 
          (fact_end_date - fact_start_date) * rental_price_daily 
          - discount_amount 
          + coalesce(deposit_deducted_amount, 0)
      )
),

-- 5. Mileage Consistency Check
test_mileage_logic as (
    select 
        rental_id,
        'negative_trip_mileage' as error_reason
    from fct
    where fact_end_date is not null
      and actual_start_mileage > actual_end_mileage
),

-- 6. Condition Score vs Mileage Band Check
test_condition_mileage as (
    select 
        rental_id,
        'score_exceeds_mileage_band' as error_reason
    from fct
    where pre_rental_condition_score > case
            when actual_start_mileage >= 65000 then 1
            when actual_start_mileage >= 50000 then 2
            when actual_start_mileage >= 40000 then 3
            when actual_start_mileage >= 32000 then 4
            when actual_start_mileage >= 25000 then 5
            when actual_start_mileage >= 18000 then 6
            when actual_start_mileage >= 12000 then 7
            when actual_start_mileage >= 7000 then 8
            when actual_start_mileage >= 3000 then 9
            else 10
        end
       or (post_rental_condition_score is not null and post_rental_condition_score > case
            when actual_end_mileage >= 65000 then 1
            when actual_end_mileage >= 50000 then 2
            when actual_end_mileage >= 40000 then 3
            when actual_end_mileage >= 32000 then 4
            when actual_end_mileage >= 25000 then 5
            when actual_end_mileage >= 18000 then 6
            when actual_end_mileage >= 12000 then 7
            when actual_end_mileage >= 7000 then 8
            when actual_end_mileage >= 3000 then 9
            else 10
        end)
),

-- 7. Deposit Deduction Reason Check
test_deposit_reason as (
    select 
        rental_id,
        'invalid_deduction_reason' as error_reason
    from fct
    where coalesce(deposit_deducted_amount, 0) = 0
      and deduction_reason_code != 'none'
)

-- Combine all validation results
select * from test_dates_logic
union all
select * from test_location_flags
union all
select * from test_employee_flags
union all
select * from test_financial_logic
union all
select * from test_mileage_logic
union all
select * from test_condition_mileage
union all
select * from test_deposit_reason