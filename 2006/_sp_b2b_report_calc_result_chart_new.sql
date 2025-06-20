CREATE procedure [dbo].[_sp_b2b_report_calc_result_chart_new]
	@person_id			nvarchar(200) 
,	@id_payment_dates	int			  
,	@metric_code		nvarchar(10)  

as
begin

/*
        _..._
      .'     '.      _
     /    .-""-\   _/ \
   .-|   /:.   |  |   |
   |  \  |:.   /.-'-./
   | .-'-;:__.'    =/
   .'=  *=|NASA _.='
  /   _.  |    ;
 ;-.-'|    \   |
/   | \    _\  _\
\__/'._;.  ==' ==\
         \    \   |
         /    /   /
         /-._/-._/
         \   `\  \
          `-._/._/
*/

		DECLARE @procedure_name	nvarchar(100)	= object_name(@@procid)
				,@note VARCHAR(1000)			= 'person_id: ' + ISNULL(CAST(@person_id AS VARCHAR(200)), 'null') 
													+ ', id_payment_dates: ' + ISNULL(CAST(@id_payment_dates AS VARCHAR(20)), 'null') 
				,@event_id int

		----------------------------------------------------------------------------------------------------------------------------------
		-- Execution log: START
		----------------------------------------------------------------------------------------------------------------------------------

		EXEC dbo._sp_b2b_stored_procedure_audit_details 0, @procedure_name, @note, NULL, @event_id_out = @event_id OUT

		declare @id_b2b_plan int
			 ,@year_to_date int
			 ,@plan_year int
			 ,@period_type nvarchar(10)
			 ,@accelerated int

		drop table if exists #targets
		create table #targets
			(period_name nvarchar(10),
			target_value decimal(18,2))


		select 
			@id_b2b_plan	= pd.id_b2b_plan,
			@year_to_date	= pd.year_to_date,
			@plan_year		= pd.year,
			@period_type	= per.period_type,
			@accelerated	= pd.accelerated
		from _tb_b2b_payment_dates pd
		join _vw_b2b_ref_periods per
			on per.id = pd.period
		where pd.id = @id_payment_dates

		drop table if exists #payment_dates
		select 
			pd2.id,
			pd2.period_name
		into #payment_dates
		from _tb_b2b_payment_dates pd1
		join _vw_b2b_ref_periods per1
			on pd1.period = per1.id
			and pd1.id = @id_payment_dates
		join _vw_b2b_ref_periods per2
			on per1.period_type = per2.period_type
		join _tb_b2b_payment_dates pd2
			on pd2.period = per2.id
			and pd1.id_b2b_plan = pd2.id_b2b_plan
			and pd1.year_to_date = pd2.year_to_date
		join _tb_b2b_plan_definition def
			on def.id_b2b_plan = pd1.id_b2b_plan
			and def.metric_code = @metric_code

		if(@year_to_date = 0 and @period_type <> 'Y') 
		-- if we show results for not PTD, we need to check it directly in _tb_b2b_target_assignment_details as future periods may not be calculated yet
		-- year calculations also have targets already summed

		begin
			drop table if exists #targets_unpivoted
			select  
				sum(coalesce(m01,0) + coalesce(m02,0) + coalesce(m03,0))	as Q1,
				sum(coalesce(m04,0) + coalesce(m05,0) + coalesce(m06,0))	as Q2,
				sum(coalesce(m07,0) + coalesce(m08,0) + coalesce(m09,0))	as Q3,
				sum(coalesce(m10,0) + coalesce(m11,0) + coalesce(m12,0))	as Q4
			into #targets_unpivoted -- select *
			from [dbo].[_tb_b2b_target_assignment_details] tad
			cross apply (
				select	distinct epa.sales_person_id
				from	_tb_b2b_employee_plan_assignment (nolock) epa
				where	epa.id_b2b_plan = @id_b2b_plan
				and		epa.person_id = @person_id
			) epa
			where	tad.year = @plan_year
			and		tad.metric_code = @metric_code
			and		tad.sales_person_id = epa.sales_person_id;


			INSERT INTO #targets 
				(period_name,
				target_value)
			SELECT 
				period_name,
				target_value
			FROM 
				(SELECT Q1, Q2, Q3, Q4 FROM #targets_unpivoted) AS source_table
			UNPIVOT
				(target_value FOR period_name IN (Q1, Q2, Q3, Q4)) AS unpivoted_table;

			IF (@period_type = 'H')
				BEGIN 
					drop table if exists #targets_period
					SELECT 
						CASE 
							WHEN period_name IN ('Q1', 'Q2') THEN 'H1'
							WHEN period_name IN ('Q3', 'Q4') THEN 'H2'
						END AS period_name,
						SUM(target_value) AS target_value
					INTO #targets_period
					FROM #targets
					GROUP BY
						CASE 
							WHEN period_name IN ('Q1', 'Q2') THEN 'H1'
							WHEN period_name IN ('Q3', 'Q4') THEN 'H2'
						END
					ORDER BY period_name;

										INSERT INTO #targets
						(period_name,
						target_value)
					SELECT 
						period_name,
						target_value
					FROM #targets_period
					DELETE FROM #targets WHERE period_name not in ('H1','H2')
				END


		end

			select 
				pd.period_name,
				ta.target_value,
				ta.actuals_value,
				cr.achievement_factorized_boostered / 100. as achievement_factorized_boostered,
				IIF(@accelerated = 1, cr.achievement_final, null) / 100. as achievement_accelerated,
				@accelerated as accelerated_flag
			from #payment_dates pd
			left join #targets t
				on pd.period_name = t.period_name
			left join _tb_b2b_calc_result_metric cr -- select * from _tb_b2b_calc_result_metric
				on cr.id_payment_dates = pd.id
				and cr.person_id = @person_id 
				and cr.metric_code = @metric_code
			cross apply (
			select [target_value] = NULLIF(COALESCE(cr.target_value, t.target_value),0)
				,[actuals_value] = NULLIF(cr.result_factorized_boostered_value,0)
				) ta
			order by pd.period_name asc

		----------------------------------------------------------------------------------------------------------------------------------
		-- Execution log: END
		----------------------------------------------------------------------------------------------------------------------------------

		EXEC dbo._sp_b2b_stored_procedure_audit_details 1, @procedure_name, @note, @event_id, @event_id_out = @event_id OUT

end;
