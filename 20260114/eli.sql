CREATE procedure [dbo].[_sp_b2b_calc_eligible_employees_situations]
	@id_payment_dates	int
,	@debug_mode			bit				= 0
,	@debug_tables_enum	int				= 65535
,	@report_mode		bit				= 0
,	@person_id			int				= null
,	@team_name			nvarchar(2000)	= null
,	@person_id_filter	xml				= null
,	@individual_mode	bit				= 0
,	@snapshot_paydate	date 			= null output
,	@current_date		date			= null

/* @debug_tables_enum parameter:
1		global_params
2		#employee_plan_assignment
4		#plan_definition
8		#target
16		#result
32		#calc_team_data
64		#calc_company_data
128		#accelerator_ranges_static
256		#result_accelerated_individual
512		#result_details
1024	#achievement_accelerated_segment
2048	#achievement_accelerated_metric
4096	#achievement_accelerated
8192	#payee_data
16383	All tables
*/
AS
BEGIN

	set ansi_warnings off;
	set nocount on;

	/* =================================================================================== */
	/* Get plan-global parameter variables ----------------------------------------------- */
	/* =================================================================================== */


	DECLARE @procedure_name	nvarchar(100)	= object_name(@@procid)
			,@note VARCHAR(1000)			= CONCAT(
				'@id_payment_dates = '		,ISNULL(QUOTENAME(@id_payment_dates	, ''''), 'NULL')	
				,',@debug_mode = '			,ISNULL(QUOTENAME(@debug_mode		, ''''), 'NULL')	
				,',@debug_tables_enum = '	,ISNULL(QUOTENAME(@debug_tables_enum, ''''), 'NULL')	
				,',@report_mode = '			,ISNULL(QUOTENAME(@report_mode		, ''''), 'NULL')
				,',@person_id = '			,ISNULL(QUOTENAME(@person_id		, ''''), 'NULL')	
				,',@team_name = '			,ISNULL(QUOTENAME(@team_name		, ''''), 'NULL')	
				,',@person_id_filter = '	,ISNULL(QUOTENAME(cast(@person_id_filter as nvarchar(1024))	, ''''), 'NULL')
				,',@individual_mode = '		,ISNULL(QUOTENAME(@individual_mode	, ''''), 'NULL')
				,',@snapshot_paydate = '	,ISNULL(QUOTENAME(@snapshot_paydate	, ''''), 'NULL')
				,',@current_date = '		,ISNULL(QUOTENAME(@current_date		, ''''), 'NULL'))
			,@event_id int

	----------------------------------------------------------------------------------------------------------------------------------
	-- Execution log: START
	----------------------------------------------------------------------------------------------------------------------------------

	EXEC dbo._sp_b2b_stored_procedure_audit_details 0, @procedure_name, @note, NULL, @event_id_out = @event_id OUT

	declare		@plan_id								int
			,	@period_id								int
			,	@period_name							varchar(100)
			,	@plan_year								int
			,	@date_start								date
			,	@date_end								date
			,	@date_start_period						date
			,	@date_end_period						date
			,	@date_start_interval					date
			,	@date_end_interval						date
			,	@calc_type_revenue						varchar(100)
			,	@achievement_cap_on_plan_level_name		varchar(100)
			,	@achievement_cap_on_plan_level_value	int
			,	@achievement_calculation_individual		varchar(100)
			,	@achievement_calculation_team			varchar(100)
			,	@team_definition_dynamic				varchar(100)
			,	@team_definition_static					varchar(100)
			,	@datasource_type_sf						varchar(100)
			,	@datasource_type_rev					varchar(100)
			,	@segment_code_bmm						varchar(100)
			,	@segment_code_ent						varchar(100)
			,	@team_type_employees_plan				varchar(100)
			,	@team_type_population_table				varchar(100)
			,	@team_type_transaction_sf				varchar(100)
			,	@team_type_transaction_rev				varchar(100)
			,	@target_code_rev_mapping				varchar(100)
			,	@target_rev								varchar(100)			
			,	@enable_rev_mapping						bit
			,	@renewal_name							nvarchar(100)
			,	@accelerated							smallint
			,	@year_to_date							smallint
			,	@admin_only								smallint
			,	@now									date	
			,	@current_month							tinyint
			,	@proporstions_of_days					decimal(8,5)
			,	@end_of_last_month						date
			,	@end_of_current_month					date
			,	@rev_preliminary_achievement			decimal(18,2)
			,	@team_frequency_sf						char(1)
			,	@team_frequency_rev						char(1);

	set @now = IIF(@current_date is null,getdate(),@current_date) -- testing purposes
	set @current_month = MONTH(@now)
	set @proporstions_of_days = cast(day(@now) as float) / cast(day(eomonth(@now)) as float);
	set @end_of_current_month = eomonth(@now)
	set @end_of_last_month = eomonth(dateadd(month,-1,@now))

	drop table if exists #result_details;
	drop table if exists #team_filter;
	drop table if exists #dimensions;
	drop table if exists #accelerator_by_range;

	create table #result_details (
			person_id					nvarchar(100)
		,	metric_code					varchar(10)
		,	segment_code				varchar(10)
		,	date_eop					datetime
		,	result_value_individual		decimal(18, 2)
		,	factorized_result_delta		decimal(18, 2)
		,	boostered_result_delta		decimal(18, 2)
		,	service_type_group			varchar(100)
		,	renewal_flag				bit
		,	focus_factor				decimal(18, 2)
		,	booster						decimal(18, 2)
		,	product_group				varchar(100)
		,	team_name					nvarchar(2000)		
		,	team_name_eop				nvarchar(2000)		
		,	manual_adjustment			bit		
		,	company_name				nvarchar(255)
		,	a_number					nvarchar(20)
		,	sales_person_id				nvarchar(10) 
		,	group_eof					bit
		,	product_grouping			varchar(100)
		,	report_grouping				varchar(100)
		);

	create table #team_filter (
			person_id					nvarchar(100)
		,	metric_code					varchar(10)
		,	segment_code				varchar(10)
		,	segment_data_flag			bit
		,	achievement_calculation		varchar(100)
		,	team_definition				varchar(100)
		,	[date]						datetime
		,	id_filter					int
		,	id_filter_type				varchar(100)
		);		

	create table #team_data (
			type						varchar(100)
		,	person_id					nvarchar(100)
		,	metric_code					varchar(10)
		,	segment_code				varchar(10)
		,	achievement_calculation		varchar(100)
		,	team_definition				varchar(100)
		,	date						datetime
		,	team_name					nvarchar(2000)
		,	team_name_eop				nvarchar(2000) -- Team for : end of period
		,	id_filter					int
		,	id_filter_type				varchar(100)
		,	team						nvarchar(100)
		,	unit						nvarchar(100)
		,	title						nvarchar(100)
		,	profile						nvarchar(100)
		,	level_1						nvarchar(100)
		,	level_2						nvarchar(100)
		,	level_3						nvarchar(100)
		,	level_4						nvarchar(100)
		);

	create table #dimensions (
			metric_code					varchar(100)		
		,	segment_code				varchar(100)
		,	segment_data_flag			bit
		,	achievement_calculation		varchar(100)
		,	team_definition				varchar(100)
		,	value_type					varchar(100)
		,	datasource_type				varchar(100)
		,	mrc_flag					bit
		,	otc_flag					bit
		,	old_calc_flag				bit
		);

	create table #target_raw (
			person_id					nvarchar(100)
		,	metric_code					varchar(100)		
		,	segment_code				varchar(100)
		,	target_value_individual		decimal(18, 2)
		);
			
	create table #target_to_add (
		person_id						nvarchar(100)
		,	metric_code					varchar(100)		
		,	segment_code				varchar(100)
		,	target_value				decimal(18, 2)
		);

	create table #target_to_add_sum (
		person_id						nvarchar(100)
		,	metric_code					varchar(100)		
		,	segment_code				varchar(100)
		,	target_value				decimal(18, 2)
		);

	/* Static variable values - START ---------------------------------------------------- */

	set @calc_type_revenue					= 'Revenue';
	set @achievement_cap_on_plan_level_name	= 'Achievement cap on plan level';
	set @achievement_calculation_individual	= 'Individual';
	set @achievement_calculation_team		= 'Team';
	set @team_definition_dynamic			= 'Dynamic';
	set @team_definition_static				= 'Static';
	set @datasource_type_sf					= 'SF'
	set @datasource_type_rev				= 'REV'
	set	@segment_code_bmm					= 'BMM'
	set	@segment_code_ent					= 'ENT';
	set @team_type_employees_plan			= 'PLAN_EMPLOYEES';
	set @team_type_population_table			= 'POPULATION_TABLE';
	set @team_type_transaction_sf			= 'TRANSACTION_SF';
	set @team_type_transaction_rev			= 'TRANSACTION_REV';
	set @renewal_name						= 'Renewal';

	/* Audit information ----------------------------------------------------------------- */
	update	_tb_b2b_payment_dates
	set			refresh_date_start	= cast(getdate() at time zone 'UTC' at time zone 'Central Europe Standard Time' as datetime)
			,	refresh_date_end	= null
	where	id = @id_payment_dates
	and		@debug_mode = 0
	and		@report_mode = 0;

	/* Static variable values - END ------------------------------------------------------ */
	select		@plan_id					= pd.id_b2b_plan
			,	@plan_year					= pd.[year]
			,	@period_id					= pd.[period]
			,	@period_name				= date_ranges.period_name
			,	@date_start_period			= date_ranges.date_start
			,	@date_end_period			= date_ranges.date_end			
			,	@enable_rev_mapping			= p.rev_mapping
			,	@accelerated				= pd.accelerated
			,	@year_to_date				= pd.year_to_date
			,	@admin_only					= pd.admin_only 
			,	@team_frequency_sf			= pd.team_frequency_sf
			,	@team_frequency_rev			= pd.team_frequency_rev
	from	_tb_b2b_payment_dates (nolock) pd
	outer apply (
		select		period_name
				,	date_start
				,	date_end
		from	_fn_b2b_get_period_dates (pd.[period], pd.[year])
	) date_ranges
	join _tb_b2b_plan (nolock) p
		on p.id = pd.id_b2b_plan
	where	pd.id = @id_payment_dates;

	if @year_to_date = 1
		begin
			IF  (@now BETWEEN @date_start_period and @date_end_period) and month(@now) > 3 
				begin 
					set @date_end_interval = @end_of_last_month
					set @date_start_interval =dateadd(month,-3,@end_of_last_month) 
				end
			select	@date_start = IIF(@date_start_period < @date_start_interval or @date_start_interval is null, @date_start_period, @date_start_interval)
					,@date_end	= IIF(@date_end_interval is null, @date_end_period, @end_of_current_month)
		END
	ELSE
		BEGIN

			set @date_start	= @date_start_period
			set @date_end	= @date_end_period

		end

	select @target_code_rev_mapping = target_code from _tb_b2b_targets_definition where REV_mapping = 1 and [year] = @plan_year
	select @target_rev = target_code from _tb_b2b_targets_definition where value_type = @datasource_type_rev and [year] = @plan_year

	select @rev_preliminary_achievement = qpd.rev_preliminary_achievement
	from _tb_b2b_quarter_payment_dates qpd
	where qpd.year = @plan_year
		and (qpd.period = @period_id
		or (qpd.period = 2 and @period_id = 5)
		or (qpd.period = 4 and @period_id in (6,7)))

	select @snapshot_paydate = qpd.payment_date -- select *
	from _tb_b2b_quarter_payment_dates qpd
	where qpd.payment_date = (select pay_date from _tb_b2b_payment_dates where id = @id_payment_dates)
		and snap_shot_created_flag = 1

	update	_tb_b2b_payment_dates_regular_periods 
	set			refresh_date_start	= cast(getdate() at time zone 'UTC' at time zone 'Central Europe Standard Time' as datetime)
			,	refresh_date_end	= null
	where	id_b2b_plan = @plan_id
	and		year = @plan_year
	and		period = @period_id
	and		@debug_mode = 0
	and		@report_mode = 0;

	select		distinct
				ar.achievement_min		
			,	ar.achievement_max		
			,	ar.accelerator_value	
			,	ar.segment_code
			,	ar.target_code
			,	ar.achievement_accelerated_base
			,	ar.cap
	into	#accelerator_ranges_static
	from	_tb_b2b_accelerator_ranges (nolock) ar
	join	_tb_b2b_plan_definition (nolock) pd 
		on	pd.id_b2b_plan = ar.id_b2b_plan
		and pd.metric_code = ar.target_code
	where	ar.id_b2b_plan = @plan_id
		and pd.accelerator_flag = 1
		--and @accelerated = 1

	select 
			segment_code
		,	target_code
		,	max(cap) as accelerator_cap_value
		,	max(achievement_max) as accelerator_cap
		,	min(achievement_min) as accelerator_floor
	into #accelerator_floor_cap
	from #accelerator_ranges_static
	group by
			segment_code
		,	target_code

	set @achievement_cap_on_plan_level_value = (
		select	parameter_value
		from	_tb_b2b_plan_parameters (nolock)
		where	id_b2b_plan = @plan_id
		and		parameter_name = @achievement_cap_on_plan_level_name);

	if isnull(@accelerated,0) <> 1
		truncate table #accelerator_ranges_static

	/* Quarter date ranges - specific for period / datasource */
	select	q_dataset_type	= dataset_type
		,	q_name			= rp.name
		,	q_date_start	= q_dates.date_start
		,	q_date_end		= q_dates.date_end
	into	#quarter_dates
	from	_vw_b2b_ref_periods rp
	outer apply (
		select	dataset_type	= 'SF'
			,	team_frequency	= @team_frequency_sf
		union all
		select	dataset_type	= 'REV'
			,	team_frequency	= @team_frequency_rev
	) tf
	outer apply (
		select	date_start
			,	date_end
		from	_fn_b2b_get_period_dates (rp.id, @plan_year)
	) q_dates
	where	rp.period_type = team_frequency
	and		q_dates.date_start >= @date_start
	and		q_dates.date_end <= @date_end;

	/* =================================================================================== */
	/* C A L C U L A T I O N  -  S T A R T  ============================================== */
	/* =================================================================================== */

	/* =================================================================================== */
	/* Data prerequisites ---------------------------------------------------------------- */
	/* =================================================================================== */

	/* Employee_plan_assignment ---------------------------------------------------------- */
	select	distinct 
			epa.person_id
	into	#employee_plan_assignment
	from	_tb_b2b_employee_plan_assignment (nolock) epa
	where	epa.id_b2b_plan = @plan_id
		and		epa.end_date >= @date_start
		and		epa.start_date <= @date_end;

	/* Metrics --------------------------------------------------------------------------- */
	select		distinct
				pd.metric_code
			,	pd.weight
			,	booked_in_metric
			,	bmm_weight
			,	ent_weight
			,	segment_data_flag		= iif(pd.bmm_weight is not null and pd.ent_weight is not null, 1, 0)
			,	achievement_calculation	= iif(@individual_mode = 1, @achievement_calculation_individual, achievement_calculation)
			,	team_definition
			,	vdm.value_type
			,	vdm.datasource_type
			,	td.MRC	as mrc_flag
			,	td.OTC	as otc_flag
			,	iif(isnull(td.value_type, @datasource_type_rev) = @datasource_type_rev, 1, 0) as old_calc_flag
			,	td.service_type
			,	td.include_mrc_in_product_groups
			,	td.exclude_product_groups
			,	td.REV_mapping
			,	td.ytd_target_calc_method

	into	#plan_definition
	from	_tb_b2b_plan_definition (nolock) pd
	join _tb_b2b_plan p
            on p.id = pd.id_b2b_plan
    left join _tb_b2b_targets_definition td -- select * from _tb_b2b_targets_definition
            on pd.metric_code = td.target_code
            and p.year = td.year
    left join _vw_b2b_value_datasource_mapping vdm
            on vdm.year = p.year
            and (vdm.value_type = td.value_type
                    or vdm.value_type = pd.metric_code )
    where	pd.id_b2b_plan = @plan_id;

	/* Dimensions ------------------------------------------------------------------------ */
	select		metric_code
			,	segment_code
			,	segment_data_flag
			,	achievement_calculation
			,	team_definition
			,	value_type
			,	datasource_type
			,	mrc_flag
			,	otc_flag
			,	old_calc_flag
	into	#dimensions_proxy
	from	#plan_definition pd
	cross apply (
			select	segment_code	= iif(segment_data_flag = 1, @segment_code_bmm, null)
			union
			select	segment_code	= iif(segment_data_flag = 1, @segment_code_ent, null)
	) segment_data;
	
	if(@individual_mode = 0)
	begin
		insert into #dimensions
		select	*
		from	#dimensions_proxy;
	end;
	else
	begin
		insert into #dimensions
		select			metric_code
					,	segment_code				= null
					,	segment_data_flag			= 0
					,	achievement_calculation		= @achievement_calculation_individual
					,	team_definition				= null
					,	value_type
					,	datasource_type
					,	mrc_flag
					,	otc_flag
					,	old_calc_flag
		from		#dimensions_proxy
		group by	metric_code					
					,	value_type
					,	datasource_type
					,	mrc_flag
					,	otc_flag
					,	old_calc_flag;
	end;

	/* person_id filter : XML 2 table */
	set ansi_warnings on;	
	select	person_id = t.c.value('./text()[1]', 'nvarchar(10)')
	into	#person_id_filter
	from	@person_id_filter.nodes('/child::node()') t(c);	
	set ansi_warnings off;

	/* =================================================================================== */
	/* Teams ----------------------------------------------------------------------------- */
	/* =================================================================================== */
	insert into #team_filter
	select			distinct
					person_id
				,	metric_code
				,	segment_code
				,	segment_data_flag
				,	achievement_calculation
				,	team_definition
				,	[date]						= qd.q_date_end
				,	id_filter					= null
				,	id_filter_type				= null
	from		_tb_b2b_employee_plan_assignment (nolock) epa
			,	#dimensions
	join		#quarter_dates qd
		on		qd.q_dataset_type = metric_code
	where		epa.id_b2b_plan = @plan_id
	and			epa.start_date <= @date_end
	and			epa.end_date >= @date_end;

	exec _sp_b2b_team_data_get
		@plan_id							= @plan_id
	,	@static_force						= 1
	,	@type								= @team_type_employees_plan
	,	@team_definition_dynamic			= @team_definition_dynamic
	,	@team_definition_static				= @team_definition_static
	,	@achievement_calculation_individual = @achievement_calculation_individual;

	if(@report_mode = 1)
	begin
		insert into #team_data_report
		select	* 
		from	#team_data 				
		where	type = @team_type_employees_plan;			
	end;

	/* =================================================================================== */
	/* Population filters (performance) -------------------------------------------------- */
	/* =================================================================================== */

	delete	#team_filter;

	insert into #team_filter
	select			person_id					= pe.person_id
				,	metric_code
				,	segment_code
				,	segment_data_flag
				,	achievement_calculation
				,	team_definition
				,	[date]						= qd.q_date_end
				,	id_filter					= null
				,	id_filter_type				= @team_type_population_table
	from		_tb_b2b_population_employee (nolock) pe			
	join		#dimensions d
		on		1 = 1
	join		#quarter_dates qd
		on		qd.q_dataset_type = d.metric_code
	left join	#person_id_filter pif
		on		pif.person_id = pe.person_id
	where	pe.end_date >= @date_end
	and		pe.start_date <= @date_end
	and		(@person_id is null or pe.person_id = @person_id)
	and		(@person_id_filter is null or pif.person_id is not null);

	exec _sp_b2b_team_data_get
		@plan_id							= @plan_id
	,	@static_force						= 0
	,	@type								= @team_type_population_table
	,	@team_definition_dynamic			= @team_definition_dynamic
	,	@team_definition_static				= @team_definition_static
	,	@achievement_calculation_individual = @achievement_calculation_individual;

	select		distinct
				td_pt.metric_code
			,	td_pt.segment_code
			,	td_pt.person_id
	into	#perf_person_id_filter
	from	#team_data td_pt
	join	#team_data td_ep
		on	td_ep.metric_code = td_pt.metric_code
			and	isnull(td_ep.segment_code, '') = isnull(td_pt.segment_code, '')
			and	td_ep.team_name = td_pt.team_name
			and	td_ep.type = @team_type_employees_plan
	where	td_pt.type = @team_type_population_table

	delete	#team_data
	where	type = @team_type_population_table;

	/* =================================================================================== */
	/* Targets --------------------------------------------------------------------------- */
	/* =================================================================================== */

	/* All person_id targets values - with no plan context ------------------------------- */
	if(@report_mode = 0)
	begin
		if(@year_to_date = 0 or year(@now) > @plan_year)
		begin
			insert into #target_raw
					(person_id
					,	ta.metric_code
					,	ta.segment_code
					,	target_value_individual)
			select		
						person_id
					,	ta.metric_code
					,	ta.segment_code
					,	target_value_individual	= sum(target_value)
			from	_tb_b2b_target_assignment_details (nolock) ta		
			join	#plan_definition pd
				on	pd.metric_code = ta.metric_code		
			outer apply (
				select		target_q1 = isnull(m01, 0) + isnull(m02, 0) + isnull(m03, 0)
						,	target_q2 = isnull(m04, 0) + isnull(m05, 0) + isnull(m06, 0)
						,	target_q3 = isnull(m07, 0) + isnull(m08, 0) + isnull(m09, 0)
						,	target_q4 = isnull(m10, 0) + isnull(m11, 0) + isnull(m12, 0)
			) t10
			outer apply (
				select		target_value	= case
								when @period_name = 'Q1' then target_q1
								when @period_name = 'Q2' then target_q2
								when @period_name = 'Q3' then target_q3
								when @period_name = 'Q4' then target_q4
								when @period_name = 'H1' then target_q1 + target_q2
								when @period_name = 'H2' then target_q3 + target_q4
								else target_q1 + target_q2 + target_q3 + target_q4
							end
			) t20
			cross apply (
				select	person_id 
				from	dbo._fn_b2b_sales_person_id_2_person_id(ta.sales_person_id)
			) contract_data
			cross apply (
				select	top 1 1 ex_on_plan
				from	_tb_b2b_employee_plan_assignment (nolock) epa
				where	epa.person_id = contract_data.person_id
				and		epa.id_b2b_plan = @plan_id
			) t30
			where	ta.year = @plan_year
			and		((pd.segment_data_flag = 0 and ta.segment_code is null)
				or	(pd.segment_data_flag = 1 and ta.segment_code is not null))
			group by		person_id
						,	ta.metric_code
						,	ta.segment_code;
		end
		else
		begin
			insert into #target_raw
					(person_id
					,	ta.metric_code
					,	ta.segment_code
					,	target_value_individual)

			select		
						person_id
					,	ta.metric_code
					,	ta.segment_code
					,	target_value_individual	= sum(target_value)
			from	_tb_b2b_target_assignment_details (nolock) ta		
			join	#plan_definition pd
				on	pd.metric_code = ta.metric_code	
			outer apply ( -- select * from _tb_b2b_targets_definition
				select 
					case 
						when pd.ytd_target_calc_method in (3) then @proporstions_of_days
						when pd.ytd_target_calc_method in (1,2) then 1
					end as proporstions_of_days
					,case 
						when pd.ytd_target_calc_method in (2,3) then 0
						when pd.ytd_target_calc_method in (1) then 1
					end as proportions_after
				) pod
			outer apply (
				select					
				case	
					when @current_month = 1 then isnull(m01, 0) * pod.proporstions_of_days										+ (isnull(m02, 0) + isnull(m03, 0))	* pod.proportions_after
					when @current_month = 2 then isnull(m02, 0) * pod.proporstions_of_days + isnull(m01, 0) 					+ (isnull(m03, 0))	* pod.proportions_after
					when @current_month = 3 then isnull(m03, 0) * pod.proporstions_of_days + isnull(m01, 0) + isnull(m02, 0)	
					else m01 + m02 + m03 
				end as target_q1
				,case	
					when @current_month < 4 then (isnull(m04, 0) + isnull(m05, 0) + isnull(m06, 0)) * pod.proportions_after
					when @current_month = 4 then isnull(m04, 0) * pod.proporstions_of_days										+ (isnull(m05, 0) + isnull(m06, 0)) * pod.proportions_after
					when @current_month = 5 then isnull(m05, 0) * pod.proporstions_of_days + isnull(m04, 0)						+ (isnull(m06, 0)) * pod.proportions_after
					when @current_month = 6 then isnull(m06, 0) * pod.proporstions_of_days + isnull(m04, 0) +isnull(m05, 0)		
					else m04 + m05 + m06 
				end as target_q2
				,case	
					when @current_month < 7 then (isnull(m07, 0) + isnull(m08, 0) + isnull(m09, 0)) * pod.proportions_after
					when @current_month = 7 then isnull(m07, 0) * pod.proporstions_of_days										+ (isnull(m08, 0) + isnull(m09, 0)) * pod.proportions_after
					when @current_month = 8 then isnull(m08, 0) * pod.proporstions_of_days + isnull(m07, 0) 					+ (isnull(m09, 0)) * pod.proportions_after
					when @current_month = 9 then isnull(m09, 0) * pod.proporstions_of_days + isnull(m07, 0) + isnull(m08, 0)
					else m07 + m08 + m09
				end as target_q3
				,case	
					when @current_month < 10 then (isnull(m10, 0) + isnull(m11, 0) + isnull(m12, 0)) * pod.proportions_after
					when @current_month = 10 then isnull(m10, 0) * pod.proporstions_of_days										+ (isnull(m11, 0) + isnull(m12, 0)) * pod.proportions_after
					when @current_month = 11 then isnull(m11, 0) * pod.proporstions_of_days + isnull(m10, 0) 					+ (isnull(m12, 0)) * pod.proportions_after
					when @current_month = 12 then isnull(m12, 0) * pod.proporstions_of_days + isnull(m10, 0) + isnull(m11, 0)
				end as target_q4
			) t10
			outer apply (
				select		target_value	= case
								when @period_name = 'Q1' then target_q1
								when @period_name = 'Q2' then target_q2
								when @period_name = 'Q3' then target_q3
								when @period_name = 'Q4' then target_q4
								when @period_name = 'H1' then target_q1 + target_q2
								when @period_name = 'H2' then target_q3 + target_q4
								else target_q1 + target_q2 + target_q3 + target_q4
							end
			) t20
			cross apply (
				select	person_id 
				from	dbo._fn_b2b_sales_person_id_2_person_id(ta.sales_person_id)
			) contract_data
			cross apply (
				select	top 1 1 ex_on_plan
				from	_tb_b2b_employee_plan_assignment (nolock) epa
				where	epa.person_id = contract_data.person_id
				and		epa.id_b2b_plan = @plan_id
			) t30
			where	ta.year = @plan_year
			and		((pd.segment_data_flag = 0 and ta.segment_code is null)
				or	(pd.segment_data_flag = 1 and ta.segment_code is not null))
			group by		person_id
						,	ta.metric_code
						,	ta.segment_code;

			insert into #target_to_add
			(		person_id						
				,	metric_code							
				,	segment_code				
				,	target_value)
			select		
					person_id
				,	ta.metric_code
				,	ta.segment_code
				,	sum(t10.target_value) as target_value
			from	_tb_b2b_target_assignment_details (nolock) ta	
			join	#plan_definition pd
				on	pd.metric_code = ta.metric_code		
			outer apply (
				select	target_value = case
					when @period_name in ('Q2','Q3','Q4','H2') or pd.ytd_target_calc_method <> 2 or @year_to_date = 0 THEN 0
					when @current_month = 1 then isnull(m01, 0)
					when @current_month = 2 then isnull(m02, 0)
					when @current_month = 3 then isnull(m03, 0)
					else 0 end
			) t10
			cross apply (
				select	person_id 
				from	dbo._fn_b2b_sales_person_id_2_person_id(ta.sales_person_id)
			) contract_data
			cross apply (
				select	top 1 1 ex_on_plan
				from	_tb_b2b_employee_plan_assignment (nolock) epa
				where	epa.person_id = contract_data.person_id
				and		epa.id_b2b_plan = @plan_id
			) t30
			where	ta.year = @plan_year
			and		((pd.segment_data_flag = 0 and ta.segment_code is null)
				or	(pd.segment_data_flag = 1 and ta.segment_code is not null))
			group by		person_id
						,	ta.metric_code
						,	ta.segment_code;

		end

		if (exists (
			select	top 1 1 
			from	#plan_definition 
			where	datasource_type  = @datasource_type_rev
			and		@year_to_date = 1)
			and
			not exists (
			select top 1 1 -- select *
			from _tb_b2b_rev_revenue
			where year(start_date) = iif(@current_month = 1, @plan_year - 1, @plan_year)
				and month(start_date) = iif(@current_month = 1,12, @current_month - 1))
			and @now BETWEEN @date_start and @date_end)
		begin
			insert into #target_to_add
			(		person_id						
				,	metric_code							
				,	segment_code				
				,	target_value)
			select		
					person_id
				,	ta.metric_code
				,	ta.segment_code
				,	sum(t10.target_value) as target_value -- select *
			from	_tb_b2b_target_assignment_details (nolock) ta	
			join	#plan_definition pd
				on	pd.metric_code = ta.metric_code		
			outer apply (
				select	target_value = case
					when @current_month = 1 then isnull(m12, 0)
					when @current_month = 2 then isnull(m01, 0)
					when @current_month = 3 then isnull(m02, 0)
					when @current_month = 4 then isnull(m03, 0)
					when @current_month = 5 then isnull(m04, 0)
					when @current_month = 6 then isnull(m05, 0)
					when @current_month = 7 then isnull(m06, 0)
					when @current_month = 8 then isnull(m07, 0)
					when @current_month = 9 then isnull(m08, 0)
					when @current_month = 10 then isnull(m09, 0)
					when @current_month = 11 then isnull(m10, 0)
					when @current_month = 12 then isnull(m11, 0)
					else 0 end
			) t10
			cross apply (
				select	person_id 
				from	dbo._fn_b2b_sales_person_id_2_person_id(ta.sales_person_id)
			) contract_data
			cross apply (
				select	top 1 1 ex_on_plan
				from	_tb_b2b_employee_plan_assignment (nolock) epa
				where	epa.person_id = contract_data.person_id
				and		epa.id_b2b_plan = @plan_id
			) t30
			where	ta.year = @plan_year
			and		ta.metric_code = @target_rev
			group by		person_id
						,	ta.metric_code
						,	ta.segment_code;
		end
		
		insert into #target_to_add_sum
		(		person_id						
			,	metric_code							
			,	segment_code				
			,	target_value)

		select
				person_id						
			,	metric_code							
			,	segment_code				
			,	sum(target_value)
		from #target_to_add
		group by
			person_id						
		,	metric_code							
		,	segment_code
	end;

	/* =================================================================================== */
	/* Results --------------------------------------------------------------------------- */
	/* =================================================================================== */

	/* - - - - - - - - - - - - - - - - - - S F - - - - - - - - - - - - - - - - - - - - - - */
	if exists (select top 1 1 from #plan_definition where datasource_type  = @datasource_type_sf)
	begin
		/* Populate basic transaction filters for SF ------------------------------------ */
		delete	#team_filter;
		
		/* Snapshot data ---------------------------------------------------------------- */		
		if(@report_mode = 1 and @snapshot_paydate is not null)
		begin
			/* SF Opportunities --------------------------------------------------------- */
			insert into #team_filter
			select			person_id					= contract_data.person_id
						,	metric_code					= d.metric_code
						,	segment_code				= d.segment_code
						,	segment_data_flag
						,	achievement_calculation
						,	team_definition
						,	[date]						= qd.q_date_end
						,	id_filter					= so.id
						,	id_filter_type				= 'SF_TABLE'
			from		_tb_b2b_sf_opportunities_arch (nolock) so
			join	#dimensions d 
				on	d.datasource_type  = @datasource_type_sf
			cross apply (
				select	person_id 
				from	dbo._fn_b2b_sales_person_id_2_person_id(so.sales_person_id)
			) contract_data
			left join	#person_id_filter pif
				on		pif.person_id = contract_data.person_id
			join	#perf_person_id_filter ppif
				on	ppif.person_id = contract_data.person_id
				and	ppif.metric_code = d.metric_code
				and	isnull(ppif.segment_code, '') = isnull(d.segment_code, '')
			outer apply (
				select	qd.q_date_end
				from	#quarter_dates qd
				where	so.closed_date between qd.q_date_start and qd.q_date_end
				and		qd.q_dataset_type = d.metric_code
			) qd  
			where	so.closed_date >= @date_start
			and		so.closed_date <= @date_end
			and		so.is_closed = 1
			and		so.is_deleted = 0
			and		so.opp_stage in ('Closed Won', 'Closed won (MAClight)')
			and		(@person_id is null or contract_data.person_id = @person_id)
			and		(@person_id_filter is null or pif.person_id is not null)
			and		so.payment_date = @snapshot_paydate;

			/* EoF SBP ------------------------------------------------------------------ */
			insert into #team_filter
			select			person_id					= contract_data.person_id
						,	metric_code					= d.metric_code
						,	segment_code				= d.segment_code
						,	segment_data_flag
						,	achievement_calculation
						,	team_definition
						,	[date]						= qd.q_date_end
						,	id_filter					= es.id
						,	id_filter_type				= 'SBP_TABLE'
			from		_tb_b2b_eof_sbp_arch (nolock) es
			join	#dimensions d 
				on	d.datasource_type  = @datasource_type_sf
			cross apply (
				select	person_id 
				from	dbo._fn_b2b_sales_person_id_2_person_id(es.sales_person_id)
			) contract_data
			left join	#person_id_filter pif
				on		pif.person_id = contract_data.person_id
			join	#perf_person_id_filter ppif
				on	ppif.person_id = contract_data.person_id
				and	ppif.metric_code = d.metric_code
				and	isnull(ppif.segment_code, '') = isnull(d.segment_code, '')
			outer apply (
				select	qd.q_date_end
				from	#quarter_dates qd
				where	es.activation_date between qd.q_date_start and qd.q_date_end
				and		qd.q_dataset_type = d.metric_code
			) qd  
			where	es.activation_date >= @date_start
			and		es.activation_date <= @date_end
			and		(@person_id is null or contract_data.person_id = @person_id)
			and		(@person_id_filter is null or pif.person_id is not null)
			and		es.payment_date = @snapshot_paydate;

		end;
		/* System data ------------------------------------------------------------------ */
		else
		begin
			/* SF Opportunities --------------------------------------------------------- */
			insert into #team_filter
			select			person_id					= contract_data.person_id
						,	metric_code					= d.metric_code
						,	segment_code				= d.segment_code
						,	segment_data_flag
						,	achievement_calculation
						,	team_definition
						,	[date]						= qd.q_date_end
						,	id_filter					= so.id
						,	id_filter_type				= 'SF_TABLE'
			from		_tb_b2b_sf_opportunities (nolock) so
			join	#dimensions d 
				on	d.datasource_type  = @datasource_type_sf
			cross apply (
				select	person_id 
				from	dbo._fn_b2b_sales_person_id_2_person_id(so.sales_person_id)
			) contract_data
			left join	#person_id_filter pif
				on		pif.person_id = contract_data.person_id
			join	#perf_person_id_filter ppif
				on	ppif.person_id = contract_data.person_id
				and	ppif.metric_code = d.metric_code
				and	isnull(ppif.segment_code, '') = isnull(d.segment_code, '')
			outer apply (
				select	qd.q_date_end
				from	#quarter_dates qd
				where	so.closed_date between qd.q_date_start and qd.q_date_end
				and		qd.q_dataset_type = d.metric_code
			) qd  
			where	so.closed_date >= @date_start
			and		so.closed_date <= @date_end
			and		so.is_closed = 1
			and		so.is_deleted = 0
			and		so.opp_stage in ('Closed Won', 'Closed won (MAClight)')
			and		(@person_id is null or contract_data.person_id = @person_id)
			and		(@person_id_filter is null or pif.person_id is not null);

			/* EoF SBP ------------------------------------------------------------------ */
			insert into #team_filter
			select			person_id					= contract_data.person_id
						,	metric_code					= d.metric_code
						,	segment_code				= d.segment_code
						,	segment_data_flag
						,	achievement_calculation
						,	team_definition
						,	[date]						= qd.q_date_end
						,	id_filter					= es.id
						,	id_filter_type				= 'SBP_TABLE'
			from		_tb_b2b_eof_sbp (nolock) es
			join	#dimensions d 
				on	d.datasource_type  = @datasource_type_sf
			cross apply (
				select	person_id 
				from	dbo._fn_b2b_sales_person_id_2_person_id(es.sales_person_id)
			) contract_data
			left join	#person_id_filter pif
				on		pif.person_id = contract_data.person_id
			join	#perf_person_id_filter ppif
				on	ppif.person_id = contract_data.person_id
				and	ppif.metric_code = d.metric_code
				and	isnull(ppif.segment_code, '') = isnull(d.segment_code, '')
			outer apply (
				select	qd.q_date_end
				from	#quarter_dates qd
				where	es.activation_date between qd.q_date_start and qd.q_date_end
				and		qd.q_dataset_type = d.metric_code
			) qd  
			where	es.activation_date >= @date_start
			and		es.activation_date <= @date_end
			and		(@person_id is null or contract_data.person_id = @person_id)
			and		(@person_id_filter is null or pif.person_id is not null);
		end;
		
		/* Manual adjustment ------------------------------------------------------------ */
		insert into #team_filter
		select			person_id					= contract_data.person_id
					,	metric_code					= d.metric_code
					,	segment_code				= d.segment_code
					,	segment_data_flag
					,	achievement_calculation
					,	team_definition
					,	[date]						= qd.q_date_end
					,	id_filter					= mac.id
					,	id_filter_type				= 'SF_MA'
		from		_vw_b2b_manual_adjustments_cov (nolock) mac		
		join	#dimensions d 
			on	d.datasource_type  = @datasource_type_sf
		cross apply (
			select	person_id 
			from	dbo._fn_b2b_sales_person_id_2_person_id(mac.sales_person_id_prefix)
		) contract_data		
		left join	#person_id_filter pif
			on		pif.person_id = contract_data.person_id
		join	#perf_person_id_filter ppif
			on	ppif.person_id = contract_data.person_id
			and	ppif.metric_code = d.metric_code
			and	isnull(ppif.segment_code, '') = isnull(d.segment_code, '')
		outer apply (
			select	qd.q_date_end
			from	#quarter_dates qd
			where	mac.closed_date between qd.q_date_start and qd.q_date_end
			and		qd.q_dataset_type = d.metric_code
		) qd  
		where		mac.closed_date >= @date_start
		and			mac.closed_date <= @date_end
		and			(@person_id is null or contract_data.person_id = @person_id)
		and			(@person_id_filter is null or pif.person_id is not null);

		/* Get team name for each transaction date --------------------------------------- */		
		exec _sp_b2b_team_data_get
			@plan_id							= @plan_id
		,	@static_force						= 0
		,	@type								= @team_type_transaction_sf		
		,	@team_definition_dynamic			= @team_definition_dynamic
		,	@team_definition_static				= @team_definition_static
		,	@achievement_calculation_individual = @achievement_calculation_individual	

		if(@report_mode = 1)
		begin
			insert into #team_data_report
			select	* 
			from	#team_data 				
			where	type = @team_type_transaction_sf;
		end;
		else
		begin

			/* Add transactions details -------------------------------------------------- */
			exec _sp_b2b_calc_get_result_details
				@datasource_type			= @datasource_type_sf
			,	@date_start					= @date_start
			,	@date_end					= @date_end
			,	@result_mode				= 0
			,	@target_code_rev_mapping	= @target_code_rev_mapping
			,	@plan_id					= @plan_id			
			,	@enable_rev_mapping			= @enable_rev_mapping
			,	@year_to_date				= @year_to_date
			,	@date_start_period			= @date_start_period	
			,	@date_end_period			= @date_end_period	
			,	@date_start_interval		= @date_start_interval
			,	@date_end_interval			= @date_end_interval
			,	@end_of_current_month		= @end_of_current_month
			,	@end_of_last_month			= @end_of_last_month
			,	@period						= @period_id;
		end;
	end;

	/* - - - - - - - - - - - - - - - - - - R E V - - - - - - - - - - - - - - - - - - - - - */
	if exists (
		select	top 1 1 
		from	#plan_definition 
		where	(datasource_type  = @datasource_type_rev)
			or	(REV_mapping = 1))
	begin
		/* Populate basic transaction filters for REV ------------------------------------ */
		delete	#team_filter;
		
		/* Snapshot data ----------------------------------------------------------------- */
		if(@report_mode = 1 and @snapshot_paydate is not null)
		begin				
			insert into #team_filter
			select			person_id					= contract_data.person_id
						,	metric_code					= d.metric_code
						,	segment_code				= d.segment_code
						,	segment_data_flag
						,	achievement_calculation
						,	team_definition
						,	[date]						= qd.q_date_end
						,	id_filter					= rr.id
						,	id_filter_type				= 'REV_TABLE'
			from		_tb_b2b_rev_revenue_arch (nolock) rr
			cross apply (
				select	rev_2_cov_mapping = iif(rr.prod_lvl_3 in ('Hardware', 'WS Hardware'), 1, 0)
			) t10
			join	#dimensions d 
				on	d.datasource_type = iif(rev_2_cov_mapping = 0, @datasource_type_rev, @datasource_type_sf)
			cross apply (
				select	person_id 
				from	dbo._fn_b2b_sales_person_id_2_person_id(rr.sales_person_id)
			) contract_data
			left join	#person_id_filter pif
				on		pif.person_id = contract_data.person_id
			join	#perf_person_id_filter ppif
				on	ppif.person_id = contract_data.person_id
				and	ppif.metric_code = d.metric_code
				and	isnull(ppif.segment_code, '') = isnull(d.segment_code, '')
			outer apply (
				select	qd.q_date_end
				from	#quarter_dates qd
				where	rr.start_date >= qd.q_date_start
				and		rr.start_date <= qd.q_date_end
				and		rr.end_date >= qd.q_date_start
				and		rr.end_date <= qd.q_date_end
				and		qd.q_dataset_type = d.metric_code
			) qd  
			where	rr.start_date >= @date_start
			and		rr.start_date <= @date_end
			and		rr.end_date >= @date_start
			and		rr.end_date <= @date_end
			and		isnull(rr.rev_net_amt_chf, 0) <> 0
			and		(@person_id is null or contract_data.person_id = @person_id)
			and		(@person_id_filter is null or pif.person_id is not null)
			and		rr.payment_date = @snapshot_paydate
			and		COALESCE(rr.flag_is_rev_in,1) = 1
			and		(t10.rev_2_cov_mapping = 0 or ISNULL(rr.profit_center_name,'') not in ('EoF', 'Medinex'))
		end;
		/* System data ------------------------------------------------------------------- */
		else
		begin
			insert into #team_filter
			select			person_id					= contract_data.person_id
						,	metric_code					= d.metric_code
						,	segment_code				= d.segment_code
						,	segment_data_flag
						,	achievement_calculation
						,	team_definition
						,	[date]						= qd.q_date_end
						,	id_filter					= rr.id
						,	id_filter_type				= 'REV_TABLE'
			from		_tb_b2b_rev_revenue (nolock) rr
			cross apply (
				select	rev_2_cov_mapping = iif(rr.prod_lvl_3 in ('Hardware', 'WS Hardware'), 1, 0)
			) t10
			join	#dimensions d 
				on	d.datasource_type = iif(rev_2_cov_mapping = 0, @datasource_type_rev, @datasource_type_sf)
			cross apply (
				select	person_id 
				from	dbo._fn_b2b_sales_person_id_2_person_id(rr.sales_person_id)
			) contract_data
			left join	#person_id_filter pif
				on		pif.person_id = contract_data.person_id
			join	#perf_person_id_filter ppif
				on	ppif.person_id = contract_data.person_id
				and	ppif.metric_code = d.metric_code
				and	isnull(ppif.segment_code, '') = isnull(d.segment_code, '')
			outer apply (
				select	qd.q_date_end
				from	#quarter_dates qd
				where	rr.start_date >= qd.q_date_start
				and		rr.start_date <= qd.q_date_end
				and		rr.end_date >= qd.q_date_start
				and		rr.end_date <= qd.q_date_end
				and		qd.q_dataset_type = d.metric_code
			) qd  
			where	rr.start_date >= @date_start
			and		rr.start_date <= @date_end
			and		rr.end_date >= @date_start
			and		rr.end_date <= @date_end
			and		isnull(rr.rev_net_amt_chf, 0) <> 0
			and		(@person_id is null or contract_data.person_id = @person_id)
			and		(@person_id_filter is null or pif.person_id is not null)
			and		COALESCE(rr.flag_is_rev_in,1) = 1;
		end;

		/* Manual adjustment ------------------------------------------------------------- */
		insert into #team_filter
		select			person_id					= contract_data.person_id
					,	metric_code					= d.metric_code
					,	segment_code				= d.segment_code
					,	segment_data_flag
					,	achievement_calculation
					,	team_definition
					,	[date]						= qd.q_date_end
					,	id_filter					= mar.id
					,	id_filter_type				= 'REV_MA'
		from		_tb_b2b_manual_adjustments_rev (nolock) mar		
		join	#dimensions d 
			on	d.datasource_type = @datasource_type_rev
		cross apply (
			select	person_id 
			from	dbo._fn_b2b_sales_person_id_2_person_id(mar.sales_person_id_prefix)
		) contract_data				
		left join	#person_id_filter pif
			on		pif.person_id = contract_data.person_id
		join	#perf_person_id_filter ppif
			on	ppif.person_id = contract_data.person_id
			and	ppif.metric_code = d.metric_code
			and	isnull(ppif.segment_code, '') = isnull(d.segment_code, '')
		outer apply (
				select	qd.q_date_end
				from	#quarter_dates qd
				where	mar.start_date >= qd.q_date_start
				and		mar.start_date <= qd.q_date_end
				and		mar.end_date >= qd.q_date_start
				and		mar.end_date <= qd.q_date_end
				and		qd.q_dataset_type = d.metric_code
		) qd  
		where	mar.start_date >= @date_start
		and		mar.start_date <= @date_end
		and		mar.end_date >= @date_start
		and		mar.end_date <= @date_end
		and		isnull(mar.rev_net_amt_chf, 0) <> 0
		and		(@person_id is null or contract_data.person_id = @person_id)
		and		(@person_id_filter is null or pif.person_id is not null)

		/* Get team name for each transaction date --------------------------------------- */		
		exec _sp_b2b_team_data_get
			@plan_id							= @plan_id
		,	@static_force						= 0
		,	@type								= @team_type_transaction_rev
		,	@team_definition_dynamic			= @team_definition_dynamic
		,	@team_definition_static				= @team_definition_static
		,	@achievement_calculation_individual = @achievement_calculation_individual		

		if(@report_mode = 1)
		begin
			insert into #team_data_report
			select	* 
			from	#team_data 				
			where	type = @team_type_transaction_rev;
		end;
		else
		begin
			/* Add transactions details -------------------------------------------------- */		
			exec _sp_b2b_calc_get_result_details
				@datasource_type			= @datasource_type_rev
			,	@date_start					= @date_start
			,	@date_end					= @date_end	
			,	@result_mode				= 0
			,	@target_code_rev_mapping	= @target_code_rev_mapping
			,	@plan_id					= @plan_id			
			,	@enable_rev_mapping			= @enable_rev_mapping
			,	@year_to_date				= @year_to_date
			,	@date_start_period			= @date_start_period	
			,	@date_end_period			= @date_end_period	
			,	@date_start_interval		= @date_start_interval
			,	@date_end_interval			= @date_end_interval
			,	@end_of_current_month		= @end_of_current_month
			,	@end_of_last_month			= @end_of_last_month
			,	@period						= @period_id;

			SELECT                                           
					rd.metric_code					
				,	rd.segment_code	                                       
				,	rd.person_id                                           
				,	rd.sales_person_id                                   
				,	rd.a_number											   
				,	rd.company_name	
				,	rd.group_eof
				,	SUM(rd.result_value_individual)  as [result_value]                                        
				,	SUM(rd.result_value_individual) + SUM(rd.factorized_result_delta) as [result_factorized_value]
				,	SUM(rd.result_value_individual) + SUM(rd.boostered_result_delta) as [result_boostered_value] 
			INTO #calc_revenue_account
			FROM #result_details rd
			JOIN #plan_definition pd
				ON rd.metric_code = pd.metric_code
			WHERE pd.datasource_type  = @datasource_type_rev
			GROUP BY 
					rd.metric_code					
				,	rd.segment_code	                                       
				,	rd.person_id                                           
				,	rd.sales_person_id                                   
				,	rd.a_number	
				,	rd.group_eof
				,	rd.company_name
		end;
	end;

	if(@report_mode = 1)
		return;

	/* =================================================================================== */
	/* Company / A Number data ----------------------------------------------------------- */
	/* =================================================================================== */

	select			rd.person_id
				,	rd.metric_code
				,	rd.segment_code
				,	rd.company_name
				,	rd.team_name_eop
				,	rd.a_number
				,	SUM(result_value_individual)	AS result_value_individual	
				,	SUM(factorized_result_delta)	AS factorized_result_delta	
				,	SUM(boostered_result_delta)		AS boostered_result_delta	
	into		#calc_company_data
	from		#result_details rd
	group by	rd.person_id
			,	rd.metric_code
			,	rd.segment_code
			,	rd.company_name
			,	rd.team_name_eop
			,	rd.a_number;

	/* =================================================================================== */
	/* Results Raw ----------------------------------------------------------------------- */
	/* =================================================================================== */

	select		rd.person_id
			,	rd.metric_code
			,	rd.segment_code
			,	rd.date_eop
			,	rd.team_name
			,	sum(rd.result_value_individual) as result_value_individual
			,	sum(rd.factorized_result_delta) as factorized_result_delta
			,	sum(rd.boostered_result_delta ) as boostered_result_delta
	into		#result_raw
	from		#result_details rd
	group by	rd.person_id
			,	rd.metric_code
			,	rd.segment_code
			,	rd.date_eop
			,	rd.team_name

	select		rd.person_id
			,	rd.metric_code
			,	rd.segment_code
			,	rd.date_eop
			,	rd.team_name
			,	rd.company_name
			,	rd.a_number
			,	sum(rd.result_value_individual) as result_value_individual
			,	sum(rd.factorized_result_delta) as factorized_result_delta
			,	sum(rd.boostered_result_delta ) as boostered_result_delta
	into		#shares_per_person_proxy
	from		#result_details rd
	group by	rd.person_id
			,	rd.metric_code
			,	rd.segment_code
			,	rd.date_eop
			,	rd.team_name
			,	rd.company_name
			,	rd.a_number


	/* =================================================================================== */
	/* Targets & Results with team context ----------------------------------------------- */
	/* =================================================================================== */
	
	select		distinct
				td.person_id
			,	td.metric_code
			,	td.segment_code
			,	td.achievement_calculation
			,	td.team_definition
			,	team_name					= td.team_name_eop
	into		#team_data_distinct_eop
	from		#team_data td
	where		td.type = @team_type_employees_plan;

	select		tr.person_id
			,	tr.metric_code
			,	tr.segment_code
			,	tdde.achievement_calculation
			,	tdde.team_definition
			,	tdde.team_name
			,	target_value_individual = target_value_individual
			,	target_value_team		= null
			,	target_value			= target_value_individual
			,	target_value_prorated
	into	#target
	from	#team_data_distinct_eop tdde
	join	#target_raw tr
		on	tr.person_id = tdde.person_id
		and	tr.metric_code = tdde.metric_code
		and	isnull(tr.segment_code, '') = isnull(tdde.segment_code, '')
	outer apply (
		select	sickness_percentage
		from	_tb_b2b_sickness (nolock) s
		join	_vw_b2b_ref_periods_no_year (nolock) rpny
			on	rpny.id = s.period
		where	s.person_id = tr.person_id
		and		s.[year] = @plan_year
		and		((@period_name <> 'Year' and rpny.name = @period_name)
			or	(@period_name = 'Year' and rpny.name in ('H1', 'H2')))
	) t10
	outer apply (
		select	target_value_prorated = target_value_individual * cast((1 - (isnull(sickness_percentage, 0) / 100.)) as decimal(18, 2))
	) t20;

	select		td.date, 
				person_id				= td.person_id
			,	metric_code				= td.metric_code
			,	segment_code			= td.segment_code
			,	achievement_calculation
			,	team_definition
			,	team_name_eop			= td.team_name_eop
			,	result_value_individual	= result_value_individual
			,	result_value_team		= isnull(result_value_team, 0)
			,	factorized_delta_individual
			,	factorized_delta_team	= isnull(factorized_delta_team,0)
			,	result_value			= case achievement_calculation
											when @achievement_calculation_individual then result_value_individual
											when @achievement_calculation_team then isnull(result_value_team, 0)
											end 
			,	factorized_delta			= case achievement_calculation
											when @achievement_calculation_individual then isnull(factorized_delta_individual,0)
											when @achievement_calculation_team then isnull(factorized_delta_team,0)
											end
			,	boostered_delta				= case achievement_calculation
											when @achievement_calculation_individual then isnull(boostered_delta_individual,0)
											when @achievement_calculation_team then isnull(boostered_delta_team,0)
											end			
	into	#result_proxy
	from	#team_data td
	outer apply (
		select	result_value_individual		= sum(result_value_individual)
			,	factorized_delta_individual = sum(factorized_result_delta)
			,	boostered_delta_individual	= sum(boostered_result_delta)
		from	#result_raw rr
		where	rr.metric_code = td.metric_code
		and		isnull(rr.segment_code, '') = isnull(td.segment_code, '')
		and		(rr.person_id = td.person_id)
		and		rr.team_name = td.team_name
		and		rr.date_eop = td.[date]
	) t10
	outer apply (
		select	result_value_team		= sum(result_value_individual)
			,	factorized_delta_team	= sum(factorized_result_delta)
			,	boostered_delta_team	= sum(boostered_result_delta)
		from	#result_raw rr
		where	rr.metric_code = td.metric_code
		and		isnull(rr.segment_code, '') = isnull(td.segment_code, '')
		and		rr.team_name = td.team_name
		and		rr.date_eop = td.[date]
	) t20
	where td.type = @team_type_employees_plan;

	select		
		person_id				= td.person_id
	,	original_person_id		= rd.person_id
	,	id_payment_dates		= @id_payment_dates
	,	metric_code				= td.metric_code
	,	segment_code			= td.segment_code
	,	a_number				= rd.a_number
	,	company_name			= rd.company_name
	,	team_name				= rd.team_name
	,	result_value			= sum(rd.result_value_individual)
	,	factorized_result_delta = sum(rd.factorized_result_delta)
	,	boostered_result_delta  = sum(rd.boostered_result_delta)
	into	#results_shares_per_person
	from	#team_data td
	join #shares_per_person_proxy rd
		on	rd.metric_code = td.metric_code
		and		isnull(rd.segment_code, '') = isnull(td.segment_code, '')
		and		rd.date_eop = td.[date]
		and		(rd.team_name = td.team_name and		td.achievement_calculation = @achievement_calculation_team
			or		rd.person_id = td.person_id and		td.achievement_calculation = @achievement_calculation_individual)
	where td.type = @team_type_employees_plan
	group by
		td.person_id
		,rd.person_id
		,td.metric_code
		,td.segment_code
		,rd.a_number
		,rd.company_name
		,rd.team_name


	select 
		spp.person_id
		,@plan_id id_plan
		,@plan_year	year
		,@period_name quarter
		,gpd.date_start start_date
		,gpd.date_end end_date
		,spp.original_person_id
		,spp.id_payment_dates
		,spp.metric_code
		,spp.segment_code
		,spp.a_number
		,spp.company_name
		,spp.team_name
		,IIF(spp.metric_code = 'REV', 'RE', spp.metric_code) datasource
		,spp.result_value
		,spp.factorized_result_delta
		,spp.boostered_result_delta
		,ptd.level_1
		,ptd.level_2
		,ptd.level_3
		,ptd.level_4
		,ptd.team
		,ptd.title
		,ptd.unit
		,ptd.profile
	into #nov_detailed
	from #results_shares_per_person spp
	cross apply (select date_start, date_end from [_fn_b2b_get_period_dates](@period_id, @plan_year)) gpd
	cross apply (select 
					team
					,unit
					,title
					,profile
					,level_1
					,level_2
					,level_3
					,level_4
				from _fn_b2b_get_team_data(spp.person_id,gpd.date_end,0,spp.segment_code)) ptd


	select		person_id					= person_id
			,	metric_code					= metric_code
			,	segment_code				= segment_code
			,	achievement_calculation		= max(achievement_calculation)
			,	team_definition				= max(team_definition)
			,	team_name					= max(team_name_eop)
			,	result_value_individual		= max(result_value_individual)
			,	result_value_team			= sum(result_value_team)
			,	factorized_delta_individual	= max(factorized_delta_individual)
			,	factorized_delta_team		= sum(factorized_delta_team)
			,	result_value				= sum(result_value)
			,	factorized_delta			= sum(factorized_delta)
			,	boostered_delta				= sum(boostered_delta)
	into	#result
	from	#result_proxy
	group by	person_id
			,	metric_code
			,	segment_code;

	/* =================================================================================== */
	/* Team data ------------------------------------------------------------------------- */
	/* =================================================================================== */
	select	distinct 
				metric_code
			,	segment_code
			,	achievement_calculation
			,	team_definition
			,	team_name	= team_name
	into	#team_data_distinct
	from	#team_data
	where	type = @team_type_employees_plan;

	select					metric_code						= tdd.metric_code
						,	segment_code					= tdd.segment_code
						,	person_id						= rr.person_id
						,	tdd.achievement_calculation
						,	tdd.team_definition
						,	ex_on_plan
						,	tdd.team_name
						,	target_value_individual			= null
						,	rr.result_value_individual
						,	factorized_delta_individual		= rr.factorized_result_delta
						,	boostered_delta_individual		= rr.boostered_result_delta
						,	team							= team_info.team	
						,	unit							= team_info.unit	
						,	title							= team_info.title	
						,	profile							= team_info.profile
						,	level_1							= team_info.level_1
						,	level_2							= team_info.level_2
						,	level_3							= team_info.level_3
						,	level_4							= team_info.level_4
	into	#calc_team_data_proxy
	from	#team_data_distinct tdd
	join	#result_raw rr
		on	rr.team_name = tdd.team_name
		and	rr.metric_code = tdd.metric_code
		and	isnull(rr.segment_code, '') = isnull(tdd.segment_code, '')
	outer apply (
		select	top 1 1 ex_on_plan
		from	#team_data td
		where	td.person_id = rr.person_id
		and		td.metric_code = rr.metric_code
		and		isnull(td.segment_code, '') = isnull(rr.segment_code, '')
		and		type = @team_type_employees_plan
	) t10
	outer apply (
		select	top 1 
					team							
				,	unit							
				,	title							
				,	profile							
				,	level_1							
				,	level_2							
				,	level_3							
				,	level_4
		from	#team_data td
		where	td.person_id = rr.person_id
		and		td.team_name = rr.team_name
		and		td.metric_code = rr.metric_code
		and		isnull(td.segment_code, '') = isnull(rr.segment_code, '')
		and		type = @team_type_employees_plan		
	) team_info		
	
	select		metric_code
			,	segment_code
			,	person_id
			,	achievement_calculation		= max(achievement_calculation)
			,	team_definition				= max(team_definition)
			,	ex_on_plan					= max(ex_on_plan)
			,	team_name
			,	target_value_individual		= sum(target_value_individual)
			,	result_value_individual		= sum(result_value_individual)
			,	factorized_delta_individual	= sum(factorized_delta_individual)
			,	boostered_delta_individual	= sum(boostered_delta_individual)
			,	team						= max(team)
			,	unit						= max(unit)
			,	title						= max(title)
			,	profile						= max(profile)
			,	level_1						= max(level_1)
			,	level_2						= max(level_2)
			,	level_3						= max(level_3)
			,	level_4						= max(level_4)
	into		#calc_team_data
	from		#calc_team_data_proxy
	group by	metric_code
			,	segment_code
			,	person_id
			,	team_name;

	/* =================================================================================== */
	/* Achievements ---------------------------------------------------------------------- */
	/* =================================================================================== */

	select			t.person_id
				,	t.metric_code
				,	t.segment_code
				,	t.achievement_calculation
				,	t.team_definition
				,	team_name						= isnull(t.team_name, result_team_name)
				,	result_value_individual			= result.result_value_individual + isnull(tta.target_value,0)
				,	result_value_team				= result.result_value_team		 + isnull(tta.target_value,0)
				,	result_value					= result.result_value			 + isnull(tta.target_value,0)
				,	factorized_delta				= result.factorized_delta	
				,	boostered_delta					= result.boostered_delta	
				,	result_team_name				= result.result_team_name		
				,	target_value_individual
				,	target_value_team
				,	target_value					= target_value_n
				,	target_value_prorated			= target_value_prorated_n
				,	achievement
				,	achievement_factorized
				,	achievement_boostered
				,	achievement_factorized_boostered
	into		#result_individual
	from		#target t
	outer apply (
		select		result_value_individual	= iif(t.team_definition = @team_definition_dynamic, sum(r.result_value_individual)	, max(r.result_value_individual))
				,	result_value_team		= iif(t.team_definition = @team_definition_dynamic, sum(r.result_value_team)		, max(r.result_value_team))
				,	result_value			= iif(t.team_definition = @team_definition_dynamic, sum(r.result_value)				, max(r.result_value))
				,	factorized_delta		= iif(t.team_definition = @team_definition_dynamic, sum(r.factorized_delta)			, max(r.factorized_delta))
				,	boostered_delta			= iif(t.team_definition = @team_definition_dynamic, sum(r.boostered_delta)			, max(r.boostered_delta))
				,	result_team_name		= max(r.team_name)
		from	#result r
		where	r.metric_code = t.metric_code
		and		isnull(r.segment_code, '') = isnull(t.segment_code, '')
		and		((t.achievement_calculation = @achievement_calculation_team and t.team_definition = @team_definition_static) 
			or	(r.person_id = t.person_id))
	) result
	join		#employee_plan_assignment epa
		on		epa.person_id = t.person_id
	left join #target_to_add_sum tta
		on	tta.person_id = t.person_id
			and	tta.metric_code = t.metric_code
			and	isnull(tta.segment_code, '') = isnull(t.segment_code, '') 
	outer apply (
		select		target_value_prorated_n	= nullif(t.target_value_prorated, 0)	
				,	target_value_n			= nullif(t.target_value, 0) 	
	) t20
	outer apply (
		select	achievement							= nullif(((result.result_value + isnull(tta.target_value,0)) * 100.), 0) / target_value_prorated_n, 
				achievement_factorized				= nullif(((result.result_value + isnull(tta.target_value,0) + factorized_delta) * 100.), 0) / target_value_prorated_n,  
				achievement_boostered				= nullif(((result.result_value + isnull(tta.target_value,0) + boostered_delta)  * 100.), 0) / target_value_prorated_n,  
				achievement_factorized_boostered	= nullif(((result.result_value + isnull(tta.target_value,0) + factorized_delta + boostered_delta ) * 100.), 0) / target_value_prorated_n  
	) t30
	where		target_value_prorated_n is not null;

	/* =================================================================================== */
	/* Accelerators ------------------------------------------------------------ */
	/* =================================================================================== */
		/* person_id filter : XML 2 table */

	/* Individual achievement calculation ------------------------------------------------ */
	select			ri.person_id
				,	ri.metric_code
				,	ri.segment_code
				,	ri.target_value					
				,	ri.target_value_prorated			
				,	ri.result_value					
				,	ri.factorized_delta		
				,	ri.boostered_delta
				,	ri.achievement_factorized
				,	ri.achievement_boostered
				,	ri.achievement_factorized_boostered
				,	ri.achievement
				,	ars.achievement_min
				,	ars.achievement_max
				,	case when afc.accelerator_cap_value =-1 or isnull(@accelerated,0) <> 1 then NULL else afc.accelerator_cap_value end as accelerator_cap_value
				,	afc.accelerator_cap
				,	afc.accelerator_floor
				,	t1.achievement_accelerated
				,	t2.acceleration		
	into		#result_accelerated_individual
	from		#result_individual ri
	left join #accelerator_floor_cap afc
		on isnull(ri.segment_code,'') = isnull(afc.segment_code,'')
		and ri.metric_code = afc.target_code
	left join #accelerator_ranges_static ars
		on isnull(ri.segment_code,'') = isnull(ars.segment_code,'')
		and ri.metric_code = ars.target_code
		and ri.achievement >= ars.achievement_min 
		and (ri.achievement < ars.achievement_max or ars.achievement_max is null)
	outer apply
		(select achievement_accelerated =
			case 
				when @accelerated = 0  then ri.achievement
				when ri.achievement < afc.accelerator_floor	then 0
				when ri.achievement > afc.accelerator_cap and afc.accelerator_cap_value <> -1	then afc.accelerator_cap_value + ri.achievement - afc.accelerator_cap
				when ars.target_code is null then ri.achievement
				else ars.achievement_accelerated_base + (ri.achievement - achievement_min) * ars.accelerator_value
			end
		) t1
	outer apply
		(select acceleration = t1.achievement_accelerated - ri.achievement
		) t2

	/* =================================================================================== */
	/* Result (with metric weights calc) ------------------------------------------------- */
	/* =================================================================================== */

	/* Achievement with acceleration (per metric code) ---------------------------- */
	select		kf.person_id
			,	kf.metric_code
			,	segment_code
			,	team_name
			,	target_value
			,	target_value_prorated
			,	result_value
			,	achievement
			,	acceleration											= acceleration
			,	weight_segment											= ws.weight_segment * 100
			,	weight_metric											= wm.weight_metric * 100
			,	achievement_cap
			,	achievement_floor
			,	acceleration_with_kickers
			,	team_definition
-- no weights 
			,	achievement_accelerated_with_kickers					
			,	achievement_not_accelerated_with_kickers
			,	achievement_accelerated_with_kickers_caps				= iif(achievement_accelerated_with_kickers > achievement_cap
																				,achievement_cap
																				,achievement_accelerated_with_kickers)
			,	achievement_not_accelerated_with_kickers_caps			= iif(achievement_not_accelerated_with_kickers > achievement_cap
																				,achievement_cap
																				,achievement_not_accelerated_with_kickers)
-- all weights 
			,	achievement_accelerated_with_kickers_weighted			= achievement_accelerated_with_kickers
																			* ws.weight_segment
																			* wm.weight_metric
			,	achievement_not_accelerated_with_kickers_weighted		= achievement_not_accelerated_with_kickers
																			* ws.weight_segment
																			* wm.weight_metric
			,	achievement_accelerated_with_kickers_weighted_caps		= iif(achievement_accelerated_with_kickers > achievement_cap
																				,achievement_cap
																				,achievement_accelerated_with_kickers)
																			* ws.weight_segment
																			* wm.weight_metric
			,	achievement_not_accelerated_with_kickers_weighted_caps	= iif(achievement_not_accelerated_with_kickers > achievement_cap
																				,achievement_cap
																				,achievement_not_accelerated_with_kickers)
																			* ws.weight_segment
																			* wm.weight_metric
--- weights segment level
			,	achievement_accelerated_with_kickers_weighted_segment_lvl			
																		= achievement_accelerated_with_kickers
																			* ws.weight_segment
			,	achievement_not_accelerated_with_kickers_weighted_segment_lvl		
																		= achievement_not_accelerated_with_kickers
																			* ws.weight_segment
			,	achievement_accelerated_with_kickers_weighted_segment_lvl_caps		
																		= iif(achievement_accelerated_with_kickers > achievement_cap
																				,achievement_cap
																				,achievement_accelerated_with_kickers)
																			* ws.weight_segment
			,	achievement_not_accelerated_with_kickers_weighted_segment_lvl_caps	
																		= iif(achievement_not_accelerated_with_kickers > achievement_cap
																				,achievement_cap
																				,achievement_not_accelerated_with_kickers)
																			* ws.weight_segment
--- weights metric level
			,	achievement_accelerated_with_kickers_weighted_metric_lvl			
																		= achievement_accelerated_with_kickers
																			* wm.weight_metric
			,	achievement_not_accelerated_with_kickers_weighted_metric_lvl		
																		= achievement_not_accelerated_with_kickers
																			* wm.weight_metric
			,	achievement_accelerated_with_kickers_weighted_metric_lvl_caps		
																		= iif(achievement_accelerated_with_kickers > achievement_cap
																				,achievement_cap
																				,achievement_accelerated_with_kickers)
																			* wm.weight_metric
			,	achievement_not_accelerated_with_kickers_weighted_metric_lvl_caps	
																		= iif(achievement_not_accelerated_with_kickers > achievement_cap
																				,achievement_cap
																				,achievement_not_accelerated_with_kickers)
																			* wm.weight_metric
-- factorized values
			,	result_factorized_value									= result_value + factorized_delta
			,	achievement_factorized									= achievement_factorized
			,	achievement_factorized_caps								= iif(achievement_factorized > achievement_cap
																				,achievement_cap
																				,achievement_factorized)
			,	achievement_factorized_delta							= factorized_achievement_delta
-- factorized values - weighted segment level
			,	achievement_factorized_weighted_segment_lvl				= achievement_factorized
																			* ws.weight_segment
			,	achievement_factorized_weighted_segment_lvl_caps		= iif(achievement_factorized > achievement_cap
																				,achievement_cap
																				,achievement_factorized)
																			* ws.weight_segment
			,	achievement_factorized_delta_weighted_segment_lvl		= factorized_achievement_delta
																			* ws.weight_segment

-- factorized values - weighted
			,	achievement_factorized_caps_weighted					= iif(achievement_factorized > achievement_cap
																				,achievement_cap
																				,achievement_factorized)
																			* ws.weight_segment
																			* wm.weight_metric
			,	achievement_factorized_delta_weighted					= factorized_achievement_delta
																			* ws.weight_segment
																			* wm.weight_metric

			

			-- boostered values
			,	result_boostered_value									= result_value + boostered_delta
			,	achievement_boostered_delta								= boostered_achievement_delta
			,	achievement_boostered
			,	achievement_boostered_caps_weighted						= iif(achievement_boostered > achievement_cap
																				,achievement_cap
																				,achievement_boostered)
																			* ws.weight_segment
																			* wm.weight_metric
			,	achievement_boostered_delta_weighted					= boostered_achievement_delta
																			* ws.weight_segment
																			* wm.weight_metric


			-- boostered factorized values
			,	result_factorized_boostered_value						= result_value + boostered_delta + factorized_delta
			,	achievement_factorized_boostered 
			,	achievement_factorized_boostered_caps_weighted			= iif(achievement_factorized_boostered > achievement_cap
																				,achievement_cap
																				,achievement_factorized_boostered)
																			* ws.weight_segment
																			* wm.weight_metric

			-- final values (factorized, boostered, accelerated)
			,	achievement_final											= achievement_final
			,	achievement_final_caps										= iif(achievement_final > achievement_cap
																				,achievement_cap
																				,achievement_final)
			,	achievement_final_weighted_segment_lvl						= (achievement_final)
																				* ws.weight_segment
			,	achievement_final_weighted_segment_lvl_caps					= iif(achievement_final > achievement_cap
																					,achievement_cap
																					,achievement_final)
																				* ws.weight_segment
			,	achievement_final_caps_weighted								= iif(achievement_final > achievement_cap
																					,achievement_cap
																					,achievement_final)
																				* ws.weight_segment
																				* wm.weight_metric
			, achievement_preliminary										= IIF(pd.metric_code = @target_rev, @rev_preliminary_achievement, null)
	into	#achievement_accelerated_segment
	from	#result_accelerated_individual kf
	join	#plan_definition pd
		on	pd.metric_code = kf.metric_code
	left join _tb_b2b_plan_person_exception ppe 
		on ppe.person_id = kf.person_id
		and ppe.id_b2b_plan = @plan_id
		and ppe.[period] = @period_id
		and ppe.metric_code = kf.metric_code
	outer apply (
		select	acceleration_with_kickers	= acceleration 
				,achievement_cap			= accelerator_cap_value
				,achievement_floor			= accelerator_floor
	) acceleration_kickers
	outer apply (
		select		achievement_accelerated_with_kickers		= achievement_accelerated
				,	achievement_not_accelerated_with_kickers	= achievement
				,	weight_segment								= case 
																	when segment_code = 'BMM' then COALESCE(ppe.bmm_weight, pd.bmm_weight)
																	when segment_code = 'ENT' then COALESCE(ppe.ent_weight, pd.ent_weight)																					
																	end
	) t10
	outer apply (
		select iif(segment_data_flag = 0, 1, isnull(weight_segment, 100) / 100.)	as weight_segment
	) ws
	outer apply (
		select isnull(coalesce(ppe.weight, pd.weight), 100) / 100.	as weight_metric
	) wm
	outer apply (
		select	top 1 team_name
		from	#team_data td
		where	td.metric_code = kf.metric_code
		and		isnull(td.segment_code, '') = isnull(kf.segment_code, '')
		and		(td.team_definition = @team_definition_static or td.person_id = kf.person_id)
	) t20
	outer apply (
		select factorized_achievement_delta = achievement_factorized - achievement_not_accelerated_with_kickers,
			 boostered_achievement_delta = achievement_boostered - achievement_not_accelerated_with_kickers 
	) t30
	outer apply (
		select achievement_final = achievement_accelerated_with_kickers + factorized_achievement_delta + boostered_achievement_delta
	) t40

	/* Achievement metric code grouping & caps handling ---------------------------------- */
	select			aas.person_id
				,	metric_code												= aas.metric_code
				,	weight_metric											= max(aas.weight_metric)	
				,	target_value											= sum(aas.target_value)									
				,	target_value_prorated									= sum(aas.target_value_prorated	)								
				,	result_value											= sum(aas.result_value)	
				,	team_name												= max(aas.team_name)
				,	achievement_cap											= max(aas.achievement_cap)
				,	achievement_accelerated_with_kickers					= sum(aas.achievement_accelerated_with_kickers_weighted_segment_lvl)
				,	achievement_not_accelerated_with_kickers				= sum(aas.achievement_not_accelerated_with_kickers_weighted_segment_lvl)
				,	achievement_accelerated_with_kickers_caps  				= sum(aas.achievement_accelerated_with_kickers_weighted_segment_lvl_caps)
				,	achievement_not_accelerated_with_kickers_caps  			= sum(aas.achievement_not_accelerated_with_kickers_weighted_segment_lvl_caps)
				,	achievement_accelerated_with_kickers_caps_weighted		= sum(aas.achievement_accelerated_with_kickers_weighted_caps)
				,	achievement_not_accelerated_with_kickers_caps_weighted	= sum(aas.achievement_not_accelerated_with_kickers_weighted_caps)
				,	result_factorized_value									= sum(aas.result_factorized_value)
				,	achievement_factorized									= sum(aas.achievement_factorized_weighted_segment_lvl)
				,	achievement_factorized_caps								= sum(aas.achievement_factorized_weighted_segment_lvl_caps)
				,	achievement_factorized_delta							= sum(aas.achievement_factorized_delta_weighted_segment_lvl)
				,	achievement_final										= sum(aas.achievement_final_weighted_segment_lvl)
				,	achievement_final_caps									= sum(aas.achievement_final_weighted_segment_lvl_caps)
				,	achievement_factorized_caps_weighted					= sum(aas.achievement_factorized_caps_weighted)	
				,	achievement_factorized_delta_weighted					= sum(aas.achievement_factorized_delta_weighted)	
				,	achievement_final_caps_weighted							= sum(aas.achievement_final_caps_weighted)
				,	result_boostered_value									= sum(aas.result_boostered_value)									
				,	achievement_boostered_delta								= sum(aas.achievement_boostered_delta)
				,	achievement_boostered									= sum(aas.achievement_boostered)						
				,	result_factorized_boostered_value						= sum(aas.result_factorized_boostered_value)
				,	achievement_factorized_boostered 						= sum(aas.achievement_factorized_boostered)
				,	achievement_boostered_caps_weighted						= sum(achievement_boostered_caps_weighted)					
				,	achievement_boostered_delta_weighted					= sum(achievement_boostered_delta_weighted)		
				,	achievement_factorized_boostered_caps_weighted			= sum(achievement_factorized_boostered_caps_weighted)	
				,	achievement_floor										= min(aas.achievement_floor)		--we can use the min function because we need that value only for plans without segments, where value on metric level is the same as on segment
				,	achievement_preliminary									= IIF(aas.metric_code = @target_rev, @rev_preliminary_achievement, null)

	into		#achievement_accelerated_metric
	from		#achievement_accelerated_segment aas
	join		#plan_definition pd
		on		pd.metric_code = aas.metric_code
	group by		aas.person_id
				,	aas.metric_code;

	/* Achievement person_id grouping with weight & plan caps handling ------------------- */
	select			person_id
				,	achievement_cap_on_plan_level_value = @achievement_cap_on_plan_level_value
				,	achievement_accelerated				= iif(sum(achievement_accelerated_with_kickers_caps_weighted) > @achievement_cap_on_plan_level_value,
															@achievement_cap_on_plan_level_value,
															sum(achievement_accelerated_with_kickers_caps_weighted))
				,	achievement_not_accelerated			= iif(sum(achievement_not_accelerated_with_kickers_caps_weighted) > @achievement_cap_on_plan_level_value,
															@achievement_cap_on_plan_level_value,
															sum(achievement_not_accelerated_with_kickers_caps_weighted))
				,	achievement_factorized				= iif(sum(achievement_factorized_caps_weighted) > @achievement_cap_on_plan_level_value,
															@achievement_cap_on_plan_level_value,
															sum(achievement_factorized_caps_weighted))
				,	achievement_factorized_delta		= sum(achievement_factorized_delta_weighted)
				,	achievement_boostered				= iif(sum(achievement_boostered_caps_weighted) > @achievement_cap_on_plan_level_value,
															@achievement_cap_on_plan_level_value,
															sum(achievement_boostered_caps_weighted))
				,	achievement_factorized_boostered	= iif(sum(achievement_factorized_boostered_caps_weighted) > @achievement_cap_on_plan_level_value,
															@achievement_cap_on_plan_level_value,
															sum(achievement_factorized_boostered_caps_weighted))

				,	achievement_boostered_delta			= sum(achievement_boostered_delta_weighted)
				,	achievement_final					= iif(sum(achievement_final_caps_weighted) > @achievement_cap_on_plan_level_value,
															@achievement_cap_on_plan_level_value,
															sum(achievement_final_caps_weighted))
				,	achievement_preliminary				= sum(IIF(metric_code = @target_rev, @rev_preliminary_achievement, null) * weight_metric)

	into		#achievement_accelerated
	from		#achievement_accelerated_metric
	group by	person_id;		

	/* =================================================================================== */
	/* Final result & save data in static tables ----------------------------------------- */
	/* =================================================================================== */

	/* Get py_payee data */
	select		aa.person_id
			,	pp.idPayee
			,	pp.firstname
			,	pp.lastname
	into	#payee_data
	from	#achievement_accelerated aa
	join	py_Payee (nolock) pp
		on	codePayee = aa.person_id;

	/* Debug mode ------------------------------------------------------------------------ */
	if(@debug_mode = 1)
	begin
		if(@debug_tables_enum & power(2, 0) <> 0)
			select		enum 								= power(2, 0)
					,	tab_name							= 'global_params'
					,	plan_id								= @plan_id
					,	plan_year							= @plan_year
					,	period_id							= @period_id
					,	date_start							= @date_start
					,	date_end							= @date_end
					,	achievement_cap_on_plan_level_value	= @achievement_cap_on_plan_level_value

		if(@debug_tables_enum & power(2, 1) <> 0)
			select	enum = power(2, 1), tab_name = '#employee_plan_assignment', *
			from	#employee_plan_assignment;

		if(@debug_tables_enum & power(2, 2) <> 0)
			select	enum = power(2, 2), tab_name = '#plan_definition', *
			from	#plan_definition;

		if(@debug_tables_enum & power(2, 3) <> 0)
			select	enum = power(2, 3), tab_name = '#target', *
			from	#target;

		if(@debug_tables_enum & power(2, 4) <> 0)
			select	enum = power(2, 4), tab_name = '#result', *
			from	#result;

		if(@debug_tables_enum & power(2, 5) <> 0)
			select	enum = power(2, 5), tab_name = '#calc_team_data', *
			from	#calc_team_data;

		if(@debug_tables_enum & power(2, 6) <> 0)
			select	enum = power(2, 6), tab_name = '#calc_company_data', *
			from	#calc_company_data;

		if(@debug_tables_enum & power(2, 7) <> 0)
			select	enum = power(2, 7), tab_name = '#accelerator_ranges_static', *
			from	#accelerator_ranges_static;

		if(@debug_tables_enum & power(2, 8) <> 0)
			select	enum = power(2, 8), tab_name = '#result_accelerated_individual', *
			from	#result_accelerated_individual;

		if(@debug_tables_enum & power(2, 9) <> 0)
			select	enum = power(2, 9), tab_name = '#result_details', *
			from	#result_details;

		if(@debug_tables_enum & power(2, 10) <> 0)
			select	enum = power(2, 10), tab_name = '#achievement_accelerated_segment', *
			from	#achievement_accelerated_segment;

		if(@debug_tables_enum & power(2, 11) <> 0)
			select	enum = power(2, 11), tab_name = '#achievement_accelerated_metric', *
			from	#achievement_accelerated_metric;

		if(@debug_tables_enum & power(2, 12) <> 0)
			select	enum = power(2, 12), tab_name = '#achievement_accelerated', *
			from	#achievement_accelerated;

		if(@debug_tables_enum & power(2, 13) <> 0)
			select	enum = power(2, 13), tab_name = '#payee_data', *
			from	#payee_data;

		return;
	end;

	/* _tb_b2b_calc_revenue_account ------------------------------------------------------------ */
	delete	_tb_b2b_calc_revenue_account
	where	id_payment_dates = @id_payment_dates;

	IF OBJECT_ID('tempdb..#calc_revenue_account') IS NOT NULL
	BEGIN
		INSERT INTO _tb_b2b_calc_revenue_account
		(	[date_created]			
			,[id_plan]                                             
			,[year]                                                
			,[period]                                              
			,[id_payment_dates]                                    
			,[metric_code]                                         
			,[segment_code]                                        
			,[person_id]                                           
			,[sales_person_id]                                     
			,[a_number]											   
			,[company_name]		
			,[is_eof]
			,[result_value]                                        
			,[result_factorized_value]
			,[result_boostered_value])
		SELECT 
				@now
			,	@plan_id
			,	@plan_year
			,	@period_id
			,	@id_payment_dates                                   
			,	[metric_code]                                         
			,	[segment_code]                                        
			,	[person_id]                                           
			,	[sales_person_id]                                     
			,	[a_number]											   
			,	[company_name]		
			,	[group_eof]
			,	[result_value]                                        
			,	[result_factorized_value]  
			,	[result_boostered_value]
		FROM #calc_revenue_account
	END

	/* _tb_b2b_calc_team_data ------------------------------------------------------------ */
	delete	_tb_b2b_calc_team_data
	where	id_payment_dates = @id_payment_dates;

	insert into _tb_b2b_calc_team_data (
				date_created
			,	id_plan
			,	year
			,	period
			,	id_payment_dates
			,	metric_code
			,	segment_code
			,	person_id
			,	id_payee
			,	first_name
			,	last_name
			,	achievement_calculation
			,	team_definition
			,	ex_on_plan
			,	team_name
			,	target_value_individual
			,	result_value_individual
			,	factorized_delta_individual
			,	boostered_delta_individual
			,	team
			,	unit
			,	title
			,	profile
			,	level_1
			,	level_2
			,	level_3
			,	level_4)
	select		@now
			,	@plan_id
			,	@plan_year
			,	@period_id
			,	@id_payment_dates
			,	metric_code
			,	segment_code
			,	ctd.person_id
			,	id_payee			= pp.idPayee
			,	first_name			= pp.firstname
			,	last_name			= pp.lastname
			,	achievement_calculation
			,	team_definition
			,	ex_on_plan
			,	team_name
			,	target_value_individual
			,	result_value_individual
			,	factorized_delta_individual
			,	boostered_delta_individual
			,	team
			,	unit
			,	title
			,	profile
			,	level_1
			,	level_2
			,	level_3
			,	level_4
	from		#calc_team_data ctd
	join		py_Payee (nolock) pp
		on		codePayee = ctd.person_id
	order by		ctd.person_id
				,	metric_code
				,	segment_code		
				
	/* _tb_b2b_calc_company_data --------------------------------------------------------- */
	delete	_tb_b2b_calc_company_data
	where	id_payment_dates = @id_payment_dates;

	insert into _tb_b2b_calc_company_data (
				date_created
			,	id_plan
			,	year
			,	period
			,	id_payment_dates
			,	person_id
			,	team_name
			,	metric_code
			,	segment_code
			,	company_name
			,	a_number
			,	result_value
			,	factorized_result_delta
			,	boostered_result_delta)
	select		@now
			,	@plan_id
			,	@plan_year
			,	@period_id
			,	@id_payment_dates
			,	person_id
			,	team_name_eop
			,	metric_code
			,	segment_code
			,	company_name
			,	a_number
			,	result_value_individual
			,	factorized_result_delta
			,	boostered_result_delta
	from		#calc_company_data ctd
	order by	metric_code
			,	segment_code	
			,	company_name
			,	a_number;

	/* _tb_b2b_calc_shares_per_person --------------------------------------------------------- */
	delete	_tb_b2b_calc_shares_per_person
	where	id_payment_dates = @id_payment_dates;

	insert into _tb_b2b_calc_shares_per_person (
				date_created
			,	id_plan
			,	year
			,	id_payment_dates
			,	metric_code
			,	segment_code
			,	person_id
			,	original_person_id
			,	company_name
			,	a_number
			,	team_name
			,	result_value
			,	factorized_result_delta
			,	boostered_result_delta)
	select		@now
			,	@plan_id
			,	@plan_year
			,	@id_payment_dates
			,	metric_code
			,	segment_code
			,	person_id
			,	original_person_id
			,	company_name
			,	a_number
			,	team_name
			,	result_value
			,	factorized_result_delta
			,	boostered_result_delta
	from		#results_shares_per_person
	order by	metric_code
			,	segment_code	
			,	company_name
			,	a_number;

	/* _tb_b2b_calc_nov_detailed --------------------------------------------------- */

	delete	_tb_b2b_calc_nov_detailed
	where	id_payment_dates = @id_payment_dates;

	insert into _tb_b2b_calc_nov_detailed
	(
		person_id
		,id_plan
		,year
		,quarter
		,start_date
		,end_date
		,original_person_id
		,id_payment_dates
		,metric_code
		,segment_code
		,a_number
		,company_name
		,team_name
		,datasource
		,result_value
		,factorized_result_delta
		,boostered_result_delta
		,level_1
		,level_2
		,level_3
		,level_4
		,team
		,title
		,unit
		,profile  
	)
	select
		person_id
		,@plan_id
		,@plan_year
		,quarter
		,start_date
		,end_date
		,original_person_id
		,id_payment_dates
		,metric_code
		,segment_code
		,a_number
		,company_name
		,team_name
		,datasource
		,result_value
		,factorized_result_delta
		,boostered_result_delta
		,level_1
		,level_2
		,level_3
		,level_4
		,team
		,title
		,unit
		,profile   
	from #nov_detailed

	/* _tb_b2b_calc_result_metric_code --------------------------------------------------- */
	delete	_tb_b2b_calc_result_segment
	where	id_payment_dates = @id_payment_dates;

	insert into _tb_b2b_calc_result_segment (
				date_created
				,id_plan
				,year
				,period
				,id_payment_dates
				,person_id
				,id_payee
				,first_name
				,last_name
				,metric_code
				,segment_code
				,target_value
				,target_value_prorated
				,result_value
				,achievement
				,acceleration
				,acceleration_with_kickers
				,achievement_accelerated_with_kickers
				,achievement_accelerated_with_kickers_weighted
				,team_name
				,weight_segment
				,weight_metric
				,achievement_cap
				,achievement_not_accelerated_with_kickers
				,achievement_not_accelerated_with_kickers_weighted
				,achievement_accelerated_with_kickers_caps
				,achievement_not_accelerated_with_kickers_caps
				,achievement_accelerated_with_kickers_weighted_caps
				,achievement_not_accelerated_with_kickers_weighted_caps
				,achievement_accelerated_with_kickers_weighted_segment_lvl
				,achievement_not_accelerated_with_kickers_weighted_segment_lvl
				,achievement_accelerated_with_kickers_weighted_segment_lvl_caps
				,achievement_not_accelerated_with_kickers_weighted_segment_lvl_caps
				,achievement_accelerated_with_kickers_weighted_metric_lvl
				,achievement_not_accelerated_with_kickers_weighted_metric_lvl
				,achievement_accelerated_with_kickers_weighted_metric_lvl_caps
				,achievement_not_accelerated_with_kickers_weighted_metric_lvl_caps
				,result_factorized_value
				,achievement_factorized
				,achievement_factorized_caps
				,achievement_factorized_delta
				,achievement_final
				,achievement_final_caps
				,achievement_floor
				,result_boostered_value			
				,achievement_boostered_delta		
				,achievement_boostered
				,result_factorized_boostered_value
				,achievement_factorized_boostered 
				,achievement_boostered_caps_weighted
				,achievement_boostered_delta_weighted
				,achievement_factorized_boostered_caps_weighted
				,achievement_preliminary
				)
	select		@now
			,	@plan_id
			,	@plan_year
			,	@period_id
			,	@id_payment_dates
			,	person_id			= pd.person_id
			,	id_payee			= pd.idPayee
			,	first_name			= pd.firstname
			,	last_name			= pd.lastname
			,	metric_code
			,	segment_code
			,	target_value
			,	target_value_prorated
			,	result_value
			,	achievement
			,	acceleration
			,	acceleration_with_kickers
			,	achievement_accelerated_with_kickers
			,	achievement_accelerated_with_kickers_weighted
			,	team_name
			,	weight_segment
			,	weight_metric
			,	achievement_cap
			,	achievement_not_accelerated_with_kickers
			,	achievement_not_accelerated_with_kickers_weighted
			,	achievement_accelerated_with_kickers_caps
			,	achievement_not_accelerated_with_kickers_caps
			,	achievement_accelerated_with_kickers_weighted_caps
			,	achievement_not_accelerated_with_kickers_weighted_caps
			,	achievement_accelerated_with_kickers_weighted_segment_lvl
			,	achievement_not_accelerated_with_kickers_weighted_segment_lvl
			,	achievement_accelerated_with_kickers_weighted_segment_lvl_caps
			,	achievement_not_accelerated_with_kickers_weighted_segment_lvl_caps
			,	achievement_accelerated_with_kickers_weighted_metric_lvl
			,	achievement_not_accelerated_with_kickers_weighted_metric_lvl
			,	achievement_accelerated_with_kickers_weighted_metric_lvl_caps
			,	achievement_not_accelerated_with_kickers_weighted_metric_lvl_caps
			,	result_factorized_value		
			,	achievement_factorized			
			,	achievement_factorized_caps	
			,	achievement_factorized_delta	
			,	achievement_final				
			,	achievement_final_caps	
			,	achievement_floor
			,	result_boostered_value			
			,	achievement_boostered_delta		
			,	achievement_boostered
			,	result_factorized_boostered_value
			,	achievement_factorized_boostered 
			,	achievement_boostered_caps_weighted
			,	achievement_boostered_delta_weighted
			,	achievement_factorized_boostered_caps_weighted
			,	achievement_preliminary
	from		#achievement_accelerated_segment aas
	join		#payee_data pd
		on		pd.person_id = aas.person_id
	order by	pd.person_id;

	/* _tb_b2b_calc_result_metric_code_booked -------------------------------------------- */
	delete	_tb_b2b_calc_result_metric
	where	id_payment_dates = @id_payment_dates;

	insert into _tb_b2b_calc_result_metric (
				date_created
			,	id_plan
			,	year
			,	period
			,	id_payment_dates
			,	person_id
			,	id_payee
			,	first_name
			,	last_name
			,	metric_code
			,	weight_metric
			,	team_name
			,	target_value
			,	target_value_prorated
			,	result_value
			,	achievement_cap
			,	achievement_accelerated_with_kickers
			,	achievement_accelerated_with_kickers_caps
			,	achievement_accelerated_with_kickers_caps_weighted
			,	achievement_not_accelerated_with_kickers
			,	achievement_not_accelerated_with_kickers_caps
			,	achievement_not_accelerated_with_kickers_caps_weighted
			,	result_factorized_value		
			,	achievement_factorized			
			,	achievement_factorized_caps	
			,	achievement_factorized_delta	
			,	achievement_final				
			,	achievement_final_caps
			,	achievement_floor
			,	result_boostered_value			
			,	achievement_boostered_delta		
			,	achievement_boostered
			,	result_factorized_boostered_value
			,	achievement_factorized_boostered 
			,	achievement_boostered_caps_weighted
			,	achievement_boostered_delta_weighted
			,	achievement_factorized_boostered_caps_weighted
			,	achievement_preliminary
			)
	select		@now
			,	@plan_id
			,	@plan_year
			,	@period_id
			,	@id_payment_dates
			,	person_id			= pd.person_id
			,	id_payee			= pd.idPayee
			,	first_name			= pd.firstname
			,	last_name			= pd.lastname
			,	metric_code
			,	weight_metric
			,	team_name
			,	target_value
			,	target_value_prorated
			,	result_value
			,	achievement_cap
			,	achievement_accelerated_with_kickers
			,	achievement_accelerated_with_kickers_caps
			,	achievement_accelerated_with_kickers_caps_weighted
			,	achievement_not_accelerated_with_kickers
			,	achievement_not_accelerated_with_kickers_caps
			,	achievement_not_accelerated_with_kickers_caps_weighted
			,	result_factorized_value		
			,	achievement_factorized			
			,	achievement_factorized_caps	
			,	achievement_factorized_delta	
			,	achievement_final				
			,	achievement_final_caps
			,	achievement_floor
			,	result_boostered_value			
			,	achievement_boostered_delta		
			,	achievement_boostered
			,	result_factorized_boostered_value
			,	achievement_factorized_boostered 
			,	achievement_boostered_caps_weighted
			,	achievement_boostered_delta_weighted
			,	achievement_factorized_boostered_caps_weighted
			,	achievement_preliminary

	from		#achievement_accelerated_metric aam
	join		#payee_data pd
		on		pd.person_id = aam.person_id
	order by	pd.person_id;

	/* _tb_b2b_calc_result --------------------------------------------------------------- */
	delete	_tb_b2b_calc_result
	where	id_payment_dates = @id_payment_dates;

	insert into _tb_b2b_calc_result (
				date_created
			,	id_plan
			,	year
			,	period
			,	id_payment_dates
			,	person_id
			,	id_payee
			,	first_name
			,	last_name
			,	achievement_accelerated
			,	achievement_cap_on_plan_level_value
			,	achievement_not_accelerated
			,	achievement_factorized
			,	achievement_factorized_delta
			,	achievement_final
			,	achievement_boostered				
			,	achievement_boostered_delta			
			,	achievement_factorized_boostered		
			,	achievement_preliminary
			)
	select		@now
			,	@plan_id
			,	@plan_year
			,	@period_id
			,	@id_payment_dates
			,	person_id			= pd.person_id
			,	id_payee			= pd.idPayee
			,	first_name			= pd.firstname
			,	last_name			= pd.lastname
			,	achievement_accelerated
			,	achievement_cap_on_plan_level_value
			,	achievement_not_accelerated
			,	achievement_factorized
			,	achievement_factorized_delta
			,	achievement_final
			,	achievement_boostered				
			,	achievement_boostered_delta			
			,	achievement_factorized_boostered	
			,	achievement_preliminary
	from		#achievement_accelerated aa
	join		#payee_data pd
		on		pd.person_id = aa.person_id
	order by	pd.person_id;

	update	_tb_b2b_payment_dates
	set			status				= iif(getdate() < pay_date , 'Payment refreshed', 'Payment generated')
			,	refresh_date_end	= cast(getdate() at time zone 'UTC' at time zone 'Central Europe Standard Time' as datetime)
	where	id = @id_payment_dates;   

	update	_tb_b2b_payment_dates_regular_periods
	set			status				= iif(getdate() < pay_date , 'Payment refreshed', 'Payment generated')
			,	refresh_date_end	= cast(getdate() at time zone 'UTC' at time zone 'Central Europe Standard Time' as datetime)
	where	id_b2b_plan = @plan_id
	and		year = @plan_year
	and		period = @period_id;

	----------------------------------------------------------------------------------------------------------------------------------
	-- Execution log: END
	----------------------------------------------------------------------------------------------------------------------------------

	EXEC dbo._sp_b2b_stored_procedure_audit_details 1, @procedure_name, @note, @event_id, @event_id_out = @event_id OUT
END
