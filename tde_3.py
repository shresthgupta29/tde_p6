import os
import shutil
import subprocess
from subprocess import Popen, PIPE
from config import *
from inspect import currentframe , getframeinfo
def get_linenumber():
	cf=currentframe()
	return cf.f_back.f_lineno
os.putenv('ORACLE_HOME',oracle_home)
os.putenv('JAVA_HOME',java_home)


try:
	os.chdir(p6db)
except OSError as err:
	print("Error At line {} : {}".format(str(get_linenumber()),err))
	exit()

src = cwd+'/scripts_new/dbsetup.properties'
dest = p6db+'/dbsetup.properties'

try:
	shutil.copyfile(src,dest)
except OSError as err:
	print ('Unable to copy dbsetup.properties file.')
	print("Error At line {} : {}".format(str(get_linenumber()),err))
	exit()
print ('dbsetup.properties copied successfully')


print "YOUR ARE GOOD TO GO :)"

try:
	os.chdir(oracle_home+'/bin')
except OSError as err:
	print("Error At line {} : {}".format(str(get_linenumber()),err))
	exit()

subprocess.call('./netca -silent -responseFile '+client_path+'/response/netca.rsp',shell=True)

try:
	os.chdir(oracle_home+'/bin')
except OSError as err:
	print("Error At line {} : {}".format(str(get_linenumber()),err))
	exit()

subprocess.call('./dbca -silent -createDatabase -templateName General_Purpose.dbc -gdbName '+cdb+' -sid '+cdb+' -createAsContainerDatabase true -numberOfPdbs 1 -pdbName '+pgdb+' -pdbadminUsername admin -pdbadminPassword '+admin_pass+' -SysPassword '+admin_pass+' -SystemPassword '+admin_pass+' -emConfiguration NONE -storageType FS -datafileDestination /u01/app/pgbuora/oradata -recoveryAreaDestination /u01/fra -recoveryAreaSize 3200  -characterSet AL32UTF8 -memoryPercentage 40 -enableArchive true -redoLogFileSize 100', shell=True)

try:
	os.chdir(oracle_home+'/network/admin')
	tnsnames = open("tnsnames.ora", "r")
except OSError as e:
	print("Error At line {} : {}".format(str(get_linenumber()),err))
	exit()

line = tnsnames.readline()
while not (line.startswith('LISTENER_'+cdb.upper())):
	line=tnsnames.readline()
line=tnsnames.readline()
x= len(line)
port = line[x-7:-3]
print port
tnsnames.close()

with open("tnsnames.ora", "a") as myfile:	
    myfile.write("\n\n"+pgdb.upper()+" =\n  (DESCRIPTION =\n    (ADDRESS = (PROTOCOL = TCP)(HOST = "+host+")(PORT = "+port+"))\n    (CONNECT_DATA =\n      (SERVER = DEDICATED)\n      (SERVICE_NAME = "+pgdb+")\n    )\n  )")

if not os.path.exists(wallet_location):
	os.makedirs(wallet_location)

os.chdir(oracle_home+'/network/admin')
with open("sqlnet.ora", "a") as myfile:
    myfile.write("\nENCRYPTION_WALLET_LOCATION=\n (SOURCE=\n  (METHOD=FILE)\n   (METHOD_DATA=\n    (DIRECTORY="+wallet_location+")))")

#-------------------Creating Wallet--------------------------------------
conn = 'sys/'+admin_pass+'@'+cdb+' as sysdba'
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('administer key management create keystore \''+wallet_location+'\' identified by admin123;')
(stdout,stderr)=session.communicate()
print stdout
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('administer key management set keystore open identified by admin123 container=all;')
(stdout,stderr)=session.communicate()
print stdout
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('administer key management set key using tag "cdb_shared" identified by admin123 with backup using "/tmp/wallet.bak" container=current;')
(stdout,stderr)=session.communicate()
print stdout
conn = 'sys/'+admin_pass+'@'+pgdb+' as sysdba'
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('administer key management set key using tag "cdb_shared" identified by admin123 with backup using "/tmp/walletp.bak" container=current;')
(stdout,stderr)=session.communicate()

