-- BA - Ergaenzung
grant dba,sysdba to system container=all; 

--set new datafile size/adjusting tablespaces pdbseed
--alter session set container = PDB$SEED;
--alter session set "_oracle_script"=TRUE;
--alter pluggable database PDB$SEED CLOSE IMMEDIATE instances=all;
--alter pluggable database PDB$SEED open instances=all;
--CREATE OR REPLACE PROCEDURE tbs_p(p_tbs out SYS_REFCURSOR)
--AS
--begin
  --for prec_sys in
--(SELECT a.TABLESPACE_NAME, b.TS#, a.FILE_ID, a.FILE_NAME from V$TABLESPACE b,
--(SELECT TABLESPACE_NAME, FILE_ID, FILE_NAME, CON_ID from CDB_DATA_FILES UNION SELECT TABLESPACE_NAME,FILE_ID, FILE_NAME, CON_ID from CDB_TEMP_FILES) a
--where b.NAME=a.TABLESPACE_NAME and b.CON_ID=(SELECT CON_NAME_TO_ID('PDB\$SEED') FROM DUAL) AND a.CON_ID=b.CON_ID)loop
     --IF prec_sys.TABLESPACE_NAME like 'SYS%%' THEN  execute immediate 'alter database datafile '||prec_sys.FILE_ID||' resize 5G';
      --ELSIF prec_sys.TABLESPACE_NAME like 'UNDO%%' THEN execute immediate 'alter database datafile '||prec_sys.FILE_ID||' resize 3G';
      --ELSIF prec_sys.TABLESPACE_NAME like 'TEM%%' THEN execute immediate 'alter database tempfile '||prec_sys.FILE_ID||' resize 3G';
      --END IF;
      --end loop;
   --end;
--/
--VAR TBS2 REFCURSOR;
--EXEC SYS.TBS_P( :TBS2);
--Drop procedure SYS.TBS_P;
--alter session set container = CDB$ROOT;
--alter session set "_oracle_script"=FALSE;
--alter pluggable database PDB$SEED CLOSE IMMEDIATE instances=all;
--alter pluggable database PDB$SEED OPEN read only instances=all;

-- Anpassung Default Profile
alter profile default limit failed_login_attempts unlimited;
alter profile default limit password_life_time unlimited;
alter profile default limit password_lock_time unlimited;
alter profile default limit password_grace_time unlimited;

-- Unified Auditing abschalten
NOAUDIT POLICY ORA_SECURECONFIG;

-- von Andreas 
EXEC dbms_stats.init_package();

-- MVIEW Statistiken ausschalten 
select * from user_mvref_stats_sys_defaults;
exec dbms_mview_stats.set_system_default('COLLECTION_LEVEL', 'NONE');
--Aktueller Collection level füEW Statistiken:
select * from user_mvref_stats_sys_defaults;
-- Steht nun auf NONE

-- Registry checken 
--@?/rdbms/admin/utlrp.sql;
--column comp_name format a40
--select comp_name,version,status from dba_registry;

-- ZELOS Anpasssungen 
exec DBMS_WORKLOAD_REPOSITORY.modify_snapshot_settings( retention => 11520, interval  => 60);
select extract( day from snap_interval) *24*60+extract( hour from snap_interval) *60+extract( minute from snap_interval ) snapshot_interval, 
extract( day from retention) *24*60+extract( hour from retention) *60+extract( minute from retention ) retention_interval, topnsql from dba_hist_wr_control;
--
--  --> AWR-Retention >= MOVING_WINDOW_SIZE (default 8)!!
select moving_window_size from dba_hist_baseline;
exec DBMS_WORKLOAD_REPOSITORY.modify_baseline_window_size( window_size => 8);
select moving_window_size from dba_hist_baseline;
--
BEGIN
EXECUTE IMMEDIATE 'alter system set resource_manager_plan=''''';
FOR rwindow IN (SELECT window_name, resource_plan, enabled, active, REPEAT_INTERVAL, DURATION, START_DATE FROM dba_scheduler_windows WHERE resource_plan IN
 ('DEFAULT_MAINTENANCE_PLAN')) LOOP
      DBMS_OUTPUT.put_line('Setting window ' || rwindow.window_name || ' to resource manager plan none');
      dbms_scheduler.set_attribute(rwindow.window_name,'RESOURCE_PLAN','');
   END LOOP;
    dbms_auto_task_admin.DISABLE(CLIENT_NAME => 'auto space advisor', operation => NULL, window_name => NULL);
    dbms_auto_task_admin.DISABLE(CLIENT_NAME => 'sql tuning advisor', operation => NULL, window_name => NULL);
  COMMIT;
END;
/
