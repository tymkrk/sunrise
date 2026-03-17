begin tran;
    with u as (
        select      u.id_user
                ,   firstname_user      = max(u.firstname_user)
                ,   lastname_user       = max(u.lastname_user)      
                ,   active_user_current = max(cast(u.active_user as int))
                ,   c                   = count(1)
        from        IAM_User_Profile iup
        left join   k_users u
            on      u.login_user = iup.UPN_login
        left join   py_Payee pp
            on      pp.idPayee = u.id_external_user
        where       user_profile in (
                    'B2B ADMIN'
                ,   'B2B SALES EMPLOYEE'
                ,   'B2B SALES MANAGER'
                ,   'B2B HR'
                ,   'B2B Finance Business Partnering')
        group by    u.id_user)
    select  [User name]             = u.firstname_user + ' ' + u.lastname_user
        ,   [Is currently active?]  = iif(u.active_user_current = 1, 'Yes', 'No')
        ,   [Session counter 2025] = c_2025.c
        ,   [Session counter 2024] = c_2024.c
        ,   [Session counter 2023] = c_2023.c
        ,   [Session counter 2022] = c_2022.c
    from    u
        outer apply (
        select  c = count(1)
        from    k_stats_user_session sus
        where   login_date between '2022-01-01' and '2022-12-31'
        and     sus.id_user = u.id_user
    ) c_2022
    outer apply (
        select  c = count(1)
        from    k_stats_user_session sus
        where   login_date between '2023-01-01' and '2023-12-31'
        and     sus.id_user = u.id_user
    ) c_2023
    outer apply (
        select  c = count(1)
        from    k_stats_user_session sus
        where   login_date between '2024-01-01' and '2024-12-31'
        and     sus.id_user = u.id_user
    ) c_2024
    outer apply (
        select  c = count(1)
        from    k_stats_user_session sus
        where   login_date between '2025-01-01' and '2025-12-31'
        and     sus.id_user = u.id_user
    ) c_2025
    order by    c_2025.c desc
rollback tran;
