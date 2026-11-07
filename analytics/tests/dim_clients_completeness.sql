/*
-------------------------------------------------------------------------------------------------------
Test Name: dim_clients_completeness
Description: 
    Verifies that all clients from the staging layer successfully migrated to the dimension 
    and that exactly one active record exists per client.

Business Rules Validated:
    1. Full Migration: No client present in `stg_client_profile_updated` should be missing from `dim_client`.
       - Failure Example: A client's JSON payload contained a corrupt character, causing the staging 
         model to parse it, but the SCD2 incremental load dropped the record.
    2. Active Record Uniqueness: Every client must have exactly one active version (`current_row_indicator = true`).
       - Failure Example: A bug in the pipeline failed to close out the previous version of a client 
         during an address update, resulting in two active records and inflating the total customer count.

Output: 
    Returns `client_natural_key` identifiers that are missing from either staging or the dimension, 
    or that possess 0 or >1 active rows.
-------------------------------------------------------------------------------------------------------
*/

with stg_clients as (
    select distinct client_id as client_natural_key
    from {{ ref('stg_client_profile_updated') }}
),

dim_summary as (
    select
        client_natural_key,
        count(*) filter (where current_row_indicator = true) as active_rows_cnt
    from {{ ref('dim_client') }}
    group by client_natural_key
)

select
    coalesce(s.client_natural_key, d.client_natural_key) as client_natural_key,
    s.client_natural_key as in_staging,
    d.client_natural_key as in_dim,
    coalesce(d.active_rows_cnt, 0) as active_rows_cnt
from stg_clients s
full outer join dim_summary d
    on s.client_natural_key = d.client_natural_key
where s.client_natural_key is null          -- Client is in the dimension but missing from staging
   or d.client_natural_key is null          -- Client was lost in transit from staging to the dimension
   or d.active_rows_cnt != 1                -- The client has 0 or >1 open versions