CREATE procedure [dbo].[_sp_b2b_etl_rev_revenue_freeze_mapping_refresh]  
  
as  
begin  
 DECLARE @procedure_name nvarchar(100) = object_name(@@procid)  
  ,@note VARCHAR(1000)   = ''  
  ,@event_id int  
   
 ----------------------------------------------------------------------------------------------------------------------------------  
 -- Execution log: START  
 ----------------------------------------------------------------------------------------------------------------------------------   
  
 EXEC dbo._sp_stored_procedure_audit_details 0, @procedure_name, @note, NULL, @event_id_out = @event_id OUT  
  
 ;with cte_rev as  
 (select   
   calendar_year_month_id,sun_site_id_sap_order_no, flag_is_rev_in, flag_revenue_py -- select *  
 from _tb_b2b_rev_revenue where start_date >= '2025-01-01')  
     
 update rrs  
 set  
  flag_is_rev_in = t13.flag_is_rev_in  
 from cte_rev rrs  
 outer apply (  
 select rev_year = cast(left(cast(calendar_year_month_id as varchar(100)), 4) as int) )t10  
 join _tb_b2b_site_id_freeze sif  
  on sif.year = t10.rev_year  
  and sif.site_id = rrs.sun_site_id_sap_order_no  
 outer apply (  
  select IIF(rrs.flag_revenue_py = 1 and sif.id is null, 0, 1) as flag_is_rev_in  
 ) t13  
  
 ;with cte_rev as  
 (select   
  a_number_taifun_id, sales_person_id, start_date, calendar_year_month_id, account_manager, original_account_manager, flag_account_manager_overwritten,original_sales_person_id  
 from _tb_b2b_rev_revenue where start_date >= '2025-01-01')  
     
 update rrs  
 set  
  account_manager = COALESCE(aof.account_manager, rrs.account_manager),  
  sales_person_id = t11.sales_person_id_proxy,  
  flag_account_manager_overwritten = t12.flag_account_manager_overwritten  
 from cte_rev rrs  
 outer apply (  
 select rev_year = cast(left(cast(calendar_year_month_id as varchar(100)), 4) as int) )t10  
 join _tb_b2b_account_owner_freeze aof  
  on aof.year = t10.rev_year  
  and aof.a_number = rrs.a_number_taifun_id  
 outer apply (  
  select sales_person_id_freezed = coalesce(aof.sales_person_id, rrs.sales_person_id)  
  ) t101  
 outer apply (  
  select sales_person_id_proxy = iif(len(t101.sales_person_id_freezed) < 10, replicate('0', 10 - len(t101.sales_person_id_freezed)) + t101.sales_person_id_freezed, t101.sales_person_id_freezed)  
   ,original_sales_person_id_proxy = iif(len(rrs.original_sales_person_id) < 10, replicate('0', 10 - len(rrs.original_sales_person_id)) + rrs.original_sales_person_id, rrs.original_sales_person_id)  
 ) t11  
 outer apply (  
  select IIF(COALESCE(t11.sales_person_id_proxy,'') = COALESCE(t11.original_sales_person_id_proxy,''), 0, 1) as flag_account_manager_overwritten  
 ) t12  
 ----------------------------------------------------------------------------------------------------------------------------------  
 -- Execution log: END  
 ----------------------------------------------------------------------------------------------------------------------------------   
  
 EXEC dbo._sp_stored_procedure_audit_details 1, @procedure_name, @note, @event_id, @event_id_out = @event_id OUT  
end
