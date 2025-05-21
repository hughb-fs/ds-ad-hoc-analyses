DECLARE from_backfill_date DATE DEFAULT date_sub(date_trunc(CURRENT_DATE(), month), interval 1 month);
DECLARE to_backfill_date_exclusive DATE DEFAULT date_trunc(CURRENT_DATE(), month);


BEGIN TRANSACTION;
DELETE FROM floors_us.daily_uplift_us_gam_v2_domain_monthly WHERE date >= from_backfill_date AND date < to_backfill_date_exclusive;
INSERT INTO floors_us.daily_uplift_us_gam_v2_domain_monthly


WITH base AS (
    SELECT  a.EventDateMST date,
            net.reg_domain(RefererURL) domain,
            device_category,
            REGEXP_EXTRACT(CustomTargeting,".*floors_id=(.*?)[;$]") floors_id,
            GeoLookup.CountryCode country_code,
            CASE WHEN CostType="CPM" THEN CostPerUnitInNetworkCurrency/1000 ELSE 0 END rev,
            1 ad_requests
    FROM `freestar-prod.data_transfer.NetworkImpressions` a
    left join `freestar-157323.ad_manager_dtf.p_MatchTableLineItem_15184186` match on a.LineItemId=match.Id AND match._PARTITIONDATE = a.EventDateMST
    left join `freestar-157323.ad_manager_dtf.p_MatchTableCompany_15184186` co on a.AdvertiserId=co.Id AND co._PARTITIONDATE = a.EventDateMST
    LEFT JOIN `freestar-157323.ad_manager_dtf.p_MatchTableGeoTarget_15184186` GeoLookup ON GeoLookup.Id = a.CountryId AND GeoLookup._PARTITIONDATE = a.EventDateMST

    WHERE a.EventDateMST >= from_backfill_date AND a.EventDateMST < to_backfill_date_exclusive
    AND (REGEXP_CONTAINS(co.Name, '(?i)^((T13-.*)|(fspb_.*)|(Google.*)|(Amazon)|(freestar_prebid)|(Mingle2)|(Brickseek)|(FootballDB)|(Ideas People.*)|(Blue Media Services)|(Mediaforce)|(WhatIsMyIPAddress)|(-)|(Open Bidding)|(AdSparc.*)|(Triple13)|(Adexchange)|(Ad Exchange)|(Freestar))$') OR LineItemId = 0)

    UNION ALL

    SELECT  a.EventDateMST date,
            net.reg_domain(RefererURL) domain,
            device_category,
            REGEXP_EXTRACT(CustomTargeting,".*floors_id=(.*?)[;$]") floors_id,
            GeoLookup.CountryCode country_code,
            EstimatedBackfillRevenue rev,
            1 ad_requests
    FROM `freestar-prod.data_transfer.NetworkBackfillImpressions` a
    LEFT JOIN `freestar-157323.ad_manager_dtf.p_MatchTableGeoTarget_15184186` GeoLookup ON GeoLookup.Id = a.CountryId AND GeoLookup._PARTITIONDATE = a.EventDateMST
    WHERE a.EventDateMST >= from_backfill_date AND a.EventDateMST < to_backfill_date_exclusive
),

base_with_control_domain as (
    select * except (rev), IFNULL(rev, 0) rev,
        domain IN (
            'aljazeera.com', 'gobankingrates.com', 'vecteezy.com', 'aljazeera.net', 'bismanonline.com', 'bismanonline-app.com', 'newser.com', 'levvvel.com', 'kprofiles.com',
            'hoopgrids.com', 'scrabble-solver.com', 'allsides.com', 'livecharts.co.uk', 'videopoker.com', 'dynasty-daddy.com', 'ffonts.net', 'clevergoat.com', 'anyconv.com',
            'studylight.org', 'leconnections.app', 'stopots.com', 'example2.com', 'fantasysixpack.net', 'pop.deals', 'tpointtech.com'
            ) control_domain
    from base
    where device_category in ('tablet', 'smartphone', 'desktop', 'smartphone-ios')
),

control AS
(
    SELECT date, country_code, device_category, 'control' domain, True control, SUM(ad_requests) ad_requests, SUM(rev) rev
    FROM base_with_control_domain
	WHERE control_domain
    GROUP BY 1, 2, 3
),

optimised AS
(
    SELECT date, country_code, device_category, domain, False control, SUM(ad_requests) ad_requests, SUM(rev) rev
    FROM base_with_control_domain
	WHERE floors_id IS NOT NULL AND floors_id NOT IN ('timeout', 'control', 'learning') AND domain IS NOT NULL AND not control_domain
    GROUP BY 1, 2, 3, 4
),

aggregated_base_data as (
    select * from control
    union all
    select * from optimised
),

aggregated_base_data_month as (
    select date_trunc(date, month) date, domain, country_code, device_category, control, sum(ad_requests) ad_requests, sum(rev) rev
    from aggregated_base_data
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

select * from domain_stats;

COMMIT TRANSACTION;

-- template for how looker should do aggregation
--   sum(estimated_floors_revenue_uplift),
--   sum(estimated_cpma_optimised * ad_requests) / sum(ad_requests),
--   sum(estimated_cpma_control * ad_requests) / sum(ad_requests),
--   sum(estimated_floors_cpma_uplift_percent * ad_requests) / sum(ad_requests)
