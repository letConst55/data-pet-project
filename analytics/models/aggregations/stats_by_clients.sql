{{
    config(
        materialized='table',
        schema='aggregations'
    )
}}

with client_bike_rent_ext as (
    select 
        fbr.bike_sk,
        fbr.client_sk,
        fbr.deposit_deducted_amount,
        fbr.fact_end_date,
        fbr.fact_start_date,
        fbr.fact_start_datetime,
        fbr.total_amount,
        (fbr.actual_end_mileage - fbr.actual_start_mileage) as trip_mileage,
        dc.client_natural_key,
        jd.helmet_damage_flag,
        se.issue_category,
        first_value(db.title) over(partition by dc.client_natural_key order by fbr.fact_start_datetime asc) as first_bike,
        first_value(db.engine_volume_cc) over(partition by dc.client_natural_key order by fbr.fact_start_datetime asc) as first_bike_cc,
        first_value(ll.title) over(partition by dc.client_natural_key order by fbr.fact_start_datetime asc) as first_dis_location,
        first_value(jd.return_status_category) over(partition by dc.client_natural_key order by fbr.fact_start_datetime asc) as first_rental_result
    from {{ ref('fct_client_bike_rent') }} fbr
    inner join {{ ref('dim_client') }} dc on dc.client_sk = fbr.client_sk 
    inner join {{ ref('dim_rental_junk') }} jd on jd.rental_junk_sk = fbr.rental_junk_sk 
    inner join {{ ref('dim_bike') }} db on db.bike_sk = fbr.bike_sk
    inner join {{ ref('dim_location') }} ll on ll.location_sk = fbr.location_dis_id 
    left join {{ ref('fct_service_events') }} se on se.rental_id = fbr.rental_id 
    where fbr.fact_end_date is not null
),
rental_metrics as (
    select 
        client_natural_key,
        min(fact_start_date) as first_rent_date,
        count(fbr.bike_sk) as cnt_rentals,
        count(distinct fbr.bike_sk) as unique_bike_models_rented,
        avg(trip_mileage) as avg_rental_mileage,
        sum(
            case 
                when deposit_deducted_amount = 0 and helmet_damage_flag = false and issue_category is null then 1
                else 0
            end
        ) as cnt_successful_rentals,
        sum(fact_end_date - fact_start_date) as total_day_rental_duration,
        sum(total_amount) as total_amount,
        sum(total_amount) / count(fbr.bike_sk) as avg_rental_amount,
        avg(fact_end_date - fact_start_date) as avg_day_rental_duration,
        max(first_bike) as first_rent_bike,
        max(first_bike_cc) as first_rent_bike_cc,
        max(first_dis_location) as first_rent_dis_location,
        max(first_rental_result) as first_rental_result
    from client_bike_rent_ext fbr
    group by 1
),
shop_metrics as (
    select 
        dc.client_natural_key,
        min(o.order_date) as first_shop_date,
        round(sum(o.total_amount), 0) as shop_total_amount,
        round(sum(o.total_amount) / count(distinct o.order_id), 1) as shop_aov
    from {{ ref('fct_shop_order') }} o
    inner join {{ ref('dim_client') }} dc on dc.client_sk = o.client_sk 
    group by 1
),
repair_metrics as (
    select 
        dc.client_natural_key,
        min(r.transportation_start_date) as first_repair_date,
        sum(r.invoice_total_amount) as repair_total_amount
    from {{ ref('fct_repair') }} r
    inner join {{ ref('dim_client') }} dc on dc.client_sk = r.client_sk 
    where r.transportation_end_date is not null
    group by 1
),
client_attributes as (
    select 
        client_natural_key,
        drive_license_verified,
        driving_experience_years,
        gender,
        nationality,
        rating_score 
    from {{ ref('dim_client') }} 
    where current_row_indicator = true
)
select 
    cl.client_natural_key,
    cl.drive_license_verified,
    cl.driving_experience_years,
    cl.gender,
    cl.nationality,
    cl.rating_score,
    rm.first_rent_date,
    rm.cnt_rentals,
    rm.cnt_successful_rentals,
    round(rm.cnt_successful_rentals::decimal / nullif(rm.cnt_rentals, 0), 2) as trouble_free_days_ratio, -- North Star Metric
    rm.unique_bike_models_rented,
    rm.avg_rental_mileage,
    rm.total_day_rental_duration,
    rm.total_amount as rental_total_amount,
    rm.avg_rental_amount,
    rm.first_rent_bike,
    rm.first_rent_bike_cc,
    sm.first_shop_date,
    sm.shop_total_amount,
    sm.shop_aov,
    rpm.first_repair_date,
    rpm.repair_total_amount, 
    least(rm.first_rent_date, sm.first_shop_date, rpm.first_repair_date) as first_touch_date,
    coalesce(rm.total_amount, 0) + coalesce(sm.shop_total_amount, 0) + coalesce(rpm.repair_total_amount, 0) as amount_across_service,
    case
        when rm.cnt_rentals = 1 then 'new_customer' 
        when rm.cnt_rentals > 1 and rm.cnt_rentals <= 5 and (rm.cnt_successful_rentals::decimal / rm.cnt_rentals) >= 0.5 then 'loyal_customer'
        when rm.cnt_rentals > 5 and (rm.cnt_successful_rentals::decimal / rm.cnt_rentals) >= 0.5 then 'vip_customer'
        when rm.cnt_rentals > 1 and (rm.cnt_successful_rentals::decimal / rm.cnt_rentals) < 0.5 then 'danger_customer'
        else 'unclassified'
    end as loyalty_segment,
    case
        when cl.driving_experience_years = 0 and coalesce(rm.first_rent_bike_cc, 0) <= 160 then 'Beginer'
        when cl.driving_experience_years > 0 and coalesce(rm.first_rent_bike_cc, 0) <= 160 and coalesce(rm.avg_rental_mileage, 0) < 100 then 'City_rider'
        when coalesce(rm.first_rent_bike_cc, 0) > 160 and coalesce(rm.avg_rental_mileage, 0) between 100 and 500 then 'Traveller_rider'
        when (cl.driving_experience_years >= 3 or rm.unique_bike_models_rented > 2) and coalesce(rm.avg_rental_mileage, 0) > 500 then 'Pro_rider'
        else 'unknown'
    end as rider_profile_segment
from client_attributes cl
left join rental_metrics rm on rm.client_natural_key = cl.client_natural_key
left join shop_metrics sm on sm.client_natural_key = cl.client_natural_key 
left join repair_metrics rpm on rpm.client_natural_key = cl.client_natural_key 
where rm.first_rent_date is not null