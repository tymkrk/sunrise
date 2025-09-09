
IF NOT EXISTS (SELECT TOP 1 1 FROM _tb_one_time_scripts_release_log WHERE script_name = '62_2_eng_341_add_info_fields_utilities_fix')


	begin
	begin tran
		declare @now datetime = getutcdate()
		declare @plan_id int = (select top 1 id_plan from k_m_plans where name_plan like '%Bonus Utilities') -- select * from k_m_plans
		declare @template_id int = 
			(select top 1 id_base_grid from k_m_type_plan where id_type_plan =
				(select top 1 id_type_plan from k_m_plans where id_plan = @plan_id))
		declare @indicator_name nvarchar(100) = 'GF_BUT_Yearly_Campaign_BUT_Total_Comp' 
		declare @id_ind int = (select top 1 id_ind from k_m_indicators where name_ind = @indicator_name)
		declare @field_name_ec nvarchar(100) = 'GF_BUT_Total_Comp'
		declare @field_name_eur nvarchar(100) = 'GF_BUT_Total_Comp_EUR'

		declare @sort int = 		(select sort_plan_ind from k_m_plans_indicators 
		where id_plan = @plan_id
			and id_ind = @id_ind)

			--select @sort
			update k_m_plans_indicators set sort_plan_ind = sort_plan_ind + 2 where sort_plan_ind > @sort and id_plan = @plan_id
			update k_m_plans_informations set sort = sort + 2 where sort > @sort and id_plan = @plan_id

		insert into k_m_fields
		(name_field,label_field,code_field,width,id_unit,id_field_type,id_control_type,type_value,is_olap,date_create_field,show_min,show_max,thousand_separator,id_access_type,is_percentage_used,show_aggregated_result,threshold_min_value,threshold_max_value,is_threshold_enabled,show_only_aggregated_result ,aggregation_type)
		select
			'Final Proposed Total Comp in employee Currency','Final Proposed Total Comp in employee Currency',@field_name_ec,240,-3,-1,-2,2,0,@now,1,1,1,-1,0,0,0,0,0,0,1
		union
		select
			'Final Proposed Total Comp in EUR','Final Proposed Total Comp in EUR',@field_name_eur,240,-3,-1,-2,2,0,@now,1,1,1,-1,0,0,0,0,0,0,1

		declare @id_ind_field_1 int = (select top 1 id_field from k_m_fields where code_field = @field_name_ec)
		declare @id_ind_field_2 int = (select top 1 id_field from k_m_fields where code_field = @field_name_eur)

		insert into k_m_indicators_fields (id_ind, id_field, sort)
			select @id_ind, @id_ind_field_1, 2 union
			select @id_ind, @id_ind_field_2, 3 


		
		insert into k_m_plan_display_field 
			(id_plan_display
			,id_indicator_field
			,available_plan_display_field
			,show_plan_display_field
			,optional_show_plan_display_field
			)
		select 
			pd.id_plan_display
			,fi.id_indicator_field
			,1,1,1
		from k_m_plan_display pd 
		join k_profiles pr
			on pr.id_profile = pd.id_profile
			and pd.id_plan = @plan_id
			and pr.name_profile in 
			(
			'GV_Administrator'
			,'ExCom'
			,'HR department'
			,'CompBen team'
			,'Reward Manager'
			,'Reward Reviewer'
			,'Head of the HRBP'
			,'CEO'
			,'Co Reward Manager'
			) 
		join k_m_indicators_fields fi -- select * from k_m_fields
			on fi.id_field in (@id_ind_field_1, @id_ind_field_2)

	--ind order
	declare @ind_sort int = (select min(pi.sort_plan_ind) from k_m_plans_indicators pi
	join k_m_indicators i
		on pi.id_ind = i.id_ind
	join k_m_plans p
		on p.id_plan = pi.id_plan
	where p.name_plan like '%Bonus Utilities'
		and i.name_ind in ('GF_BUT_Yearly_Campaign_BUT_PerformanceShares','GF_BUT_Yearly_Campaign_BUT_Total_Comp'))


	UPDATE pin
	set sort_plan_ind = @ind_sort
	from k_m_plans_indicators pin
	join k_m_indicators i
		on pin.id_ind = i.id_ind
	join k_m_plans p
		on p.id_plan = pin.id_plan
	where p.name_plan like '%Bonus Utilities'
		and i.name_ind in ('GF_BUT_Yearly_Campaign_BUT_Total_Comp')

	UPDATE pin
	set pin.sort_plan_ind = @ind_sort + 4
	from k_m_plans_indicators pin
	join k_m_indicators i
		on pin.id_ind = i.id_ind
	join k_m_plans p
		on p.id_plan = pin.id_plan
	where p.name_plan like '%Bonus Utilities'
		and i.name_ind in ('GF_BUT_Yearly_Campaign_BUT_PerformanceShares')



	commit
	--	rollback

		insert into _tb_one_time_scripts_release_log (script_name, applied_on)
		VALUES ('62_1_eng_341_add_info_fields_utilities_fix',GETUTCDATE());

	end

go
