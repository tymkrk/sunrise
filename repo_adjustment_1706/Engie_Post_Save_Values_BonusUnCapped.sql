CREATE PROCEDURE [dbo].[Engie_Post_Save_Values_BonusUnCapped]
@kMValuesData AS [dbo].[Kernel_Type_k_m_values] READONLY
AS
/*
	Author: Rafal Jura
	Date: 2022-02-24
	Description: procedure refreshes values in Bonus Uncapped Campaign

Changes:

(1) - 02/06/2022 - Joanna Rokosz: max exceeded warning changes
(2) - 14/10/2022 - Joanna Rokosz: max exceeded commented out due to EGM requirements changes
(3) - 15/10/2022 - Anna Burczyn: Logic for MRT flag
(4) - 03/11/2022 - Anna Burczyn: Deferral Bonus Flag added
(5) - 16/11/2022 - Anna Burczyn: Deferral Bonus Flag - other currencies
(6) - 01/12/2022 - Rafal Jura: added parameter to _fn_mrt_flag function
(7) - 04/07/2023 - Rafal Jura: added logging values to Engie_k_m_values_histo
(8) - 15/09/2023 - Przemyslaw Kot: fix issue for NULL values in input_value column in #temp_values_MRT_flag temp table
(9) - 27/10/2023 - Rafal Jura: changed format of Pct column
(10) - 23/02/2024 - Patryk Skiba: New ASF should not be used, only Current ASF when calculating Total Comp and MRT ZD#103517
(11) - 22-05-2024 - Tymek Kruk - Bonus in Employee Currency should be round up
(12) - 29-05-2024 - Kamil Roganowicz: logic for ASF
(13) - 14-06-2024 - Kamil Roganowicz: ENG-89 change denominator in GF_BUC_Pourcentage_Bonus calculation
(14) - 05-08-2024 - Rafal Jura: ENG-167 fixed calculations of Pct - changed to Base Salary without Prorata
(15) - 06-02-2025 - Kamil Roganowicz: ENG-296 changed logic for MRT and Deferred Flag

*/
BEGIN
	DECLARE @procedure_name nvarchar(255) = OBJECT_NAME(@@PROCID)

	EXEC dbo._sp_audit_procedure_log 'Procedure Start', @procedure_name

	BEGIN TRY
		BEGIN TRANSACTION

		--DECLARE @kMValuesData AS [dbo].[Kernel_Type_k_m_values]
		
		DECLARE @id_plan int = (SELECT id_plan FROM k_m_plans WHERE name_plan LIKE '%Bonus Uncapped')
		DECLARE @id_yearly_campaign int = (SELECT ID FROM Engie_Param_Yearly_Campaign WHERE ID_Status IN (2,3))

		DECLARE @id_ind_GF_BUC_Yearly_Campaign_BUC_Bonus int = (SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_BUC_Yearly_Campaign_BUC_Bonus') 
		DECLARE @id_ind_GF_BUC_Yearly_Campaign_BUC_Salary int = (SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_BUC_Yearly_Campaign_BUC_Salary')
		DECLARE @id_ind_GF_BUC_Yearly_Campaign_BUC_ASF int = (SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_BUC_Yearly_Campaign_BUC_ASF') 
		DECLARE @id_ind_GF_BUC_Yearly_Campaign_BUC_Total_Comp int = (SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_BUC_Yearly_Campaign_BUC_Total_Comp')
		DECLARE @id_ind_GF_BUC_MRT_Flag int = (SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_BUC_MRT_Flag') 

		DECLARE @id_field_GF_BUC_Bonus_Amount int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_BUC_Bonus_Amount')
		DECLARE @id_field_GF_BUC_Pourcentage_Bonus int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_BUC_Pourcentage_Bonus')
		DECLARE @id_field_GF_BUC_Pourcentage_Bonus_Proposal int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_BUC_Pourcentage_Bonus_Proposal')
		DECLARE @id_field_GF_BUC_Salary_N1_Prorata int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_BUC_Salary_N1_Prorata')
		DECLARE @id_field_GF_BUC_Final_Bonus_In_Employee_Currency int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_BUC_Final_Bonus_In_Employee_Currency')
		DECLARE @id_field_GF_BUC_Bonus int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_BUC_Bonus')
		DECLARE @id_field_GF_BUC_ASF int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_BUC_ASF')
		DECLARE @id_field_GF_BUC_Total_Comp int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_BUC_Total_Comp')
		DECLARE @id_field_GF_BUC_Total_Comp_EUR int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_BUC_Total_Comp_EUR')
		DECLARE @id_field_GF_BUC_MRT_Flag int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_BUC_MRT_Flag')
		DECLARE @id_field_GF_BUC_Deferral_Flag int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_BUC_Deferral_Flag')

		DROP TABLE IF EXISTS #temp_steps
		DROP TABLE IF EXISTS #temp_values_bonus_amount
		DROP TABLE IF EXISTS #temp_values_current_base_salary_eur
		DROP TABLE IF EXISTS #temp_values_pct_bonus
		DROP TABLE IF EXISTS #temp_values_pct_bonus_incl_exceptional_bonus
		DROP TABLE IF EXISTS #temp_values_final_bonus
		DROP TABLE IF EXISTS #temp_values_final_bonus_in_eur
		DROP TABLE IF EXISTS #temp_values_max_exceed_msg
		DROP TABLE IF EXISTS #temp_values_final_total_comp
		DROP TABLE IF EXISTS #temp_values_final_total_comp_in_eur
		DROP TABLE IF EXISTS #temp_values_MRT_flag
		DROP TABLE IF EXISTS #temp_values_Deferral_flag
		DROP TABLE IF EXISTS #temp_values_new_asf_in_employee_currency

		CREATE TABLE #temp_steps (
			id_step int
		)

		IF NOT EXISTS(SELECT * FROM @kMValuesData)
		BEGIN
			INSERT INTO #temp_steps
			SELECT DISTINCT
				ps.id_step
			FROM k_m_plans_payees_steps ps
			WHERE ps.id_plan = @id_plan
		END
		ELSE
		BEGIN
			INSERT INTO #temp_steps
			SELECT DISTINCT
				id_step
			FROM @kMValuesData
		END


		CREATE TABLE #temp_values_bonus_amount (
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

		CREATE TABLE #temp_values_current_base_salary_eur (
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

		CREATE TABLE #temp_values_pct_bonus (
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

		CREATE TABLE #temp_values_pct_bonus_incl_exceptional_bonus (
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

		CREATE TABLE #temp_values_final_bonus (
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

		CREATE TABLE #temp_values_final_bonus_in_eur (
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

		CREATE TABLE #temp_values_max_exceed_msg (
			id_step int,
			id_ind int,
			id_field int,
			input_value nvarchar(MAX),
			input_date datetime,
			id_user int,
			comment_value nvarchar(200),
			source_value nvarchar(200),
			value_type int,
			idSim int
		)

		CREATE TABLE #temp_values_final_total_comp (
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

		CREATE TABLE #temp_values_final_total_comp_in_eur (
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

		CREATE TABLE #temp_values_MRT_flag (
			id_step int,
			id_ind int,
			id_field int,
			input_value nvarchar(MAX),
			input_date datetime,
			id_user int,
			comment_value nvarchar(200),
			source_value nvarchar(200),
			value_type int,
			idSim int
		)
		
		CREATE TABLE #temp_values_Deferral_flag (
			id_step int,
			id_ind int,
			id_field int,
			input_value nvarchar(MAX),
			input_date datetime,
			id_user int,
			comment_value nvarchar(200),
			source_value nvarchar(200),
			value_type int,
			idSim int
		)
		
		CREATE TABLE #temp_values_new_asf_in_employee_currency (
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

		/*
			Update Current Base Salary in EUR with prorata in Salary
		*/
		INSERT INTO #temp_values_current_base_salary_eur (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GF_BUC_Yearly_Campaign_BUC_Salary AS id_ind,
			@id_field_GF_BUC_Salary_N1_Prorata AS id_field,
			CAST(CAST(c.BaseSalary * c.Final_Prorata * COALESCE(cur.ExchangeRatefor1EUR, 1) AS DECIMAL(18,4)) AS NVARCHAR(100)) AS input_value,
			CAST(c.BaseSalary * c.Final_Prorata * COALESCE(cur.ExchangeRatefor1EUR, 1) AS DECIMAL(18,4)) AS input_value_numeric,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_BonusUnCapped',
			1,
			0
		FROM Engie_Cache_View_Process_BonusUncapped c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		LEFT JOIN (SELECT
						exR.exchangeRatefor1EUR,
						exR.currency,
						exr.EffectiveDate,
						row_number() over(partition by exR.Family order by exR.EffectiveDate desc)  as rn
					FROM  Engie_Exchange_Rates exR
				) as cur
			ON cur.rn = 1
			AND c.Code_Currency = cur.currency
			AND c.YearlyCampaign_Effective_Date >= cur.EffectiveDate

		MERGE k_m_values AS tg
		USING #temp_values_current_base_salary_eur AS sc
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
			Update Bonus value -- (11)
		*/
		INSERT INTO #temp_values_bonus_amount (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GF_BUC_Yearly_Campaign_BUC_Bonus AS id_ind,
			@id_field_GF_BUC_Bonus_Amount AS id_field,
			CAST([dbo].[_fn_round_up](v_am.input_value_numeric,2) as NVARCHAR(100))  AS input_value,
			[dbo].[_fn_round_up](v_am.input_value_numeric,2) AS input_value_numeric,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_BonusUnCapped',
			1,
			0
		FROM Engie_Cache_View_Process_BonusUncapped c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		INNER JOIN k_m_values v_am
			ON v_am.id_step = ps.id_step
			AND v_am.id_ind = @id_ind_GF_BUC_Yearly_Campaign_BUC_Bonus
			AND v_am.id_field = @id_field_GF_BUC_Bonus_Amount
		WHERE c.ID_YearlyCampaign = @id_yearly_campaign

		MERGE k_m_values AS tg
		USING #temp_values_bonus_amount AS sc
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
			Update Pct from Bonus
		*/
		INSERT INTO #temp_values_pct_bonus (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GF_BUC_Yearly_Campaign_BUC_Bonus AS id_ind,
			@id_field_GF_BUC_Pourcentage_Bonus AS id_field,
			CAST(CAST(COALESCE((v_am.input_value_numeric / (NULLIF(((ISNULL(c.BaseSalary,0) * c.Final_Prorata) + ISNULL(c.Current_ASF,0)), 0))), 0) AS DECIMAL(18,4)) AS NVARCHAR(100)) AS input_value,
			CAST(COALESCE((v_am.input_value_numeric / (NULLIF((ISNULL(c.BaseSalary,0) + ISNULL(c.Current_ASF,0)), 0))), 0) AS DECIMAL(18,4)) AS input_value_numeric,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_BonusUnCapped',
			1,
			0
		FROM Engie_Cache_View_Process_BonusUncapped c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		INNER JOIN k_m_values v_am
			ON v_am.id_step = ps.id_step
			AND v_am.id_ind = @id_ind_GF_BUC_Yearly_Campaign_BUC_Bonus
			AND v_am.id_field = @id_field_GF_BUC_Bonus_Amount
		WHERE c.ID_YearlyCampaign = @id_yearly_campaign

		MERGE k_m_values AS tg
		USING #temp_values_pct_bonus AS sc
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
			Update Pct from Bonus (Incl. excp. bonus)
		*/
		INSERT INTO #temp_values_pct_bonus_incl_exceptional_bonus (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GF_BUC_Yearly_Campaign_BUC_Bonus AS id_ind,
			@id_field_GF_BUC_Pourcentage_Bonus_Proposal AS id_field,
			CAST(CAST(COALESCE((v_am.input_value_numeric / (NULLIF((COALESCE(c.Current_ASF, 0) + c.BaseSalary), 0))), 0) AS DECIMAL(18,4)) AS NVARCHAR(100)) AS input_value,
			CAST(COALESCE((v_am.input_value_numeric / (NULLIF((COALESCE(c.Current_ASF, 0) + c.BaseSalary), 0))), 0) AS DECIMAL(18,4)) AS input_value_numeric,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_BonusUnCapped',
			1,
			0
		FROM Engie_Cache_View_Process_BonusUncapped c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		INNER JOIN k_m_values v_am
			ON v_am.id_step = ps.id_step
			AND v_am.id_ind = @id_ind_GF_BUC_Yearly_Campaign_BUC_Bonus
			AND v_am.id_field = @id_field_GF_BUC_Bonus_Amount
		WHERE c.ID_YearlyCampaign = @id_yearly_campaign

		MERGE k_m_values AS tg
		USING #temp_values_pct_bonus_incl_exceptional_bonus AS sc
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
			Update Final Bonus from Bonus
		*/
		INSERT INTO #temp_values_final_bonus (id_step, id_ind, id_field, input_value, input_value_int, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GF_BUC_Yearly_Campaign_BUC_Bonus AS id_ind,
			@id_field_GF_BUC_Final_Bonus_In_Employee_Currency AS id_field,
			CAST(v_am.input_value_numeric AS NVARCHAR(100)) AS input_value,
			v_am.input_value_numeric AS input_value_int,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_BonusUnCapped',
			1,
			0
		FROM Engie_Cache_View_Process_BonusUncapped c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		INNER JOIN k_m_values v_am
			ON v_am.id_step = ps.id_step
			AND v_am.id_ind = @id_ind_GF_BUC_Yearly_Campaign_BUC_Bonus
			AND v_am.id_field = @id_field_GF_BUC_Bonus_Amount
		WHERE c.ID_YearlyCampaign = @id_yearly_campaign

		MERGE k_m_values AS tg
		USING #temp_values_final_bonus AS sc
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
			Update Final Bonus in Eur from Bonus
		*/
		INSERT INTO #temp_values_final_bonus_in_eur (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GF_BUC_Yearly_Campaign_BUC_Bonus AS id_ind,
			@id_field_GF_BUC_Bonus AS id_field,
			CAST(CAST(v_am.input_value_numeric * ISNULL(cur.exchangeRatefor1EUR, 1) AS DECIMAL(18,4)) AS NVARCHAR(100)) AS input_value,
			v_am.input_value_numeric * ISNULL(cur.exchangeRatefor1EUR, 1) AS input_value_numeric,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_BonusUnCapped',
			1,
			0
		FROM Engie_Cache_View_Process_BonusUncapped c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		INNER JOIN k_m_values v_am
			ON v_am.id_step = ps.id_step
			AND v_am.id_ind = @id_ind_GF_BUC_Yearly_Campaign_BUC_Bonus
			AND v_am.id_field = @id_field_GF_BUC_Bonus_Amount
		LEFT JOIN (SELECT
						exR.exchangeRatefor1EUR,
	                    exR.currency,
						exr.EffectiveDate,
						row_number() over(partition by exR.Family order by exR.EffectiveDate desc)  as rn
					FROM  Engie_Exchange_Rates exR
				) as cur
			ON cur.rn = 1
			AND c.Code_Currency = cur.currency
			AND c.YearlyCampaign_Effective_Date >= cur.EffectiveDate 
		WHERE c.ID_YearlyCampaign = @id_yearly_campaign

		MERGE k_m_values AS tg
		USING #temp_values_final_bonus_in_eur AS sc
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
			Update Max Exceeded from Bonus
		*/
		--INSERT INTO #temp_values_max_exceed_msg (id_step, id_ind, id_field, input_value, input_date, id_user, comment_value, source_value, value_type, idSim)
		--SELECT
		--	ps.id_step,
		--	(SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_BUC_Yearly_Campaign_BUC_Bonus') AS id_ind,
		--	(SELECT id_field FROM k_m_fields WHERE code_field = 'GF_BUC_Warning_Message') AS id_field,
		--	CASE
		--		WHEN (COALESCE(c.BonusRangeMaximum, 0) * 100 < v_pct.input_value_numeric AND c.BonusRangeMaximum IS NOT NULL)
		--			OR (br.Regulation_Value < v_pct.input_value_numeric  AND ISNULL(c.RiskTakers, '') <> '' AND c.EGM_cond = 1)
		--			OR (tcomp_limit.Regulation_Value < COALESCE(tcomp_eur.input_value_numeric, tcomp_eur.input_value_int, tcomp_eur.input_value,0) AND ISNULL(c.RiskTakers, '') = ''  AND c.EGM_cond = 1)
		--		THEN 'Yes'
		--		ELSE 'No'
		--	END AS input_value,
		--	GETUTCDATE(),
		--	-1 AS id_user,
		--	'Automatically Insert',
		--	'Engie_Post_Save_Values_BonusUnCapped',
		--	1,
		--	0
		--FROM Engie_Cache_View_Process_BonusUncapped c
		--INNER JOIN k_m_plans_payees_steps ps
		--	ON ps.id_payee = c.idPayee
		--	AND ps.id_plan = @id_plan
		--INNER JOIN #temp_steps t
		--	ON t.id_step = ps.id_step
		--INNER JOIN k_m_values v_pct
		--	ON v_pct.id_step = ps.id_step
		--	AND v_pct.id_ind = (SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_BUC_Yearly_Campaign_BUC_Bonus')
		--	AND v_pct.id_field = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_BUC_Pourcentage_Bonus')
		--LEFT JOIN k_m_values tcomp_eur
		--	ON tcomp_eur.id_step = ps.id_step
		--	AND tcomp_eur.id_ind = (SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GF_BUC_Yearly_Campaign_BUC_Total_Comp')
		--	AND tcomp_eur.id_field = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_BUC_Total_Comp_EUR')
		--LEFT JOIN Engie_Param_Bonus_Regulations br
		--	ON br.Regulation_Name = 'Bonus_Limit'
		--LEFT JOIN Engie_Param_Bonus_Regulations tcomp_limit
		--	ON tcomp_limit.Regulation_Name = 'TCOMP_Limit'
		--WHERE c.ID_YearlyCampaign = (SELECT ID FROM Engie_Param_Yearly_Campaign WHERE ID_Status = 3)

		--MERGE k_m_values AS tg
		--USING #temp_values_max_exceed_msg AS sc
		--	ON sc.id_step = tg.id_step
		--	AND sc.id_ind = tg.id_ind
		--	AND sc.id_field = tg.id_field
		--WHEN MATCHED AND COALESCE(sc.input_value, '') <> COALESCE(tg.input_value, '')
		--	THEN UPDATE
		--		SET input_value = sc.input_value,
		--			input_date = sc.input_date,
		--			comment_value = sc.comment_value,
		--			id_user = sc.id_user
		--WHEN NOT MATCHED
		--THEN INSERT (id_ind, id_field, id_step, input_value, input_date, id_user, comment_value, source_value, value_type, idSim)
		--VALUES (sc.id_ind, sc.id_field, sc.id_step, sc.input_value, sc.input_date, sc.id_user, sc.comment_value, sc.source_value, sc.value_type, sc.idSim);

		/*

		*/

		
		/*
			Update ASF
		*/
		INSERT INTO #temp_values_new_asf_in_employee_currency (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GF_BUC_Yearly_Campaign_BUC_ASF AS id_ind,
			@id_field_GF_BUC_ASF AS id_field,
			CAST(c.Current_ASF AS NVARCHAR(100)) AS input_value, 
			c.Current_ASF AS input_value_numeric,
			GETUTCDATE() AS input_date,
			-1 AS id_user,
			'Automatically Insert' AS comment_value,
			'Engie_Post_Save_Values_BonusUnCapped' AS source_value,
			1 AS value_type,
			0 AS idSim
		FROM Engie_Cache_View_Process_BonusUncapped c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		WHERE c.ID_YearlyCampaign = @id_yearly_campaign

		MERGE k_m_values AS tg
		USING #temp_values_new_asf_in_employee_currency AS sc
			ON sc.id_step = tg.id_step
			AND sc.id_ind = tg.id_ind
			AND sc.id_field = tg.id_field
		WHEN MATCHED AND ISNULL(sc.input_value,'') <> ISNULL(tg.input_value,'') AND tg.id_user = -1
			THEN UPDATE
				SET input_value = sc.input_value,
					input_date = sc.input_date,
					comment_value = sc.comment_value,
					id_user = sc.id_user
		WHEN NOT MATCHED
		THEN INSERT (id_ind, id_field, id_step, input_value, input_date, id_user, comment_value, source_value, value_type, idSim)
		VALUES (sc.id_ind, sc.id_field, sc.id_step, sc.input_value, sc.input_date, sc.id_user, sc.comment_value, sc.source_value, sc.value_type, sc.idSim)
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


		DROP TABLE IF EXISTS #temp_bonus_ASF
		CREATE TABLE #temp_bonus_ASF (
			id_step int,
			value_bonus_amount decimal(18,4),
			value_new_ASF decimal(18,4)
		)

		DROP TABLE IF EXISTS #temp_final_bonus_ASF
		CREATE TABLE #temp_final_bonus_ASF (
			id_step int,
			BaseSalary int,
			value_bonus_amount decimal(18,4),
			value_new_ASF decimal(18,4),
			exchangeRatefor1EUR decimal(18,4)
		)

		INSERT INTO #temp_bonus_ASF (id_step, value_bonus_amount, value_new_ASF)
		SELECT
			a.id_step,
			SUM(a.value_bonus_amount) AS value_bonus_amount,
			SUM(a.value_new_ASF) AS value_new_ASF
		FROM (
			SELECT
				v_b_am.id_step,
				v_b_am.input_value_numeric AS value_bonus_amount,
				NULL AS value_new_ASF
			FROM k_m_values v_b_am
			INNER JOIN #temp_steps t
				ON t.id_step = v_b_am.id_step
			WHERE v_b_am.id_ind =  @id_ind_GF_BUC_Yearly_Campaign_BUC_Bonus
			AND v_b_am.id_field =  @id_field_GF_BUC_Bonus_Amount

			UNION

			SELECT
				v_asf.id_step,
				NULL AS value_bonus_amount,
				v_asf.input_value_numeric  AS value_new_ASF
			FROM k_m_values v_asf
			INNER JOIN #temp_steps t
				ON t.id_step = v_asf.id_step
			WHERE v_asf.id_ind =  @id_ind_GF_BUC_Yearly_Campaign_BUC_ASF
			AND v_asf.id_field = @id_field_GF_BUC_ASF
		) a
		GROUP BY a.id_step

		INSERT INTO #temp_final_bonus_ASF (id_step, BaseSalary, value_bonus_amount, value_new_ASF, exchangeRatefor1EUR)
		SELECT
			ps.id_step,
			CEILING(c.BaseSalary) AS base_salary,
			t.value_bonus_amount AS value_bonus_amount,
			COALESCE(c.Current_ASF, 0) AS value_new_ASF,	--(10)
			COALESCE(exchangeRatefor1EUR, 1) AS exchangeRatefor1EUR
		FROM Engie_Cache_View_Process_BonusUncapped c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_bonus_ASF t
			ON t.id_step = ps.id_step
		LEFT JOIN (SELECT
						exR.exchangeRatefor1EUR,
	                    exR.currency,
						exr.EffectiveDate,
						row_number() over(partition by exR.Family order by exR.EffectiveDate desc)  as rn
					FROM  Engie_Exchange_Rates exR
				) as cur
			ON cur.rn = 1
			AND c.Code_Currency = cur.currency
			AND c.YearlyCampaign_Effective_Date >= cur.EffectiveDate

		INSERT INTO #temp_values_final_total_comp (id_step, id_ind, id_field, input_value, input_value_int, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			id_step,
			@id_ind_GF_BUC_Yearly_Campaign_BUC_Total_Comp AS id_ind,
			@id_field_GF_BUC_Total_Comp AS id_field,
			CAST(CAST(BaseSalary + COALESCE(value_new_ASF, 0) + COALESCE(value_bonus_amount, 0) AS int) as nvarchar(max)) AS input_value,
			CAST(BaseSalary + COALESCE(value_new_ASF, 0) + COALESCE(value_bonus_amount, 0) AS int) AS input_value_int,
			GETUTCDATE() AS input_date,
			-1 AS id_user,
			'Automatically Insert' AS comment_value,
			'Engie_Post_Save_Values_BonusUnCapped' AS source_value,
			1 AS value_type,
			0 AS idSim
		FROM #temp_final_bonus_ASF

		MERGE k_m_values AS tg
		USING #temp_values_final_total_comp AS sc
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

		INSERT INTO #temp_values_final_total_comp_in_eur (id_step, id_ind, id_field, input_value, input_value_int, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			id_step,
			@id_ind_GF_BUC_Yearly_Campaign_BUC_Total_Comp AS id_ind,
			@id_field_GF_BUC_Total_Comp_EUR AS id_field,
			CAST(CAST((BaseSalary + COALESCE(value_new_ASF, 0) + COALESCE(value_bonus_amount, 0)) * COALESCE(exchangeRatefor1EUR, 1) AS int) as nvarchar(max)) AS input_value,
			CAST((BaseSalary + COALESCE(value_new_ASF, 0) + COALESCE(value_bonus_amount, 0)) * COALESCE(exchangeRatefor1EUR, 1) AS int) AS input_value_int,
			GETUTCDATE() AS input_date,
			-1 AS id_user,
			'Automatically Insert' AS comment_value,
			'Engie_Post_Save_Values_BonusUnCapped' AS source_value,
			1 AS value_type,
			0 AS idSim
		FROM #temp_final_bonus_ASF

		MERGE k_m_values AS tg
		USING #temp_values_final_total_comp_in_eur AS sc
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
			Update MRT Flag from Bonus and ASF	--(3)
		*/
		INSERT INTO #temp_values_MRT_flag (id_step, id_ind, id_field, input_value, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GF_BUC_MRT_Flag AS id_ind,
			@id_field_GF_BUC_MRT_Flag AS id_field,
			CASE WHEN 
			[dbo].[_fn_mrt_flag](ps.id_payee, 'Uncapped') != '' 
			THEN 
			[dbo].[_fn_mrt_flag](ps.id_payee, 'Uncapped')
			ELSE 
			NULL
			END AS input_value,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_BonusUnCapped',
			1,
			0
		FROM Engie_Cache_View_Process_BonusUncapped c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
	/*	INNER JOIN k_m_values v_am
			ON v_am.id_step = ps.id_step
			AND v_am.id_ind = (SELECT id_ind FROM k_m_indicators WHERE name_ind =  'GF_BUC_Yearly_Campaign_BUC_Bonus')
			AND v_am.id_field = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_BUC_Bonus_Amount')*/
		WHERE c.ID_YearlyCampaign = @id_yearly_campaign

		UPDATE mrt_flag
		SET input_value = NULL
		,	comment_value = 'Automatically Update - excluded MRT'
		FROM #temp_values_MRT_flag mrt_flag
		INNER JOIN k_m_plans_payees_steps ps
			ON mrt_flag.id_step = ps.id_step
		INNER JOIN Engie_View_MRT_Exclude_Validation exclude
			ON ps.id_payee = exclude.id_payee


		MERGE k_m_values AS tg
		USING #temp_values_MRT_flag AS sc
			ON sc.id_step = tg.id_step
			AND sc.id_ind = tg.id_ind
			AND sc.id_field = tg.id_field
		WHEN MATCHED AND ISNULL(sc.input_value,'') <> ISNULL(tg.input_value,'')
			THEN UPDATE
				SET input_value = sc.input_value,
					input_date = sc.input_date,
					comment_value = sc.comment_value,
					id_user = sc.id_user
		WHEN NOT MATCHED
		THEN INSERT (id_ind, id_field, id_step, input_value, input_date, id_user, comment_value, source_value, value_type, idSim)
		VALUES (sc.id_ind, sc.id_field, sc.id_step, sc.input_value, sc.input_date, sc.id_user, sc.comment_value, sc.source_value, sc.value_type, sc.idSim)
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
			Update Deferral Flag	--(4)
		*/
		INSERT INTO #temp_values_Deferral_flag (id_step, id_ind, id_field, input_value, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GF_BUC_MRT_Flag AS id_ind,
			@id_field_GF_BUC_Deferral_Flag AS id_field,
			CASE
				WHEN v_mrt.input_value = 'Non-MRT' THEN 'Bonus deferred, refer to Bonus Scheme Report'
				WHEN (v_mrt.input_value = 'MRT - Ex-post' OR v_mrt.input_value = 'MRT - Ex-ante') AND 
					(COALESCE(v_bon.input_value_numeric, v_bon.input_value,0)>50000 OR COALESCE(v_bon.input_value_numeric, v_bon.input_value,0) > 0.25*(c.BaseSalary+COALESCE(c.Current_ASF,0)+COALESCE(v_bon.input_value_numeric, v_bon.input_value,0))) THEN 'Bonus deferred, refer to Bonus Scheme Report'		--(5)
			END AS input_value,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_BonusUnCapped',
			1,
			0
		FROM Engie_Cache_View_Process_BonusUncapped c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		INNER JOIN k_m_values v_bon
			ON v_bon.id_step = ps.id_step
			AND v_bon.id_ind = @id_ind_GF_BUC_Yearly_Campaign_BUC_Bonus
			AND v_bon.id_field = @id_field_GF_BUC_Final_Bonus_In_Employee_Currency
		--LEFT JOIN k_m_values v_asf		--(10)
		--	ON v_asf.id_step = ps.id_step
		--	AND v_asf.id_ind = (SELECT id_ind FROM k_m_indicators WHERE name_ind =  'GF_BUC_Yearly_Campaign_BUC_ASF')
		--	AND v_asf.id_field = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_BUC_ASF')
		LEFT JOIN k_m_values v_mrt
			ON v_mrt.id_step = ps.id_step
			AND v_mrt.id_ind = @id_ind_GF_BUC_MRT_Flag
			AND v_mrt.id_field = @id_field_GF_BUC_MRT_Flag
		LEFT JOIN (SELECT
					exR.exchangeRatefor1EUR,
					exR.currency,
					exr.EffectiveDate,
					row_number() over(partition by exR.Family order by exR.EffectiveDate desc)  as rn
					FROM  Engie_Exchange_Rates exR
					) as cur
			ON cur.rn = 1
			AND c.Code_Currency = cur.currency
			AND c.YearlyCampaign_Effective_Date >= cur.EffectiveDate
		WHERE c.ID_YearlyCampaign = @id_yearly_campaign


		UPDATE def_flag
		SET input_value = NULL
		,	comment_value = 'Automatically Update - excluded deferral flag'
		FROM #temp_values_Deferral_flag def_flag
		INNER JOIN k_m_plans_payees_steps ps
			ON def_flag.id_step = ps.id_step
		INNER JOIN Engie_View_MRT_Exclude_Validation exclude
			ON ps.id_payee = exclude.id_payee


		MERGE k_m_values AS tg
		USING #temp_values_Deferral_flag AS sc
			ON sc.id_step = tg.id_step
			AND sc.id_ind = tg.id_ind
			AND sc.id_field = tg.id_field
		WHEN MATCHED AND COALESCE(sc.input_value,'') <> COALESCE(tg.input_value,'')
			THEN UPDATE
				SET input_value = sc.input_value,
					input_date = sc.input_date,
					comment_value = sc.comment_value,
					id_user = sc.id_user
		WHEN NOT MATCHED
		THEN INSERT (id_ind, id_field, id_step, input_value, input_date, id_user, comment_value, source_value, value_type, idSim)
		VALUES (sc.id_ind, sc.id_field, sc.id_step, sc.input_value, sc.input_date, sc.id_user, sc.comment_value, sc.source_value, sc.value_type, sc.idSim)
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

