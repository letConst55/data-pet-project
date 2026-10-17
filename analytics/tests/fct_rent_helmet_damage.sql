select rental_id
from {{ ref('fct_client_bike_rent') }}
where coalesce(helmets_issued_qty, 0) = 0
  and helmet_damage_flag = true