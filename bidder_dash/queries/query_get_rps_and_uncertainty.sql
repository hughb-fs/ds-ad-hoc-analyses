
with status_fix as (

    select * except (status),
        if(bidder in  ('ix', 'rise', 'appnexus', 'rubicon', 'triplelift', 'pubmatic') and date_hour > '2024-08-28 20:00:00' and status = 'disabled', 'client', status) status
    from `{project_id}.DAS_eventstream_session_data.{tablename}`

), agg as (

    select {select_dimensions},
        sum(session_count) session_count,
        sum(revenue) sum_revenue,
        sum(revenue_sq) sum_revenue_sq
    from status_fix
    {where}
    group by {group_by_dimensions}

), stats as (

    select {group_by_dimensions},
        session_count,
        safe_divide(sum_revenue, session_count) mean_revenue,
        safe_divide(sum_revenue_sq, session_count) mean_revenue_sq
    from agg

)

select {group_by_dimensions},
    session_count,
    mean_revenue * 1000 rps,
    sqrt((mean_revenue_sq - pow(mean_revenue, 2)) / session_count) * 1000 rps_std

from stats


