import os
import subprocess
from subprocess import Popen, PIPE
from config import *
os.putenv('ORACLE_HOME',oracle_home)
os.putenv('JAVA_HOME',java_home)
os.chdir(client_path)
#cwd = os.getcwd()
#print cwd

'''
As a root user, execute the following script(s):
        1. /u01/app/oraInventory/orainstRoot.sh
        2. /u01/app/pgbuora/product/12.2.0/dbhome_1/root.sh
'''
subprocess.call('/u01/app/oraInventory/orainstRoot.sh',shell=True)
subprocess.call(oracle_home+'/root.sh', shell=True)
