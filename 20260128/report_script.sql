
	/* ----------------------------------------------------------------------------- */
	/* REPORT NAME: B2B Achievement - Nov Details 2025                                 */
	/* ----------------------------------------------------------------------------- */

	/* ================================================================================================= */
	/* TABLE NAME:                 k_reports                                                             */
	/* SCRIPT GENERATION TIME:     2026-01-28 07:53:04.                                                  */
	/* USER:					   tymoteusz.kruk@beqom.com                                              */
	/* FILTER 1 - NAME:            @name_report                                                          */
	/* FILTER 1 - VALUE:           B2B Achievement - Nov Details 2025                                    */
	/* ================================================================================================= */

			if object_id('tempdb..#sync_data') is not null
				drop table #sync_data
			go
		
			select	*
			into	#sync_data
			from	(values
			
	('1', '2025', 'B2B Achievement - Nov Details 2025', '#NULL#', 'B2B_Achievements_Nov_Details_2025', '#NULL#', '39', '#NULL#', '#NULL#', '-1', '#NULL#', '#NULL#', '#NULL#', '#NULL#', '#NULL#', '0', '0', '#NULL#', '0', 'SSRS', '0', '0')
	) s ( rn, ref_name_folder, name_report, id_bar, url_report, sort_report, type, visual_type, description, id_owner, id_source_tenant, id_source, id_change_set, configuration_report, id_report_model, is_password_protection_enabled, show_description, description_original, use_translate, ref_name_report_source, show_filter_panel, configuration_report_version) ;


	exec [dbo].[_sp_sync_k_reports_data_merge];

	/* ================================================================================================= */
	/* TABLE NAME:                 k_reports_control                                                     */
	/* SCRIPT GENERATION TIME:     2026-01-28 07:53:04.                                                  */
	/* USER:					   tymoteusz.kruk@beqom.com                                              */
	/* FILTER 1 - NAME:            @name_report                                                          */
	/* FILTER 1 - VALUE:           B2B Achievement - Nov Details 2025                                    */
	/* ================================================================================================= */

			if object_id('tempdb..#sync_data') is not null
				drop table #sync_data
			go
		
			select	*
			into	#sync_data
			from	(values
			
	('1', 'B2B User', 'GV_ComboBox', 'User', '150', '20', 'sp', '_sp_b2b_rep_filter_user', 'name_user', 'id_user', '#NULL#', '0', 'Sep 28 2021 12:17PM', 'Feb 22 2022 12:24PM', '#NULL#', '0', '#NULL#', '1', 'dynamic', 'False', '_sp_b2b_rep_filter_user_default', 'idUser', '#NULL#', '#NULL#', '#NULL#', '1000', '0', '1', 'idUser', 'dynamic', 'userid')
, 	('2', 'B2B Profile', 'GV_ComboBox', 'Profile', '150', '20', 'sp', '_sp_b2b_rep_filter_profile', 'name_profile', 'id_profile', '#NULL#', '0', 'Sep 28 2021 12:17PM', 'Feb 22 2022 12:23PM', '#NULL#', '0', '#NULL#', '1', 'dynamic', 'False', '_sp_b2b_rep_filter_profile_default', 'idProfile', '#NULL#', '#NULL#', '#NULL#', '1000', '0', '1', 'idProfile', 'dynamic', 'profileid')
, 	('3', 'B2B_Employee', 'GV_ComboBox', 'Employee', '200', '20', 'sp', '_sp_b2b_rep_filter_employee', 'full_name', 'person_id', '#NULL#', '0', 'Sep 28 2021 12:17PM', 'Feb 22 2022  1:14PM', '#NULL#', '0', '#NULL#', '0', '#NULL#', '', '', '', '#NULL#', '#NULL#', '#NULL#', '1000', '0', '1', 'IdUserProfile', 'dynamic', 'userprofileid')
, 	('4', 'B2B_Segment', 'GV_ComboBox', 'Segment', '200', '20', 'sp', '_sp_b2b_rep_filter_segment', 'name', 'code', '#NULL#', '0', 'Dec 23 2025  2:42PM', 'Jan  7 2026 11:49AM', '#NULL#', '0', '#NULL#', '0', '#NULL#', 'false', '', '', '#NULL#', '#NULL#', '#NULL#', '1000', '0', '0', '#NULL#', '#NULL#', '#NULL#')
, 	('5', 'B2B_Reported_Plans_2025', 'GV_ComboBox', 'Plan | Period', '200', '20', 'sp', '_sp_b2b_rep_filter_reported_plans', 'label', 'id', '#NULL#', '0', 'Dec 13 2024  1:37PM', '#NULL#', '#NULL#', '0', '#NULL#', '0', '#NULL#', 'false', '', '', '#NULL#', '#NULL#', '#NULL#', '1000', '0', '1', 'IdUserProfile', 'dynamic', 'userprofileid')
, 	('6', 'B2B_Reported_Plans_Periods_2025', 'GV_ComboBox', 'Period', '200', '20', 'sp', '_sp_b2b_rep_filter_reported_plans_periods_2025', 'period_label', 'period_default', '#NULL#', '0', 'Dec 13 2024  1:45PM', 'Feb  4 2025  9:43AM', '#NULL#', '0', '#NULL#', '0', '', '', '', '', '#NULL#', '#NULL#', '#NULL#', '100', '0', '1', 'period_default', 'static', 'period_default')
	) s ( rn, control_name, ref_name_control_type, layout_label, layout_width, layout_height, source_type, source_name, source_display_field, source_value_field, source_parent_display_field, source_multi_select_used, date_creation, date_modification, culture, source_root_included, auto_select, is_default_value, default_value_type, default_elementId, default_SP_name, default_column_name, id_source_tenant, id_source, id_change_set, page_size, allow_empty, source_filter_used, source_filter_field, source_filter_type, source_filter_value) ;


	exec [dbo].[_sp_sync_k_reports_control_data_merge];

	/* ================================================================================================= */
	/* TABLE NAME:                 k_reports_control_link                                                */
	/* SCRIPT GENERATION TIME:     2026-01-28 07:53:04.                                                  */
	/* USER:					   tymoteusz.kruk@beqom.com                                              */
	/* FILTER 1 - NAME:            @name_report                                                          */
	/* FILTER 1 - VALUE:           B2B Achievement - Nov Details 2025                                    */
	/* ================================================================================================= */

			if object_id('tempdb..#sync_data') is not null
				drop table #sync_data
			go
		
			select	*
			into	#sync_data
			from	(values
			
	('1', 'B2B Achievement - Nov Details 2025', 'B2B User', 'IdUser', '#NULL#', '#NULL#', '0', '#NULL#', '#NULL#', '#NULL#', '#NULL#')
, 	('2', 'B2B Achievement - Nov Details 2025', 'B2B Profile', 'IdProfile', '#NULL#', '#NULL#', '1', '#NULL#', '#NULL#', '#NULL#', '#NULL#')
, 	('3', 'B2B Achievement - Nov Details 2025', 'B2B_Employee', 'person_id', '#NULL#', '#NULL#', '2', '#NULL#', '#NULL#', '#NULL#', '#NULL#')
, 	('4', 'B2B Achievement - Nov Details 2025', 'B2B_Segment', 'segment_code', '#NULL#', '#NULL#', '5', '#NULL#', '#NULL#', '#NULL#', '#NULL#')
, 	('5', 'B2B Achievement - Nov Details 2025', 'B2B_Reported_Plans_2025', 'id_payment_dates', '#NULL#', '#NULL#', '4', '#NULL#', '#NULL#', '#NULL#', '#NULL#')
, 	('6', 'B2B Achievement - Nov Details 2025', 'B2B_Reported_Plans_Periods_2025', 'period_label', '#NULL#', '#NULL#', '3', '#NULL#', '#NULL#', '#NULL#', '#NULL#')
	) s ( rn, ref_name_report, ref_name_control, report_filter_name, is_filtered, is_required, sort, goto_line, id_source_tenant, id_source, id_change_set) ;


	exec [dbo].[_sp_sync_k_reports_control_link_data_merge];

	/* ================================================================================================= */
	/* TABLE NAME:                 k_reports_control_relation                                            */
	/* SCRIPT GENERATION TIME:     2026-01-28 07:53:04.                                                  */
	/* USER:					   tymoteusz.kruk@beqom.com                                              */
	/* FILTER 1 - NAME:            @name_report                                                          */
	/* FILTER 1 - VALUE:           B2B Achievement - Nov Details 2025                                    */
	/* ================================================================================================= */

			if object_id('tempdb..#sync_data') is not null
				drop table #sync_data
			go
		
			select	*
			into	#sync_data
			from	(values
			
	('1', 'B2B_Reported_Plans_Periods_2025', 'B2B_Employee', '#NULL#', '@person_id', 'B2B Achievement - Nov Details 2025')
, 	('2', 'B2B_Reported_Plans_2025', 'B2B_Employee', '#NULL#', '@person_id', 'B2B Achievement - Nov Details 2025')
, 	('3', 'B2B_Reported_Plans_2025', 'B2B_Reported_Plans_Periods_2025', '#NULL#', '@period_default', 'B2B Achievement - Nov Details 2025')
	) s ( rn, ref_name_control, ref_name_control_parent, is_required, filter_field, name_report) ;


	exec [dbo].[_sp_sync_k_reports_control_relation_data_merge];

	/* ================================================================================================= */
	/* TABLE NAME:                 k_modules                                                             */
	/* SCRIPT GENERATION TIME:     2026-01-28 07:53:04.                                                  */
	/* USER:					   tymoteusz.kruk@beqom.com                                              */
	/* FILTER 1 - NAME:            @name_report                                                          */
	/* FILTER 1 - VALUE:           B2B Achievement - Nov Details 2025                                    */
	/* ================================================================================================= */

			if object_id('tempdb..#sync_data') is not null
				drop table #sync_data
			go
		
			select	*
			into	#sync_data
			from	(values
			
	('1', 'ND_StandartReports', 'B2B Achievement - Nov Details 2025', '-9', 'B2B Achievement - Nov Details 2025', '0', '#NULL#', '#NULL#', '#NULL#', '1', 'report')
	) s ( rn, ref_parent_name_module, name_module, id_tab, ref_name_object, order_module, id_source_tenant, id_source, id_change_set, show_in_accordion, ref_name_module_type) ;


	exec [dbo].[_sp_sync_k_modules_data_merge];

	/* ================================================================================================= */
	/* TABLE NAME:                 k_modules_rights                                                      */
	/* SCRIPT GENERATION TIME:     2026-01-28 07:53:04.                                                  */
	/* USER:					   tymoteusz.kruk@beqom.com                                              */
	/* FILTER 1 - NAME:            @name_report                                                          */
	/* FILTER 1 - VALUE:           B2B Achievement - Nov Details 2025                                    */
	/* ================================================================================================= */

			if object_id('tempdb..#sync_data') is not null
				drop table #sync_data
			go
		
			select	*
			into	#sync_data
			from	(values
			
	('1', 'B2B Achievement - Nov Details 2025', 'EXC_read', '#NULL#', '#NULL#', '#NULL#', 'report')
	) s ( rn, ref_name_object, ref_name_right, id_source_tenant, id_source, id_change_set, ref_name_module_type) ;


	exec [dbo].[_sp_sync_k_modules_rights_data_merge];

	/* ================================================================================================= */
	/* TABLE NAME:                 k_profiles_modules_rights                                             */
	/* SCRIPT GENERATION TIME:     2026-01-28 07:53:04.                                                  */
	/* USER:					   tymoteusz.kruk@beqom.com                                              */
	/* FILTER 1 - NAME:            @name_report                                                          */
	/* FILTER 1 - VALUE:           B2B Achievement - Nov Details 2025                                    */
	/* ================================================================================================= */

			if object_id('tempdb..#sync_data') is not null
				drop table #sync_data
			go
		
			select	*
			into	#sync_data
			from	(values
			
	('1', 'B2B Admin', 'B2B Achievement - Nov Details 2025', 'EXC_read', '#NULL#', '#NULL#', '#NULL#', '#NULL#', '#NULL#', 'report', 'B2B Achievement - Nov Details 2025')
	) s ( rn, ref_name_profile, ref_name_object, ref_name_right, id_source_tenant, id_source, id_change_set, start_date, end_date, ref_name_module_type, ref_name_module) ;


	exec [dbo].[_sp_sync_k_profiles_modules_rights_data_merge];

	GO

