BEGIN
DBMS_MACADM.CREATE_REALM(
realm_name    => 'P6AppsVault',
description   => 'Securing P6 ADMUSER tables',
enabled       => DBMS_MACUTL.G_YES,
audit_options => DBMS_MACUTL.G_REALM_AUDIT_FAIL + DBMS_MACUTL.G_REALM_AUDIT_SUCCESS,
realm_type    => 1);
END;
/

BEGIN
DBMS_MACADM.ADD_OBJECT_TO_REALM(
realm_name   => 'P6AppsVault',
object_owner => 'ADMUSER',
object_name  => '%',
object_type  => 'TABLE');
END;
/

BEGIN
DBMS_MACADM.ADD_AUTH_TO_REALM(
realm_name  => 'P6AppsVault',
grantee     => 'ADMUSER',
auth_options => DBMS_MACUTL.G_REALM_AUTH_OWNER);
END;
/


BEGIN
DBMS_MACADM.ADD_AUTH_TO_REALM(
realm_name  => 'P6AppsVault',
grantee     => 'PRIVUSER',
auth_options => DBMS_MACUTL.G_REALM_AUTH_PARTICIPANT);
END;
/

BEGIN
DBMS_MACADM.ADD_AUTH_TO_REALM(
realm_name  => 'P6AppsVault',
grantee     => 'PUBUSER',
auth_options => DBMS_MACUTL.G_REALM_AUTH_PARTICIPANT);
END;
/










