{{
    config(
        materialized='table',
        schema='aggregations'
    )
}}

-- 1. Создаем "хребет" (Spine): Каждому клиенту генерируем сетку месяцев
-- начиная с даты его первой активности до текущего месяца
with client_first_touch as (
    select 
        c.client_natural_key,
        least(
            min(fbr.fact_start_date),
            min(fso.order_date),
            min(fr.transportation_start_date)
        ) as first_touch_date
    from {{ ref('dim_client') }} c
    left join {{ ref('fct_client_bike_rent') }} fbr on c.client_sk = fbr.client_sk
    left join {{ ref('fct_shop_order') }} fso on c.client_sk = fso.client_sk
    left join {{ ref('fct_repair') }} fr on c.client_sk = fr.client_sk
    group by 1
),
calendar_spine as (
    select distinct 
        c.client_natural_key,
        date_trunc('month', cal.date)::date as report_month
    from client_first_touch c
    -- Предполагается, что в dim_calendar есть поле date. 
    -- Если у тебя ролевое измерение, используй его.
    inner join {{ ref('dim_calendar') }} cal 
        on cal.date >= date_trunc('month', c.first_touch_date)
        and cal.date <= current_date
),
-- 2. Подготавливаем базовые факты
client_bike_rent_ext as (
    select 
        fbr.bike_sk,
        fbr.client_sk,
        fbr.deposit_deducted_amount,
        fbr.fact_end_date,
        fbr.fact_start_date,
        date_trunc('month', fbr.fact_start_date)::date as event_month,
        fbr.total_amount,
        (fbr.actual_end_mileage - fbr.actual_start_mileage) as trip_mileage,
        dc.client_natural_key,
        jd.helmet_damage_flag,	
        jd.field_service_flag,	
        jd.rent_extend_flag,
        jd.bike_exchange_flag,
        first_value(db.title) over(partition by dc.client_natural_key order by fbr.fact_start_datetime asc) as first_bike,
        first_value(db.engine_volume_cc) over(partition by dc.client_natural_key order by fbr.fact_start_datetime asc) as first_bike_cc,
        first_value(ll.title) over(partition by dc.client_natural_key order by fbr.fact_start_datetime asc) as first_dis_location,
        first_value(jd.return_status_category) over(partition by dc.client_natural_key order by fbr.fact_start_datetime asc) as first_rental_result
    from {{ ref('fct_client_bike_rent') }} fbr
    inner join {{ ref('dim_client') }} dc on dc.client_sk = fbr.client_sk 
    inner join {{ ref('dim_rental_junk') }} jd on jd.rental_junk_sk = fbr.rental_junk_sk 
    inner join {{ ref('dim_bike') }} db on db.bike_sk = fbr.bike_sk
    inner join {{ ref('dim_location') }} ll on ll.location_sk = fbr.location_dis_id 
    -- Здесь получается связь многие-ко-многим поэтому убираем джойн
    --left join {{ ref('fct_service_events') }} se on se.rental_id = fbr.rental_id 
    where fbr.fact_end_date is not null
),
-- 3. Агрегируем метрики по месяцам
rental_metrics as (
    select 
        client_natural_key,
        event_month,
        count(bike_sk) as mtd_rentals,
        count(distinct bike_sk) as mtd_unique_bike_models_rented,
        avg(trip_mileage) as mtd_avg_rental_mileage,
        sum(trip_mileage) as mtd_sum_rental_mileage,
        sum(
            case 
                when deposit_deducted_amount = 0 and helmet_damage_flag = false and field_service_flag = false then 1
                else 0
            end
        ) as mtd_successful_rentals,
        sum(fact_end_date - fact_start_date) as mtd_rental_duration_days,
        sum(total_amount) as mtd_rental_amount
    from client_bike_rent_ext 
    group by 1, 2
),
shop_metrics as (
    select 
        dc.client_natural_key,
        date_trunc('month', o.order_date)::date as event_month,
        round(sum(o.total_amount), 0) as mtd_shop_amount,
        count(distinct o.order_id) as mtd_shop_orders
    from {{ ref('fct_shop_order') }} o
    inner join {{ ref('dim_client') }} dc on dc.client_sk = o.client_sk 
    group by 1, 2
),
repair_metrics as (
    select 
        dc.client_natural_key,
        date_trunc('month', r.transportation_start_date)::date as event_month,
        sum(r.invoice_total_amount) as mtd_repair_amount
    from {{ ref('fct_repair') }} r
    inner join {{ ref('dim_client') }} dc on dc.client_sk = r.client_sk 
    where r.transportation_end_date is not null
    group by 1, 2
),
first_client_experience as (
    select 
        cb.client_natural_key,
        max(cb.first_bike) as first_rent_bike,
        max(cb.first_bike_cc) as first_rent_bike_cc,
        max(cb.first_dis_location) as first_rent_dis_location,
        max(cb.first_rental_result) as first_rental_result
    from client_bike_rent_ext cb
    group by 1
),
client_attributes as (
    -- Берем актуальный профиль клиента
    select 
        dc.client_natural_key,
        dc.drive_license_verified,
        dc.driving_experience_years,
        dc.gender,
        dc.nationality,
        dc.rating_score,
        coalesce(fce.first_rent_bike::text, 'never rent') as first_rent_bike,
        fce.first_rent_bike_cc as first_rent_bike_cc,
        coalesce(fce.first_rent_dis_location::text, 'never rent') as first_rent_dis_location,
        coalesce(fce.first_rental_result::text, 'never rent') as first_rental_result
    from {{ ref('dim_client') }} dc 
    left join first_client_experience fce on fce.client_natural_key = dc.client_natural_key
    where current_row_indicator = true
),
-- 4. Джойним агрегаты на календарный хребет и считаем кумулятивные (накопительные) итоги
monthly_rollup as (
    select 
        spine.report_month,
        spine.client_natural_key,
        cl.drive_license_verified,
        cl.driving_experience_years,
        cl.gender,
        cl.nationality,
        cl.rating_score,
        cl.first_rent_bike,
        cl.first_rent_bike_cc,
        cl.first_rent_dis_location,
        cl.first_rental_result,
        -- Метрики за текущий месяц (MTD - Month to Date)
        coalesce(rm.mtd_rentals, 0) as mtd_rentals,
        coalesce(rm.mtd_successful_rentals, 0) as mtd_successful_rentals,
        coalesce(rm.mtd_unique_bike_models_rented, 0) as mtd_unique_bike_models_rented,
        coalesce(rm.mtd_rental_amount, 0) as mtd_rental_amount,
        coalesce(sm.mtd_shop_amount, 0) as mtd_shop_amount,
        coalesce(rpm.mtd_repair_amount, 0) as mtd_repair_amount,
        coalesce(rm.mtd_avg_rental_mileage, 0) as mtd_avg_rental_mileage,
        coalesce(rm.mtd_sum_rental_mileage, 0) as mtd_sum_rental_mileage,
        -- Кумулятивные метрики (YTD / Lifetime) на конец отчетного месяца
        sum(coalesce(rm.mtd_rentals, 0)) over (partition by spine.client_natural_key order by spine.report_month) as lifetime_rentals,
        sum(coalesce(rm.mtd_successful_rentals, 0)) over (partition by spine.client_natural_key order by spine.report_month) as lifetime_successful_rentals,
        sum(coalesce(rm.mtd_unique_bike_models_rented, 0)) over (partition by spine.client_natural_key order by spine.report_month) as lifetime_unique_bikes,
        sum(coalesce(rm.mtd_sum_rental_mileage, 0)) over (partition by spine.client_natural_key order by spine.report_month) as lifetime_sum_mileage,
        -- Кумулятивная выручка (LTV)
        sum(coalesce(rm.mtd_rental_amount, 0) + coalesce(sm.mtd_shop_amount, 0) + coalesce(rpm.mtd_repair_amount, 0)) 
            over (partition by spine.client_natural_key order by spine.report_month) as lifetime_total_amount
    from calendar_spine spine
    left join client_attributes cl on spine.client_natural_key = cl.client_natural_key
    left join rental_metrics rm on spine.client_natural_key = rm.client_natural_key and spine.report_month = rm.event_month
    left join shop_metrics sm on spine.client_natural_key = sm.client_natural_key and spine.report_month = sm.event_month
    left join repair_metrics rpm on spine.client_natural_key = rpm.client_natural_key and spine.report_month = rpm.event_month
)
-- 5. Финальный расчет сегментов на основе кумулятивных (исторических) данных на тот момент времени
select 
    mr.report_month::date as report_month,
    mr.client_natural_key::text as client_natural_key,
    mr.drive_license_verified::boolean as drive_license_verified,
    mr.driving_experience_years::int as driving_experience_years,
    mr.gender::text as gender,
    mr.nationality::text as nationality,
    mr.rating_score::int as rating_score,
    mr.first_rent_bike::text as first_rent_bike,
    --mr.first_rent_bike_cc::text as first_rent_bike_cc,
    mr.first_rent_dis_location::text as first_rent_dis_location,
    mr.first_rental_result::text as first_rental_result,
    mr.mtd_rentals::int as mtd_rentals,
    mr.mtd_successful_rentals::int as mtd_successful_rentals,
    mr.mtd_unique_bike_models_rented::int as mtd_unique_bike_models_rented,
    mr.mtd_rental_amount::numeric as mtd_rental_amount,
    mr.mtd_shop_amount::numeric as mtd_shop_amount,
    mr.mtd_repair_amount::numeric as mtd_repair_amount,
    mr.mtd_avg_rental_mileage::numeric as mtd_avg_rental_mileage,
    mr.mtd_sum_rental_mileage::int as mtd_sum_rental_mileage,
    mr.lifetime_rentals::int as lifetime_rentals,
    mr.lifetime_successful_rentals::int as lifetime_successful_rentals,
    mr.lifetime_unique_bikes::int as lifetime_unique_bikes,
    mr.lifetime_total_amount::numeric as lifetime_total_amount,
    round(mr.lifetime_successful_rentals::decimal / nullif(mr.lifetime_rentals, 0), 2)::numeric as trouble_free_days_ratio,  
    case
        when mr.lifetime_rentals = 0 then 'shop_only_customer'
        when mr.lifetime_rentals = 1 then 'new_customer' 
        when mr.lifetime_rentals > 1 and mr.lifetime_rentals <= 5 and (mr.lifetime_successful_rentals::decimal / nullif(mr.lifetime_rentals, 0)) >= 0.5 then 'loyal_customer'
        when mr.lifetime_rentals > 5 and (mr.lifetime_successful_rentals::decimal / nullif(mr.lifetime_rentals, 0)) >= 0.5 then 'vip_customer'
        else 'danger_customer'
    end::text as loyalty_segment_at_month,
    case
        when mr.lifetime_rentals = 0 then 'Shop_or_Garage_Only'
        when mr.driving_experience_years = 0 then 'Beginner'
        when (mr.lifetime_sum_mileage::decimal / nullif(mr.lifetime_rentals, 0)) < 180 
             and mr.driving_experience_years <= 5 then 'City_rider'
        when (mr.driving_experience_years >= 5 or mr.lifetime_unique_bikes >= 3) 
             and (mr.lifetime_sum_mileage::decimal / nullif(mr.lifetime_rentals, 0)) >= 350 then 'Pro_rider'
        else 'Traveller_rider'
    end::text as rider_profile_segment_at_month
from monthly_rollup mr