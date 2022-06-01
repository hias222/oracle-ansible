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

#####
# env
#####
export ORACLE_HOME=/orasw/oracle/product/db19
export ORACLE_BASE=/orasw/oracle
export PERL5LIB=${ORACLE_HOME}/rdbms/admin:$PERL5LIB
export PATH=${ORACLE_HOME}/bin:${ORACLE_HOME}/perl/bin:$PATH
export NLS_LANG=GERMAN_GERMANY.AL32UTF8

START=$(date +%s)
DB_NAME=$1
DB_NAME_UPPER=$(echo "${DB_NAME}" | tr a-z A-Z)
RAC=0 && RAC=$(ps -ef | grep -i "ocssd.bin" | grep -v grep | wc -l)
DB_UNIQUE_NAME=${DB_NAME}
WORK_DIR=$(pwd)
TNSNAMES_ORA=${ORACLE_HOME}/network/admin/tnsnames.ora
LISTENER_ORA=${ORACLE_HOME}/network/admin/listener.ora
ORATAB=/etc/oratab
ORAPWFILE=/orasw/oracle/BA/adm/etc/ora_pwfile
ALIAS=/home/oracle/.alias

if [[ -f ${WORK_DIR}/resources/.dbvpw.enc ]];then
  export $(openssl enc -aes-256-cbc -d -in ${WORK_DIR}/resources/.dbvpw.enc -k DBVAULT2020)
else
  echo "${WORK_DIR}/resources/.dbvpw.enc not found, please check." 
  exit 1
fi
export PATH=${ORACLE_HOME}:${PATH}


#####
# getting sys/system password
#####
read -p "enter sys/system password[[ (return) = default (Oracle123)]]: " SYS_PW
[[ -z ${SYS_PW} ]] && SYS_PW=Oracle123

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
  if [[ $(uname -n) = l9693022 ]] || [[ $(nslookup $(uname -n) | grep ^Name: | awk '{ print $2 }' | cut -d'.' -f 2) = 'idst' ]];then
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


#####
# creating response file
#####
#source config.cfg
. config.cfg

echo "#created by db-creator
#-------------------------------------------------------------------------------
# Do not change the following system generated value.
#-------------------------------------------------------------------------------
responseFileVersion=/oracle/assistants/rspfmt_dbca_response_schema_v12.2.0
gdbName=${DB_NAME}
createAsContainerDatabase=TRUE				
useLocalUndoForPDBs=TRUE
sysPassword=${SYS_PW}
systemPassword=${SYS_PW}
dbsnmpPassword=Casper001
dvConfiguration=FALSE
olsConfiguration=TRUE
characterSet=${CHARSET}
nationalCharacterSet=${NCHARSET}
variables=DB_NAME=${DB_NAME},ORACLE_BASE=${ORACLE_BASE},ORACLE_HOME=${ORACLE_HOME}
" | grep -v ^$ > ${DB_NAME}.rsp

if [[ $RAC -eq 0 ]];then
TEMPLATE_FILE=tec4_single.dbt
echo "
databaseConfigType=SI
storageType=FS
templateName=tec4_single.dbt
datafileDestination=${ORACLE_BASE}/oradata/
initParams=db_block_size=${DB_BLOCK_SIZE},max_dump_file_size=100M
listeners=listener_${DB_NAME}
" | grep -v ^$ >> ${DB_NAME}.rsp
else
TEMPLATE_FILE=tec4_rac.dbt
echo "
databaseConfigType=SI
sid=${DB_NAME}${HOST_NUM}
storageType=ASM						
templateName=tec4_rac.dbt
datafileDestination=+DG1
recoveryAreaDestination=+DG3
asmsnmpPassword=Casper001
initParams=service_names=${DB_NAME},max_dump_file_size=100M,db_block_size=${DB_BLOCK_SIZE}
" | grep -v ^$ >> ${DB_NAME}.rsp
fi
cp ${TEMPLATE_FILE} $ORACLE_HOME/assistants/dbca/templates/

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

#Server 2
{
cat <<EOF
ENTRY="${ENTRY}"
DB_NAME="${DB_NAME}"
TNSNAMES_ORA="${TNSNAMES_ORA}"
EOF

cat <<-"EOF"
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

EOF
} | ssh oracle@${HOST2} /bin/bash
ENTRY=''
echo "" >> ${LOGFILE}
fi


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
echo "$(uname -n): OK" | tee -a ${LOGFILE}
else
echo "$(uname -n): SKIP - Entry already exists" | tee -a ${LOGFILE}
fi