#-----------MANUAL SCRIPT BEFORE INSTALL-------------------------------
try:
	os.chdir(cwd+'/scripts_new')
except OSError as e:
	print("Error At line {} : {}".format(str(get_linenumber()),err))
	exit()

conn = 'sys/'+admin_pass+'@'+pgdb+' as sysdba'
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('@'+cwd+'/scripts_new/manual_script_before_install;')
print session.communicate()

#-----------------------DBSETUP FROM FILE-------------------------

try:
	os.chdir(p6db)
except OSError as e:
	print("Error At line {} : {}".format(str(get_linenumber()),err))
	exit()

with open('dbsetup.properties','r') as file :
	filedata = file.read()
con_str = 'system/'+admin_pass+'@oracle:'+host+':'+port+'/'+pgdb
print con_str
filedata = filedata.replace('system/Manager1@oracle:blr00aoh.idc.oracle.com:1521/pdb',con_str)

with open('dbsetup.properties','w') as file :
	file.write(filedata)
print "Done replace"

try:
	os.chdir(p6db)
	subprocess.call('chmod 777 *',shell=True)
	os.chdir(p6db)
	subprocess.call('./dbsetup.sh -readfromfile /dbsetup.properties',shell=True)
except OSError as e:
	print("Error At line {} : {}".format(str(get_linenumber()),err))
	exit()
#--------------------------------------GRANTS BEFORE TDE------------------
conn = 'sys/'+admin_pass+'@'+pgdb+' as sysdba'
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('@'+cwd+'/scripts_new/grants_before_tde;')
(stdout,stderr)=session.communicate()
stdout_lines = stdout.split("\n")
for lines in stdout_lines:
	print lines

#--------------------------------------------VALIDATE BEFORE---------------------------------
conn = 'admuser/admuser@'+pgdb
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('@'+cwd+'/scripts_new/validate-before_1')
(stdout,stderr)=session.communicate()
stdout_lines = stdout.split("\n")
for lines in stdout_lines:
	print lines

session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('@'+cwd+'/scripts_new/validate-before_2')
(stdout,stderr)=session.communicate()
stdout_lines = stdout.split("\n")
for lines in stdout_lines:
	print lines
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('@'+cwd+'/scripts_new/validate-before_3')
(stdout,stderr)=session.communicate()
stdout_lines = stdout.split("\n")
for lines in stdout_lines:
	print lines
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('@'+cwd+'/scripts_new/validate-before_4')
(stdout,stderr)=session.communicate()
stdout_lines = stdout.split("\n")
for lines in stdout_lines:
	print lines
#-----------------------------------DRY_RUN------------------------------------------------------
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('@'+cwd+'/scripts_new/dry_run_1')
(stdout,stderr)=session.communicate()
stdout_lines = stdout.split("\n")
for lines in stdout_lines:
	print lines
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('@'+cwd+'/scripts_new/dry_run_2')
(stdout,stderr)=session.communicate()
stdout_lines = stdout.split("\n")
for lines in stdout_lines:
	print lines
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('@'+cwd+'/scripts_new/dry_run_3')
(stdout,stderr)=session.communicate()
stdout_lines = stdout.split("\n")
for lines in stdout_lines:
	print lines
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('@'+cwd+'/scripts_new/dry_run_4')
(stdout,stderr)=session.communicate()
stdout_lines = stdout.split("\n")
for lines in stdout_lines:
	print lines
