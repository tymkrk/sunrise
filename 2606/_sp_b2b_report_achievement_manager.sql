CREATE procedure [dbo].[_sp_b2b_report_achievement_manager]
	@id_user		int
,	@year			int
,	@period_id		int
,	@result_mode	int = 0 /* 0: result-set, 1: tmp table insert, 2: result-set aggregated for charts */
as
begin

		DECLARE @procedure_name	nvarchar(100)	= object_name(@@procid)
				,@note VARCHAR(1000)			= 'id_user: ' + ISNULL(CAST(@id_user AS VARCHAR(20)), 'null') 
													+ ', year: ' + ISNULL(CAST(@year AS VARCHAR(20)), 'null') 
													+ ', period_id: ' + ISNULL(CAST(@period_id AS VARCHAR(20)), 'null') 
													+ ', result_mode: ' + ISNULL(CAST(@result_mode AS VARCHAR(20)), 'null')
				,@event_id int

		----------------------------------------------------------------------------------------------------------------------------------
		-- Execution log: START
		----------------------------------------------------------------------------------------------------------------------------------

		EXEC dbo._sp_b2b_stored_procedure_audit_details 0, @procedure_name, @note, NULL, @event_id_out = @event_id OUT


	/* Prerequisites ---------------------------------------------- */
​
	declare		@person_id_manager		int
			,	@id_user_profile		int
			,	@person_id				int
			,	@id_payment_dates		int
			,	@hid_level				int
			,	@plan_name				nvarchar(100)
			,	@target_1				varchar(100)	
			,	@target_2				varchar(100)
			,	@target_3				varchar(100)
			,	@target_4				varchar(100)
			,	@target_1_name			varchar(100)	
			,	@target_2_name			varchar(100)
			,	@target_3_name			varchar(100)
			,	@target_4_name			varchar(100)
			,	@manager_name			varchar(200)
			,	@period_end_date		datetime
			,	@second_period_end_date	datetime
			,	@second_period_id		int
			;

	if @period_id = -1
	BEGIN

		set @period_id = (month(getdate())-1)/6 + 6
		set @second_period_id = (month(getdate())-1)/3 + 1

		set @second_period_end_date = (
		select	date_end
		from	_fn_b2b_get_period_dates (@second_period_id, @year))

	END

	else 

	begin
		set @second_period_id = null
		set @second_period_end_date = null
	end


	set @period_end_date = (
		select	date_end
		from	_fn_b2b_get_period_dates (@period_id, @year));



	declare @achievement_cap_on_plan_level_name	varchar(100) = 'Achievement cap on plan level';

	/* Targets in year */
	select 
	rn=row_number() over (order by target_code)
	,target_code
	,td.target_name
	into #targets
	from _tb_b2b_targets_definition td
	where year=@year
	
	select @target_1 = target_code , @target_1_name= target_name from #targets where rn=1;
	select @target_2 = target_code , @target_2_name= target_name from #targets where rn=2;
	select @target_3 = target_code , @target_3_name= target_name from #targets where rn=3;
	select @target_4 = target_code , @target_4_name= target_name from #targets where rn=4;
