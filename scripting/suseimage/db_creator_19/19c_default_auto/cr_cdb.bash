#!/bin/bash

fct_usage()
{
echo -e "
cr_cdb.bash <DB_NAME>

Usage:
\t<DB_NAME> = name of the new database
"
}

if [[ $# != 1 ]];then
 fct_usage
 exit 1
fi

START=$(date +%s)
DB_NAME=$1
RAC=0
RAC=$(ps -ef | grep -i "ocssd.bin" | grep -v grep | wc -l)
SCHUL_HOST='l9693022'

#####
# env
#####
DB_UNIQUE_NAME=${DB_NAME}
WORK_DIR=$(pwd)
DB_NAME_CL=$(echo "${DB_NAME}" | tr a-z A-Z)

export ORACLE_HOME=/orasw/oracle/product/db19
export ORACLE_BASE=/orasw/oracle
export PERL5LIB=${ORACLE_HOME}/rdbms/admin:$PERL5LIB
export PATH=${ORACLE_HOME}/bin:${ORACLE_HOME}/perl/bin:$PATH
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
if [[ -f ${WORK_DIR}/resources/.dbvpw.enc ]];then
  export $(openssl enc -aes-256-cbc -d -in ${WORK_DIR}/resources/.dbvpw.enc -k DBVAULT2020)
else
  echo "${WORK_DIR}/resources/.dbvpw.enc not found, please check."
  exit 1
fi
export PATH=${ORACLE_HOME}:${PATH}

TNSNAMES_ORA=${ORACLE_HOME}/network/admin/tnsnames.ora
LISTENER_ORA=${ORACLE_HOME}/network/admin/listener.ora
ORATAB=/etc/oratab
ORAPWFILE=/orasw/oracle/BA/adm/etc/ora_pwfile
ALIAS=/home/oracle/.alias


#####
# getting sys/system password
#####
read -p "enter sys/system password[[ (return) = default (oracle)]]: " SYS_PW
[[ -z ${SYS_PW} ]] && SYS_PW=oracle

if [[ $RAC -eq 0 ]];then
#####
# getting port
#####
unset PORT
while [ -z "$PORT" ]
 do
  echo "Enter PORT"
  read PORT
  used_ports=$(grep -E "\<PORT = [0-9]*" ${LISTENER_ORA} | awk '{ print $NF }' | sed 's/)//g')
   if [[ $(echo "$used_ports" | grep $PORT) ]]
    then
    echo "PORT $PORT is already used, enter again"
    echo "Already used Ports: $used_ports"
    unset PORT
   fi
done
echo "PORT $PORT will be used"
fi

mkdir -p ${ORACLE_BASE}/admin/${DB_UNIQUE_NAME}/log
LOGFILE=${ORACLE_BASE}/admin/${DB_UNIQUE_NAME}/log/$(echo "install_cdb_${DB_NAME}_$(date '+Y%YM%mD%d_H%HM%MS%S').log")
log_dir=${ORACLE_BASE}/admin/${DB_UNIQUE_NAME}/log

if [[ $RAC -eq 0 ]];then
 export ORACLE_SID=${DB_NAME}
 #l9693022 & idst Databases get db adress hostname
 if [[ $(uname -n) = ${SCHUL_HOST} ]] || [[ $(nslookup $(uname -n) | grep ^Name: | awk '{ print $2 }' | cut -d'.' -f 2) = 'idst' ]];then
  HOST=$(echo "$(uname -n)db.$(nslookup $(uname -n) | grep ^Name: | awk '{ print $2 }' | cut -d'.' -f 2-)")
 else
  HOST=$(nslookup $(uname -n) | grep ^Name: | awk -F' ' '{ print $2 }')
 fi
else
 export CRS_HOME=$(cat ${ORATAB} | grep -v ^# | grep -v ^$ | grep -E "^[+|-]" | cut -d":" -f2 | sort | uniq)
 HOST=$(uname -n)
 HOST2=$(${CRS_HOME}/bin/olsnodes | grep -v ${HOST})
 HOST_NUM=$(${CRS_HOME}/bin/olsnodes -n | grep  ${HOST} | awk -F' ' '{ print $2 }')
 HOST2_NUM=$(${CRS_HOME}/bin/olsnodes -n | grep -v ${HOST} | awk -F' ' '{ print $2 }')
 export ORACLE_SID=${DB_NAME}${HOST_NUM}
 DOMAIN=$(nslookup $(uname -n) | grep ^Name: | awk -F' ' '{ print $2 }' | cut -d"." -f2-)
 CLUSTER_NAME=$(${CRS_HOME}/bin/olsnodes -c)
fi


if [[ $RAC -eq 0 ]];then
 echo "Starting Single installation with:" | tee -a ${LOGFILE}
else
 echo "Starting RAC installation with:" | tee -a ${LOGFILE}
fi
echo "" >> ${LOGFILE}


echo "
DATABASE_NAME=${DB_NAME}
ORACLE_SID=${ORACLE_SID}
DB_UNIQUE_NAME=${DB_NAME}
ORACLE_HOME=${ORACLE_HOME}
ORACLE_BASE=${ORACLE_BASE}" | tee -a ${LOGFILE}
if [[ $RAC -eq 0 ]];then
echo "PORT=${PORT}" | tee -a ${LOGFILE}
fi
echo "
Log_Dir=${ORACLE_BASE}/admin/${DB_UNIQUE_NAME}/log/
Main Log File: ${LOGFILE}

" | tee -a ${LOGFILE}

echo "is this correct? (y/n)?"
read answer
if [ "$answer" != "${answer#[Yy]}" ] ;then
echo ""

cp -p ./resources/ctl_cdbseed.ctl ctl_${DB_NAME}.ctl

#####
# creating directorys
#####
echo "###[STEP]### create directories..." | tee -a ${LOGFILE}

if [[ $RAC -eq 0 ]];then
 if [ ! -r /oraclearch ];then
  mkdir -p ${ORACLE_BASE}/admin/${ORACLE_SID}/arch
 else
  mkdir -p /oraclearch/ora12c/${ORACLE_SID}
  [ ! -r ${ORACLE_BASE}/admin/${ORACLE_SID}/arch ] && ln -s /oraclearch/ora12c/${ORACLE_SID} ${ORACLE_BASE}/admin/${ORACLE_SID}/arch
 fi
 [ ! -r /oracle/ora12c ] && mkdir -p /oracle/ora12c
 [ ! -r ${ORACLE_BASE}/oradata ] && ln -s /oracle/ora12c ${ORACLE_BASE}/oradata
 [ ! -r ${ORACLE_BASE}/oradata/${DB_NAME_CL} ] && mkdir -p ${ORACLE_BASE}/oradata/${DB_NAME_CL}
 [ ! -r ${ORACLE_BASE}/BA/etc/ ] && mkdir -p ${ORACLE_BASE}/BA/etc
 mkdir -p ${ORACLE_BASE}/oradata/${DB_NAME_CL}
 mkdir -p ${ORACLE_BASE}/diag/rdbms/${ORACLE_SID}/${DB_UNIQUE_NAME}/cdump
 mkdir -p ${ORACLE_BASE}/admin/${DB_UNIQUE_NAME}/arch
else
 mkdir -p /orabase/admin/${DB_NAME}/adump
fi
echo "" >> ${LOGFILE}


#####
# create pwfile
#####
if [[ $RAC -eq 0 ]];then
echo "###[STEP]### creating DB pwfile..." | tee -a ${LOGFILE}
${ORACLE_HOME}/bin/orapwd file=${ORACLE_HOME}/dbs/orapw${DB_NAME} force=y format=12 password=${SYS_PW} entries=50
#ls -ltr ${ORACLE_HOME}/dbs/orapw${ORACLE_SID} | tee -a ${LOGFILE}
fi
echo "" >> ${LOGFILE}


#####
# create temp init.ora
#####
echo "###[STEP]### create init files..." | tee -a ${LOGFILE}
echo "#
log_archive_format=%t_%s_%r.arch
db_block_size=8192
open_cursors=300
db_name=\"cdbseed\"
compatible=19.0.0.0
diagnostic_dest = ${ORACLE_BASE}
enable_pluggable_database=true
nls_language=\"GERMAN\"
nls_territory=\"GERMANY\"
#local_listener=LISTENER_${DB_NAME}
processes=1920
sga_target=5g
audit_file_dest=\"/orasw/oracle/admin/${DB_NAME}/adump\"
audit_trail=OS
audit_syslog_level=\"local1.warning\"
audit_sys_operations=FALSE
remote_login_passwordfile=EXCLUSIVE
dispatchers=\"(PROTOCOL=TCP) (SERVICE=${DB_NAME}XDB)\"
pga_aggregate_target=3g
undo_tablespace=UNDOTBS1
db_unique_name=\"${DB_NAME}\"
_diag_hm_rc_enabled=false
nls_language=\"GERMAN\"
nls_territory=\"GERMANY\"
nls_length_semantics=\"CHAR\"
control_files=\"$(pwd)/resources/ctl_cdbseed.ctl\"
JOB_QUEUE_PROCESSES=0
AQ_TM_PROCESSES=0
_no_recovery_through_resetlogs=true
_enable_automatic_maintenance=0
_diag_hm_rc_enabled=false
" > init_tmp_${DB_NAME}.ora

if [[ $RAC -eq 0 ]];then
echo "
db_create_file_dest = ${ORACLE_BASE}/oradata/ #OMF
db_create_online_log_dest_1 = ${ORACLE_BASE}/oradata/ #OMF
db_create_online_log_dest_2 = ${ORACLE_BASE}/oradata/ #OMF
log_archive_dest_1 = 'LOCATION=${ORACLE_BASE}/admin/arch'
" >> init_tmp_${DB_NAME}.ora
else
echo "
db_create_file_dest=+DG1
db_create_online_log_dest_1=+DG1
db_create_online_log_dest_2=+DG1
db_recovery_file_dest=+DG1
db_recovery_file_dest_size=50G
log_archive_dest_1='LOCATION=USE_DB_RECOVERY_FILE_DEST'
log_archive_dest_2='LOCATION=+DG1'
" >> init_tmp_${DB_NAME}.ora
fi


#####
# final init.ora
#####
echo "#
dispatchers=\"(PROTOCOL=TCP) (SERVICE=${DB_NAME}XDB)\"
undo_management = AUTO
db_name = ${DB_NAME}
db_files = 2048
db_block_size = 8192
enable_pluggable_database=true
max_pdbs=200
_exclude_seed_cdb_view=FALSE
_gby_hash_aggregation_enabled=false
_use_single_log_writer=true
_optimizer_aggr_groupby_elim=false
_cursor_obsolete_threshold=1024
awr_pdb_autoflush_enabled=TRUE
awr_snapshot_time_offset=1000000
open_cursors=300
processes=400
parallel_max_servers=32
sga_target = 5G
pga_aggregate_target = 4G
shared_pool_size=512M
db_cache_size=512M
large_pool_size=128M
streams_pool_size=100M
compatible=19.0.0.0
nls_language=\"GERMAN\"
nls_territory=\"GERMANY\"
nls_length_semantics=\"CHAR\"
audit_file_dest=\"/orabase/admin/${DB_NAME}/adump\"
audit_trail=OS
audit_syslog_level=\"local1.warning\"
audit_sys_operations=FALSE
remote_login_passwordfile=EXCLUSIVE
recyclebin=off
parallel_force_local=TRUE
deferred_segment_creation=false
uniform_log_timestamp_format=FALSE
max_dump_file_size=100M
diagnostic_dest = ${ORACLE_BASE}
undo_tablespace=UNDOTBS1
log_archive_format=%t_%s_%r.arch
target_pdbs=30
" > init${DB_NAME}.ora

if [[ $RAC -eq 0 ]];then
echo "
control_files = (${ORACLE_BASE}/oradata/${DB_NAME_CL}/control1.ctl,${ORACLE_BASE}/oradata/${DB_NAME_CL}/control2.ctl)
use_large_pages=false
filesystemio_options=setall
db_create_file_dest = ${ORACLE_BASE}/oradata/ #OMF
db_create_online_log_dest_1 = ${ORACLE_BASE}/oradata/ #OMF
db_create_online_log_dest_2 = ${ORACLE_BASE}/oradata/ #OMF
log_archive_dest_1 = 'LOCATION=${ORACLE_BASE}/admin/${ORACLE_SID}/arch'
" >> init${DB_NAME}.ora
else
echo "
control_files=(\"+DG1/${DB_NAME_CL}/${DB_NAME}.ctl1\",\"+DG1/${DB_NAME_CL}/${DB_NAME}.ctl2\")
use_large_pages=only
db_create_file_dest=+DG1
db_create_online_log_dest_1=+DG1
db_create_online_log_dest_2=+DG1
db_recovery_file_dest=+DG3
db_recovery_file_dest_size=50G
log_archive_dest_1='LOCATION=USE_DB_RECOVERY_FILE_DEST'
log_archive_dest_2='LOCATION=+DG1'
_backup_file_bufcnt=8
_backup_file_bufsz=16777216
_gby_hash_aggregation_enabled=false
" >> init${DB_NAME}.ora
fi
echo "" >> ${LOGFILE}


#####
# startup mount und clear
#####
echo "###[STEP]### cloning database from backup..." | tee -a ${LOGFILE}
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL >> ${LOGFILE} 2>&1
startup mount pfile="init_tmp_${DB_NAME}.ora";
execute dbms_backup_restore.resetCfileSection(dbms_backup_restore.RTYP_DFILE_COPY);
execute dbms_backup_restore.resetCfileSection(13);
EOSQL


#####
# rename datafiles in RMAN
#####
data_path="'${WORK_DIR}/resources/datafiles/'"
${ORACLE_HOME}/bin/rman target / <<EORMAN  >> ${LOGFILE} 2>&1
SPOOL LOG TO ${LOGFILE} append;
CATALOG START WITH ${data_path} NOPROMPT  ;
RUN {
set newname for datafile 1 to new;
set newname for datafile 2 to new;
set newname for datafile 3 to new;
set newname for datafile 4 to new;
set newname for datafile 5 to new;
set newname for datafile 6 to new;
set newname for datafile 7 to new;
set newname for datafile 8 to new;
restore database;
}
EORMAN


#####
# check renamed datafiles
#####
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL >> ${LOGFILE} 2>&1
select NAME FROM V\$DATAFILE_COPY order by 1;
EOSQL


#####
# saving new datafiles location in vars
#####
cnt=0
files=$(${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL
set heading off;
set feedback off;
set lines 200;
col name for a150;
select NAME FROM V\$DATAFILE_COPY order by 1;
EOSQL
)

for i in ${files}
do
 declare file${cnt}=\'$i\'
 ((cnt+= 1))
done


#####
#####
echo "###[STEP]### change db name & generate new controlfiles..." | tee -a ${LOGFILE}
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL >> ${LOGFILE} 2>&1
shutdown abort;
--
startup nomount pfile="init${DB_NAME}.ora";
--
Create controlfile reuse set database "${DB_NAME}"
MAXINSTANCES 8
MAXLOGHISTORY 1
MAXLOGFILES 16
MAXLOGMEMBERS 3
MAXDATAFILES 1024
Datafile
${file0},
${file1},
${file2},
${file3},
${file4},
${file5},
${file6},
${file7}
LOGFILE GROUP 01  SIZE 512M,
GROUP 02  SIZE 512M,
GROUP 03  SIZE 512M RESETLOGS;
--
select name from v\$controlfile;
--
connect / as sysdba
exec dbms_backup_restore.zerodbid(0);
--
alter system enable restricted session;
alter database "${DB_NAME}" open resetlogs;
--
DECLARE
cursor cur_services is
select name from dba_services where name like 'cdbseed%';
BEGIN
 for i in cur_services loop
 dbms_service.delete_service(i.name);
 end loop;
END;
/
--
connect / as sysdba
alter database rename global_name to "${DB_NAME}";
ALTER TABLESPACE TEMP ADD TEMPFILE SIZE 3G;
alter session set container = PDB\$SEED;
alter session set "_oracle_script"=TRUE;
alter pluggable database PDB\$SEED CLOSE IMMEDIATE;
alter pluggable database PDB\$SEED open;
ALTER PROFILE  default LIMIT PASSWORD_LIFE_TIME UNLIMITED;
ALTER TABLESPACE TEMP ADD TEMPFILE SIZE 3G;
alter session set container = CDB\$ROOT;
alter session set "_oracle_script"=FALSE;
alter pluggable database PDB\$SEED CLOSE IMMEDIATE;
alter pluggable database PDB\$SEED OPEN read only;
select tablespace_name from dba_tablespaces where tablespace_name='USERS';
ALTER PROFILE default LIMIT PASSWORD_VERIFY_FUNCTION null;
ALTER PROFILE c##ba_user LIMIT PASSWORD_LIFE_TIME UNLIMITED;
alter user sys account unlock identified by "${SYS_PW}";
alter user system account unlock identified by "${SYS_PW}";
alter user dbsnmp identified by Casper001 account unlock;
--
EOSQL
echo "" >> ${LOGFILE}


#####
# create spfile
#####
if [[ $RAC -eq 0 ]];then
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL >> ${LOGFILE} 2>&1
create spfile='${ORACLE_HOME}/dbs/spfile${DB_NAME}.ora' FROM pfile='${WORK_DIR}/init${DB_NAME}.ora';
EOSQL
else
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL >> ${LOGFILE} 2>&1
create spfile='+DG1/${DB_UNIQUE_NAME}/spfile${DB_NAME}' from pfile='${WORK_DIR}/init${DB_NAME}.ora';
EOSQL
echo "###[STEP]### create crs ressources & pw File" | tee -a ${LOGFILE}
${ORACLE_HOME}/bin/srvctl add database -db ${DB_NAME} -o ${ORACLE_HOME} -spfile +DG1/${DB_UNIQUE_NAME}/spfile${DB_NAME} -dbname ${DB_UNIQUE_NAME} >> ${LOGFILE} 2>&1
${ORACLE_HOME}/bin/srvctl add instance -db ${DB_NAME} -instance ${DB_NAME}${HOST_NUM} -node ${HOST} >> ${LOGFILE} 2>&1
${ORACLE_HOME}/bin/orapwd file="+DG1/${DB_UNIQUE_NAME}/pwd${DB_NAME}" format=12 password=${SYS_PW} entries=50 dbuniquename=${DB_UNIQUE_NAME} >> ${LOGFILE} 2>&1
fi


#####
# post actions
#####
echo "###[STEP]### doing some post options on new db..." | tee -a ${LOGFILE}
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL >> ${LOGFILE} 2>&1
grant sysdba to system container=all;
alter system disable restricted session;
alter user sys account unlock identified by "${SYS_PW}";
alter user system account unlock identified by "${SYS_PW}";
UPDATE sys.USER$ set SPARE6=NULL;
execute dbms_datapump_utl.create_default_dir;
--disable autotasks
EXEC DBMS_AUTO_TASK_ADMIN.DISABLE(client_name=>'sql tuning advisor', operation=>NULL, window_name=>NULL);
EXEC DBMS_AUTO_TASK_ADMIN.DISABLE(client_name=>'auto space advisor', operation=>NULL, window_name=>NULL);
SELECT client_name, status FROM dba_autotask_client;
commit;
alter session set "_oracle_script"=FALSE;
host perl ${ORACLE_HOME}/rdbms/admin/catcon.pl -n 1 -l ${log_dir} -v  -b ordlib  -U "SYS"/"${SYS_PW}" ${ORACLE_HOME}/ord/im/admin/ordlib.sql;
connect / as SYSDBA
create or replace directory XMLDIR as '${ORACLE_HOME}/rdbms/xml';
create or replace directory XSDDIR as '${ORACLE_HOME}/rdbms/xml/schema';
create or replace directory ORA_DBMS_FCP_ADMINDIR as '${ORACLE_HOME}/rdbms/admin';
create or replace directory ORA_DBMS_FCP_LOGDIR as '${ORACLE_HOME}/cfgtoollogs';
@${ORACLE_HOME}/rdbms/admin/execocm.sql;
execute dbms_qopatch.replace_logscrpt_dirs;
connect / as SYSDBA
create or replace directory ORACLE_HOME as '${ORACLE_HOME}';
create or replace directory ORACLE_BASE as '${ORACLE_BASE}';
connect / as sysdba
host perl ${ORACLE_HOME}/rdbms/admin/catcon.pl -n 1 -l ${log_dir} -v  -b utlrp  -U "SYS"/"${SYS_PW}" ${ORACLE_HOME}/rdbms/admin/utlrp.sql;
select comp_id, status from dba_registry;
connect / as sysdba
execute dbms_swrf_internal.cleanup_database(cleanup_local => FALSE);
commit;
shutdown immediate;
EOSQL


#####
# generate new dbid
#####
echo "###[STEP]### generate new DBID and log mode... " | tee -a ${LOGFILE}
if [[ $(uname -n) = ${SCHUL_HOST} ]]; then
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL >> ${LOGFILE} 2>&1
startup mount;
alter database noarchivelog;
EOSQL
echo "DB befindet sich im noarchivelog-mode"
else
${ORACLE_HOME}/bin/sqlplus -S -L / as sysdba << EOSQL >> ${LOGFILE} 2>&1
startup mount;
alter database archivelog;
EOSQL
echo "DB befindet sich im archivelog-mode"
fi

nid TARGET=SYS/oracle LOGFILE=${LOGFILE} APPEND=YES

${ORACLE_HOME}/bin/sqlplus -S -L / as sysdba << EOSQL >> ${LOGFILE} 2>&1
STARTUP MOUNT;
ALTER DATABASE OPEN RESETLOGS;
EOSQL


#####
# execute Datapatch
#####
echo "###[STEP]### executing datapatch... " | tee -a ${LOGFILE}
${ORACLE_HOME}/OPatch/datapatch -skip_upgrade_check >> ${LOGFILE} 2>&1


if [[ $RAC -eq 0 ]];then
#####
# generate tnsnames entry for SINGLE
#####
echo "###[STEP]### create tnsnames.ora entry..." | tee -a ${LOGFILE}
ENTRY=$(echo "#Eintrag fuer Datenbankinstanz und Listener ${DB_NAME}, $(date '+%d.%m.%Y')
${DB_NAME}=
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${HOST})(PORT = ${PORT}))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${DB_NAME})
    )
  )

listener_${DB_NAME}=
  (ADDRESS_LIST =
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${HOST})(PORT = $PORT))
  )

