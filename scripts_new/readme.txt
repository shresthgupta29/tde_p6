Step-by-step Guide|
==================|


========Oracle Wallet Manage before starting the steps=================|
                                                                       |
1.First, decide on the location of the Oracle wallet.                  |
Example the location is "/u01/app/oracle/wallet" directory.            |
Add the following entries into the client "sqlnet.ora" file, with your |
preferred wallet location.                                             |
                                                                       |
WALLET_LOCATION =                                                      |
   (SOURCE =                                                           |
     (METHOD = FILE)                                                   |
     (METHOD_DATA =                                                    |
       (DIRECTORY = /u01/app/oracle/wallet)                            |
     )                                                                 |
   )                                                                   |
                                                                       |
SQLNET.WALLET_OVERRIDE = TRUE                                          |
SSL_CLIENT_AUTHENTICATION = FALSE                                      |
SSL_VERSION = 0                                                        |
                                                                       |
2.Set the encryption key to the wallet.                                |
  (Run sqlplus in command prompt)                                      |
                                                                       |
$sqlplus sys/passwd as sysdba                                          |
sql>ALTER SYSTEM SET ENCRYPTION KEY IDENTIFIED BY "password";          |
                                                                       |
=======================================================================|

-------------------------------------------------------------------------------------------------------------------------------------------------------
Configuring keystore for 12c database
 The keystore is at container level and keys can be separate for pdbs.
 1)To setup TDE the location for the wallet needs to be set in sqlnet.ora. 
 eg ENCRYPTION_WALLET_LOCATION=   (SOURCE=     (METHOD=FILE)      (METHOD_DATA=       (DIRECTORY=/etc/ORACLE/WALLETS/orcl))).
 After logging into the database with SYSDBA or at least SYSKM role we can create a password protected wallet     
 2) SQL> administer key management create keystore '/etc/ORACLE/WALLETS/orcl' identified by tdecdb;   
 3)Next we open the keystore.     
    SQL> administer key management set keystore open identified by tdecdb container=all; 
  The container=all clause opens the wallet for all pdbs. If we only wanted to open the wallet for a select pdb we could have run container=<pdb>.
  With the wallet open a TDE key can be created. For Multitenant environments a TDE key can be used by all PDBs or each PDB can have a dedicated TDE key. 
    SQL> administer key management set key using tag 'cdb_shared' identified by tdecdb with backup using '/tmp/wallet.bak' container=all;
  The container=all creates a shared TDE key. If you want a PDB TDE key then change the container=all to the container=current.
  Make sure you are logged in to the PDB first.
-------------------------------------------------------------------------------------------------------------------------------------------------------
*** Not applicable for Compressed clear text application tablespaces. 

A.‘preferences.txt‘ is configuration file.
  Edit the ‘preferences.txt’ file so that it matches your environment and security requirements:

  alg varchar2(7 char) NOT NULL := 'AES256'; 
  owner varchar2(30 char) NOT NULL := 'ADMUSER'; 
  source_dir varchar2(128 char) NOT NULL := '/u01/opt/oradata/orcl/'; 
  target_dir varchar2(128 char) NOT NULL := '/u02/opt/oradata/orcl/';

  The string in alg can be '3DES168', 'AES128' (recommended default), 'AES192' or 'AES256'. 
  Note that 3DES168 does not benefit from hardware crypto acceleration provided by Intel AES-NI 
  (for Oracle databases running on Linux, incl. Oracle Exadata and Oracle Database Appliance) and 
  SPARC T4 and T5 CPUs (for Oracle databases that run on Oracle Solaris 11, incl. Oracle SPARC SuperCluster). 

  The owner is the Oracle database user who owns all Oracle Primavera P6 EPPM  objects, default is 'ADMUSER'. 
  Replace 'ADMUSER' with the user name applicable to your environment. 
  All other database users that come with Oracle Primavera P6 don’t own physical objects, but in the course of the 
  migration, their default tablespaces are automatically relocated to the encrypted tablespaces. 

  The source_dir is the directory that contains the current clear text application tablespaces. 
  Target_dir can point to the same or another directory or partition, allowing you to relocate the encrypted tablespaces.

