-- Тест проверяет, что общая сумма по сервису строго равна сумме покупок, ремонтов и аренд.
-- Если coalesce отработал неверно, тест вернет строки с ошибками.

select
    client_natural_key,
    rental_total_amount,
    shop_total_amount,
    repair_total_amount,
    amount_across_service
from {{ ref('stats_by_clients') }}
where round(amount_across_service::numeric, 2) != round((
    coalesce(rental_total_amount, 0) + 
    coalesce(shop_total_amount, 0) + 
    coalesce(repair_total_amount, 0)
)::numeric, 2)