")

grep -i  "${DB_NAME}[: $=]" ${TNSNAMES_ORA} >/dev/null
RC=$?
if [[ $RC != 0 ]];then
echo "${ENTRY}" >> ${TNSNAMES_ORA}
else
echo "SKIP - Entry already exists" | tee -a ${LOGFILE}
fi
ENTRY=''
echo "" >> ${LOGFILE}


#####
# generate listener.ora entry for SINGLE
#####
echo "###[STEP]### create listener.ora entry..." | tee -a ${LOGFILE}
ENTRY=$(echo "#Eintrag fuer Datenbankinstanz und Listener ${DB_NAME}, $(date '+%d.%m.%Y')
listener_${DB_NAME} =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS_LIST =
        (ADDRESS = (PROTOCOL = TCP)(HOST = ${HOST})(PORT = ${PORT}))
      )
    )
  )

SID_LIST_listener_${DB_NAME} =
  (SID_LIST =
    (SID_DESC =
      (ORACLE_HOME = ${ORACLE_HOME})
      (SID_NAME = ${ORACLE_SID})
    )
  )

LOGGING_listener_${DB_NAME} = OFF

")

grep -i  "${DB_NAME}[: $=]" ${LISTENER_ORA} >/dev/null
RC=$?
if [[ $RC != 0 ]];then
echo "${ENTRY}" >> ${LISTENER_ORA}
else
echo "SKIP - Entry already exists" | tee -a ${LOGFILE}
fi
ENTRY=''
echo "" >> ${LOGFILE}

