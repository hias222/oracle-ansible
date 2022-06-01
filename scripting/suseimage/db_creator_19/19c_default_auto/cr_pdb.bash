#!/bin/bash

VERSION=1.0-2-nodes

# Changed for EXa
# MFU 17.11.2020 initial version

echo "--------------------"
echo $VERSION
echo "--------------------"


####
# check input and usage func
####
fct_usage()
{
echo -e "
cr_pdb.bash <CDB_NAME> <PDB_NAME>

Usage:
\t<CDB_NAME> = name of the existing cdb
\t<PDB_NAME> = name of new pdb
"
}

if [[ $# != 2 ]];then
 fct_usage
 exit 1
fi

CDB_NAME=$1
PDB_NAME=$2

if [[ $(grep -E "^${CDB_NAME}[0-9]*:" /etc/oratab | wc -l) -eq 0 ]];then
 echo "
no cdb ${CDB_NAME} found in /etc/oratab
"
 fct_usage
 exit 1
fi

# Exadata specific
EXA_CLUSTER_NAME=m8308022
EXA_SCAN_PORT=57577
EXA_LOCAL_LISTENER_PORT=57575


DISK_GROUP_DATA=+${EXA_CLUSTER_NAME^^}_DATA
DISK_GROUP_RECO=+${EXA_CLUSTER_NAME^^}_RECO

####
# set env
####
RAC=0
RAC=$(ps -ef | grep -i "ocssd.bin" | grep -v grep | wc -l)
WORK_DIR=$(pwd)
SCHUL_HOST='l9693022'

export ORACLE_HOME=$(grep -E "^${CDB_NAME}:" /etc/oratab | cut -d: -f2 | uniq)
export ORACLE_BASE=/u01/app/oracle
export PERL5LIB=${ORACLE_HOME}/rdbms/admin:$PERL5LIB
export PATH=${ORACLE_HOME}/bin:${ORACLE_HOME}/perl/bin:$PATH
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
export PATH=${ORACLE_HOME}:${PATH}

TNSNAMES_ORA=${ORACLE_HOME}/network/admin/tnsnames.ora
LISTENER_ORA=${ORACLE_HOME}/network/admin/listener.ora
ORATAB=/etc/oratab
ORAPWFILE=/u01/app/oracle/BA/adm/etc/ora_pwfile
mkdir -p ${ORACLE_BASE}/admin/${CDB_NAME}/log
LOGFILE=${ORACLE_BASE}/admin/${CDB_NAME}/log/$(echo "install_pdb_${PDB_NAME}_$(date '+Y%YM%mD%d_H%HM%MS%S').log")
log_dir=${ORACLE_BASE}/admin/${CDB_NAME}/log

if [[ $RAC -eq 0 ]];then
 export ORACLE_SID=${CDB_NAME}
  #l9693022 & idst Databases get db adress hostname
 if [[ $(uname -n) = ${SCHUL_HOST} ]] || [[ $(nslookup $(uname -n) | grep ^Name: | awk '{ print $2 }' | cut -d'.' -f 2) = 'idst' ]];then
  HOST=$(echo "$(uname -n)db.$(nslookup $(uname -n) | grep ^Name: | awk '{ print $2 }' | cut -d'.' -f 2-)")
 else
  HOST=$(nslookup $(uname -n) | grep ^Name: | awk -F' ' '{ print $2 }')
 fi 
 PORT=$(${ORACLE_HOME}/bin/lsnrctl status listener_${CDB_NAME} | head | grep PORT | awk -F'=' '{ print $6 }' | cut -d')' -f1)
else
 export CRS_HOME=$(cat ${ORATAB} | grep -v ^# | grep -v ^$ | grep -E "^[+|-]" | cut -d":" -f2 | sort | uniq)
 HOST_FQDN=$(uname -n)
 HOST=`echo ${HOST_FQDN}|cut -d'.' -f1`
 HOST2=$(${CRS_HOME}/bin/olsnodes | grep -v ${HOST})
 HOST_NUM=$(${CRS_HOME}/bin/olsnodes -n | grep  ${HOST} | awk -F' ' '{ print $2 }')
 HOST2_NUM=$(${CRS_HOME}/bin/olsnodes -n | grep -v ${HOST} | awk -F' ' '{ print $2 }')
 export ORACLE_SID=${CDB_NAME}${HOST_NUM}
 DOMAIN=$(nslookup $(uname -n) | grep ^Name: | awk -F' ' '{ print $2 }' | cut -d"." -f2-)
 # CLUSTER_NAME=$(${CRS_HOME}/bin/olsnodes -c)
 CLUSTER_NAME=${EXA_CLUSTER_NAME}-scan
fi


if [[ $RAC -eq 0 ]];then
 echo "Starting PDB-Single installation with:" | tee -a ${LOGFILE}
else
 echo "Starting PDB-RAC installation with:" | tee -a ${LOGFILE}
fi
echo "" >> ${LOGFILE}

####
# check env & vars before starting
####
echo "
Container = ${CDB_NAME}
ORACLE_SID = ${ORACLE_SID}
PDB = ${PDB_NAME}
ORACLE_HOME=${ORACLE_HOME}
HOST = ${HOST}
CLUSTER_NAME = ${CLUSTER_NAME}
"

if [[ $RAC -eq 0 ]];then
 echo "PORT = ${PORT}"
fi

echo "Log_Dir=${ORACLE_BASE}/admin/${CDB_NAME}/log/
Main Log File: ${LOGFILE}
" | tee -a ${LOGFILE}

echo "is this correct? (y/n)?"
read answer
if [ "$answer" != "${answer#[Yy]}" ] ;then


####
# create pluggable database
####
echo "###[STEP]### creating Pluggable Database" | tee -a ${LOGFILE}
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE}
CREATE PLUGGABLE DATABASE ${PDB_NAME} ADMIN USER PDB_ADMIN IDENTIFIED BY PDB_ADMIN;
ALTER PLUGGABLE DATABASE ${PDB_NAME} OPEN instances=all;
alter session set container=${PDB_NAME};
drop user PDB_ADMIN cascade;
--disable autotasks
EXEC DBMS_AUTO_TASK_ADMIN.DISABLE(client_name=>'sql tuning advisor', operation=>NULL, window_name=>NULL);
EXEC DBMS_AUTO_TASK_ADMIN.DISABLE(client_name=>'auto space advisor', operation=>NULL, window_name=>NULL);
--Parameter fuer awr reports
execute dbms_workload_repository.modify_snapshot_settings(interval => 60, retention => 11520);
exec dbms_workload_repository.create_snapshot();
--default profile values
alter profile default limit failed_login_attempts unlimited;
alter profile default limit password_life_time unlimited;
alter profile default limit password_lock_time unlimited;
alter profile default limit password_grace_time unlimited;
ALTER PLUGGABLE DATABASE ${PDB_NAME} save state instances=all;
commit;
EOSQL

if [[ $RAC -gt 0 ]];then
####
# create pdb services
####
echo "###[STEP]### creating PDB services..." | tee -a ${LOGFILE}

#######################
## ToDO
# flexible number of hosts left and right

echo "${ORACLE_HOME}/bin/srvctl add service -d ${CDB_NAME} -pdb ${PDB_NAME} -s ${PDB_NAME}_1 -r ${CDB_NAME}${HOST_NUM} -a ${CDB_NAME}${HOST2_NUM}"
${ORACLE_HOME}/bin/srvctl add service -d ${CDB_NAME} -pdb ${PDB_NAME} -s ${PDB_NAME}_1 -r ${CDB_NAME}${HOST_NUM} -a ${CDB_NAME}${HOST2_NUM}
echo "${ORACLE_HOME}/bin/srvctl add service -d ${CDB_NAME} -pdb ${PDB_NAME} -s ${PDB_NAME}_2 -r ${CDB_NAME}${HOST2_NUM} -a ${CDB_NAME}${HOST_NUM}"
${ORACLE_HOME}/bin/srvctl add service -d ${CDB_NAME} -pdb ${PDB_NAME} -s ${PDB_NAME}_2 -r ${CDB_NAME}${HOST2_NUM} -a ${CDB_NAME}${HOST_NUM}

# removed 
# echo "${ORACLE_HOME}/bin/srvctl add service -d ${CDB_NAME} -pdb ${PDB_NAME} -s ${PDB_NAME}agl -preferred ${CDB_NAME}${HOST_NUM},${CDB_NAME}${HOST2_NUM}"
# ${ORACLE_HOME}/bin/srvctl add service -d ${CDB_NAME} -pdb ${PDB_NAME} -s ${PDB_NAME}agl -preferred "${CDB_NAME}${HOST_NUM},${CDB_NAME}${HOST2_NUM}"

${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE}
ALTER PLUGGABLE DATABASE ${PDB_NAME} close immediate instances=all;
ALTER PLUGGABLE DATABASE ${PDB_NAME} OPEN instances=all;
EOSQL

#######################
## ToDO
# flexible number of hosts - left and right


echo "${ORACLE_HOME}/bin/srvctl start service -d ${CDB_NAME} -s ${PDB_NAME}_1"
${ORACLE_HOME}/bin/srvctl start service -d ${CDB_NAME} -s ${PDB_NAME}_1
echo "${ORACLE_HOME}/bin/srvctl start service -d ${CDB_NAME} -s ${PDB_NAME}_2"
${ORACLE_HOME}/bin/srvctl start service -d ${CDB_NAME} -s ${PDB_NAME}_2

# removed
# echo "${ORACLE_HOME}/bin/srvctl start service -d ${CDB_NAME} -s ${PDB_NAME}agl"
# ${ORACLE_HOME}/bin/srvctl start service -d ${CDB_NAME} -s ${PDB_NAME}agl

${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE}
ALTER PLUGGABLE DATABASE ${PDB_NAME} SAVE STATE instances=all;
ALTER PLUGGABLE DATABASE ${PDB_NAME} close immediate instances=all;
ALTER PLUGGABLE DATABASE ${PDB_NAME} OPEN instances=all;
--Adjusting Tablespace
--alter session set container=${PDB_NAME};
--CREATE OR REPLACE PROCEDURE tbs_r(p_tbs out SYS_REFCURSOR)
--AS
--begin
-- for rec_sys in (
--select c.PDB_ID, c.PDB_NAME, a.TABLESPACE_NAME, b.TS#, a.FILE_ID, a.FILE_NAME from V\$TABLESPACE b,
--(SELECT TABLESPACE_NAME, FILE_ID, FILE_NAME, CON_ID from CDB_DATA_FILES UNION SELECT TABLESPACE_NAME,FILE_ID, FILE_NAME, CON_ID from CDB_TEMP_FILES) a, DBA_PDBS c
--where b.NAME=a.TABLESPACE_NAME AND c.PDB_NAME=(select sys_context('USERENV', 'CON_NAME') from dual)) loop
--      IF rec_sys.TABLESPACE_NAME like 'SYS%%' THEN  execute immediate 'alter database datafile '||rec_sys.FILE_ID||' resize 5G';
--      ELSIF rec_sys.TABLESPACE_NAME like 'UNDO%%' THEN execute immediate 'alter database datafile '||rec_sys.FILE_ID||' resize 3G';
--      ELSIF rec_sys.TABLESPACE_NAME like 'TEM%%' THEN execute immediate 'alter database tempfile '||rec_sys.FILE_ID||' resize 3G';
--      END IF;
--      end loop;
--   end;
--/
--VAR TBS REFCURSOR;
--EXEC SYS.TBS_R( :TBS);
--drop procedure SYS.TBS_R;
EOSQL
${ORACLE_HOME}/bin/srvctl status service -d ${CDB_NAME} -pdb ${PDB_NAME}
echo "" | tee -a ${LOGFILE}
fi

if [[ $RAC -eq 0 ]];then
####
# generate tnsnames.ora entry for single pdb
####
echo "###[STEP]### making tnsnames.ora Entry" | tee -a ${LOGFILE}
ENTRY=$(echo "#Eintrag fuer PDB ${PDB_NAME}, $(date '+%d.%m.%Y')
${PDB_NAME}=
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${HOST})(PORT = ${PORT}))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${PDB_NAME})
    )
  )
