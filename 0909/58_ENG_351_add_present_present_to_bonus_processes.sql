IF NOT EXISTS(SELECT * FROM _tb_one_time_scripts_release_log WHERE script_name = '58_ENG_351_add_present_present_to_bonus_processes')
BEGIN

			/* SCRIPT FOR ADDING PRESENT - PRESENT COLUMNS */

			/* PREPARE BACKUPS FOR KERNEL TABLES */
			DECLARE @current_date NVARCHAR(30) = (SELECT REPLACE(CAST(Convert(date, getdate()) AS NVARCHAR(30)),'-','_'))
			
			DROP TABLE IF EXISTS #backup_tmp
			;WITH backup_cte AS (
				SELECT 
					tb.table_name
				,	'___' + tb.table_name + '_' + @current_date  as backup_table_name
				FROM (VALUES 
						 ('k_referential_grids_fields')
						,('k_m_plans_informations')
						,('k_m_plans_indicators')
						,('k_m_plan_display_information')
				) AS tb (table_name)
			)
			SELECT 
				table_name
			,	backup_table_name
			,	'if not exists (select * from sys.tables where name =' + ''''+ backup_table_name + '''' + ') 
				 begin
					select * into ' + backup_table_name + ' from ' + table_name + ' 
				 end' AS code_to_exec
			INTO #backup_tmp
			FROM backup_cte
		
			/* CREATE BACKUPS */
			DECLARE 
			    @table_name  NVARCHAR(MAX), 
				@code_to_exec NVARCHAR(MAX)
			
			DECLARE cursor_product CURSOR
			FOR SELECT 
			        table_name
				,	code_to_exec
			    FROM 
			       #backup_tmp;
			
			OPEN cursor_product;
			
			FETCH NEXT FROM cursor_product INTO 
			    @table_name, 
			    @code_to_exec;
			
			WHILE @@FETCH_STATUS = 0
			    BEGIN
					EXEC (@code_to_exec)

			        FETCH NEXT FROM cursor_product INTO 
			            @table_name, 
			            @code_to_exec;
			    END;
			
			CLOSE cursor_product;
			DEALLOCATE cursor_product;

			------------------------------------------------------------------------------------------------------------


			/* SELECT PLANS */
			DROP TABLE IF EXISTS #changed_plans
			SELECT
				kmp.id_plan
			   ,kmp.name_plan
			   ,kmp.id_type_plan 
			   ,trim(substring(name_plan, PATINDEX('%["-]%', name_plan) + 2, len(name_plan))) name_plan_match
			   ,case 
					when kmp.name_plan LIKE '%bonus capped'					then 'GF_BC_PresentPresent'
					when kmp.name_plan LIKE '%bonus uncapped'				then 'GF_BUC_PresentPresent'
					when kmp.name_plan LIKE '%bonus utilities'				then 'GF_BUT_PresentPresent'
					when kmp.name_plan LIKE '%bonus excom bp ec leaders'	then 'GF_BEC_PresentPresent'
			   end as column_name
			INTO #changed_plans
			FROM k_m_plans kmp
			WHERE 
			   kmp.name_plan LIKE '%bonus capped'
			OR kmp.name_plan LIKE '%bonus uncapped'
			OR kmp.name_plan LIKE '%bonus utilities'
			OR kmp.name_plan LIKE '%bonus excom bp ec leaders'
			

			/* SELECT PROFILES */
			DROP TABLE IF EXISTS #profiles
			SELECT
				id_profile
			   ,name_profile 
			INTO #profiles
			FROM k_profiles
			WHERE name_profile IN
			(
			 'GV_Administrator'
			,'ExCom'
			,'HR department'
			,'CompBen team'
			,'Reward Manager'
			,'Reward Reviewer'
			,'Audit'
			,'Head of the HRBP'
			,'CEO'
			,'Co Reward Manager'
			)

			/* SYNCHRONIZE TABLES */
			exec sp_client_std_synchronize 'Engie_Cache_View_Process_Bonus_Capped', 'table', -14;
			exec sp_client_std_synchronize 'Engie_Cache_View_Process_BonusUncapped', 'table', -14;
			exec sp_client_std_synchronize 'Engie_Cache_View_Process_Bonus_Utility', 'table', -14;
			exec sp_client_std_synchronize 'Engie_Cache_View_Process_Bonus_ExCom_BP_EC_Leaders', 'table', -14;

			/* ADD FIELDS */
			INSERT INTO k_referential_grids_fields (id_grid, id_field, name_column, order_column, is_editable, is_sortable, width, thousand_separator, decimal_precision, is_flex_used, is_percentage_used, is_bulk_apply_used, enable_row_validation, is_uid_reference, hyperlink_enabled, hyperlink_type)
			SELECT
				krg.id_grid
			   ,vf.id_field
			   ,cp.column_name
			   ,0
			   ,0
			   ,0
			   ,130
			   ,1
			   ,0
			   ,0
			   ,0
			   ,0
			   ,0
			   ,0
			   ,0
			   ,0
			FROM #changed_plans cp
			JOIN k_m_type_plan kmtp
				ON kmtp.id_type_plan = cp.id_type_plan
			JOIN k_referential_grids krg
				ON kmtp.id_base_grid = krg.id_grid
			JOIN k_referential_tables_views krtv
				ON krg.id_table_view = krtv.id_table_view
			JOIN k_referential_tables_views_fields vf
				ON krtv.id_table_view = vf.id_table_view
			WHERE vf.name_field = 'PresentPresent'
			AND cp.name_plan_match IN ('Bonus Capped', 'Bonus Uncapped', 'Bonus Utilities', 'Bonus ExCom BP EC Leaders')

			/* ADD TRANSLATIONS */
			INSERT INTO rps_Localization (tab_id, module_type, item_id, name, value, culture, type_source)
			VALUES 
				(100, 6, 15, 'GF_BC_PresentPresent',  'Present - Present', 'en-US', 1)
			,	(100, 6, 15, 'GF_BUC_PresentPresent', 'Present - Present', 'en-US', 1)
			,	(100, 6, 15, 'GF_BUT_PresentPresent', 'Present - Present', 'en-US', 1)
			,	(100, 6, 15, 'GF_BEC_PresentPresent', 'Present - Present', 'en-US', 1);	


			/* PREPARE SORTING FOR EXISTING FIELDS + CALCULATE SORT FOR PRESENT - PRESENT, NEXT TO CURRENT ASF */
			drop table if exists #sort_present_present
			SELECT
				kmpi.id_planInfo
			   ,kmpi.sort 
			   ,krgf.name_column
			   ,kmpi.sort + 1 as sort_for_present_present
			   ,kmp.name_plan
			   ,kmp.id_plan
			INTO #sort_present_present
			FROM k_m_plans kmp
			JOIN #changed_plans cp
				ON kmp.id_plan = cp.id_plan
			JOIN k_m_plans_informations kmpi
				ON kmp.id_plan = kmpi.id_plan
			JOIN k_referential_grids_fields krgf
				ON krgf.id_column = kmpi.id_field_grid
			where krgf.name_column in 
			(
			'GF_BC_Current_ASF'
			,'GF_BUC_Current_ASF'
			,'GF_BUT_Current_ASF'
			,'GF_BEC_Previous_ASF'
			)

			/* UPDATE SORT FOR EXISTING FIELDS */
			DROP TABLE IF EXISTS #sort_update_existing_fields
			SELECT
				kmpi.id_planInfo
			   ,kmpi.sort 
			INTO #sort_update_existing_fields
			FROM k_m_plans kmp
			JOIN #changed_plans cp
				ON kmp.id_plan = cp.id_plan
			JOIN k_m_plans_informations kmpi
				ON kmp.id_plan = kmpi.id_plan
			JOIN k_referential_grids_fields krgf
				ON krgf.id_column = kmpi.id_field_grid
			JOIN (SELECT
					MIN(s.sort_for_present_present) AS sort
				   ,name_plan
				FROM #sort_present_present s
				GROUP BY s.name_plan) s_min
			ON kmpi.sort >= s_min.sort
			AND kmp.name_plan = s_min.name_plan

			UPDATE kmpi
			SET sort = kmpi.sort + 1
			FROM k_m_plans_informations kmpi
			JOIN #sort_update_existing_fields su
				ON kmpi.id_planInfo = su.id_planInfo

			/* UPDATE SORT FOR EXISTSING INDICATORS */
			DROP TABLE IF EXISTS #k_m_plans_indicators_cu
			SELECT
				kmpi.id_plan_indicator 
				, kmpi.sort_plan_ind
			INTO #k_m_plans_indicators_cu
			FROM k_m_plans_indicators kmpi
			JOIN #changed_plans cp
				ON kmpi.id_plan = cp.id_plan
			JOIN (SELECT
					MIN(s.sort_for_present_present) AS sort
				   ,s.id_plan
				FROM #sort_present_present s
				GROUP BY s.id_plan) s_min
			ON kmpi.sort_plan_ind >= s_min.sort
			AND kmpi.id_plan = s_min.id_plan
	

			UPDATE kmpi
			SET sort_plan_ind = kmpi.sort_plan_ind + 1
			FROM k_m_plans_indicators kmpi
			JOIN #k_m_plans_indicators_cu tkmpi
				ON kmpi.id_plan_indicator = tkmpi.id_plan_indicator


			/* ADD FIELDS TO THE PROCESS */
			INSERT INTO k_m_plans_informations (id_plan, id_field_grid, width, sort, is_locked, type)
			SELECT
				cp.id_plan
			   ,krgf.id_column
			   ,150 AS width
			   ,s.sort_for_present_present AS sort
			   ,0 AS is_locked
			   ,1 AS type
			FROM #changed_plans cp
			JOIN k_m_type_plan kmtp
				ON kmtp.id_type_plan = cp.id_type_plan
			JOIN k_referential_grids krg
				ON kmtp.id_base_grid = krg.id_grid
			JOIN k_referential_grids_fields krgf
				ON krg.id_grid = krgf.id_grid
				AND krgf.name_column = cp.column_name
			JOIN #sort_present_present s
					ON cp.name_plan = s.name_plan

			/* SETUP FIELDS VISIBILITY */
			DROP TABLE IF EXISTS #display_information
			SELECT
				kmpd.id_plan_display	AS id_plan_display
			   ,ref_grid.id_planInfo	AS id_plan_information
			   ,1						AS available_plan_display_information
			   ,1						AS show_plan_display_information
			   ,1						AS optional_show_plan_display_information
			   ,p.name_profile 
			   ,cp.name_plan_match 
			INTO #display_information
			FROM k_m_plan_display kmpd
			JOIN #changed_plans cp
				ON kmpd.id_plan = cp.id_plan
			JOIN #profiles p
				ON kmpd.id_profile = p.id_profile
			JOIN k_m_type_plan kmpt
				ON kmpt.id_type_plan = cp.id_type_plan
			JOIN (SELECT
					krgf.id_grid
				   ,kmpi.id_planInfo
				FROM k_referential_grids_fields krgf
				JOIN k_m_plans_informations kmpi
					ON kmpi.id_field_grid = krgf.id_column
				WHERE name_column IN 
					(
						'GF_BC_PresentPresent'
					,	'GF_BUC_PresentPresent'
					,	'GF_BUT_PresentPresent'
					,	'GF_BEC_PresentPresent'
					)
				) ref_grid
				ON kmpt.id_base_grid = ref_grid.id_grid
				

			INSERT INTO k_m_plan_display_information (id_plan_display, id_plan_information, available_plan_display_information, show_plan_display_information, optional_show_plan_display_information)
			SELECT
				id_plan_display
			   ,id_plan_information
			   ,available_plan_display_information
			   ,show_plan_display_information
			   ,optional_show_plan_display_information
			FROM #display_information


			DROP TABLE IF EXISTS #backup_tmp;
			DROP TABLE IF EXISTS #changed_plans;
			DROP TABLE IF EXISTS #profiles;
			DROP TABLE IF EXISTS #sort_present_present;
			DROP TABLE IF EXISTS #sort_update_existing_fields;
			DROP TABLE IF EXISTS #k_m_plans_indicators_cu;
			DROP TABLE IF EXISTS #display_information;


	
	INSERT INTO _tb_one_time_scripts_release_log (script_name, applied_on)
	VALUES ('58_ENG_351_add_present_present_to_bonus_processes', GETUTCDATE());

END
GO