#-----------------------------------MIGRATE-----------------------------------------------------------------
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('@'+cwd+'/scripts_new/migrate_1')
(stdout,stderr)=session.communicate()
stdout_lines = stdout.split("\n")
for lines in stdout_lines:
	print lines
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('@'+cwd+'/scripts_new/migrate_2')
(stdout,stderr)=session.communicate()
stdout_lines = stdout.split("\n")
for lines in stdout_lines:
	print lines
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('@'+cwd+'/scripts_new/migrate_3')
(stdout,stderr)=session.communicate()
stdout_lines = stdout.split("\n")
for lines in stdout_lines:
	print lines
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('@'+cwd+'/scripts_new/migrate_4')
(stdout,stderr)=session.communicate()
stdout_lines = stdout.split("\n")
for lines in stdout_lines:
	print lines

#--------------------------------------POST MIGRATION---------------------------------------------------
conn = 'admuser/admuser@'+pgdb
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('select index_name from user_indexes where index_type = \'DOMAIN\' and table_name in (select table_name from user_tables where tablespace_name = \'PMDB_DAT1\');')
(stdout,stderr)=session.communicate()
stdout_lines = stdout.split("\n")
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('drop index ' + stdout_lines[3] + 'force'+';')
(stdout,stderr)=session.communicate()
print stdout
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('drop index ' + stdout_lines[4] + 'force'+';')
(stdout,stderr)=session.communicate()
print stdout
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('drop index ' + stdout_lines[5] + 'force'+';')
(stdout,stderr)=session.communicate()
print stdout


conn = 'admuser/admuser@'+pgdb
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('alter tablespace PMDB_PX_DAT1 rename to PMDB_PX_DAT1_backup;')
(stdout,stderr)=session.communicate()
print stdout
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('alter tablespace PMDB_PX_DAT1_ENC rename to PMDB_PX_DAT1;')
(stdout,stderr)=session.communicate()
print stdout
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('alter tablespace PMDB_PX_DAT1_backup offline normal;')
(stdout,stderr)=session.communicate()
print stdout
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('alter tablespace PMDB_DAT1 rename to PMDB_DAT1_backup;')
(stdout,stderr)=session.communicate()
print stdout
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('alter tablespace PMDB_DAT1_ENC rename to PMDB_DAT1;')
(stdout,stderr)=session.communicate()
print stdout
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('alter tablespace PMDB_DAT1_backup offline normal;')
(stdout,stderr)=session.communicate()
print stdout
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('alter tablespace PMDB_LOB1 rename to PMDB_LOB1_backup;')
(stdout,stderr)=session.communicate()
print stdout
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('alter tablespace PMDB_LOB1_ENC rename to PMDB_LOB1;')
(stdout,stderr)=session.communicate()
print stdout
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('alter tablespace PMDB_LOB1_backup offline normal;')
(stdout,stderr)=session.communicate()
print stdout
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('alter tablespace PMDB_NDX1 rename to PMDB_NDX1_backup;')
(stdout,stderr)=session.communicate()
print stdout
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('alter tablespace PMDB_NDX1_ENC rename to PMDB_NDX1;')
(stdout,stderr)=session.communicate()
print stdout
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('alter tablespace PMDB_NDX1_backup offline normal;')
(stdout,stderr)=session.communicate()
print stdout



conn = 'admuser/admuser@'+pgdb
session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
session.stdin.write('select tablespace_name, encrypted from user_tablespaces;')
(stdout,stderr)=session.communicate()
print stdout

print ('--------------------------------------')
print ('|	TDE Done Successfully 	       |')
print ('| host: '+host+'      |')
print ('| port : '+port+'             |')
print ('--------------------------------------')



dbVault = raw_input("Wanna configure this db for db vault ? (y/n)")
if dbVault=='y':

	conn = 'sys/'+admin_pass+'@'+cdb+' as sysdba'
	try:	
		session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	except OSError as e:
		print e
		exit()
	session.stdin.write('CREATE USER C##DBVOWNER IDENTIFIED BY Manager_1;');
	print session.communicate()
	session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	session.stdin.write('CREATE USER C##DBVMANAGER IDENTIFIED BY Manager_1;');
	print session.communicate()
	session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	session.stdin.write('GRANT CREATE SESSION TO C##DBVOWNER;');
	print session.communicate()
	session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	session.stdin.write('GRANT CREATE SESSION TO C##DBVMANAGER;');
	print session.communicate()


	conn = 'sys/'+admin_pass+'@'+cdb+' as sysdba'
	try:	
		session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	except OSError as e:
		print("Error At line {} : {}".format(str(get_linenumber()),err))
		exit() 	
	session.stdin.write("BEGIN\nDVSYS.CONFIGURE_DV (\ndvowner_uname         => 'C##DBVOWNER',\ndvacctmgr_uname       => 'C##DBVMANAGER');\nEND;\n/")	;
	print session.communicate()

