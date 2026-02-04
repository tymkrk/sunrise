DECLARE @ssoid nvarchar(50) = 'd201213a-9c72-400a-ba83-37a813ec84e5',
		@firstname nvarchar(100) ='Lukasz',
		@lastname nvarchar(100) = 'Przywara',
		@login nvarchar(100) = 'lukasz.przywara@beqom.com'

------------------------------------------------
---

DECLARE @id_parameter int
BEGIN TRAN

INSERT INTO k_users_parameters ([defaultProfileId],[cultureParamsUsed],[thousandSeparator],[decimalSeparator],[datetimeFormat],[dateFormat],[hideUserPanelAlways],[numberOfDaysBoxItems],[dynamicNotification],[autoLoadLastSelectedProcess],[lastSelectedProcess],[autoLoadCurrentPeriod],[culture],[defaultTree],[messagePosition],[cultureUsedInReports])
VALUES(0,0,',','.','d-M-Y H:i:s','d-M-Y',0,20,0,1,NULL,1,'en-US',NULL,'br',0)

SELECT @id_parameter = @@identity

INSERT INTO k_users ([id_external_user],[firstname_user],[lastname_user],[login_user],[domainName],[ldapSid],[ntLoginName],[password_user],[isadmin_user],[date_created_user],[date_modified_user],[nb_attempt_user],[culture_user],[stylesheet_user],[active_user],[comments_user],[mail_user],[id_owner],[id_user_parameter],[idExternalSSO],[date_modified_password],[id_source_tenant],[id_source],[id_change_set])
VALUES(NULL,@firstname,@lastname,@login,NULL,NULL,NULL,'',1,GETDATE(),GETDATE(),0,'en-US',-1,1,NULL,@login,-1,@id_parameter,@ssoid,GETDATE(),NULL,NULL,NULL)

SELECT @id_parameter = @@identity

INSERT INTO k_users_profiles (id_user, id_profile)
VALUES (@id_parameter, -1)

COMMIT
PRINT 'Successfully inserted'




------------------------------------------------
------------------------------------------------
------------------------------------------------
------------------------------------------------
------------------------------------------------




DECLARE @firstname nvarchar(100) = ''
		,@lastname nvarchar(100) = ''
		,@email nvarchar(100) = ''
		,@codePayee nvarchar(50) = ''
		,@idPayee int
		,@idHisto int
		,@id_parameter int


BEGIN TRAN

INSERT INTO py_Payee (codePayee, is_active, lastname, firstname, email)
VALUES (@codePayee, 1, @lastname, @firstname, @email)

SELECT @idPayee = @@identity

--SELECT *, start_date_histo FROM py_PayeeHisto
INSERT INTO py_PayeeHisto (start_date_histo, end_date_histo, idPayee, codePayee, firstname, lastname, email)
VALUES ('1900-01-01 00:00:00.000', '9999-12-31 00:00:00.000', @idPayee, @codePayee, @firstname, @lastname, @email)

SELECT @idHisto = @@identity

INSERT INTO py_PayeeExt (id_histo, idPayee, emplid, email_address)
VALUES (@idHisto, @idPayee, @codePayee, @email)


--------------------------------------------
-- setup user
INSERT INTO k_users_parameters ([defaultProfileId],[cultureParamsUsed],[thousandSeparator],[decimalSeparator],[datetimeFormat],[dateFormat],[hideUserPanelAlways],[numberOfDaysBoxItems],[dynamicNotification],[autoLoadLastSelectedProcess],[lastSelectedProcess],[autoLoadCurrentPeriod],[culture],[defaultTree],[messagePosition],[cultureUsedInReports])
VALUES(0,0,',','.','d-M-Y H:i:s','d-M-Y',0,20,0,1,NULL,1,'en-US',NULL,'br',0)

SELECT @id_parameter = @@identity

INSERT INTO k_users (id_external_user, firstname_user, lastname_user, login_user, isadmin_user, date_created_user, date_modified_user, nb_attempt_user, culture_user, stylesheet_user, active_user, mail_user, id_owner, id_user_parameter, password_user)
VALUES (@idPayee, @firstname, @lastname, @email, 0, GETDATE(), GETDATE(), 0, 'en-US', -1, 1, @email, -1, @id_parameter, '')


COMMIT




