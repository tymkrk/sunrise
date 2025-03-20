

begin tran


DECLARE @id_b2b_plan INT



DECLARE c CURSOR FOR
select id from _tb_b2b_plan where year = 2025

OPEN c;

FETCH NEXT FROM c
INTO @id_b2b_plan

WHILE @@FETCH_STATUS = 0
BEGIN


	exec _sp_b2b__tb_b2b_plan_validation @id_b2b_plan, 'save_post'

	FETCH NEXT FROM c INTO @id_b2b_plan

END

CLOSE c;
DEALLOCATE c;


update _tb_b2b_payment_dates_regular_periods set accelerated = 0 where year = 2025 and period <> 5
update _tb_b2b_payment_dates_regular_periods set accelerated = 1 where year = 2025 and period = 5

update pd
set pd.accelerated = pdrp.accelerated 
from _tb_b2b_payment_dates_regular_periods pdrp
join _tb_b2b_payment_dates pd
	on pd.id_b2b_plan = pdrp.id_b2b_plan
	and pd.year = pdrp.year
	and pd.period = pdrp.period
	and pd.year_to_date = 0
where	pdrp.year = 2025

update pd
set pd.accelerated = 0 
from _tb_b2b_payment_dates pd
	where pd.year_to_date = 1
	and	pd.year = 2025

rollback