#	conn = 'sys/'+admin_pass+'@'+cdb+' as sysdba'
	session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	session.stdin.write("@?/rdbms/admin/utlrp.sql")	;
	res = session.communicate()
	print res[0]
	print "Done Step  1: " + res[1]
	
	
	conn = 'C##DBVOWNER/Manager_1@'+cdb;
	try:
		session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	except OSError as e:
		print("Error At line {} : {}".format(str(get_linenumber()),err))
		exit()	
	session.stdin.write("EXEC DBMS_MACADM.ENABLE_DV;")	;
	res = session.communicate()
	print res[0]
	print "Done Step  2: " + res[1]

	conn = 'sys/'+admin_pass+'@'+cdb+' as sysdba'
	try:
		session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	except OSError as e:
		print("Error At line {} : {}".format(str(get_linenumber()),err))
		exit()	
	session.stdin.write('SHUTDOWN IMMEDIATE;');
	res = session.communicate()
	print res[0]
	print "Done Step  3: " + res[1]


	os.putenv('ORACLE_SID',cdb)
	os.chdir(oracle_home+'/bin')
	
	try:
		session = subprocess.Popen([oracle_home+'/bin/sqlplus', '/ as sysdba'], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	except OSError as e:
		print("Error At line {} : {}".format(str(get_linenumber()),err))
		exit()	
	session.stdin.write('startup;');
	res = session.communicate()
	print res[0]
	print "Done Step  4: " + res[1]

	conn = 'sys/'+admin_pass+'@'+cdb+' as sysdba'
	try:	
		session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	except OSError as e:
		print("Error At line {} : {}".format(str(get_linenumber()),err))
		exit()	
	session.stdin.write('ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY admin123;');
	res = session.communicate()
	print res[0]
	print "Done Step  5: " + res[1]
	
	conn = 'sys/'+admin_pass+'@'+pgdb+' as sysdba'
	try:	
		session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	except OSError as e:
		print("Error At line {} : {}".format(str(get_linenumber()),err))
		exit()	
	session.stdin.write('ALTER DATABASE OPEN;');
	res = session.communicate()
	print res[0]
	print "Done Step  5: " + res[1]
	
	try:	
		session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	except OSError as e:
		print("Error At line {} : {}".format(str(get_linenumber()),err))
		exit()	
	session.stdin.write('ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY admin123;');
	res = session.communicate()
	print res[0]
	print "Done Step  5: " + res[1]
	
	#ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY admin123;

	session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	session.stdin.write('GRANT CREATE SESSION, SET CONTAINER TO C##DBVOWNER CONTAINER = CURRENT;');
	res = session.communicate()
	print res[0]
	print "Done Step  6: " + res[1]

	session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	session.stdin.write('GRANT CREATE SESSION, SET CONTAINER TO C##DBVMANAGER CONTAINER = CURRENT;');
	res = session.communicate()
	print res[0]
	print "Done Step  7: " + res[1]
	
	conn = 'sys/'+admin_pass+'@'+pgdb+' as sysdba'
	
	try:	
		session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	except OSError as e:
		print("Error At line {} : {}".format(str(get_linenumber()),err))
		exit()	
	session.stdin.write('ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY admin123;');
	res = session.communicate()
	print res[0]
	print "Done Step 8: " + res[1]
	
	
	try:	
		session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	except OSError as e:
		print("Error At line {} : {}".format(str(get_linenumber()),err))
		exit()	
	session.stdin.write("BEGIN\nDVSYS.CONFIGURE_DV (\ndvowner_uname         => 'C##DBVOWNER',\ndvacctmgr_uname       => 'C##DBVMANAGER');\nEND;\n/")	;
	res = session.communicate()
	print res[0]
	print "Done Step  9: " + res[1]

	conn = 'C##DBVOWNER/Manager_1@'+pgdb;
	try:	
		session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	except OSError as e:
		print("Error At line {} : {}".format(str(get_linenumber()),err))
		exit()	
	session.stdin.write("EXEC DBMS_MACADM.ENABLE_DV;")	;
	res = session.communicate()
	print res[0]
	print "Done Step  10: " + res[1]
	
	conn = 'sys/'+admin_pass+'@'+cdb+' as sysdba'
	try:	
		session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)	
	except OSError as e:
		print("Error At line {} : {}".format(str(get_linenumber()),err))
		exit()
	session.stdin.write("ALTER PLUGGABLE DATABASE "+pgdb+" CLOSE IMMEDIATE;")	;
	res = session.communicate()
	print res[0]
	print "Done Step  11: " + res[1]