else

####
# generate tnsnames.ora Entry for RAC
####
echo "###[STEP]### making tnsnames.ora Entry" | tee -a ${LOGFILE}
ENTRY=$(echo "#Eintrag fuer Datenbank ${DB_NAME}, $(date '+%d.%m.%Y')
${DB_NAME}${HOST_NUM} =
  (DESCRIPTION =
    (ADDRESS_LIST =
      (ADDRESS = (PROTOCOL = TCP)(HOST = ${CLUSTER_NAME}.${DOMAIN})(PORT = 57575))
    )
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${DB_NAME}_l)
    )
  )

${DB_NAME}${HOST2_NUM} =
  (DESCRIPTION =
    (ADDRESS_LIST =
      (ADDRESS = (PROTOCOL = TCP)(HOST = ${CLUSTER_NAME}.${DOMAIN})(PORT = 57575))
    )
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${DB_NAME}_r)
    )
  )

${DB_NAME} =
  (DESCRIPTION =
    (ADDRESS_LIST =
      (ADDRESS = (PROTOCOL = TCP)(HOST = ${CLUSTER_NAME}.${DOMAIN})(PORT = 57575))
    )
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${DB_NAME})
    )
  )
")

#Server 1
if [[ ! -f ${TNSNAMES_ORA} ]];then
touch ${TNSNAMES_ORA}
fi

