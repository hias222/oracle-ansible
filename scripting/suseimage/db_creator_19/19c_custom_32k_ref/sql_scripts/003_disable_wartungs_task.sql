execute DBMS_AUTO_TASK_ADMIN.enable();
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