#	conn = 'sys/'+admin_pass+'@'+cdb+' as sysdba'
	session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	session.stdin.write("ALTER PLUGGABLE DATABASE "+pgdb+" OPEN;")	;
	res = session.communicate()
	print res[0]
	print "Done Step  12: " + res[1]
	
	try:	
		session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	except OSError as e:
		print("Error At line {} : {}".format(str(get_linenumber()),err))
		exit()	
	session.stdin.write('ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY admin123;');
	res = session.communicate()
	print res[0]
	print "Done Step  13: " + res[1]
	
	conn = 'sys/'+admin_pass+'@'+pgdb+' as sysdba'
	try:	
		session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	except OSError as e:
		print("Error At line {} : {}".format(str(get_linenumber()),err))
		exit()	
	session.stdin.write('ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY admin123;');
	res = session.communicate()
	print res[0]
	print "Done Step  14: " + res[1]
		
	conn = 'C##DBVOWNER/Manager_1@'+pgdb;
	try:
		session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	except OSError as e:
		print("Error At line {} : {}".format(str(get_linenumber()),err))
		exit()	
	session.stdin.write('@'+cwd+'/scripts_new/grants.sql')
	res = session.communicate()
	print res[0]
	print "Done Step  15: " + res[1]

#	conn = 'C##DBVOWNER/Manager_1@'+pgdb;
	try:	
		session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	except OSError as e:
		print("Error At line {} : {}".format(str(get_linenumber()),err))
		exit()	
	session.stdin.write("SELECT VALUE FROM V$OPTION WHERE PARAMETER = 'Oracle Database Vault';")
	res = session.communicate()
	print res[0]
	print "Done Step  16: " + res[1]

	session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	session.stdin.write("SELECT VALUE FROM V$OPTION WHERE PARAMETER = 'Oracle Label Security';")
	res = session.communicate()
	print res[0]
	print "Done Step  17: " + res[1]

	session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	session.stdin.write("select * from DVSYS.DBA_DV_REALM where name='P6AppsVault';")
	res = session.communicate()
	print res[0]
	print "Done Step  18: " + res[1]

	conn = 'sys/'+admin_pass+'@'+cdb+' as sysdba'
	session = subprocess.Popen([oracle_home+'/bin/sqlplus', '-S', conn], stdin=PIPE, stdout=PIPE, stderr=PIPE)
	session.stdin.write("SELECT * FROM DVSYS.DBA_DV_STATUS;")
	res = session.communicate()
	print res[0]
	print "Done Step  19: " + res[1]
	
	print ('Hurrah !!! DB Vault configured for ')
	print ('--------------------------------------')
	print (' DB VAULT Configured Successfully    |')
	print ('| host: '+host+'    |')
	print ('| port : '+port+'           |')
	print ('--------------------------------------')

	
	




