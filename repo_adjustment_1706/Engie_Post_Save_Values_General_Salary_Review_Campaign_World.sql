CREATE PROCEDURE [dbo].[Engie_Post_Save_Values_General_Salary_Review_Campaign_World]
@kMValuesData AS [dbo].[Kernel_Type_k_m_values] READONLY
AS
/*
	Author: Rafal Jura
	Date: 2022-02-24
	Description: procedure refreshes values in World Campaign


	Changes:
	- (1) - 2022-05-26 - Rafał Walkowiak: Added promotion date differs per country
	- (2) - 2023-02-16 - Rafal Jura: added update of Effective Date if format is not correct
	- (3) - 2023-07-04 - Rafal Jura: added logging values to Engie_k_m_values_histo
	- (4) - 2023-07-12 - Rafal Jura: added NULLIF to denominators
*/
BEGIN
	DECLARE @procedure_name nvarchar(255) = OBJECT_NAME(@@PROCID)

	EXEC dbo._sp_audit_procedure_log 'Procedure Start', @procedure_name

	BEGIN TRY
		BEGIN TRANSACTION

		--DECLARE @kMValuesData AS [dbo].[Kernel_Type_k_m_values]
		
		DECLARE @id_plan int = (SELECT id_plan FROM k_m_plans WHERE name_plan LIKE '%Base Pay Review World%')

		DROP TABLE IF EXISTS #temp_steps
		DROP TABLE IF EXISTS #temp_values_pct_salary_increase
		DROP TABLE IF EXISTS #temp_values_total_increase
		DROP TABLE IF EXISTS #temp_values_new_hay_level
		DROP TABLE IF EXISTS #temp_values_effective_date

		CREATE TABLE #temp_steps (
			id_step int
		)

		IF NOT EXISTS(SELECT * FROM @kMValuesData)
		BEGIN
			INSERT INTO #temp_steps
			SELECT DISTINCT
				ps.id_step
			FROM k_m_plans_payees_steps ps
			WHERE  ps.id_plan = @id_plan
		END
		ELSE
		BEGIN
			INSERT INTO #temp_steps
			SELECT DISTINCT
				id_step
			FROM @kMValuesData
		END

		CREATE TABLE #temp_values_pct_salary_increase (
			id_step int,
			id_ind int,
			id_field int,
			input_value nvarchar(200),
			input_value_numeric decimal(18,4),
			input_date datetime,
			id_user int,
			comment_value nvarchar(200),
			source_value nvarchar(200),
			value_type int,
			idSim int
		)

		CREATE TABLE #temp_values_total_increase (
			id_step int,
			id_ind int,
			id_field int,
			input_value nvarchar(200),
			input_value_numeric decimal(18,4),
			input_date datetime,
			id_user int,
			comment_value nvarchar(200),
			source_value nvarchar(200),
			value_type int,
			idSim int
		)

		CREATE TABLE #temp_values_new_hay_level (
			id_step int,
			id_ind int,
			id_field int,
			input_value nvarchar(200),
			input_value_int int,
			input_date datetime,
			id_user int,
			comment_value nvarchar(200),
			source_value nvarchar(200),
			value_type int,
			idSim int
		)

		CREATE TABLE #temp_values_effective_date (
			id_step int,
			id_ind int,
			id_field int,
			input_value nvarchar(200),
			input_value_date datetime,
			input_date datetime,
			id_user int,
			comment_value nvarchar(200),
			source_value nvarchar(200),
			value_type int,
			idSim int
		)

		/*
			Update Pct from Salary Increase
		*/
		INSERT INTO #temp_values_pct_salary_increase (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			(SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_GW_Yearly_Campaign_GW_SalaryIncrease') AS id_ind,
			(SELECT id_field FROM k_m_fields WHERE code_field = 'GF_GW_Pourcentage') AS id_field,
			CASE WHEN v_am.input_value_numeric IS NULL THEN NULL ELSE CAST(CAST(COALESCE((v_am.input_value_numeric / NULLIF(c.BaseSalary, 0)), 0) AS decimal(18,4)) AS NVARCHAR(100)) END AS input_value,
			CASE WHEN v_am.input_value_numeric IS NULL THEN NULL ELSE CAST(COALESCE((v_am.input_value_numeric / NULLIF(c.BaseSalary, 0)), 0) AS decimal(18,4)) END AS input_value_numeric,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_General_Salary_Review_Campaign_World',
			1,
			0
		FROM Engie_Cache_View_Process_General_Salary_Review_Campaign_World c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		LEFT JOIN k_m_values v_am
			ON v_am.id_step = ps.id_step
			AND v_am.id_ind = (SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_GW_Yearly_Campaign_GW_SalaryIncrease')
			AND v_am.id_field = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_GW_Amount_SR')
		WHERE c.ID_YearlyCampaign = (SELECT ID FROM Engie_Param_Yearly_Campaign WHERE ID_Status = 3)

		MERGE k_m_values AS tg
		USING #temp_values_pct_salary_increase AS sc
			ON sc.id_step = tg.id_step
			AND sc.id_ind = tg.id_ind
			AND sc.id_field = tg.id_field
		WHEN MATCHED AND COALESCE(sc.input_value_numeric, 0) <> COALESCE(tg.input_value_numeric, 0)
			THEN UPDATE
				SET input_value = sc.input_value,
					input_value_numeric = sc.input_value_numeric,
					input_date = sc.input_date,
					comment_value = sc.comment_value,
					id_user = sc.id_user
		WHEN NOT MATCHED
		THEN INSERT (id_ind, id_field, id_step, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		VALUES (sc.id_ind, sc.id_field, sc.id_step, sc.input_value, sc.input_value_numeric, sc.input_date, sc.id_user, sc.comment_value, sc.source_value, sc.value_type, sc.idSim)
		OUTPUT		inserted.id_value
		  ,		inserted.id_ind
		  ,		inserted.id_field
		  ,		inserted.id_step
		  ,		inserted.input_value
		  ,		inserted.input_value_int
		  ,		inserted.input_value_numeric
		  ,		inserted.input_value_date
		  ,		inserted.input_date
		  ,		inserted.id_user
		  ,		inserted.comment_value
		  ,		inserted.source_value
		  ,		inserted.input_date
		  ,		inserted.id_user
		INTO Engie_k_m_values_histo (
					id_value
			   ,	id_ind
			   ,	id_field
			   ,	id_step
			   ,	input_value
			   ,	input_value_int
			   ,	input_value_numeric
			   ,	input_value_date
			   ,	input_date
			   ,	id_user
			   ,	comment_value
			   ,	source_value
			   ,	date_histo
			   ,	user_histo
			   );

		/*
			Update Global Pct and Increase Amount
		*/
		INSERT INTO #temp_values_total_increase (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			(SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_GW_Yearly_Campaign_GW_GlobalAmount') AS id_ind,
			(SELECT id_field FROM k_m_fields WHERE code_field = 'GF_GW_Final_Revised_Salary') AS id_field,
			CAST(CAST((c.BaseSalary * COALESCE(c.CollectiveSalaryIncreaseBelgium, 0)) + c.BaseSalary + COALESCE(v_am.input_value_numeric, 0) AS DECIMAL(18,4)) AS NVARCHAR(100)) AS input_value,
			CAST((c.BaseSalary * COALESCE(c.CollectiveSalaryIncreaseBelgium, 0)) + c.BaseSalary + COALESCE(v_am.input_value_numeric, 0) AS DECIMAL(18,4)) AS input_value_numeric,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_General_Salary_Review_Campaign_World',
			1,
			0
		FROM Engie_Cache_View_Process_General_Salary_Review_Campaign_World c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		LEFT JOIN k_m_values v_am
			ON v_am.id_step = ps.id_step
			AND v_am.id_ind = (SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_GW_Yearly_Campaign_GW_SalaryIncrease')
			AND v_am.id_field = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_GW_Amount_SR')
		WHERE c.ID_YearlyCampaign = (SELECT ID FROM Engie_Param_Yearly_Campaign WHERE ID_Status = 3)

		UNION

		SELECT
			ps.id_step,
			(SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GR_Yearly_Campaign_GW_Total_Increase') AS id_ind,
			(SELECT id_field FROM k_m_fields WHERE code_field = 'GR_GW_Total_Increase_Percent') AS id_field,
			CAST(CAST(((c.BaseSalary * COALESCE(c.CollectiveSalaryIncreaseBelgium, 0)) + COALESCE(v_am.input_value_numeric, 0)) / NULLIF(c.BaseSalary, 0) AS DECIMAL(18,4)) AS NVARCHAR(100)) AS input_value,
			CAST(((c.BaseSalary * COALESCE(c.CollectiveSalaryIncreaseBelgium, 0)) + COALESCE(v_am.input_value_numeric, 0)) / NULLIF(c.BaseSalary, 0) AS DECIMAL(18,4)) AS input_value_numeric,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_General_Salary_Review_Campaign_World',
			1,
			0
		FROM Engie_Cache_View_Process_General_Salary_Review_Campaign_World c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		LEFT JOIN k_m_values v_am
			ON v_am.id_step = ps.id_step
			AND v_am.id_ind = (SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_GW_Yearly_Campaign_GW_SalaryIncrease')
			AND v_am.id_field = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_GW_Amount_SR')
		WHERE c.ID_YearlyCampaign = (SELECT ID FROM Engie_Param_Yearly_Campaign WHERE ID_Status = 3)

		MERGE k_m_values AS tg
		USING #temp_values_total_increase AS sc
			ON sc.id_step = tg.id_step
			AND sc.id_ind = tg.id_ind
			AND sc.id_field = tg.id_field
		WHEN MATCHED AND COALESCE(sc.input_value_numeric, 0) <> COALESCE(tg.input_value_numeric, 0)
			THEN UPDATE
				SET input_value = sc.input_value,
					input_value_numeric = sc.input_value_numeric,
					input_date = sc.input_date,
					comment_value = sc.comment_value,
					id_user = sc.id_user
		WHEN NOT MATCHED
		THEN INSERT (id_ind, id_field, id_step, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		VALUES (sc.id_ind, sc.id_field, sc.id_step, sc.input_value, sc.input_value_numeric, sc.input_date, sc.id_user, sc.comment_value, sc.source_value, sc.value_type, sc.idSim)
		OUTPUT		inserted.id_value
		  ,		inserted.id_ind
		  ,		inserted.id_field
		  ,		inserted.id_step
		  ,		inserted.input_value
		  ,		inserted.input_value_int
		  ,		inserted.input_value_numeric
		  ,		inserted.input_value_date
		  ,		inserted.input_date
		  ,		inserted.id_user
		  ,		inserted.comment_value
		  ,		inserted.source_value
		  ,		inserted.input_date
		  ,		inserted.id_user
		INTO Engie_k_m_values_histo (
					id_value
			   ,	id_ind
			   ,	id_field
			   ,	id_step
			   ,	input_value
			   ,	input_value_int
			   ,	input_value_numeric
			   ,	input_value_date
			   ,	input_date
			   ,	id_user
			   ,	comment_value
			   ,	source_value
			   ,	date_histo
			   ,	user_histo
			   );

		/*
			Update New Hay Level
		*/
		DROP TABLE IF EXISTS #id_next_Hay_Level
		CREATE TABLE #id_next_Hay_Level (
			id_Classification_Specifics_Hay_Level int,
			id_next_Classification_Specifics_Hay_Level int,
			Hay_Level_Code int,
			next_Hay_Level_Code int
		)

		;WITH next_Hay_Level AS
		(
			SELECT
				a.id id_Classification_Specifics_Hay_Level,
				b.ID id_next_Classification_Specifics_Hay_Level,
				a.Hay_Level_Code,
				b.Hay_Level_Code next_Hay_Level_Code
				,ROW_NUMBER() over( partition by a.id order by b.[Order]) num
			FROM Engie_Buffer_Hay_Level a
			LEFT JOIN Engie_Buffer_Hay_Level b
				ON a.[Order] < b.[Order]
		)
		INSERT INTO #id_next_Hay_Level (id_Classification_Specifics_Hay_Level, id_next_Classification_Specifics_Hay_Level, Hay_Level_Code, next_Hay_Level_Code)
		SELECT
			id_Classification_Specifics_Hay_Level,
			id_next_Classification_Specifics_Hay_Level,
			Hay_Level_Code,
			next_Hay_Level_Code
		FROM next_Hay_Level
		WHERE num = 1 AND id_next_Classification_Specifics_Hay_Level IS NOT NULL

		UNION

		SELECT
			null id_Classification_Specifics_Hay_Level,
			mn.ID id_next_Classification_Specifics_Hay_Level,
			null,
			Hay_Level_Code next_Hay_Level_Code
		FROM (
			SELECT TOP(1)
				*
			FROM Engie_Buffer_Hay_Level
			ORDER BY [order] 
		) mn

		UNION 

		SELECT
			mx.ID id_Classification_Specifics_Hay_Level,
			mx.ID id_next_Classification_Specifics_Hay_Level,
			Hay_Level_Code,
			Hay_Level_Code next_Hay_Level_Code
		FROM (
			SELECT TOP(1)
				*
			FROM Engie_Buffer_Hay_Level
			ORDER BY [order] desc
		) mx

		INSERT INTO #temp_values_new_hay_level (id_step, id_ind, id_field, input_value, input_value_int, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			(SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_GW_Yearly_Campaign_GW_Promotion') AS id_ind,
			(SELECT id_field FROM k_m_fields WHERE code_field = 'GF_GW_New_Hay_Level') AS id_field,
			IIF(TRY_CONVERT(bit, v_check.input_value) = 1,hl.next_Hay_Level_Code,NULL) AS input_value,
			IIF(TRY_CONVERT(bit, v_check.input_value) = 1,hl.next_Hay_Level_Code,NULL) AS input_value_numeric,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_General_Salary_Review_Campaign_World',
			1,
			0
		FROM Engie_Cache_View_Process_General_Salary_Review_Campaign_World c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		INNER JOIN #id_next_Hay_Level hl
			ON ISNULL(c.Code_PositionHayLevel,-999999) = ISNULL(hl.Hay_Level_Code,-999999)
		INNER JOIN k_m_values v_check
			ON v_check.id_step = ps.id_step
			AND v_check.id_ind = (SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_GW_Yearly_Campaign_GW_Promotion')
			AND v_check.id_field = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_GW_Checkbox')
		WHERE c.ID_YearlyCampaign = (SELECT ID FROM Engie_Param_Yearly_Campaign WHERE ID_Status = 3)

		MERGE k_m_values AS tg
		USING #temp_values_new_hay_level AS sc
			ON sc.id_step = tg.id_step
			AND sc.id_ind = tg.id_ind
			AND sc.id_field = tg.id_field
		WHEN MATCHED AND COALESCE(sc.input_value_int, 0) <> COALESCE(tg.input_value_int, 0)
			THEN UPDATE
				SET input_value = sc.input_value,
					input_value_int = sc.input_value_int,
					input_date = sc.input_date,
					comment_value = sc.comment_value,
					id_user = sc.id_user
		WHEN NOT MATCHED
		THEN INSERT (id_ind, id_field, id_step, input_value, input_value_int, input_date, id_user, comment_value, source_value, value_type, idSim)
		VALUES (sc.id_ind, sc.id_field, sc.id_step, sc.input_value, sc.input_value_int, sc.input_date, sc.id_user, sc.comment_value, sc.source_value, sc.value_type, sc.idSim)
		OUTPUT		inserted.id_value
		  ,		inserted.id_ind
		  ,		inserted.id_field
		  ,		inserted.id_step
		  ,		inserted.input_value
		  ,		inserted.input_value_int
		  ,		inserted.input_value_numeric
		  ,		inserted.input_value_date
		  ,		inserted.input_date
		  ,		inserted.id_user
		  ,		inserted.comment_value
		  ,		inserted.source_value
		  ,		inserted.input_date
		  ,		inserted.id_user
		INTO Engie_k_m_values_histo (
					id_value
			   ,	id_ind
			   ,	id_field
			   ,	id_step
			   ,	input_value
			   ,	input_value_int
			   ,	input_value_numeric
			   ,	input_value_date
			   ,	input_date
			   ,	id_user
			   ,	comment_value
			   ,	source_value
			   ,	date_histo
			   ,	user_histo
			   );


		/*
			Update Effective Date from Salary Increase
		*/
		INSERT INTO #temp_values_effective_date (id_step, id_ind, id_field, input_value, input_value_date, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			(SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_GW_Yearly_Campaign_GW_Promotion') AS id_ind,
			(SELECT id_field FROM k_m_fields WHERE code_field = 'GF_GW_Effective_Date_Promo') AS id_field,
			CASE c.Label_WorkPlaceCountryCode -- (1)
				WHEN 'Italy' THEN '04/01/' + CAST(c.YearlyCampaign_Year + 1 as nvarchar(6)) + ' 01:00:00 AM'
				WHEN 'United States of America' THEN '03/01/' + CAST(c.YearlyCampaign_Year + 1 as nvarchar(6)) + ' 01:00:00 AM'
				ELSE '01/01/' + CAST(c.YearlyCampaign_Year + 1 as nvarchar(6)) + ' 01:00:00 AM'
			END AS input_value,
			--'01/01/' + CAST(c.YearlyCampaign_Year + 1 as nvarchar(6)) + ' 01:00:00 AM' AS input_value,
			CASE c.Label_WorkPlaceCountryCode -- (1)
				WHEN 'Italy' THEN CAST(c.YearlyCampaign_Year + 1 as nvarchar(6)) + '-04-01 01:00:00'
				WHEN 'United States of America' THEN CAST(c.YearlyCampaign_Year + 1 as nvarchar(6)) + '-03-01 01:00:00'
				ELSE CAST(c.YearlyCampaign_Year + 1 as nvarchar(6)) + '-01-01 01:00:00' 
			END AS input_value_date,
			--CAST(c.YearlyCampaign_Year + 1 as nvarchar(6)) + '-01-01 01:00:00' AS input_value_date,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_General_Salary_Review_Campaign_World',
			1,
			0
		FROM Engie_Cache_View_Process_General_Salary_Review_Campaign_World c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		INNER JOIN k_m_values v_check
			ON v_check.id_step = ps.id_step
			AND v_check.id_ind = (SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_GW_Yearly_Campaign_GW_Promotion')
			AND v_check.id_field = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_GW_Checkbox')
			AND TRY_CONVERT(bit, v_check.input_value) = 1
		WHERE c.ID_YearlyCampaign = (SELECT ID FROM Engie_Param_Yearly_Campaign WHERE ID_Status = 3)

		MERGE k_m_values AS tg
		USING #temp_values_effective_date AS sc
			ON sc.id_step = tg.id_step
			AND sc.id_ind = tg.id_ind
			AND sc.id_field = tg.id_field
		WHEN NOT MATCHED
		THEN INSERT (id_ind, id_field, id_step, input_value, input_value_date, input_date, id_user, comment_value, source_value, value_type, idSim)
		VALUES (sc.id_ind, sc.id_field, sc.id_step, sc.input_value, sc.input_value_date, sc.input_date, sc.id_user, sc.comment_value, sc.source_value, sc.value_type, sc.idSim)
		OUTPUT		inserted.id_value
		  ,		inserted.id_ind
		  ,		inserted.id_field
		  ,		inserted.id_step
		  ,		inserted.input_value
		  ,		inserted.input_value_int
		  ,		inserted.input_value_numeric
		  ,		inserted.input_value_date
		  ,		inserted.input_date
		  ,		inserted.id_user
		  ,		inserted.comment_value
		  ,		inserted.source_value
		  ,		inserted.input_date
		  ,		inserted.id_user
		INTO Engie_k_m_values_histo (
					id_value
			   ,	id_ind
			   ,	id_field
			   ,	id_step
			   ,	input_value
			   ,	input_value_int
			   ,	input_value_numeric
			   ,	input_value_date
			   ,	input_date
			   ,	id_user
			   ,	comment_value
			   ,	source_value
			   ,	date_histo
			   ,	user_histo
			   );

		DELETE v_eff_date
		FROM k_m_values v_eff_date
		INNER JOIN #temp_steps t
			ON t.id_step = v_eff_date.id_step
		LEFT JOIN k_m_values v_check
			ON v_check.id_step = t.id_step
			AND v_check.id_ind = (SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_GW_Yearly_Campaign_GW_Promotion')
			AND v_check.id_field = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_GW_Checkbox')
		WHERE COALESCE(TRY_CONVERT(bit, v_check.input_value), 0) = 0
		AND v_eff_date.id_ind = (SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_GW_Yearly_Campaign_GW_Promotion')
		AND v_eff_date.id_field = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_GW_Effective_Date_Promo')

		DECLARE @Effective_Date_Promotion_id_field int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_GW_Effective_Date_Promo')
		DECLARE @Promotion_id_ind int = (SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_GW_Yearly_Campaign_GW_Promotion')

		UPDATE v
			SET input_value = FORMAT(v.input_value_date, 'MM/dd/yyyy hh:mm:ss tt')
		FROM #temp_steps s
		INNER JOIN k_m_values v
			ON v.id_ind = @Promotion_id_ind
			AND v.id_field = @Effective_Date_Promotion_id_field
			AND v.id_step = s.id_step
		WHERE v.input_value_date IS NOT NULL
		AND FORMAT(v.input_value_date, 'MM/dd/yyyy hh:mm:ss tt') <> v.input_value

		EXEC dbo._sp_audit_procedure_log 'Procedure End', @procedure_name

		COMMIT TRANSACTION

    END TRY
    BEGIN CATCH
		IF (@@TRANCOUNT > 0)
		BEGIN
			ROLLBACK TRANSACTION
		END

		EXEC dbo._sp_audit_procedure_log 'Procedure Error', @procedure_name
	END CATCH

END
GO