grep -i  "${DB_NAME}[: $=]" ${TNSNAMES_ORA} >/dev/null
RC=$?
if [[ $RC != 0 ]];then
echo "${ENTRY}" >> ${TNSNAMES_ORA}
echo "$(uname -n): OK" | tee -a ${LOGFILE}
else
echo "$(uname -n): SKIP - Entry already exists" | tee -a ${LOGFILE}
fi

fi


#####
# generate /etc/oratab Entry
#####
echo "###[STEP]### create oratab entry..." | tee -a ${LOGFILE}
ENTRY=$(echo "${DB_NAME}:${ORACLE_HOME}:N")

if [[ ! -f ${ORATAB} ]];then
touch ${ORATAB}
fi

grep -i  "${DB_NAME}[: $=]" ${ORATAB} >/dev/null
RC=$?
if [[ $RC != 0 ]];then
echo "${ENTRY}" >> ${ORATAB}
else
echo "SKIP - Entry already exists" | tee -a ${LOGFILE}
fi
echo "" >> ${LOGFILE}


#####
# generate ora_pwfile ($Z/etc) entry
#####
if [[ ! -f ${ORAPWFLIE} ]];then
touch ${ORAPWFILE}
fi

echo "###[STEP]### create \$Z/etc/ora_pwfile entry..." | tee -a ${LOGFILE}
ENTRY=$(echo "${DB_NAME}:system:${SYS_PW}:::")

