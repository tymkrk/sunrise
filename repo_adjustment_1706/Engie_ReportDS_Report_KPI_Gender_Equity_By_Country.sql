CREATE PROCEDURE [dbo].[Engie_ReportDS_Report_KPI_Gender_Equity_By_Country]
	@idUser		int
	,@idProfile int
	,@bpec nvarchar(72)
	,@currency nvarchar(50) 
	,@geographical_zone_id int
AS
-- ========================================================
-- Author:       Kamil Roganowicz 
-- Create date : 25/07/2024
-- Description : Stored procedure for report KPI Gender Equity AVG Salary Increase By Country
-- Changes:
-- (1) - 2024-08-02 - Kamil Roganowicz - ENG-164 changing indicator to GF_ESA_Yearly_Campaign_ESA_SeniorityIncrease for GF_ESA_CollectiveSalaryInc_Pct field
-- (2) - 2024-08-22 - Rafal Jura - ENG-184 changed calculations of increase amount: World and Italy - take directly from Increase Amount, Engie SA - take as ("Total Salary Increase Pct"- "Collective Salary Increase %"-"Seniority Increase Pct") * Current Base Salary 
-- ======================================================== 
BEGIN

 
	--declare 	@idUser		int = 7515
	--,@idProfile int = -1
	--,@bpec nvarchar(72) = '63404CB0-8C30-496C-9958-EDC7B035589C'
	--,@geographical_zone_id int = 1
	--,@currency nvarchar(50)  = 'Employee Currency'

  DECLARE 
      @Id_log int,
      @ReportPstkName varchar(max),
      @ParamPstkList varchar(max),
	  @EffectiveDate date = (SELECT Effective_Date FROM Engie_Param_Yearly_Campaign WHERE ID_Status IN (2,3)),
	  @Campaign_ID INT = (SELECT ID FROM Engie_Param_Yearly_Campaign WHERE ID_Status IN (2,3)),
	  @ExchangeRatefor1EUR_currency decimal(18,4)



    set @ReportPstkName=OBJECT_NAME(@@PROCID) 
    set @ParamPstkList = ''
        +'@idUser = '+isnull(''''+convert(varchar(100),@idUser)+'''','NULL') 
        +', @idProfile = '+isnull(''''+convert(varchar(100),@idProfile)+'''','NULL')     
		+', @bpec = '+isnull(''''+convert(varchar(100),@bpec)+'''','NULL') 
		+', @currency = '+isnull(''''+convert(varchar(100),@currency)+'''','NULL') 

    exec Engie_Insert_Report_Logs_Start @ReportPstkName,@ParamPstkList,@Id_log output

	DECLARE 
		@campaign_world		 INT	= (SELECT id_plan FROM k_m_plans where name_plan LIKE '%Base Pay Review World')
	 ,	@campaign_engie_sa	 INT	= (SELECT id_plan FROM k_m_plans where name_plan LIKE '%Base Pay Review ENGIE SA')
	 ,	@campaign_italy		 INT	= (SELECT id_plan FROM k_m_plans where name_plan LIKE '%Base Pay Review Italy')

	 DECLARE @geographical_zone_name NVARCHAR(100) = (SELECT geographical_zone_name FROM Engie_REF_Geographical_Zone WHERE id = @geographical_zone_id)

	 DECLARE
		@id_field_GF_GW_Pourcentage INT
	,	@id_field_GF_IE_Pourcentage_Individual_Salary_Increase INT
	,	@id_field_GF_ESA_Pourcentage INT
	,	@id_field_GF_ESA_CollectiveSalaryInc_Pct INT
	,	@id_field_GF_GW_Amount_SR INT
	,	@id_field_GF_IE_Amount_SR INT

	DECLARE 
		@id_ind_GF_ESA_Yearly_Campaign_ESA_TotalSalaryIncrease INT
	,	@id_ind_GF_ESA_Yearly_Campaign_ESA_SeniorityIncrease INT

	SELECT 
		@id_field_GF_GW_Pourcentage								= GF_GW_Pourcentage 
	,	@id_field_GF_IE_Pourcentage_Individual_Salary_Increase	= GF_IE_Pourcentage_Individual_Salary_Increase
	,	@id_field_GF_ESA_Pourcentage							= GF_ESA_Pourcentage
	,	@id_field_GF_ESA_CollectiveSalaryInc_Pct				= GF_ESA_CollectiveSalaryInc_Pct
	,	@id_field_GF_GW_Amount_SR								= GF_GW_Amount_SR
	,	@id_field_GF_IE_Amount_SR								= GF_IE_Amount_SR
	FROM Engie_View_Ref_Field_List

	SELECT
		@id_ind_GF_ESA_Yearly_Campaign_ESA_TotalSalaryIncrease = GF_ESA_Yearly_Campaign_ESA_TotalSalaryIncrease
	,	@id_ind_GF_ESA_Yearly_Campaign_ESA_SeniorityIncrease = GF_ESA_Yearly_Campaign_ESA_SeniorityIncrease
	FROM Engie_View_Ref_Indicator_List

	DROP TABLE IF EXISTS #exchange_rate_current
	CREATE TABLE #exchange_rate_current (
		ExchangeRatefor1EUR decimal(18,4),
		currency nvarchar(3)
	)

	INSERT INTO #exchange_rate_current (ExchangeRatefor1EUR, currency)
	SELECT
		ExchangeRatefor1EUR,
		currency
	FROM(
		SELECT
		exR.exchangeRatefor1EUR,
	    exR.currency,
		exr.EffectiveDate,
	    row_number() over(partition by  exR.Family order by exR.EffectiveDate desc)  as rn
		FROM  Engie_Exchange_Rates exR
		WHERE exR.EffectiveDate <= @EffectiveDate) as T
	WHERE T.rn = 1

	SELECT
		@ExchangeRatefor1EUR_currency = ExchangeRatefor1EUR
	FROM #exchange_rate_current
	WHERE currency = @currency

	DROP TABLE IF EXISTS #temp_hierarchy_cte_filtered
	CREATE TABLE #temp_hierarchy_cte_filtered (
		idTree int,
		idChild int
	)

	INSERT INTO #temp_hierarchy_cte_filtered (idTree, idChild)
	EXEC Engie_ReportDS_Hierarchy_Security @idUser, @idProfile, null, null

	drop table if exists #country_list
	CREATE TABLE #country_list (country NVARCHAR(3))

	IF @geographical_zone_id = 500
	BEGIN
		INSERT INTO #country_list
		SELECT 
		country
		FROM Engie_Geographical_Zone_Country_Assignment
	END
	ELSE
	BEGIN
		INSERT INTO #country_list
		SELECT 
			country
		FROM Engie_Geographical_Zone_Country_Assignment
		WHERE geographical_zone_id = @geographical_zone_id
	END
	

	DROP TABLE IF EXISTS #bp_ec_levels
	SELECT
		bp.BPGuid AS bp_ec_guid
	   ,'BP' AS type
	INTO #bp_ec_levels
	FROM Engie_BP_Levels bp
	WHERE bp.bp_lvl1 = @bpec OR @bpec IS NULL

	UNION
	
	SELECT
		CAST(ec.GcrowdId AS NVARCHAR(72)) AS GcrowdId
	   ,'EC' AS type
	FROM Engie_EC_Levels ec
	WHERE ec.ec_lvl1 = @bpec OR @bpec IS NULL
	

	DROP TABLE IF EXISTS #payees_list_final
	;WITH payees_list_final AS (
	SELECT
		ps.idPayee
	   ,ps.Code_gender
	   ,ec.Associated_Country AS country
	   ,ps.Code_Currency
	   ,ps.BaseSalary 
	FROM Engie_Cache_View_Yearly_Campaign_Payees_Situations ps
	JOIN #bp_ec_levels pl
		ON ps.Code_BPGuid = pl.bp_ec_guid
			AND pl.type = 'BP'
	JOIN Engie_Param_Link_Legal_Entity_Country ec
		ON ps.LegalEntity = ec.Legal_Entity
	JOIN #country_list cl
		ON ec.Associated_Country = cl.country
	WHERE ISNULL(ps.RewardCategory,'') <> 'COMP&BEN'	

	UNION ALL
	
	SELECT
		ps.idPayee
	   ,ps.Code_gender
	   ,ec.Associated_Country
	   ,ps.Code_Currency
	   ,ps.BaseSalary
	FROM Engie_Cache_View_Yearly_Campaign_Payees_Situations ps
	JOIN #bp_ec_levels pl
		ON ps.Code_GcrowdId = pl.bp_ec_guid
			AND pl.type = 'EC'
	JOIN Engie_Param_Link_Legal_Entity_Country ec
		ON ps.LegalEntity = ec.Legal_Entity
	JOIN #country_list cl
		ON ec.Associated_Country = cl.country
	WHERE ISNULL(ps.RewardCategory,'') <> 'COMP&BEN'	
	)
	SELECT DISTINCT 
		idPayee
	,	Code_gender
	,	country
	,	Code_Currency
	,	BaseSalary
	INTO #payees_list_final
	FROM payees_list_final

	DROP TABLE IF EXISTS #process_dataset
		SELECT
				ps.idPayee
		   ,	kmp.id_plan
		   ,	ps.Code_gender AS Gender
		   ,	ps.Code_Currency
		   ,	kmpps.id_step
		   ,	ps.country
	INTO #process_dataset
	From #temp_hierarchy_cte_filtered c
	JOIN #payees_list_final ps
			ON ps.idPayee = c.idChild
	JOIN k_m_plans_payees_steps kmpps
			ON ps.idPayee = kmpps.id_payee
	JOIN k_m_plans kmp
			ON kmp.id_plan = kmpps.id_plan
	WHERE kmp.id_plan IN (@campaign_world, @campaign_engie_sa, @campaign_italy)

	DROP TABLE IF EXISTS #process_values
	SELECT 
			pd.idPayee
		,	pd.gender
		,	pd.country
		,	pd.id_plan
		,	pd.Code_Currency
		,	isi_world_italy.input_value_numeric as isi_wi
		,	isi_eng_total.input_value_numeric	as total_eng
		,	isi_eng_salary.input_value_numeric	as si_eng
		,	increase_amount.input_value_numeric AS increase_amount
	INTO #process_values
	FROM #process_dataset pd
	LEFT JOIN k_m_values isi_world_italy 
		ON isi_world_italy.id_step		= pd.id_step 
		AND isi_world_italy.id_field	IN  (@id_field_GF_GW_Pourcentage, @id_field_GF_IE_Pourcentage_Individual_Salary_Increase)
	LEFT JOIN k_m_values isi_eng_total
		ON  isi_eng_total.id_step		= pd.id_step 
		AND isi_eng_total.id_field		= @id_field_GF_ESA_Pourcentage 
		AND isi_eng_total.id_ind		= @id_ind_GF_ESA_Yearly_Campaign_ESA_TotalSalaryIncrease
	LEFT JOIN k_m_values isi_eng_salary
		ON  isi_eng_salary.id_step		= pd.id_step 
		AND isi_eng_salary.id_field		= @id_field_GF_ESA_CollectiveSalaryInc_Pct
		AND isi_eng_salary.id_ind		= @id_ind_GF_ESA_Yearly_Campaign_ESA_SeniorityIncrease
	LEFT JOIN k_m_values increase_amount 
		ON increase_amount.id_step		= pd.id_step 
		AND increase_amount.id_field	IN  (@id_field_GF_GW_Amount_SR, @id_field_GF_IE_Amount_SR)
	
	


	/* HEAD COUNT */
	DROP TABLE IF EXISTS #head_count
	SELECT
			gender
	   ,	country
	   ,	COUNT(*) AS counted 
	INTO #head_count
	FROM #process_values
	GROUP BY gender, country
	
	DROP TABLE IF EXISTS #hc_count_final
	;
	WITH country_gender
	AS
	(SELECT
			gen.gender
		   ,hc_s.country
		FROM (VALUES ('F'), ('M')) gen (gender)
		CROSS JOIN (SELECT DISTINCT
				country
			FROM #head_count) hc_s)
	SELECT
			cg.country
	   ,	cg.gender
	   ,	ISNULL(hc_t.counted, 0) AS counted
	into #hc_count_final
	FROM country_gender cg
	LEFT JOIN #head_count hc_t
		ON cg.gender = hc_t.gender
			AND cg.country = hc_t.country

	/* INDIVIDUAL SALARY INCREASE % */
	DROP TABLE IF EXISTS #individual_salary_increase_pct
	;WITH cte_isi_source
	AS
	(
		SELECT
				idpayee
		   ,	gender
		   ,	country
		   ,	isi_wi
		FROM #process_values
		WHERE id_plan IN (@campaign_world, @campaign_italy)
		AND ISNULL(isi_wi, 0) > 0
	
		UNION ALL
	
		SELECT
				pv.idPayee
		   ,	gender
		   ,	country
		   ,	ISNULL(pv.total_eng, 0) - ISNULL(esa.Percentage_of_SNB_evolution, 0) - ISNULL(pv.si_eng, 0)
		FROM #process_values pv
		JOIN Engie_Cache_view_Process_Engie_SA esa
			ON esa.idPayee = pv.idPayee
		WHERE id_plan = @campaign_engie_sa
		AND ISNULL(pv.total_eng, 0) - ISNULL(esa.Percentage_of_SNB_evolution, 0) - ISNULL(pv.si_eng, 0) > 0

	 )
	SELECT
			cis.gender
	   ,	cis.country
	   ,	CAST(AVG(cis.isi_wi)  AS DECIMAL(18, 4)) AS salary_increase_pct
	INTO #individual_salary_increase_pct
	FROM cte_isi_source cis
	GROUP BY	cis.gender
			 ,	cis.country



	/* INDIVIDUAL SALARY INCREASE AMOUNT */
	DROP TABLE IF EXISTS #individual_salary_increase_amount
	;WITH cte_isi_source
	AS
	(
		SELECT
				pv.idpayee
		   ,	pv.gender
		   ,	pv.country
		   ,	pv.code_Currency
		   ,	pv.increase_amount
		   ,	pv.increase_amount * COALESCE(erc.ExchangeRatefor1EUR, 1) AS increase_amount_EUR
		FROM #process_values pv
		LEFT JOIN #exchange_rate_current erc
			ON erc.currency = pv.code_Currency
		WHERE id_plan IN (@campaign_world, @campaign_italy)
		AND ISNULL(increase_amount, 0) > 0
	
		UNION ALL
	
		SELECT
				pv.idpayee
		   ,	pv.gender
		   ,	pv.country
		   ,	pv.code_Currency
		   ,	(ISNULL(pv.total_eng, 0) - ISNULL(esa.Percentage_of_SNB_evolution, 0) - ISNULL(pv.si_eng, 0)) * esa.BaseSalary aS increase_amount
		   ,	((ISNULL(pv.total_eng, 0) - ISNULL(esa.Percentage_of_SNB_evolution, 0) - ISNULL(pv.si_eng, 0)) * esa.BaseSalary) * COALESCE(erc.ExchangeRatefor1EUR, 1) aS increase_amount_EUR
		FROM #process_values pv
		JOIN Engie_Cache_view_Process_Engie_SA esa
			ON esa.idPayee = pv.idPayee
		LEFT JOIN #exchange_rate_current erc
			ON erc.currency = pv.code_Currency
		WHERE id_plan = @campaign_engie_sa
		AND (ISNULL(pv.total_eng, 0) - ISNULL(esa.Percentage_of_SNB_evolution, 0) - ISNULL(pv.si_eng, 0)) * esa.BaseSalary > 0
	 ), cte_isi_source_currency AS (
		SELECT
				s.idpayee
			,	s.gender
			,	s.country
			,	CASE
					WHEN COALESCE(@currency, '') = 'Employee Currency' THEN increase_amount
					WHEN @currency = 'EUR' THEN increase_amount_EUR
					ELSE s.increase_amount_EUR / COALESCE(NULLIF(@ExchangeRatefor1EUR_currency, 0), 1)
				END AS increase_amount
		FROM cte_isi_source s
	 )
	SELECT
			cis.gender
	   ,	cis.country
	   ,	CAST(AVG(increase_amount) AS DECIMAL(18, 2)) AS salary_increase_amount 
	INTO #individual_salary_increase_amount
	FROM cte_isi_source_currency cis
	GROUP BY	cis.gender
			 ,	cis.country


	/* FINAL QUERY */
	DROP TABLE IF EXISTS #final_result
	SELECT 
			rc.Label as country
	  ,		CASE WHEN hc.Gender = 'M' THEN 'Male'
				 WHEN hc.Gender = 'F' THEN 'Female' END AS Gender
	  ,		hc.counted as headcount
	  ,		ISNULL(isi_pct.salary_increase_pct,0) AS salary_increase_pct
	  ,		ROUND(ISNULL(isi_amount.salary_increase_amount,0),2)  AS salary_increase_amount
	  ,		@geographical_zone_name as geographical_zone_name
	INTO #final_result
	FROM #hc_count_final hc
	JOIN Engie_View_REF_Country rc
		ON hc.country = rc.Code
	LEFT JOIN #individual_salary_increase_pct isi_pct
		ON hc.gender = isi_pct.gender
		AND hc.country = isi_pct.country
	LEFT JOIN #individual_salary_increase_amount isi_amount
		ON hc.gender = isi_amount.gender
		AND hc.country = isi_amount.country
	WHERE ISNULL(hc.Gender , '') <> ''
	GROUP BY rc.Label,hc.Gender, hc.counted, isi_pct.salary_increase_pct, isi_amount.salary_increase_amount

	DROP TABLE IF EXISTS #chart_max_interval_by_country
	SELECT country, cast(max(salary_increase_amount) + (max(salary_increase_amount * 0.3)) AS DECIMAL(18,0)) AS chart_max_interval
	INTO #chart_max_interval_by_country
	FROM #final_result
	GROUP BY country
	
	SELECT 
			fr.country
		,	fr.Gender
		,	fr.headcount
		,	fr.salary_increase_pct
		,	fr.salary_increase_amount
		,	fr.geographical_zone_name
		,	cmibc.chart_max_interval AS chart_max_interval
	FROM #final_result fr
	JOIN #chart_max_interval_by_country cmibc
		ON fr.country = cmibc.country


EXEC Engie_Update_Report_Logs_End @Id_log

END
GO

