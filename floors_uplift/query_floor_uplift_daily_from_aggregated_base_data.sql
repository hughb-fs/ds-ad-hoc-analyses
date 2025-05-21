create table floors_us.daily_uplift_us_gam_v2_domain_monthly as

with
aggregated_base_data_month as (
    select date_trunc(date, month) date,
      --date,
      domain, country_code, device_category, control, sum(ad_requests) ad_requests, sum(rev) rev
    from `streamamp-qa-239417.floors_uplift_US.floors_uplift_domain_2025_aggregated_base_data`
    where device_category in ('tablet', 'smartphone', 'desktop', 'smartphone-ios')
        and date < '2025-5-1'
    group by 1, 2, 3, 4, 5
),

aggregated_base_data_with_continent as (
    select *
    from aggregated_base_data_month
    join `sublime-elixir-273810.ideal_ad_stack.continent_country_mapping` on country_code = geo_country
),

qualifying_country_codes as (
    select date, country_code
    from aggregated_base_data_with_continent
    group by 1, 2
    qualify row_number() over (partition by date order by least(sum(if(control, ad_requests, 0)), sum(if(control, 0, ad_requests))) desc) <= 30
),

aggregated_base_data_country_continent as (
    select * except (country_code, geo_country, geo_continent), coalesce(qualifying_country_codes.country_code, 'continent_' || geo_continent) country_continent
    from aggregated_base_data_with_continent
    left join qualifying_country_codes using (date, country_code)
),

cpma_country_continent_device as (
    select date, country_continent, device_category,
        safe_divide(sum(if(control, 0, rev)), sum(if(control, 0, ad_requests))) * 1000 cpma_optimised,
        safe_divide(sum(if(control, rev, 0)), sum(if(control, ad_requests, 0))) * 1000 cpma_control,
        sum(if(control, 0, ad_requests)) ad_requests_optimised,
        sum(if(control, ad_requests, 0)) ad_requests_control
    from aggregated_base_data_country_continent
    where country_continent not like 'continent_%'
    group by 1, 2, 3

    union all

    select date, 'continent_' || geo_continent country_continent, device_category,
        safe_divide(sum(if(control, 0, rev)), sum(if(control, 0, ad_requests))) * 1000 cpma_optimised,
        safe_divide(sum(if(control, rev, 0)), sum(if(control, ad_requests, 0))) * 1000 cpma_control,
        sum(if(control, 0, ad_requests)) ad_requests_optimised,
        sum(if(control, ad_requests, 0)) ad_requests_control
    from aggregated_base_data_with_continent
    group by 1, 2, 3
),

domain_aggregates as (
  select date, domain, country_continent, device_category,
      sum(ad_requests) domain_ad_requests, sum(rev) domain_rev
    from aggregated_base_data_country_continent
    where not control and
      country_continent not like 'continent_%'
    group by 1, 2, 3, 4

    union all

    select date, domain, 'continent_' || geo_continent country_continent, device_category,
      sum(ad_requests) domain_ad_requests, sum(rev) domain_rev
    from aggregated_base_data_with_continent
    where not control
    group by 1, 2, 3, 4
),

domain_stats as (
  select date, domain,
    safe_divide(sum(cpma_optimised * domain_ad_requests), sum(domain_ad_requests)) estimated_cpma_optimised,
    safe_divide(sum(cpma_control * domain_ad_requests), sum(domain_ad_requests)) estimated_cpma_control,
    100 * (1 - safe_divide(sum(cpma_control * domain_ad_requests), sum(cpma_optimised * domain_ad_requests))) estimated_floors_cpma_uplift_percent,
    sum((1 - safe_divide(cpma_control, cpma_optimised)) * domain_rev) estimated_floors_revenue_uplift,
    sum(domain_ad_requests) ad_requests,
    sum(domain_rev) total_revenue
  from domain_aggregates
  join cpma_country_continent_device using (country_continent, date, device_category)
  group by 1, 2
)

select *
from domain_stats;

-- template for how looker should do aggregation
-- select date, sum(estimated_floors_revenue_uplift),
--   sum(estimated_cpma_optimised * ad_requests) / sum(ad_requests),
--   sum(estimated_cpma_control * ad_requests) / sum(ad_requests),
--   sum(estimated_floors_cpma_uplift_percent * ad_requests) / sum(ad_requests)
--
-- from domain_stats
-- group by 1
-- order by 1
