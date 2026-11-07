/*
-------------------------------------------------------------------------------------------------------
Test Name: dim_bikes_valid_specs
Description: 
    Checks the adequacy of technical specifications and pricing in the Bike Fleet dimension.

Business Rules Validated:
    1. Positive values: Procurement price, engine volume, and horsepower must be strictly greater than 0.
       - Failure Example: A data entry error causes a new bike's procurement price to be registered as $0,
         which would subsequently cause division-by-zero errors in ROI calculations.
    2. Valid model year: The bike's model year must be between 1990 and the current year + 1.
       - Failure Example: A typo in the source system sets a bike's year to 205, breaking age analytics.

Output: 
    Returns rows from `dim_bike` containing invalid technical or financial specifications.
-------------------------------------------------------------------------------------------------------
*/

select
    bike_sk,
    bike_natural_key,
    model_year,
    hourse_power,
    engine_volume_cc,
    procurement_price
from {{ ref('dim_bike') }}
where procurement_price <= 0
   or engine_volume_cc <= 0
   or hourse_power <= 0
   or model_year < 1990
   or model_year > extract(year from current_date) + 1