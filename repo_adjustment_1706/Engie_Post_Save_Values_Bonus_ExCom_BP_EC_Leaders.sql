CREATE PROCEDURE [dbo].[Engie_Post_Save_Values_Bonus_ExCom_BP_EC_Leaders]
@kMValuesData AS [dbo].[Kernel_Type_k_m_values] READONLY
AS
/*
	Author: Rafal Jura
	Date: 2022-02-24
	Description: procedure refreshes values in Bonus Excom Campaign

Changes:

(1) - 02/06/2022 - Joanna Rokosz: max exceeded warning changes
(2) - 12/07/2022 - Tymek Kruk: section 'Update Max Exceeded from Bonus' commented out
(3) - 14/10/2022 - Joanna Rokosz: max exceeded bonus changes - only Bonus Rage considered (EGM requirements change)
(4) - 14/10/2022 - Anna Burczyn: Logic for MRT flag
(5) - 03/11/2022 - Anna Burczyn: Deferral Bonus Flag added
(6) - 16/11/2022 - Anna Burczyn: Deferral Bonus Flag - other currencies
(7) - 01/12/2022 - Rafal Jura: added parameter to _fn_mrt_flag function
(8) - 04/07/2023 - Rafal Jura: added logging values to Engie_k_m_values_histo
(9) - 06-09-2023 - Maciej Srodulski: Changes to Campaign [EN-80]
(10) - 15-09-2023 - Przemyslaw Kot: fix issue for NULL values in input_value column in #temp_values_MRT_flag temp table
(11) - 29-09-2023 - Przemyslaw Kot: replace GR_BEC_Bonus_Amount with GR_BEC_Bonus_Amount_Proposal while inserting into #temp_bonus_ASF table,
									add ROUND func for numeric data insert into #temp_values_final_total_comp and #temp_values_final_total_comp_in_eur temp tables,
									correct calculation for Base_Salary in #temp_final_bonus_ASF temp table, use New Base Salary from Base Pay Review campaigns, instead of Current Base Salary
(12) - 30-11-2023 - Rafal Jura: added missing calculations of Total bonus amount in employee currency,  Total bonus amount in EUR,
								% Bonus (Excl. Exceptional Bonus) and Bonus amount in Employee Currency (Excl. Exceptional Bonus) fields
(13) - 23/02/2024 - Patryk Skiba: New ASF should not be used, only Current ASF when calculating Total Comp and MRT ZD#103517
(14) - 07/03/2024 - Mateusz Paluch: changing source for base_salary renamed value_new_ASF to value_current_ASF
(15) - 18/03/2024 - Mateusz Paluch - ZD#104811 - getting rid of multiplication by 100 for BonusRangeMaximum in calculating bonus exceeded message,
	changed "<" sign to "<=" and BonusRangeMaximum will compared now to Bonus % proposed
(16) - 22-05-2024 - Tymek Kruk - Bonus in Employee Currency should be round up
(17) - 29-05-2024 - Kamil Roganowicz: logic for ASF
(18) - 13-06-2024 - Kamil Roganowicz: ENG-89 change denominator in GR_BEC_Bonus_Percent_Proposal calculation
(19) - 04-07-2024 - Rafal Jura: ENG-117  % Bonus (Excl. Exceptional Bonus), % Bonus (Excl. Exceptional Bonus), Bonus Amount in Employee Currency (Excl. Exceptional Bonus) should be NULL by default not 0
(20) 05-08-2024 - Rafal Jura: ENG-167 fixed calculations of % Bonus (Incl. Exceptional Bonus) - changed to Base Salary without Prorata
(21) - 12-09-2024 - Rafal Jura: ENG-218 fixed calculations of % Bonus (Excl. Exceptional Bonus) - use base Salary without Prorata and Current ASF
(22) 06-02-2025 - Kamil Roganowicz: ENG-296 changed logic for MRT and Deferred Flag

*/
BEGIN
	DECLARE @procedure_name nvarchar(255) = OBJECT_NAME(@@PROCID)

	EXEC dbo._sp_audit_procedure_log 'Procedure Start', @procedure_name

	BEGIN TRY
		BEGIN TRANSACTION

		--DECLARE @kMValuesData AS [dbo].[Kernel_Type_k_m_values]
		
		DECLARE @id_plan int = (SELECT id_plan FROM k_m_plans WHERE name_plan LIKE '%Bonus ExCom BP EC Leaders')
		DECLARE @id_yearly_campaign int = (SELECT ID FROM Engie_Param_Yearly_Campaign WHERE ID_Status IN (2,3))

		DECLARE @id_plan_World int = (SELECT id_plan FROM k_m_plans WHERE name_plan LIKE '%Base Pay Review World')
		DECLARE @id_plan_Engie_SA int = (SELECT id_plan FROM k_m_plans WHERE name_plan LIKE '%Base Pay Review ENGIE SA')
		DECLARE @id_plan_Italy int = (SELECT id_plan FROM k_m_plans WHERE name_plan LIKE '%Base Pay Review Italy')
		DECLARE @id_field_New_Base_Salary_World INT = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_GW_Final_Revised_Salary')
		DECLARE @id_field_New_Base_Salary_Engie_SA INT = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_ESA_NewBaseSalary')
		DECLARE @id_field_New_Base_Salary_Italy INT = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_IE_Final_Revised_Salary')

		DECLARE @id_ind_GR_Yearly_Campaign_BEC_Bonus int = (SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GR_Yearly_Campaign_BEC_Bonus')
		DECLARE @id_ind_GR_Yearly_Campaign_BEC_Salary int = (SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GR_Yearly_Campaign_BEC_Salary')
		DECLARE @id_ind_GR_BEC_MRT_Flag int = (SELECT id_ind FROM k_m_indicators WHERE name_ind = 'GR_BEC_MRT_Flag')

		DECLARE @id_field_GR_BEC_Final_Bonus int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GR_BEC_Final_Bonus')
		DECLARE @id_field_GR_BEC_Bonus_Amount_Proposal int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GR_BEC_Bonus_Amount_Proposal')
		DECLARE @id_field_GR_BEC_Bonus_EUR int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GR_BEC_Bonus_EUR')
		DECLARE @id_field_GR_BEC_Salary_Prorata_EC int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GR_BEC_Salary_Prorata_EC')
		DECLARE @id_field_GR_BEC_Salary_Prorata int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GR_BEC_Salary_Prorata')
		DECLARE @id_field_GR_BEC_Bonus_Percent int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GR_BEC_Bonus_Percent')
		DECLARE @id_field_GR_BEC_Bonus_Amount int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GR_BEC_Bonus_Amount')
		DECLARE @id_field_GF_BEC_ExceptionalBonus int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_BEC_ExceptionalBonus')
		DECLARE @id_field_GF_BEC_Bonus_Amount_Proposal int  = (SELECT id_field FROM k_m_fields WHERE code_field = 'GR_BEC_Bonus_Amount_Proposal') 
		DECLARE @id_field_GF_BEC_ExceptionalBonus_EUR  int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GF_BEC_ExceptionalBonus_EUR')
		DECLARE @id_field_GR_BEC_MaxExceeded int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GR_BEC_MaxExceeded')
		DECLARE @id_field_GR_BEC_Bonus_Percent_Proposal int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GR_BEC_Bonus_Percent_Proposal')
		DECLARE @id_field_GR_BEC_New_ASF int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GR_BEC_New_ASF')
		DECLARE @id_field_GR_BEC_Finale_Proposed int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GR_BEC_Finale_Proposed')
		DECLARE @id_field_GR_BEC_Total_Comp_EUR int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GR_BEC_Total_Comp_EUR')
		DECLARE @id_field_GR_BEC_Bonus_Amount_EUR_2 int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GR_BEC_Bonus_Amount_EUR_2')
		DECLARE @id_field_GR_BEC_MRT_Flag int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GR_BEC_MRT_Flag')
		DECLARE @id_field_GR_BEC_Deferral_Flag int = (SELECT id_field FROM k_m_fields WHERE code_field = 'GR_BEC_Deferral_Flag')

		DROP TABLE IF EXISTS #temp_steps
		DROP TABLE IF EXISTS #temp_values_bonus_amount
		DROP TABLE IF EXISTS #temp_values_bonus_amount_proposal
		DROP TABLE IF EXISTS #temp_values_current_base_salary_eur
		DROP TABLE IF EXISTS #temp_values_pct_bonus
		DROP TABLE IF EXISTS #temp_values_final_bonus
		DROP TABLE IF EXISTS #temp_values_final_bonus_in_eur
		DROP TABLE IF EXISTS #temp_values_max_exceed_msg
		DROP TABLE IF EXISTS #temp_values_final_total_comp
		DROP TABLE IF EXISTS #temp_values_final_total_comp_in_eur
		DROP TABLE IF EXISTS #temp_values_MRT_flag
		DROP TABLE IF EXISTS #temp_values_Deferral_flag
		DROP TABLE IF EXISTS #temp_values_exceptional_bonus_eur
		DROP TABLE IF EXISTS #temp_values_bonus_amount_eur
		DROP TABLE IF EXISTS #temp_values_current_base_salary_ec
		DROP TABLE IF EXISTS #temp_values_total_bonus_in_employee_currency
		DROP TABLE IF EXISTS #temp_values_total_bonus_in_eur
		DROP TABLE IF EXISTS #temp_values_pct_bonus_excl_exceptional_bonus
		DROP TABLE IF EXISTS #temp_values_pct_bonus_incl_exceptional_bonus
		DROP TABLE IF EXISTS #temp_values_amount_bonus_excl_exceptional_bonus
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

		CREATE TABLE #temp_values_bonus_amount_proposal (
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
			input_value varchar(50),
			input_date datetime,
			id_user int,
			comment_value nvarchar(200),
			source_value nvarchar(200),
			value_type int,
			idSim int
		)
		
		CREATE TABLE #temp_values_exceptional_bonus_eur (
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
		
		CREATE TABLE #temp_values_bonus_amount_eur (
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

		CREATE TABLE #temp_values_current_base_salary_ec (
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

		CREATE TABLE #temp_values_total_bonus_in_employee_currency (
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

		CREATE TABLE #temp_values_total_bonus_in_eur (
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

		CREATE TABLE #temp_values_pct_bonus_excl_exceptional_bonus (
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
		CREATE TABLE #temp_values_amount_bonus_excl_exceptional_bonus (
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
			Update bonus amount proposal
		*/
		INSERT INTO #temp_values_bonus_amount_proposal (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GR_Yearly_Campaign_BEC_Bonus AS id_ind,
			@id_field_GF_BEC_Bonus_Amount_Proposal AS id_field,
			CAST([dbo].[_fn_round_up] (v_am.input_value_numeric,2) AS NVARCHAR(100)) AS input_value,
			[dbo].[_fn_round_up] (v_am.input_value_numeric,2) AS input_value_numeric,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_Bonus_ExCom_BP_EC_Leaders',
			1,
			0
		FROM Engie_Cache_View_Process_Bonus_ExCom_BP_EC_Leaders c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		INNER JOIN k_m_values v_am
			ON v_am.id_step = ps.id_step
			AND v_am.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Bonus
			AND v_am.id_field = @id_field_GF_BEC_Bonus_Amount_Proposal
		WHERE c.ID_YearlyCampaign = @id_yearly_campaign

		MERGE k_m_values AS tg
		USING #temp_values_bonus_amount_proposal AS sc
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
			Update bonus amount exc. bonus
		*/
		INSERT INTO #temp_values_bonus_amount (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GR_Yearly_Campaign_BEC_Bonus AS id_ind,
			@id_field_GF_BEC_ExceptionalBonus AS id_field,
			CASE
				WHEN v_am.input_value_numeric IS NULL
				THEN NULL
				ELSE CAST([dbo].[_fn_round_up] (v_am.input_value_numeric,2) AS NVARCHAR(100))
			END AS input_value,
			CASE
				WHEN v_am.input_value_numeric IS NULL
				THEN NULL
				ELSE [dbo].[_fn_round_up] (v_am.input_value_numeric,2)
			END AS input_value_numeric,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_Bonus_ExCom_BP_EC_Leaders',
			1,
			0
		FROM Engie_Cache_View_Process_Bonus_ExCom_BP_EC_Leaders c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		INNER JOIN k_m_values v_am
			ON v_am.id_step = ps.id_step
			AND v_am.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Bonus
			AND v_am.id_field = @id_field_GF_BEC_ExceptionalBonus
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
			Update 'Exceptional bonus in EUR'
		*/
		INSERT INTO #temp_values_exceptional_bonus_eur (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GR_Yearly_Campaign_BEC_Bonus AS id_ind,
			@id_field_GF_BEC_ExceptionalBonus_EUR AS id_field,
			CAST(CAST(v_am.input_value_numeric * ISNULL(cur.exchangeRatefor1EUR, 1) AS DECIMAL(18,4)) AS NVARCHAR(100)) AS input_value,
			v_am.input_value_numeric * ISNULL(cur.exchangeRatefor1EUR, 1) AS input_value_numeric,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_Bonus_ExCom_BP_EC_Leaders',
			1,
			0
		FROM Engie_Cache_View_Process_Bonus_ExCom_BP_EC_Leaders c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		INNER JOIN k_m_values v_am
			ON v_am.id_step = ps.id_step
			AND v_am.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Bonus
			AND v_am.id_field = @id_field_GF_BEC_ExceptionalBonus
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
		USING #temp_values_exceptional_bonus_eur AS sc
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
			Update Current Base Salary with prorata in Salary
		*/
		INSERT INTO #temp_values_current_base_salary_ec (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GR_Yearly_Campaign_BEC_Salary AS id_ind,
			@id_field_GR_BEC_Salary_Prorata_EC AS id_field,
			CAST(CAST(((c.BaseSalary * c.Final_Prorata / 100) * 100) AS DECIMAL(18,2)) AS NVARCHAR(100)) AS input_value,
			CAST(((c.BaseSalary * c.Final_Prorata / 100) * 100) AS DECIMAL(18,2)) AS input_value_numeric,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_Bonus_ExCom_BP_EC_Leaders',
			1,
			0
		FROM Engie_Cache_View_Process_Bonus_ExCom_BP_EC_Leaders c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step

		MERGE k_m_values AS tg
		USING #temp_values_current_base_salary_ec AS sc
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
			Update Current Base Salary in EUR with prorata in Salary
		*/
		INSERT INTO #temp_values_current_base_salary_eur (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GR_Yearly_Campaign_BEC_Salary AS id_ind,
			@id_field_GR_BEC_Salary_Prorata AS id_field,
			CASE WHEN c.Code_Currency = 'EUR'
			THEN 
			CAST(CAST(c.BaseSalary * c.Final_Prorata * 1 AS DECIMAL(18,4)) AS NVARCHAR(100))
			ELSE
			CAST(CAST(c.BaseSalary * c.Final_Prorata * COALESCE(cur.ExchangeRatefor1EUR, 1) AS DECIMAL(18,4)) AS NVARCHAR(100)) END AS input_value,
			CASE WHEN c.Code_Currency = 'EUR'
			THEN
			CAST(c.BaseSalary * c.Final_Prorata * 1 AS DECIMAL(18,4))
			ELSE
			CAST(c.BaseSalary * c.Final_Prorata * COALESCE(cur.ExchangeRatefor1EUR, 1) AS DECIMAL(18,4)) END AS input_value_numeric,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_Bonus_ExCom_BP_EC_Leaders',
			1,
			0
		FROM Engie_Cache_View_Process_Bonus_ExCom_BP_EC_Leaders c
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
			Update ASF
		*/
		INSERT INTO #temp_values_new_asf_in_employee_currency (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GR_Yearly_Campaign_BEC_Bonus AS id_ind,
			@id_field_GR_BEC_New_ASF AS id_field,
			CAST(c.Current_ASF AS NVARCHAR(100)) AS input_value, 
			c.Current_ASF AS input_value_numeric,
			GETUTCDATE() AS input_date,
			-1 AS id_user,
			'Automatically Insert' AS comment_value,
			'Engie_Post_Save_Values_Bonus_ExCom_BP_EC_Leaders' AS source_value,
			1 AS value_type,
			0 AS idSim
		FROM Engie_Cache_View_Process_Bonus_ExCom_BP_EC_Leaders c
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

		/*
				Total Compensation
		*/
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
			value_current_ASF decimal(18,4),
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
			WHERE v_b_am.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Bonus
			AND v_b_am.id_field = @id_field_GR_BEC_Bonus_Amount_Proposal

			UNION

			SELECT
				v_asf.id_step,
				NULL AS value_bonus_amount,
				v_asf.input_value_numeric  AS value_new_ASF
			FROM k_m_values v_asf
			INNER JOIN #temp_steps t
				ON t.id_step = v_asf.id_step
			WHERE v_asf.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Bonus
			AND v_asf.id_field = @id_field_GR_BEC_New_ASF
		) a
		GROUP BY a.id_step


		-- Temp table to collect relevant 'New Base Salary' amounts from other Base Pay Review Campaigns
		DROP TABLE IF EXISTS #temp_New_Base_Salary
		CREATE TABLE #temp_New_Base_Salary (
			id_step int,
			id_plan_ExCom_BP_EC_Leaders int,
			id_payee int,
			id_step_salary_campaign int,
			id_plan_salary_campaign int,
			New_Base_Salary int
		)

		INSERT INTO #temp_New_Base_Salary (id_step, id_plan_ExCom_BP_EC_Leaders, id_payee, id_step_salary_campaign, id_plan_salary_campaign, New_Base_Salary)
		SELECT
			t.id_step
			,kmpps_excom.id_plan
			,kmpps_excom.id_payee
			,kmpps_salary_campaign.id_step
			,kmpps_salary_campaign.id_plan
			,CAST(ROUND(ISNULL(kmv.input_value_numeric, 0), 0) AS INT)
		FROM #temp_steps AS t
		INNER JOIN k_m_plans_payees_steps AS kmpps_excom
		ON t.id_step = kmpps_excom.id_step
			LEFT JOIN k_m_plans_payees_steps AS kmpps_salary_campaign
			ON kmpps_excom.id_payee = kmpps_salary_campaign.id_payee
			AND kmpps_salary_campaign.id_plan <> @id_plan
			AND kmpps_salary_campaign.id_plan in (61, 62, 63, 65)
				LEFT JOIN k_m_values AS kmv
				ON kmpps_salary_campaign.id_step = kmv.id_step
				AND kmv.id_field IN (@id_field_New_Base_Salary_World, @id_field_New_Base_Salary_Engie_SA, @id_field_New_Base_Salary_Italy)


		INSERT INTO #temp_final_bonus_ASF (id_step, BaseSalary, value_bonus_amount, value_current_ASF, exchangeRatefor1EUR)
		SELECT
			ps.id_step,
			--CEILING(c.BaseSalary * c.Final_Prorata) AS base_salary,
			c.BaseSalary AS base_salary,
			t.value_bonus_amount AS value_bonus_amount,
			COALESCE(c.Current_ASF, 0) AS value_current_ASF,	--(13)
			COALESCE(exchangeRatefor1EUR, 1) AS exchangeRatefor1EUR
		FROM Engie_Cache_View_Process_Bonus_ExCom_BP_EC_Leaders c
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
			@id_ind_GR_Yearly_Campaign_BEC_Bonus AS id_ind,
			@id_field_GR_BEC_Finale_Proposed AS id_field,
			CAST(CAST(ROUND(BaseSalary + COALESCE(value_current_ASF, 0) + COALESCE(value_bonus_amount, 0), 0) AS int) as nvarchar(max)) AS input_value,
			CAST(ROUND(BaseSalary + COALESCE(value_current_ASF, 0) + COALESCE(value_bonus_amount, 0), 0) AS int) AS input_value_int,
			GETUTCDATE() AS input_date,
			-1 AS id_user,
			'Automatically Insert' AS comment_value,
			'Engie_Post_Save_Values_Bonus_ExCom_BP_EC_Leaders' AS source_value,
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
			@id_ind_GR_Yearly_Campaign_BEC_Bonus AS id_ind,
			@id_field_GR_BEC_Total_Comp_EUR AS id_field,
			CAST(CAST(ROUND((BaseSalary + COALESCE(value_current_ASF, 0) + COALESCE(value_bonus_amount, 0)) * COALESCE(exchangeRatefor1EUR, 1), 0) AS int) as nvarchar(max)) AS input_value,
			CAST(ROUND((BaseSalary + COALESCE(value_current_ASF, 0) + COALESCE(value_bonus_amount, 0)) * COALESCE(exchangeRatefor1EUR, 1), 0) AS int) AS input_value_int,
			GETUTCDATE() AS input_date,
			-1 AS id_user,
			'Automatically Insert' AS comment_value,
			'Engie_Post_Save_Values_Bonus_ExCom_BP_EC_Leaders' AS source_value,
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
			Update Total bonus amount in employee currency
		*/
		INSERT INTO #temp_values_total_bonus_in_employee_currency (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GR_Yearly_Campaign_BEC_Bonus AS id_ind,
			@id_field_GR_BEC_Final_Bonus AS id_field,
			v_ba.input_value,
			v_ba.input_value_numeric,
			GETUTCDATE() AS input_date,
			-1 AS id_user,
			'Automatically Insert' AS comment_value,
			'Engie_Post_Save_Values_Bonus_ExCom_BP_EC_Leaders' AS source_value,
			1 AS value_type,
			0 AS idSim
		FROM k_m_plans_payees_steps ps
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		LEFT JOIN k_m_values v_ba
			ON v_ba.id_step = ps.id_step
			AND v_ba.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Bonus
			AND v_ba.id_field = @id_field_GR_BEC_Bonus_Amount_Proposal
		WHERE ps.id_plan = @id_plan

		MERGE k_m_values AS tg
		USING #temp_values_total_bonus_in_employee_currency AS sc
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
			Update Total bonus amount in EUR
		*/
		INSERT INTO #temp_values_total_bonus_in_eur (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GR_Yearly_Campaign_BEC_Bonus AS id_ind,
			@id_field_GR_BEC_Bonus_EUR AS id_field,
			CAST(v_ba.input_value_numeric / NULLIF((v_cbs_ec.input_value_numeric / NULLIF(v_cbs_e.input_value_numeric, 0)), 0) AS NVARCHAR(100)) AS input_value,
			v_ba.input_value_numeric / NULLIF((v_cbs_ec.input_value_numeric / NULLIF(v_cbs_e.input_value_numeric, 0)), 0) AS input_value_numeric,
			GETUTCDATE() AS input_date,
			-1 AS id_user,
			'Automatically Insert' AS comment_value,
			'Engie_Post_Save_Values_Bonus_ExCom_BP_EC_Leaders' AS source_value,
			1 AS value_type,
			0 AS idSim
		FROM k_m_plans_payees_steps ps
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		LEFT JOIN k_m_values v_ba
			ON v_ba.id_step = ps.id_step
			AND v_ba.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Bonus
			AND v_ba.id_field = @id_field_GR_BEC_Bonus_Amount_Proposal
		LEFT JOIN k_m_values v_cbs_ec
			ON v_cbs_ec.id_step = ps.id_step
			AND v_cbs_ec.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Salary
			AND v_cbs_ec.id_field = @id_field_GR_BEC_Salary_Prorata_EC
		LEFT JOIN k_m_values v_cbs_e
			ON v_cbs_e.id_step = ps.id_step
			AND v_cbs_e.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Salary
			AND v_cbs_e.id_field = @id_field_GR_BEC_Salary_Prorata
		WHERE ps.id_plan = @id_plan

		MERGE k_m_values AS tg
		USING #temp_values_total_bonus_in_eur AS sc
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
			Update % Bonus (Excl. Exceptional Bonus)
		*/
		INSERT INTO #temp_values_pct_bonus_excl_exceptional_bonus (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GR_Yearly_Campaign_BEC_Bonus AS id_ind,
			@id_field_GR_BEC_Bonus_Percent AS id_field,
			CASE
				WHEN v_ba.input_value_numeric IS NULL AND NULLIF(v_ba_exc.input_value_numeric, 0) IS NULL
				THEN NULL
				ELSE CAST((COALESCE(v_ba.input_value_numeric, 0) - COALESCE(v_ba_exc.input_value_numeric, 0)) / NULLIF((ecvpbc.BaseSalary + COALESCE(ecvpbc.Current_ASF,0)), 0) AS NVARCHAR(100))
			END AS input_value,
			CASE
				WHEN v_ba.input_value_numeric IS NULL AND v_ba_exc.input_value_numeric IS NULL
				THEN NULL
				ELSE (COALESCE(v_ba.input_value_numeric, 0) - COALESCE(v_ba_exc.input_value_numeric, 0)) / NULLIF((ecvpbc.BaseSalary + COALESCE(ecvpbc.Current_ASF,0)), 0)
			END AS input_value_numeric,
			GETUTCDATE() AS input_date,
			-1 AS id_user,
			'Automatically Insert' AS comment_value,
			'Engie_Post_Save_Values_Bonus_ExCom_BP_EC_Leaders' AS source_value,
			1 AS value_type,
			0 AS idSim
		FROM k_m_plans_payees_steps ps
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		LEFT JOIN k_m_values v_ba
			ON v_ba.id_step = ps.id_step
			AND v_ba.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Bonus
			AND v_ba.id_field = @id_field_GR_BEC_Bonus_Amount_Proposal
		LEFT JOIN k_m_values v_ba_exc
			ON v_ba_exc.id_step = ps.id_step
			AND v_ba_exc.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Bonus
			AND v_ba_exc.id_field = @id_field_GF_BEC_ExceptionalBonus
		LEFT JOIN k_m_values v_cbs_ec
			ON v_cbs_ec.id_step = ps.id_step
			AND v_cbs_ec.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Salary
			AND v_cbs_ec.id_field = @id_field_GR_BEC_Salary_Prorata_EC
		INNER JOIN Engie_Cache_View_Process_Bonus_ExCom_BP_EC_Leaders ecvpbc
			ON ecvpbc.idPayee = ps.id_payee
		WHERE ps.id_plan = @id_plan

		MERGE k_m_values AS tg
		USING #temp_values_pct_bonus_excl_exceptional_bonus AS sc
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
			Update % Bonus (Incl. Exceptional Bonus)
		*/
		INSERT INTO #temp_values_pct_bonus_incl_exceptional_bonus (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GR_Yearly_Campaign_BEC_Bonus AS id_ind,
			@id_field_GR_BEC_Bonus_Percent_Proposal AS id_field,
			CASE
				WHEN v_ba.input_value_numeric IS NULL
				THEN NULL
				ELSE CAST((COALESCE(v_ba.input_value_numeric, 0)) / NULLIF(ISNULL(c.BaseSalary,0) + ISNULL(c.Current_ASF,0), 0) AS NVARCHAR(100))
			END AS input_value,
			CASE
				WHEN v_ba.input_value_numeric IS NULL
				THEN NULL
				ELSE (COALESCE(v_ba.input_value_numeric, 0)) / NULLIF(ISNULL(c.BaseSalary,0) + ISNULL(c.Current_ASF,0), 0)
			END AS input_value_numeric,
			GETUTCDATE() AS input_date,
			-1 AS id_user,
			'Automatically Insert' AS comment_value,
			'Engie_Post_Save_Values_Bonus_ExCom_BP_EC_Leaders' AS source_value,
			1 AS value_type,
			0 AS idSim
		FROM k_m_plans_payees_steps ps
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		INNER JOIN Engie_Cache_View_Process_Bonus_ExCom_BP_EC_Leaders c
			ON ps.id_payee = c.idPayee
		LEFT JOIN k_m_values v_ba
			ON v_ba.id_step = ps.id_step
			AND v_ba.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Bonus
			AND v_ba.id_field = @id_field_GR_BEC_Bonus_Amount_Proposal
		WHERE ps.id_plan = @id_plan

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
			Update Max Exceeded from Bonus
		*/
		INSERT INTO #temp_values_max_exceed_msg (id_step, id_ind, id_field, input_value, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GR_Yearly_Campaign_BEC_Bonus AS id_ind,
			@id_field_GR_BEC_MaxExceeded AS id_field,
			CASE
				WHEN v_pct.input_value_numeric IS NULL THEN NULL
				WHEN COALESCE(c.BonusRangeMaximum, 0) <= v_pct.input_value_numeric --(15)
					AND c.BonusRangeMaximum IS NOT NULL
				THEN 'Yes'
				ELSE 'No'
			END AS input_value,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_Bonus_ExCom',
			1,
			0
		FROM Engie_Cache_View_Process_Bonus_ExCom_BP_EC_Leaders c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		INNER JOIN k_m_values v_pct
			ON v_pct.id_step = ps.id_step
			AND v_pct.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Bonus
			AND v_pct.id_field = @id_field_GR_BEC_Bonus_Percent_Proposal
		WHERE c.ID_YearlyCampaign = @id_yearly_campaign

		MERGE k_m_values AS tg
		USING #temp_values_max_exceed_msg AS sc
			ON sc.id_step = tg.id_step
			AND sc.id_ind = tg.id_ind
			AND sc.id_field = tg.id_field
		WHEN MATCHED AND COALESCE(sc.input_value, '') <> COALESCE(tg.input_value, '')
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
			Update Bonus Amount in Employee Currency (Excl. Exceptional Bonus)
		*/
		INSERT INTO #temp_values_amount_bonus_excl_exceptional_bonus (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GR_Yearly_Campaign_BEC_Bonus AS id_ind,
			@id_field_GR_BEC_Bonus_Amount AS id_field,
			CASE
				WHEN v_ba.input_value_numeric IS NULL AND NULLIF(v_ba_exc.input_value_numeric, 0) IS NULL
				THEN NULL
				ELSE CAST(COALESCE(v_ba.input_value_numeric, 0) - COALESCE(v_ba_exc.input_value_numeric, 0) AS NVARCHAR(100))
			END AS input_value,
			CASE
				WHEN v_ba.input_value_numeric IS NULL AND v_ba_exc.input_value_numeric IS NULL
				THEN NULL
				ELSE COALESCE(v_ba.input_value_numeric, 0) - COALESCE(v_ba_exc.input_value_numeric, 0)
			END AS input_value_numeric,
			GETUTCDATE() AS input_date,
			-1 AS id_user,
			'Automatically Insert' AS comment_value,
			'Engie_Post_Save_Values_Bonus_ExCom_BP_EC_Leaders' AS source_value,
			1 AS value_type,
			0 AS idSim
		FROM k_m_plans_payees_steps ps
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		LEFT JOIN k_m_values v_ba
			ON v_ba.id_step = ps.id_step
			AND v_ba.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Bonus
			AND v_ba.id_field = @id_field_GR_BEC_Bonus_Amount_Proposal
		LEFT JOIN k_m_values v_ba_exc
			ON v_ba_exc.id_step = ps.id_step
			AND v_ba_exc.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Bonus
			AND v_ba_exc.id_field = @id_field_GF_BEC_ExceptionalBonus
		WHERE ps.id_plan = @id_plan

		MERGE k_m_values AS tg
		USING #temp_values_amount_bonus_excl_exceptional_bonus AS sc
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
			Update Amount in employee currency (excl. Exceptional bonus) in EUR to Amount in EUR (excl. Exceptional bonus)
		*/
		INSERT INTO #temp_values_bonus_amount_eur (id_step, id_ind, id_field, input_value, input_value_numeric, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GR_Yearly_Campaign_BEC_Bonus AS id_ind,
			@id_field_GR_BEC_Bonus_Amount_EUR_2 AS id_field,
			CAST(CAST(v_am.input_value_numeric - ISNULL(v_am_2.input_value_numeric,0)  AS DECIMAL(18,4)) AS NVARCHAR(100)) AS input_value, 
			v_am.input_value_numeric - ISNULL(v_am_2.input_value_numeric,0)  AS input_value_numeric,
			GETUTCDATE() AS input_date,
			-1 AS id_user,
			'Automatically Insert' AS comment_value,
			'Engie_Post_Save_Values_Bonus_ExCom_BP_EC_Leaders' AS source_value,
			1 AS value_type,
			0 AS idSim
		FROM Engie_Cache_View_Process_Bonus_ExCom_BP_EC_Leaders c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		INNER JOIN k_m_values v_am
			ON v_am.id_step = ps.id_step
			AND v_am.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Bonus
			AND v_am.id_field = @id_field_GR_BEC_Bonus_EUR
		LEFT JOIN k_m_values v_am_2
			ON v_am_2.id_step = ps.id_step
			AND v_am_2.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Bonus
			AND v_am_2.id_field = @id_field_GF_BEC_ExceptionalBonus_EUR
		WHERE c.ID_YearlyCampaign = @id_yearly_campaign

		MERGE k_m_values AS tg
		USING #temp_values_bonus_amount_eur AS sc
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
			Update MRT Flag from Bonus and ASF		--(4)
		*/
		INSERT INTO #temp_values_MRT_flag (id_step, id_ind, id_field, input_value, input_date, id_user, comment_value, source_value, value_type, idSim)
		SELECT
			ps.id_step,
			@id_ind_GR_BEC_MRT_Flag AS id_ind,
			@id_field_GR_BEC_MRT_Flag AS id_field,
			CASE WHEN 
			[dbo].[_fn_mrt_flag](ps.id_payee, 'EC/BP Leader') != '' 
			THEN 
			[dbo].[_fn_mrt_flag](ps.id_payee, 'EC/BP Leader')
			ELSE 
			NULL
			END AS input_value,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_Bonus_ExCom_BP_EC_Leaders',
			1,
			0
		FROM Engie_Cache_View_Process_Bonus_ExCom_BP_EC_Leaders c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