if [[ $RAC -eq 0 ]];then
ENTRY=''
else
#Server 2
{
cat <<EOF
ENTRY="${ENTRY}"
DB_NAME="${DB_NAME}"
ORAPWFILE="${ORAPWFILE}"
EOF

cat <<-"EOF"
if [[ ! -f ${ORAPWFILE} ]];then
touch ${ORAPWFILE}
fi

grep -i  "${DB_NAME}[: $=]" ${ORAPWFILE} >/dev/null
RC=$?
if [[ $RC != 0 ]];then
echo "${ENTRY}" >> ${ORAPWFILE}
echo "$(uname -n): OK" | tee -a ${LOGFILE}
else
echo "$(uname -n): SKIP - Entry already exists" | tee -a ${LOGFILE}
fi

EOF
} | ssh oracle@${HOST2} /bin/bash
ENTRY=''
fi
echo "" >> ${LOGFILE}


#####
# start listener & register
#####
if [[ $RAC -eq 0 ]];then
echo "###[STEP]### starting listener & register database..." | tee -a ${LOGFILE}
${ORACLE_HOME}/bin/lsnrctl start listener_${DB_NAME} >> ${LOGFILE}
echo "" >> ${LOGFILE}
fi

#####
# run dbca to create db
#####
#check /etc/oratab - if entry with DB_NAME exists -> delete it otherwise the dbca fails
if [[ $(grep -E "^${DB_NAME}:" ${ORATAB} | wc -l) -gt 0 ]];then
 sudo sed -i -e "/^${DB_NAME}:/d" ${ORATAB} >> ${LOGFILE} 2>&1
 ssh ${HOST2} "sudo sed -i -e "/^${DB_NAME}:/d" /etc/oratab" >> ${LOGFILE} 2>&1
fi
echo "###[STEP]### DB creation with DBCA silent mode..." | tee -a ${LOGFILE}
${ORACLE_HOME}/bin/dbca -silent -createDatabase -ignorePreReqs -responseFile ${DB_NAME}.rsp >> ${LOGFILE}

if [[ $? -ne 0 ]];then
 echo "ERROR - DBCA failed."
 exit 1
fi
echo "" >> ${LOGFILE}

export NLS_LANG=AMERICAN_AMERICA.AL32UTF8

#####
# enable RAC
#####
if [[ $RAC -ge 1 ]];then
echo "###[STEP]### enabling RAC" | tee -a ${LOGFILE}
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE} 2>&1
ALTER DATABASE ADD LOGFILE THREAD 2
GROUP 11 size 512M,
GROUP 12 size 512M,
GROUP 13 size 512M;
CREATE UNDO TABLESPACE undotbs2 DATAFILE SIZE 3G;
alter system set service_names='${DB_NAME}';
alter system set remote_listener='${CLUSTER_NAME}.${DOMAIN}:57575' scope=both sid='*';
alter system set cluster_database=true scope=spfile sid='*';
alter system set instance_number=1 scope=spfile sid='${DB_NAME}${HOST_NUM}';
alter system set instance_number=2 scope=spfile sid='${DB_NAME}${HOST2_NUM}';
alter system set thread=1 scope=spfile sid='${DB_NAME}${HOST_NUM}';
alter system set thread=2 scope=spfile sid='${DB_NAME}${HOST2_NUM}';
alter system set undo_tablespace='undotbs1' scope=spfile sid='${DB_NAME}${HOST_NUM}';
alter system set undo_tablespace='undotbs2' scope=spfile sid='${DB_NAME}${HOST2_NUM}';
--alter system set cluster_database_instances=2 scope=spfile sid='*';
alter system set instance_name='${DB_NAME}${HOST_NUM}' scope=spfile sid='${DB_NAME}${HOST_NUM}';
alter system set instance_name='${DB_NAME}${HOST2_NUM}' scope=spfile sid='${DB_NAME}${HOST2_NUM}';
alter system set local_listener='(ADDRESS=(PROTOCOL=TCP)(HOST=${HOST}-vip.${DOMAIN})(PORT=57575))' scope=spfile sid='${DB_NAME}${HOST_NUM}';
alter system set local_listener='(ADDRESS=(PROTOCOL=TCP)(HOST=${HOST2}-vip.${DOMAIN})(PORT=57575))' scope=spfile sid='${DB_NAME}${HOST2_NUM}';
ALTER DATABASE ENABLE PUBLIC THREAD 2;
EXECUTE dbms_registry.loading('RAC','Oracle Real Application Clusters','dbms_clustdb.validate');
BEGIN
  dbms_registry.loaded('RAC');
  dbms_clustdb.validate;
