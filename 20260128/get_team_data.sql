/****** Object:  StoredProcedure [dbo].[_sp_b2b_team_data_get]    Script Date: 1/28/2026 11:20:05 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER procedure [dbo].[_sp_b2b_team_data_get]
	@plan_id							int
,	@static_force						bit
,	@type								varchar(100)
,	@team_definition_dynamic			varchar(100)
,	@team_definition_static				varchar(100)
,	@achievement_calculation_individual varchar(100)
as
begin
	insert into #team_data
	select		type					= @type
			,	tf.person_id
			,	tf.metric_code
			,	tf.segment_code
			,	tf.achievement_calculation
			,	tf.team_definition
			,	date_checked			= tf.date
			,	team_name
			,	team_name_eop			= iif(@type = 'PLAN_EMPLOYEES'
											,	first_value(team_name) over (
													partition by tf.person_id, tf.metric_code, tf.segment_code
													order by tf.date desc
													rows between unbounded preceding and unbounded following)
											,	null)
			,	id_filter				= tf.id_filter
			,	id_filter_type			= tf.id_filter_type
			,	team_data.team
			,	team_data.unit
			,	team_data.title
			,	team_data.profile
			,	team_data.level_1
			,	team_data.level_2
			,	team_data.level_3
			,	team_data.level_4		
	from	#team_filter tf
	join	_tb_b2b_targets_definition td
		on td.target_code = tf.metric_code
		and td.year = datepart(year, tf.date)
	join	_vw_b2b_value_datasource_mapping vdm 
		on	vdm.value_type = COALESCE(td.value_type, td.target_code)
		and	vdm.year = datepart(year, tf.date)
	outer apply (
		select	team
			,	unit
			,	title
			,	profile
			,	level_1
			,	level_2
			,	level_3
			,	level_4
		from	dbo._fn_b2b_get_team_data (tf.person_id, tf.date, 1, vdm.datasource_type)
	) team_data
	left join	_tb_b2b_team_definition_dynamic tdd
		on		tdd.id_b2b_plan = @plan_id
		and		tdd.metric_code = tf.metric_code			
		and		tf.team_definition = @team_definition_dynamic
		and		(tf.segment_data_flag = 0 or tdd.segment_code = tf.segment_code)
	left join	_tb_b2b_team_definition_static tds
		on		tds.id_b2b_plan = @plan_id
		and		tds.metric_code = tf.metric_code
		and		tf.team_definition = @team_definition_static
		and		(tf.segment_data_flag = 0 or tds.segment_code = tf.segment_code)
	outer apply (
		select	team_name	=
					iif(tf.achievement_calculation = @achievement_calculation_individual, tf.person_id, 
						case 
							when tf.team_definition = @team_definition_dynamic then
								iif(tdd.team		= 1					,	team_data.team		,	'{1}') +
								iif(tdd.unit		= 1					,	team_data.unit		,	'{2}') +
								iif(tdd.title		= 1					,	team_data.title		,	'{3}') +
								iif(tdd.profile		= 1					,	team_data.profile	,	'{4}') +
								iif(tdd.level_1		= 1					,	team_data.level_1	,	'{5}') +
								iif(tdd.level_2		= 1					,	team_data.level_2	,	'{6}') +
								iif(tdd.level_3		= 1					,	team_data.level_3	,	'{7}') +
								iif(tdd.level_4		= 1					,	team_data.level_4	,	'{8}')
							when tf.team_definition = @team_definition_static and @static_force = 1 then
								isnull(tds.team, '{1}') + 
								isnull(tds.unit, '{2}') + 
								isnull(tds.title, '{3}') + 
								isnull(tds.profile, '{4}') + 
								isnull(tds.level_1, '{5}') + 
								isnull(tds.level_2, '{6}') + 
								isnull(tds.level_3, '{7}') + 
								isnull(tds.level_4, '{8}')
							when tf.team_definition = @team_definition_static and @static_force = 0 then
								iif(	((tds.team		is null or tds.team		= team_data.team)
									and	(tds.unit		is null or tds.unit		= team_data.unit)
									and	(tds.title		is null or tds.title	= team_data.title)
									and	(tds.profile	is null or tds.profile	= team_data.profile)
									and	(tds.level_1	is null or tds.level_1	= team_data.level_1)
									and	(tds.level_2	is null or tds.level_2	= team_data.level_2)
									and	(tds.level_3	is null or tds.level_3	= team_data.level_3)
									and	(tds.level_4	is null or tds.level_4	= team_data.level_4))
									,	iif(tds.team	= team_data.team	,	team_data.team		,	'{1}') +
										iif(tds.unit	= team_data.unit	,	team_data.unit		,	'{2}') +
										iif(tds.title	= team_data.title	,	team_data.title		,	'{3}') +
										iif(tds.profile	= team_data.profile	,	team_data.profile	,	'{4}') +
										iif(tds.level_1	= team_data.level_1	,	team_data.level_1	,	'{5}') +
										iif(tds.level_2	= team_data.level_2	,	team_data.level_2	,	'{6}') +
										iif(tds.level_3	= team_data.level_3	,	team_data.level_3	,	'{7}') +
										iif(tds.level_4	= team_data.level_4	,	team_data.level_4	,	'{8}')
									,	null)
							else null
						end)
	) t10			
where	team_name is not null;
end;
