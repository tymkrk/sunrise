
IF NOT EXISTS (SELECT TOP 1 1 FROM _tb_one_time_scripts_release_log WHERE script_name = '61_5_eng_341_add_info_fields_exec_procs_fix')
 
	begin
        EXEC Engie_Post_Save_Values_Bonus_Utility
        EXEC Engie_Post_Save_Values_Bonus_ExCom_BP_EC_Leaders
        EXEC Engie_Post_Save_Values_Bonus_Capped
        EXEC Engie_Post_Save_Values_BonusUnCapped


		insert into _tb_one_time_scripts_release_log (script_name, applied_on)
		VALUES ('61_5_eng_341_add_info_fields_exec_procs_fix',GETUTCDATE());

	end

go