END;
/
select comp_id, status from dba_registry;
ALTER DATABASE ENABLE BLOCK CHANGE TRACKING;
EOSQL
${ORACLE_HOME}/bin/srvctl stop database -d ${DB_NAME} -o abort >> ${LOGFILE} 2>&1
${ORACLE_HOME}/bin/srvctl start database -d ${DB_NAME} >> ${LOGFILE} 2>&1
echo "" >> ${LOGFILE}
fi


#####
# create crs ressources & pw File
#####
if [[ $RAC -ge 1 ]];then
SPFILE_ORIG=$(srvctl config database -d ${DB_NAME} | grep "Spfile: " | awk -F'/' '{ print $NF }')
OLD_HOME=${ORACLE_HOME}
export ORACLE_HOME=${CRS_HOME}
${ORACLE_HOME}/bin/asmcmd mkalias +DG1/${DB_UNIQUE_NAME}/PARAMETERFILE/${SPFILE_ORIG} +DG1/${DB_UNIQUE_NAME}/spfile${DB_NAME}

export ORACLE_HOME=${OLD_HOME}

echo "###[STEP]### create crs ressources & pw File" | tee -a ${LOGFILE}
${ORACLE_HOME}/bin/srvctl stop database -db ${DB_NAME} -o abort >> ${LOGFILE} 2>&1
${ORACLE_HOME}/bin/srvctl remove database -db ${DB_NAME} -f
${ORACLE_HOME}/bin/srvctl add database -db ${DB_NAME} -o ${ORACLE_HOME} -spfile +DG1/${DB_UNIQUE_NAME}/spfile${DB_NAME} >> ${LOGFILE} 2>&1
${ORACLE_HOME}/bin/srvctl add instance -db ${DB_NAME} -instance ${DB_NAME}${HOST_NUM} -node ${HOST} >> ${LOGFILE} 2>&1
${ORACLE_HOME}/bin/srvctl add instance -db ${DB_NAME} -instance ${DB_NAME}${HOST2_NUM} -node ${HOST2} >> ${LOGFILE} 2>&1
${ORACLE_HOME}/bin/orapwd file="+DG1/${DB_UNIQUE_NAME}/pwd${DB_NAME}" format=12 password=${SYS_PW} entries=50 dbuniquename=${DB_UNIQUE_NAME} >> ${LOGFILE} 2>&1
${ORACLE_HOME}/bin/srvctl stop database -db ${DB_NAME} -o abort >> ${LOGFILE} 2>&1
${ORACLE_HOME}/bin/srvctl start database -db ${DB_NAME} >> ${LOGFILE} 2>&1
fi


#####
# some BA custom post actions
#####
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE} 2>&1
alter system set "_exclude_seed_cdb_view"=FALSE scope=spfile;
alter system set "_gby_hash_aggregation_enabled"=false scope=spfile;
alter system set "_use_single_log_writer"=true scope=spfile;
alter system set "_optimizer_aggr_groupby_elim"=false scope=spfile;
alter system set "_cursor_obsolete_threshold"=1024 scope=spfile;
alter system set "processes"=400 scope=spfile;
alter system set awr_pdb_autoflush_enabled=true scope=spfile;
alter system set awr_snapshot_time_offset=1000000 scope=spfile;
execute dbms_workload_repository.modify_snapshot_settings(interval => 60, retention => 11520);
execute dbms_workload_repository.create_snapshot();
--disable autotasks
EXEC DBMS_AUTO_TASK_ADMIN.DISABLE(client_name=>'sql tuning advisor', operation=>NULL, window_name=>NULL);
EXEC DBMS_AUTO_TASK_ADMIN.DISABLE(client_name=>'auto space advisor', operation=>NULL, window_name=>NULL);
commit;
EOSQL

if [[ $RAC -ge 1 ]];then
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE} 2>&1
alter system set "_backup_file_bufcnt"=8 scope=spfile;
alter system set "_backup_file_bufsz"=16777216 scope=spfile;
alter system set "_gby_hash_aggregation_enabled"=false scope=spfile;
alter system set "processes"=400 scope=spfile;
alter system set awr_pdb_autoflush_enabled=true scope=spfile;
alter system set awr_snapshot_time_offset=1000000 scope=spfile;
execute dbms_workload_repository.modify_snapshot_settings(interval => 60, retention => 11520);
execute dbms_workload_repository.create_snapshot();
--disable autotasks
EXEC DBMS_AUTO_TASK_ADMIN.DISABLE(client_name=>'sql tuning advisor', operation=>NULL, window_name=>NULL);
EXEC DBMS_AUTO_TASK_ADMIN.DISABLE(client_name=>'auto space advisor', operation=>NULL, window_name=>NULL);
commit;
create pfile='${ORACLE_HOME}/dbs/init${DB_NAME}.ora' from spfile;
EOSQL
fi

