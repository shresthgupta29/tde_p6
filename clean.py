import os
import subprocess
from subprocess import Popen, PIPE
from config import *
##cd /u01/app/pgbuora/product/12.2.0/dbhome_1/bin
os.chdir(oracle_home+'/bin')
##./dbca -silent -deleteDatabase -sourceDB orcl -sid orcl -sysDBAPassword Manager1 -sysDBAUserName sys
try:
	subprocess.call('./dbca -silent -deleteDatabase -sourceDB '+cdb+' -sid '+cdb+' -sysDBAPassword '+admin_pass+' -sysDBAUserName sys',shell=True)
except OSError as e:
	print e
	exit()
##cd /u01/app/pgbuora/oradata
os.chdir(oracle_base+'/oradata')
##rm -rf orcl
subprocess.call('rm -rf '+cdb,shell=True)
##cd /wallet/location
os.chdir(wallet_location)
##rm -rf *
subprocess.call('rm -rf *',shell=True)


