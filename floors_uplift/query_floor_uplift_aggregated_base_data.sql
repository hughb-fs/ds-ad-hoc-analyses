DECLARE from_backfill_date DATE DEFAULT DATE(2025, 1, 1);
DECLARE to_backfill_date_exclusive DATE DEFAULT CURRENT_DATE();

CREATE OR REPLACE TABLE `streamamp-qa-239417.floors_uplift_US.floors_uplift_domain_2025_aggregated_base_data` AS

WITH base AS (
    SELECT  a.EventDateMST date,
            net.reg_domain(RefererURL) domain,
            Device_category,
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
            Device_category,
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
            'aljazeera.com', 'gobankingrates.com', 'vecteezy.com', 'aljazeera.net', 'bismanonline.com', 'bismanonline-app.com', 'newser.com', 'levvvel.com',
            'kprofiles.com', 'hoopgrids.com', 'scrabble-solver.com', 'allsides.com', 'livecharts.co.uk', 'videopoker.com', 'dynasty-daddy.com', 'ffonts.net',
            'clevergoat.com', 'anyconv.com', 'studylight.org', 'leconnections.app', 'stopots.com', 'example2.com', 'fantasysixpack.net', 'pop.deals', 'tpointtech.com'
            ) control_domain
    from base
    where device_category in ('tablet', 'smartphone', 'desktop', 'smartphone-ios')
),

control AS
(
    SELECT date, country_code, Device_category, 'control' domain, True control, SUM(ad_requests) ad_requests, SUM(rev) rev
    FROM base_with_control_domain
	WHERE control_domain
    GROUP BY 1, 2, 3
),

optimised AS
(
    SELECT date, country_code, Device_category, domain, False control, SUM(ad_requests) ad_requests, SUM(rev) rev
    FROM base_with_control_domain
	WHERE floors_id IS NOT NULL AND floors_id NOT IN ('timeout', 'control', 'learning') AND domain IS NOT NULL AND not control_domain
    GROUP BY 1, 2, 3, 4
),

aggregated_base_data as (
    select * from control
    union all
    select * from optimised
)
select * from aggregated_base_data;
