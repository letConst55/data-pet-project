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
			fbr.deduction_reason_code,
			fbr.deposit_amount,
			fbr.deposit_deducted_amount,
			fbr.discount_amount,
			fbr.fact_end_date,
			fbr.fact_end_datetime,
			fbr.fact_start_date,
			fbr.fact_start_datetime,
			fbr.fuel_end_percent,
			fbr.fuel_start_percent,
			fbr.helmets_issued_qty,
			fbr.location_dis_id,
			fbr.location_return_id,
			fbr.planned_end_date,
			fbr.planned_start_date,
			fbr.post_rental_condition_score,
			fbr.pre_rental_condition_score,
			fbr.rental_id,
			fbr.rental_junk_sk,
			fbr.rental_price_daily,
			fbr.total_amount,
			dc.client_natural_key,
			jd.helmet_damage_flag,
			jd.field_service_flag,
			jd.rent_extend_flag,
			jd.bike_exchange_flag,
			jd.return_status_category,
			se.issue_category,
			se.client_fault_flag,
			se.service_cost_usd,
			row_number() over(partition by dc.client_natural_key 
							  order by fbr.fact_start_datetime asc) as ranked_rentals,
			first_value(db.title) over(partition by dc.client_natural_key 
									   order by fbr.fact_start_datetime asc) as first_bike,
			first_value(ll.title) over(partition by dc.client_natural_key 
									   order by fbr.fact_start_datetime asc) as first_dis_location,
			first_value(jd.return_status_category) over(partition by dc.client_natural_key 
									   					order by fbr.fact_start_datetime asc) as first_rental_result
	from core.fct_client_bike_rent fbr
	inner join core.dim_client dc on dc.client_sk = fbr.client_sk 
	inner join core.dim_rental_junk jd on jd.rental_junk_sk = fbr.rental_junk_sk 
	inner join core.dim_bike db on db.bike_sk = fbr.bike_sk
	inner join core.dim_location ll on ll.location_sk = fbr.location_dis_id 
	left join core.fct_service_events se on se.rental_id = fbr.rental_id 
	where fbr.fact_end_date is not null
),
rental_metrics as (
	select 
			client_natural_key as client_natural_key,
			min(fact_start_date) as first_rent_date,
			count(rental_id) as cnt_rentals,
			sum(
				case 
					when deposit_deducted_amount = 0 
							and helmet_damage_flag = false
							and issue_category is null
					then 1
					else 0
				end
				) as cnt_successful_rentals,
			sum(fact_end_date - fact_start_date) as total_day_rental_duration,
			sum(
				case 
					when deposit_deducted_amount = 0 
							and helmet_damage_flag = false
							and issue_category is null
					then fact_end_date - fact_start_date
					else 0
				end
				) as total_day_rental_successful_duration,
			sum(total_amount) as total_amount,
			sum(total_amount) / count(rental_id) as avg_rental_amount,
			avg(fact_end_date - fact_start_date) as avg_day_rental_duration,
			max(first_bike) as first_rent_bike,
			max(first_dis_location) as first_rent_dis_location,
			max(first_rental_result) as first_rental_result
	from client_bike_rent_ext
	group by 1
),
shop_metrics as (
	select 
			dc.client_natural_key,
			min(o.order_date) as first_shop_date,
			round(sum(o.total_amount), 0) as shop_total_amount,
			round(sum(o.total_amount) / count(distinct o.order_id), 1) as shop_aov
	from core.fct_shop_order o
	inner join core.dim_client dc on dc.client_sk = o.client_sk 
	group by 1
),
repair_metrics as (
	select 
			dc.client_natural_key,
			min(r.transportation_start_date) as first_repair_date,
			sum(r.invoice_total_amount) as repair_total_amount
	from core.fct_repair r
	inner join core.dim_client dc on dc.client_sk = r.client_sk 
	where r.transportation_end_date is not null
	group by 1
),
client_attributes as (
	select 
			dc.client_natural_key,
			dc.drive_license_verified,
			dc.driving_experience_years,
			dc.gender,
			dc.nationality,
			dc.rating_score 
	from core.dim_client dc 
	where dc.current_row_indicator = true
)
select 
		cl.client_natural_key,                    -- натуральный ключ
		cl.drive_license_verified, 				  -- флаг наличия водительских прав
		cl.driving_experience_years,			  -- опыт вождения (в годах)
		cl.gender,								  -- пол клиента
		cl.nationality,							  -- национальность клиента
		cl.rating_score,						  -- внутренний рейтинг клиента
		rm.first_rent_date,						  -- дата первой аренды 
		rm.cnt_rentals,							  -- общее число завершенных аренд
		rm.cnt_successful_rentals,				  -- общее число успешных аренд (без повреждений байка и без факта выезда механиков) 
		rm.total_day_rental_duration,			  -- общая длительность всех аренд
		rm.total_day_rental_successful_duration,  -- общая длительность успешных аренд
		rm.total_amount, 						  -- общая сумма аренд
		rm.avg_rental_amount,					  -- средняя стоимость аренды
		rm.avg_day_rental_duration,				  -- средняя длительность аренды
		rm.first_rent_bike,						  -- модель байка первой аренды
		rm.first_rent_dis_location,				  -- локация выдачи первой аренды
		rm.first_rental_result,					  -- результат возврата после первой аренды
		sm.first_shop_date,						  -- дата первой покупки в магазине
		sm.shop_total_amount,					  -- общая сумма покупок в магазине
		sm.shop_aov,							  -- средний чек покупок в магазине
		rpm.first_repair_date,					  -- дата первого ремонта байка в мастерской
		rpm.repair_total_amount, 				  -- общая сумма всех счетов за ремонт байков в мастерской
		least(
			  rm.first_rent_date, 
			  sm.first_shop_date, 
			  rpm.first_repair_date
			  ) as first_touch_date,              -- общая первая дата касания сервиса
		rm.total_amount + sm.shop_total_amount + rpm.repair_total_amount as amount_across_service,     -- общая сумма, потраченная во всем сервисе
		case
			when rm.cnt_rentals = 1 then 'new_customers' 
			when rm.cnt_rentals > 1 and rm.cnt_rentals <= 5 
				 and rm.cnt_successful_rentals::decimal / rm.cnt_rentals >= 0.5 then 'loyal_customers'
			when rm.cnt_rentals > 5 
				 and rm.cnt_successful_rentals::decimal / rm.cnt_rentals >= 0.5 then 'vip_customers'
			when rm.cnt_rentals > 1 and rm.cnt_successful_rentals::decimal / rm.cnt_rentals < 0.5 then 'danger_customers'
		end as customer_segments      -- простая сегментация на основе аренды
from client_attributes cl
left join rental_metrics rm on rm.client_natural_key = cl.client_natural_key
left join shop_metrics sm on sm.client_natural_key = rm.client_natural_key 
left join repair_metrics rpm on rpm.client_natural_key = rm.client_natural_key 
where rm.first_rent_date is not null