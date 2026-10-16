-- Проверка консистентности дат аренды
select rental_id
from {{ ref('fct_client_bike_rent') }}
where 
    -- Планируемые даты перепутаны
    planned_start_date > planned_end_date
    
    -- Фактическое завершение раньше выдачи (проверяем только для завершенных аренд)
    or (fact_start_date is not null 
        and fact_end_date is not null 
        and fact_start_date > fact_end_date)