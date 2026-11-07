/*
-------------------------------------------------------------------------------------------------------
Test Name: dim_calendar_no_gaps
Description: 
    Ensures continuous date coverage without missing days (gaps) in the calendar dimension.

Business Rules Validated:
    - Contiguous Dates: The total number of rows in the calendar must exactly equal the difference 
      in days between the maximum and minimum dates, plus one.
    - Failure Example: An ETL failure drops data for February 29th during a leap year, causing 
      monthly aggregations and moving averages for that period to be skewed.

Output: 
    Returns the total rows and expected days ONLY if there is a mismatch (returns 1 row on failure).
-------------------------------------------------------------------------------------------------------
*/

select
    count(*) as total_rows,
    (max(date) - min(date) + 1) as expected_days
from {{ ref('dim_calendar') }}
having count(*) != (max(date) - min(date) + 1)