grep -i  "${DB_NAME}[: $=]" ${ORAPWFILE} >/dev/null
RC=$?
if [[ $RC != 0 ]];then
echo "${ENTRY}" >> ${ORAPWFILE}
else
echo "SKIP - Entry already exists" | tee -a ${LOGFILE}
fi

echo "" >> ${LOGFILE}


#####
# start listener & register
#####
if [[ $RAC -eq 0 ]];then
echo "###[STEP]### starting listener & register database..." | tee -a ${LOGFILE}
${ORACLE_HOME}/bin/lsnrctl start listener_${DB_NAME} >> ${LOGFILE}

${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE} 2>&1
alter system set local_listener=listener_${DB_NAME};
alter system register;
EOSQL
echo "" >> ${LOGFILE}
fi


#####
# set new datafile size
#####
echo "###[STEP]### resize datafiles..." | tee -a ${LOGFILE}
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE} 2>&1
--Adjusting Tablespace cdbroot
CREATE OR REPLACE PROCEDURE tbs_c(c_tbs out SYS_REFCURSOR)
AS
begin
  for crec_sys in
(SELECT a.TABLESPACE_NAME, b.TS#, a.FILE_ID, a.FILE_NAME from V\$TABLESPACE b,
(SELECT TABLESPACE_NAME, FILE_ID, FILE_NAME, CON_ID from CDB_DATA_FILES UNION SELECT TABLESPACE_NAME,FILE_ID, FILE_NAME, CON_ID from CDB_TEMP_FILES) a
where b.NAME=a.TABLESPACE_NAME and b.CON_ID=(SELECT CON_NAME_TO_ID('CDB\$ROOT') FROM DUAL) AND a.CON_ID=b.CON_ID)loop
      IF crec_sys.TABLESPACE_NAME like 'SYS%%' THEN  execute immediate 'alter database datafile '||crec_sys.FILE_ID||' resize 5G';
      ELSIF crec_sys.TABLESPACE_NAME like 'UNDO%%' THEN execute immediate 'alter database datafile '||crec_sys.FILE_ID||' resize 3G';
      ELSIF crec_sys.TABLESPACE_NAME like 'TEM%%' THEN execute immediate 'alter database tempfile '||crec_sys.FILE_ID||' resize 3G';
      END IF;
      end loop;
