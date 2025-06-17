CREATE  PROCEDURE [dbo].[Engie_ReportDS_Hierarchy_Security]
	@idUser int
	,@idProfile int
	,@idTree int
	,@idProcess int
	,@procName nvarchar(100) = NULL
AS
/*
	Author: Rafal Jura
	Date: 2024-05-13
	Description: returns filtered list of employees for tree
	Changes:
		(1) 18/06/2024 - Kamil Roganowicz - added @idTree and @idProcess null handling
		(2) 26/06/2024 - specific handling of some reports 
		(3) 17/07/2024 - Kamil Roganowicz - added sso handling + ebl report procedures handling
		(4) 29/07/2024 - Kamil Roganowicz - added kpi gender equity report handling
		(5) 09/09/2024 - Rafal Jura - ENG-192 added Bonus Proposals handling
		(6) 09/09/2024 - Rafal Jura - ENG-194 added Salary Increase Proposals handling
		(7) 25/09/2024 - Kamil Roganowicz - added kpi gender equity ebl ebl report handling
*/

BEGIN

	DECLARE 
		@id_profile_co_reward_manager				INT = (SELECT id_profile FROM k_profiles where  name_profile = ('Co Reward Manager')),
		@id_profile_reward_manager					INT = (SELECT id_profile FROM k_profiles where  name_profile = ('Reward Manager')),
		@id_profile_excom							INT = (SELECT id_profile FROM k_profiles where  name_profile = ('ExCom'))

	DECLARE 
		@codePayee_user								NVARCHAR(50),
		@idPayee_user								INT
	IF EXISTS(SELECT
						*
					FROM Engie_SSO_Switcher_Assignment ssa
					WHERE ssa.active_assignment = 1
					AND ssa.id_user_source = @idUser
					AND ssa.id_profile_destination = @idProfile)
		BEGIN
			SELECT
				@codePayee_user = py.codePayee,
				@idPayee_user	= py.idPayee
			FROM Engie_SSO_Switcher_Assignment ssa
			INNER JOIN k_users u
				ON u.id_user = ssa.id_user_destination
			INNER JOIN py_Payee py
				ON py.idPayee = u.id_external_user
			WHERE active_assignment = 1
			AND id_user_source = @idUser
			AND id_profile_destination = @idProfile
		END
		ELSE
		BEGIN
			SELECT
				@codePayee_user = py.codePayee,
				@idPayee_user	= py.idPayee
			FROM k_users u
			INNER JOIN py_Payee py
				ON py.idPayee = u.id_external_user
			WHERE u.id_user = @idUser
		END