​
	/* User ID -> Person ID --------------------------------------- */
	select		@id_user_profile	= up.idUserProfile
			,	@person_id_manager	= pp.codePayee
			,	@manager_name		= isnull(pp.firstname, '') + ' ' + isnull(pp.lastname, '')
	from	k_users (nolock) u
	join	py_Payee (nolock) pp
		on	pp.idPayee = u.id_external_user
	/* Additional validation */
	join	_tb_b2b_sap_employee (nolock) se
		on	se.person_id = pp.codePayee
	join	k_profiles (nolock) p
		on	p.name_profile = 'B2B Manager'
	join	k_users_profiles (nolock) up
		on	up.id_user = u.id_user
		and	up.id_profile = p.id_profile
	where	u.id_user = @id_user;
	
	/* Get hierarchy structure ------------------------------------ */
	select	distinct 
				person_id	= employee_id
			,	hid_level	= iif(employee_id = @person_id_manager, 1, 2)
	into	#manager_hierarchy
	from	_tb_b2b_sap_employee_to_manager (nolock)
	where	@person_id_manager in (manager_id, employee_id)
	and		((start_date <= @period_end_date
		and		end_date >= @period_end_date)
		OR(@second_period_end_date is not null
		and start_date <= @second_period_end_date
		and end_date >= @second_period_end_date));


	/* Plan assigment & other checks ------------------------------ */
	select	distinct	
				person_id				= mh.person_id
			,	plan_name				= p.b2b_plan_name
			,	plan_id					= p.id
			,	id_payment_dates		= pd.id
	into	#plan_assigments
	from	#manager_hierarchy mh
	join	_tb_b2b_employee_plan_assignment (nolock) epa		
		on	epa.person_id = mh.person_id
	join	_tb_b2b_plan (nolock) p
		on	p.id = epa.id_b2b_plan
		and	p.year = @year
	join	_tb_b2b_payment_dates (nolock) pd
		on	pd.id_b2b_plan = p.id
		and	(pd.period = @period_id or pd.period = coalesce(@second_period_id,-1))
		and pd.year_to_date = 0
			cross apply (
		select	distinct id_b2b_plan,bmm_weight
		from	_tb_b2b_plan_definition (nolock) pd
		where	id_b2b_plan = p.id
	) t30
	where (bmm_weight IS NULL OR @result_mode = 1);		

  /* Get achievement -------------------------------------------- */
	select		crm.metric_code
			,	crm.person_id
			,	crm.id_payee
			,	crm.first_name
			,	crm.last_name			
			,	mh.hid_level
			,	pa.plan_id
			,	pa.plan_name			
			,	pa.id_payment_dates
						
			,	target_value_target_1							= target_value_target_1						
			,	achievement_not_accelerated_target_1			= achievement_not_accelerated_target_1	
			,	achievement_not_accelerated_weighted_target_1	= achievement_not_accelerated_weighted_target_1
			,	achievement_accelerated_target_1				= achievement_accelerated_target_1
			,	achievement_accelerated_weighted_target_1		= achievement_accelerated_weighted_target_1
			,	achievement_final_target_1						= achievement_final_target_1					
			,	achievement_final_weighted_target_1				= achievement_final_weighted_target_1			
			,	achievement_factorized_delta_weighted_target_1	= achievement_factorized_delta_weighted_target_1
			,	result_value_target_1							= result_value_target_1

			,	target_value_target_2							= target_value_target_2						
			,	achievement_not_accelerated_target_2			= achievement_not_accelerated_target_2	
			,	achievement_not_accelerated_weighted_target_2	= achievement_not_accelerated_weighted_target_2
			,	achievement_accelerated_target_2				= achievement_accelerated_target_2
			,	achievement_accelerated_weighted_target_2		= achievement_accelerated_weighted_target_2
			,	achievement_final_target_2						= achievement_final_target_2					
			,	achievement_final_weighted_target_2				= achievement_final_weighted_target_2			
			,	achievement_factorized_delta_weighted_target_2	= achievement_factorized_delta_weighted_target_2
			,	result_value_target_2							= result_value_target_2

			,	target_value_target_3							= target_value_target_3						
			,	achievement_not_accelerated_target_3			= achievement_not_accelerated_target_3
			,	achievement_not_accelerated_weighted_target_3	= achievement_not_accelerated_weighted_target_3
			,	achievement_accelerated_target_3				= achievement_accelerated_target_3
			,	achievement_accelerated_weighted_target_3		= achievement_accelerated_weighted_target_3
			,	achievement_final_target_3						= achievement_final_target_3					
			,	achievement_final_weighted_target_3				= achievement_final_weighted_target_3			
			,	achievement_factorized_delta_weighted_target_3	= achievement_factorized_delta_weighted_target_3
			,	result_value_target_3							= result_value_target_3

			,	target_value_target_4							= target_value_target_4						
			,	achievement_not_accelerated_target_4			= achievement_not_accelerated_target_4		
			,	achievement_not_accelerated_weighted_target_4	= achievement_not_accelerated_weighted_target_4
			,	achievement_accelerated_target_4				= achievement_accelerated_target_4
			,	achievement_accelerated_weighted_target_4		= achievement_accelerated_weighted_target_4
			,	achievement_final_target_4						= achievement_final_target_4					
			,	achievement_final_weighted_target_4				= achievement_final_weighted_target_4			
			,	achievement_factorized_delta_weighted_target_4	= achievement_factorized_delta_weighted_target_4
			,	result_value_target_4							= result_value_target_4

			,	achievent_cap_on_plan_level						= parameter_value
			
			,	hierarchy_level_relative						= dense_rank() over (order by hid_level)
			,	achievement_final_caps							= crm.achievement_final_caps
			,	weight_metric									= crm.weight_metric
