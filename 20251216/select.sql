SELECT 
		-- sf opportunities columns
		so.opp_number
		, so.opp_name
		, so.company_number
		, so.opp_type
		, so.opp_stage
		, so.sales_person_id
		, so.opp_territory
		, so.contracted_months
		, so.budgetary_offer
		, so.iot
		, so.sales_approval_date
		, so.fin_approval_date
		, so.closed_date
		, so.is_closed
		, so.is_deleted
		, so.amount
		, so.curr_code
		, so.object_cd
		, so.company_object_cd
		-- sf opportunities products columns
		,sop.opp_product_name
		--,sop.opp_number
		,sop.opp_product_code
		,sop.quantity
		,sop.duration_month
		,sop.service_type
		,sop.total_fov
		,sop.commission_order_value
		,sop.sales_price
		,sop.one_time_charge
		,sop.recurring_charge
		,sop.monthly_trafic_charge
		--,sop.is_deleted
		,sop.metric
		--,sop.object_cd
		,sop.product_object_cd
		--,sop.opp_object_cd
		,sop.NOV_MRC
		,sop.NOV_OTC
		,sop.OV_MRC
		,sop.OV_OTC
		,sop.NOV
		,sop.OV
		,sop.renewal_flag
		,sop.focus_factor
		,sop.service_type_group
		,sop.product_group
		,sop.recurring_charge_old
		,sop.NOV_GP
		,sop.PCT_GP_margin
		-- sf companies Columns
		--, company_data.company_number
		, company_data.start_date
		, company_data.end_date
		, company_data.company_name
		, company_data.company_short_name
		, company_data.a_number
		, company_data.company_account_mgr
		, company_data.is_active
		, company_data.bcch_flag
		--, company_data.object_cd
		--sf Products columns
		, sp.product_code
		, sp.product_name
		, sp.product_family
		--, sp.product_group
		, sp.product_type
		--, sp.curr_code
		--, sp.object_cd
	FROM dbo._tb_b2b_sf_opportunities so WITH (NOLOCK)
	LEFT JOIN dbo._tb_b2b_sf_opportunities_products sop WITH (NOLOCK)
	    ON sop.opp_object_cd = so.object_cd
	OUTER APPLY (
	    SELECT TOP 1
	          sc.id
	        , sc.company_name
	        , sc.a_number
			, sc.start_date
			, sc.end_date
			, sc.company_number
			, sc.company_short_name
			, sc.company_account_mgr
			, sc.is_active
			, sc.bcch_flag
	    FROM dbo._tb_b2b_sf_companies sc WITH (NOLOCK)
	    WHERE sc.object_cd = so.company_object_cd
	      AND sc.start_date <= so.closed_date
	      AND sc.end_date   >= so.closed_date
	    ORDER BY sc.start_date DESC
	) company_data
	LEFT JOIN dbo._tb_b2b_sf_products sp WITH (NOLOCK)
	    ON sp.object_cd = sop.product_object_cd
	WHERE so.closed_date >= DATEFROMPARTS(YEAR(GETDATE()) - 1, 1, 1);	
