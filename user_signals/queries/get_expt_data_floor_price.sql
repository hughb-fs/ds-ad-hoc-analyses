with t1 as (
  select split(device_category, '_')[0] device_category_raw, right(device_category, length(device_category)-strpos(device_category,'_')) user_category, *
from `streamamp-qa-239417.training.floors_vertex_devbrowser-signal_green_28042025_expt_{EXPT_NUMBER}`
), t_user as (
  select * from t1 where user_category = 'user'
), t_no_user as (
  select * from t1 where user_category = 'no_user'
), t_prod as (
  select lower(device_category) device_category_raw, * except (device_category)
  from `sublime-elixir-273810.training.floors_vertex_main_green_28042025`
)
select cast(t_prod.floor_price as float64) floor_price_prod,
    cast(t_no_user.floor_price as float64) floor_price_no_user,
    cast(t_user.floor_price as float64) floor_price_user
from t_prod
left join t_no_user using (device_category_raw, date, hour_x, hour_y, country_code, ad_unit_name)
left join t_user using (device_category_raw, date, hour_x, hour_y, country_code, ad_unit_name)
