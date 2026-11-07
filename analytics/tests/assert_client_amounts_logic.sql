/*
-------------------------------------------------------------------------------------------------------
Test Name: assert_client_amounts_logic
Description: 
    Validates the mathematical consistency of the Customer Lifetime Value (LTV) calculations.
    This test verifies that the grand total revenue across all services (LTV) strictly equals 
    the cumulative sum of rentals, shop purchases, and external repairs.

Business Rules Validated:
    - Cross-domain Revenue Consistency: `lifetime_total_amount` must match the sum of accumulating 
      totals from the three separate business domains.
    - Failure Example: A client makes a retail purchase, but the `COALESCE` function fails to handle a 
      `NULL` value in the repair domain, causing the addition operation to return `NULL` for the entire LTV.

Output: 
    Returns clients and months where the calculated LTV does not match the sum of its components.
-------------------------------------------------------------------------------------------------------
*/

with rollup_check as (
    select
        client_natural_key,
        report_month,
        
        -- Calculate expected LTV by summing the running totals for each domain
        sum(coalesce(mtd_rental_amount, 0)) over (partition by client_natural_key order by report_month) as expected_lifetime_rental,
        sum(coalesce(mtd_shop_amount, 0)) over (partition by client_natural_key order by report_month) as expected_lifetime_shop,
        sum(coalesce(mtd_repair_amount, 0)) over (partition by client_natural_key order by report_month) as expected_lifetime_repair,
        
        -- The actual calculated LTV value in the datamart
        lifetime_total_amount
        
    from {{ ref('stats_by_clients') }}
)

select
    client_natural_key,
    report_month,
    expected_lifetime_rental,
    expected_lifetime_shop,
    expected_lifetime_repair,
    lifetime_total_amount
from rollup_check
where round(lifetime_total_amount::numeric, 2) != round((
    coalesce(expected_lifetime_rental, 0) + 
    coalesce(expected_lifetime_shop, 0) + 
    coalesce(expected_lifetime_repair, 0)
)::numeric, 2)