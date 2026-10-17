with fct as (
    select * from {{ ref('fct_inventory_snapshot') }}
),
dim_prod as (
    select * from {{ ref('dim_product') }}
),

-- 1. Логика доступности (флаг должен строго соответствовать остатку)
test_availability as (
    select
        inventory_snapshot_sk,
        'availability_flag_mismatch' as error_reason
    from fct
    where (product_quantity > 0 and available_flag = false)
       or (product_quantity <= 0 and available_flag = true)
),

-- 2. Логика ожидаемых поставок (дата есть только если товар заказан)
test_shipment_dates as (
    select
        inventory_snapshot_sk,
        'shipment_date_logic_error' as error_reason
    from fct
    where (isin_shipment_flag = true and planned_delivery_date is null)
       or (isin_shipment_flag = false and planned_delivery_date is not null)
),

-- 3. Хронология поставки (ожидаемая дата не может быть в прошлом относительно даты снимка)
test_delivery_chronology as (
    select
        inventory_snapshot_sk,
        'delivery_date_in_past' as error_reason
    from fct
    where planned_delivery_date is not null
      and planned_delivery_date < snapshot_date_key
),

-- 4. В снимок попадают только физические товары (без услуг тюнинга)
test_physical_products as (
    select
        f.inventory_snapshot_sk,
        'snapshot_contains_tuning_service' as error_reason
    from fct f
    left join dim_prod p on f.product_sk = p.product_sk
    where p.is_tuning_flag = true
),

-- 5. День снятия снимка (всегда должно быть воскресенье, 7 день недели)
test_snapshot_day as (
    select
        inventory_snapshot_sk,
        'snapshot_not_on_sunday' as error_reason
    from fct
    -- Функция extract(isodow) в PostgreSQL возвращает 1 для понедельника и 7 для воскресенья
    where extract(isodow from snapshot_date_key) != 7
)

-- Объединяем все проверки
select * from test_availability
union all
select * from test_shipment_dates
union all
select * from test_delivery_chronology
union all
select * from test_physical_products
union all
select * from test_snapshot_day