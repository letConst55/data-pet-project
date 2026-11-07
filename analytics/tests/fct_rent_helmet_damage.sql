/*
-------------------------------------------------------------------------------------------------------
Test Name: fct_rent_helmet_damage
Description: 
    Validates the logical consistency between issued equipment and reported damages at return.
    If a client did not rent any helmets (`helmets_issued_qty` = 0), they cannot logically 
    be penalized for helmet damage.

Business Rules Validated:
    - Equipment Damage Constraint: The `helmet_damage_flag` (residing in the junk dimension) MUST 
      be false if `helmets_issued_qty` is 0.
    - Failure Example: A client uses their own personal helmet and rents only the bike. Upon return, 
      the mechanic mistakenly taps the "Helmet Scratched" checkbox in the app, resulting in an 
      unjustified penalty deduction from the client's deposit.

Output: 
    Returns the `rental_id` of rentals where a helmet damage flag was raised despite 0 helmets issued.
-------------------------------------------------------------------------------------------------------
*/

select f.rental_id
from {{ ref('fct_client_bike_rent') }} f
left join {{ ref('dim_rental_junk') }} j
  on f.rental_junk_sk = j.rental_junk_sk
where coalesce(f.helmets_issued_qty, 0) = 0
  and j.helmet_damage_flag = true