-- Проверка, что пробег при возврате не может быть меньше пробега при выдаче
select rental_id
from {{ ref('fct_client_bike_rent') }}
where fact_end_date is not null
  and actual_start_mileage > actual_end_mileage