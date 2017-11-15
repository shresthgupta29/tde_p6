set serveroutput off;
set echo off;
set timing off;
-- alter session force parallel dml;
-- alter session force parallel query;
set serveroutput on format word_wrapped;
select distinct tablespace_name from user_lobs where tablespace_name not like '%_ENC' UNION select distinct tablespace_name from user_tables where temporary = 'N' and tablespace_name not like '%_ENC' and table_name not in (select container_name from user_mviews) UNION select distinct tablespace_name from user_indexes where generated = 'N' and temporary = 'N' and index_type != 'DOMAIN' and tablespace_name not like '%_ENC' order by 1;
set pagesize 0;
set timing on;
set trimspool on;
set linesize 2500;
set feedback off;
set verify off;

--ACCEPT input_tbs CHAR prompt 'Name of existing clear-text tablespace: '
define input_tbs = 'PMDB_DAT1' 
spool &input_tbs..migrate.log replace

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
	pkcname		varchar2(30 char) default 'PrimKeyName'; -- for Primary key
	pkciname	varchar2(30 char) default 'PrimKeyIndName'; -- and it's index
	pkcgen		varchar2(30 char) default 'PrimKeyGen'; -- USER or GENERATED?
  	ctx_name	varchar2(30 char) default 'IntCTXName';
	printstring	varchar2(4000 char) default 'PrintString';
	col_count	number default -1; -- # of unused columns
	cname		varchar2(30 char) default 'P6';
  	intiname	varchar2(25 char) default 'P6';
	start_del	number default -1;
	end_del		number default -1;
	diff		number default -1;
	diff_pj		number default -1;
	n		number default -1;
@@preferences.txt
	TYPE app_user_names_type IS TABLE OF VARCHAR2(40 char); -- for App-user's def tablespace
	app_user_names	app_user_names_type := app_user_names_type();
	TYPE tname_type IS TABLE OF VARCHAR2(40 char); -- for tables
	rtname		tname_type := tname_type(); -- Name of temp. ref. constraint (leftover from OTR)
	tname		tname_type := tname_type(); -- List of tables in current tablespace
  	tbname		tname_type := tname_type(); -- List of all tablespaces that contain objects owned by <owner>
  	tbname_spec	tname_type := tname_type(); -- List of tablespaces that contain objects of processed TBS
	mvcontname	tname_type := tname_type(); -- MView container names
	inttname	tname_type := tname_type(); -- Interim tables in clear text tablespace (complete)
	in_proc		tname_type := tname_type(); -- Interim tables in encrypted tablespace (incomplete)
	TYPE cname_type IS TABLE OF VARCHAR2(40 char); 
	checkname	cname_type := cname_type(); -- for CHECK constrains
	ckcheckname	cname_type := cname_type(); -- for other CHECK constraints
	uqconsname	cname_type := cname_type(); -- for UNIQUE constrains
	nnconsname	cname_type := cname_type(); -- for NOT NULL constrains
	consiname	cname_type := cname_type(); -- and their indexes
	lobsegname	cname_type := cname_type(); -- for LOB Segment names
  	TYPE iname_type IS TABLE OF VARCHAR2(40 char);
  	iname		iname_type := iname_type(); -- for indexes
  	itbsname	iname_type := iname_type(); -- and their tablepaces
	num_err		pls_integer;
