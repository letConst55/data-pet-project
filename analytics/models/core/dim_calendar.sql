{{
    config(
        materialized='table',
        schema='core'
    )
}}

with staging_dates as (
    select min(event_timestamp::date) as min_dt, max(event_timestamp::date) as max_dt
    from {{ ref('stg_client_profile_updated') }}

    union all

    select
        min(least(event_timestamp::date, coalesce(planned_start_date, event_timestamp::date))),
        max(greatest(event_timestamp::date, coalesce(planned_end_date, event_timestamp::date)))
    from {{ ref('stg_rental_booked') }}

    union all

    select
        min(least(event_timestamp::date, coalesce(fact_start_date, event_timestamp::date))),
        max(greatest(event_timestamp::date, coalesce(fact_start_date, event_timestamp::date)))
    from {{ ref('stg_bike_dispensed') }}

    union all

    select
        min(least(event_timestamp::date, coalesce(fact_end_date, event_timestamp::date))),
        max(greatest(event_timestamp::date, coalesce(fact_end_date, event_timestamp::date)))
    from {{ ref('stg_bike_returned') }}

    union all

    select
        min(least(event_timestamp::date, coalesce(event_date, event_timestamp::date))),
        max(greatest(event_timestamp::date, coalesce(event_date, event_timestamp::date)))
    from {{ ref('stg_field_service_performed') }}
),

date_bounds as (
    select
        coalesce(min(min_dt), '2024-03-01'::date) as start_date,
        greatest(current_date, coalesce(max(max_dt), current_date)) as end_date
    from staging_dates
),

date_spine as (
    {% if target.type == 'snowflake' %}
    select
        dateadd(day, seq4(), b.start_date)::date as date_day
    from date_bounds b
    cross join table(generator(rowcount => 5000))
    where dateadd(day, seq4(), b.start_date)::date <= b.end_date
    {% else %}
    select
        generate_series(start_date, end_date, '1 day'::interval)::date as date_day
    from date_bounds
    {% endif %}
),

thai_holidays as (
    select
        d.date_day,
        case
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
            when d.date_day in ('2024-02-24'::date, '2025-02-12'::date, '2026-03-03'::date) then 'Makha Bucha Day'
            when d.date_day in ('2024-05-22'::date, '2025-05-11'::date, '2026-05-31'::date) then 'Visakha Bucha Day'
            when d.date_day in ('2024-07-20'::date, '2025-07-10'::date, '2026-07-29'::date) then 'Asanha Bucha Day'
            when d.date_day in ('2024-07-21'::date, '2025-07-11'::date, '2026-07-30'::date) then 'Buddhist Lent Day (Khao Phansa)'
            else null
        end as holiday_name
    from date_spine d
),

base_dates as (
    select
        d.date_day,
        h.holiday_name,
        {% if target.type == 'snowflake' %}
        dayofweekiso(d.date_day)::int as dow_number,
        dayofyear(d.date_day)::int as day_of_year,
        to_char(d.date_day, 'MMMM') as month_name,
        dateadd(day, 6, date_trunc('week', d.date_day))::date as week_end_date,
        last_day(d.date_day)::date as month_end_date
        {% else %}
        extract(isodow from d.date_day)::int as dow_number,
        extract(doy from d.date_day)::int as day_of_year,
        trim(to_char(d.date_day, 'Month')) as month_name,
        (date_trunc('week', d.date_day) + interval '6 days')::date as week_end_date,
        (date_trunc('month', d.date_day) + interval '1 month - 1 day')::date as month_end_date
        {% endif %}
    from date_spine d
    left join thai_holidays h
        on d.date_day = h.date_day
),

final as (
    select
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,

        date_day as date,

        to_char(date_day, 'YYYY-MM') as month_year,
        'Q' || extract(quarter from date_day)::int::varchar || '-' || extract(year from date_day)::int::varchar as quarter_year,
        extract(week from date_day)::int as week_number,
        dow_number,
        case dow_number
            when 1 then 'Monday'
            when 2 then 'Tuesday'
            when 3 then 'Wednesday'
            when 4 then 'Thursday'
            when 5 then 'Friday'
            when 6 then 'Saturday'
            when 7 then 'Sunday'
        end as dow_text,
        case when holiday_name is not null then true else false end as is_holiday_flg,

        holiday_name,
        to_char(date_day, 'YYYYMMDD')::int as date_key_int,
        extract(year from date_day)::int as year_number,
        extract(quarter from date_day)::int as quarter_number,
        extract(month from date_day)::int as month_number,
        month_name,
        to_char(date_day, 'Mon') as month_name_short,
        extract(day from date_day)::int as day_of_month,
        day_of_year,
        upper(to_char(date_day, 'DY')) as dow_text_short,

        case when dow_number in (6, 7) then true else false end as is_weekend_flg,
        case when dow_number not in (6, 7) and holiday_name is null then true else false end as is_working_day_flg,

        case
            when extract(month from date_day) in (11, 12, 1, 2) then 'Cool & Dry (High Season)'
            when extract(month from date_day) in (3, 4, 5) then 'Hot Season'
            else 'Monsoon / Rainy (Low Season)'
        end as bkk_weather_season,

        date_trunc('week', date_day)::date as week_start_date,
        week_end_date,
        date_trunc('month', date_day)::date as month_start_date,
        month_end_date,
        case when date_day = month_end_date then true else false end as is_month_end_flg

    from base_dates
)

select *
from final
order by date