####
#postskripts
####
for i in $(ls ${WORK_DIR}/sql_scripts)
do
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE} 2>&1
@${WORK_DIR}/sql_scripts/$i
EOSQL
done


#####
# enable DB-Vault
#####
#echo "###[STEP]### enable DB-Vault... " | tee -a ${LOGFILE}
#${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE} 2>&1
#CREATE USER C##BA_DVOWNER IDENTIFIED BY ${OWNER_PW};
#CREATE USER C##BA_DVACCOUNT IDENTIFIED BY ${ACCOUNT_PW};
#grant create session, SET CONTAINER to C##BA_DVOWNER container=all;
#grant create session, SET CONTAINER to C##BA_DVACCOUNT container=all;
#execute dvsys.configure_dv('C##BA_DVOWNER', 'C##BA_DVACCOUNT');
#connect C##BA_DVOWNER/${OWNER_PW}
#execute dvsys.dbms_macadm.enable_dv();
#connect / as sysdba
#create role C##DP_USER;
#grant dba, become user, exp_full_database, imp_full_database, create any directory, drop any directory to C##DP_USER container=all;
#grant BECOME USER,CREATE ANY JOB,CREATE EXTERNAL JOB,DEQUEUE ANY QUEUE,ENQUEUE ANY QUEUE,EXECUTE ANY CLASS,EXECUTE ANY PROGRAM,MANAGE ANY QUEUE,MANAGE SCHEDULER,SELECT ANY TRANSACTION to C##DP_USER container=all;
#grant "C##DP_USER" to system container=all;
#alter system set compatible = '19.5.0.0.0' scope=spfile;
#EOSQL

#if [[ $RAC -eq 0 ]];then
#${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE} 2>&1
#shutdown immediate;
#startup;
#EOSQL
#else
#${ORACLE_HOME}/bin/srvctl stop database -d ${DB_NAME} -o immediate >> ${LOGFILE} 2>&1
#${ORACLE_HOME}/bin/srvctl start database -d ${DB_NAME} >> ${LOGFILE} 2>&1
#fi
#echo "" >> ${LOGFILE}


#####
# creating dba's, dv_acctmgr & dv_owner
#####
#echo "###[STEP]### create dba accounts... " | tee -a ${LOGFILE}
#for i in $(cat ${WORK_DIR}/user.lst | grep -v ^# | cut -d: -f3)
#do
#$ORACLE_HOME/bin/sqlplus -L -S C##BA_DVACCOUNT/${ACCOUNT_PW} <<EOSQL >> ${LOGFILE} 2>&1
#--drop user C##$i;
#create user C##$i identified by Oracle_1234 account unlock default tablespace users profile C##BA_USER;
#grant connect to C##$i container=all;
#connect / as sysdba
#grant resource to C##$i container=all;
#grant unlimited tablespace to C##$i container=all;
#grant dba, sysdba,set container to C##$i container=all;
#EOSQL
#done


#echo "###[STEP]### manage vault accounts..." | tee -a ${LOGFILE}
# make DV_OWNER, DV_ACCOUNT & Basis DBA work
#for i in $(cat ${WORK_DIR}/user.lst | grep -v ^# | grep -v extern)
#do
#ROLE=$(echo $i | cut -d: -f2)
#NAME=$(echo $i | cut -d: -f3)

#case ${ROLE} in
#DV_OWNER)
#if [[ ${ROLE} = 'DV_OWNER' ]];then
#$ORACLE_HOME/bin/sqlplus -L -S 'C##BA_DVOWNER'/${OWNER_PW} <<EOSQL >>$LOGFILE 2>&1
#grant dv_owner to C##${NAME} container=all;
#connect / as sysdba
#grant SELECT_CATALOG_ROLE to C##${NAME} container=all;
#revoke dba,sysdba from C##${NAME} container=all;
#EOSQL
#fi
#;;

