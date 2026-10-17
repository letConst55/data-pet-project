with score_limits as (
    select 
        rental_id,
        pre_rental_condition_score,
        post_rental_condition_score,
        case
            when actual_start_mileage >= 65000 then 1
            when actual_start_mileage >= 50000 then 2
            when actual_start_mileage >= 40000 then 3
            when actual_start_mileage >= 32000 then 4
            when actual_start_mileage >= 25000 then 5
            when actual_start_mileage >= 18000 then 6
            when actual_start_mileage >= 12000 then 7
            when actual_start_mileage >= 7000 then 8
            when actual_start_mileage >= 3000 then 9
            else 10
        end as max_allowed_pre_score,
        case
            when actual_end_mileage >= 65000 then 1
            when actual_end_mileage >= 50000 then 2
            when actual_end_mileage >= 40000 then 3
            when actual_end_mileage >= 32000 then 4
            when actual_end_mileage >= 25000 then 5
            when actual_end_mileage >= 18000 then 6
            when actual_end_mileage >= 12000 then 7
            when actual_end_mileage >= 7000 then 8
            when actual_end_mileage >= 3000 then 9
            else 10
        end as max_allowed_post_score
    from {{ ref('fct_client_bike_rent') }}
)

select rental_id
from score_limits
where pre_rental_condition_score > max_allowed_pre_score
   or (post_rental_condition_score is not null and post_rental_condition_score > max_allowed_post_score)