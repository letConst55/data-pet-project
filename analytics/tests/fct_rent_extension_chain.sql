/*
-------------------------------------------------------------------------------------------------------
Test Name: fct_rent_extension_chain
Description: 
    Validates the continuity of a rental extension chain. If a rental is marked as extended 
    (`rent_extend_flag` = true), there MUST exist a subsequent rental for the exact same client 
    and bike that starts immediately after the previous one ends.

Business Rules Validated:
    1. Extension Linkage: A `rent_extend_flag` is a promise of a future record. This test ensures 
       that the promised subsequent rental fact actually exists in the database.
       - Failure Example: A client requests to extend their rental, the current fact is closed with 
         the extension flag set to true, but the system crashes before writing the new booking into 
         the database, creating an orphaned extension.
    2. SCD2 Time Travel Trap Avoidance: The test joins subsequent rentals using the unchanging 
       `client_natural_key` rather than the surrogate `client_sk`. 
       - Failure Example: If a client updates their profile address during an active rental, a new 
         SCD2 surrogate key is generated. Joining on the old surrogate key would falsely indicate a 
         broken chain, even though the physical client extended the rental.

Output: 
    Returns `rental_id` values of rentals that were supposedly extended but have no subsequent booking.
-------------------------------------------------------------------------------------------------------
*/

with max_date as (
    select max(fact_end_date) as current_max_date
    from {{ ref('fct_client_bike_rent') }}
),
-- Fetch the natural key from dim_client and flags from dim_rental_junk to avoid SCD2 traps
fct_with_nk as (
    select 
        f.rental_id,
        f.client_sk,
        c.client_natural_key, -- Unchanging Natural Key
        f.bike_sk,
        f.fact_end_date,
        j.rent_extend_flag,   -- The flag now resides in the junk dimension
        coalesce(f.fact_start_date, f.planned_start_date) as start_date
    from {{ ref('fct_client_bike_rent') }} f
    left join {{ ref('dim_client') }} c on f.client_sk = c.client_sk
    left join {{ ref('dim_rental_junk') }} j on f.rental_junk_sk = j.rental_junk_sk
),
extended as (
    select *
    from fct_with_nk
    where rent_extend_flag = true
      -- Check only "settled" data (exclude the final days of the simulation to account for pipeline lag)
      and fact_end_date < (select current_max_date - interval '3 days' from max_date)
),
subsequent as (
    select *
    from fct_with_nk
)

select e.rental_id
from extended e
left join subsequent s
  -- Join based on the unchanging natural key to bypass SCD2 dimension updates
  on e.client_natural_key = s.client_natural_key 
 and e.bike_sk = s.bike_sk
 and s.start_date >= e.fact_end_date
where s.rental_id is null