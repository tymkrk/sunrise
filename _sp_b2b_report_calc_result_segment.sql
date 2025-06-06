CREATE  procedure [dbo].[_sp_b2b_report_calc_result_segment]
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

		----------------------------------------------------------------------------------------------------------------------------------
		-- Execution log: END
		----------------------------------------------------------------------------------------------------------------------------------

		EXEC dbo._sp_b2b_stored_procedure_audit_details 1, @procedure_name, @note, @event_id, @event_id_out = @event_id OUT
	
end;