​
	into	#data_proxy
	from	#manager_hierarchy mh
	join	#plan_assigments pa
		on	pa.person_id = mh.person_id
	join	_tb_b2b_calc_result_metric (nolock) crm
		on	crm.id_payment_dates = pa.id_payment_dates
		and	crm.person_id = mh.person_id
	
	cross apply (
		select		target_value_target_1							= iif(crm.metric_code = @target_1, crm.target_value, null)  
				,	achievement_not_accelerated_target_1			= iif(crm.metric_code = @target_1, crm.achievement_not_accelerated_with_kickers, null) 
				,	achievement_not_accelerated_weighted_target_1	= iif(crm.metric_code = @target_1, crm.achievement_not_accelerated_with_kickers*crm.weight_metric/100., null)
				,	achievement_accelerated_target_1				= iif(crm.metric_code = @target_1, crm.achievement_accelerated_with_kickers_caps, null)
				,	achievement_accelerated_weighted_target_1		= iif(crm.metric_code = @target_1, crm.achievement_accelerated_with_kickers*crm.weight_metric/100., null)
				,	achievement_final_target_1						= iif(crm.metric_code = @target_1, iif(@target_1 = 'rev', crm.achievement_preliminary,  crm.achievement_final_caps), null)
				,	achievement_final_weighted_target_1				= iif(crm.metric_code = @target_1, iif(@target_1 = 'rev', crm.achievement_preliminary,  crm.achievement_final_caps)*crm.weight_metric/100., null)
				,	achievement_factorized_delta_weighted_target_1	= iif(crm.metric_code = @target_1, crm.achievement_factorized_delta*crm.weight_metric/100., null)
				,	result_value_target_1							= iif(crm.metric_code = @target_1, crm.result_value, null)

				,	target_value_target_2							= iif(crm.metric_code = @target_2, crm.target_value, null)  
				,	achievement_not_accelerated_target_2			= iif(crm.metric_code = @target_2, crm.achievement_not_accelerated_with_kickers, null) 
				,	achievement_not_accelerated_weighted_target_2	= iif(crm.metric_code = @target_2, crm.achievement_not_accelerated_with_kickers*crm.weight_metric/100., null)
				,	achievement_accelerated_target_2				= iif(crm.metric_code = @target_2, crm.achievement_accelerated_with_kickers_caps, null)
				,	achievement_accelerated_weighted_target_2		= iif(crm.metric_code = @target_2, crm.achievement_accelerated_with_kickers*crm.weight_metric/100., null)
				,	achievement_final_target_2						= iif(crm.metric_code = @target_2, iif(@target_2 = 'rev', crm.achievement_preliminary,  crm.achievement_final_caps), null)
				,	achievement_final_weighted_target_2				= iif(crm.metric_code = @target_2, iif(@target_2 = 'rev', crm.achievement_preliminary,  crm.achievement_final_caps)*crm.weight_metric/100., null)
				,	achievement_factorized_delta_weighted_target_2	= iif(crm.metric_code = @target_2, crm.achievement_factorized_delta*crm.weight_metric/100., null)
				,	result_value_target_2							= iif(crm.metric_code = @target_2, crm.result_value, null)

				,	target_value_target_3							= iif(crm.metric_code = @target_3, crm.target_value, null)  
				,	achievement_not_accelerated_target_3			= iif(crm.metric_code = @target_3, crm.achievement_not_accelerated_with_kickers, null) 
				,	achievement_not_accelerated_weighted_target_3	= iif(crm.metric_code = @target_3, crm.achievement_not_accelerated_with_kickers*crm.weight_metric/100., null)
				,	achievement_accelerated_target_3				= iif(crm.metric_code = @target_3, crm.achievement_accelerated_with_kickers_caps, null)
				,	achievement_accelerated_weighted_target_3		= iif(crm.metric_code = @target_3, crm.achievement_accelerated_with_kickers*crm.weight_metric/100., null)
				,	achievement_final_target_3						= iif(crm.metric_code = @target_3, iif(@target_3 = 'rev', crm.achievement_preliminary,  crm.achievement_final_caps), null)
				,	achievement_final_weighted_target_3				= iif(crm.metric_code = @target_3, iif(@target_3 = 'rev', crm.achievement_preliminary,  crm.achievement_final_caps)*crm.weight_metric/100., null)
				,	achievement_factorized_delta_weighted_target_3	= iif(crm.metric_code = @target_3, crm.achievement_factorized_delta*crm.weight_metric/100., null)
				,	result_value_target_3							= iif(crm.metric_code = @target_3, crm.result_value, null)

				,	target_value_target_4							= iif(crm.metric_code = @target_4, crm.target_value, null)  
				,	achievement_not_accelerated_target_4			= iif(crm.metric_code = @target_4, crm.achievement_not_accelerated_with_kickers, null) 
				,	achievement_not_accelerated_weighted_target_4	= iif(crm.metric_code = @target_4, crm.achievement_not_accelerated_with_kickers*crm.weight_metric/100., null)
				,	achievement_accelerated_target_4				= iif(crm.metric_code = @target_4, crm.achievement_accelerated_with_kickers_caps, null)
				,	achievement_accelerated_weighted_target_4		= iif(crm.metric_code = @target_4, crm.achievement_accelerated_with_kickers*crm.weight_metric/100., null)
				,	achievement_final_target_4						= iif(crm.metric_code = @target_4, iif(@target_4 = 'rev', crm.achievement_preliminary,  crm.achievement_final_caps), null)
				,	achievement_final_weighted_target_4				= iif(crm.metric_code = @target_4, iif(@target_4 = 'rev', crm.achievement_preliminary,  crm.achievement_final_caps)*crm.weight_metric/100., null)
				,	achievement_factorized_delta_weighted_target_4	= iif(crm.metric_code = @target_4, crm.achievement_factorized_delta*crm.weight_metric/100., null)
				,	result_value_target_4							= iif(crm.metric_code = @target_4, crm.result_value, null)
	) t10	
	cross apply (	
		select	parameter_value
		from	_tb_b2b_plan_parameters (nolock) pp
		where	pp.id_b2b_plan = crm.id_plan
		and		parameter_name = @achievement_cap_on_plan_level_name
	) t20;
	
	-----------------------------------------------------------------------------------------------------------

	select			manager_name									= @manager_name
				,	is_manager										= iif(@person_id_manager = dp.person_id, 1, 0)
				,	dp.plan_id								
				,	plan_name										= max(plan_name)
				,	id_payment_dates								= max(dp.id_payment_dates)
				,	hierarchy_level_absolute						= max(hid_level)
				,	hierarchy_level_relative						= dense_rank() over (order by max(hid_level))
				,	dp.person_id				
				,	id_payee										= max(dp.id_payee)
				,	first_name										= max(dp.first_name)
				,	last_name										= max(dp.last_name)
				,	target_value_target_1							= nullif(sum(isnull(target_value_target_1, 0)), 0)
				,	achievement_not_accelerated_target_1			= nullif((sum(isnull(achievement_not_accelerated_target_1, 0)) / 100.), 0)
				,	achievement_not_accelerated_weighted_target_1	= nullif((sum(isnull(achievement_not_accelerated_weighted_target_1, 0)) / 100.), 0)
				,	achievement_accelerated_target_1				= nullif((sum(isnull(achievement_accelerated_target_1, 0)) / 100.), 0)
				,	achievement_accelerated_weighted_target_1		= nullif((sum(isnull(achievement_accelerated_weighted_target_1, 0)) / 100.), 0)
				,	achievement_final_target_1						= nullif((sum(isnull(achievement_final_target_1, 0)) / 100.), 0)
				,	achievement_final_weighted_target_1				= nullif((sum(isnull(achievement_final_weighted_target_1, 0)) / 100.), 0)
				,	result_value_target_1							= nullif(sum(isnull(result_value_target_1, 0)), 0)
				,	target_value_target_2							= nullif(sum(isnull(target_value_target_2, 0)), 0)
				,	achievement_not_accelerated_target_2			= nullif((sum(isnull(achievement_not_accelerated_target_2, 0)) / 100.), 0)
				,	achievement_not_accelerated_weighted_target_2	= nullif((sum(isnull(achievement_not_accelerated_weighted_target_2, 0)) / 100.), 0)
				,	achievement_accelerated_target_2				= nullif((sum(isnull(achievement_accelerated_target_2, 0)) / 100.), 0)
				,	achievement_accelerated_weighted_target_2		= nullif((sum(isnull(achievement_accelerated_weighted_target_2, 0)) / 100.), 0)
				,	achievement_final_target_2						= nullif((sum(isnull(achievement_final_target_2, 0)) / 100.), 0)
				,	achievement_final_weighted_target_2				= nullif((sum(isnull(achievement_final_weighted_target_2, 0)) / 100.), 0)
				,	result_value_target_2							= nullif(sum(isnull(result_value_target_2, 0)), 0)
				,	target_value_target_3							= nullif(sum(isnull(target_value_target_3, 0)), 0)
				,	achievement_not_accelerated_target_3			= nullif((sum(isnull(achievement_not_accelerated_target_3, 0)) / 100.), 0)
				,	achievement_not_accelerated_weighted_target_3	= nullif((sum(isnull(achievement_not_accelerated_weighted_target_3, 0)) / 100.), 0)
				,	achievement_accelerated_target_3				= nullif((sum(isnull(achievement_accelerated_target_3, 0)) / 100.), 0)
				,	achievement_accelerated_weighted_target_3		= nullif((sum(isnull(achievement_accelerated_weighted_target_3, 0)) / 100.), 0)
				,	achievement_final_target_3						= nullif((sum(isnull(achievement_final_target_3, 0)) / 100.), 0)
				,	achievement_final_weighted_target_3				= nullif((sum(isnull(achievement_final_weighted_target_3, 0)) / 100.), 0)				
				,	result_value_target_3							= nullif(sum(isnull(result_value_target_3, 0)), 0)
				,	target_value_target_4							= nullif(sum(isnull(target_value_target_4, 0)), 0)
				,	achievement_not_accelerated_target_4			= nullif((sum(isnull(achievement_not_accelerated_target_4, 0)) / 100.), 0)
				,	achievement_not_accelerated_weighted_target_4	= nullif((sum(isnull(achievement_not_accelerated_weighted_target_4, 0)) / 100.), 0)
				,	achievement_accelerated_target_4				= nullif((sum(isnull(achievement_accelerated_target_4, 0)) / 100.), 0)
				,	achievement_accelerated_weighted_target_4		= nullif((sum(isnull(achievement_accelerated_weighted_target_4, 0)) / 100.), 0)
				,	achievement_final_target_4						= nullif((sum(isnull(achievement_final_target_4, 0)) / 100.), 0)
				,	achievement_final_weighted_target_4				= nullif((sum(isnull(achievement_final_weighted_target_4, 0)) / 100.), 0)
				,	result_value_target_4							= nullif(sum(isnull(result_value_target_4, 0)), 0)
				,	achievement_factorized_delta					= nullif((max(cr.achievement_factorized_delta) / 100.), 0)
				,	achievement_final_weighted_cap					= nullif(
																		case when (max(cr.achievement_final))
																			> max(achievent_cap_on_plan_level)
																		then max(achievent_cap_on_plan_level) /100.
																		else (max(cr.achievement_final))
																		end, 0)/100.
				,	achievement_not_accelerated_weighted_sum		= nullif(max(cr.achievement_not_accelerated), 0)/100.
				,	achievement_accelerated_weighted_sum			= nullif(max(cr.achievement_accelerated), 0)/100.
				,	target_1_code									= @target_1
				,	target_2_code									= @target_2
				,	target_3_code									= @target_3
				,	target_4_code									= @target_4
				,	target_1_name									= @target_1_name
				,	target_2_name									= @target_2_name
				,	target_3_name									= @target_3_name
				,	target_4_name									= @target_4_name				
	into		#resultsb2b
	from		#data_proxy	dp
	join 		_tb_b2b_calc_result cr on cr.id_payment_dates = dp.id_payment_dates
		and		cr.person_id = dp.person_id
	group by		dp.plan_id
				,	dp.person_id
	order by	5, first_name, last_name

	---------------------------------------------------------------------------------
	if(@result_mode = 0)
	begin
		Select * from #resultsb2b 
		where  hierarchy_level_relative <= 2
		order by	5, first_name, last_name
	end;
	---------------------------------------------------------------------------------
	else if(@result_mode = 1)
	begin
		insert into #achievement
		Select			r.* 					
					,	@id_user as id_user
					,	t.segment_flag
		from		#resultsb2b r
		cross apply
			(select	distinct 
				id_b2b_plan
				,case when bmm_weight is null then 0 else 1 end as segment_flag
			from	_tb_b2b_plan_definition (nolock) pd
			where	id_b2b_plan = r.plan_id) t
		where		hierarchy_level_relative <= 2
		order by	5, first_name, last_name;
	end;
	---------------------------------------------------------------------------------
	else if(@result_mode = 2)
	begin
		select		plan_id							= dp.plan_id
				,	person_id						= dp.person_id
				,	first_name						= dp.first_name
				,	last_name						= dp.last_name
				,	metric_code						= dp.metric_code
				,	target_name						= t.target_name
				,	achievement_final_weighted		= dp.achievement_final_caps * dp.weight_metric / 10000.
		into	#result_proxy		
		from	#data_proxy dp
		join	#targets t
			on	t.target_code = dp.metric_code
		where	hierarchy_level_relative <= 2;

		select			person_id
					,	first_name					= max(first_name)
					,	last_name					= max(last_name)
					,	metric_code					= /* TMP !!! */ upper(replace(metric_code, 'arget_', ''))
					,	target_name					= max(target_name)
					,	achievement_final_weighted	= sum(achievement_final_weighted)
		from		#result_proxy
		group by		person_id
					,	metric_code
		union all
		select			person_id
					,	first_name					= max(first_name)
					,	last_name					= max(last_name)
					,	'Total'
					,	'Total'
					,	achievement_final_weighted_cap	= sum(achievement_final_weighted)
		from		#result_proxy
		group by	person_id;
	end;

		----------------------------------------------------------------------------------------------------------------------------------
		-- Execution log: END
		----------------------------------------------------------------------------------------------------------------------------------

		EXEC dbo._sp_b2b_stored_procedure_audit_details 1, @procedure_name, @note, @event_id, @event_id_out = @event_id OUT

end;
