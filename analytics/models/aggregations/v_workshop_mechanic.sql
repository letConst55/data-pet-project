{{
    config(
        materialized='view',
        schema='aggregations'
    )
}}

select
    employee_sk as workshop_mechanic_sk, -- Role key
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
where can_workshop_repair_flg = true