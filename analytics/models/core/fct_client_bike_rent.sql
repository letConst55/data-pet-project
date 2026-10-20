{{
    config(
        materialized='incremental',
        unique_key='rental_id',
        schema='core'
    )
}}

with dummy as (
    select 1
),
{% if is_incremental() %}
-- Ищем аренды, по которым были ЛЮБЫЕ движения со времени последнего запуска
changed_rentals as (
    select rental_id from {{ ref('stg_rental_booked') }} 
    where event_timestamp > (select coalesce(max(last_source_timestamp), '1900-01-01'::timestamp) from {{ this }})
    union
    select rental_id from {{ ref('stg_bike_dispensed') }} 
    where event_timestamp > (select coalesce(max(last_source_timestamp), '1900-01-01'::timestamp) from {{ this }})
    union
    select rental_id from {{ ref('stg_bike_returned') }} 
    where event_timestamp > (select coalesce(max(last_source_timestamp), '1900-01-01'::timestamp) from {{ this }})
),
{% endif %}
-- 1. Зарождение пайплайна (Бронирование)
booked as (
    select 
        * 
    from {{ ref('stg_rental_booked') }}
    {% if is_incremental() %}
    where rental_id in (select rental_id from changed_rentals)
    {% endif %}
),

-- 2. Обновление пайплайна (Выдача)
dispensed as (
    select 
        * 
    from {{ ref('stg_bike_dispensed') }}
    {% if is_incremental() %}
    where rental_id in (select rental_id from changed_rentals)
    {% endif %}
),

-- 3. Завершение пайплайна (Возврат)
returned as (
    select 
        * 
    from {{ ref('stg_bike_returned') }}
    {% if is_incremental() %}
    where rental_id in (select rental_id from changed_rentals)
    {% endif %}
),

-- 4. Сборка таблицы фактов
pipeline as (
    select
        -- Ключ факта
        b.rental_id,
        
        -- FK: Клиент (SCD2 Point-in-Time Lookup)
        c.client_sk,
        
        -- FK: Байк (SCD1)
        bk.bike_sk,
        
        -- FK: Локации (SCD1)
        ld.location_sk as location_dis_id,
        lr.location_sk as location_return_id,
        
        -- FK: Сотрудники (SCD2 Point-in-Time Lookup)
        emp_d.employee_sk as employee_disp_id,
        emp_r.employee_sk as employee_return_id,
        
        -- Даты
        b.planned_start_date,
        b.planned_end_date,
        d.fact_start_date,
        d.fact_start_datetime,
        r.fact_end_date,
        r.fact_end_datetime,
        
        -- Финансы
        b.rental_price_daily,
        b.deposit_amount,
        r.deposit_deducted_amount,
        r.deduction_reason_code,
        b.discount_amount,
        r.total_amount,
        
        -- Состояние и пробег
        d.actual_start_mileage,
        r.actual_end_mileage,
        d.fuel_start_percent,
        r.fuel_end_percent,
        
        -- FK: Состояние байка (SCD4 Mini-Dimension, используем само значение как ключ)
        d.pre_rental_condition_score,
        r.post_rental_condition_score,
        
        -- Детали аренды
        d.helmets_issued_qty,


        -- FK: Мусорное измерение флагов возврата (Junk Dimension)
        -- Используем coalesce(..., false), так как для еще не возвращенных байков (NULL) 
        -- мы логически предполагаем отсутствие флагов проблем
        {{ dbt_utils.generate_surrogate_key([
            'coalesce(r.helmet_damage_flag, false)',
            'coalesce(r.field_service_flag, false)',
            'coalesce(r.rent_extend_flag, false)',
            'coalesce(r.bike_exchange_flag, false)'
        ]) }} as rental_junk_sk,
        
        -- Техническое поле для инкрементальной загрузки: 
        -- запоминаем максимальный timestamp из всех трех событий пайплайна
        greatest(
            b.event_timestamp, 
            coalesce(d.event_timestamp, '1900-01-01'::timestamp), 
            coalesce(r.event_timestamp, '1900-01-01'::timestamp)
        ) as last_source_timestamp

    from booked b
    
    -- Связываем стадии пайплайна
    left join dispensed d on b.rental_id = d.rental_id
    left join returned r on b.rental_id = r.rental_id
    
    -- 1. SCD2 Lookup: Клиент на момент бронирования
    left join {{ ref('dim_client') }} c
      on b.client_id = c.client_natural_key
     and b.event_timestamp >= c.row_effective_date
     and b.event_timestamp < c.row_expiration_date
     
    -- 2. SCD1 Lookup: Байк
    left join {{ ref('dim_bike') }} bk
      on b.bike_id = bk.bike_natural_key
      
    -- 3. SCD1 Lookup: Локации
    left join {{ ref('dim_location') }} ld on d.location_dis_id = ld.location_natural_key
    left join {{ ref('dim_location') }} lr on r.location_return_id = lr.location_natural_key
    
    -- 4. SCD2 Lookup: Сотрудник выдачи на момент выдачи
    left join {{ ref('dim_employee') }} emp_d
      on d.employee_disp_id = emp_d.employee_natural_key
     and d.event_timestamp >= emp_d.row_effective_date
     and d.event_timestamp < emp_d.row_expiration_date
     
    -- 5. SCD2 Lookup: Сотрудник возврата на момент возврата
    left join {{ ref('dim_employee') }} emp_r
      on r.employee_return_id = emp_r.employee_natural_key
     and r.event_timestamp >= emp_r.row_effective_date
     and r.event_timestamp < emp_r.row_expiration_date
)

select
    '{{ invocation_id }}'::varchar as dataflow_id,
    current_timestamp as dataflow_dttm,
    p.*
from pipeline p