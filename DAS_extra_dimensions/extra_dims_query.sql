with base_data_domain_fs_testgroup as (
    SELECT fs_testgroup, bidder, rtt_category, fsrefresh, country_code,
        `freestar-157323.ad_manager_dtf`.device_category(device_category) device_category, <EXTRA_DIM>, status,
        sum(revenue) revenue,
        sum(session_count) session_count,
        safe_divide(sum(revenue), sum(session_count)) rps
    FROM `freestar-157323.ad_manager_dtf.daily_client_server_mask_reporting_refresh_w_domain_expanded`
    WHERE DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL <DAYS_BACK_START> DAY) AND DATE <= DATE_SUB(CURRENT_DATE(), INTERVAL <DAYS_BACK_END> DAY)
        and fs_testgroup in ('experiment', 'optimised')
        and country_code is not null
        and status != 'disabled'
        and ad_product not like '%video%'
    group by fs_testgroup, bidder, country_code, device_category, rtt_category, fsrefresh, <EXTRA_DIM>, status
), base_data_domain_expt as (
    select bidder, country_code, device_category, rtt_category, fsrefresh, <EXTRA_DIM>, status, revenue, session_count, rps
    from base_data_domain_fs_testgroup
    where fs_testgroup = 'experiment'
), results_domain_expt as (
    select bidder, country_code, device_category, rtt_category, fsrefresh, <EXTRA_DIM>, status, rps
    from base_data_domain_expt
    qualify row_number() over (partition by bidder, country_code, device_category, rtt_category, fsrefresh, <EXTRA_DIM> order by rps desc) = 1
), base_data_no_domain_expt as (
    select bidder, country_code, device_category, rtt_category, fsrefresh, status, safe_divide(sum(revenue), sum(session_count)) rps
    from base_data_domain_expt
    group by bidder, country_code, device_category, rtt_category, fsrefresh, status
), decision_no_domain_expt as (
    select bidder, country_code, device_category, rtt_category, fsrefresh, status
    from base_data_no_domain_expt
    qualify row_number() over (partition by bidder, country_code, device_category, rtt_category, fsrefresh order by rps desc) = 1
), results_no_domain_expt as (
    select base_data_domain_expt.* except (revenue, session_count)
    from decision_no_domain_expt
    join base_data_domain_expt using (bidder, country_code, device_category, rtt_category, fsrefresh, status)
), results_domain_opt as (
    select bidder, country_code, device_category, rtt_category, fsrefresh, <EXTRA_DIM>, sum(session_count) session_count
    from base_data_domain_fs_testgroup
    where fs_testgroup = 'optimised'
    group by bidder, country_code, device_category, rtt_category, fsrefresh, <EXTRA_DIM>
), results_all as (
    select t1.*, 
        t2.status as status_domain, t2.rps rps_domain, t2.rps * session_count revenue_domain,
        t3.status as status_no_domain, t3.rps rps_no_domain, t3.rps * session_count revenue_no_domain
    from results_domain_opt t1
    join results_domain_expt t2 using (bidder, country_code, device_category, rtt_category, fsrefresh, <EXTRA_DIM>)
    join results_no_domain_expt t3 using (bidder, country_code, device_category, rtt_category, fsrefresh, <EXTRA_DIM>)
)
select count(*) unique_cohorts, 
    sum(session_count) total_sessions,
    sum(revenue_no_domain) revenue_no_domain, 
    sum(revenue_domain) revenue_domain 
from results_all
