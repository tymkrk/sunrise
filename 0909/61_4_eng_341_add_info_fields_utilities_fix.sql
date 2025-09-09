
IF NOT EXISTS (SELECT TOP 1 1 FROM _tb_one_time_scripts_release_log WHERE script_name = '61_4_eng_341_add_info_fields_utilities_fix')
 --57_eng_341_add_info_fields_utilities added fields as infor fields. this is wrong. it has to be added as ind fields. this script corrects the problem


	begin
	begin tran
		declare @now datetime = getutcdate()
		declare @plan_id int = (select top 1 id_plan from k_m_plans where name_plan like '%Bonus Utilities') 
		declare @template_id int = 
			(select top 1 id_base_grid from k_m_type_plan where id_type_plan =
				(select top 1 id_type_plan from k_m_plans where id_plan = @plan_id))
		declare @indicator_name nvarchar(100) = 'GF_BUT_Yearly_Campaign_BUT_Total_Comp' -- new indicator

		declare @id_info_field_1 int = 
		(select top 1 pi.id_planInfo 
		from k_m_plans_informations pi
		join k_referential_grids_fields gf
			on pi.id_field_grid = gf.id_column
			and gf.id_grid = @template_id
			and gf.name_column in ('TComp Y-1')
			order by sort asc)

		declare @id_info_field_2 int = 
		(select top 1 pi.id_planInfo 
		from k_m_plans_informations pi
		join k_referential_grids_fields gf
			on pi.id_field_grid = gf.id_column
			and gf.id_grid = @template_id
			and gf.name_column in ('TComp Y-2')
			order by sort asc)

		declare @new_sort int = 
		(select top 1 sort 
		from k_m_plans_informations pi
		where id_planInfo in (@id_info_field_1,@id_info_field_2)
		order by sort asc)


		delete from k_user_plan_field_view where id_plan_information in (@id_info_field_1,@id_info_field_2)
		delete from k_m_plan_display_information where id_plan_information in (@id_info_field_1,@id_info_field_2)
		delete from k_user_plan_field where id_plan_information in (@id_info_field_1,@id_info_field_2)
		delete from k_m_plans_informations where id_planInfo in (@id_info_field_1,@id_info_field_2)
	
		insert k_m_indicators ( name_ind, id_type_ind, is_olap, date_create_ind)
		select @indicator_name, -1, 0, @now

		declare @id_ind int = (select top 1 id_ind from k_m_indicators where name_ind = @indicator_name)

		insert into k_m_fields
		(name_field,label_field,code_field,width,id_unit,id_field_type,id_control_type,type_value,is_olap,date_create_field,show_min,show_max,thousand_separator,decimal_precision,id_access_type,is_percentage_used,show_aggregated_result,threshold_min_value,threshold_max_value,is_threshold_enabled,show_only_aggregated_result ,aggregation_type)
		select
			'Tcomp Y-1 in employee Currency','Tcomp Y-1 in employee Currency','GF_BUT_TComp_N1',240,-3,-1,-2,2,0,@now,1,1,1,0,-1,0,0,0,0,0,0,1
		union
		select
			'Tcomp Y-2 in employee Currency','Tcomp Y-2 in employee Currency','GF_BUT_TComp_N2',240,-3,-1,-2,2,0,@now,1,1,1,0,-1,0,0,0,0,0,0,1

		declare @id_ind_field_1 int = (select top 1 id_field from k_m_fields where code_field = 'GF_BUT_TComp_N1')
		declare @id_ind_field_2 int = (select top 1 id_field from k_m_fields where code_field = 'GF_BUT_TComp_N2')

	
		insert into k_m_indicators_fields
		(id_ind
		,id_field
		,sort)
		select @id_ind, @id_ind_field_2, 0
		union
		select @id_ind, @id_ind_field_1, 1


		
		insert k_m_plans_indicators (id_plan, id_ind, weight_plan_ind, sort_plan_ind, start_date_plan_ind, end_date_plan_ind,is_frozen,color_code)
		select @plan_id, @id_ind, null, @new_sort, '2025-01-01 00:00:00.000', '2026-01-01 00:00:00.000',0, '#ffffff'

		
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
		join k_m_indicators_fields fi -- select * from k_m_indicators_fields
			on fi.id_field in (@id_ind_field_1, @id_ind_field_2)

		insert rps_Localization (tab_id, module_type, name, value, culture, type_source)
		select 101, 14, @indicator_name,'Total Comp','en-US',1

		insert into _tb_one_time_scripts_release_log (script_name, applied_on)
		VALUES ('61_4_eng_341_add_info_fields_utilities_fix',GETUTCDATE());


	commit

	end

go
