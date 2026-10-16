-- Проверка корректности расчетов итоговой стоимости и скидок
select rental_id
from {{ ref('fct_client_bike_rent') }}
where fact_end_date is not null
  and (
      -- Правило 5: Итоговая сумма должна биться с формулой (Дни * Тариф - Скидка + Штрафы)
          total_amount != greatest(
          0.0, 
          (fact_end_date - fact_start_date) * rental_price_daily 
          - discount_amount 
          + coalesce(deposit_deducted_amount, 0)
      )
  )