rman target /
CONFIGURE COMPRESSION ALGORITHM 'BASIC';    
CONFIGURE DEVICE TYPE disk PARALLELISM 4;
shutdown immediate;
startup mount;
RUN
{
ALLOCATE CHANNEL ch11 TYPE DISK;
ALLOCATE CHANNEL ch12 TYPE DISK;
ALLOCATE CHANNEL ch13 TYPE DISK;
ALLOCATE CHANNEL ch14 TYPE DISK;
backup as compressed backupset database
FORMAT '/opt/oracle/temp/%d_D_%T_%u_s%s_p%p'
CURRENT CONTROLFILE FORMAT '/opt/oracle/temp/ctl_cdbseed.bkp'
SPFILE FORMAT '/opt/oracle/temp/spfile_cdbseed.bkp';
}
alter database open;