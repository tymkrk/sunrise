
IF NOT EXISTS (SELECT TOP 1 1 FROM _tb_one_time_scripts_release_log WHERE script_name = '59_1_eng_341_add_info_fields_capped')

	begin
		-- select * from k_m_plans
		declare @plan_id int = (select top 1 id_plan from k_m_plans where name_plan like '%Bonus Capped')
		declare @template_id int = 
			(select top 1 id_base_grid from k_m_type_plan where id_type_plan =
				(select top 1 id_type_plan from k_m_plans where id_plan = @plan_id))
		declare @template_name nvarchar(100) = 
			(select top 1 name_grid from k_referential_grids where id_grid = @template_id)
		declare @table_name nvarchar(100) = 
			(select top 1 tv.name_table_view 
			from k_referential_grids g
			join k_referential_tables_views tv
				on g.id_table_view = tv.id_table_view
			where g.id_grid = @template_id)
		declare @info_field_after_name_1 nvarchar(100) = 'GF_BC_Previous_total_bonus_N1' -- info field, after which new columns 1 is added
		declare @info_field_after_name_2 nvarchar(100) = 'GF_BC_Previous_total_bonus_N2' -- info field, after which new columns 2 is added
		declare @table_column_name_1 nvarchar(100) = 'Total_Bonus_Percentage_N1'
			,@table_column_name_2 nvarchar(100) = 'Total_Bonus_Percentage_N2'
			,@info_field_name_1 nvarchar(100) = '% Bonus Y-1'
			,@info_field_name_2 nvarchar(100) = '% Bonus Y-2'



		-- new field 1 have to be added after the field
		declare @new_sort_1 int = 2+
		(select top 1 pi.sort -- select *
		from k_m_plans_informations pi
		join k_referential_grids_fields gf
			on pi.id_field_grid = gf.id_column
			and pi.id_plan =  @plan_id
			and gf.name_column = @info_field_after_name_1
		)

				-- new field 1 have to be added after the field
		declare @new_sort_2 int = 1+
		(select top 1 pi.sort -- select *
		from k_m_plans_informations pi
		join k_referential_grids_fields gf
			on pi.id_field_grid = gf.id_column
			and pi.id_plan =  @plan_id
			and gf.name_column = @info_field_after_name_2
		)

		--select @new_sort_2, @new_sort_1


		exec sp_client_std_synchronize @table_name, 'table', -14;


		if object_id('tempdb..#sync_data') is not null
			drop table #sync_data
	
		select	*
		into	#sync_data
		from	(values
			
		('1', @template_name, @table_column_name_1, @info_field_name_1, '0', '0', '#NULL#', '1', '#NULL#', '#NULL#', '140', '#NULL#', '#NULL#', '#NULL#', '#NULL#', '20', '#NULL#', '#NULL#', '0', '#NULL#', '0', '1', '2', '#NULL#', '0', 'right', '0', '1', '#NULL#', '#NULL#', '#NULL#', '#NULL#', '#NULL#', '#NULL#', '1', '#NULL#', '#NULL#', '0', '0', '0', '0', '#NULL#', '#NULL#')
	, 	('2', @template_name, @table_column_name_2, @info_field_name_2, '0', '0', '#NULL#', '1', '#NULL#', '#NULL#', '140', '#NULL#', '#NULL#', '#NULL#', '#NULL#', '20', '#NULL#', '#NULL#', '0', '#NULL#', '0', '1', '2', '#NULL#', '0', 'right', '0', '1', '#NULL#', '#NULL#', '#NULL#', '#NULL#', '#NULL#', '#NULL#', '1', '#NULL#', '#NULL#', '0', '0', '0', '0', '#NULL#', '#NULL#')
		) s ( rn, ref_name_grid, ref_name_field, name_column, order_column, is_editable, regular_expression, is_sortable, error_message, url, width, combo_datasource_name, combo_datavaluefield_name, combo_datatextfield_name, combo_defaultfield_value, combo_page_size, combo_filtered_column_name, combo_filtered_pattern, combo_allow_custom_text, group_index, is_frozen, thousand_separator, decimal_precision, filter_field, sort_order, column_align, is_flex_used, flex, id_source_tenant, id_source, id_change_set, is_mandatory, defaultfield_value, sort_direction, is_percentage_used, ref_name_combotype, combo_dataparentvaluefield_name, is_bulk_apply_used, enable_row_validation, is_uid_reference, hyperlink_enabled, ref_name_field_display, hyperlink_default_display_text) ;


		exec [dbo].[_sp_sync_process_k_referential_grids_fields_data_merge];

		declare @column_id_y1 int = (select top 1 id_column from k_referential_grids_fields where name_column = @info_field_name_1 and id_grid =  @template_id)
		declare @column_id_y2 int = (select top 1 id_column from k_referential_grids_fields where name_column = @info_field_name_2 and id_grid =  @template_id)

		-- update existing sorts:


		update k_m_plans_informations
			set sort = sort + 1
		where id_plan = @plan_id
			and sort >=@new_sort_2

		update k_m_plans_informations
			set sort = sort + 1
		where id_plan = @plan_id
			and sort >=@new_sort_1

		update k_m_plans_indicators
		set sort_plan_ind = sort_plan_ind + 1
		where id_plan = @plan_id
			and sort_plan_ind >=@new_sort_2

		update k_m_plans_indicators
		set sort_plan_ind = sort_plan_ind + 1
		where id_plan = @plan_id
			and sort_plan_ind >=@new_sort_1

		--insert 2 new info fields

		insert into k_m_plans_informations
			(id_plan
			,id_field_grid
			,width
			,sort
			,is_locked
			,type)
		select @plan_id, @column_id_y1, 120, @new_sort_1, 0,1 union all
		select @plan_id, @column_id_y2, 120, @new_sort_2, 0,1 


		-- update  k_m_plan_display_information

		insert into k_m_plan_display_information 
			(id_plan_display
			,id_plan_information
			,available_plan_display_information
			,show_plan_display_information
			,optional_show_plan_display_information
			)
		select 
			pd.id_plan_display
			,pi.id_planInfo
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
		join k_m_plans_informations pi -- select * from k_m_plans_informations
			on pi.id_field_grid in (@column_id_y1,@column_id_y2)

		insert into _tb_one_time_scripts_release_log (script_name, applied_on)
		VALUES ('59_1_eng_341_add_info_fields_capped',GETUTCDATE());

	end

go
