/*
-------------------------------------------------------------------------------------------------------
Test Name: fct_service_events_business_logic
Description: 
    Comprehensive business logic validation for the Transactional fact table tracking 
    mechanic dispatches (field service) to active rentals. This test consolidates 4 independent 
    checks into a single CTE-based script.

Business Rules Validated:
    1. Employee Permissions: Mechanics dispatched to the field must possess the 
       `can_field_service_flg`.
       - Failure Example: A junior workshop assistant who does not hold a driver's license is 
         mistakenly dispatched in the rescue van.
    2. Service Cost Adequacy: The cost of the field service dispatch must be strictly greater than zero.
       - Failure Example: The mechanic app glitches and records a $0 rescue cost, heavily inflating 
         the perceived profitability of a problematic bike model.
    3. Cross-Fact Referential Integrity: A field service dispatch MUST be tied to a valid, existing 
       rental event in `fct_client_bike_rent`.
       - Failure Example: A mechanic creates a dummy rescue event to cover a personal errand, but 
         the logged rental ID does not exist in the main rental pipeline.
    4. Category Consistency: Issue categories and resolution actions must strictly match the 
       allowed generator enums to prevent analytics corruption.
       - Failure Example: A mechanic manually types "Flat tyre" instead of selecting the standard 
         'flat_tire' enum, causing the incident to drop out of BI dashboards.

Output: 
    Returns `service_event_sk` and `service_event_id` alongside an `error_reason` flag for 
    any violated rule.
-------------------------------------------------------------------------------------------------------
*/

with fct as (
    select * from {{ ref('fct_service_events') }}
),
dim_emp as (
    select * from {{ ref('dim_employee') }}
),
rent_fct as (
    select distinct rental_id from {{ ref('fct_client_bike_rent') }}
),

-- 1. Employee permissions (authorization for field service dispatch)
test_employee_flags as (
    select
        f.service_event_sk,
        f.service_event_id,
        'employee_cannot_field_service' as error_reason
    from fct f
    left join dim_emp e on f.employee_sk = e.employee_sk
    where e.can_field_service_flg = false
),

-- 2. Adequacy of dispatch cost
test_service_cost as (
    select
        service_event_sk,
        service_event_id,
        'invalid_service_cost' as error_reason
    from fct
    where coalesce(service_cost_usd, 0) <= 0
),

-- 3. Referential integrity with the rental table
-- (A dispatch is always tied to a specific rental fact, which must exist)
test_rental_existence as (
    select
        f.service_event_sk,
        f.service_event_id,
        'orphan_rental_id' as error_reason
    from fct f
    left join rent_fct r on f.rental_id = r.rental_id
    where r.rental_id is null
),

-- 4. Consistency of issue categories and resolutions
test_valid_enums as (
    select
        service_event_sk,
        service_event_id,
        'invalid_category_or_action' as error_reason
    from fct
    where issue_category not in ('dead_battery', 'flat_tire', 'engine_check', 'lost_key')
       or resolution_action not in ('fixed_on_site', 'bike_replaced', 'towed_to_shop')
)

-- Combine all validation results
select * from test_employee_flags
union all
select * from test_service_cost
union all
select * from test_rental_existence
union all
select * from test_valid_enums