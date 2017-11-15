/*-------------------------------------------------------------------------| 
|These grants should run before all the TDE activities through sys user.   |
|If the administrative user name is not ADMUSER then replace the           |
|ADMUSER with administrative user name (like ADMUSER1, ADMUSER2,..,etc).   |
|-------------------------------------------------------------------------*/
GRANT EXECUTE ON DBMS_REDEFINITION TO ADMUSER
/
GRANT SELECT ON DBA_USERS TO ADMUSER
/
GRANT SELECT ON V_$ENCRYPTION_WALLET TO ADMUSER
/
GRANT SELECT_CATALOG_ROLE TO ADMUSER
/
GRANT CREATE TABLESPACE TO ADMUSER
/
GRANT ALTER TABLESPACE TO ADMUSER
/
GRANT ALTER USER TO ADMUSER
/
GRANT DBA TO ADMUSER
/