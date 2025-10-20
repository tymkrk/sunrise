select
	action_type,
	status,
	date_start,
	date_end
from
	(
	select 
		'Data Warehouse Load' as action_type,
		'Success' as status, 
		dateadd(hour,2,date_start) as date_start,
		dateadd(hour,2,date_end) as date_end
	from org._tb_b2b_data_load_status 
	where type = 'DWH_LOAD'

	union all

	select 
		'Beqom Load' as action_type,
		CASE 
			WHEN Note = 'Sunrise B2B - No refresh' THEN 'No Load'
			WHEN Note = 'Sunrise B2B - Refresh done' THEN  'Success'
			ELSE '-1' 
		END as status,
		dateadd(hour,2,StartTime) as date_start,
		dateadd(hour,2,EndTime) as date_end -- select *
	from _tb_stored_procedure_audit
	where object = '_sp_b2b_etl_refresh_all'
	) tab
where date_start > '2025-01-01'
order by date_start desc 

