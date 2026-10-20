select f.rental_id
from {{ ref('fct_client_bike_rent') }} f
left join {{ ref('dim_rental_junk') }} j
  on f.rental_junk_sk = j.rental_junk_sk
where coalesce(f.helmets_issued_qty, 0) = 0
  and j.helmet_damage_flag = true