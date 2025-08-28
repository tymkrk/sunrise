create   procedure [dbo].[_sp_b2b_rep_filter_manager]
@id_user_profile int
as
begin

		DECLARE @procedure_name	nvarchar(100)	= object_name(@@procid)
				,@note VARCHAR(1000)			= 'id_user_profile = ' + ISNULL(CAST(@id_user_profile AS VARCHAR(20)), 'null') 
				,@event_id int

		----------------------------------------------------------------------------------------------------------------------------------
		-- Execution log: START
		----------------------------------------------------------------------------------------------------------------------------------

		EXEC dbo._sp_b2b_stored_procedure_audit_details 0, @procedure_name, @note, NULL, @event_id_out = @event_id OUT

		drop table if exists #manager_list
		
		select 
				person_id	= se.person_id
				,	full_name	= se.person_id + ' - ' + se.first_name + ' ' + se.last_name
				,	id_user		= u.id_user
				,	rn	= row_number() over (partition by se.person_id, se.first_name, se.first_name  order by se.person_id)
		into #manager_list
		from	k_users_profiles (nolock) up
		join	k_profiles (nolock) p
			on	p.id_profile = up.id_profile
			and	p.name_profile = 'B2B Manager'
		join	k_users (nolock) u
			on	u.id_user = up.id_user
			and	u.active_user = 1
		join	py_payee (nolock) pp
			on	pp.idpayee = u.id_external_user
		outer apply
			(select top 1 * 
			from _tb_b2b_sap_employee (nolock) se
			where se.person_id = pp.codepayee) se
		join	k_users_profiles (nolock) up_parameter
			on	up_parameter.iduserprofile = @id_user_profile
		join	k_profiles (nolock) p_parameter
			on	p_parameter.id_profile = up_parameter.id_profile
		where	p_parameter.name_profile = 'B2B Admin'
			or	up.id_user = up_parameter.id_user
			--) tab;


		select 
			person_id,
			full_name,
			id_user,
			sort_order	= row_number() over (order by person_id)
		from 	#manager_list
		where rn = 1
		----------------------------------------------------------------------------------------------------------------------------------
		-- Execution log: END
		----------------------------------------------------------------------------------------------------------------------------------

		EXEC dbo._sp_b2b_stored_procedure_audit_details 1, @procedure_name, @note, @event_id, @event_id_out = @event_id OUT

end