")

if [[ ! -f ${TNSNAMES_ORA} ]];then
touch ${TNSNAMES_ORA}
fi

grep -iE  "\<${PDB_NAME}\>[: $=]" ${TNSNAMES_ORA} >/dev/null
RC=$?
if [[ $RC != 0 ]];then
echo "${ENTRY}" >> ${TNSNAMES_ORA}
echo "$(uname -n): OK" | tee -a ${LOGFILE}
else
echo "$(uname -n): SKIP - Entry already exists" | tee -a ${LOGFILE}
fi
ENTRY=''
echo "" | tee -a ${LOGFILE}
else
####
# generate tnsnames.ora entry for rac pdb
####
echo "###[STEP]### making tnsnames.ora Entry" | tee -a ${LOGFILE}
ENTRY=$(echo "#Eintrag fuer Datenbank ${PDB_NAME}, $(date '+%d.%m.%Y')
${PDB_NAME}=
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${CLUSTER_NAME}.${DOMAIN})(PORT = ${EXA_SCAN_PORT} ))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${PDB_NAME})
    )
  )

${PDB_NAME}1=
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${CLUSTER_NAME}.${DOMAIN})(PORT = ${EXA_SCAN_PORT}))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${PDB_NAME}_1)
    )
  )

${PDB_NAME}2=
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${CLUSTER_NAME}.${DOMAIN})(PORT = ${EXA_SCAN_PORT}))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${PDB_NAME}_2)
    )
  )
