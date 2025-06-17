CREATE VIEW [dbo].[Engie_View_REF_Employee]
AS
  
    SELECT DISTINCT
		py.codepayee as EmployeeId,
		CONCAT(py.LastName, ' ',py.FirstName) AS FullName
    FROM py_Payee py
	WHERE ISNULL(ss_nb,'') <>'Desk'
		AND idPayee > 0
