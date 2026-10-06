{{
    config(
        materialized='table',
        schema='core'
    )
}}

-- 1. Собираем минимальные и максимальные даты со всех 5 staging-таблиц
with staging_dates as (
    select min(event_timestamp::date) as min_dt, max(event_timestamp::date) as max_dt 
    from {{ ref('stg_client_profile_updated') }}
    
    union all
    
    select min( least(event_timestamp::date, planned_start_date) ), max( greatest(event_timestamp::date, planned_end_date) ) 
    from {{ ref('stg_rental_booked') }}
    
    union all
    
    select min( least(event_timestamp::date, fact_start_date) ), max( greatest(event_timestamp::date, fact_start_date) ) 
    from {{ ref('stg_bike_dispensed') }}
    
    union all
    
    select min( least(event_timestamp::date, fact_end_date) ), max( greatest(event_timestamp::date, fact_end_date) ) 
    from {{ ref('stg_bike_returned') }}
    
    union all
    
    select min( least(event_timestamp::date, event_date) ), max( greatest(event_timestamp::date, event_date) ) 
    from {{ ref('stg_field_service_performed') }}
),

date_bounds as (
    select
        coalesce(min(min_dt), '2024-03-01'::date) as start_date,
        -- Берем текущую дату (или максимум из стейджинга, если плановые даты окончания броней ушли вперед)
        greatest(current_date, coalesce(max(max_dt), current_date)) as end_date
    from staging_dates
),

-- 2. Генерируем непрерывный ряд дат с шагом 1 день
date_spine as (
    select 
        generate_series(start_date, end_date, '1 day'::interval)::date as date_day
    from date_bounds
),

-- 3. Справочник государственных праздников Таиланда (фиксированные + лунные на 2024-2026 гг.)
thai_holidays as (
    select 
        d.date_day,
        case
            -- Фиксированные государственные праздники Таиланда (работают для любого года)
            when extract(month from d.date_day) = 1  and extract(day from d.date_day) = 1  then 'New Year''s Day'
            when extract(month from d.date_day) = 4  and extract(day from d.date_day) = 6  then 'Chakri Memorial Day'
            when extract(month from d.date_day) = 4  and extract(day from d.date_day) in (13, 14, 15) then 'Songkran Festival'
            when extract(month from d.date_day) = 5  and extract(day from d.date_day) = 1  then 'National Labour Day'
            when extract(month from d.date_day) = 5  and extract(day from d.date_day) = 4  then 'Coronation Day'
            when extract(month from d.date_day) = 6  and extract(day from d.date_day) = 3  then 'Queen Suthida''s Birthday'
            when extract(month from d.date_day) = 7  and extract(day from d.date_day) = 28 then 'King Vajiralongkorn''s Birthday'
            when extract(month from d.date_day) = 8  and extract(day from d.date_day) = 12 then 'The Queen Mother''s Birthday / Mother''s Day'
            when extract(month from d.date_day) = 10 and extract(day from d.date_day) = 13 then 'King Bhumibol Memorial Day'
            when extract(month from d.date_day) = 10 and extract(day from d.date_day) = 23 then 'Chulalongkorn Day'
            when extract(month from d.date_day) = 12 and extract(day from d.date_day) = 5  then 'King Bhumibol''s Birthday / Father''s Day'
            when extract(month from d.date_day) = 12 and extract(day from d.date_day) = 10 then 'Constitution Day'
            when extract(month from d.date_day) = 12 and extract(day from d.date_day) = 31 then 'New Year''s Eve'
            
            -- Подвижные буддийские праздники по лунному календарю (2024 - 2026)
            when d.date_day in ('2024-02-24'::date, '2025-02-12'::date, '2026-03-03'::date) then 'Makha Bucha Day'
            when d.date_day in ('2024-05-22'::date, '2025-05-11'::date, '2026-05-31'::date) then 'Visakha Bucha Day'
            when d.date_day in ('2024-07-20'::date, '2025-07-10'::date, '2026-07-29'::date) then 'Asanha Bucha Day'
            when d.date_day in ('2024-07-21'::date, '2025-07-11'::date, '2026-07-30'::date) then 'Buddhist Lent Day (Khao Phansa)'
            else null
        end as holiday_name
    from date_spine d
),

-- 4. Формируем финальную витрину
final as (
    select
        -- Технические поля пайплайна (со схемы)
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,

        -- Первичный ключ (со схемы)
        d.date_day as date,

        -- Обязательные атрибуты со схемы ERD
        to_char(d.date_day, 'YYYY-MM') as month_year,
        'Q' || to_char(d.date_day, 'Q-YYYY') as quarter_year,
        extract(week from d.date_day)::int as week_number,
        extract(isodow from d.date_day)::int as dow_number, -- 1 = Monday ... 7 = Sunday (стандарт ISO)
        trim(to_char(d.date_day, 'Day')) as dow_text,
        case when h.holiday_name is not null then true else false end as is_holiday_flg,

        -- Дополнительные полезные аналитические атрибуты по Кимбаллу
        h.holiday_name,
        to_char(d.date_day, 'YYYYMMDD')::int as date_key_int, -- Числовой ключ вида 20240301
        extract(year from d.date_day)::int as year_number,
        extract(quarter from d.date_day)::int as quarter_number,
        extract(month from d.date_day)::int as month_number,
        trim(to_char(d.date_day, 'Month')) as month_name,
        to_char(d.date_day, 'Mon') as month_name_short,
        extract(day from d.date_day)::int as day_of_month,
        extract(doy from d.date_day)::int as day_of_year,
        to_char(d.date_day, 'DY') as dow_text_short,
        
        -- Флаги выходных и рабочих дней
        case 
            when extract(isodow from d.date_day) in (6, 7) then true 
            else false 
        end as is_weekend_flg,
        case 
            when extract(isodow from d.date_day) not in (6, 7) and h.holiday_name is null then true 
            else false 
        end as is_working_day_flg,

        -- Туристический/погодный сезон в Бангкоке (очень полезно для анализа спроса на байки!)
        case
            when extract(month from d.date_day) in (11, 12, 1, 2) then 'Cool & Dry (High Season)'
            when extract(month from d.date_day) in (3, 4, 5) then 'Hot Season'
            else 'Monsoon / Rainy (Low Season)'
        end as bkk_weather_season,

        -- Границы периодов (удобно для группировок в BI)
        date_trunc('week', d.date_day)::date as week_start_date,
        (date_trunc('week', d.date_day) + interval '6 days')::date as week_end_date,
        date_trunc('month', d.date_day)::date as month_start_date,
        (date_trunc('month', d.date_day) + interval '1 month - 1 day')::date as month_end_date,
        case 
            when d.date_day = (date_trunc('month', d.date_day) + interval '1 month - 1 day')::date then true 
            else false 
        end as is_month_end_flg

    from date_spine d
    left join thai_holidays h
        on d.date_day = h.date_day
)

select 
    * 
from final
order by date