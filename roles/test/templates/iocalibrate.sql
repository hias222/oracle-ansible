SET SERVEROUTPUT ON
-- check with dstat -pcmrd
DECLARE
      lat  INTEGER;
      iops INTEGER;
      mbps INTEGER;
     BEGIN
      --DBMS_RESOURCE_MANAGER.CALIBRATE_IO(, , iops, mbps, lat);
      DBMS_RESOURCE_MANAGER.CALIBRATE_IO (1, 1, iops, mbps, lat);
      DBMS_OUTPUT.PUT_LINE ('max_iops = ' || iops);
      DBMS_OUTPUT.PUT_LINE ('latency  = ' || lat);
      DBMS_OUTPUT.PUT_LINE ('max_mbps = ' || mbps);
END;
/