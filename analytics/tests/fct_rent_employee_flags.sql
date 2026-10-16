-- Проверка, что сотрудники, оформляющие аренду, имеют допуск can_dispense_return_flg
with invalid_employees as (
    select 
        f.rental_id,
        ed.can_dispense_return_flg as disp_emp_flag,
        er.can_dispense_return_flg as ret_emp_flag
    from {{ ref('fct_client_bike_rent') }} f
    left join {{ ref('dim_employee') }} ed on f.employee_disp_id = ed.employee_sk
    left join {{ ref('dim_employee') }} er on f.employee_return_id = er.employee_sk
)

select rental_id
from invalid_employees
where disp_emp_flag = false
   or ret_emp_flag = false