")

#Server 1
if [[ ! -f ${TNSNAMES_ORA} ]];then
touch ${TNSNAMES_ORA}
fi

grep -i  "\<${PDB_NAME}\>[: $=]" ${TNSNAMES_ORA} >/dev/null
RC=$?
if [[ $RC != 0 ]];then
echo "${ENTRY}" >> ${TNSNAMES_ORA}
echo "$(uname -n): OK" | tee -a ${LOGFILE}
else
echo "$(uname -n): SKIP - Entry already exists" | tee -a ${LOGFILE}
fi

#Server 2
{
cat <<EOF
ENTRY="${ENTRY}"
PDB_NAME="${PDB_NAME}"
TNSNAMES_ORA="${TNSNAMES_ORA}"
EOF

cat <<-"EOF"
if [[ ! -f ${TNSNAMES_ORA} ]];then
touch ${TNSNAMES_ORA}
fi

grep -i  "$\<{PDB_NAME}\>[: $=]" ${TNSNAMES_ORA} >/dev/null
RC=$?
if [[ $RC != 0 ]];then
echo "${ENTRY}" >> ${TNSNAMES_ORA}
echo "$(uname -n): OK" | tee -a ${LOGFILE}
else
echo "$(uname -n): SKIP - Entry already exists" | tee -a ${LOGFILE}
fi

EOF
} | ssh oracle@${HOST2} /bin/bash
ENTRY=''
echo "" | tee -a ${LOGFILE}
fi


