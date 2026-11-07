/*
-------------------------------------------------------------------------------------------------------
Test Name: fct_procurement_business_logic
Description: 
    Comprehensive business logic validation for the Accumulating Snapshot fact table tracking 
    the procurement pipeline from suppliers. This test consolidates 4 independent checks into 
    a single CTE-based script for efficient execution.

Business Rules Validated:
    1. Pipeline Chronology: The procurement order date must precede or equal the shipment departure 
       date from the vendor. If an arrival date is logged, it must strictly follow the departure date.
       - Failure Example: A logistics API glitch swaps the departure and arrival timestamps, creating 
         a negative transit time that breaks Lead Time analytics.
    2. Financial and Volume Adequacy: Both the quantity of procured products and the payment amount 
       must be strictly greater than zero.
       - Failure Example: A procurement manager places an empty draft order (qty = 0) that accidentally 
         slips into the production database, inflating the total count of shipments.
    3. Physical Goods Only: Tuning and repair services (`is_tuning_flag` = true) cannot be purchased 
       from external vendors; they are performed in-house.
       - Failure Example: A data entry error tags an in-house "Fork Overhaul" service as an item 
         procured from an external parts supplier.
    4. Financial Documentation: Because payments are processed immediately upon ordering in this 
       business model, both the vendor invoice number and the payment check number must be present.
       - Failure Example: An API timeout occurs with the payment gateway, leaving the payment check 
         number NULL while the shipment is already on its way.

Output: 
    Returns `procurement_sk` alongside an `error_reason` flag for any violated rule.
-------------------------------------------------------------------------------------------------------
*/

with fct as (
    select * from {{ ref('fct_procurement') }}
),
dim_prod as (
    select * from {{ ref('dim_product') }}
),

-- 1. Verify strict date chronology across the procurement pipeline
test_date_chronology as (
    select
        procurement_sk,
        'invalid_date_chronology' as error_reason
    from fct
    where order_date > shipment_departure_date
       -- If the arrival date is populated, it must be strictly after the departure date
       or (shipment_arrival_date is not null and shipment_departure_date >= shipment_arrival_date)
),

-- 2. Verify the adequacy of financial and quantitative metrics
test_positive_amounts as (
    select
        procurement_sk,
        'negative_or_zero_amounts' as error_reason
    from fct
    where product_quantity <= 0
       or payment_amount <= 0
),

-- 3. Procurement is restricted to physical goods (exclude tuning services)
test_physical_products as (
    select
        f.procurement_sk,
        'procurement_of_tuning_service' as error_reason
    from fct f
    left join dim_prod p on f.product_sk = p.product_sk
    where p.is_tuning_flag = true
),

-- 4. Presence of financial documentation (invoice and payment check)
test_invoice_presence as (
    select
        procurement_sk,
        'missing_financial_docs' as error_reason
    from fct
    where vendor_invoice_number is null
       or payment_check_number is null
)

-- Combine all validation results
select * from test_date_chronology
union all
select * from test_positive_amounts
union all
select * from test_physical_products
union all
select * from test_invoice_presence