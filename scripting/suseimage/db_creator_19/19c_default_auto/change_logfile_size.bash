#!/bin/bash

# change size of logfile

# Changes

fct_usage()
{
echo -e "
$0 <DG_CONFIG>
Usage:
\t<DG_CONFIG> = filename
"
}

if [[ $# != 1 ]];then
 fct_usage
 exit 1
fi

### Config file

if test -f ${1} ; then
  echo "using config file ${1}" | tee -a ${LOGFILE}
  . ${1}
else
    echo "config file: ${1} not found " | tee -a ${LOGFILE}
    exit 1
fi


START=$(date +%s)
WORK_DIR=$(pwd)
SSH_CONECTIVITY=false
ORATAB=/etc/oratab
DB_HOST=$(uname -n)db
DB_HOST_IDENTIFIER=${DB_HOST:1:4}
DB_UNIQUE_NAME=${dgenv}d${DB_HOST_IDENTIFIER}${dgnumber}
SCRIPT_DIR=${WORK_DIR}/${DB_UNIQUE_NAME}
DB_NAME=${dbname}
DB_DOMAIN=$(nslookup $(uname -n) | grep ^Name: | awk -F' ' '{ print $2 }' | cut -d"." -f2-)
ORG_PATH=$PATH
DB_HOME=/orasw/oracle/product/db19
CRS_HOME=$(cat ${ORATAB} | grep -v ^# | grep -v ^$ | grep -E "^[+|-]" | cut -d":" -f2 | sort | uniq)
WALLET_DIRECTORY="/orasw/oracle/wallet"
SLEEP_TIMER=1

LISTENER_ORA=${DB_HOME}/network/admin/listener.ora
SQLNET_ORA=${DB_HOME}/network/admin/sqlnet.ora
TNSNAMES_ORA=${DB_HOME}/network/admin/tnsnames.ora

GI_LISTENER_ORA=${CRS_HOME}/network/admin/listener.ora
GI_TNSNAMES_ORA=${CRS_HOME}/network/admin/tnsnames.ora

## set homes

function setasm () {
    export ORACLE_SID=+ASM
    export ORACLE_HOME=$CRS_HOME
    export PATH=$ORG_PATH
    export PATH=${ORACLE_HOME}/bin:${ORACLE_HOME}/perl/bin:$PATH
    export PERL5LIB=${ORACLE_HOME}/rdbms/admin:$PERL5LIB
    export ORACLE_BASE=/orasw/oracle
    export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
}

function setdb () {
    export ORACLE_SID=${DB_UNIQUE_NAME} 
    export ORACLE_HOME=/orasw/oracle/product/db19
    export PATH=$ORG_PATH
    export PATH=${ORACLE_HOME}/bin:${ORACLE_HOME}/perl/bin:$PATH
    export PERL5LIB=${ORACLE_HOME}/rdbms/admin:$PERL5LIB
    export ORACLE_BASE=/orasw/oracle
    export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
}

function setdbInFile() {
    echo "export ORACLE_SID=${DB_UNIQUE_NAME}" >> $1
    echo "export ORACLE_HOME=/orasw/oracle/product/db19" >> $1
    echo "export PATH=$ORG_PATH" >> $1
    echo "export PATH=${ORACLE_HOME}/bin:${ORACLE_HOME}/perl/bin:$PATH" >> $1
    echo "export PERL5LIB=${ORACLE_HOME}/rdbms/admin:$PERL5LIB" >> $1
    echo "export ORACLE_BASE=/orasw/oracle" >> $1
    echo "export NLS_LANG=AMERICAN_AMERICA.AL32UTF8" >> $1
}

### validate parameter

if [[ -z ${dbname} ]]; then
  echo "missing parameter dbname in $1"
  exit 1
fi

if [[ -z ${activenode} ]]; then
  echo "missing parameter activenode in $1"
  exit 1
fi

if [[ -z ${dgnumber} ]]; then
  echo "missing parameter dgnumber in $1"
  exit 1
fi  

if [[ -z ${logfilesize} ]]; then
  echo "missing parameter logfilesize in $1"
  echo "# add logfilesize eg 20G or 1024M "
  echo "logfilesize=20G"
  echo "add in $1"
  exit 1
fi  

if [[ -z ${logfilenumber} ]]; then
  echo "missing parameter logfilesize in $1"
  echo "# add logfilenumber e.g. 3 "
  echo "logfilenumber=4"
  echo "add in $1"
  exit 1
fi

echo "DB Name          $DB_NAME"
echo "Active Node      $activenode"
echo "Host:            ${DB_HOST}.${DB_DOMAIN}"
echo "ORACLE_SID       ${DB_UNIQUE_NAME}"
echo "LOGFILESIZE      ${logfilesize}"
echo "Number logfil    ${logfilenumber}"
echo "DG HOSTS"

if [[ "${DB_HOST}" != "${activenode}" ]]; then
  echo "ERROR-98: run on active node - see config file"
  exit 1  
fi

FOUND_LOCAL_HOST=false

for readhosts in $(echo $dghosts | tr "," "\n")
do
  dghostname=$(echo $readhosts| awk -F  ":" '{print $1}')
  dghvip=$(echo $readhosts| awk -F  ":" '{print $2}')
  if [[ "${DB_HOST}" == "${dghostname}" ]]; then
    FOUND_LOCAL_HOST=true
  fi
  if [[ -z ${dghvip} ]]; then
    dghvip=${dghostname}
  fi
  echo "- $dghostname HVIP $dghvip"
done

if [[ "${FOUND_LOCAL_HOST}" == "false" ]]; then
  echo "missing local host config, please add local host ${DB_HOST} in dghosts in config "
  exit 1
fi

echo "is this correct? (y/n)?"
read answer
if [ "$answer" != "${answer#[Yy]}" ] ;then
echo ""
else
echo "ERROR-99: installation aborted by user"
exit 1
fi 

### Log Configuration

mkdir -p ${ORACLE_BASE}/admin/${DB_UNIQUE_NAME}/log
LOGFILE=${ORACLE_BASE}/admin/${DB_UNIQUE_NAME}/log/$(echo "change_log_${DB_UNIQUE_NAME}_$(date '+Y%YM%mD%d_H%HM%MS%S').log")
log_dir=${ORACLE_BASE}/admin/${DB_UNIQUE_NAME}/log

echo "Logfile: ${LOGFILE}" | tee -a ${LOGFILE}

### Folder configs
## Folder to store scripts
mkdir -p ${SCRIPT_DIR}

#### Backup Files

backup_file() {
  new_file=$(echo $1 | rev | cut -f 2- -d '.' | rev)
  cp $1 ${new_file}_$(date '+Y%YM%mD%d_H%HM%MS%S').save
  echo "Save: ${1}" | tee -a ${LOGFILE}
}

#####
# check existing log files
#####

setdb

function checkCurrentLog(){
  currentlogexist=false
  for i in ${loggroups}
  do
    CURRENT_LOG=`echo "select count(*) LOGSTATE from v\\$log where group#=$i and STATUS='CURRENT';" | sqlplus -s / as sysdba | grep -v -- '--' | grep -v LOGSTATE | grep -v "^$" | cut -d" " -f2`
    if [[ "$CURRENT_LOG" == "1" ]]; then
      currentlogexist=true
    fi
  done
  echo $currentlogexist
}

function checkIfLogUsed(){
  # checkIfLogUsed >/< standby_log/log 500
  logmode="<"
  lognumber=800
  logtable=log
  currentlogexist=false

  if [[ $# -gt 0 ]];then
    logmode="$1"
  fi

  if [[ $# -gt 1 ]];then
   logtable="$2"
  fi

  if [[ $# -gt 2 ]];then
   lognumber="$3"
  fi

  if [[ "$1" == "standby_log" ]]; then
    ACTIVE_LOG=`echo "select count(*) LOGSTATE from v\\\$standby_log where group# $logmode $lognumber and STATUS='ACTIVE';" | sqlplus -s / as sysdba | grep -v -- '--' | grep -v LOGSTATE | grep -v "^$" | cut -d" " -f2`
    CURRENT_LOG=`echo "select count(*) LOGSTATE from v\\\$standby_log where group# $logmode $lognumber and STATUS='CURRENT';" | sqlplus -s / as sysdba | grep -v -- '--' | grep -v LOGSTATE | grep -v "^$" | cut -d" " -f2`
  else
    ACTIVE_LOG=`echo "select count(*) LOGSTATE from v\\\$log where group# $logmode $lognumber and STATUS='ACTIVE';" | sqlplus -s / as sysdba | grep -v -- '--' | grep -v LOGSTATE | grep -v "^$" | cut -d" " -f2`
    CURRENT_LOG=`echo "select count(*) LOGSTATE from v\\\$log where group# $logmode $lognumber and STATUS='CURRENT';" | sqlplus -s / as sysdba | grep -v -- '--' | grep -v LOGSTATE | grep -v "^$" | cut -d" " -f2`
  fi

  echo "running checkIfLogUsed with: ${logtable} $logmode $lognumber" >> ${LOGFILE}

  if [[ "$ACTIVE_LOG" != "0" ]]; then
    currentlogexist=true
    echo "active logs $lognumber $logmode ($CURRENT_LOG)" >> ${LOGFILE}
  fi
  
  if [[ "$CURRENT_LOG" != "0" ]]; then
    currentlogexist=true
    echo "current logs $lognumber $logmode ($CURRENT_LOG)" >> ${LOGFILE}
  fi

  DEBUUG_LOG=`echo "select distinct STATUS LOGSTATE from v\\\$log where group# $logmode $lognumber ;" | sqlplus -s / as sysdba | grep -v -- '--' | grep -v LOGSTATE | grep -v "^$" `
  echo "debug $DEBUUG_LOG" >> ${LOGFILE}

  echo $currentlogexist
}

loggroups=$(${DB_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL
set heading off;
set feedback off;
set lines 200;
col NAME for 999;
select group# as NAME from v\$log where group# < 900 order by 1;
EOSQL
)

echo "### Step ### create new logs" | tee -a ${LOGFILE} 
### create new logs

${DB_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL >> ${LOGFILE} 2>&1
  alter database add logfile group 900 size ${logfilesize};
  alter database add logfile group 901 size ${logfilesize};
  alter database add logfile group 902 size ${logfilesize};
EOSQL

echo "### Step ### switch logs" | tee -a ${LOGFILE} 

res=$(checkIfLogUsed)
while [ "$res" == "true" ]
do
  echo "Logs used begin $res" >> ${LOGFILE}
${DB_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL >> ${LOGFILE} 2>&1
  ALTER SYSTEM ARCHIVE LOG CURRENT;
  alter system checkpoint;
  -- alter system archive log all;
EOSQL
  sleep $SLEEP_TIMER
  res=$(checkIfLogUsed)
  echo "Logs used end $res" >> ${LOGFILE}
done

echo "### Step ### remove old logs" | tee -a ${LOGFILE} 

for i in ${loggroups}
do
 RUN_SQL="ALTER DATABASE DROP LOGFILE GROUP $i;"
  echo $RUN_SQL >> ${LOGFILE} 
${DB_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL >> ${LOGFILE} 2>&1
  set heading off;
  set feedback off;
  set lines 200;
  ${RUN_SQL}
EOSQL
done

echo "### Step ### add new logs" | tee -a ${LOGFILE} 

for g in $(seq 1 $logfilenumber)
do
  echo "log number $g" >> ${LOGFILE}
 RUN_SQL="alter database add logfile group $g size ${logfilesize};"
  echo $RUN_SQL >> ${LOGFILE}
${DB_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL >> ${LOGFILE} 2>&1
  set heading off;
  set feedback off;
  set lines 200;
  ${RUN_SQL}
EOSQL
done

echo "### Step ### switch logs" | tee -a ${LOGFILE} 

res=$(checkIfLogUsed ">")
while [ "$res" == "true" ]
do
  echo "Logs used begin $res" >> ${LOGFILE}
${DB_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL >> ${LOGFILE} 2>&1
  ALTER SYSTEM ARCHIVE LOG CURRENT;
  alter system checkpoint;
  -- alter system archive log all;
EOSQL
  sleep $SLEEP_TIMER
  res=$(checkIfLogUsed ">")
  echo "Logs used end $res" >> ${LOGFILE}
done

echo "### Step ### remove helper logs" | tee -a ${LOGFILE} 

loggroups=$(${DB_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL
set heading off;
set feedback off;
set lines 200;
col NAME for 999;
select group# as NAME from v\$log where group# > 800 order by 1;
EOSQL
)

for i in ${loggroups}
do
 RUN_SQL="ALTER DATABASE DROP LOGFILE GROUP $i;"
  echo $RUN_SQL >> ${LOGFILE} 
${DB_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL >> ${LOGFILE} 2>&1
  set heading off;
  set feedback off;
  set lines 200;
  ${RUN_SQL}
EOSQL
done

echo "### Step ### delete standby logs " | tee -a ${LOGFILE} 

stbyloggroups=$(${DB_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL
set heading off;
set feedback off;
set lines 200;
col NAME for 999;
select group# as NAME from v\$standby_log order by 1;
EOSQL
)

for i in ${stbyloggroups}
do
 RUN_SQL="ALTER DATABASE DROP standby LOGFILE GROUP $i;"
  echo $RUN_SQL >> ${LOGFILE} 
${DB_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL >> ${LOGFILE} 2>&1
  set heading off;
  set feedback off;
  set lines 200;
  ${RUN_SQL}
EOSQL
done

stdbylogfilenumber=$((100+$logfilenumber))

for g in $(seq 100 $stdbylogfilenumber)
do
  echo "log number $g" >> ${LOGFILE}
  RUN_SQL="alter database add standby logfile group $g size ${logfilesize};"
  echo $RUN_SQL >> ${LOGFILE}
${DB_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL >> ${LOGFILE} 2>&1
  set heading off;
  set feedback off;
  set lines 200;
  ${RUN_SQL}
EOSQL
done

## check
echo "### Step ### end check " | tee -a ${LOGFILE} 

loggroups=$(${DB_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL
set heading off;
set feedback off;
set lines 200;
col LOGS for a50;
select 'LOG-' || group# || '-' || round(bytes/1024/1024) || '-MB' LOGS from v\$log order by 1;
select 'STANDBYLOG-' || group# || '-' || round(bytes/1024/1024) || '-MB'  LOGS from v\$standby_log order by 1;
EOSQL
)

for i in ${loggroups}
do
  echo $i;
done

echo "### Step ### recreate archivelog on remote nodes" | tee -a ${LOGFILE} 

function getRemoteLoggroups() {

remoteloggroups=$(${DB_HOME}/bin/sqlplus -L -S /@${1} as sysdba << EOSQL
set heading off;
set feedback off;
set lines 200;
col NAME for 9999;
select group# as NAME from v\$log order by 1;
EOSQL
)

remotestandbyloggroups=$(${DB_HOME}/bin/sqlplus -L -S /@${1} as sysdba << EOSQL
set heading off;
set feedback off;
set lines 200;
col NAME for 9999;
select group# as NAME from v\$standby_log order by 1;
EOSQL
)

allloggroups=$(${DB_HOME}/bin/sqlplus -L -S /@${1} as sysdba << EOSQL
set heading off;
set feedback off;
set lines 200;
col LOGS for a50;
select 'LOG-' || group# || '-' || round(bytes/1024/1024) || '-MB' LOGS from v\$log order by 1;
select 'STANDBYLOG-' || group# || '-' || round(bytes/1024/1024) || '-MB'  LOGS from v\$standby_log order by 1;
EOSQL
)

}

for dghost in $(echo $dghosts | tr "," "\n")
do
    dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
    OTHER_HOST_IDENTIFIER=${dghostname:1:4}
    OTHER_DB_UNIQUE_NAME=${dgenv}d${OTHER_HOST_IDENTIFIER}${dgnumber}
    if [[ "${DB_HOST}" != "$dghostname" ]]; then
      echo "run on host $dghostname" >> ${LOGFILE} 2>&1
      echo "DB: $OTHER_DB_UNIQUE_NAME on $dghostname" >> ${LOGFILE} 2>&1

      ${DB_HOME}/bin/dgmgrl / <<EOSQL >> ${LOGFILE} 2>&1
      EDIT DATABASE ${OTHER_DB_UNIQUE_NAME} SET STATE='APPLY-OFF';
      show database ${OTHER_DB_UNIQUE_NAME} StandbyFileManagement;
      EDIT database ${OTHER_DB_UNIQUE_NAME} SET PROPERTY StandbyFileManagement='MANUAL';
EOSQL

    getRemoteLoggroups ${OTHER_DB_UNIQUE_NAME}

    for i in ${remoteloggroups}
    do
      RUN_SQL="ALTER DATABASE DROP LOGFILE GROUP $i;"
      echo $RUN_SQL >> ${LOGFILE} 
      ${DB_HOME}/bin/sqlplus -L -S /@${OTHER_DB_UNIQUE_NAME} as sysdba << EOSQL >> ${LOGFILE} 2>&1
      set heading off;
      set feedback off;
      set lines 200;
      ${RUN_SQL}
EOSQL
    done

 
    for h in ${remotestandbyloggroups}
    do
      RUN_SQL="ALTER DATABASE DROP STANDBY LOGFILE GROUP $h;"
      echo $RUN_SQL >> ${LOGFILE} 
      ${DB_HOME}/bin/sqlplus -L -S /@${OTHER_DB_UNIQUE_NAME} as sysdba << EOSQL >> ${LOGFILE} 2>&1
      set heading off;
      set feedback off;
      set lines 200;
      ${RUN_SQL}
EOSQL
    done

    for g in $(seq 1 $logfilenumber)
    do
      echo "${OTHER_DB_UNIQUE_NAME}: log number $g" >> ${LOGFILE}
      RUN_SQL="alter database add logfile group $g size ${logfilesize};"
      echo $RUN_SQL >> ${LOGFILE}
      ${DB_HOME}/bin/sqlplus -L -S /@${OTHER_DB_UNIQUE_NAME}  as sysdba << EOSQL >> ${LOGFILE} 2>&1
      set heading off;
      set feedback off;
      set lines 200;
      ${RUN_SQL}
EOSQL
    done

      ${DB_HOME}/bin/sqlplus -L -S / as sysdba << EOSQL >> ${LOGFILE} 2>&1
      set heading off;
      set feedback off;
      set lines 200;
      ALTER SYSTEM ARCHIVE LOG CURRENT;
      alter system checkpoint;
EOSQL

    getRemoteLoggroups ${OTHER_DB_UNIQUE_NAME}

    for h in ${remotestandbyloggroups}
    do
      RUN_SQL="ALTER DATABASE DROP STANDBY LOGFILE GROUP $h;"
      echo $RUN_SQL >> ${LOGFILE} 
      ${DB_HOME}/bin/sqlplus -L -S /@${OTHER_DB_UNIQUE_NAME} as sysdba << EOSQL >> ${LOGFILE} 2>&1
      set heading off;
      set feedback off;
      set lines 200;
      ${RUN_SQL}
EOSQL
    done

    stdbylogfilenumber=$((100+$logfilenumber))

    for j in $(seq 100 $stdbylogfilenumber)
    do
      echo "log number $j" >> ${LOGFILE}
      RUN_SQL="alter database add standby logfile group $j size ${logfilesize};"
      echo $RUN_SQL >> ${LOGFILE}
    ${DB_HOME}/bin/sqlplus -L -S /@${OTHER_DB_UNIQUE_NAME} as sysdba << EOSQL >> ${LOGFILE} 2>&1
      set heading off;
      set feedback off;
      set lines 200;
      ${RUN_SQL}
EOSQL
    done

    ${DB_HOME}/bin/dgmgrl / <<EOSQL >> ${LOGFILE} 2>&1
      EDIT DATABASE ${OTHER_DB_UNIQUE_NAME} SET STATE='APPLY-ON';
      show database ${OTHER_DB_UNIQUE_NAME} StandbyFileManagement;
      EDIT database ${OTHER_DB_UNIQUE_NAME} SET PROPERTY StandbyFileManagement='AUTO';
      show database ${OTHER_DB_UNIQUE_NAME} StandbyFileManagement;
EOSQL

    ## check
    echo "### Step ### end check ${OTHER_DB_UNIQUE_NAME}" | tee -a ${LOGFILE} 

    getRemoteLoggroups ${OTHER_DB_UNIQUE_NAME}

    for i in ${allloggroups}
    do
      echo $i;
    done

    fi
     
done

${DB_HOME}/bin/dgmgrl / <<EOSQL >> ${LOGFILE} 2>&1
      show configuration verbose;
EOSQL
