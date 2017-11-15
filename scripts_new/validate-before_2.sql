set serveroutput off;
set echo off;
set timing off;
set serveroutput on format wrapped;
select distinct tablespace_name from user_lobs where tablespace_name not like '%ENC' UNION select distinct tablespace_name from user_tables where temporary = 'N' and tablespace_name not like '%ENC' UNION select distinct tablespace_name from user_indexes where generated = 'N' and temporary = 'N' and index_type != 'DOMAIN' and tablespace_name not like '%ENC';
set pagesize 0;
set timing on;
set trimspool on;
set linesize 2500;
set feedback off;
set verify off;

--ACCEPT input_tbs CHAR prompt 'Name of existing clear-text tablespace: '
define input_tbs = 'PMDB_LOB1'

spool &input_tbs..validate-before.log replace

declare
	tbs_ddl		clob default empty_clob();
	pjddl		clob default empty_clob();
	table_ddl	clob default empty_clob();
 	index_ddl	clob default empty_clob();
	mview_ddl	clob default empty_clob();
	print_ddl	clob default empty_clob();
	tbs_is_enc	number default -1;
	start_pj	number default -1; -- # of single quotes in PRINTJOINS
	stop_pj		number default -1; -- # of single quotes in PRINTJOINS
	wallet_status	varchar2(18 char) default 'CLOSED';
	can_redef	varchar2(3 char) default 'NO';
	tbs_name	varchar2(30 char) := '&input_tbs';
	mtname		varchar2(30 char) default 'P6';
	mcname 		varchar2(30 char) default 'P6';
	mdname		MDSYS.SDO_DIM_ARRAY;
	msname		number default -1;
  	ctx_name	varchar2(30 char) default 'IntCTXName';
	cname		varchar2(30 char) default 'P6';
  	intiname	varchar2(30 char) default 'P6';
	start_del	number default -1;
	end_del		number default -1;
	diff		number default -1;
@@preferences.txt
	TYPE P6user_type IS TABLE OF VARCHAR2(30 char); -- for App-user's default tablespaces
	P6user		P6user_type := P6user_type();
	TYPE tname_type IS TABLE OF VARCHAR2(30 char); -- for tables
	tname		tname_type := tname_type();
  	tbname		tname_type := tname_type();
	TYPE cname_type IS TABLE OF VARCHAR2(30 char); -- for CHECK constrains
	checkname	cname_type := cname_type();
  	TYPE iname_type IS TABLE OF VARCHAR2(30 char); -- for indexes
  	iname		iname_type := iname_type();
  	itbsname	iname_type := iname_type();
	num_err		pls_integer;
begin

-- check if encrypted tablespace already exists:
select count(*) into tbs_is_enc from user_tablespaces where tablespace_name like tbs_name||'%' and encrypted = 'YES';
if tbs_is_enc > 0 then
	dbms_output.put_line('Tablespace '''||tbs_name||''' is already encrypted!');
else		-- tbs_is_enc = 0
 	select dbms_metadata.get_ddl('TABLESPACE', tbs_name) into tbs_ddl from dual;

-- Take care of size changes through Alter Database statement
if dbms_lob.instr (tbs_ddl, 'ALTER DATABASE') > 0 then -- if keyword ALTER DATABASE found
	select dbms_lob.instr(tbs_ddl, 'ALTER DATABASE') into start_del from dual;
	select dbms_lob.getlength(tbs_ddl) into end_del from dual;
	select end_del - start_del + 1 into diff from dual;
	dbms_lob.erase(tbs_ddl, diff, start_del);
end if;

-- Done with tablespace DDL:
   dbms_output.put_line(tbs_ddl||';');
end if; -- if tbs_is_enc = 0

dbms_output.put_line(' ');

select username bulk collect into P6user from dba_users where default_tablespace = tbs_name;
for u in 1 .. P6user.count loop
dbms_output.put_line (P6user(u)||': Default TBS: '||tbs_name);
end loop;

-- Tables in migrated tablespace:
select table_name bulk collect into tname from user_tables where TABLESPACE_NAME = tbs_name 
and temporary = 'N' 
and table_name not like 'INT_TBL%' -- interim tables in clear-text TBS are already migrated
and table_name not like 'MDRT_%'   -- automatically generated for spatial indexes
and table_name not like 'DR$%$_'   -- automatically generated for text indexes
and table_name not in (select queue_table from all_queue_tables) 
and table_name not in (select table_name from all_tables where iot_type = 'IOT_OVERFLOW') 
and table_name not in (select container_name from all_mviews) 
and table_name not in (select log_table from all_mview_logs) order by 1;

	for i in 1 .. tname.count loop
  	select dbms_metadata.get_ddl('TABLE', tname(i), owner) into table_ddl from dual;

	dbms_output.put_line(table_ddl||';');
	dbms_output.put_line(' ');

-- Indexes in current table:
  	select index_name, tablespace_name bulk collect into iname, itbsname from user_indexes where TABLE_NAME = tname(i) and generated = 'N' and index_name not in (select index_name from user_constraints where constraint_type = 'P') order by 1;

-- Start Index Loop:
	for j in 1 .. iname.count loop  -- Index Loop
	dbms_output.put_line('-- Processing index '||iname(j)||' ('||j||' of '||iname.count||'):');
	select dbms_metadata.get_ddl('INDEX', iname(j), owner) into index_ddl from dual;
	if dbms_lob.instr(index_ddl, 'INDEXTYPE IS "CTXSYS"') > 0 then
		ctx_name := owner||'.'||iname(j);
		dbms_output.put_line('-- Table with Text index '||owner||'.'||iname(j)||':');
		dbms_output.put_line(CHR(13));
	 	select ctx_report.create_index_script(ctx_name) into index_ddl from dual;
	elsif dbms_lob.instr(index_ddl, 'INDEXTYPE IS "MDSYS"') > 0 then
		dbms_output.put_line(CHR(13));
		dbms_output.put_line('-- Table with Spatial index '||iname(j)||':');
	end if;

	if dbms_lob.getlength(index_ddl) <= 32767 then
		dbms_output.put_line(index_ddl||';');
	else
		dbms_output.put_line('Index DDL is '||dbms_lob.getlength(index_ddl)||' characters long,');
		dbms_output.put_line('only the first 32700 characters will be printed:');
		dbms_lob.copy(print_ddl, index_ddl, 32700, 1, 1);
		dbms_output.put_line(print_ddl||' ... TRUNCATED');
		dbms_output.put_line(CHR(13));
		dbms_lob.trim(print_ddl, 0);
	end if;

   dbms_lob.trim(index_ddl, 0);
   dbms_output.put_line(CHR(13));

   end loop; -- END index loop
   end loop; -- END table loop

end;
/
spool off;
exit;