begin
select 1 into print_ddl from dual;
select '''' into pjddl from dual;

-- check if TDE master key is available to the database:
select STATUS into wallet_status from v$encryption_wallet;
if wallet_status <> 'OPEN' then
  	dbms_output.put_line(' ');
  	dbms_output.put_line('****************** ERROR ****** EXITING ******************');
  	dbms_output.put_line('******* TDE master encryption key is not available *******');
  	dbms_output.put_line('****************** ERROR ****** EXITING ******************');
  	dbms_output.put_line(' '); return;
end if;

-- check if encrypted tablespace already exists:
select count(*) into tbs_is_enc from user_tablespaces where tablespace_name in (tbs_name, tbs_name||'_ENC') and encrypted = 'YES';
if tbs_is_enc > 0 then
	dbms_output.put_line('-- Tablespace '''||tbs_name||''' is already encrypted!');
	dbms_output.put_line(CHR(10));
else		-- tbs_is_enc = 0
 	select dbms_metadata.get_ddl('TABLESPACE', tbs_name) into tbs_ddl from dual;
  	select replace (tbs_ddl, tbs_name, tbs_name||'_ENC') into tbs_ddl from dual;
  	select replace (tbs_ddl, source_dir, target_dir) into tbs_ddl from dual;
  	select replace (tbs_ddl, '.dbf', '_enc.dbf') into tbs_ddl from dual;
  	select replace (tbs_ddl, 'EXTENT MANAGEMENT LOCAL', 'ENCRYPTION using '''||alg||''' EXTENT MANAGEMENT LOCAL') into tbs_ddl from dual;

	if dbms_lob.instr (tbs_ddl, 'STORAGE(') > 0 then -- if keyword STORAGE found then ADD keyword ENCRYPT
		select replace (tbs_ddl, 'STORAGE(', 'STORAGE(ENCRYPT ') into tbs_ddl from dual;
	else 	-- if keyword STORAGE is NOT found, INSERT keywords STORAGE(encrypt):
		select replace (tbs_ddl, 'NOCOMPRESS ', ' NOCOMPRESS STORAGE(encrypt)') into tbs_ddl from dual;
	end if;

select distinct tablespace_name||'_ENC' bulk collect into tbname_spec from user_indexes where table_name in (select table_name from user_tables where temporary = 'N' and tablespace_name  = tbs_name and table_name not like 'DR$%' and table_name not like '%MDRT%') and generated = 'N' and temporary = 'N' and tablespace_name||'_ENC' not in (select tablespace_name from user_tablespaces where encrypted = 'YES') and tablespace_name != tbs_name order by 1;
if tbname_spec.count > 0 then
for p in 1 .. tbname_spec.count loop
	dbms_output.put_line('Required tablespace '||tbname_spec(p)||' does not exist');
end loop; -- return;
end if;

-- Take care of size changes through ALTER DATABASE statement
if dbms_lob.instr (tbs_ddl, 'ALTER DATABASE') > 0 then -- if keyword ALTER DATABASE found
	if dbms_lob.instr (tbs_ddl, 'RESIZE') > 0 then -- AND if keyword RESIZE found
	select dbms_lob.instr(tbs_ddl, 'ALTER DATABASE') into start_del from dual;
	select dbms_lob.getlength(tbs_ddl) into end_del from dual;
	select end_del - start_del + 1 into diff from dual;
	dbms_lob.erase(tbs_ddl, diff, start_del); -- do not RESIZE the tablespaces as they are allowed to grow as needed
	end if;
end if;

-- Done with tablespace DDL:
   dbms_output.put_line(tbs_ddl||';');
execute immediate (tbs_ddl);
   dbms_output.put_line(' ');
end if; -- if tbs_is_enc = 0

select username bulk collect into app_user_names from dba_users where default_tablespace = tbs_name;
for u in 1 .. app_user_names.count loop
	printstring := 'alter user '||app_user_names(u)||' default tablespace '||tbs_name||'_ENC';
	dbms_output.put_line(printstring||';');
execute immediate (printstring);
	dbms_output.put_line(' ');
end loop;

-- Tables in migrated tablespace:
select table_name bulk collect into tname from (select table_name from user_tables where tablespace_name = tbs_name and table_name not like 'MDRT%' and table_name not like 'DR$%' and table_name not like 'INT_TBL_%' and temporary = 'N' and partitioned = 'NO' and table_name not in (select container_name from user_mviews) UNION select table_name from user_part_tables where def_tablespace_name = tbs_name and table_name not like 'INT_TBL_%') order by 1;

if tname.count > 0 then
	select distinct tablespace_name bulk collect into tbname from user_lobs where tablespace_name not like '%_ENC' UNION select distinct tablespace_name from user_tables where temporary = 'N' and partitioned = 'NO' and tablespace_name not like '%_ENC' and table_name not in (select container_name from user_mviews) UNION select distinct tablespace_name from user_indexes where generated = 'N' and temporary = 'N' and index_type != 'DOMAIN' and tablespace_name not like '%_ENC';

select table_name bulk collect into inttname from (select table_name from user_tables where temporary = 'N' and partitioned = 'NO' and tablespace_name = tbs_name||'_ENC' and table_name not like 'INT_TBL_%' and table_name not like 'MDRT%' and table_name not in (select container_name from user_mviews) UNION select table_name from user_part_tables where def_tablespace_name = tbs_name||'_ENC' and table_name not like 'INT_TBL_%') order by 1;
	for x in 1 .. inttname.count loop
	dbms_output.put_line('-- Table '||x||' ('||inttname(x)||'): Online migration completed');
	end loop;

select table_name bulk collect into in_proc from (select table_name from user_tables where temporary = 'N' and partitioned = 'NO' and tablespace_name = tbs_name||'_ENC' and table_name not like 'MDRT%' and table_name not in (select container_name from user_mviews) and table_name like 'INT_TBL_%' UNION select table_name from user_part_tables where def_tablespace_name = tbs_name||'_ENC' and table_name like 'INT_TBL_%') order by 1;
if in_proc.count > 0 then
	for p in 1 .. in_proc.count loop
	dbms_output.put_line('-- Table '||in_proc(p)||': Redefinition incomplete! Exiting ...');
	end loop; return;
end if;

dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'REF_CONSTRAINTS', FALSE);

for i in 1 .. tname.count loop
	n := inttname.count + i;
	dbms_output.put_line(CHR(10));
	dbms_output.put_line('-- Processing table '||tname(i)||' ('||n||' of '||(inttname.count + tname.count)||'):');
	  begin
	    dbms_redefinition.can_redef_table(owner, tname(i), dbms_redefinition.cons_use_pk);
	    can_redef := 'PK';
	  exception
	    when others then
		begin
		  dbms_redefinition.can_redef_table(owner, tname(i), dbms_redefinition.cons_use_rowid);
		  can_redef := 'ROW';
	        exception
		  when others then
		  continue;
	        end;
          end;

  	select dbms_metadata.get_ddl('TABLE', tname(i), owner) into table_ddl from dual;

	for k in 1 .. tbname.count loop -- Tablespace loop
  	select replace (table_ddl, 'TABLESPACE "'||tbname(k)||'"', 'TABLESPACE "'||tbname(k)||'_ENC"') into table_ddl from dual;
	end loop;

  	select replace (table_ddl, 'TABLE "'||owner||'"."'||tname(i)||'"', 'TABLE "'||owner||'"."INT_TBL_'||tbs_name||'_'||n||'"') into table_ddl from dual;
  	select replace (table_ddl, ''||CHR(9)||'', '') into table_ddl from dual;
  	select replace (table_ddl, ', '||CHR(10)||'', ' '||CHR(10)||', ') into table_ddl from dual;

	if dbms_lob.instr(table_ddl, 'PRIMARY KEY') > 0 then
		select constraint_name, index_name, generated into pkcname, pkciname, pkcgen from user_constraints where TABLE_NAME = tname(i) and CONSTRAINT_TYPE = 'P';
		if pkcgen = 'USER NAME' then
		dbms_output.put_line('-- Primary constraint name: '||pkcname);
		dbms_output.put_line('-- Index name:              '||pkciname);
		select replace (table_ddl, 'CONSTRAINT "'||pkcname||'" PRIMARY KEY', 'CONSTRAINT "INT_PKC_'||tbs_name||'_'||n||'" PRIMARY KEY') into table_ddl from dual;
		end if;
		select replace (table_ddl, '", "', '",'||CHR(10)||' "') into table_ddl from dual;		
	end if;

	if dbms_lob.instr(table_ddl, 'UNIQUE') > 0 then
		select constraint_name, index_name bulk collect into uqconsname, consiname from user_constraints where TABLE_NAME = tname(i) and CONSTRAINT_TYPE = 'U' and GENERATED = 'USER NAME';
		for c in 1 .. uqconsname.count loop
		dbms_output.put_line('-- Unique constraint name:  '||uqconsname(c));
		dbms_output.put_line('-- Index name:              '||consiname(c));
		select replace (table_ddl, 'CONSTRAINT "'||uqconsname(c)||'"', 'CONSTRAINT "INT_UC_'||tbs_name||'_'||n||'_'||c||'"') into table_ddl from dual;
		select replace (table_ddl, '", "', '",'||CHR(10)||' "') into table_ddl from dual;
		end loop;
	end if;

	if dbms_lob.instr(table_ddl, 'CONSTRAINT "') > 0 then
	  	if dbms_lob.instr(table_ddl, '" CHECK (') > 0 then
  		select constraint_name bulk collect into ckcheckname from user_constraints where TABLE_NAME = tname(i) and CONSTRAINT_TYPE = 'C' and GENERATED = 'USER NAME';
  		for d in 1 .. ckcheckname.count loop
  		select replace (table_ddl, ',  CONSTRAINT "'||ckcheckname(d)||'" CHECK', '-- , CHECK') into table_ddl from dual;
		end loop;
		end if;
	end if;

	if dbms_lob.instr(table_ddl, 'STORE AS BASICFILE "') > 0 then
		select segment_name bulk collect into lobsegname from user_lobs where TABLE_NAME = tname(i);
		for l in 1 .. lobsegname.count loop
		select replace (table_ddl, 'STORE AS BASICFILE "'||lobsegname(l)||'"', 'STORE AS BASICFILE ') into table_ddl from dual;
		end loop;
	end if;

	if dbms_lob.instr(table_ddl, 'CONSTRAINT "') > 0 then
		if dbms_lob.instr(table_ddl, '" NOT NULL') > 0 then
		select constraint_name bulk collect into nnconsname from user_constraints where TABLE_NAME = tname(i) and CONSTRAINT_TYPE = 'C' and GENERATED = 'USER NAME';
		for m in 1 .. nnconsname.count loop
		select replace (table_ddl, 'CONSTRAINT "'||nnconsname(m)||'" NOT NULL', 'NOT NULL') into table_ddl from dual;
		end loop;
		end if;
	end if;

	if dbms_lob.getlength(table_ddl) <= 32767 then
	  	dbms_output.put_line(table_ddl||';');
	else
		dbms_output.put_line('Table DDL is '||dbms_lob.getlength(table_ddl)||' characters long:');
		dbms_output.put_line('Only the first 32,700 characters will be printed:');
		dbms_lob.copy(print_ddl, table_ddl, 32700, 1, 1);
		dbms_output.put_line(print_ddl||' ... TRUNCATED');
	end if;
	dbms_output.put_line(CHR(10));

execute immediate (table_ddl);

  	if can_redef = 'PK' then
		dbms_redefinition.start_redef_table(owner, tname(i), 'INT_TBL_'||tbs_name||'_'||n, NULL, dbms_redefinition.cons_use_pk);
		dbms_output.put_line('-- Started redefinition of '''||tname(i)||''' to'); 
		dbms_output.put_line('--''INT_TBL_'||tbs_name||'_'||n||''' using PK.');
	else
		dbms_redefinition.start_redef_table(owner, tname(i), 'INT_TBL_'||tbs_name||'_'||n, NULL, dbms_redefinition.cons_use_rowid);
		dbms_output.put_line('-- Started redefinition of '''||tname(i)||''' to'); 
		dbms_output.put_line('--''INT_TBL_'||tbs_name||'_'||n||''' using rowID.');
  	end if;	

	if dbms_lob.instr(table_ddl, 'PRIMARY KEY') > 0 then
		if pkcgen = 'USER NAME' then
		dbms_output.put_line(CHR(10));
		dbms_redefinition.register_dependent_object(owner, tname(i), 'INT_TBL_'||tbs_name||'_'||n, dbms_redefinition.cons_constraint, owner, pkcname, 'INT_PKC_'||tbs_name||'_'||n);
 		dbms_output.put_line('-- Registered interim PRIMARY KEY Constraint ''INT_PKC_'||tbs_name||'_'||n||'''');
  		dbms_output.put_line('-- with interim table ''INT_TBL_'||tbs_name||'_'||n||'''.');
		dbms_output.put_line(CHR(10));
		dbms_redefinition.register_dependent_object(owner, tname(i), 'INT_TBL_'||tbs_name||'_'||n, dbms_redefinition.cons_index, owner, pkciname, 'INT_PKC_'||tbs_name||'_'||n);
 		dbms_output.put_line('-- Registered interim PRIMARY KEY Index ''INT_PKC_'||tbs_name||'_'||n||'''');
  		dbms_output.put_line('-- with interim table ''INT_TBL_'||tbs_name||'_'||n||'''.');
		end if;
	end if;

	if dbms_lob.instr(table_ddl, 'UNIQUE') > 0 then
		for c in 1 .. uqconsname.count loop
		dbms_output.put_line(CHR(10));
		dbms_redefinition.register_dependent_object(owner, tname(i), 'INT_TBL_'||tbs_name||'_'||n, dbms_redefinition.cons_constraint, owner, uqconsname(c), 'INT_UC_'||tbs_name||'_'||n||'_'||c);
 		dbms_output.put_line('-- Registered interim UNIQUE Constraint ''INT_UC_'||tbs_name||'_'||n||'_'||c||'''');
  		dbms_output.put_line('-- with interim table ''INT_TBL_'||tbs_name||'_'||n||'''.');
		dbms_output.put_line(CHR(10));
		dbms_redefinition.register_dependent_object(owner, tname(i), 'INT_TBL_'||tbs_name||'_'||n, dbms_redefinition.cons_index, owner, consiname(c), 'INT_UC_'||tbs_name||'_'||n||'_'||c);
 		dbms_output.put_line('-- Registered interim UNIQUE Index ''INT_UC_'||tbs_name||'_'||n||'_'||c||'''');
  		dbms_output.put_line('-- with interim table ''INT_TBL_'||tbs_name||'_'||n||'''.');
		end loop;
	end if;

-- Indexes in current table:
  	select index_name, tablespace_name bulk collect into iname, itbsname from (select index_name, tablespace_name from user_indexes where TABLE_NAME = tname(i) and temporary = 'N' and generated = 'N' and partitioned = 'NO' and index_name not in (select index_name from user_constraints where TABLE_NAME = tname(i) and constraint_type in ('P', 'U')) UNION select index_name, def_tablespace_name from user_part_indexes where TABLE_NAME = tname(i));

-- Start Index Loop:
	for j in 1 .. iname.count loop  -- Index Loop
  	select 'IX_'||tbs_name||'_'||n||'_'||j into intiname from dual;
	  
	dbms_output.put_line(' ');
	dbms_output.put_line('-- Processing index # '||j||' of '||iname.count||' index(es) for table # '||n||':');
	select dbms_metadata.get_ddl('INDEX', iname(j), owner) into index_ddl from dual;

  	if dbms_lob.instr(index_ddl, 'INDEXTYPE IS "CTXSYS"') > 0 then
		dbms_lob.trim(index_ddl, 0);
	  	select ctx_report.create_index_script(iname(j)) into index_ddl from dual;
	  	select replace (index_ddl, 'create index "'||owner||'"."'||iname(j)||'"', 'create index "'||intiname||'"') into index_ddl from dual;
	  	select replace (index_ddl, 'on "'||owner||'"."'||tname(i)||'"', 'on "'||owner||'"."INT_TBL_'||tbs_name||'_'||n||'"') into index_ddl from dual;
	  	for k in 1 .. tbname.count loop -- Tablespace loop
	  	  	select replace (index_ddl, 'tablespace '||tbname(k), 'tablespace '||tbname(k)||'_ENC') into index_ddl from dual;
	  	end loop;
		select replace(index_ddl, 'begin'||CHR(10), '') into index_ddl from dual;
		select replace(index_ddl, 'end;'||CHR(10), '') into index_ddl from dual;
		select replace(index_ddl, CHR(10)||'/'||CHR(10), '') into index_ddl from dual;
		select replace(index_ddl, '  ctx_ddl.', 'ctx_ddl.') into index_ddl from dual;
		select replace(index_ddl, '  ctx_output.', 'ctx_output.') into index_ddl from dual;

		while dbms_lob.instr(index_ddl, 'ctx_ddl.', 1, 1) > 0 loop
		select dbms_lob.instr(index_ddl, 'ctx_ddl.', 1, 1) into start_del from dual;
		select dbms_lob.instr(index_ddl, ');', 1, 1) + 2  into end_del from dual;
		diff := end_del - start_del;
		dbms_lob.copy(print_ddl, index_ddl, diff, 1, start_del);
		select replace(print_ddl, 'ctx_ddl.', 'begin'||CHR(10)||'ctx_ddl.') into print_ddl from dual;
-- WORKAROUND BUG 17622964 -->
		if dbms_lob.instr(print_ddl, 'PRINTJOINS', 1, 1) > 0 then
		if dbms_lob.instr(print_ddl, '''', 1, 8) > 0 then
		NULL;
		elsif dbms_lob.instr(print_ddl, '''', 1, 7) > 0 then
		select dbms_lob.instr(print_ddl, '''', 1, 6) into start_pj from dual;
		select dbms_lob.getlength(print_ddl) into stop_pj from dual;
		diff_pj := stop_pj - start_pj;
		dbms_lob.copy(pjddl, print_ddl, diff_pj + 1, 2, start_pj);
		dbms_lob.trim(print_ddl, start_pj - 1);
		dbms_lob.append(print_ddl, pjddl);
		dbms_lob.trim(pjddl, 1);
		end if;
  		end if;
-- <-- WORKAROUND BUG 17622964

		select replace(print_ddl, ');', ');'||CHR(10)||'end;'||CHR(10)) into print_ddl from dual;
		select dbms_lob.substr(print_ddl, diff + 13, 1) into printstring from dual;
		dbms_lob.trim(print_ddl, 0);
		dbms_output.put_line(printstring);
		execute immediate (printstring);
		dbms_lob.erase(index_ddl, end_del, 1);
		end loop;

		select dbms_lob.instr(index_ddl, 'ctx_output.', 1, 1) into start_del from dual;		
		if start_del > 0 then -- added by PK for 12.2
		select dbms_lob.instr(index_ddl, ');', 1, 1) + 2 into end_del from dual;
		diff := end_del - start_del;
		dbms_lob.copy(print_ddl, index_ddl, diff, 1, start_del);
		select replace(print_ddl, 'ctx_output.', 'begin'||CHR(10)||' ctx_output.') into print_ddl from dual;
		select replace(print_ddl, ');', ');'||CHR(10)||'end;'||CHR(10)) into print_ddl from dual;
		select dbms_lob.substr(print_ddl, diff + 13, 1) into printstring from dual;
		dbms_lob.trim(print_ddl, 0);
		dbms_output.put_line(printstring);
  		execute immediate (printstring);
		dbms_lob.erase(index_ddl, end_del, 1);
		end if; -- added by PK 		
		select dbms_lob.instr(index_ddl, 'create index "', 1, 1) into start_del from dual;
		select dbms_lob.instr(index_ddl, 'ctx_output.end_log;', 1, 1) - 1 into end_del from dual;		
		if end_del > 0 then -- added by PK for 12.2
		diff := end_del - start_del;
		dbms_lob.copy(print_ddl, index_ddl, diff, 1, start_del);
		select dbms_lob.substr(print_ddl, diff, 1) into printstring from dual;
		dbms_output.put_line(printstring);
 		execute immediate (printstring);
		dbms_lob.trim(print_ddl, 0);
		dbms_lob.erase(index_ddl, end_del, 1);	
		else
		
		select dbms_lob.instr(index_ddl, ''')', 1, 1) +2  into end_del from dual;
		if end_del > 0 then -- added by PK for 12.2
		diff := end_del - start_del;
		dbms_lob.copy(print_ddl, index_ddl, diff, 1, start_del);
		select dbms_lob.substr(print_ddl, diff, 1) into printstring from dual;
		dbms_output.put_line(printstring);
 		--execute immediate (printstring);
		dbms_lob.trim(print_ddl, 0);
		--dbms_lob.erase(index_ddl, end_del, 1);		
		end if;
		
        end if ;  -- added by PK for 12.2
		
		select dbms_lob.instr(index_ddl, 'ctx_output.', 1, 1) into start_del from dual;
		select dbms_lob.instr(index_ddl, 'end_log;', 1, 1) + 8 into end_del from dual;	
		if start_del > 0 then -- added by PK for 12.2
		diff := end_del - start_del;
		dbms_lob.copy(print_ddl, index_ddl, diff, 1, start_del);
		select replace(print_ddl, 'ctx_output.', CHR(10)||'begin'||CHR(10)||' ctx_output.') into print_ddl from dual;
		select replace(print_ddl, 'end_log;', 'end_log;'||CHR(10)||'end;'||CHR(10)) into print_ddl from dual;
		dbms_lob.trim(index_ddl, 0);
		dbms_lob.copy(index_ddl, print_ddl, diff + 13, 1, 1);
		dbms_lob.trim(print_ddl, 0);
		end if; -- added by PK for 12.2
 	end if;

	select replace (index_ddl, 'CREATE INDEX "'||owner||'"."'||iname(j)||'"', 'CREATE INDEX '||intiname) into index_ddl from dual;
	select replace (index_ddl, 'CREATE UNIQUE INDEX "'||owner||'"."'||iname(j)||'"', 'CREATE UNIQUE INDEX '||intiname) into index_ddl from dual;
	select replace (index_ddl, 'ON "'||owner||'"."'||tname(i)||'"', 'ON'||CHR(10)||'  "'||owner||'"."INT_TBL_'||tbs_name||'_'||n||'"') into index_ddl from dual;
	select replace (index_ddl, '", "', '",'||CHR(10)||'  "') into index_ddl from dual;

	for k in 1 .. tbname.count loop -- Tablespace loop
	  	select replace (index_ddl, 'TABLESPACE "'||tbname(k)||'"', 'TABLESPACE "'||tbname(k)||'_ENC"') into index_ddl from dual;
	end loop;

	if dbms_lob.instr(index_ddl, 'SPATIAL_INDEX') > 0 then -- if index = SPATIAL INDEX
		dbms_output.put_line(CHR(10));
		dbms_output.put_line('-- Found spatial index '''||iname(j)||'''.');
		delete from user_sdo_geom_metadata where table_name = 'INT_TBL_'||tbs_name||'_'||n;
		select COLUMN_NAME, DIMINFO, SRID into mcname, mdname, msname from user_sdo_geom_metadata where TABLE_NAME = tname(i);
		insert into user_sdo_geom_metadata (TABLE_NAME, COLUMN_NAME, DIMINFO, SRID) values ('INT_TBL_'||tbs_name||'_'||n, mcname, mdname, msname);
	end if;

	if dbms_lob.getlength(index_ddl) <= 32767 then
		dbms_output.put_line(index_ddl||';');
	else
		dbms_output.put_line('Index DDL is '||dbms_lob.getlength(index_ddl)||' characters long:');
		dbms_output.put_line('Only the first 32,700 characters will be printed:');
		dbms_lob.copy(print_ddl, index_ddl, 32700, 1, 1);
		dbms_output.put_line(print_ddl||' ... TRUNCATED');
		dbms_lob.trim(print_ddl, 0);
	end if;

execute immediate (index_ddl);

dbms_output.put_line(CHR(10));
dbms_redefinition.register_dependent_object(owner, tname(i), 'INT_TBL_'||tbs_name||'_'||n, dbms_redefinition.cons_index, owner, iname(j), intiname);
dbms_output.put_line('-- Registered interim index '''||intiname||'''');
dbms_output.put_line('-- with interim table ''INT_TBL_'||tbs_name||'_'||n||'''.');
  	end loop; -- END index loop

dbms_output.put_line(CHR(10));
dbms_redefinition.copy_table_dependents(owner, tname(i), 'INT_TBL_'||tbs_name||'_'||n, 0, TRUE, TRUE, TRUE, TRUE, num_err, TRUE, TRUE);
dbms_output.put_line('-- Copied dependent objects from '''||tname(i)||'''');
dbms_output.put_line('-- to interim table ''INT_TBL_'||tbs_name||'_'||n||'''.');

dbms_output.put_line(CHR(10));
dbms_redefinition.sync_interim_table(owner, tname(i), 'INT_TBL_'||tbs_name||'_'||n);
dbms_output.put_line('-- Synchronized updates in '''||tname(i)||'''');
dbms_output.put_line('-- with interim table ''INT_TBL_'||tbs_name||'_'||n||'''.');
dbms_output.put_line(CHR(10));

dbms_redefinition.finish_redef_table(owner, tname(i), 'INT_TBL_'||tbs_name||'_'||n);
dbms_output.put_line('-- Swapped table names: '''||tname(i)||''' <==> ''INT_TBL_'||tbs_name||'_'||n||'''.');

dbms_output.put_line(CHR(10));

-- Workaround for bug 16751278; once the patch is available and applied, remove the 
-- following SELECT statement and the loop that follows; also remove the lines
-- rtname		tname_type := tname_type();
-- from the 'declare' section.

select constraint_name, table_name bulk collect into checkname, rtname from user_constraints where CONSTRAINT_TYPE = 'R' and CONSTRAINT_NAME like 'TMP$$%' and STATUS = 'DISABLED' order by table_name;
	for x in 1 .. checkname.count loop
	printstring := 'alter table '||rtname(x)||' drop constraint '||checkname(x);
	dbms_output.put_line(printstring||';');
 	execute immediate (printstring);
	dbms_output.put_line(' ');
	end loop;

-- select count into col_count from user_unused_col_tabs where table_name = tname(i);
-- if col_count > 0 then
--	printstring := 'alter table '||tname(i)||' drop unused columns';
--	dbms_output.put_line(printstring||';');
--  execute immediate (printstring);
--	dbms_output.put_line(' ****************************************************************************** ');
--	dbms_output.put_line(' ');
-- end if;

	end loop; -- END table loop

-- select constraint_name, table_name bulk collect into checkname, rtname from user_constraints where CONSTRAINT_TYPE = 'R' and STATUS = 'DISABLED' order by table_name;
--	for x in 1 .. checkname.count loop
--	printstring := 'alter table '||rtname(x)||' modify constraint '||checkname(x)||' ENABLE';
--	dbms_output.put_line(printstring||';');
--	execute immediate (printstring);
--	dbms_output.put_line(' ');
--	end loop;

end if; -- tname.count > 0
commit;
end;
/
spool off;
exit;
