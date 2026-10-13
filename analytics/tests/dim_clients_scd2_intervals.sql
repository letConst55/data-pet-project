-- Тест ищет аномалии в цепочке версий SCD2:
-- 1. Инверсия дат: дата начала >= даты окончания в рамках одной строки
-- 2. Гэпы (разрывы) или пересечения (нахлесты): дата окончания текущей версии 
--    не равна в точности дате начала следующей версии этого же клиента
-- 3. Некорректная заглушка у последней версии

with version_chains as (
    select
        client_sk,
        client_natural_key,
        row_effective_date,
        row_expiration_date,
        current_row_indicator,
        -- Смотрим дату начала следующей версии по факту в таблице
        lead(row_effective_date) over (
            partition by client_natural_key 
            order by row_effective_date
        ) as next_effective_date
    from {{ ref('dim_client') }}
)

select 
    *
from version_chains
where 
    -- 1. Ошибка внутри самой строки (начало позже или равно концу)
    row_effective_date >= row_expiration_date
    
    -- 2. Если есть следующая версия, но между ними дыра (gap) или нахлест (overlap)
    or (next_effective_date is not null and row_expiration_date != next_effective_date)
    
    -- 3. Если есть следующая версия, но текущая строка почему-то помечена как активная
    or (next_effective_date is not null and current_row_indicator = true)
    
    -- 4. Если это последняя версия, но у нее не стоит дата бесконечности или флаг активности
    or (next_effective_date is null and (
        row_expiration_date != '9999-12-31 23:59:59'::timestamp 
        or current_row_indicator != true
    ))