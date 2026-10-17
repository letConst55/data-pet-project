with fct as (
    select * from {{ ref('fct_procurement') }}
),
dim_prod as (
    select * from {{ ref('dim_product') }}
),

-- 1. Проверка строгой хронологии дат пайплайна поставки
test_date_chronology as (
    select
        procurement_sk,
        'invalid_date_chronology' as error_reason
    from fct
    where order_date > shipment_departure_date
       -- Если прибытие уже заполнено, оно должно быть строго после отправки
       or (shipment_arrival_date is not null and shipment_departure_date >= shipment_arrival_date)
),

-- 2. Проверка адекватности финансовых и количественных показателей
test_positive_amounts as (
    select
        procurement_sk,
        'negative_or_zero_amounts' as error_reason
    from fct
    where product_quantity <= 0
       or payment_amount <= 0
),

-- 3. Закупать можно только физические товары (исключаем услуги тюнинга)
test_physical_products as (
    select
        f.procurement_sk,
        'procurement_of_tuning_service' as error_reason
    from fct f
    left join dim_prod p on f.product_sk = p.product_sk
    where p.is_tuning_flag = true
),

-- 4. Наличие финансовых документов (инвойс и чек)
test_invoice_presence as (
    select
        procurement_sk,
        'missing_financial_docs' as error_reason
    from fct
    where vendor_invoice_number is null
       or payment_check_number is null
)

-- Объединяем все проверки
select * from test_date_chronology
union all
select * from test_positive_amounts
union all
select * from test_physical_products
union all
select * from test_invoice_presence