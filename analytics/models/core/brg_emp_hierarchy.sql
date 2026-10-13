{{
    config(
        materialized='table',
        schema='core'
    )
}}

-- Ключевое слово RECURSIVE обязательно для работы с иерархией в PostgreSQL
with recursive active_employees as (
    -- Берем только актуальный срез работающих сотрудников
    select
        employee_natural_key,
        manager_employee_id
    from {{ ref('dim_employee') }}
    where current_row_indicator = true
      and is_active_flg = true
),

-- Рекурсивный CTE для разворачивания дерева (транзитивное замыкание)
hierarchy_paths as (
    -- Базовый случай: каждый сотрудник подчиняется самому себе (уровень 0)
    select
        employee_natural_key as manager_employee_id,
        employee_natural_key as subordinate_employee_id,
        0 as hierarchy_depth
    from active_employees
    
    union all
    
    -- Рекурсивный шаг: спускаемся вниз по дереву подчинения
    select
        p.manager_employee_id,
        e.employee_natural_key as subordinate_employee_id,
        p.hierarchy_depth + 1 as hierarchy_depth
    from hierarchy_paths p
    join active_employees e 
      on p.subordinate_employee_id = e.manager_employee_id
),

-- Определяем верхушку иерархии (CEO и те, у кого нет начальника)
top_levels as (
    select employee_natural_key
    from active_employees
    where manager_employee_id is null
),

-- Определяем линейный персонал (листья дерева - те, у кого нет подчиненных)
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
        -- Технические поля
        '{{ invocation_id }}'::varchar as dataflow_id,
        current_timestamp as dataflow_dttm,

        -- Ключи
        h.manager_employee_id,
        h.subordinate_employee_id,
        h.hierarchy_depth,
        
        -- Флаг: является ли менеджер в этой связке сотрудником высшего звена (CEO)
        case when t.employee_natural_key is not null then true else false end as is_top_level_flg,
        
        -- Флаг: является ли подчиненный в этой связке линейным сотрудником (без своих подчиненных)
        case when b.employee_natural_key is not null then true else false end as is_bottom_level_flg
        
    from hierarchy_paths h
    left join top_levels t on h.manager_employee_id = t.employee_natural_key
    left join bottom_levels b on h.subordinate_employee_id = b.employee_natural_key
)

select * from final