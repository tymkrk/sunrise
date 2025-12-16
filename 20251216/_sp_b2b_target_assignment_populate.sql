
ALTER PROCEDURE [dbo].[_sp_b2b_target_assignment_populate]  
	@id_b2b_plan int  = null
,	@person_id nvarchar(133)  = null
,	@report_mode int 
,	@tl_version int = null
AS  
/*  
 Author: Kamil Roganowicz
 Date: 2023-10-12
 Description:  Procedure to populate _tb_b2b_target_assignment_details using _tb_b2b_target_assignment_details_versions
 Changes:  

*/  
BEGIN  

--declare	@id_b2b_plan int  = 116
--,	@person_id nvarchar(133)  = '58463'
--,	@report_mode int = 0
--,	@tl_version int = null

			IF @tl_version = -1
			BEGIN
			
				SET @tl_version = (select dbo._fn_b2b_tl_max_version(@person_id,@id_b2b_plan))
			
			END


			declare @initial_step_id int = (select MIN(id)
					from _tb_b2b_tl_ref_status
					)
			
			declare @initial_step nvarchar(255) = (select status
					from _tb_b2b_tl_ref_status
					where id = @initial_step_id
					)
		
	
			drop table if exists #employee_list_plan_assignment
			select distinct 
					pa.sales_person_id
				,	pa.id_b2b_plan
				,	p.year
				,	@report_mode as report_mode
			into #employee_list_plan_assignment
			from _tb_b2b_employee_plan_assignment pa
			join _tb_b2b_plan p
				on pa.id_b2b_plan = p.id
			left join _tb_b2b_tl_signature_status sa
				on sa.plan_id = pa.id_b2b_plan
				and sa.person_id = pa.person_id
			where	id_b2b_plan = @id_b2b_plan
			and	((@report_mode = 1 and	sa.status	<> @initial_step) or (@report_mode = 0 and sa.status is not null))
			and ((@report_mode = 1 and pa.person_id = @person_id) or @report_mode = 0)
	

			drop table if exists #max_version
			select 
				dv.sales_person_id
			,	dv.year
			,	MAX(dv.version) as max_version
			,	ISNULL(@tl_version,-1) as tl_version
			,	pa.report_mode
			,	case when ((pa.report_mode = 1 and MAX(dv.version) = ISNULL(@tl_version,-1)) or pa.report_mode = 0) then 1 
				else 0 end as update_target
			into #max_version
			From _tb_b2b_target_assignment_details_versions dv
			join #employee_list_plan_assignment pa
				on dv.sales_person_id = pa.sales_person_id
				and dv.year = pa.year
			group by dv.sales_person_id, dv.year, pa.report_mode

			drop table if exists #final_update
			select 
				sales_person_id
			,	year
			,	max_version
			,	update_target
			into #final_update
			from #max_version
			where update_target = 1


			if exists (select 1 from #final_update)
			begin
			
	
				drop table if exists #final_targets
				select
					dv.sales_person_id
				,	dv.metric_code
				,	dv.segment_code
				,	dv.year
				,	dv.version
				,	dv.m01
				,	dv.m02
				,	dv.m03
				,	dv.m04
				,	dv.m05
				,	dv.m06
				,	dv.m07
				,	dv.m08
				,	dv.m09
				,	dv.m10
				,	dv.m11
				,	dv.m12
				into #final_targets 
				From #final_update fu
				join _tb_b2b_target_assignment_details_versions dv
					on fu.sales_person_id	= dv.sales_person_id
					and fu.max_version		= dv.version
					and fu.year				= dv.year

				delete d
				from _tb_b2b_target_assignment_details d
				join #final_targets ft
					on d.sales_person_id = ft.sales_person_id
					and d.year = ft.year

				delete d
				from _tb_b2b_target_assignment_details d
				left join  _tb_b2b_target_assignment_details_versions dv
					on d.metric_code = dv.metric_code
					and d.year = dv.year
					and coalesce(tad.segment_code, '') = coalesce(dv.segment_code, '')
					and d.sales_person_id = dv.sales_person_id
				where dv.id is null
					and d.year > 2023 -- funcionality added after year 2023.

				insert into _tb_b2b_target_assignment_details 
				(sales_person_id, metric_code, segment_code, year, m01, m02, m03, m04, m05, m06, m07, m08, m09, m10, m11, m12)
				select
					ft.sales_person_id
				,	ft.metric_code
				,	ft.segment_code
				,	ft.year
				,	ft.m01
				,	ft.m02
				,	ft.m03
				,	ft.m04
				,	ft.m05
				,	ft.m06
				,	ft.m07
				,	ft.m08
				,	ft.m09
				,	ft.m10
				,	ft.m11
				,	ft.m12
				from #final_targets  ft


				update  dv
				set is_current = 
					case when dv.version =	mv.max_version 
					then 1 else 0 end
				from _tb_b2b_target_assignment_details_versions dv
				join #max_version mv
					on		dv.sales_person_id	=	mv.sales_person_id

		
				
			end
		

		


end
