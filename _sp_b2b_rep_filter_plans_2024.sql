create PROCEDURE  [dbo].[_sp_b2b_rep_filter_plans_2024]
	@person_id nvarchar(133)
AS

BEGIN
/*
	Description: Procedure filters plans that are in status 'Active', 'Active, in review' and 'Archived'
*/

		DECLARE @procedure_name	nvarchar(100)	= object_name(@@procid)
				,@note VARCHAR(1000)			= 'person_id: ' + ISNULL(CAST(@person_id AS VARCHAR(133)), 'null') 
				,@event_id int

		----------------------------------------------------------------------------------------------------------------------------------
		-- Execution log: START
		----------------------------------------------------------------------------------------------------------------------------------

		EXEC dbo._sp_b2b_stored_procedure_audit_details 0, @procedure_name, @note, NULL, @event_id_out = @event_id OUT

	SELECT distinct  
		vbrrp.id_b2b_plan,
		vbrrp.b2b_plan_name,  
		tbepa.person_id
	FROM _vw_b2b_ref_reported_plans AS vbrrp  
	JOIN _tb_b2b_employee_plan_assignment AS tbepa 
		ON vbrrp.id_b2b_plan = tbepa.id_b2b_plan  
	JOIN _tb_b2b_plan bp
		ON tbepa.id_b2b_plan = bp.id
	WHERE tbepa.person_id = @person_id
		AND bp.year IN (2023,2024)

		----------------------------------------------------------------------------------------------------------------------------------
		-- Execution log: END
		----------------------------------------------------------------------------------------------------------------------------------

		EXEC dbo._sp_b2b_stored_procedure_audit_details 1, @procedure_name, @note, @event_id, @event_id_out = @event_id OUT

END
