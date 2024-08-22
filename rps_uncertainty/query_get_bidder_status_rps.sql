
with t1 as (
  select bucket_number, bucket_number * {samples_per_bucket} + sample_number + 1 rn
  from (select * from unnest(GENERATE_ARRAY(0, {samples_per_bucket} - 1)) as sample_number)
  cross join (select * from unnest(GENERATE_ARRAY(0, {number_of_buckets} - 1)) as bucket_number )
), t2 as (
  select revenue, row_number() over(order by rand()) rn
  from `streamamp-qa-239417.DAS_eventstream_session_data.{eventstream_session_data_tablename}`
  where REGEXP_CONTAINS(fs_clientservermask, '{bidder_mask}')
), t3 as (
  select bucket_number, avg(revenue) * 1000 bucket_rps
  from t1 join t2 using (rn)
  group by 1
)
select bucket_rps from t3


