/*
-------------------------------------------------------------------------------------------------------
Test Name: dim_clients_scd2_intervals
Description: 
    Hunts for anomalies within the SCD Type 2 version chain for clients.

Business Rules Validated:
    1. Date Inversion: A record's effective date must be strictly earlier than its expiration date.
    2. No Gaps or Overlaps: The expiration date of a current version must exactly match the effective 
       date of the immediate next version.
       - Failure Example: A batch processing delay causes two profile updates for the same client to 
         be processed out of order, creating overlapping validity periods that crash Point-in-Time joins.
    3. Active Flag Accuracy: A record cannot be marked as active (`current_row_indicator = true`) if a 
       subsequent version exists.
    4. Infinity Date: The final, active version must carry the '9999-12-31' infinity date placeholder.

Output: 
    Returns rows from `dim_client` containing invalid SCD2 date intervals or corrupted flags.
-------------------------------------------------------------------------------------------------------
*/

with version_chains as (
    select
        client_sk,
        client_natural_key,
        row_effective_date,
        row_expiration_date,
        current_row_indicator,
        -- Fetch the effective date of the subsequent version based on chronological order
        lead(row_effective_date) over (
            partition by client_natural_key 
            order by row_effective_date
        ) as next_effective_date
    from {{ ref('dim_client') }}
)

select 
    *
from version_chains
where 
    -- 1. Error within the row itself (start date is later than or equal to end date)
    row_effective_date >= row_expiration_date
    
    -- 2. A subsequent version exists, but there is a gap or overlap between them
    or (next_effective_date is not null and row_expiration_date != next_effective_date)
    
    -- 3. A subsequent version exists, yet the current row is flagged as active
    or (next_effective_date is not null and current_row_indicator = true)
    
    -- 4. This is the final version, but it lacks the infinity date or the active flag
    or (next_effective_date is null and (
        row_expiration_date != '9999-12-31 23:59:59'::timestamp 
        or current_row_indicator != true
    ))