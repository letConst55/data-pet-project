/*
-------------------------------------------------------------------------------------------------------
Test Name: dim_location_valid_business_rules
Description: 
    Validates business department flags within the Location dimension and ensures referential 
    integrity against actual rental events.

Business Rules Validated:
    1. Active Department: Every physical location must host at least one active business department 
       (Garage, Shop, or Warehouse).
       - Failure Example: A location was decommissioned and all flags were set to false, but it wasn't 
         removed from the active directory, causing dummy records in downstream aggregations.
    2. Referential Integrity: Any location ID present in staging rental events (booking, dispense, 
       or return) MUST exist in `dim_location`.
       - Failure Example: A new pop-up rental booth was opened and began generating rentals, but 
         the data engineering team forgot to add it to the static `dim_location` seed file.

Output: 
    Returns locations with 0 active departments or orphaned location IDs from the staging layer.
-------------------------------------------------------------------------------------------------------
*/

-- 1. Check that every location has at least one active business department
with invalid_flags as (
    select 
        location_natural_key,
        'no_active_department' as error_reason
    from {{ ref('dim_location') }}
    where not (is_garage_flag or is_shop_flag or is_warehouse_flag)
),

-- 2. Collect all locations that actually appeared in rental events
staging_rental_locations as (
    select distinct location_id from {{ ref('stg_rental_booked') }}
    union
    select distinct location_dis_id as location_id from {{ ref('stg_bike_dispensed') }}
    union
    select distinct location_return_id as location_id from {{ ref('stg_bike_returned') }}
),

-- Verify that all collected locations exist in dim_location (Referential Integrity)
invalid_rental_locations as (
    select
        s.location_id as location_natural_key,
        'missing_in_dim_location' as error_reason
    from staging_rental_locations s
    left join {{ ref('dim_location') }} d
        on s.location_id = d.location_natural_key
    where d.location_natural_key is null
       -- Note: Strict business rule check (e.g., ensuring is_warehouse_flag = true) 
       -- is commented out because the current data generator can drop off bikes at pure retail shops.
       -- or d.is_garage_flag = false
)

select * from invalid_flags
union all
select * from invalid_rental_locations