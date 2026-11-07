/*
-------------------------------------------------------------------------------------------------------
Test Name: fct_inventory_snapshot_business_logic
Description: 
    Comprehensive business logic validation for the Periodic Snapshot fact table tracking 
    warehouse inventory balances. This test consolidates 5 independent checks into a single 
    CTE-based script for efficient execution and debugging.

Business Rules Validated:
    1. Availability Consistency: The `available_flag` must exactly match the physical stock logic 
       (true if `product_quantity` > 0, otherwise false).
       - Failure Example: A mechanic reserves the last engine for an upcoming repair, dropping physical 
         stock to 0, but the flag remains true, leading to false inventory availability on dashboards.
    2. Shipment Date Logic: If an item is currently on order (`isin_shipment_flag` = true), there MUST 
       be a `planned_delivery_date`. If it's not on order, the date must be NULL.
       - Failure Example: The purchasing system flags a helmet as ordered, but a network error drops 
         the ETA date from the payload, leaving warehouse managers blind.
    3. Delivery Chronology: The `planned_delivery_date` cannot be in the past relative to the 
       date the snapshot was taken (`snapshot_date_key`).
       - Failure Example: An expected shipment from China was delayed at customs, but the system 
         failed to update the ETA, leaving past-due dates in current inventory reports.
    4. Physical Goods Only: Tuning and installation services cannot physically sit on warehouse shelves, 
       so products with `is_tuning_flag = true` must not appear in the snapshot.
       - Failure Example: A misclassified "Exhaust System Upgrade" service is accidentally counted as 
         a physical item, inflating the total warehouse asset valuation.
    5. Snapshot Cadence: Snapshots must be taken strictly on Sundays (the end of the business week).
       - Failure Example: A manual ETL trigger causes a snapshot to be taken on a Wednesday, breaking 
         weekly trend analysis and double-counting inventory for that week.

Output: 
    Returns `inventory_snapshot_sk` alongside an `error_reason` flag for any violated rule.
-------------------------------------------------------------------------------------------------------
*/

with fct as (
    select * from {{ ref('fct_inventory_snapshot') }}
),
dim_prod as (
    select * from {{ ref('dim_product') }}
),

-- 1. Availability logic (the flag must strictly align with the actual quantity)
test_availability as (
    select
        inventory_snapshot_sk,
        'availability_flag_mismatch' as error_reason
    from fct
    where (product_quantity > 0 and available_flag = false)
       or (product_quantity <= 0 and available_flag = true)
),

-- 2. Expected shipment logic (the delivery date must exist ONLY if the product is on order)
test_shipment_dates as (
    select
        inventory_snapshot_sk,
        'shipment_date_logic_error' as error_reason
    from fct
    where (isin_shipment_flag = true and planned_delivery_date is null)
       or (isin_shipment_flag = false and planned_delivery_date is not null)
),

-- 3. Delivery chronology (the expected date cannot be in the past relative to the snapshot date)
test_delivery_chronology as (
    select
        inventory_snapshot_sk,
        'delivery_date_in_past' as error_reason
    from fct
    where planned_delivery_date is not null
      and planned_delivery_date < snapshot_date_key
),

-- 4. The snapshot must contain only physical goods (no tuning or repair services)
test_physical_products as (
    select
        f.inventory_snapshot_sk,
        'snapshot_contains_tuning_service' as error_reason
    from fct f
    left join dim_prod p on f.product_sk = p.product_sk
    where p.is_tuning_flag = true
),

-- 5. Snapshot execution day (must always fall on a Sunday, the 7th day of the ISO week)
test_snapshot_day as (
    select
        inventory_snapshot_sk,
        'snapshot_not_on_sunday' as error_reason
    from fct
    -- The extract(isodow) function in PostgreSQL returns 1 for Monday and 7 for Sunday
    where extract(isodow from snapshot_date_key) != 7
)

-- Combine all validation results
select * from test_availability
union all
select * from test_shipment_dates
union all
select * from test_delivery_chronology
union all
select * from test_physical_products
union all
select * from test_snapshot_day