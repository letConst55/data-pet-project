-- Проверка отсутствия пропусков дат (дыр) в календаре
select
    count(*) as total_rows,
    (max(date) - min(date) + 1) as expected_days
from {{ ref('dim_calendar') }}
having count(*) != (max(date) - min(date) + 1)