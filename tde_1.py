import os
import subprocess
from subprocess import Popen, PIPE
from config import *
os.putenv('ORACLE_HOME',oracle_home)
os.putenv('JAVA_HOME',java_home)
try:
	os.chdir(client_path)
except OSError as err:
	print(err)
	exit()

cwd = os.getcwd()
print "At "+cwd

try:
	subprocess.call('./runInstaller -ignoreSysPrereqs -ignorePrereq -waitforcompletion -showProgress -silent -responseFile '+client_path+'/response/db_install.rsp oracle.install.option=INSTALL_DB_SWONLY UNIX_GROUP_NAME=oinstall INVENTORY_LOCATION=/u01/app/oraInventory SELECTED_LANGUAGES=en ORACLE_HOME='+oracle_home+' ORACLE_BASE='+oracle_base+' oracle.install.db.InstallEdition=EE oracle.install.db.isCustomInstall=false oracle.install.db.OSDBA_GROUP=dba oracle.install.db.OSBACKUPDBA_GROUP=dba oracle.install.db.OSDGDBA_GROUP=dba oracle.install.db.OSKMDBA_GROUP=dba oracle.install.db.OSRACDBA_GROUP=dba SECURITY_UPDATES_VIA_MYORACLESUPPORT=false DECLINE_SECURITY_UPDATES=true', shell=True)
except OSError as err:
	print(err)
	exit()		
print "Run script tde_2.py with root privilages"
