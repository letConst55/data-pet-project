{{
    config(
        materialized='view',
        schema='aggregations'
    )
}}

select
    employee_sk as rental_employee_sk, -- Специфичный ролевой ключ
    employee_natural_key,
    full_name,
    phone,
    email,
    department,
    position_title,
    grade_level,
    assigned_location_id,
    manager_employee_id,
    is_active_flg,
    row_effective_date,
    row_expiration_date,
    current_row_indicator
from {{ ref('dim_employee') }}
where can_dispense_return_flg = true