--- special exception
	IF @idProfile = @id_profile_reward_manager and @codePayee_user in (select codePayee from Engie_Special_Handling_Co_Leader) and @procName in 
	(
	'Engie_ReportDS_Report_Budget_Follow_Up_Bonus'
	)
	BEGIN


		select distinct
			NULL as idTree,
			ps.idPayee
		from  Engie_Ref_Organization ec
		left join Engie_EC_Levels ecl
			on ec.GcrowdId = ecl.ec_lvl1
		left join Engie_REF_Business_Allocation bp 
			on bp.CoBusinessAllocationHeadGAIA = @codePayee_user
		left join Engie_BP_Levels bpl
			on bpl.bp_lvl1 = bp.BPGuid
		join Engie_Cache_View_Yearly_Campaign_Payees_Situations ps
			on ps.Code_GcrowdId = ecl.GcrowdId
			or ps.Code_BPGuid = bpl.BPGuid
		where ec.CoOrganizationHeadGAIA = @codePayee_user
			and ps.codePayee not in (
			ISNULL(bp.BusinessAllocationHeadGAIA,'')
			,ISNULL(bp.CoBusinessAllocationHeadGAIA,'')
			,ISNULL(ec.OrganizationHeadGAIA,'')
			,ISNULL(ec.CoOrganizationHeadGAIA,''))
			


	END


	ELSE IF @idProfile = @id_profile_reward_manager and @procName in 
	(
	'Engie_ReportDS_Report_Budget_Follow_Up_Bonus'
	, 'Engie_ReportDS_Report_EBL_EBL_Budget_EC', 'Engie_ReportDS_Report_EBL_EBL_Budget_BP'
	, 'Engie_ReportDS_Report_KPI_Gender_Equity', 'Engie_ReportDS_Report_KPI_Gender_Equity_Average_Bonus'
	, 'Engie_ReportDS_Bonus_Proposals', 'Engie_ReportDS_Bonus_Proposals_Currencies'
	, 'Engie_ReportDS_Salary_Increase_Proposals', 'Engie_ReportDS_Salary_Increase_Proposals_Currencies'
	, 'Engie_ReportDS_Report_KPI_Gender_Equity_EBL_EBL', 'Engie_ReportDS_Report_KPI_Gender_Equity_Average_Bonus_EBL_EBL'
	)
	BEGIN


		select distinct
			NULL as idTree,
			ps.idPayee
		from  Engie_Ref_Organization ec
		left join Engie_EC_Levels ecl
			on ec.GcrowdId = ecl.ec_lvl1
		left join Engie_REF_Business_Allocation bp 
			on bp.BusinessAllocationHeadGAIA = @codePayee_user
		left join Engie_BP_Levels bpl
			on bpl.bp_lvl1 = bp.BPGuid
		join Engie_Cache_View_Yearly_Campaign_Payees_Situations ps
			on ps.Code_GcrowdId = ecl.GcrowdId
			or ps.Code_BPGuid = bpl.BPGuid
		where ec.OrganizationHeadGAIA = @codePayee_user
			and ps.codePayee not in (
			ISNULL(bp.BusinessAllocationHeadGAIA,'')
			,ISNULL(bp.CoBusinessAllocationHeadGAIA,'')
			,ISNULL(ec.OrganizationHeadGAIA,'')
			,ISNULL(ec.CoOrganizationHeadGAIA,''))
			



	END


	ELSE IF @idProfile = @id_profile_co_reward_manager and @procName in 
	(
	'Engie_ReportDS_Report_Budget_Follow_Up_Bonus'
	, 'Engie_ReportDS_Report_EBL_EBL_Budget_EC', 'Engie_ReportDS_Report_EBL_EBL_Budget_BP'
	, 'Engie_ReportDS_Report_KPI_Gender_Equity', 'Engie_ReportDS_Report_KPI_Gender_Equity_Average_Bonus'
	, 'Engie_ReportDS_Bonus_Proposals', 'Engie_ReportDS_Bonus_Proposals_Currencies'
	, 'Engie_ReportDS_Salary_Increase_Proposals', 'Engie_ReportDS_Salary_Increase_Proposals_Currencies'
	, 'Engie_ReportDS_Report_KPI_Gender_Equity_EBL_EBL', 'Engie_ReportDS_Report_KPI_Gender_Equity_Average_Bonus_EBL_EBL'
	)
	BEGIN


		select distinct
			NULL as idTree,
			ps.idPayee
		from Engie_Ref_Organization ec
		left join Engie_EC_Levels ecl
			on ec.GcrowdId = ecl.ec_lvl1
		left join Engie_REF_Business_Allocation bp 
			on bp.CoBusinessAllocationHeadGAIA = @codePayee_user
		left join Engie_BP_Levels bpl
			on bpl.bp_lvl1 = bp.BPGuid
		join Engie_Cache_View_Yearly_Campaign_Payees_Situations ps 
			on ps.Code_GcrowdId = ecl.GcrowdId
			or ps.Code_BPGuid = bpl.BPGuid
		where ec.OrganizationHeadGAIA = @codePayee_user
			and ps.codePayee not in (
			ISNULL(bp.BusinessAllocationHeadGAIA,'')
			,ISNULL(bp.CoBusinessAllocationHeadGAIA,'')
			,ISNULL(ec.OrganizationHeadGAIA,'')
			,ISNULL(ec.CoOrganizationHeadGAIA,''))
			



	END

	ELSE IF @idProfile = @id_profile_excom and @procName in 
	(
	'Engie_ReportDS_Report_Budget_Follow_Up_Bonus', 'Engie_ReportDS_Report_Budget_Follow_Up_SA_Increase'
	, 'Engie_ReportDS_Report_EBL_EBL_Budget_EC','Engie_ReportDS_Report_EBL_EBL_Budget_BP'
	, 'Engie_ReportDS_Report_KPI_Gender_Equity', 'Engie_ReportDS_Report_KPI_Gender_Equity_Average_Bonus'
	, 'Engie_ReportDS_Bonus_Proposals', 'Engie_ReportDS_Bonus_Proposals_Currencies'
	, 'Engie_ReportDS_Salary_Increase_Proposals', 'Engie_ReportDS_Salary_Increase_Proposals_Currencies'
	, 'Engie_ReportDS_Report_KPI_Gender_Equity_EBL_EBL', 'Engie_ReportDS_Report_KPI_Gender_Equity_Average_Bonus_EBL_EBL'
	)
	BEGIN
		/*
			Excom can see employees from whom first level BP or EC is supervised by this Excom
		*/
		SELECT DISTINCT
			idTree,
			idPayee
		FROM (
				SELECT DISTINCT
					NULL as idTree,
					ps.idPayee
				FROM Engie_Cache_View_Yearly_Campaign_Payees_Situations ps 
				INNER JOIN Engie_EC_Levels ecl
					ON ecl.GcrowdId = ps.Code_GcrowdId
				INNER JOIN Engie_Ref_Organization o
					ON o.GcrowdId = ecl.ec_lvl1
				WHERE (o.ExcomSupervisorGAIA = @codePayee_user
					or o.CoExcomSupervisorGAIA = @codePayee_user)
					and ps.codePayee not in (
						ISNULL(o.ExcomSupervisorGAIA,'')
						,ISNULL(o.CoExcomSupervisorGAIA,''))
			


				UNION ALL

				SELECT DISTINCT
					NULL as idTree,
					ps.idPayee
				FROM Engie_Cache_View_Yearly_Campaign_Payees_Situations ps
				INNER JOIN Engie_BP_Levels bpl
					ON bpl.BPGuid = ps.Code_BPGuid
				INNER JOIN Engie_REF_Business_Allocation ba
					ON ba.BPGuid = bpl.bp_lvl1
				WHERE (ba.ExcomSupervisorGAIA = @codePayee_user
					OR ba.CoExcomSupervisorGAIA = @codePayee_user)
					and ps.codePayee not in (
						ISNULL(ba.ExcomSupervisorGAIA,'')
						,ISNULL(ba.CoExcomSupervisorGAIA,''))
			) a

	END

	ELSE
