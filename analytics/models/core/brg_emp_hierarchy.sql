{{
    config(
        materialized='table',
        schema='core'
    )
}}

-- The RECURSIVE keyword is required for working with hierarchies in PostgreSQL.
with recursive active_employees as (
    -- We take only the current snapshot of active employees.
    select
        employee_natural_key,
        manager_employee_id
    from {{ ref('dim_employee') }}
    where current_row_indicator = true
      and is_active_flg = true
),

-- Recursive CTE for traversing a tree (transitive closure)
hierarchy_paths as (
    -- Base case: each employee reports to themselves (level 0)
    select
        employee_natural_key as manager_employee_id,
        employee_natural_key as subordinate_employee_id,
        0 as hierarchy_depth
    from active_employees
    
    union all
    
    -- Recursive step: descend the hierarchy tree
    select
        p.manager_employee_id,
        e.employee_natural_key as subordinate_employee_id,
        p.hierarchy_depth + 1 as hierarchy_depth
    from hierarchy_paths p
    join active_employees e 
      on p.subordinate_employee_id = e.manager_employee_id
),

-- Identifying the top of the hierarchy
top_levels as (
    select employee_natural_key
    from active_employees
    where manager_employee_id is null
),

-- Identify the bottom-level personnel (the leaves of the tree—those who have no subordinates)
bottom_levels as (
    select employee_natural_key
    from active_employees
    where employee_natural_key not in (
        select distinct manager_employee_id 
        from active_employees 
        where manager_employee_id is not null
    )
),

final as (
    select
        -- technical fields
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,

        -- keys
        h.manager_employee_id,
        h.subordinate_employee_id,
        h.hierarchy_depth,
        
        -- Flag: whether the manager in this relationship is a top-level executive (CEO)
        case when t.employee_natural_key is not null then true else false end as is_top_level_flg,
        
        -- Flag: indicates whether the subordinate in this relationship is an individual contributor (i.e., has no subordinates of their own)
        case when b.employee_natural_key is not null then true else false end as is_bottom_level_flg
        
    from hierarchy_paths h
    left join top_levels t on h.manager_employee_id = t.employee_natural_key
    left join bottom_levels b on h.subordinate_employee_id = b.employee_natural_key
)

select * from final