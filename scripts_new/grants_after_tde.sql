/*-------------------------------------------------------------------------| 
|These grants should run after all the TDE activities through sys user.    |
|If the administrative user name is not ADMUSER then replace the           |
|ADMUSER with administrative user name (like ADMUSER1, ADMUSER2,..,etc).   |
|-------------------------------------------------------------------------*/
REVOKE EXECUTE ON DBMS_REDEFINITION FROM ADMUSER
/
REVOKE SELECT ON DBA_USERS FROM ADMUSER
/
REVOKE SELECT ON V_$ENCRYPTION_WALLET FROM ADMUSER
/
REVOKE SELECT_CATALOG_ROLE FROM ADMUSER
/
REVOKE CREATE TABLESPACE FROM ADMUSER
/
REVOKE ALTER TABLESPACE FROM ADMUSER
/
REVOKE ALTER USER FROM ADMUSER
/
REVOKE DBA FROM ADMUSER
/