####
# execute Datapatch
####
echo "###[STEP]### executing Datapatch" | tee -a ${LOGFILE}
${ORACLE_HOME}/OPatch/datapatch -verbose -skip_upgrade_check -pdbs ${PDB_NAME}>> ${LOGFILE}
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE}
alter session set container=${PDB_NAME};
set lines 155
col description format a50
select PATCH_ID, STATUS, DESCRIPTION from dba_registry_sqlpatch;
EOSQL
echo "" | tee -a ${LOGFILE}


#####
# function cr_tbs
#####
function cr_tbs()
{
TBS_NAME=''
TBS_SIZE=''
while [[ -z ${TBS_NAME} ]]
do 
 read -p "enter tablespace name: " TBS_NAME
done
while [[ -z ${TBS_SIZE} ]]
do
 read -p "enter tablespace size in MB: " TBS_SIZE
done

${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL | tee -a ${LOGFILE}
alter session set container=${PDB_NAME};
create bigfile tablespace ${TBS_NAME} datafile SIZE ${TBS_SIZE}M;
commit;
EOSQL

BOOL_TBS=''
read -p "do you want to create another additional tablespaces?[(Y)/N]: " BOOL_TBS 
if [[ ${BOOL_TBS} =~ ^[y|Y]$ ]];then
 cr_tbs
fi
}


#####
# create user tbs
#####
BOOL_TBS=''
read -p "do you want to create any additional tablespaces?[(Y)/N]: " BOOL_TBS
if [[ ${BOOL_TBS} =~ ^[y|Y]$ ]];then
 cr_tbs
else
 echo "no additional tablespaces will be created."
fi 


else
echo "aborting database creation. Reason: User"
fi
