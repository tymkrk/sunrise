CREATE procedure [dbo].[_sp_b2b_calc_get_result_details_snapshot]
	@datasource_type			varchar(100)
,	@date_start					datetime
,	@date_end					datetime
,	@result_mode				int				/* 0: minimal, 1: minimal + IDs */
,	@target_code_rev_mapping	varchar(100)
,	@plan_id					int
,	@enable_rev_mapping			bit				= 1
,	@payment_date				date
,	@period						int	
as
begin 	


	declare		@team_type_filter							varchar(100)
			,	@plan_year									int
			,	@segment_code_on_plan						nvarchar(50)
			,	@renewal_name								nvarchar(100)	= 'Renewal'
			,	@id_snapshot_rev_revenue_arch				int
			,	@id_snapshot_sf_companies_arch				int
			,	@id_snapshot_sf_opportunities_arch			int
			,	@id_snapshot_sf_opportunities_products_arch	int
			,	@id_snapshot_sf_products_arch				int
			,	@id_snapshot_eof_sbp_arch					int
			,	@eof_type									nvarchar(100)	= 'EoF'
			,	@sbp_type									nvarchar(100)	= 'SBP'
			,	@rev_mapping_result_factor					decimal(18, 2);

	set @team_type_filter = 'TRANSACTION_' + @datasource_type;
	select @id_snapshot_rev_revenue_arch				= 	id	from _tb_b2b_quarter_snapshot_log where payment_date = @payment_date and table_name = '_tb_b2b_rev_revenue_arch'
	select @id_snapshot_sf_companies_arch				= 	id	from _tb_b2b_quarter_snapshot_log where payment_date = @payment_date and table_name = '_tb_b2b_sf_companies_arch'
	select @id_snapshot_sf_opportunities_arch			= 	id	from _tb_b2b_quarter_snapshot_log where payment_date = @payment_date and table_name = '_tb_b2b_sf_opportunities_arch'
	select @id_snapshot_sf_opportunities_products_arch	= 	id	from _tb_b2b_quarter_snapshot_log where payment_date = @payment_date and table_name = '_tb_b2b_sf_opportunities_products_arch'
	select @id_snapshot_sf_products_arch				= 	id	from _tb_b2b_quarter_snapshot_log where payment_date = @payment_date and table_name = '_tb_b2b_sf_products_arch'
	select @id_snapshot_eof_sbp_arch					= 	id	from _tb_b2b_quarter_snapshot_log where payment_date = @payment_date and table_name = '_tb_b2b_eof_sbp_arch'
	
	select @plan_year				= year			from _tb_b2b_payment_dates	where id_b2b_plan = @plan_id
	select @segment_code_on_plan	= segment_code	from _tb_b2b_plan			where id = @plan_id
											
	select	distinct
					pd.metric_code
				,	td.MRC
				,	td.OTC
				,	td.GP
				,	td.service_type
				,	td.include_mrc_in_product_groups
				,	td.exclude_product_groups
				,	pd.id_b2b_plan
				,	td.value_type
				,	td.include_renewal_selected
				,	td.include_eof_sbp
				,	p.include_eof_data
				,	p.include_sbp_data
				,	isnull(pd.eof_factor_bmm, 1) as eof_factor_bmm
				,	isnull(pd.eof_factor_ent, 1) as eof_factor_ent
				,	td.REV_mapping
				,	isnull(td.REV_mapping_result_factor, 1.) as REV_mapping_result_factor
	into	#plan_definition_local
	from	_tb_b2b_plan_definition (nolock) pd 
	join _tb_b2b_plan p
            on p.id = pd.id_b2b_plan
    left join _tb_b2b_targets_definition td
            on pd.metric_code = td.target_code
            and p.year = td.year
    where	pd.id_b2b_plan = @plan_id;		
						
	/* Assumption : only one target can be mapped to REV */
	set @rev_mapping_result_factor = isnull((
		select	REV_mapping_result_factor
		from	#plan_definition_local
		where	REV_mapping = 1), 1.);

	/* Sales Force ============================================================ */
	if(@datasource_type = 'SF')
	begin		
		/* _tb_b2b_sf_opportunities ---------------------------------- */
		select			person_id						= team_data.person_id
					,	metric_code						= team_data.metric_code
					,	segment_code					= team_data.segment_code
					,	date_eop						= team_data.[date]
					,	sop.nov_mrc
					,	sop.nov_otc
					,	sop.ov_mrc
					,	sop.ov_otc
					,	sop.nov_gp
					,	sop.service_type_group
					,	sop.duration_month
					,	sop.renewal_flag
					,	sop.focus_factor
					,	b.booster
					,	sop.product_group
					,	team_name
					,	manual_adjustment				= 0					
					,	eof_sbp_flag					= 0
					,	eof_sbp_type					= cast(null as varchar(100))
					/*	IDs ------------------------------------------ */
					,	id_sf_opportunities				= so.id
					,	id_sf_opportunities_products	= sop.id
					,	id_sf_companies					= company_data.id
					,	id_sf_products					= sp.id
					,	id_manual_adjustments			= cast(null as int)
					,	id_eof_sbp						= cast(null as int)
					/*	Basic attributes ----------------------------- */
					,	so.closed_date
					,	so.is_closed
					,	so.is_deleted
					,	company_name					= company_data.company_name
					,	a_number						= company_data.a_number
					,	team_data.team
					,	team_data.unit
					,	team_data.level_1
					,	team_data.level_2
					,	team_data.level_3
					,	team_data.level_4
		into		#result_details_sf_proxy
		from		_tb_b2b_sf_opportunities_arch (nolock) so
		join		_tb_b2b_sf_opportunities_products_arch (nolock) sop 
			on		sop.opp_object_cd = so.object_cd
		cross apply (
			select		person_id
					,	team_name
					,	segment_code
					,	metric_code
					,	[date]
					,	team
					,	unit
					,	level_1
					,	level_2
					,	level_3
					,	level_4
			from	#team_data td
			where	(type is null or type = @team_type_filter)
			and		td.id_filter_type = 'SF_TABLE'
			and		td.id_filter = so.id
		) team_data	
		outer apply (
			select		top 1 
						sc.id
					,	sc.company_name
					,	sc.a_number
			from	_tb_b2b_sf_companies_arch (nolock) sc
			where	sc.object_cd = so.company_object_cd
			and		sc.start_date <= so.closed_date
			and		sc.end_date >= so.closed_date
			and		sc.id_snpshot = @id_snapshot_sf_companies_arch
		) company_data
		left join	_tb_b2b_sf_products_arch (nolock) sp
			on		sp.object_cd = sop.product_object_cd
			and		sp.id_snpshot = @id_snapshot_sf_products_arch
		left join	_tb_b2b_booster b
			on b.id_b2b_plan = @plan_id
			and b.id_month = MONTH(so.closed_date)
		where	sop.is_deleted = 0
		and		sop.service_type_group is not null
		and		so.id_snpshot = @id_snapshot_sf_opportunities_arch
		and		sop.id_snpshot = @id_snapshot_sf_opportunities_products_arch
		

		/* _tb_b2b_manual_adjustments -------------------------------- */
		union all
		select			person_id						= team_data.person_id
					,	metric_code						= team_data.metric_code
					,	segment_code					= team_data.segment_code
					,	date_eop						= team_data.[date]
					,	mac.NOV_MRC
					,	mac.NOV_OTC
					,	mac.OV_MRC
					,	mac.OV_OTC
					,	mac.NOV_GP
					,	service_type_group				= stm.service_type_group
					,	mac.duration_month
					,	renewal_flag					= mac.renewal_flag
					,	focus_factor					= mac.focus_factor
					,	b.booster
					,	product_group					= mac.product_group
					,	team_name						= team_data.team_name
					,	manual_adjustment				= 1
					,	eof_sbp_flag					= 0
					,	eof_sbp_type					= cast(null as varchar(100))
					/*	IDs ------------------------------------------ */
					,	id_sf_opportunities				= null
					,	id_sf_opportunities_products	= null
					,	id_sf_companies					= null
					,	id_sf_products					= null
					,	id_manual_adjustments			= mac.id
					,	id_eof_sbp						= null
					/*	Basic attributes ----------------------------- */
					,	closed_date						= mac.closed_date
					,	is_closed						= null
					,	is_deleted						= null
					,	company_name					= mac.company_name
					,	a_number						= mac.a_number
					,	team_data.team
					,	team_data.unit
					,	team_data.level_1
					,	team_data.level_2
					,	team_data.level_3
					,	team_data.level_4
		from		_vw_b2b_manual_adjustments_cov (nolock) mac				
		cross apply (
			select		person_id
					,	team_name
					,	segment_code
					,	metric_code
					,	[date]
					,	team
					,	unit
					,	level_1
					,	level_2
					,	level_3
					,	level_4
			from	#team_data td
			where	(type is null or type = @team_type_filter)
			and		td.id_filter_type = 'SF_MA'
			and		td.id_filter = mac.id
		) team_data	
		left join	_tb_b2b_service_type_mapping (nolock) stm 
			on		isnull(stm.service_type,'') = isnull(mac.service_type,'')
			and		stm.year = year(mac.closed_date)
		left join	_tb_b2b_booster b
			on b.id_b2b_plan = @plan_id
			and b.id_month = MONTH(mac.closed_date)

			/* _tb_b2b_eof_sbp ------------------------------------------- */
		union all
		select			person_id						= team_data.person_id
					,	metric_code						= team_data.metric_code
					,	segment_code					= team_data.segment_code
					,	date_eop						= team_data.[date]
					,	nov_mrc							= es.new_order_value
					,	nov_otc							= null
					,	ov_mrc							= null
					,	ov_otc							= null
					,	nov_gp							= NOV_GP
					,	service_type_group				= 'New Business'
					,	es.contract_duration_month
					,	renewal_flag					= 0
					,	focus_factor					= null
					,	b.booster
					,	product_group					= es.benchmark_group
					,	team_name						= team_data.team_name
					,	manual_adjustment				= 0
					,	eof_sbp_flag					= 1
					,	eof_sbp_type					= iif(es.profit_center_name = 'EOF' and isnull(es.order_entry_system_name, '') <> 'ESBA', @eof_type, @sbp_type)
					/*	IDs ------------------------------------------ */
					,	id_sf_opportunities				= null
					,	id_sf_opportunities_products	= null
					,	id_sf_companies					= null
					,	id_sf_products					= null
					,	id_manual_adjustments			= null
					,	id_eof_sbp						= es.id
					/*	Basic attributes ----------------------------- */
					,	closed_date						= es.activation_date
					,	is_closed						= 1
					,	is_deleted						= 0
					,	company_name					= es.sf_company_name
					,	a_number						= es.a_number	
					,	team_data.team
					,	team_data.unit
					,	team_data.level_1
					,	team_data.level_2
					,	team_data.level_3
					,	team_data.level_4

		from		_tb_b2b_eof_sbp_arch (nolock) es		
		cross apply (
			select		person_id
					,	team_name
					,	segment_code
					,	metric_code
					,	[date]
					,	team
					,	unit
					,	level_1
					,	level_2
					,	level_3
					,	level_4
			from	#team_data td
			where	(type is null or type = @team_type_filter)
			and		td.id_filter_type = 'SBP_TABLE'
			and		td.id_filter = es.id
		) team_data			
		left join	_tb_b2b_booster b
			on b.id_b2b_plan = @plan_id
			and b.id_month = MONTH(es.activation_date)
		where	es.id_snapshot = @id_snapshot_eof_sbp_arch;


		/* factorized result manual adjustment  ---------------------------------- */
		select			person_id						= team_data.person_id
					,	metric_code						= team_data.metric_code
					,	segment_code					= team_data.segment_code
					,	date_eop						= team_data.[date]
					,	result_value_individual			= 0
					,	factorized_result_delta			= mac.factorized_result_adjustment
					,	boostered_result_delta			= 0
					,	service_type_group				= stm.service_type_group
					,	renewal_flag					= mac.renewal_flag
					,	focus_factor					= 1
					,	booster							= 1
					,	product_group					= mac.product_group
					,	team_name						= team_data.team_name
					,	manual_adjustment				= 1
					,	eof_sbp_flag					= 0
					,	eof_sbp_type					= cast(null as varchar(100))
					/*	IDs ------------------------------------------ */
					,	id_sf_opportunities				= null
					,	id_sf_opportunities_products	= null
					,	id_sf_companies					= null
					,	id_sf_products					= null
					,	id_manual_adjustments			= mac.id
					,	id_eof_sbp						= null
					/*	Basic attributes ----------------------------- */
					,	closed_date						= mac.closed_date
					,	is_closed						= null
					,	is_deleted						= null
					,	company_name					= mac.company_name
					,	a_number						= mac.a_number
		into		#result_details_sf_factorized_adjustment
		from		_vw_b2b_manual_adjustments_cov (nolock) mac	
		left join	_tb_b2b_service_type_mapping (nolock) stm 
			on		isnull(stm.service_type,'') = isnull(mac.service_type,'')
			and		stm.year = year(mac.closed_date)
		outer apply (
			select	top 1 product_group_flag	= 1
			from	_tb_b2b_product_groups_selection (nolock) pgs
			where	pgs.year = year(mac.closed_date)
			and		pgs.product_group = mac.product_group
		) pgf
		join #plan_definition_local pdl
			on 1=1 -- pdl.metric_code = team_data.metric_code
			and ((stm.service_type_group = pdl.service_type and pdl.service_type = 'Renewal' and mac.renewal_flag = 1) -- t2
			or (pgf.product_group_flag = 1 and pdl.include_mrc_in_product_groups = 1) -- 3
			or ((mac.renewal_flag <> 1 or stm.service_type_group = 'New Business') and isnull(pgf.product_group_flag,0) <> 1 and pdl.service_type = 'New Business')
			)
		cross apply (
			select		person_id
					,	team_name
					,	segment_code
					,	metric_code
					,	[date]
			from	#team_data td
			where	(type is null or type = 'TRANSACTION_SF')
			and		td.id_filter_type = 'SF_MA'
			and		td.id_filter = mac.id
			and		td.metric_code = pdl.metric_code
		) team_data	
		where isnull(mac.factorized_result_adjustment,0) <> 0


		/* calculation logic for SF ---------------------------------- */
		select		rd.person_id						
				,	rd.metric_code						
				,	rd.segment_code	
				,	rd.date_eop				
				,	result_value_individual			= t42.result_value_bmm_ent
				,	factorized_result_delta			= (isnull(t51.result_value_factorized, 0) - isnull(t42.result_value_bmm_ent, 0))
				,	boostered_result_delta			= isnull(t61.result_value_boostered, 0) - isnull(t42.result_value_bmm_ent, 0)
				,	rd.service_type_group				
				,	rd.renewal_flag					
				,	focus_factor					= focus_factor_adj
				,	booster							= booster_adj
				,	rd.product_group					
				,	rd.team_name						
				,	rd.manual_adjustment
				,	rd.eof_sbp_flag
				,	rd.eof_sbp_type
				/*	IDs ----------------------------*/
				,	rd.id_sf_opportunities				
				,	rd.id_sf_opportunities_products	
				,	rd.id_sf_companies					
				,	rd.id_sf_products					
				,	rd.id_manual_adjustments	
				,	rd.id_eof_sbp
				/*	Basic attributes ---------------*/
				,	rd.closed_date						
				,	rd.is_closed						
				,	rd.is_deleted						
				,	rd.company_name					
				,	rd.a_number
		into	#result_details_sf_proxy_calculated
		from	#result_details_sf_proxy rd
		left join _tb_b2b_focus_factor_exceptions ff
			on (ff.team		= rd.team		or ff.team is null)
			and (ff.unit	= rd.unit		or ff.unit is null)
			and (ff.level_1 = rd.level_1	or ff.level_1 is null)
			and (ff.level_2 = rd.level_2	or ff.level_2 is null)
			and (ff.level_3 = rd.level_3	or ff.level_3 is null)
			and (ff.level_4 = rd.level_4	or ff.level_4 is null)
			and ff.year = @plan_year
			and ff.period = @period
		join	#plan_definition_local pdl
			on	pdl.metric_code = rd.metric_code
		outer apply (
			select	top 1 multiplier
			from	_tb_b2b_multiplier
			where	year = year(rd.closed_date)
			and		duration_min <= rd.duration_month
			and		duration_max >= rd.duration_month
			and		segment_code = isnull(@segment_code_on_plan, rd.segment_code)
		) t10
		outer apply (
			select	top 1 product_group_flag	= 1
			from	_tb_b2b_product_groups_selection (nolock) pgs
			where	pgs.year = year(rd.closed_date)
			and		pgs.product_group = rd.product_group
		) t20
		outer apply (
			select	result_value_basic = case
						when pdl.value_type = 'NOV' and MRC = 1 then nov_mrc
						when pdl.value_type = 'NOV' and OTC = 1 then nov_otc
						when pdl.value_type = 'OV' and MRC = 1 then ov_mrc
						when pdl.value_type = 'OV' and OTC = 1 then ov_otc
						when GP = 1 then nov_gp
						end
		) t30
		outer apply (
			select	result_value = result_value_basic +
						iif(isnull(pdl.include_mrc_in_product_groups, 0) = 0, 0,
						iif(isnull(t20.product_group_flag, 0) = 0, 0,
						case
							when value_type = 'NOV' then nov_mrc
							when value_type = 'OV' then ov_mrc end))
		) t40
		outer apply (
			select eof_factor_bmm_ent = case when rd.eof_sbp_flag = 1 and rd.eof_sbp_type = @eof_type
										then case
												when  isnull(@segment_code_on_plan, rd.segment_code) = 'bmm' THEN pdl.eof_factor_bmm 
												when  isnull(@segment_code_on_plan, rd.segment_code) = 'ent' THEN pdl.eof_factor_ent
											 else 1 
											 end
										else 1
										end
		) t41
		outer apply (
			select result_value_bmm_ent = t40.result_value * t41.eof_factor_bmm_ent
		) t42
		outer apply (
			select	focus_factor_adj	= isnull(iif(rd.focus_factor < 1 or ff.id is not null, 1, rd.focus_factor), 1)
		) t50
		outer apply (
			select	result_value_factorized	= t42.result_value_bmm_ent * focus_factor_adj * isnull(t10.multiplier, 1)
		) t51
		outer apply (
			select COALESCE(rd.booster,1)  as booster_adj
		) t60
		outer apply (
			select	result_value_boostered	= t42.result_value_bmm_ent * t60.booster_adj
		) t61


		where	(pdl.exclude_product_groups = 0 or isnull(t20.product_group_flag, 0) = 0)
		and		rd.service_type_group		= iif(pdl.service_type = 'Both' or pdl.include_renewal_selected = 1, rd.service_type_group, pdl.service_type)
		and		isnull(rd.renewal_flag, 0)	= case
												when pdl.service_type = 'Renewal'											then 1
												when rd.service_type_group = 'Renewal' and pdl.include_renewal_selected = 1 then 0
												else isnull(rd.renewal_flag, 0) end
		and		(rd.eof_sbp_type is null 
			or	(pdl.include_eof_sbp = 1 and rd.eof_sbp_type = @eof_type and pdl.include_eof_data = 1)
			or	(pdl.include_eof_sbp = 1 and rd.eof_sbp_type = @sbp_type and pdl.include_sbp_data = 1))
		union ALL
		select 
			fa.person_id						
				,	fa.metric_code						
				,	fa.segment_code		
				,	fa.date_eop				
				,	fa.result_value_individual			
				,	fa.factorized_result_delta	
				,	fa.boostered_result_delta
				,	fa.service_type_group			
				,	fa.renewal_flag					
				,	fa.focus_factor				
				,	fa.booster
				,	fa.product_group				
				,	fa.team_name					
				,	fa.manual_adjustment			
				,	fa.eof_sbp_flag					
				,	fa.eof_sbp_type
				/*	IDs ----------------------------*/
				,	fa.id_sf_opportunities				
				,	fa.id_sf_opportunities_products	
				,	fa.id_sf_companies					
				,	fa.id_sf_products					
				,	fa.id_manual_adjustments	
				,	fa.id_eof_sbp
				/*	Basic attributes ---------------*/
				,	fa.closed_date						
				,	fa.is_closed						
				,	fa.is_deleted						
				,	fa.company_name					
				,	fa.a_number
		from #result_details_sf_factorized_adjustment fa;


		/* Result ---------------------------------------------------- */
		if(@result_mode = 1)
		begin
			insert into #result_details_sf
			select	*
			from	#result_details_sf_proxy_calculated
			where	isnull(result_value_individual , 0) <> 0
				or isnull(factorized_result_delta , 0) <> 0
		end;
	end;	

	/* Revenue =========================================================================== */
	if(@datasource_type = 'REV')
	begin
		/* _tb_b2b_rev_revenue --------------------------------------- */
		select		person_id				= team_data.person_id
				,	metric_code				= iif(rev_mapping = 1, @target_code_rev_mapping, team_data.metric_code)
				,	segment_code			= team_data.segment_code
				,	date_eop				= team_data.[date]
				,	result_value			= iif(rev_mapping = 1, (rev_net_amt_chf * @rev_mapping_result_factor), rev_net_amt_chf)
				,	b.booster
				,	team_name
				,	manual_adjustment		= 0
				/*	IDs ------------------------------------------ */
				,	id_rev_revenue			= rr.id
				,	id_manual_adjustments	= cast(null as int)
				/*	Basic attributes ----------------------------- */
				,	rr.start_date
				,	rr.end_date
				,	close_date				= cast(null as datetime)
				,	company_name			= rr.sf_company_name
				,	a_number				= rr.a_number_taifun_id
				,	rr.group_eof
				,	rr.product_grouping
				,	rr.report_grouping
				,	rr.sales_person_id  
		into	#result_details_rev_proxy
		from	_tb_b2b_rev_revenue_arch (nolock) rr		
		cross apply (
			select	rev_mapping = iif(rr.prod_lvl_3 in ('Hardware', 'WS Hardware'), 1, 0)
		) t10
		cross apply (
			select		person_id
					,	team_name
					,	segment_code
					,	metric_code
					,	[date]
			from	#team_data td
			where	(type is null or type = @team_type_filter)
			and		td.metric_code = iif(rev_mapping = 1, @target_code_rev_mapping, td.metric_code)
			and		(rev_mapping = 0 or @enable_rev_mapping = 1)
			and		td.id_filter_type = 'REV_TABLE'
			and		td.id_filter = rr.id
			and		(@segment_code_on_plan is not null or td.segment_code = 'ent' or t10.rev_mapping = 0)
		) team_data
		left join	_tb_b2b_booster b
			on b.id_b2b_plan = @plan_id
			and b.id_month = MONTH(rr.start_date)
			and rev_mapping = 1
		where (t10.rev_mapping = 0 or ISNULL(rr.profit_center_name,'')  not in ('EoF', 'Medinex'))
			and rr.id_snpshot = @id_snapshot_rev_revenue_arch
			and COALESCE(rr.flag_is_rev_in,1) = 1

		
		/* _tb_b2b_manual_adjustments -------------------------------- */
		union all
		select			person_id				= team_data.person_id
					,	metric_code				= team_data.metric_code
					,	segment_code			= team_data.segment_code
					,	date_eop				= team_data.[date]
					,	result_value			= mar.rev_net_amt_chf
					,	booster					= null
					,	team_name
					,	manual_adjustment		= 1
					/*	IDs ------------------------------------------ */
					,	id_rev_revenue			= null
					,	id_manual_adjustments	= mar.id
					/*	Basic attributes ----------------------------- */
					,	start_date				= mar.start_date
					,	end_date				= mar.end_date
					,	close_date				= null
					,	company_name			= mar.sf_company_name
					,	a_number				= mar.a_number_taifun_id
					,	eof.is_eof
					,	pgm.product_grouping
					,	rgm.report_grouping
					,	sales_person_id			= mar.sales_person_id_prefix
		from		_tb_b2b_manual_adjustments_rev (nolock) mar					
		cross apply (
			select		person_id
					,	team_name
					,	segment_code
					,	metric_code
					,	[date]
			from	#team_data td
			where	(type is null or type = @team_type_filter)
			and		td.id_filter_type = 'REV_MA'
			and		td.id_filter = mar.id
		) team_data
		outer apply (
			select iif(mar.profit_center_name = 'eof',1,0) as is_eof 
			) eof
		left join _tb_b2b_product_grouping_mapping pgm
			on pgm.prod_lvl_1 = mar.prod_lvl_1
			and pgm.year = YEAR(mar.start_date)
			and pgm.year = YEAR(mar.end_date)
		left join _vw_b2b_report_grouping_mapping rgm
			on rgm.is_eof = eof.is_eof
			and (rgm.product_grouping is null 
				or rgm.product_grouping  = pgm.product_grouping)

		/* Result ---------------------------------------------------- */
		if(@result_mode = 1)
		begin			

			select	
					*  
			from	#result_details_rev_proxy;
		end;
	end;		
end;
