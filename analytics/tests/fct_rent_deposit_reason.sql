select rental_id
from {{ ref('fct_client_bike_rent') }}
where coalesce(deposit_deducted_amount, 0) = 0
  and deduction_reason_code != 'none'