end;
/
VAR TBS1 REFCURSOR;
EXEC SYS.TBS_C( :TBS1);
Drop procedure SYS.TBS_C;
alter session set container = PDB\$SEED;
alter session set "_oracle_script"=TRUE;
alter pluggable database PDB\$SEED CLOSE IMMEDIATE instances=all;
alter pluggable database PDB\$SEED open instances=all;
--Adjusting tablespaces pdbseed
CREATE OR REPLACE PROCEDURE tbs_p(p_tbs out SYS_REFCURSOR)
AS
begin
  for prec_sys in
(SELECT a.TABLESPACE_NAME, b.TS#, a.FILE_ID, a.FILE_NAME from V\$TABLESPACE b,
(SELECT TABLESPACE_NAME, FILE_ID, FILE_NAME, CON_ID from CDB_DATA_FILES UNION SELECT TABLESPACE_NAME,FILE_ID, FILE_NAME, CON_ID from CDB_TEMP_FILES) a
where b.NAME=a.TABLESPACE_NAME and b.CON_ID=(SELECT CON_NAME_TO_ID('PDB\$SEED') FROM DUAL) AND a.CON_ID=b.CON_ID)loop
      IF prec_sys.TABLESPACE_NAME like 'SYS%%' THEN  execute immediate 'alter database datafile '||prec_sys.FILE_ID||' resize 5G';
      ELSIF prec_sys.TABLESPACE_NAME like 'UNDO%%' THEN execute immediate 'alter database datafile '||prec_sys.FILE_ID||' resize 3G';
      ELSIF prec_sys.TABLESPACE_NAME like 'TEM%%' THEN execute immediate 'alter database tempfile '||prec_sys.FILE_ID||' resize 3G';
      END IF;
      end loop;
   end;