B.As a database user with the ‘alter system’ privilege (for example ‘SYSTEM’/ 'SYS'), 
  open the TDE wallet to make the master encryption key available to the database:
  The “grants_before_tde.sql” script
  
  SYS> alter system set encryption wallet open identified by “password”;
  SYS> @/uo1/user1/Desktop/grants_before_tde;

C.The “validate-before.sql” script
  Create a snapshot of the current environment
  All following scripts are written to be executed as the Primavera application owner, by default ‘ADMUSER’!
  It is recommended to create a complete backup of the database before starting the migration.
  The script ‘validate-before.sql’ prompts for an existing clear-text tablespace and 
  generates a log file that contains the DDL (data definition language) commands that it extracts from the rich metadata 
  repository of the Oracle database. These commands were used to build the database as it is right now; each DDL command 
  for all tablespaces, tables, indexes, primary and foreign keys and spatial indexes is logged. The log file is to be kept 
  until the migration process has been completed.
  Note: ‘validate-before.sql’ does not make any changes to your database and can be run any number of times; 
  it takes approximately 30 to 90 seconds to complete.
  Oracle White Paper—TDE “OneCommand” for Primavera P6 EPPM 

D.The “dry_run” script
  The ‘dry_run.sql’ is an extension to the ‘validate-before.sql’ script in that it applies all the changes to the extracted 
  DDL and contains all Online Table Redefinition commands for one complete migration cycle of one tablespace. But, ‘dry_run.sql’,
  as the name implies, does not touch your database; it generates a log file that should be closely reviewed for any 
  inconsistencies. It can be run any number of times; it takes approximately 30 to 90 seconds to complete.

E.The “migrate” script
  The ‘migrate.sql’ script is very similar to ‘dry_run.sql’, with the one big difference that it actually migrates all objects 
  in the given clear text tablespace into its encrypted counterpart. The encrypted tablespaces are exact replicas of the 
  original clear-text tablespaces; apart from the added encryption syntax, no other parameters are changed. The script does not 
  rename the tablespaces, and does not delete the original tablespaces after the migration of their content to encrypted 
  tablespaces. These steps are to be completed manually.

  During the migration, Online Table Redefinition will add approximately 12 – 13% to your existing CPU load.
  There are 4 tablespaces in a standard Primavera P6 EPPM  installation:
  1.) PMDB_NDX1 (contains only indexes, no tables)
  2.) PMDB_LOB1 (contains only LOB data)
  3.) PMDB_DAT1 (contains tables, indexes, PKs, FKs, spatial and text indexes)
  4.) PMDB_PX_DAT1 (contains tables and indexes)

  It is mandatory to create the encrypted counterparts for the PMDB_NDX1 and PMDB_LOB1 tablespaces first, 
  so that dependent objects in PMDB_DAT1 and PMDB_PX_DAT1 can be created in these encrypted tablespaces (otherwise the script 
  will exit).

