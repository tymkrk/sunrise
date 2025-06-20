CREATE procedure [dbo].[_sp_b2b_report_calc_result_segment]
	@person_id			nvarchar(200)
,	@id_payment_dates	int
,	@mode				int
as
begin	

		DECLARE @procedure_name	nvarchar(100)	= object_name(@@procid)
				,@note VARCHAR(1000)			= 'person_id: ' + ISNULL(CAST(@person_id AS VARCHAR(200)), 'null') 
													+ ', id_payment_dates: ' + ISNULL(CAST(@id_payment_dates AS VARCHAR(20)), 'null') 
													+ ', mode: ' + ISNULL(CAST(@mode AS VARCHAR(20)), 'null') 
				,@event_id int
		declare @end_date date


		----------------------------------------------------------------------------------------------------------------------------------
		-- Execution log: START
		----------------------------------------------------------------------------------------------------------------------------------

		EXEC dbo._sp_b2b_stored_procedure_audit_details 0, @procedure_name, @note, NULL, @event_id_out = @event_id OUT

	/* Result-set modes ------------------------------------------- */

	declare @achievement_cap_on_plan_level_name	varchar(100) = 'Achievement cap on plan level';
	declare @cap_default_value int = 300;

	
	/* Achievement on BMM Targets ---------------------------- */
	if(@mode = 3)
	begin
		select 
				sys_team_group_column
			,	metric_code
			,	segment_code
			,	achievement_cap / 100.	 as achievement_cap
			,	target_value = REPLACE(FORMAT(target_value, 'N0', 'en-US'), ',', '''') 
			,	result_value = REPLACE(FORMAT(result_value, 'N0', 'en-US'), ',', '''') 
			,	result_factorized_value = REPLACE(FORMAT(result_factorized_value, 'N0', 'en-US'), ',', '''') 
			,	result_boostered_value = REPLACE(FORMAT(result_boostered_value, 'N0', 'en-US'), ',', '''')
			,	achievement_not_accelerated_with_kickers / 100. as achievement_not_accelerated	
			,	achievement_factorized_delta /100. as delta
			,	achievement_boostered_delta /100. as boostered_delta
			,	achievement_accelerated_with_kickers_caps / 100. as achievement_accelerated	
			,	achievement_final_caps /100. as total_achievement
			,	weight_metric * weight_segment / 10000. as weight_metric
			,	achievement_final_caps * weight_metric / 10000. as final_achievement_weighted
			
			--Total weighted 
			,	achievement_not_accelerated_with_kickers_weighted_metric_lvl / 100.	as achievement_not_accelerated_weighted	
			,	achievement_factorized_delta * weight_metric / 10000.  as achievement_factorized_delta_weighted
			,	achievement_accelerated_with_kickers_weighted_metric_lvl_caps / 100.		as achievement_accelerated_weighted		
	
		from _tb_b2b_calc_result_segment s
		cross apply (
			select	sys_team_group_column
			from	_fn_b2b_report_calc_get_team_checksum (@id_payment_dates, metric_code, segment_code, team_name)
	) t10		
		join _tb_b2b_targets_definition td -- select * from _tb_b2b_targets_definition
			on td.target_code = s.metric_code
			and td.year = s.year
		where id_payment_dates = @id_payment_dates
		and person_id = @person_id
		and segment_code = 'BMM'
		order by td.[order]

		
	end;
		else
	
	/* Achievement on ENT Targets ---------------------------- */
	if(@mode = 4)
	begin
		select 
				sys_team_group_column
			,	metric_code
			,	segment_code
			,	achievement_cap / 100.	 as achievement_cap
			,	target_value = REPLACE(FORMAT(target_value, 'N0', 'en-US'), ',', '''')  
			,	result_value = REPLACE(FORMAT(result_value, 'N0', 'en-US'), ',', '''') 
			,	result_factorized_value = REPLACE(FORMAT(result_factorized_value, 'N0', 'en-US'), ',', '''') 
			,	result_boostered_value = REPLACE(FORMAT(result_boostered_value, 'N0', 'en-US'), ',', '''') 
			,	achievement_not_accelerated_with_kickers / 100. as achievement_not_accelerated	
			,	achievement_factorized_delta /100. as delta
			,	achievement_boostered_delta /100. as boostered_delta
			,	achievement_accelerated_with_kickers_caps / 100. as achievement_accelerated	
			,	achievement_final_caps /100. as total_achievement
			,	weight_metric * weight_segment / 10000. as weight_metric
			,	achievement_final_caps * weight_metric / 10000. as final_achievement_weighted
			
			--Total weighted 
			,	achievement_not_accelerated_with_kickers_weighted_metric_lvl / 100.	as achievement_not_accelerated_weighted	
			,	achievement_factorized_delta * weight_metric / 10000.  as achievement_factorized_delta_weighted
			,	achievement_accelerated_with_kickers_weighted_metric_lvl_caps / 100.		as achievement_accelerated_weighted	

		from _tb_b2b_calc_result_segment s
		cross apply (
			select	sys_team_group_column
			from	_fn_b2b_report_calc_get_team_checksum (@id_payment_dates, metric_code, segment_code, team_name)
	) t10
		join _tb_b2b_targets_definition td -- select * from _tb_b2b_targets_definition
			on td.target_code = s.metric_code
			and td.year = s.year
		where id_payment_dates = @id_payment_dates
		and person_id = @person_id
		and segment_code = 'ENT'
		order by td.[order]
	end;
	else

	if(@mode=5)
	begin
	select 
			BMM_weight				 = sum(iif (segment_code='BMM', weight_segment, 0))
		,	ENT_weight				 = sum(iif (segment_code='ENT', weight_segment, 0))
		,	achievement_Weight_BMM	 = sum(iif (segment_code='BMM', achievement_final, 0))
		,	achievement_Weight_ENT	 = sum(iif (segment_code='ENT', achievement_final, 0))
		,	cap_on_plan_lvl			 = max(cap_on_plan_lvl)
		,	achievement_cap			 = max(cast(round(coalesce(cap_on_plan_lvl, @cap_default_value), 0) as int))

		FROM
		(
	
			select			segment_code
						,	achievement_final						= iif(sum(crs.achievement_final_caps *weight)>max(cap_on_plan_lvl), max(cap_on_plan_lvl), sum(crs.achievement_final_caps *weight))/100.
						,	weight_segment							= sum(weight) 
						,	cap_on_plan_lvl							= max(cap_on_plan_lvl)
			from		_tb_b2b_calc_result_segment crs
			cross apply (
					select	weight= weight_segment*weight_metric/10000.
				) t10
			cross apply (	
					select	cap_on_plan_lvl = parameter_value
					from	_tb_b2b_plan_parameters (nolock) pp
					where	pp.id_b2b_plan = crs.id_plan
					and		parameter_name = @achievement_cap_on_plan_level_name
				) t20
				where	id_payment_dates = @id_payment_dates
				and person_id = @person_id
				group by segment_code
		) t
	end;


	if(@mode=6)
	begin
		select		target_code								= crs.metric_code	
			,	segment_code							= crs.segment_code
			,	target_cap								= crs.achievement_cap /100.
			,	target_value							= REPLACE(FORMAT(crs.target_value, 'N0', 'en-US'), ',', '''') 
			,	result_value							= REPLACE(FORMAT(crs.result_value, 'N0', 'en-US'), ',', '''') 
			,	result_factor_addon						= REPLACE(FORMAT(crs.result_factorized_value - crs.result_value, 'N0', 'en-US'), ',', '''') 
			,	result_booster_addon					= REPLACE(FORMAT(crs.result_boostered_value - crs.result_value, 'N0', 'en-US'), ',', '''') 
			,	result_factorized_boostered_value		= REPLACE(FORMAT(crs.result_factorized_boostered_value, 'N0', 'en-US'), ',', '''') 
			,	achievement_not_accelerated				= crs.achievement_not_accelerated_with_kickers / 100.
			,	achievement_factorized_boostered_delta	= (crs.achievement_boostered_delta + crs.achievement_factorized_delta) / 100.
			,	achievement_factorized_boostered		= crs.achievement_factorized_boostered / 100.
			,	achievement_accelerated_with_kickers	= crs.achievement_accelerated_with_kickers  / 100. 
			,	achievement_preliminary					= crs.achievement_preliminary	 / 100.
			,	achievement_total						= IIF(crs.metric_code = 'REV', crs.achievement_preliminary	 / 100., crs.achievement_final  / 100. )
			,	weight_metric							= crs.weight_metric	 / 100.
			,	weight_segment							= crs.weight_segment / 100.
			,	achievement_weighted					= IIF(crs.metric_code = 'REV', crs.achievement_preliminary	 / 100., crs.achievement_final  / 100. ) * weight_metric / 100. * crs.weight_segment / 100.
			,	sys_team_group_column
		from  _tb_b2b_calc_result_segment (nolock) crs
		left join _tb_b2b_targets_definition td
			on td.year = crs.year
			and td.target_code = crs.metric_code
		cross apply (
			select	sys_team_group_column
			from	_fn_b2b_report_calc_get_team_checksum (@id_payment_dates, crs.metric_code, NULL, crs.team_name)
		) t10
		where	crs.id_payment_dates = @id_payment_dates
		and		crs.person_id = @person_id
		order by crs.segment_code desc, td.[order]


	end;


	if(@mode=7)
	begin
		select
			@end_date =	date_end
		FROM _tb_b2b_payment_dates pd
		cross apply	_fn_b2b_get_period_dates (pd.[period], pd.[year])
		where pd.id = @id_payment_dates

		select		plan_name						= p.b2b_plan_name
				--,	metric_code						= cr.metric_code
				--,	segment_code					= cr.segment_code
				--,	weight_segment					= cr.weight_segment
				,	year							= cr.year
				,	period							= vbrp.name
				,	person_id						= cr.person_id			
				,	first_name						= cr.first_name
				,	last_name						= cr.last_name
				,	sales_team						= t10.team
				,	achievement						= sum(IIF(cr.metric_code = 'REV', cr.achievement_preliminary, cr.achievement_final) * cr.weight_metric  * cr.weight_segment / 1000000.)
				,	achievement_ent					= sum(IIF(cr.segment_code = 'ENT', IIF(cr.metric_code = 'REV', cr.achievement_preliminary, cr.achievement_final) * cr.weight_metric / 10000.,0))
				,	achievement_bmm					= sum(IIF(cr.segment_code = 'BMM', IIF(cr.metric_code = 'REV', cr.achievement_preliminary, cr.achievement_final) * cr.weight_metric / 10000.,0))
		from	_tb_b2b_calc_result_segment (nolock) cr -- select * from _tb_b2b_calc_result_metric
		join	_tb_b2b_plan (nolock) p
			on	p.id = cr.id_plan
		join	_vw_b2b_ref_periods vbrp
			on	cr.period = vbrp.id
		cross apply(
			select TOP 1
				pe.team
			FROM _tb_b2b_population_employee pe
			WHERE pe.person_id = cr.person_id
				and @end_date between pe.start_date and pe.end_date
			ORDER BY pe.start_date desc
				,pe.sales_person_id desc
				,pe.id desc
			) t10
		where	cr.id_payment_dates = @id_payment_dates
			and		cr.person_id = @person_id
		group by 
			p.b2b_plan_name
			,cr.year
			,vbrp.name
			,cr.person_id		
			,cr.first_name
			,cr.last_name
			,t10.team
	end


	if(@mode=8)
	begin
		select		
			cr.segment_code
			,	achievement					= sum(IIF(cr.metric_code = 'REV', cr.achievement_preliminary, cr.achievement_final) * cr.weight_metric / 10000.)
			,	weight_segment				= cr.weight_segment / 100.
			,	achievement_weighted		= sum(IIF(cr.metric_code = 'REV', cr.achievement_preliminary, cr.achievement_final) * cr.weight_metric  * cr.weight_segment / 1000000.)
		from	_tb_b2b_calc_result_segment (nolock) cr -- select * from _tb_b2b_calc_result_metric

		where	cr.id_payment_dates = @id_payment_dates
			and		cr.person_id = @person_id
		group by 
			cr.segment_code
			,	cr.weight_segment
		order by 
			cr.segment_code desc
	end

		----------------------------------------------------------------------------------------------------------------------------------
		-- Execution log: END
		----------------------------------------------------------------------------------------------------------------------------------

		EXEC dbo._sp_b2b_stored_procedure_audit_details 1, @procedure_name, @note, @event_id, @event_id_out = @event_id OUT
	
end;
