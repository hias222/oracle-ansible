# tests

## nvme

l9790022:~ # nvme list
Node             SN                   Model                                    Namespace Usage                      Format           FW Rev
---------------- -------------------- ---------------------------------------- --------- -------------------------- ---------------- --------
/dev/nvme0n1     PHLN006000ZH6P4CGN   7361456_ICRPC2DD2ORA6.4T                 1           6.40  TB /   6.40  TB    512   B +  0 B   VDV1RL04


l9790022:~ # hdparm -a 0 /dev/nvme0n1

/dev/nvme0n1:
 setting fs readahead to 0
 readahead     =  0 (off)

 ## iocalibrate

 eine NVME

 max_iops = 379174
latency  = ,313
max_mbps = 3114
max_iops = 379174
latency  = 0
max_mbps = 3114