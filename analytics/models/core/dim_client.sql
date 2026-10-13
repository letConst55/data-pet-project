-- Инкрементальная версия

{{
    config(
        materialized='incremental',
        unique_key='client_sk',
        schema='core'
    )
}}

with new_events as (
        select 
                *
        from {{ ref('stg_client_profile_updated') }}
        {% if is_incremental() %}
        where event_timestamp > (select max(row_effective_date) from {{ this }})
        {% endif %}
),
-- Дедуплицируем новую пачку событий
deduped_new_events as (
    select distinct on (client_id, event_timestamp)
        client_id as client_natural_key,
        full_name,
        gender,
        birthday,
        salutation,
        preferred_payment_method,
        phone,
        email,
        nationality,
        residential_address,
        driving_experience_years,
        drive_license_category,
        drive_license_verified,
        rating_score,
        event_timestamp as row_effective_date
    from new_events
    order by client_id, event_timestamp, loaded_at desc
),
-- Берем из УЖЕ существующей витрины dim_clients ({{ this }}) только открытые записи 
-- и ТОЛЬКО по тем клиентам, которые пришли в новой пачке событий
{% if is_incremental() %}
existing_active_records as (
    select
        client_natural_key,
        full_name,
        gender,
        birthday,
        salutation,
        preferred_payment_method,
        phone,
        email,
        nationality,
        residential_address,
        driving_experience_years,
        drive_license_category,
        drive_license_verified,
        rating_score,
        row_effective_date
    from {{ this }}
    where true 
    and current_row_indicator = true
    and client_natural_key in (select distinct client_natural_key from deduped_new_events)
),
{% endif %}
-- Объединяем открытые старые записи и новые события, чтобы сшить цепочку версий
combined_records as (
    select * from deduped_new_events
    {% if is_incremental() %}
    union all 
    select * from existing_active_records
    {% endif %}
),
-- Считаем LEAD() только по затронутым клиентам
scd2_calculated as (
    select
        *,
        lead(row_effective_date) over (partition by client_natural_key 
                order by row_effective_date
        ) as next_event_timestamp
    from combined_records
),
final_ as (
    select
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,
        -- У старой записи этот хэш совпадет с тем, что уже в таблице -> сработает UPDATE
        -- У новой записи хэш будет новым -> сработает INSERT
        md5(client_natural_key || '_' || row_effective_date::varchar) as client_sk,
        client_natural_key,
        full_name,
        gender,
        birthday,
        salutation,
        preferred_payment_method,
        phone,
        email,
        nationality,
        residential_address,
        driving_experience_years,
        drive_license_category,
        drive_license_verified,
        rating_score,
        row_effective_date,
        coalesce(next_event_timestamp, '9999-12-31 23:59:59'::timestamp) as row_expiration_date,
        case 
            when next_event_timestamp is null then true 
            else false 
        end as current_row_indicator
    from scd2_calculated
)
select 
    *
from final_