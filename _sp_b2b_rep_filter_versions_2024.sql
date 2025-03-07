CREATE PROCEDURE  [dbo].[_sp_b2b_rep_filter_versions_2024]
		@person_id nvarchar(133)
	,	@id_profile int
	,	@id_plan int
AS

BEGIN
  
		DECLARE @procedure_name	nvarchar(100)	= object_name(@@procid)
				,@note VARCHAR(1000)			= 'person_id: ' + ISNULL(CAST(@person_id AS VARCHAR(133)), 'null') 
													+ ', id_profile: ' + ISNULL(CAST(@id_profile AS VARCHAR(10)), 'null') 
													+ ', id_plan: ' + ISNULL(CAST(@id_plan AS VARCHAR(10)), 'null') 
				,@event_id int

		----------------------------------------------------------------------------------------------------------------------------------
		-- Execution log: START
		----------------------------------------------------------------------------------------------------------------------------------

		EXEC dbo._sp_b2b_stored_procedure_audit_details 0, @procedure_name, @note, NULL, @event_id_out = @event_id OUT


			DECLARE @id_profile_B2B_Admin INT	= (SELECT id_profile FROM k_profiles WHERE name_profile = 'B2B Admin')

			DECLARE @current_version int =  (select dbo._fn_b2b_tl_max_version(@person_id,@id_plan))

			IF @id_profile = @id_profile_B2B_Admin or @id_profile = -1
			BEGIN
			
					SELECT DISTINCT
						  case when v.version = @current_version then 'Current version' else concat('Version ', v.version) end as version
						 ,case when v.version = @current_version then -1 else v.version  end version_value
					FROM _tb_b2b_target_assignment_details_versions v
					JOIN _tb_b2b_employee_plan_assignment epa
						ON v.sales_person_id = epa.sales_person_id
					JOIN _tb_b2b_plan p
						ON epa.id_b2b_plan = p.id
							AND v.year = p.year
					WHERE epa.person_id = @person_id
					AND epa.id_b2b_plan = @id_plan

					UNION

					SELECT 'Current version' as version, -1 as version_value
					ORDER BY version 
			END
			
			ELSE 
			BEGIN
			
					SELECT DISTINCT
						  case when v.version = @current_version then 'Current version' else concat('Version ', v.version) end as version
						 ,case when v.version = @current_version then -1 else v.version  end version_value
					FROM _tb_b2b_target_assignment_details_versions v
					JOIN _tb_b2b_employee_plan_assignment epa
						ON v.sales_person_id = epa.sales_person_id
					JOIN _tb_b2b_plan p
						ON epa.id_b2b_plan = p.id
							AND v.year = p.year
					JOIN _tb_b2b_tl_signature_status s
						ON epa.id_b2b_plan = s.plan_id
						AND epa.person_id = s.person_id
						AND v.version = s.tl_version
					WHERE epa.person_id = @person_id
					AND epa.id_b2b_plan = @id_plan

					UNION

					SELECT 'Current version' as version, -1 as version_value
					ORDER BY version 
					
			
			END
	

		----------------------------------------------------------------------------------------------------------------------------------
		-- Execution log: END
		----------------------------------------------------------------------------------------------------------------------------------

		EXEC dbo._sp_b2b_stored_procedure_audit_details 1, @procedure_name, @note, @event_id, @event_id_out = @event_id OUT
	
END