/*		INNER JOIN k_m_values v_am
			ON v_am.id_step = ps.id_step
			AND v_am.id_ind = (SELECT id_ind FROM k_m_indicators WHERE name_ind =  'GR_Yearly_Campaign_BEC_Bonus')
			AND v_am.id_field = (SELECT id_field FROM k_m_fields WHERE code_field = 'GR_BEC_Bonus_Amount') */
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
			@id_ind_GR_BEC_MRT_Flag AS id_ind,
			@id_field_GR_BEC_Deferral_Flag AS id_field,
			CASE
				WHEN v_mrt.input_value = 'Non-MRT' THEN 'Bonus deferred, refer to Bonus Scheme Report'
				WHEN (v_mrt.input_value = 'MRT - Ex-post' OR v_mrt.input_value = 'MRT - Ex-ante') AND 
					(COALESCE(v_bon.input_value_numeric, v_bon.input_value,0)>50000 OR COALESCE(v_bon.input_value_numeric, v_bon.input_value,0) > 0.25*(c.BaseSalary+COALESCE(c.Current_ASF,0)+COALESCE(v_bon.input_value_numeric, v_bon.input_value,0))) THEN 'Bonus deferred, refer to Bonus Scheme Report'	--(6)	
			END AS input_value,
			GETUTCDATE(),
			-1 AS id_user,
			'Automatically Insert',
			'Engie_Post_Save_Values_Bonus_ExCom_BP_EC_Leaders',
			1,
			0
		FROM Engie_Cache_View_Process_Bonus_ExCom_BP_EC_Leaders c
		INNER JOIN k_m_plans_payees_steps ps
			ON ps.id_payee = c.idPayee
			AND ps.id_plan = @id_plan
		INNER JOIN #temp_steps t
			ON t.id_step = ps.id_step
		INNER JOIN k_m_values v_bon
			ON v_bon.id_step = ps.id_step
			AND v_bon.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Bonus
			AND v_bon.id_field = @id_field_GR_BEC_Final_Bonus
		--LEFT JOIN k_m_values v_asf
		--	ON v_asf.id_step = ps.id_step
		--	AND v_asf.id_ind = @id_ind_GR_Yearly_Campaign_BEC_Bonus
		--	AND v_asf.id_field = (SELECT id_field FROM k_m_fields WHERE code_field = 'GR_BEC_New_ASF')
		LEFT JOIN k_m_values v_mrt
			ON v_mrt.id_step = ps.id_step
			AND v_mrt.id_ind = @id_ind_GR_BEC_MRT_Flag
			AND v_mrt.id_field = @id_field_GR_BEC_MRT_Flag
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

