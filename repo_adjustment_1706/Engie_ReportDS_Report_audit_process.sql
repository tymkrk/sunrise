CREATE PROCEDURE [dbo].[Engie_ReportDS_Report_audit_process] 
@idUser int,
@idProfile int,
@show_all bit = 1,
@idProcessList varchar(255) = NULL,
@idTree INT = null,
@idProcess INT = null,
@idPayee INT = null,
@idType int = null

AS

/*  
	Author: Rafal Jura
	Date: 2023-07-06
	Description: main source for Audit report
	Changes:
		(1) 2023-11-17 Rafal Jura: optimization
		(2) 2023-11-27 Rafal Jura: visibility controlled by Engie_Profile_Report_Permission table
		(3) 27/02/2024 - Mateusz Paliuch - ZD#103736 Added distinct to #temp_hierarchy_cte insert
		(4) 2024-05-13 Rafal Jura: ENG-56 moved security to separate procedure
		(5) 2024-06-19 Kamil Roganowicz: ENG-31 null handling in @idTree, @idProcess, @idPayee, @idType
		(6) 02/07/2024 - Maciej Srodulski - ENG-31 Removing report from manager reports and adapting to analysis tab.
		(7) 2024-10-21 - Rafal Jura - ENG-258 changed approach to show only one process
		(8) 2024-10-29 - Rafal Jura- ENG-258 added parameter @idProcessList used as multiselect filter
*/


