CREATE PROCEDURE [dbo].[Engie_ReportDS_Bonus_Proposals]  
     @idUser int  
    ,@idProfile int  
  
AS  
/*  
 Author: Rafal Jura  
 Date: 2024-09-04  
 Description: stored procedure for Bonus Proposals report. Returns summed proposals in thousands on 1st level BP/EC  
 Changes:   
  2024-09-19 Kamil Roganowicz: if an employee is assigned to transversal, the report should include the employee in EC   
*/  
BEGIN  
 DECLARE   
      @Id_log int,  
      @ReportPstkName varchar(max),  
      @ParamPstkList varchar(max),  
      @date datetime,  
   @id_plan_capped int = (SELECT id_plan FROM k_m_plans WHERE name_plan LIKE '% - Bonus Capped'),  
   @id_plan_uncapped int = (SELECT id_plan FROM k_m_plans WHERE name_plan LIKE '% - Bonus Uncapped'),  
   @id_plan_utilities int = (SELECT id_plan FROM k_m_plans WHERE name_plan LIKE '% - Bonus Utilities'),  
   @id_plan_excom_bp_ec_leaders int = (SELECT id_plan FROM k_m_plans WHERE name_plan LIKE '% - Bonus ExCom BP EC Leaders'),  
   @id_plan_ebl_ebl int = (SELECT id_plan FROM k_m_plans WHERE name_plan LIKE '% - EBL - EBL'),  
   @Campaign_ID int,  
   @Effective_Date date,  
   @Year_YearlyCampaign int  
  
  SELECT  
   @Campaign_ID = ID,  
   @Effective_Date = Effective_Date,  
   @Year_YearlyCampaign = [Year]  
  FROM Engie_Param_Yearly_Campaign  
  WHERE ID_Status IN (2,3)  
  
    SET @date = getdate()  
    SET @ReportPstkName=OBJECT_NAME(@@PROCID)   
    SET @ParamPstkList = ''  
        +'@idUser = '+isnull(''''+convert(varchar(100),@idUser)+'''','NULL')  
        +', @idProfile = '+isnull(''''+convert(varchar(100),@idProfile)+'''','NULL')  
  
 DECLARE  
  @id_field_GF_BUC_Bonus int,  
  @id_field_GF_BC_Bonus_Amount_Proposal int,  
  @id_field_GF_BUT_Bonus_Amount_Proposal int,  
  @id_field_GR_BEC_Bonus_Amount_Proposal int,  
  @id_field_GR_EBL_Bonus_Amount_Prorated_Rounded int  
  
 /*  
  Log start  
 */  
    EXEC Engie_Insert_Report_Logs_Start @ReportPstkName,@ParamPstkList,@Id_log output  
   
 SELECT  
 -- @id_field_GF_BUC_Bonus = GF_BUC_Bonus,  
 -- @id_field_GF_BC_Bonus_Amount_Proposal = GF_BC_Final_Bonus_ToPaid, --GF_BC_Bonus_Amount_Proposal,  
 -- @id_field_GF_BUT_Bonus_Amount_Proposal = GF_BUT_Bonus_Amount_Proposal,  
  @id_field_GR_BEC_Bonus_Amount_Proposal = GR_BEC_Bonus_Amount_Proposal,  
  @id_field_GR_EBL_Bonus_Amount_Prorated_Rounded = GR_EBL_Bonus_Amount_Prorated_Rounded  -- select *
 FROM Engie_View_Ref_Field_List  

 set @id_field_GF_BC_Bonus_Amount_Proposal = (select id_field from k_m_fields where code_field = 'GF_BC_Bonus_EUR')
 set @id_field_GF_BUT_Bonus_Amount_Proposal = (select id_field from k_m_fields where code_field = 'GF_BUT_Bonus_Amount_EUR')
 set @id_field_GF_BUC_Bonus = (select id_field from k_m_fields where code_field = 'GF_BUC_Bonus')
  
 DROP TABLE IF EXISTS #currency_bonus_proposals  
 CREATE TABLE #currency_bonus_proposals (  
  idPayee int,  
  ID_YearlyCampaign int,  
  YearlyCampaign_Year int,  
  Currency_N nvarchar(3),  
  Currency_N1 nvarchar(3),  
  YearlyCampaign_Effective_Date date  
 )  
  
 DROP TABLE IF EXISTS #exchange_rate_current  
 CREATE TABLE #exchange_rate_current (  
  ExchangeRatefor1EUR decimal(18,4),  
  currency nvarchar(3),  
  EffectiveDate date  
 )  
   
 DROP TABLE IF EXISTS #exchange_rate_previous_year_1  
 CREATE TABLE #exchange_rate_previous_year_1 (  
  ExchangeRatefor1EUR decimal(18,4),  
  currency nvarchar(3),  
  EffectiveDate date  
 )  
   
 /*  
  Visibility  
 */  
    DROP TABLE IF EXISTS #visibility_bonus_proposals  
 CREATE TABLE #visibility_bonus_proposals (  
  idPayee int,  
  Currency_N nvarchar(10)  
 )  
  
 DROP TABLE IF EXISTS #temp_hierarchy_cte_filtered  
 CREATE TABLE #temp_hierarchy_cte_filtered (  
  idTree int,  
  idChild int  
 )  
  
 /*  
  Security  
 */  
 INSERT INTO #temp_hierarchy_cte_filtered (idTree, idChild)  
 EXEC Engie_ReportDS_Hierarchy_Security @idUser, @idProfile, NULL, NULL, @ReportPstkName  
  
 INSERT INTO #visibility_bonus_proposals (idPayee, Currency_N)  
    SELECT  
  ps.idPayee,  
  ps.Code_Currency  
    FROM #temp_hierarchy_cte_filtered c  
 INNER JOIN Engie_Cache_View_Yearly_Campaign_Payees_Situations ps  
  ON ps.idPayee = c.idChild  
  AND ps.ID_YearlyCampaign = @Campaign_ID  
 WHERE COALESCE(ps.RewardCategory, '') <> 'COMP&BEN'  
  
 DROP TABLE IF EXISTS #temp_hierarchy_cte_filtered  
  
 /*  
  Currencies for current and previous years  
 */  
 INSERT INTO #currency_bonus_proposals (idPayee, ID_YearlyCampaign, YearlyCampaign_Year, Currency_N, Currency_N1, YearlyCampaign_Effective_Date)  
 SELECT   
  ps.idPayee,   
  @Campaign_ID AS ID_YearlyCampaign,  
  @Year_YearlyCampaign,  
  ps.Currency_N,  
  histD.Currency_N1,  
  @Effective_Date  
 FROM #visibility_bonus_proposals ps  
 LEFT JOIN Engie_Cache_View_Historical_Campaign_Data histD  
  ON histD.idpayee = ps.idpayee  
  AND histD.id_yearlycampaign = @Campaign_ID  
  
 INSERT INTO #exchange_rate_current (ExchangeRatefor1EUR, currency, EffectiveDate)  
 SELECT ExchangeRatefor1EUR, currency, EffectiveDate FROM(  
  SELECT  
  exR.exchangeRatefor1EUR,  
     exR.currency,  
  exr.EffectiveDate,  
     row_number() over(partition by  exR.Family order by exR.EffectiveDate desc)  as rn  
  FROM  Engie_Exchange_Rates exR) as T  
 WHERE T.rn = 1  
  
 INSERT INTO #exchange_rate_previous_year_1 (ExchangeRatefor1EUR, currency, EffectiveDate)  
 SELECT ExchangeRatefor1EUR, currency, EffectiveDate FROM(  
  SELECT   
   exR.exchangeRatefor1EUR,  
   exR.currency,  
   exR.EffectiveDate,  
   row_number() over(partition by  exR.Family order by exR.EffectiveDate desc)  as rn  
  FROM  Engie_Exchange_Rates exR  
  WHERE exR.EffectiveDate <= DATEADD(year,-1,(SELECT TOP 1 Effective_Date FROM Engie_Param_Yearly_Campaign WHERE ID_Status IN (2,3)))) as T1  
 WHERE T1.rn = 1  
  
 /*  
  Final data  
  Returns on BP/EC and campaign level  
 */  
 SELECT  
  summary.ObjectName,  
  summary.campaign,  
  SUM(summary.Previous_Bonus_Eur) / 1000 AS Previous_Bonus_Eur,  
  SUM(summary.Current_Bonus_Eur) / 1000 AS Current_Bonus_Eur,  
  CASE  
   WHEN COALESCE(SUM(summary.Previous_Bonus_Eur), 0) = 0 AND COALESCE(SUM(summary.Current_Bonus_Eur), 0) = 0  
    THEN 0  
   ELSE (COALESCE(SUM(summary.Current_Bonus_Eur), 0) / NULLIF(SUM(summary.Previous_Bonus_Eur), 0)) - 1  
  END AS Evolution,  
  @Year_YearlyCampaign AS Campaign_Year,  
  @Year_YearlyCampaign - 1 AS Previous_Campaign_Year,  
  MAX(summary.campaign_order_int) AS campaign_order_int,  
  CASE WHEN summary.campaign = 'Uncapped' THEN 1 ELSE 0 END show_campaign_uncapped,  
  CASE WHEN summary.campaign = 'Capped' THEN 1 ELSE 0 END show_campaign_capped,  
  CASE WHEN summary.campaign = 'Excom BP EC Leaders' THEN 1 ELSE 0 END show_campaign_excom_bp_ec_leaders,  
  CASE WHEN summary.campaign = 'Utilities' THEN 1 ELSE 0 END show_campaign_utilities,  
  CASE WHEN summary.campaign = 'EBL-EBL' THEN 1 ELSE 0 END show_campaign_ebl_ebl  
 FROM (  
   SELECT  
    CASE WHEN bp.bp_name_lvl1 = 'TRANSVERSAL' THEN ec.ec_name_lvl1 ELSE COALESCE(bp.bp_name_lvl1, ec.ec_name_lvl1) END AS ObjectName,  
    a.idPayee,  
    a.Previous_Bonus_N1 * IIF(a.campaign = 'Uncapped', 1, COALESCE(erp1.ExchangeRatefor1EUR, 1)) Previous_Bonus_Eur,  
    v_bonus.input_value_numeric AS Current_Bonus_Eur,   --/ COALESCE(erc.ExchangeRatefor1EUR, 1) 
    a.campaign,  
    a.campaign_order_int  
   FROM (SELECT  
      idPayee,  
      Previous_Total_Bonus_N1 AS Previous_Bonus_N1,  
      'Capped' AS campaign,  
      Code_BPGuid,  
      Code_GcrowdId,  
      2 AS campaign_order_int  
     FROM Engie_Cache_View_Process_Bonus_Capped  
  
     UNION ALL  
  
     --SELECT  
     -- idPayee,  
     -- Previous_Total_Bonus_N1,  
     -- 'Excom BP EC Leaders' AS campaign,  
     -- Code_BPGuid,  
     -- Code_GcrowdId,  
     -- 4 AS campaign_order_int  
     --FROM Engie_Cache_View_Process_Bonus_ExCom_BP_EC_Leaders  
  
     --UNION ALL  
  
     SELECT  
      idPayee,  
      Previous_Total_Bonus_N1,  
      'Utilities' AS campaign,  
      Code_BPGuid,  
      Code_GcrowdId,  
      3 AS campaign_order_int  
     FROM Engie_Cache_View_Process_Bonus_Utility  
  
     UNION ALL  
  
     SELECT  
      idPayee,  
      Previous_Bonus_N1_EUR,  
      'Uncapped' AS campaign,  
      Code_BPGuid,  
      Code_GcrowdId,  
      1 AS campaign_order_int  
     FROM Engie_Cache_View_Process_BonusUncapped  
  
     --UNION ALL  
  
     --SELECT  
     -- ebl.idPayee,  
     -- ebl.Previous_Bonus_N1,  
     -- 'EBL-EBL' AS campaign,  
     -- ps.Code_BPGuid,  
     -- Code_GcrowdId,  
     -- 5 AS campaign_order_int  
     --FROM Engie_Cache_View_Process_EBL_EBL ebl  
     --INNER JOIN Engie_Cache_View_Yearly_Campaign_Payees_Situations ps  
     -- ON ps.idPayee = ebl.idPayee  
    ) a  
   LEFT JOIN Engie_BP_Levels bp  
    ON bp.BPGuid = a.Code_BPGuid  
   LEFT JOIN Engie_EC_Levels ec  
    ON ec.GcrowdId = a.Code_GcrowdId  
   INNER JOIN #visibility_bonus_proposals v  
    ON v.idPayee = a.idPayee  
   INNER JOIN #currency_bonus_proposals c  
    ON c.idPayee = a.idPayee  
   LEFT JOIN #exchange_rate_current erc  
    ON erc.currency = c.Currency_N  
   LEFT JOIN #exchange_rate_previous_year_1 erp1  
    ON erp1.currency = c.Currency_N1  
   INNER JOIN k_m_plans_payees_steps ps  
    --ON ps.id_plan IN (@id_plan_capped, @id_plan_ebl_ebl, @id_plan_excom_bp_ec_leaders, @id_plan_uncapped, @id_plan_utilities)  
    ON ps.id_plan IN (@id_plan_capped, @id_plan_uncapped, @id_plan_utilities)  

    AND ps.id_payee = a.idPayee  
   LEFT JOIN k_m_values v_bonus  
    ON v_bonus.id_step = ps.id_step  
    AND v_bonus.id_field IN (@id_field_GF_BC_Bonus_Amount_Proposal, @id_field_GF_BUC_Bonus, @id_field_GF_BUT_Bonus_Amount_Proposal, @id_field_GR_BEC_Bonus_Amount_Proposal, @id_field_GR_EBL_Bonus_Amount_Prorated_Rounded)  
  ) summary  
 GROUP BY summary.ObjectName, summary.campaign  
  
  
 /*  
  Log end  
 */  
 EXEC Engie_Update_Report_Logs_End @Id_log  
END
GO

