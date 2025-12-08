CREATE procedure [dbo].[_sp_b2b_etl_eof_sbp_freeze_mapping_refresh]
  
as  
begin  
	DECLARE @procedure_name nvarchar(100) = object_name(@@procid)  
		,@note VARCHAR(1000)   = ''  
		,@event_id int  
   
 ----------------------------------------------------------------------------------------------------------------------------------  
 -- Execution log: START  
 ----------------------------------------------------------------------------------------------------------------------------------   
  
	 EXEC dbo._sp_stored_procedure_audit_details 0, @procedure_name, @note, NULL, @event_id_out = @event_id OUT  

  
	;with cte_eof as  
		(select   
		a_number, sales_person_id, activation_date,  sf_account_manager_activation, sf_account_manager_latest, flag_account_manager_overwritten,original_sales_person_id, activation_year
		from _tb_b2b_eof_sbp where activation_date >= '2025-01-01')  
     

	update cte  
	set  
		sf_account_manager_latest = COALESCE(aof.account_manager, cte.sf_account_manager_latest),  
		sf_account_manager_activation = COALESCE(aof.account_manager, cte.sf_account_manager_activation),  
		sales_person_id = COALESCE(aof.sales_person_id, cte.sales_person_id), 
		flag_account_manager_overwritten = IIF(COALESCE(aof.sales_person_id, cte.sales_person_id,'') <> cte.original_sales_person_id,1,0)
	from cte_eof cte  
	join _tb_b2b_eof_account_owner_freeze aof  
		on aof.year = cte.activation_year  
		and aof.a_number = cte.a_number

 ----------------------------------------------------------------------------------------------------------------------------------  
 -- Execution log: END  
 ----------------------------------------------------------------------------------------------------------------------------------   
  
	EXEC dbo._sp_stored_procedure_audit_details 1, @procedure_name, @note, @event_id, @event_id_out = @event_id OUT  
end
