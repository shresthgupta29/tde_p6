# tde_p6
Script for tde encryption of p6 


Prerequisites :  DB client setup , P6 db setup , tde_script folder
1. Copy the folde 'tde_script.zip' to machine

2. Extract the zip file

3. cd tde_script

4. Edit config.py file for different values and path to clientDB(12c) and p6db

5 .Check whether 'script_new' folder is present

6. run script tde_1.py as pgbuora
- python tde_1.py
7. run script tde_2.py as "root user":
- sudo python tde_2.py
8. run script tde_3.py as pgbuora
- python tde_3.py
9. Check console for error
Note : if db client in already installed, then continue from step 8 after editing the config.py file
