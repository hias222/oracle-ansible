-----------------------------------------------------------------------------------------------------------------------------------------
-- Beginn dba_autotask_client_ersatz.sql
-----------------------------------------------------------------------------------------------------------------------------------------
begin
  for r in ( select client_name from dba_autotask_client where status = 'ENABLED') loop
    begin
      dbms_auto_task_admin.disable(
      client_name => r.client_name,
      operation   => NULL,
      window_name => NULL);
    exception
      when others then
        null;
    end;
  end loop;
end;
/

-----------------------------------------------------------------------------------------------------------------------------------------
select client_name, status from dba_autotask_client;
-----------------------------------------------------------------------------------------------------------------------------------------

set lin 155  
col con_id head "Con|tai|ner" form 999
col id head "Opera|tion|ID" form 9999999
col operation head "Operation" form a30
col job_name head "job name" form a22
col target head "Target" form a10
col jst head "Operation|start|time" form a12
col duration head "Operation|dura|tion|mins" form 999999
col status head "Operation|status" form a10

select 	con_id, id, operation, job_name, target, to_char(start_time, 'DD-MON HH24:MI') jst,
	extract(hour from (end_time - start_time))*60 + extract(minute from (end_time - start_time)) duration,
	status
from  	cdb_optstat_operations
where	operation = 'gather_database_stats (auto)'
order 	by  start_time, con_id
/

--exec dbms_stats.gather_database_stats;

connect /as sysdba

declare
  ora_27475 exception;
  pragma exception_init(ora_27475, -27475);
  ldrUser      varchar2(32000) := 'PSLFRSYS';
begin
  dbms_scheduler.stop_job(job_name => ldrUser || '$collect_stats', force => true);
exception
  when ora_27475 then
    null;
end;
/

declare
  ora_27475 exception;
  pragma exception_init(ora_27475, -27475);
  ldrUser      varchar2(32000) := 'PSLFRSYS';
begin
  dbms_scheduler.drop_job(job_name => ldrUser || '$collect_stats');
exception
  when ora_27475 then
    null;
end;
/

declare
  ldrUser      varchar2(32000) := 'PSLFRSYS';
begin
  dbms_scheduler.create_job(job_name => ldrUser || '$collect_stats',
                            job_type => 'PLSQL_BLOCK',
                            job_action => 'begin dbms_stats.gather_fixed_objects_stats(no_invalidate => false); dbms_stats.gather_dictionary_stats(no_invalidate => false); dbms_stats.gather_database_stats( options=> ''gather stale'', no_invalidate => false); end;',
                            start_date => sysdate + 20/(24*60),
                            repeat_interval => 'FREQ = MINUTELY; INTERVAL = 300',
                            auto_drop => FALSE,
                            enabled => TRUE);
end;
/

set lines 150 pages 5000
col ADDITIONAL_INFO format a30
col LAST_START_DATE for a40
col NEXT_RUN_DATE for a40
col LOG_DATE for a40
--select LAST_START_DATE, STATE, NEXT_RUN_DATE from dba_scheduler_jobs where job_name = 'PSLFRSYS$COLLECT_STATS';
-- Kurzer "sleep" damit die initiale Statistik die Chance hat fertig zu werden bevor die DB durchgestartet wird 
--exec DBMS_LOCK.sleep(seconds => 60);
select LAST_START_DATE, STATE, NEXT_RUN_DATE from dba_scheduler_jobs where job_name = 'PSLFRSYS$COLLECT_STATS';
select LOG_DATE, STATUS, OPERATION, ADDITIONAL_INFO from dba_scheduler_job_log where job_name = 'PSLFRSYS$COLLECT_STATS' order by 1;
commit;
-----------------------------------------------------------------------------------------------------------------------------------------
-- Ende dba_autotask_client_ersatz.sql
-----------------------------------------------------------------------------------------------------------------------------------------