F.Post-migration steps
  1.Once the migration of all tablespaces is completed, there are some manual steps concerning spatial indexes, text indexes and 
    clear-text tablespaces:
  
  ADMUSER> select index_name from user_indexes 
             where index_type = 'DOMAIN' and table_name 
			          in (select table_name from user_tables where tablespace_name = 'PMDB_DAT1');
  INDEX_NAME ----------------------- 
  IX_PMDB_DAT1_38_1 (Interim text index)
  IX_PMDB_DAT1_141_1 (Interim spatial index)
  IX_PMDB_DAT1_63_1 (Interim spatial index)

  Drop the interim indexes:
  
  ADMUSER> drop index IX_PMDB_DAT1_38_1 force; 
  ADMUSER> drop index IX_PMDB_DAT1_141_1 force; 
  ADMUSER> drop index IX_PMDB_DAT1_63_1 force;

  (*): These extension numbers may be different in your database, so here aim is to drop domain indexes.
  (*): The number of index may be different in PPM database, so here aim is to drop domain indexes.
 
  2.Now rename all tablespaces and take the clear text tablespaces offline (as 'ADMUSER'):

  alter tablespace PMDB_PX_DAT1 rename to PMDB_PX_DAT1_backup; 
  alter tablespace PMDB_PX_DAT1_ENC rename to PMDB_PX_DAT1; 
  alter tablespace PMDB_PX_DAT1_backup offline normal;
  alter tablespace PMDB_DAT1 rename to PMDB_DAT1_backup; 
  alter tablespace PMDB_DAT1_ENC rename to PMDB_DAT1; 
  alter tablespace PMDB_DAT1_backup offline normal;
  alter tablespace PMDB_LOB1 rename to PMDB_LOB1_backup; 
  alter tablespace PMDB_LOB1_ENC rename to PMDB_LOB1; 
  alter tablespace PMDB_LOB1_backup offline normal;
  alter tablespace PMDB_NDX1 rename to PMDB_NDX1_backup; 
  alter tablespace PMDB_NDX1_ENC rename to PMDB_NDX1; 
  alter tablespace PMDB_NDX1_backup offline normal;

  3.Correct the metadata information of the spatial indexes (as 'SYS'):
  (*): This below 2 alter command and update command is only applicable for EPPM database as these spatial geometric index has been applied in EPPM database.

  --execute through ADMUSER connection if first two fails then try with second
  alter index NDX_LOCATION_GEO_LOCATION rebuild parameters ('TABLESPACE = PMDB_DAT1');
  alter index NDX_RSRCLOC_GEO_LOCATION rebuild parameters ('TABLESPACE = PMDB_DAT1');
  
  alter index NDX_LOCATION_GEO_LOCATION rebuild parameters ('TABLESPACE = PMDB_DAT1');
  alter index NDX_RSRCLOC_GEO_LOCATION rebuild parameters ('TABLESPACE = PMDB_DAT1');
  
  --execute through SYS connection
  update mdsys.sdo_index_metadata_table set sdo_tablespace = 'PMDB_DAT1' 
     where sdo_index_name = 'NDX_LOCATION_GEO_LOCATION' and sdo_index_owner = 'ADMUSER';
  update mdsys.sdo_index_metadata_table set sdo_tablespace = 'PMDB_DAT1' 
     where sdo_index_name = 'NDX_RSRCLOC_GEO_LOCATION' and sdo_index_owner = 'ADMUSER';
 
  After confirming that the Primavera application runs seamlessly off encrypted tablespaces, 
  the original clear-text tablespaces can now be deleted; as 'ADMUSER':
  
  --execute through SYS connection
  drop tablespace PMDB_PX_DAT1_backup including contents and datafiles; 
  drop tablespace PMDB_DAT1_backup including contents and datafiles; 
  drop tablespace PMDB_LOB1_backup including contents and datafiles; 
  drop tablespace PMDB_NDX1_backup including contents and datafiles;

G.Log in as sysdba and: SYS> revoke execute on DBMS_REDEFINITION from ADMUSER;

  Final validation
  ADMUSER> select tablespace_name, encrypted from user_tablespaces;
  TABLESPACE_NAME ENC -------------------------- --- 
  <default tablespaces> NO 
  PMDB_LOB1 YES 
  PMDB_NDX1 YES 
  PMDB_DAT1 YES 
  PMDB_PX_DAT1 YES

  Generate log files by running ‘validate-after.sql’ and compare the “validate” - log files next to each other, 
  for example with “Meld” in Linux or “WinMerge” in Windows. There should be only minor differences, for example:
   Table name, index name or any database object name with $ symbol  difference.
      
H.The “grants_after_tde” script
  Log in as sysdba and:
  SYS> @/uo1/user1/Desktop/grants_after_tde;

   


