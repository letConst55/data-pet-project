-- Тест проверяет, что кумулятивная общая сумма по сервису (LTV) строго равна 
-- кумулятивной сумме аренд, покупок и ремонтов.
-- Если coalesce или оконные функции отработали неверно, тест вернет строки с ошибками.

with rollup_check as (
    select
        client_natural_key,
        report_month,
        
        -- Считаем ожидаемый LTV, суммируя нарастающие итоги по каждому домену
        sum(coalesce(mtd_rental_amount, 0)) over (partition by client_natural_key order by report_month) as expected_lifetime_rental,
        sum(coalesce(mtd_shop_amount, 0)) over (partition by client_natural_key order by report_month) as expected_lifetime_shop,
        sum(coalesce(mtd_repair_amount, 0)) over (partition by client_natural_key order by report_month) as expected_lifetime_repair,
        
        -- Фактическое рассчитанное значение в витрине
        lifetime_total_amount
        
    from {{ ref('stats_by_clients') }}
)

select
    client_natural_key,
    report_month,
    expected_lifetime_rental,
    expected_lifetime_shop,
    expected_lifetime_repair,
    lifetime_total_amount
from rollup_check
where round(lifetime_total_amount::numeric, 2) != round((
    coalesce(expected_lifetime_rental, 0) + 
    coalesce(expected_lifetime_shop, 0) + 
    coalesce(expected_lifetime_repair, 0)
)::numeric, 2)