BEGIN
	declare
	  @assigned_idType int = 14,
	  @assigned_idChild int,
	  @assigned_top_node bit = 1

	IF ((@idTree IS NULL AND @idProcess IS NULL)
		OR  @idProfile in (@id_profile_co_reward_manager, @id_profile_reward_manager) and @procName in ('Engie_ReportDS_Report_Budget_Follow_Up_SA_Increase'))

	BEGIN

			SELECT DISTINCT
					NULL AS idTree
				,	id_payee AS idChild -- select *
			FROM Engie_Hierarchy_Security_User_Tree
			WHERE id_user = @idUser
				AND id_profile = @idProfile
				AND id_payee  <> coalesce(@idPayee_user, '')
	
	END
	ELSE
	BEGIN

			SELECT
				@assigned_idType = ntp.idType,
				@assigned_idChild = ntp.idChild,
				@assigned_top_node = CASE WHEN ntp.idParent = 0 THEN 1 ELSE 0 END
			FROM k_tree_security kts
			INNER JOIN k_users_profiles kup
			  ON kup.idUserProfile = kts.id_user_profile
			INNER JOIN hm_NodelinkPublished ntp
			  ON ntp.id = kts.id_tree_node_published
			WHERE kup.id_user = @idUser
				AND kup.id_profile = @idProfile
				AND ntp.idTree = @idTree		

			DROP TABLE IF EXISTS #temp_hierarchy_cte
			CREATE TABLE #temp_hierarchy_cte (
				idTree int,
				idType int,
				idChild int
			)

			;WITH org_node_tree AS (
				SELECT DISTINCT
					ntp.idTree,
					ntp.idChild,
					ntp.idType
				FROM k_tree_security kts
				INNER JOIN k_users_profiles kup
				  ON kup.idUserProfile = kts.id_user_profile
				INNER JOIN hm_NodelinkPublished ntp
				  ON ntp.id = kts.id_tree_node_published
				WHERE kup.id_user = @idUser
				 AND kup.id_profile = @idProfile
				 AND ntp.idTree = @idTree
			), hierarchy_cte AS (
				SELECT
					n.idTree,
					n.idType,
					n.idChild
				FROM hm_NodeLinkPublishedHierarchy n
				INNER JOIN (SELECT
								np.*
							FROM org_node_tree ont
							INNER JOIN hm_NodeLinkPublishedHierarchy np
								ON np.idTree = ont.idTree
								AND np.idChild = ont.idChild
								AND np.idType = ont.idType) nn
					ON nn.idTree = n.idTree
				WHERE n.hid.IsDescendantOf(nn.hid) = 1
			)
			INSERT INTO #temp_hierarchy_cte (idTree, idType, idChild)
			SELECT DISTINCT -- (12)
				idTree,
				idType,
				idChild
			FROM hierarchy_cte

			;WITH hierarchy_cte_filtered AS (
				SELECT
					c.idTree,
					c.idType,
					c.idChild
				FROM #temp_hierarchy_cte c
				INNER JOIN Engie_Hierarchy_Security_User_Tree hsut
					ON hsut.id_user = @idUser
					AND hsut.id_profile = @idProfile
					AND hsut.id_tree = @idTree
					AND hsut.id_payee = c.idChild
				WHERE c.idType = 14 --only payees
				AND (@assigned_top_node = 1
					OR
					(@assigned_top_node = 0 AND NOT (c.idType = @assigned_idType AND c.idChild = @assigned_idChild)) --if assigned to top node show all from hierarchy and population, if not show everyone under but assigned node
				)
			)
			--INSERT INTO #temp_hierarchy_cte_filtered (idTree, idChild)
			SELECT
				idTree,
				idChild
			FROM hierarchy_cte_filtered
				WHERE idChild <> coalesce(@idPayee_user, '')

		END
	END
END
GO