#DV_ACCOUNT)
#if [[ ${ROLE} = 'DV_ACCOUNT' ]];then
#$ORACLE_HOME/bin/sqlplus -L -S 'C##BA_DVOWNER'/${OWNER_PW} <<EOSQL >>$LOGFILE 2>&1
#grant dv_admin to C##${NAME} container=all;
#connect C##BA_DVACCOUNT/${ACCOUNT_PW}
#grant dv_acctmgr to C##${NAME} container=all;
#connect / as sysdba
#grant SELECT_CATALOG_ROLE to C##${NAME} container=all;
#revoke dba,sysdba from C##${NAME} container=all;
#EOSQL
#fi
#;;
#esac
#done
#echo "" >> ${LOGFILE}

#unset -v OWNER_PW
#unset -v ACCOUNT_PW

####
#set new datafile size/adjusting tablespaces pdbseed
####
echo "###[STEP]### resize datafiles..." | tee -a ${LOGFILE}
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE} 2>&1
alter session set container = PDB\$SEED;
alter session set "_oracle_script"=TRUE;
alter pluggable database PDB\$SEED CLOSE IMMEDIATE instances=all;
alter pluggable database PDB\$SEED open instances=all;
create tablespace USERS DATAFILE SIZE 500M;
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
echo "" >> ${LOGFILE}

#####
# execute Datapatch
#####
echo "###[STEP]### executing datapatch... " | tee -a ${LOGFILE}
${ORACLE_HOME}/OPatch/datapatch -skip_upgrade_check >> ${LOGFILE} 2>&1

#####
#cleanup invalid objects
#####
${ORACLE_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE} 2>&1
@${ORACLE_HOME}/rdbms/admin/utlrp.sql
column comp_name format a40
select comp_name,version,status from dba_registry;
EOSQL

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
echo "$(uname -n): OK" | tee -a ${LOGFILE}
else
echo "$(uname -n): SKIP - Entry already exists" | tee -a ${LOGFILE}
fi

if [[ $RAC -eq 0 ]];then
ENTRY=''
else
#Server 2
{
cat <<EOF
ENTRY="${ENTRY}"
DB_NAME="${DB_NAME}"
ORATAB="${ORATAB}"
EOF

cat <<-"EOF"
if [[ ! -f ${ORATAB} ]];then
touch ${ORATAB}
fi

grep -i  "${DB_NAME}[: $=]" ${ORATAB} >/dev/null
RC=$?
if [[ $RC != 0 ]];then
echo "${ENTRY}" >> ${ORATAB}
echo "$(uname -n): OK" | tee -a ${LOGFILE}
else
echo "$(uname -n): SKIP - Entry already exists" | tee -a ${LOGFILE}
fi

EOF
} | ssh oracle@${HOST2} /bin/bash
ENTRY=''
fi
echo "" >> ${LOGFILE}

#####
# cleanup
#####
[[ -f ${DB_NAME}.rsp ]] && rm ${DB_NAME}.rsp
[[ -f ${ORACLE_HOME}/assistants/dbca/templates/${TEMPLATE_FILE} ]] && rm ${ORACLE_HOME}/assistants/dbca/templates/${TEMPLATE_FILE}

if [[ $RAC -ge 1 ]];then
 [[ -f ${ORACLE_HOME}/dbs/orapw${DB_NAME} ]] && rm ${ORACLE_HOME}/dbs/orapw${DB_NAME}
 ln -sr ${ORACLE_HOME}/dbs/init${DB_NAME}.ora ${ORACLE_HOME}/dbs/init${DB_NAME}1.ora
 ln -sr ${ORACLE_HOME}/dbs/init${DB_NAME}.ora ${ORACLE_HOME}/dbs/init${DB_NAME}2.ora
 scp -p ${ORACLE_HOME}/dbs/init${DB_NAME}.ora ${HOST2}:${ORACLE_HOME}/dbs/
 ssh ${HOST2} "ln -sr ${ORACLE_HOME}/dbs/init${DB_NAME}.ora ${ORACLE_HOME}/dbs/init${DB_NAME}1.ora"
 ssh ${HOST2} "ln -sr ${ORACLE_HOME}/dbs/init${DB_NAME}.ora ${ORACLE_HOME}/dbs/init${DB_NAME}2.ora"
fi

else
echo "ERROR-99: installation aborted by user"
fi
FINISH=$(date +%s)
TEMP=$(( (${FINISH} - ${START})/60 ))

echo "" | tee -a ${LOGFILE}
echo "install duration: ${TEMP} min." | tee -a ${LOGFILE}
echo "" | tee -a ${LOGFILE}