BEGIN


	declare 
      @Id_log int,
      @ReportPstkName varchar(max),
      @ParamPstkList varchar(max),
      @date datetime,
	  @EffectiveDate date = (SELECT Effective_Date FROM Engie_Param_Yearly_Campaign WHERE ID_Status IN (2,3)),
	  @is_apply_filter bit = 0,
	  @is_included bit = 1,
	  @assigned_idType int = 14,
	  @assigned_idChild int,
	  @assigned_top_node bit = 1,
	  @show_report bit = 0,
	  @user_culture nvarchar(10) = 'en-US'

	SET @show_all = 0

	set @date = GETUTCDATE()
    set @ReportPstkName=OBJECT_NAME(@@PROCID) 
    set @ParamPstkList = ''
        +'@idUser = '+isnull(''''+convert(varchar(100),@idUser)+'''','NULL') 
        +', @idProfile = '+isnull(''''+convert(varchar(100),@idProfile)+'''','NULL')       
        +', @idTree = '+isnull(''''+convert(varchar(100),@idTree)+'''','NULL') 
        +', @idProcess = '+isnull(''''+convert(varchar(100),@idProcess)+'''','NULL')
        +', @idPayee = '+isnull(''''+convert(varchar(100),@idPayee)+'''','NULL')
        +', @idType = '+isnull(''''+convert(varchar(100),@idType)+'''','NULL')
		+', @show_all = '+isnull(''''+ CASE WHEN @show_all = 1 THEN '1' ELSE '0' END + '''','NULL')
        +', @idProcessList = ' + isnull('''' + @idProcessList + '''', 'NULL')

	DECLARE @process_list TABLE (id_plan int)

	IF @idProcess IS NOT NULL
		INSERT INTO @process_list (id_plan)
		VALUES (@idProcess)
	ELSE
		INSERT INTO @process_list (id_plan)
		SELECT
			ss.[value] AS id_plan
		FROM STRING_SPLIT(@idProcessList, ',') ss

    exec Engie_Insert_Report_Logs_Start @ReportPstkName,@ParamPstkList,@Id_log output

	SELECT
		@user_culture = up.culture
	FROM k_users u
	INNER JOIN k_users_parameters up
		ON up.id = u.id_user_parameter
	WHERE u.id_user = @idUser

	DROP TABLE IF EXISTS #TempAudit
	CREATE TABLE #TempAudit (
		idPayee int,
		idPayee_affected int,
		codepayee nvarchar(50),
		[name] nvarchar(512),
		user_fullname nvarchar(512),
		user_login nvarchar(128),
		home_host nvarchar(10),
		id_step int,
		id_ind int,
		id_field int,
		name_ind nvarchar(256),
		name_field nvarchar(256),
		label_field nvarchar(256),
		name_plan nvarchar(256),
		id_plan int,
		start_step datetime,
		end_step datetime,
		input_value NVARCHAR(MAX),
		date_histo datetime
	)

	DROP TABLE IF EXISTS #visibility
	CREATE TABLE #visibility (
		TreeName nvarchar(255),
		idTreePublished int,
		id_hm_NodeTree int,
		ID_YearlyCampaign int,
		Year_YearlyCampaign int,
		Effective_Date date,
		idPayee int,
		codePayee nvarchar(20),
		lastname nvarchar(100),
		firstname nvarchar(100),
		LegalEntity nvarchar(100),
		BPGuid nvarchar(100),
		GcrowdId nvarchar(100)
	)

	DROP TABLE IF EXISTS #temp_hierarchy_cte_filtered
	CREATE TABLE #temp_hierarchy_cte_filtered (
		idTree int,
		idChild int
	)

	INSERT INTO #temp_hierarchy_cte_filtered (idTree, idChild)
	EXEC Engie_ReportDS_Hierarchy_Security @idUser, @idProfile, NULL, NULL

	INSERT INTO #visibility (idPayee, codePayee, lastname, firstname)
    SELECT
      ps.idPayee
	  ,ps.codePayee
	  ,ps.lastname
	  ,ps.firstname
    FROM #temp_hierarchy_cte_filtered c
--decide if below should be stored as view Engie_View_Payee_Current_Campaign_Info	
	INNER JOIN Engie_Cache_View_Yearly_Campaign_Payees_Situations ps
		ON ps.idPayee = c.idChild

	DROP TABLE IF EXISTS #temp_hierarchy_cte_filtered

	DROP TABLE IF EXISTS #temp_result_payees
	CREATE TABLE #temp_result_payees (
		id_payee int
	)

	INSERT INTO #temp_result_payees (id_payee)
	SELECT DISTINCT
		ps.id_payee
	FROM k_m_plans_payees_steps ps
	INNER JOIN #visibility v
		ON v.idPayee = ps.id_payee

	DROP TABLE IF EXISTS #temp_field_editable_list
	CREATE TABLE #temp_field_editable_list (
		id_plan int,
		id_ind int,
		id_field int,
		name_ind nvarchar(255),
		name_field nvarchar(255),
		label_field nvarchar(255),
		code_field nvarchar(255),
		is_percentage_used int,
		is_number bit,
		decimal_precision int
	)

	INSERT INTO #temp_field_editable_list (id_plan, id_ind, id_field, name_ind, name_field, label_field, code_field, is_percentage_used, is_number, decimal_precision)
	SELECT DISTINCT
		p.id_plan,
		wsgd.id_ind,
		wsgd.id_field,
		COALESCE(li.value, i.name_ind) AS name_ind,
		f.name_field,
		REPLACE(REPLACE(f.label_field, ' (Proposal)', ''), 'Proposal ', '') AS label_field,
		f.code_field,
		f.is_percentage_used,
		CASE WHEN f.type_value = '2' OR f.type_value = '4' THEN 1 ELSE 0 END AS is_number,
		COALESCE(f.decimal_precision, 0) AS decimal_precision
	FROM k_m_workflow w
	INNER JOIN k_m_plans p
		ON p.id_workflow = w.id_workflow
	INNER JOIN k_m_workflow_step ws
		ON ws.id_workflow = w.id_workflow
	INNER JOIN k_m_workflow_step_group wsg
		ON wsg.id_wflstep = ws.id_wflstep
	INNER JOIN k_m_workflow_step_group_profile wsgp
		ON wsgp.id_wflstepgroup = wsg.id_wflstepgroup
	INNER JOIN k_profiles pr
		ON pr.id_profile = wsgp.id_profile
		AND pr.name_profile NOT IN ('GV_Administrator', 'Audit', 'SSO Switcher')
	INNER JOIN k_m_workflow_step_group_detail wsgd
		ON wsgd.id_wflstepgroup = wsg.id_wflstepgroup
	INNER JOIN k_m_indicators i
		ON i.id_ind = wsgd.id_ind
	LEFT JOIN rps_Localization li
		ON li.name = i.name_ind
		AND li.culture = 'en-us'
	INNER JOIN k_m_fields f
		ON f.id_field = wsgd.id_field
	INNER JOIN k_m_indicators_fields kmif
		ON i.id_ind = kmif.id_ind
		AND f.id_field = kmif.id_field
	WHERE
	/*
		List of fields
	*/
	(
		(wsgd.is_editable = 1
		AND wsgd.is_readable = 1
		AND f.code_field NOT LIKE '%_Proposal')
	OR
		(f.code_field in ('GR_EBL_Pourcentage', 'GF_ESA_Pourcentage', 'GR_GB_Pourcentage', 'GR_GB_Total_Increase_Percent',
		 'GF_GW_Pourcentage', 'GF_IE_Pourcentage_Individual_Salary_Increase', 'GF_IE_Pourcentage_Total_Salary_Increase', 'GF_BUC_Pourcentage_Bonus', 'GR_GW_Total_Increase_Percent', 'GF_ESA_CollectiveSalaryInc_Pct', 
		 'GF_BC_Pourcentage_Bonus_Proposal', 'GF_BUT_Pourcentage_Bonus_Proposal','GR_BEC_Bonus_Percent_Proposal') -- Pct / % Bonus(Incl. Exceptional bonus)
		OR f.code_field in ('GF_BUT_Bonus_Amount', 'GR_BEC_Bonus_Amount', 'GF_BC_Bonus_Amount', 'GR_GB_Amount_SR', 'GF_GW_Amount_SR', 'GF_IE_Amount_SR') -- Amount in employee currency / Bonus amount in Employee Currency (Excl. Exceptional bonus)
		OR f.label_field = 'Salary Increase Amount (in EUR FTE)' 
		OR f.label_field = 'Salary Increase %' 
		OR f.code_field IN ('GF_BC_Bonus_Amount_EUR_2', 'GF_BUT_Bonus_Amount_EUR_2', 'GR_BEC_Bonus_Amount_EUR_2') -- Bonus amount in EUR (Excl.  Exceptional bonus)
		OR f.code_field IN ('GF_BC_ExceptionalBonus', 'GF_BUT_ExceptionalBonus', 'GF_BEC_ExceptionalBonus') -- Exceptional Bonus in employee currency
		OR f.code_field IN ('GF_BC_ExceptionalBonus_EUR', 'GF_BUT_ExceptionalBonus_EUR', 'GF_BEC_ExceptionalBonus_EUR')) -- Exceptional bonus in EUR
		
	)
	/*
		List of processes
	*/
	AND (p.name_plan LIKE '%Base Pay Review World%'
			OR p.name_plan LIKE '%Base Pay Review ENGIE SA%'
			OR p.name_plan LIKE '%EBL - EBL%'
			OR p.name_plan LIKE '%Base Pay Review Italy%'
			OR p.name_plan LIKE '%Bonus Capped%'
			OR p.name_plan LIKE '%Bonus Uncapped%'
			OR p.name_plan LIKE '%Bonus Utilities%'
			OR p.name_plan LIKE '%Bonus ExCom BP EC Leaders%'
			OR p.name_plan LIKE '%Bonus Deferral%')
	/*
		Show all processes or only one
	*/
	AND (@show_all = 1
		OR 
			(@show_all = 0 AND p.id_plan IN (SELECT id_plan FROM @process_list))
		)

	/*
		Show report always to CompBen Team profile, to other profiles in specific period
	*/
	SELECT
		@show_report = CASE WHEN p.name_profile IN ('CompBen team', 'GV_Administrator') THEN 1
							WHEN prp.ID IS NOT NULL THEN 1
							ELSE 0
						END
	FROM k_profiles p
	INNER JOIN Engie_View_REF_Report_List rl
		ON rl.report_name = 'Audit Process Report'
	LEFT JOIN Engie_Profile_Report_Permission prp
		ON prp.report_id = rl.report_id
		AND prp.id_profile = p.id_profile
		AND @date BETWEEN prp.[start_date] AND prp.[end_date]
	WHERE p.id_profile = @idProfile

	IF @show_report = 0
	BEGIN
		SELECT
			NULL AS codepayee,
			NULL AS [name],
			NULL AS home_host,
			NULL AS user_fullname,
			NULL AS user_login,
			NULL AS name_ind,
			NULL AS name_field,
			NULL AS label_field,
			NULL AS name_plan,
			NULL AS id_plan,
			NULL AS start_step,
			NULL AS end_step,
			NULL AS date_histo,
			NULL AS date_histo_char,
			NULL AS input_value,
			NULL AS prev_input_value,
			'True' as row_count_flag,
			1 as CountRow,
			NULL AS idPayee_affected,
			NULL AS idPayee,
			CAST(@show_report AS bit) AS show_report
		
		EXEC Engie_Update_Report_Logs_End @Id_log

		RETURN
	END
	
	INSERT INTO #TempAudit
	SELECT
		@idPayee AS idPayee,
		pp.idPayee AS idPayee_affected,
		pp.codepayee,
		ISNULL(pp.firstname, '') + ' ' + ISNULL(pp.lastname, '') AS [name],
		CASE WHEN vh.id_user = -1 THEN 'SYSTEM UPDATE' ELSE ISNULL(u.firstname_user, '') + ' ' + ISNULL(u.lastname_user, '') END AS user_fullname,
		CASE WHEN vh.id_user = -1 THEN 'SYSTEM UPDATE' ELSE ISNULL(u.login_user,'') END AS user_login,
		CASE WHEN pp.ss_nb = 'expat' THEN 'Home' ELSE NULL END AS home_host,
		vh.id_step,
		vh.id_ind,
		vh.id_field,
		tfel.name_ind,
		tfel.label_field AS name_field,
		tfel.label_field,
		kmp.name_plan, 
		kmp.id_plan,
		ps.start_step,
		ps.end_step,
		CASE
			WHEN tfel.is_percentage_used = 1
			THEN FORMAT(TRY_CAST(vh.input_value as decimal(18,4)), 'P')
			WHEN tfel.is_number = 1
				THEN CASE tfel.decimal_precision
						WHEN 0
						THEN FORMAT(TRY_CAST(vh.input_value as decimal(18,0)), 'G', @user_culture)
						WHEN 1
						THEN FORMAT(TRY_CAST(vh.input_value as decimal(18,1)), 'N', @user_culture)
						WHEN 2
						THEN FORMAT(TRY_CAST(vh.input_value as decimal(18,2)), 'N', @user_culture)
						WHEN 3
						THEN FORMAT(TRY_CAST(vh.input_value as decimal(18,3)), 'N', @user_culture)
						WHEN 4
						THEN FORMAT(TRY_CAST(vh.input_value as decimal(18,4)), 'N', @user_culture)
					ELSE vh.input_value
				END
			ELSE vh.input_value END AS input_value,
		vh.date_histo
	FROM py_Payee pp
	INNER JOIN #temp_result_payees t
		ON t.id_payee = pp.idPayee
    INNER JOIN k_m_plans_payees_steps ps WITH(NOLOCK)
	    ON t.id_payee = ps.id_payee
    INNER JOIN k_m_plans as kmp
	    ON kmp.id_plan = ps.id_plan
	LEFT JOIN Engie_k_m_values_histo vh WITH(NOLOCK)
	    ON ps.id_step = vh.id_step
	INNER JOIN #temp_field_editable_list tfel
		ON tfel.id_plan = kmp.id_plan
		AND tfel.id_ind = vh.id_ind
		AND tfel.id_field = vh.id_field
    LEFT JOIN k_users AS u
		ON u.id_user = vh.id_user

	/*
		Select result
	*/
	SELECT
		t.codepayee,
		[name],
		home_host,
		user_fullname,
		user_login,
		name_ind,
		name_field,
		label_field,
		name_plan,
		t.id_plan,
		start_step,
		end_step,
		date_histo,
		CONVERT(varchar(19), date_histo ,120) as date_histo_char,
		input_value = dbo.fnClearText(input_value),
		prev_input_value = LAG( dbo.fnClearText(input_value) , 1) OVER (PARTITION BY idPayee_affected, id_ind, id_field, t.id_plan ORDER BY date_histo),
		'True' as row_count_flag,
		1 as CountRow,
		t.idPayee_affected as idPayee_affected,
		t.idPayee as idPayee,
		CAST(@show_report AS bit) AS show_report
	FROM #TempAudit t
	WHERE 1 = 1
	order by date_histo desc
	
	EXEC Engie_Update_Report_Logs_End @Id_log
END
GO

