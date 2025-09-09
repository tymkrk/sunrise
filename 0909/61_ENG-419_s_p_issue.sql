IF NOT EXISTS(SELECT * FROM _tb_one_time_scripts_release_log WHERE script_name = '61_ENG-419_s_p_issue')
BEGIN

    declare @Engie_Param_Sales_Minus_Purchases_id int =  (select id_table_view from k_referential_tables_views where name_table_view = 'Engie_Param_Sales_Minus_Purchases')

    update k_referential_tables_views_fields 
    set is_unique = 1
    where id_table_view = @Engie_Param_Sales_Minus_Purchases_id
    and name_field = 'ID'
    and isnull(is_unique,0) = 0


	INSERT INTO _tb_one_time_scripts_release_log (script_name, applied_on)
	VALUES ('61_ENG-419_s_p_issue', GETUTCDATE());
END
GO