/
VAR TBS2 REFCURSOR;
EXEC SYS.TBS_P( :TBS2);
Drop procedure SYS.TBS_P;
alter session set container = CDB\$ROOT;
alter session set "_oracle_script"=FALSE;
alter pluggable database PDB\$SEED CLOSE IMMEDIATE instances=all;
alter pluggable database PDB\$SEED OPEN read only instances=all;
EOSQL
#echo "" >> ${LOGFILE}


#####
# enable DB-Vault
#####
echo "###[STEP]### enable DB-Vault... " | tee -a ${LOGFILE}
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE} 2>&1
CREATE USER C##BA_DVOWNER IDENTIFIED BY ${OWNER_PW};
CREATE USER C##BA_DVACCOUNT IDENTIFIED BY ${ACCOUNT_PW};
grant create session, SET CONTAINER to C##BA_DVOWNER container=all;
grant create session, SET CONTAINER to C##BA_DVACCOUNT container=all;
execute dvsys.configure_dv('C##BA_DVOWNER', 'C##BA_DVACCOUNT');
connect C##BA_DVOWNER/${OWNER_PW}
execute dvsys.dbms_macadm.enable_dv();
connect / as sysdba
create role C##DP_USER;
grant dba, become user, exp_full_database, imp_full_database, create any directory, drop any directory to C##DP_USER container=all;
grant BECOME USER,CREATE ANY JOB,CREATE EXTERNAL JOB,DEQUEUE ANY QUEUE,ENQUEUE ANY QUEUE,EXECUTE ANY CLASS,EXECUTE ANY PROGRAM,MANAGE ANY QUEUE,MANAGE SCHEDULER,SELECT ANY TRANSACTION to C##DP_USER container=all;
grant "C##DP_USER" to system container=all;
alter system set compatible = '19.5.0.0.0' scope=spfile;
EOSQL

