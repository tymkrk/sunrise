
IF NOT EXISTS (SELECT TOP 1 1 FROM _tb_one_time_scripts_release_log WHERE script_name = '61_6_eng_341_grid_fields_naming')
 
	begin
        
        drop table if exists #new_columns_names
        select 
            pl.name_plan,
            gr.name_grid,
            gf.name_column,
            gf.id_column,
            concat(
            case
                when pl.name_plan like '%bonus capped' then 'GF_BC_'
                when pl.name_plan like '%bonus uncapped' then 'GF_BUC_'
                when pl.name_plan like '%bonus Utilities' then 'GF_BUT_'
                when pl.name_plan like '%bonus ExCom BP EC Leaders' then 'GF_BEC_'
                when pl.name_plan like '%exceptional bonus' then 'GF_EB_'
            end
            ,REPLACE(REPLACE(name_column,' ','_'),'%','pct')) as new_name_column
        into #new_columns_names
        from k_m_plans pl
        join k_m_type_plan tp
            on tp.id_type_plan = pl.id_type_plan
        join k_referential_grids gr
            on gr.id_grid = tp.id_base_grid
        join k_referential_grids_fields gf
            on gf.id_grid = gr.id_grid
        where name_column not like 'gf%'
            and name_column not in 
            ('fullname'
            ,'idPayee'
            ,'id_histo'
            ,'end_date_histo'
            ,'start_date'
            ,'end_date'
            ,'start_date_histo'
            )
        and name_plan like '%bonus%'
        
        update gf
            set name_column = ncn.new_name_column
        from k_referential_grids_fields gf
        join #new_columns_names ncn
            on ncn.id_column = gf.id_column


        insert into rps_Localization (tab_id, module_type, item_id, name, value,culture)
        select distinct 
            100,
            6,
            130,
            new_name_column,
            name_column,
            'en-US'
        from #new_columns_names



		insert into _tb_one_time_scripts_release_log (script_name, applied_on)
		VALUES ('61_6_eng_341_grid_fields_naming',GETUTCDATE());

	end

go
