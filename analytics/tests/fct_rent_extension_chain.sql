with extended as (
    select 
        rental_id,
        client_sk,
        bike_sk,
        fact_end_date
    from {{ ref('fct_client_bike_rent') }}
    where rent_extend_flag = true
),
subsequent as (
    select 
        client_sk,
        bike_sk,
        coalesce(fact_start_date, planned_start_date) as start_date
    from {{ ref('fct_client_bike_rent') }}
)

select 
        e.rental_id
from extended e left join subsequent s on e.client_sk = s.client_sk
                                       and e.bike_sk = s.bike_sk
                                       and s.start_date >= e.fact_end_date
where s.client_sk is null