if [[ $RAC -eq 0 ]];then
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE} 2>&1
shutdown immediate;
startup;
EOSQL
else
${ORACLE_HOME}/bin/srvctl stop database -d ${DB_NAME} -o immediate >> ${LOGFILE} 2>&1
${ORACLE_HOME}/bin/srvctl start database -d ${DB_NAME} >> ${LOGFILE} 2>&1
fi
echo "" >> ${LOGFILE}


#####
# creating dba's, dv_acctmgr & dv_owner
#####
echo "###[STEP]### create dba accounts... " | tee -a ${LOGFILE}
for i in $(cat ${WORK_DIR}/resources/post_scripts/user.lst | grep -v ^# | cut -d: -f3)
do
$ORACLE_HOME/bin/sqlplus -L -S C##BA_DVACCOUNT/${ACCOUNT_PW} <<EOSQL >> ${LOGFILE} 2>&1
--drop user C##$i;
create user C##$i identified by Oracle_1234 account unlock default tablespace users profile C##BA_USER;
grant connect to C##$i container=all;
connect / as sysdba
grant resource to C##$i container=all;
grant unlimited tablespace to C##$i container=all;
grant dba, sysdba,set container to C##$i container=all;
EOSQL
done


echo "###[STEP]### manage vault accounts..." | tee -a ${LOGFILE}
# make DV_OWNER, DV_ACCOUNT & Basis DBA work
for i in $(cat ${WORK_DIR}/resources/post_scripts/user.lst | grep -v ^# | grep -v extern)
do
ROLE=$(echo $i | cut -d: -f2)
NAME=$(echo $i | cut -d: -f3)

case ${ROLE} in
DV_OWNER)
if [[ ${ROLE} = 'DV_OWNER' ]];then
$ORACLE_HOME/bin/sqlplus -L -S 'C##BA_DVOWNER'/${OWNER_PW} <<EOSQL >>$LOGFILE 2>&1
grant dv_owner to C##${NAME} container=all;
connect / as sysdba
grant SELECT_CATALOG_ROLE to C##${NAME} container=all;
revoke dba,sysdba from C##${NAME} container=all;
EOSQL
fi
;;

DV_ACCOUNT)
if [[ ${ROLE} = 'DV_ACCOUNT' ]];then
$ORACLE_HOME/bin/sqlplus -L -S 'C##BA_DVOWNER'/${OWNER_PW} <<EOSQL >>$LOGFILE 2>&1
grant dv_admin to C##${NAME} container=all;
connect C##BA_DVACCOUNT/${ACCOUNT_PW}
grant dv_acctmgr to C##${NAME} container=all;
connect / as sysdba
grant SELECT_CATALOG_ROLE to C##${NAME} container=all;
revoke dba,sysdba from C##${NAME} container=all;
EOSQL
fi
;;
esac
done
echo "" >> ${LOGFILE}

unset -v OWNER_PW
unset -v ACCOUNT_PW

#####
#cleanup invalid objects
#####
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE} 2>&1
@${ORACLE_HOME}/rdbms/admin/utlrp.sql
EOSQL

#####
# cleanup
#####
[[ -f init_tmp_${DB_NAME}.ora ]] && rm init_tmp_${DB_NAME}.ora
[[ -f init${DB_NAME}.ora ]] && rm init${DB_NAME}.ora
[[ -f ctl_${DB_NAME}.ctl ]] && rm ctl_${DB_NAME}.ctl

else
echo "ERROR-99: installation aborted by user"
fi
FINISH=$(date +%s)
TEMP=$(( (${FINISH} - ${START})/60 ))

echo "" | tee -a ${LOGFILE}
echo "install duration: ${TEMP} min." | tee -a ${LOGFILE}
echo "" | tee -a ${LOGFILE}
