#!/bin/bash

# Changes
# 19.01.22 MFU Compatible mode in new standby
# 13.01.22 MFU broker checks added 
# 27.12.21 MFU EXA2ZELOS-120 - Add service connect for active CDB
# 20.12.21 MFU IGNORE_PUBLIC_INTERFACE test für CC monitoring
# 12.12.21 MFU EXA2ZELOS-111/113 audit und diag dest
# ... -> cr_dg.info


function fct_usage()
{
echo -e "
$0 -f <DG_CONFIG> [options -p -l -c]
Usage:
\t-f <DG_CONFIG>
\t-p no password needed, wallets stay untouched
\t-l no listener restarts
\t-c prepare for cloning
"
}

if [[ $# -lt 2 ]];then
 fct_usage
 exit 1
fi

#######################
# Parameter

IGNORE_PUBLIC_INTERFACE=true
password=true
cloninguser=false
listener_restarts=true

##################


while getopts f:pl flag
do
    case "${flag}" in
        f) configfile=${OPTARG}
          ;;
        p) password=false
          ;;
        c) cloninguser=true
          ;;
        l) listener_restarts=false
          ;;
        h) fct_usage
           exit 0
          ;;
        \? ) fct_usage
           exit 0
          ;;
    esac
done

### Config file

echo "Info"

if test -f ${configfile} ; then
  echo "-f :   using config file ${configfile}" | tee -a ${LOGFILE}
  . ${configfile}
else
    echo "config file: ${configfile} not found " | tee -a ${LOGFILE}
    exit 1
fi

if [[ $password == "false" ]];then
  echo "-p:   wallets are not touched using no password"
else
  echo "wallets are changed, password needed"
  password=true
fi

if [[ $listener_restarts == "false" ]];then
  echo "-l    listener not restarted"
else
  echo "listeners will be restarted" 
  listener_restarts=true
fi

echo "####"
echo ""

START=$(date +%s)
WORK_DIR=$(pwd)
SSH_CONECTIVITY=false
ORATAB=/etc/oratab
DB_HOST=$(uname -n)db
PUBLIC_HOST=$(uname -n)
DB_HOST_IDENTIFIER=${DB_HOST:1:4}
DB_UNIQUE_NAME=${dgenv}d${DB_HOST_IDENTIFIER}${dgnumber}
SCRIPT_DIR=${WORK_DIR}/${DB_UNIQUE_NAME}
HOST_SCRIPT_DIR=${WORK_DIR}/${DB_HOST}
DB_NAME=${dbname}
DB_DOMAIN=$(nslookup $(uname -n) | grep ^Name: | awk -F' ' '{ print $2 }' | cut -d"." -f2-)
ORG_PATH=$PATH
DB_HOME=/orasw/oracle/product/db19
ORACLE_BASE=/orasw/oracle
CRS_HOME=$(cat ${ORATAB} | grep -v ^# | grep -v ^$ | grep -E "^[+|-]" | cut -d":" -f2 | sort | uniq)
WALLET_DIRECTORY="/orasw/oracle/wallet"

LISTENER_ORA=${DB_HOME}/network/admin/listener.ora
SQLNET_ORA=${DB_HOME}/network/admin/sqlnet.ora
TNSNAMES_ORA=${DB_HOME}/network/admin/tnsnames.ora
TNSNAMES_OBSERVER=${HOST_SCRIPT_DIR}/tnsnames.observer
TNSNAMES_ODI=${HOST_SCRIPT_DIR}/tnsnames.odi

GI_LISTENER_ORA=${CRS_HOME}/network/admin/listener.ora
GI_TNSNAMES_ORA=${CRS_HOME}/network/admin/tnsnames.ora

## passwords

if [[ -f ${WORK_DIR}/resources/.dbvpw.enc ]];then
  export $(openssl enc -aes-256-cbc -d -in ${WORK_DIR}/resources/.dbvpw.enc -k DBVAULT2020)
else
  echo "${WORK_DIR}/resources/.dbvpw.enc not found, please check." 
  exit 1
fi
## set homes

function setasm () {
    export ORACLE_SID=+ASM
    export ORACLE_HOME=$CRS_HOME
    export PATH=$ORG_PATH
    export PATH=${ORACLE_HOME}/bin:${ORACLE_HOME}/perl/bin:$PATH
    export PERL5LIB=${ORACLE_HOME}/rdbms/admin:$PERL5LIB
    export ORACLE_BASE=${ORACLE_BASE}
    export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
}

function setdb () {
    export ORACLE_SID=${DB_UNIQUE_NAME} 
    export ORACLE_HOME=${DB_HOME}
    export PATH=$ORG_PATH
    export PATH=${ORACLE_HOME}/bin:${ORACLE_HOME}/perl/bin:$PATH
    export PERL5LIB=${ORACLE_HOME}/rdbms/admin:$PERL5LIB
    export ORACLE_BASE=${ORACLE_BASE}
    export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
}

function setdbInFile() {
    echo "export ORACLE_SID=${DB_UNIQUE_NAME}" >> $1
    echo "export ORACLE_HOME=${DB_HOME}" >> $1
    echo "export PATH=$ORG_PATH" >> $1
    echo "export PATH=${ORACLE_HOME}/bin:${ORACLE_HOME}/perl/bin:$PATH" >> $1
    echo "export PERL5LIB=${ORACLE_HOME}/rdbms/admin:$PERL5LIB" >> $1
    echo "export ORACLE_BASE=${ORACLE_BASE}" >> $1
    echo "export NLS_LANG=AMERICAN_AMERICA.AL32UTF8" >> $1
}

function addQuestionToFile {
    echo "echo \"is this correct? (y/n)?\"" >> $1
    echo "read answer >> \$1" >> $1
    echo "if [ \"\$answer\" != \"\${answer#[Yy]}\" ] ;then" >> $1
    echo "echo \"\"" >> $1
    echo "else" >> $1
    echo "echo \"ERROR-99: installation aborted by user\"" >> $1
    echo "exit 99" >> $1
    echo "fi" >> $1
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

if [[ -z ${syncmode} ]]; then
  echo "missing parameter syncmode in $1"
  echo "# Sync mode "
  echo "# SYNC, FASTSYNC, ASYNC"
  echo "syncmode=FASTSYNC"
  echo "add in $1"
  exit 1
fi  

if [[ -z ${cmanhosts} ]]; then
  echo "missing parameter cmanhosts in $1"
  echo "# comma separtede no spaces, cman hsot names to connect "
  echo "# e.g. Prod l0392022.dst.baintern.de,l0393022.dst.baintern.de"
  echo "# e.g. Int l0398022.idst.ibaintern.de,l0399022.idst.ibaintern.de"
  echo "cmanhosts=l0392022.dst.baintern.de,l0393022.dst.baintern.de"
  echo "add in $1"
  exit 1
fi  

if [[ -z ${cmanhosts} ]]; then
  echo "missing dgohsts cmanhosts in $1"
  echo "example: dghosts=l9701022db:l9701022db,l9703022db:l9703022dg,l9702022:192.168.200.54,l9704022:192.168.200.77"
  echo "first host -> primary"
  echo "third host -> Remote sync"
  echo "forth host -> Remote Async"
fi

if [[ -z ${cmanport} ]]; then
  echo "missing parameter cmanport in $1"
  echo "port for cman, added in tnsnames"
  echo "# e.g. cmanport=55436"
  echo "cmanport=55436"
  echo "add in $1"
  exit 1
fi

if [[ -z ${servicenames} ]]; then
  echo "missing parameter servicenames in $1"
  echo "# genrateion of dataguard TNS Entries"
  echo "# the service are genreated with seperate script <db_unique_name>/generate_service.sh"
  echo "# e.g. servicenames=ISTAT,ISTAT_IA,ISTAT_RO"
  echo "servicenames=ISTAT,ISTAT_IA,ISTAT_RO"
  echo "add in $1"
  exit 1
fi


echo "DB Name          $DB_NAME"
echo "Active Node      $activenode"
echo "DG Number        $dgnumber"
echo "DG Environment   $dgenv"
echo "Listener Port    $port"
echo "HV Listener Port $hvport"
echo "Sync Mode        $syncmode"
echo "Host:            ${DB_HOST}.${DB_DOMAIN}"
echo "ORACLE_SID       ${DB_UNIQUE_NAME}"
echo "HV Service:      ${DB_UNIQUE_NAME}_HV"
echo "GI listner.ora   ${GI_LISTENER_ORA}"
echo "DG HOSTS"

FOUND_LOCAL_HOST=false

dgcounter=0
REMOTE_SYNC_DB_STANDBY='undefined'
REMOTE_ASYNC_DB_STANDBY='undefined'
DATAGUARD_PRIMARY='undefined'

for readhosts in $(echo $dghosts | tr "," "\n")
do
  dgcounter=$((dgcounter+1))
  dghostname=$(echo $readhosts| awk -F  ":" '{print $1}')
  dghvip=$(echo $readhosts| awk -F  ":" '{print $2}')
  if [[ "${DB_HOST}" == "${dghostname}" ]]; then
    FOUND_LOCAL_HOST=true
  fi
  if [[ -z ${dghvip} ]]; then
    dghvip=${dghostname}
  fi

  OTHER_HOST_IDENTIFIER=${readhosts:1:4}
  TEMP_DB_UNIQUE_NAME=${dgenv}d${OTHER_HOST_IDENTIFIER}${dgnumber} 

  echo "- $dghostname HVIP $dghvip (${TEMP_DB_UNIQUE_NAME})"

  declare DG_DBNAMES_${dgcounter}=${TEMP_DB_UNIQUE_NAME}

done

DG_HOST_NUMBERS=$dgcounter

if [[ ! -z $DG_DBNAMES_1 ]]; then
  echo "Primary DB           : $DG_DBNAMES_1"
else
  echo "error in config, Primary missing - $DG_DBNAMES_1"
  exit 1
fi

if [[ ! -z $DG_DBNAMES_3 ]]; then
  echo "Remote Standby Sync  : $DG_DBNAMES_3"
fi

if [[ ! -z $DG_DBNAMES_4 ]]; then
  echo "Remote Standby ASync : $DG_DBNAMES_4"
fi

echo "CMAN"
echo "CMAN port         ${cmanport}"

for readcmans in $(echo $cmanhosts | tr "," "\n")
do
  cmanhostname=$(echo $readcmans| awk -F  ":" '{print $1}')
  echo "- $cmanhostname"
done

if [[ "${FOUND_LOCAL_HOST}" == "false" ]]; then
  echo "missing local host config, please add local host ${DB_HOST} in dghosts in config "
  exit 1
fi

echo "Services"
for readservice in $(echo $servicenames | tr "," "\n")
do
  echo "- $readservice"
done

if [[ "${FOUND_LOCAL_HOST}" == "false" ]]; then
  echo "missing local host config, please add local host ${DB_HOST} in dghosts in config "
  exit 1
fi

### 
### some checks
####

setdb

DATABASE_STATE=NOTHING
DATABASE_RUNNING=`srvctl status database -d ${DB_UNIQUE_NAME} | grep -i "is running" | wc -l`

if [[ "$DATABASE_RUNNING" == "1" ]]; then
  EXIST_DATABASE_ROLE=`echo "select database_role DATABASE_ROLE from v\\$database;" | sqlplus -s / as sysdba | grep -v -- '--' | grep -v DATABASE_ROLE | grep -v "^$" | cut -d" " -f2`
  if [[ "$EXIST_DATABASE_ROLE" == "PRIMARY" ]];then
    echo "ROLE:             $EXIST_DATABASE_ROLE"
    DATABASE_STATE=READWRITE
  fi
fi

echo "DATABASE State:   ${DATABASE_STATE}"

echo "is this correct? (y/n)?"
read answer
if [ "$answer" != "${answer#[Yy]}" ] ;then
echo ""
else
echo "ERROR-99: installation aborted by user"
exit 1
fi 


#####
# getting sys/system password
#####


if [[ $password == "true" ]]; then

read -p "enter sys/system password for wallet creation[[ (return) = default (oracle)]]: " SYS_PASSWORD
[[ -z ${SYS_PASSWORD} ]] && SYS_PASSWORD=oracle

else 
  SYS_PASSWORD=unknown
fi

### Log Configuration

mkdir -p ${ORACLE_BASE}/admin/${DB_UNIQUE_NAME}/log
LOGFILE=${ORACLE_BASE}/admin/${DB_UNIQUE_NAME}/log/$(echo "install_dg_${DB_UNIQUE_NAME}_$(date '+Y%YM%mD%d_H%HM%MS%S').log")
log_dir=${ORACLE_BASE}/admin/${DB_UNIQUE_NAME}/log

echo "Logfile: ${LOGFILE}" | tee -a ${LOGFILE}

### Folder configs
## Folder to store scripts
mkdir -p ${SCRIPT_DIR}
mkdir -p ${HOST_SCRIPT_DIR}

#### Backup Files

backup_file() {
  new_file=$(echo $1 | rev | cut -f 2- -d '.' | rev)
  cp $1 ${new_file}_$(date '+Y%YM%mD%d_H%HM%MS%S').save
  echo "Save: ${1}" | tee -a ${LOGFILE}
}

#####
# generate oratab entry for STANDBY
#####

echo "###[STEP]### create oratab entry..." | tee -a ${LOGFILE}
ENTRY=$(echo "${DB_UNIQUE_NAME}:${DB_HOME}:N")

if [[ ! -f ${ORATAB} ]];then
touch ${ORATAB}
fi

grep -i  "${DB_UNIQUE_NAME}[: $=]" ${ORATAB} >/dev/null
RC=$?
if [[ $RC != 0 ]];then
backup_file ${ORATAB}
echo "${ENTRY}" >> ${ORATAB}
else
echo "SKIP - Entry already exists" | tee -a ${LOGFILE}
fi


########
# correct ASM configuration
########



echo "###[STEP]### correct ASM configuration ${CRS_HOME}" | tee -a ${LOGFILE}

CRS_PASSWORD_FILE=${CRS_HOME}/dbs/orapw+ASM.ora

setasm

EXISTING_PASSWORD_FILE=`srvctl config asm | grep -vi "Backup" | grep -i "PASSWORD" | awk '{print $3}'`

if [[ "${CRS_PASSWORD_FILE}" != "${EXISTING_PASSWORD_FILE}" ]]; then
  echo "different Password file configured ${CRS_PASSWORD_FILE} vs ${EXISTING_PASSWORD_FILE}" | tee -a ${LOGFILE}
  echo "   ---> check !!! " | tee -a ${LOGFILE}
else 
  if [[ ! -f ${CRS_PASSWORD_FILE} ]];then
    if [[ $password == "true" ]];then
      ${CRS_HOME}/bin/orapwd file=${CRS_PASSWORD_FILE} entries=20 password=${SYS_PASSWORD}
      echo "created ASM Password file ${CRS_PASSWORD_FILE}" >> ${LOGFILE} 2>&1
    else
      echo "no password - no changes"
    fi
  fi
fi

ASMSNMP_EXIST=`echo "select count(*) ASMSNMP from v\\$pwfile_users where username='ASMSNMP';" | sqlplus -s / as sysasm | grep -v -- '--' | grep -v ASMSNMP | grep -v "^$" | cut -d" " -f2`

if [[ "$ASMSNMP_EXIST" == "1" ]]; then
  echo "alter ASMSNMP user" >> ${LOGFILE} 2>&1
${CRS_HOME}/bin/sqlplus -L -S / as sysasm <<EOSQL >> ${LOGFILE} 2>&1
alter user asmsnmp identified by Casper001;
grant sysdba to asmsnmp;
grant sysasm to asmsnmp;
EOSQL
else 
  echo "create ASMSNMP user" >> ${LOGFILE} 2>&1
${CRS_HOME}/bin/sqlplus -L -S / as sysasm <<EOSQL >> ${LOGFILE} 2>&1
create user asmsnmp identified by Casper001;
grant sysdba to asmsnmp;
grant sysasm to asmsnmp;
EOSQL
fi

#####
# generate listener.ora entry for SINGLE
#####

function generateListnerConfig(){
for dghost in $(echo $dghosts | tr "," "\n")
do
  dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
  if [[ "${DB_HOST}" == "${dghostname}" ]]; then
     dghvip=$(echo $dghost| awk -F  ":" '{print $2}')
     if [[ -z ${dghvip} ]]; then
        dghvip="${dghostname}"
     fi

     if [[ "$1" == "DG" ]]; then
       ENTRY=$(echo "LISTENER_DG=(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=IPC)(KEY=LISTENER_DG))(ADDRESS=(PROTOCOL=TCP)(HOST=${dghvip})(PORT=${hvport}))))
ENABLE_GLOBAL_DYNAMIC_ENDPOINT_LISTENER_DG=ON
VALID_NODE_CHECKING_REGISTRATION_LISTENER_DG=ON
DIAG_ADR_ENABLED_LISTENER_DG=OFF
LOGGING_LISTENER_DG=OFF
INBOUND_CONNECT_TIMEOUT_LISTENER_DG=1200
OUTBOUND_CONNECT_TIMEOUT_LISTENER_DG=1200
       ")
     else
       ENTRY=$(echo "LISTENER=(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=IPC)(KEY=LISTENER))(ADDRESS=(PROTOCOL=TCP)(HOST=${DB_HOST})(PORT=${port}))))
ENABLE_GLOBAL_DYNAMIC_ENDPOINT_LISTENER=ON
VALID_NODE_CHECKING_REGISTRATION_LISTENER=ON
DIAG_ADR_ENABLED_LISTENER=OFF
LOGGING_LISTENER=OFF
INBOUND_CONNECT_TIMEOUT_LISTENER=1200
OUTBOUND_CONNECT_TIMEOUT_LISTENER=1200
       ")
     fi
  fi
done

}

checkListenerExist(){

LISTENER_EXIST=$(${CRS_HOME}/bin/lsnrctl status $1 | grep -i Alias | grep -v grep | wc -l)

if [[ $LISTENER_EXIST -eq 0 ]];then
  echo "Listener ${1} not found in ASM env"
  LISTENER_EXIST_CRS=$(${CRS_HOME}/bin/crsctl stat res -t | grep ora.${1}.lsnr | grep -v grep | wc -l)
  if [[ $LISTENER_EXIST_CRS -eq 0 ]];then
    setdb
    ${DB_HOME}/bin/srvctl add listener -listener ${1} -endpoints ${2} -skip -oraclehome ${CRS_HOME} >> ${LOGFILE} 2>&1
    echo "Listener ${1} added"
    setasm
  else 
    echo "try listener start $1"
    ${CRS_HOME}/bin/lsnrctl start $1 >> ${LOGFILE} 2>&1
  fi
fi
}

#####

echo "###[STEP]### create listener.ora entry ${GI_LISTENER_ORA}" | tee -a ${LOGFILE}

grep -i  "${DB_UNIQUE_NAME}[: $=]" ${ORATAB} >/dev/null
RC=$?
if [[ $RC != 0 ]];then
echo "SKIP - Failure DB not exists" | tee -a ${LOGFILE}
# exit 1
fi

STAT_ALL=$(echo "# Eintrag DG CONFIG, $(date '+%d.%m.%Y')
SID_LIST_LISTENER_DG =
  (SID_LIST ="
  )

for DB in $(cat /etc/oratab | grep -vE "^#|^$|MGMTDB|ASM" | cut -d':' -f1 | sort)
do
    DB_ORACLE_HOME=$(cat /etc/oratab | grep ^${DB}: | cut -d':' -f2)
    # echo "   add entry ${DB} ${DB_ORACLE_HOME} in listener " | tee -a ${LOGFILE}
    STAT_LISTENER=$(echo "
        (SID_DESC =
        (GLOBAL_DBNAME = ${DB}_HV )
        (ORACLE_HOME = ${DB_ORACLE_HOME})
        (SID_NAME = ${DB})
        )"
    )
    STAT_ALL=${STAT_ALL}${STAT_LISTENER}
done

STAT_ALL=${STAT_ALL}$(echo "
)")

lead='### BEGIN GENERATED CONTENT DATAGUARD'
tail='### END GENERATED CONTENT DATAGUARD'

backup_file ${GI_LISTENER_ORA}

# delete old comments
sed -i "/^$lead$/,/^$tail$/d" ${GI_LISTENER_ORA}

echo "${lead}" >> ${GI_LISTENER_ORA}

generateListnerConfig
echo "$ENTRY" >> ${GI_LISTENER_ORA}
generateListnerConfig DG
echo "$ENTRY" >> ${GI_LISTENER_ORA}

echo "${STAT_ALL}" >> ${GI_LISTENER_ORA}
echo "${tail}" >> ${GI_LISTENER_ORA}

ENTRY=''

######
# CHeck listener exist

echo "###[STEP]### LISTENER setup " | tee -a ${LOGFILE}

setasm
checkListenerExist LISTENER ${port}
checkListenerExist LISTENER_DG ${hvport}

setasm

if [[ $listener_restarts == "true" ]]; then

  echo "restart listener in ${CRS_HOME}" | tee -a ${LOGFILE}
  ${CRS_HOME}/bin/srvctl stop listener -listener listener >> ${LOGFILE} 2>&1
  ${CRS_HOME}/bin/srvctl start listener -listener listener >> ${LOGFILE} 2>&1

  ${CRS_HOME}/bin/srvctl stop listener -listener listener_dg >> ${LOGFILE} 2>&1
  ${CRS_HOME}/bin/srvctl start listener -listener listener_dg >> ${LOGFILE} 2>&1
else
  echo "no restart of listener in ${CRS_HOME}" | tee -a ${LOGFILE}
fi
#####
# generate dataguard tnsnames entry for SINGLE
#####
setdb

echo "###[STEP]### create dataguard tnsnames.ora entry ${TNSNAMES_ORA}" | tee -a ${LOGFILE}

if [ ! -f ${TNSNAMES_ORA} ]; then
    touch ${TNSNAMES_ORA}
fi

function generateHVTNSEntry() {
OTHER_HOST_IDENTIFIER=$1
OTHER_DB_UNIQUE_NAME=$2

ENTRY=$(echo "# Eintrag statischer Listener ${1} DG ${OTHER_DB_UNIQUE_NAME}, $(date '+%d.%m.%Y')
${OTHER_DB_UNIQUE_NAME}_HV=
  (DESCRIPTION =
    (SEND_BUF_SIZE=16777216)
    (RECV_BUF_SIZE=16777216)
    (SDU=65535)
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${1})(PORT = ${hvport}))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${OTHER_DB_UNIQUE_NAME}_HV)
    )
  )

")
}

function generateDirectTNSEntry() {
OTHER_HOST_IDENTIFIER=$1
OTHER_DB_UNIQUE_NAME=$2

ENTRY=$(echo "# Eintrag UNIQUE Name hosts ${1} ${OTHER_DB_UNIQUE_NAME}, $(date '+%d.%m.%Y')
${OTHER_DB_UNIQUE_NAME}=
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${1}.${DB_DOMAIN})(PORT = ${port}))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${OTHER_DB_UNIQUE_NAME})
    )
  )

")
}

function generateNetListenerEntry() {

NET_LISTNER_HOST_NAME=$1
NET_LISTNER_PORT=$2

# ALTER SYSTEM SET listener_networks='((NAME=net2)(LOCAL_LISTENER="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=morrison-dg-vip)(PORT=1853)))")(REMOTE_LISTENER=doors-dg:1854))'; 
ENTRY=$(echo "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${NET_LISTNER_HOST_NAME})(PORT=${NET_LISTNER_PORT})))")
}


function setNetListenerEntry() {

  for dghost in $(echo $dghosts | tr "," "\n")
  do
    dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
    if [[ "${DB_HOST}" == "${dghostname}" ]]; then
      dghvip=$(echo $dghost| awk -F  ":" '{print $2}')
      if [[ -z ${dghvip} ]]; then
        dghvip=${dghostname}
      fi

      generateNetListenerEntry ${dghvip} ${hvport}
      NET_LISTENER_DG_ENTRY=$ENTRY
    fi
  done

generateNetListenerEntry ${DB_HOST} ${port}
NET_LISTENER_LOCAL_ENTRY=$ENTRY

}


function generateCMANTNSEntry() {
CMAN_SERVER_1=$1
CMAN_SERVER_2=$2

ENTRY=$(echo "# Eintrag CMAN Names, $(date '+%d.%m.%Y')
CMAN_BI=
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${1})(PORT = ${cmanport}))
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${2})(PORT = ${cmanport}))
  )

")
}

function generateCdbDgEntry() {

TNS_CONFIG_DB_NAME=$1
TNS_CONFIG_SERVICE_NAME=$1

ENTRY_BEGIN=$(echo "# Eintrag CMAN Names, $(date '+%d.%m.%Y')
${TNS_CONFIG_DB_NAME}=
  (DESCRIPTION =
    (ADDRESS_LIST=
      (LOAD_BALANCE=off)
      (FAILOVER=on)
")

ENTRY_HOSTS="${ENTRY_BEGIN}"

for dghost in $(echo $dghosts | tr "," "\n")
do
  dghostname=$(echo $dghost| awk -F  ":" '{print $1}')

  ENTRY_HOST=$(echo "
          (ADDRESS = (PROTOCOL = TCP)(HOST = ${dghostname}.${DB_DOMAIN})(PORT = ${port}))")
  ENTRY_HOSTS="${ENTRY_HOSTS}${ENTRY_HOST}"
done

ENTRY_END=$(echo "
    )
    (CONNECT_DATA=
      (SERVER=DEDICATED)
      (SERVICE_NAME=${TNS_CONFIG_SERVICE_NAME})
    )
  )

")

ENTRY_HOSTS="${ENTRY_HOSTS}${ENTRY_END}"
ENTRY="${ENTRY_HOSTS}"

}

### backup
backup_file ${TNSNAMES_ORA}

##########
## for listener

lead='### BEGIN GENERATED TNSNAMES FOR DG LISTENER'
tail='### END GENERATED TNSNAMES FOR DG LISTENER'

sed -i "/^$lead$/,/^$tail$/d" ${TNSNAMES_ORA}
echo "${lead}" >> ${TNSNAMES_ORA}

for dghost in $(echo $dghosts | tr "," "\n")
do
  dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
  if [[ "${DB_HOST}" == "${dghostname}" ]]; then
    dghvip=$(echo $dghost| awk -F  ":" '{print $2}')
    if [[ -z ${dghvip} ]]; then
      dghvip=${dghostname}
    fi

    cnt=0
    for readcmans in $(echo $cmanhosts | tr "," "\n")
    do
      declare cmanhostname${cnt}=$readcmans
      ((cnt+= 1))
    done
    
    generateCMANTNSEntry $cmanhostname0 $cmanhostname1
    echo "$ENTRY" >> ${TNSNAMES_ORA}
  fi
done

echo "${tail}" >> ${TNSNAMES_ORA}

#####
# Services

lead='### BEGIN GENERATED TNSNAMES FOR '${DB_NAME}
tail='### END GENERATED TNSNAMES FOR '${DB_NAME}

# delete old comments
sed -i "/^$lead$/,/^$tail$/d" ${TNSNAMES_ORA}
sed -i "/^$lead$/,/^$tail$/d" ${TNSNAMES_ODI}
sed -i "/^$lead$/,/^$tail$/d" ${TNSNAMES_OBSERVER}

echo "${lead}" >> ${TNSNAMES_ORA}
echo "${lead}" >> ${TNSNAMES_ODI}
echo "${lead}" >> ${TNSNAMES_OBSERVER}

# For DB NAME
generateCdbDgEntry ${DB_NAME} 
echo "$ENTRY" >> ${TNSNAMES_ORA}
echo "$ENTRY" >> ${TNSNAMES_OBSERVER}


# FOR PDB
for readservice in $(echo $servicenames | tr "," "\n")
do
  generateCdbDgEntry ${readservice} 
  echo "$ENTRY" >> ${TNSNAMES_ORA}
  echo "$ENTRY" >> ${TNSNAMES_ODI}
done

for dghost in $(echo $dghosts | tr "," "\n")
do
    dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
    OTHER_HOST_IDENTIFIER=${dghostname:1:4}
    OTHER_DB_UNIQUE_NAME=${dgenv}d${OTHER_HOST_IDENTIFIER}${dgnumber}

    generateDirectTNSEntry $dghostname $OTHER_DB_UNIQUE_NAME
    # echo $ENTRY

    echo "${ENTRY}" >> ${TNSNAMES_ORA}
    echo "" >> ${TNSNAMES_ORA}

    echo "${ENTRY}" >> ${TNSNAMES_OBSERVER}
    echo "" >> ${TNSNAMES_OBSERVER}

    ENTRY=''  
done

for readhosts in $(echo $dghosts | tr "," "\n")
do
  dghostname=$(echo $readhosts| awk -F  ":" '{print $1}')
  OTHER_HOST_IDENTIFIER=${readhosts:1:4}
  OTHER_DB_UNIQUE_NAME=${dgenv}d${OTHER_HOST_IDENTIFIER}${dgnumber}
  dghvip=$(echo $readhosts| awk -F  ":" '{print $2}')
  if [[ -z ${dghvip} ]]; then
    dghvip=${dghostname}
  fi

  generateHVTNSEntry $dghvip $OTHER_DB_UNIQUE_NAME

  echo "${ENTRY}" >> ${TNSNAMES_ORA}
  echo "" >> ${TNSNAMES_ORA}

  echo "${ENTRY}" >> ${TNSNAMES_OBSERVER}
  echo "" >> ${TNSNAMES_OBSERVER}
  ENTRY=''  

done

echo "${tail}" >> ${TNSNAMES_ORA}
echo "${tail}" >> ${TNSNAMES_ODI}
echo "${tail}" >> ${TNSNAMES_OBSERVER}
echo "" >> ${LOGFILE} 


##########
### prepare listener
# TNS: listener_default listener_dataguard

echo "###[STEP]### edit listener_networks in ${DB_UNIQUE_NAME} at ${DB_HOME}" | tee -a ${LOGFILE}

setdb

# (ADDRESS=(PROTOCOL=TCP))

function generateLocalListnerIdentifier() {
# 1 Hostname public ${port}
# 2 Hostname dblan ${port}
# 3 hostname dglan ${hvport} 
ENTRY=$(echo "(ADDRESS=(PROTOCOL=TCP)(HOST=${1}.${DB_DOMAIN})(PORT=${port})),(ADDRESS=(PROTOCOL=TCP)(HOST=${2}.${DB_DOMAIN})(PORT=${port})),(ADDRESS=(PROTOCOL=TCP)(HOST=${3}.${DB_DOMAIN})(PORT=${hvport}))")

if [[ ${IGNORE_PUBLIC_INTERFACE} == 'true' ]]; then
  echo "no local listner entry for ${1}.${DB_DOMAIN} (IGNORE_PUBLIC_INTERFACE in script) " | tee -a ${LOGFILE}
  ENTRY=$(echo "(ADDRESS=(PROTOCOL=TCP)(HOST=${2}.${DB_DOMAIN})(PORT=${port})),(ADDRESS=(PROTOCOL=TCP)(HOST=${3}.${DB_DOMAIN})(PORT=${hvport}))")
fi

}

generateLocalListnerIdentifier ${PUBLIC_HOST} ${DB_HOST} ${PUBLIC_HOST}dg
echo "local listener ${ENTRY}" >> $LOGFILE
LOCAL_LISTENER_DB_ENTRY=${ENTRY}

if [[ "${DB_HOST}" == "${activenode}" ]]; then

setNetListenerEntry

${DB_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE} 2>&1
alter system set local_listener='${LOCAL_LISTENER_DB_ENTRY}' scope=both;
alter system set LISTENER_NETWORKS='((NAME=network_default)(LOCAL_LISTENER=${NET_LISTENER_LOCAL_ENTRY}))','((NAME=network_dataguard)(LOCAL_LISTENER=${NET_LISTENER_DG_ENTRY}))' scope=both;
EOSQL
else
 echo "nothing todo - standby" | tee -a ${LOGFILE}
fi

### add standby

setdb

echo "###[STEP]### Configure DB for startup ${DB_UNIQUE_NAME} " | tee -a ${LOGFILE}

if [[ "${DB_HOST}" != "${activenode}" ]]; then
  echo "Standby - configure db in crs" | tee -a ${LOGFILE}
  echo "${DB_HOME}/bin/srvctl add database -db ${DB_UNIQUE_NAME} -o ${DB_HOME} -spfile +DG1/${DB_UNIQUE_NAME}/spfile${DB_UNIQUE_NAME} -dbname ${DB_NAME} -role PHYSICAL_STANDBY -startoption \"READ ONLY\" " >> ${LOGFILE}
  ${DB_HOME}/bin/srvctl add database -db ${DB_UNIQUE_NAME} -o ${DB_HOME} -spfile +DG1/${DB_UNIQUE_NAME}/spfile${DB_UNIQUE_NAME} -dbname ${DB_NAME} -role PHYSICAL_STANDBY -startoption "READ ONLY" >> ${LOGFILE} 2>&1
else
  echo "Active - Set spfile in DBS folder" | tee -a ${LOGFILE}
  echo "spfile='+DG1/${DB_UNIQUE_NAME}/spfile${DB_UNIQUE_NAME}'" > ${DB_HOME}/dbs/init${DB_UNIQUE_NAME}.ora
fi



#################

function setDbCloneAccount() {

CLONE_DG_USER=$1
echo "###[STEP]### Setupe for PDB clone - C##$CLONE_DG_USER  " | tee -a ${LOGFILE}

echo "manage user C##$CLONE_DG_USER" >> ${LOGFILE} 2>&1
DGSNMP_EXIST=`echo "select count(*) DGSNMP from v\\$pwfile_users where username='C##$CLONE_DG_USER';" | sqlplus -s / as sysdba | grep -v -- '--' | grep -v DGSNMP | grep -v "^$" | cut -d" " -f2`

if [[ "$DGSNMP_EXIST" == "1" ]]; then
    echo "user C##${CLONE_DG_USER} exists" >> ${LOGFILE} 2>&1
    ${DB_HOME}/bin/sqlplus -L -S C##BA_DVACCOUNT/${ACCOUNT_PW} <<EOSQL >> ${LOGFILE} 2>&1 
      alter user C##$CLONE_DG_USER identified by "Caesar001!" account unlock;
EOSQL
  else
    ${DB_HOME}/bin/sqlplus -L -S C##BA_DVACCOUNT/${ACCOUNT_PW} <<EOSQL >> ${LOGFILE} 2>&1 
      create user C##$CLONE_DG_USER identified by "Caesar001!" account unlock default tablespace users profile C##BA_USER;
EOSQL
fi

${DB_HOME}/bin/sqlplus -L -S C##BA_DVACCOUNT/${ACCOUNT_PW} <<EOSQL >> ${LOGFILE} 2>&1 
      grant connect to C##$CLONE_DG_USER container=all;
      connect / as sysdba
      GRANT CREATE SESSION, CREATE PLUGGABLE DATABASE TO c##$CLONE_DG_USER CONTAINER=ALL;

EOSQL
}

function setDbDGAccount() {

MONITORING_DG_USER=$1
echo "###[STEP]### Monitoring setup - C##$MONITORING_DG_USER  " | tee -a ${LOGFILE}

echo "manage user C##$MONITORING_DG_USER" >> ${LOGFILE} 2>&1
DGSNMP_EXIST=`echo "select count(*) DGSNMP from v\\$pwfile_users where username='C##$MONITORING_DG_USER';" | sqlplus -s / as sysdba | grep -v -- '--' | grep -v DGSNMP | grep -v "^$" | cut -d" " -f2`

if [[ "$DGSNMP_EXIST" == "1" ]]; then
    echo "user C##${MONITORING_DG_USER} exists" >> ${LOGFILE} 2>&1
    ${DB_HOME}/bin/sqlplus -L -S C##BA_DVACCOUNT/${ACCOUNT_PW} <<EOSQL >> ${LOGFILE} 2>&1 
      alter user C##$MONITORING_DG_USER identified by "Casper001!" account unlock;
EOSQL
  else
    ${DB_HOME}/bin/sqlplus -L -S C##BA_DVACCOUNT/${ACCOUNT_PW} <<EOSQL >> ${LOGFILE} 2>&1 
      create user C##$MONITORING_DG_USER identified by "Casper001!" account unlock default tablespace users profile C##BA_USER;
EOSQL
fi

${DB_HOME}/bin/sqlplus -L -S C##BA_DVACCOUNT/${ACCOUNT_PW} <<EOSQL >> ${LOGFILE} 2>&1 
      grant connect to C##$MONITORING_DG_USER container=all;
      connect / as sysdba
      grant resource to C##$MONITORING_DG_USER container=all;
      grant unlimited tablespace to C##$MONITORING_DG_USER container=all;
      grant dba, sysdba,set container to C##$MONITORING_DG_USER container=all;
      grant sysdg to C##$MONITORING_DG_USER container=all;
EOSQL
}
  
#####

## account
setdb

MONITORING_USER_NAME=DGSNMP

if [[ $password == "true" ]]; then
  if [[ "${DATABASE_STATE}" == "READWRITE" ]]; then
    setDbDGAccount $MONITORING_USER_NAME
  fi
fi

##
## standby config
#### Passwordfile
#############

function copyPasswordInASM(){
echo "###[STEP]### Check Password in file on standby from active node " | tee -a ${LOGFILE}

ASM_PWD_FILE="+DG1/${DB_UNIQUE_NAME}/pwd${DB_NAME}"
PWD_FILE_DST_NAME="${DB_HOME}/dbs/orapw${DB_UNIQUE_NAME}"

setdb

DATABASE_RUNNING=`srvctl status database -d ${DB_UNIQUE_NAME} | grep -i "is running" | wc -l`

if [[ "$DATABASE_RUNNING" == "1" ]]; then
  echo "${DB_UNIQUE_NAME} is running no pwd file changes" | tee -a ${LOGFILE}
  if [ -f ${PWD_FILE_DST_NAME} ];then
    rm ${PWD_FILE_DST_NAME}
    echo " removed ${PWD_FILE_DST_NAME}" | tee -a ${LOGFILE}
  fi
  return 0
else
  echo "${DB_UNIQUE_NAME} is not running" | tee -a ${LOGFILE}
fi

setasm

if [ ! -f ${PWD_FILE_DST_NAME} ];then
    echo "please check pw file ${PWD_FILE_DST_NAME} - populate it from active node" | tee -a ${LOGFILE}
    echo "exit error" | tee -a ${LOGFILE}
    exit 1
else 
    setasm
    asmcmd pwcopy --dbuniquename ${DB_UNIQUE_NAME} ${PWD_FILE_DST_NAME} ${ASM_PWD_FILE} -f 
fi

}

#####

if [[ "${DB_HOST}" != "${activenode}" ]]; then
  copyPasswordInASM
fi

### Start
echo "###[STEP]### start standby " | tee -a ${LOGFILE}

setdb

function generateStandbyInit() {

setNetListenerEntry

ENTRY=$(echo "# init for standby ${DB_UNIQUE_NAME}, $(date '+%d.%m.%Y')
*.db_name='${DB_NAME}'
*.db_unique_name='${DB_UNIQUE_NAME}'
*.compatible='19.0.0.0.0'
*.local_listener='${1}'
*.LISTENER_NETWORKS='((NAME=network_default)(LOCAL_LISTENER=${NET_LISTENER_LOCAL_ENTRY}))','((NAME=network_dataguard)(LOCAL_LISTENER=${NET_LISTENER_DG_ENTRY}))'
")
}

INIT_ORA_FILE=${DB_HOME}/dbs/init${DB_UNIQUE_NAME}.ora

generateLocalListnerIdentifier ${PUBLIC_HOST} ${DB_HOST} ${PUBLIC_HOST}dg
echo "local listener ${ENTRY}" >> $LOGFILE

generateStandbyInit $ENTRY

if [[ "${DB_HOST}" != "${activenode}" ]]; then

  STANDBY_RUNNING=$(srvctl status database -d ${DB_UNIQUE_NAME} | grep 'is running' | grep -v grep | wc -l)
  if [[ $STANDBY_RUNNING -eq 0 ]];then
    echo "Standby Down - start it" | tee -a ${LOGFILE}
    echo "${ENTRY}" > ${INIT_ORA_FILE}
    STATE_DB=$(srvctl start database -d ${DB_UNIQUE_NAME} -startoption NOMOUNT)
    echo "state $STATE_DB "
  else 
    echo "Active Standby - set spfile in DBS folder" | tee -a ${LOGFILE}
    echo "if you want to recreate standby, remove it first" | tee -a ${LOGFILE}
    echo "spfile='+DG1/${DB_UNIQUE_NAME}/spfile${DB_UNIQUE_NAME}'" > ${DB_HOME}/dbs/init${DB_UNIQUE_NAME}.ora
  fi

else
  echo "active node - nothing todo" | tee -a ${LOGFILE}
fi


##++++++++++++++++++++++++++++++ duplicate 

function generateStaticConnectIdentifier() {
ENTRY=$(echo "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${2})(PORT=${hvport}))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=${1})))")
}

function generateCloneScript() {
OTHER_DB_UNIQUE_NAME=$1

ENTRY=$(echo "# Script to genreate STANDBY ${OTHER_DB_UNIQUE_NAME}, $(date '+%d.%m.%Y')
run {
allocate channel c1 device type disk;
allocate channel c2 device type disk;
allocate channel c3 device type disk;
allocate channel c4 device type disk;
allocate auxiliary channel c5 device type disk;
allocate auxiliary channel c6 device type disk;
allocate auxiliary channel c7 device type disk;
allocate auxiliary channel c8 device type disk;
duplicate target database to ${DB_NAME} from active database
section size 200G
spfile
set db_unique_name='${OTHER_DB_UNIQUE_NAME}'
set control_files='+DG1','+DG3'
set DG_BROKER_CONFIG_FILE1='+DG1/${OTHER_DB_UNIQUE_NAME}/DR1.DAT'
set DG_BROKER_CONFIG_FILE2='${DB_HOME}/dbs/${OTHER_DB_UNIQUE_NAME}_DR2.DAT'
reset log_archive_dest_2
reset log_archive_dest_3
reset log_archive_dest_4
reset log_archive_dest_5
reset log_archive_config
set standby_file_management='AUTO'
set db_create_file_dest='+DG1'
set db_create_online_log_dest_1='+DG1'
set db_recovery_file_dest='+DG3'
set cluster_database='false'
set db_recovery_file_dest_size='200T'
set audit_file_dest='/orabase/admin/${OTHER_DB_UNIQUE_NAME}/adump'
set diagnostic_dest='/orasw/oracle'
reset remote_listener
reset fal_client
reset fal_server
reset db_create_online_log_dest_2
reset service_names
reset dispatchers
reset sessions
reset log_buffer
;
}

")
}

function generateRmanRunScript() {
OTHER_DB_UNIQUE_NAME=$1
NEW_LOCAL_LISTENER_ENTRY=$2

ACTIVE_DB_HOST_IDENTIFIER=${activenode:1:4}
ACTIVE_DB_UNIQUE_NAME=${dgenv}d${ACTIVE_DB_HOST_IDENTIFIER}${dgnumber}

setNetListenerEntry

ENTRY=$(echo "# Script to genreate STANDBY ${OTHER_DB_UNIQUE_NAME}, $(date '+%d.%m.%Y')
run {
allocate channel c1 device type disk;
allocate channel c2 device type disk;
allocate channel c3 device type disk;
allocate channel c4 device type disk;
allocate auxiliary channel c5 device type disk;
allocate auxiliary channel c6 device type disk;
allocate auxiliary channel c7 device type disk;
allocate auxiliary channel c8 device type disk;
duplicate target database for standby from active database
section size 200G
spfile
set db_unique_name='${OTHER_DB_UNIQUE_NAME}'
set fal_server='${ACTIVE_DB_UNIQUE_NAME}'
set local_listener='${NEW_LOCAL_LISTENER_ENTRY}'
set LISTENER_NETWORKS='((NAME=network_default)(LOCAL_LISTENER=${NET_LISTENER_LOCAL_ENTRY}))','((NAME=network_dataguard)(LOCAL_LISTENER=${NET_LISTENER_DG_ENTRY}))'
set control_files='+DG1','+DG3'
set DG_BROKER_CONFIG_FILE1='+DG1/${OTHER_DB_UNIQUE_NAME}/DR1.DAT'
set DG_BROKER_CONFIG_FILE2='${DB_HOME}/dbs/${OTHER_DB_UNIQUE_NAME}_DR2.DAT'
reset log_archive_dest_2
reset log_archive_dest_3
reset log_archive_dest_4
reset log_archive_dest_5
reset service_names
reset dispatchers
set standby_file_management='AUTO'
set audit_file_dest='/orabase/admin/${OTHER_DB_UNIQUE_NAME}/adump'
;
}

")
}


function setHeaderinRmanScript(){

SCRIPT_SHELL_NAME_FUNCTION=$1

echo "#!/bin/bash" > ${SCRIPT_SHELL_NAME_FUNCTION}
setdbInFile ${SCRIPT_SHELL_NAME_FUNCTION}
echo "" >> ${SCRIPT_SHELL_NAME_FUNCTION}
echo "LOGFILE=${RMAN_LOGFILE}" >> ${SCRIPT_SHELL_NAME_FUNCTION}
echo "echo LOGFILE ${RMAN_LOGFILE}" >> ${SCRIPT_SHELL_NAME_FUNCTION}
echo "" >> ${SCRIPT_SHELL_NAME_FUNCTION}

}


function generateRmanScript() {

SCRIPT_SHELL_NAME_FUNCTION=$1
RMAN_SCRIPT_NAME_FUNCTION=$2

echo "$ENTRY" > ${RMAN_SCRIPT_NAME_FUNCTION}

BASH_SCRIPT=$(echo "$DB_HOME/bin/$RMAN_COMMAND <<EOF
@${RMAN_SCRIPT_NAME_FUNCTION}
EOF
")

echo "$BASH_SCRIPT" >> ${SCRIPT_SHELL_NAME_FUNCTION}
chmod u+x ${SCRIPT_SHELL_NAME_FUNCTION}
}

function setParameterOnPrimary() {

ACTIVE_DB_HOST_IDENTIFIER=${activenode:1:4}
ACTIVE_DB_UNIQUE_NAME=${dgenv}d${ACTIVE_DB_HOST_IDENTIFIER}${dgnumber}

ALL_DB_NAMES=unkown

for dghost in $(echo $dghosts | tr "," "\n")
do
    dghostname=$(echo $dghost| awk -F  ":" '{print $1}')

    OTHER_DG_DB_HOST_IDENTIFIER=${dghostname:1:4}
    OTHER_DG_DB_UNIQUE_NAME=${dgenv}d${OTHER_DG_DB_HOST_IDENTIFIER}${dgnumber}

    if [[ $ALL_DB_NAMES == "unkown" ]]; then
      ALL_DB_NAMES="$OTHER_DG_DB_UNIQUE_NAME"
    else
      ALL_DB_NAMES="${ALL_DB_NAMES},$OTHER_DG_DB_UNIQUE_NAME"
    fi

done

echo "\${ORACLE_HOME}/bin/sqlplus /@${ACTIVE_DB_UNIQUE_NAME} as sysdba <<EOSQL" >> ${1}
echo "alter system set log_archive_config='dg_config=($ALL_DB_NAMES)';" >> ${1}
echo "alter system set log_archive_dest_4='service=\"${DB_UNIQUE_NAME}_hv\", ASYNC optional compression=disable reopen=300 db_unique_name=\"${DB_UNIQUE_NAME}\", valid_for=(online_logfile,all_roles)';" >> ${1}
echo "EOSQL" >> ${1}
echo "" >> ${1}

}

function setParameterOnPrimaryAfterClone() {

ACTIVE_DB_HOST_IDENTIFIER=${activenode:1:4}
ACTIVE_DB_UNIQUE_NAME=${dgenv}d${ACTIVE_DB_HOST_IDENTIFIER}${dgnumber}

echo "\${ORACLE_HOME}/bin/sqlplus /@${ACTIVE_DB_UNIQUE_NAME} as sysdba <<EOSQL" >> ${1}
echo "alter system set log_archive_dest_4='';" >> ${1}
echo "EOSQL" >> ${1}
echo "" >> ${1}

}

function checkDgmWarning() {

echo "" >> ${1}

echo "function checkDgmWarning() { " >> ${1}

echo "echo \"Check broker in sync - check on success/warning in dgmgr output \" | tee -a \$LOGFILE " >> ${1}

echo "CHECK_DGM_SUCCESS=0" >> ${1}
echo "NUMBER_CHECKS=0" >> ${1}
echo "WAIT_TIME_SEC=10" >> ${1}

echo "\${ORACLE_HOME}/bin/dgmgrl /@${ACTIVE_DB_UNIQUE_NAME}_hv <<EOSQL | tee -a \$LOGFILE " >> ${1}
echo "show configuration" >> ${1}
echo "EOSQL" >> ${1}

echo "echo \"waiting 10 seconds \"" >> ${1}
echo "sleep 10" >> ${1}

echo "while : ; do " >> ${1}
echo "CHECK_DGM_SUCCESS=\`echo \"SHOW configuration;\" | dgmgrl /@${ACTIVE_DB_UNIQUE_NAME} | grep 'SUCCESS\|WARNING' | wc -l\` " >> ${1}
echo "   if [[ \$CHECK_DGM_SUCCESS == \"1\" ]]; then " >> ${1}
echo "      echo \"success dgmgr\"  | tee -a \$LOGFILE " >> ${1}
echo "      break" >> ${1}
echo "   else" >> ${1}
echo "      ((NUMBER_CHECKS++)) " >> ${1}
echo "      echo \"failure \$NUMBER_CHECKS (max 6) WAIT \$WAIT_TIME_SEC \" | tee -a \$LOGFILE " >> ${1}
echo "      if [[ \$NUMBER_CHECKS -gt 6 ]]; then " >> ${1}
echo "          echo \"exit\" | tee -a \$LOGFILE " >> ${1}
echo "          exit 1" >> ${1}
echo "      fi" >> ${1}
echo "      sleep \$WAIT_TIME_SEC " >> ${1}
echo "      let \"WAIT_TIME_SEC+=10\" " >> ${1}
echo "   fi" >> ${1}
echo "done" >> ${1}
echo "}" >> ${1}
echo "" >> ${1}

}


function checkDgmSuccess() {

echo "" >> ${1}

echo "function checkDgmSuccess() { " >> ${1}

echo "echo \"Check broker in sync - check on success in dgmgr output \" | tee -a \$LOGFILE " >> ${1}

echo "CHECK_DGM_SUCCESS=0" >> ${1}
echo "NUMBER_CHECKS=0" >> ${1}
echo "WAIT_TIME_SEC=30" >> ${1}

echo "echo \"waiting 30 seconds \" | tee -a \$LOGFILE" >> ${1}
echo "sleep 30" >> ${1}

echo "while : ; do " >> ${1}
echo "CHECK_DGM_SUCCESS=\`echo \"SHOW configuration;\" | dgmgrl /@${ACTIVE_DB_UNIQUE_NAME} | grep SUCCESS | wc -l\` " >> ${1}
echo "   if [[ \$CHECK_DGM_SUCCESS == \"1\" ]]; then " >> ${1}
echo "      echo \"success dgmgr\"  | tee -a \$LOGFILE " >> ${1}
echo "      break" >> ${1}
echo "   else" >> ${1}
echo "      \${ORACLE_HOME}/bin/dgmgrl /@${ACTIVE_DB_UNIQUE_NAME}_hv <<EOSQL | tee -a \$LOGFILE " >> ${1}
echo "      show configuration" >> ${1}
echo "EOSQL" >> ${1}
echo "      ((NUMBER_CHECKS++)) " >> ${1}
echo "      echo \"----> ERROR \" | tee -a \$LOGFILE " >> ${1}
echo "      echo \"failure \$NUMBER_CHECKS (max 20) WAIT \$WAIT_TIME_SEC \" | tee -a \$LOGFILE " >> ${1}
echo "      if [[ \$NUMBER_CHECKS -gt 20 ]]; then " >> ${1}
echo "          echo \"exit\" | tee -a \$LOGFILE " >> ${1}
echo "          exit 1" >> ${1}
echo "      fi" >> ${1}
echo "      sleep \$WAIT_TIME_SEC " >> ${1}
echo "      let \"WAIT_TIME_SEC+=30\" " >> ${1}
echo "   fi" >> ${1}
echo "done" >> ${1}
echo "}" >> ${1}
echo "" >> ${1}

}

function setParameterOnStandby() {

# echo "\${ORACLE_HOME}/bin/srvctl stop database -d ${DB_UNIQUE_NAME}" >> ${1}
# echo "\${ORACLE_HOME}/bin/srvctl start database -d ${DB_UNIQUE_NAME} -startoption mount" >> ${1}

ACTIVE_DB_HOST_IDENTIFIER=${activenode:1:4}
ACTIVE_DB_UNIQUE_NAME=${dgenv}d${ACTIVE_DB_HOST_IDENTIFIER}${dgnumber}

for dghost in $(echo $dghosts | tr "," "\n")
do
    
    dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
    
    if [[ "${dghostname}" == "${DB_HOST}" ]]; then

        dghvip=$(echo $dghost| awk -F  ":" '{print $2}')

        if [[ -z ${dghvip} ]]; then
          echo "missing dghvip ${dghostname}" 
          dghvip=${dghostname}
        fi

        generateStaticConnectIdentifier ${DB_UNIQUE_NAME}_hv ${dghvip}

        echo "echo add node to broker " >> ${1}
        echo "\${ORACLE_HOME}/bin/dgmgrl /@${ACTIVE_DB_UNIQUE_NAME}_hv <<EOSQL" >> ${1}
        echo "add database ${DB_UNIQUE_NAME} as connect identifier is ${DB_UNIQUE_NAME}_hv maintained as physical;" >> ${1}
        echo "EDIT DATABASE ${DB_UNIQUE_NAME} SET PROPERTY LogXptMode='${syncmode}';" >> ${1}
        echo "edit database ${DB_UNIQUE_NAME} set property StaticConnectIdentifier='${ENTRY}';" >> ${1}
        echo "enable configuration;" >> ${1}
        echo "EOSQL" >> ${1}

    fi
done

echo "echo \"Active - Set spfile in DBS folder\"" >> ${1}
echo "echo \"spfile='+DG1/${DB_UNIQUE_NAME}/spfile${DB_UNIQUE_NAME}'\" > \${ORACLE_HOME}/dbs/init${DB_UNIQUE_NAME}.ora " >> ${1}

# check success
echo "" >> ${1}
echo "checkDgmSuccess" >> ${1}
echo "" >> ${1}

echo "echo restart to open read only" >> ${1}
echo "\${ORACLE_HOME}/bin/srvctl stop database -d ${DB_UNIQUE_NAME}" >> ${1}
echo "\${ORACLE_HOME}/bin/srvctl start database -d ${DB_UNIQUE_NAME} " >> ${1}

# check success
echo "" >> ${1}
echo "checkDgmSuccess" >> ${1}
echo "" >> ${1}

echo "\${ORACLE_HOME}/bin/dgmgrl /@${ACTIVE_DB_UNIQUE_NAME}_hv <<EOSQL" >> ${1}
echo "EDIT DATABASE ${DB_UNIQUE_NAME} SET STATE='APPLY-ON';" >> ${1}
echo "EOSQL" >> ${1}

# check success
echo "" >> ${1}
echo "checkDgmSuccess" >> ${1}
echo "" >> ${1}

echo "\${ORACLE_HOME}/bin/dgmgrl /@${ACTIVE_DB_UNIQUE_NAME}_hv <<EOSQL" >> ${1}
echo "show configuration" >> ${1}
echo "EOSQL" >> ${1}

echo "echo - " >> ${1}
echo "echo wait 20 seconds" >> ${1}
echo "sleep 20" >> ${1}

echo "echo turn off apply to change flashback" >> ${1}

echo "\${ORACLE_HOME}/bin/dgmgrl /@${ACTIVE_DB_UNIQUE_NAME}_hv <<EOSQL" >> ${1}
echo "EDIT DATABASE ${DB_UNIQUE_NAME} SET STATE='APPLY-OFF';" >> ${1}
echo "EOSQL" >> ${1}

echo "echo - " >> ${1}
echo "echo wait 20 seconds" >> ${1}
echo "sleep 20" >> ${1}

echo "echo - " >> ${1}

## flashback
echo "echo add parameter changes for stdby to ${1}" >> ${1}
echo "echo turn flashback on ${DB_UNIQUE_NAME}" >> ${1}
echo "\${ORACLE_HOME}/bin/sqlplus / as sysdba <<EOSQL" >> ${1}
echo "alter database flashback on;" >> ${1}
echo "EOSQL" >> ${1}

echo "\${ORACLE_HOME}/bin/dgmgrl /@${ACTIVE_DB_UNIQUE_NAME}_hv <<EOSQL" >> ${1}
echo "EDIT DATABASE ${DB_UNIQUE_NAME} SET STATE='APPLY-ON';" >> ${1}
echo "enable configuration" >> ${1}
echo "EOSQL" >> ${1}

}

#######################
## Duplicate
#######################

echo "###[STEP]### generate duplicate scripts " | tee -a ${LOGFILE}

SCRIPT_SHELL_NAME=${SCRIPT_DIR}/duplicate.sh
SCRIPT_RMAN_NAME=${SCRIPT_DIR}/duplicate.rman

if [[ "${DB_HOST}" != "${activenode}" ]]; then

  ACTIVE_HOST_IDENTIFIER=${activenode:1:4}
  ACTIVE_DB_UNIQUE_NAME=${dgenv}d${ACTIVE_HOST_IDENTIFIER}${dgnumber} 
  RMAN_LOGFILE=${ORACLE_BASE}/admin/${DB_UNIQUE_NAME}/log/$(echo "install_rman_${DB_UNIQUE_NAME}_$(date '+Y%YM%mD%d_H%HM%MS%S').log")

  RMAN_COMMAND="rman target /@${ACTIVE_DB_UNIQUE_NAME}_HV auxiliary /@${DB_UNIQUE_NAME}_HV LOG=${RMAN_LOGFILE} APPEND"
  
  generateLocalListnerIdentifier ${PUBLIC_HOST} ${DB_HOST} ${PUBLIC_HOST}dg
  LOCAL_LISTENER_ENTRY=${ENTRY}

  echo "generateRmanRunScript ${DB_UNIQUE_NAME} ${LOCAL_LISTENER_ENTRY}" >> $LOGFILE

  # Headers
  setHeaderinRmanScript ${SCRIPT_SHELL_NAME}
  setHeaderinRmanScript ${SCRIPT_DIR}/clone.sh

  checkDgmSuccess ${SCRIPT_SHELL_NAME}
  checkDgmWarning ${SCRIPT_SHELL_NAME}

  # Prepare Primary for duplicate
  setParameterOnPrimary ${SCRIPT_SHELL_NAME}

  # check success
  echo "" >> ${SCRIPT_SHELL_NAME}
  echo "checkDgmWarning" >> ${SCRIPT_SHELL_NAME}
  echo "" >> ${SCRIPT_SHELL_NAME}

  # The Clone Process
  generateRmanRunScript ${DB_UNIQUE_NAME} ${LOCAL_LISTENER_ENTRY}
  generateRmanScript ${SCRIPT_SHELL_NAME} ${SCRIPT_RMAN_NAME}

  generateCloneScript ${DB_UNIQUE_NAME}
  generateRmanScript ${SCRIPT_DIR}/clone.sh ${SCRIPT_DIR}/clone.rman

  echo "" >> ${SCRIPT_SHELL_NAME}

  ## After Clone
  setParameterOnPrimaryAfterClone ${SCRIPT_SHELL_NAME}

  ## TRun on broker

  setParameterOnStandby ${SCRIPT_SHELL_NAME}

  echo "to delete old stdby use " | tee -a ${LOGFILE}
  echo "--> ${SCRIPT_DIR}/delete_dg_stdby.bash ${dgenv} ${dgnumber}" | tee -a ${LOGFILE}
  echo "--> restart this script $0 $1 $2 " | tee -a ${LOGFILE}

  echo "to duplicate it " | tee -a ${LOGFILE}
  echo "--> ${SCRIPT_DIR}/duplicate.sh" | tee -a ${LOGFILE}
  
fi

#### Wallet
#### Functions

function generateSQLNetEntry() {
echo "SSL_CLIENT_AUTHENTICATION = FALSE" >> ${1}
echo "SSL_VERSION = 0" >> ${1}
echo "" >> ${1}
echo "SQLNET.INBOUND_CONNECT_TIMEOUT = 1200" >> ${1}
echo "SQLNET.OUTBOUND_CONNECT_TIMEOUT = 1200" >> ${1}
echo "SQLNET.EXPIRE_TIME=1" >> ${1}
echo "USE_NS_PROBES_FOR_DCD=TRUE" >> ${1}
echo "" >> ${1}
echo "SQLNET.ENCRYPTION_SERVER=REQUIRED" >> ${1}
echo "DIAG_ADR_ENABLED=OFF" >> ${1}

ENTRY=$(echo "WALLET_LOCATION=
   (SOURCE =
     (METHOD = FILE)
     (METHOD_DATA =
       (DIRECTORY = ${WALLET_DIRECTORY})
     )
   )
SQLNET.WALLET_OVERRIDE = TRUE
")
echo "${ENTRY}" >> ${1}
echo "" >> ${1}
}

function addDBsToWallet(){
for dghost in $(echo $dghosts | tr "," "\n")
do
  dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
  OTHER_HOST_IDENTIFIER=${dghostname:1:4}
  OTHER_DB_UNIQUE_NAME=${dgenv}d${OTHER_HOST_IDENTIFIER}${dgnumber} 
  ${DB_HOME}/bin/mkstore -wrl ${WALLET_DIRECTORY} -deleteCredential ${OTHER_DB_UNIQUE_NAME} >> /dev/null 2>&1
  ${DB_HOME}/bin/mkstore -wrl ${WALLET_DIRECTORY} -createCredential ${OTHER_DB_UNIQUE_NAME} sys ${SYS_PASSWORD} >> /dev/null 2>&1
  ${DB_HOME}/bin/mkstore -wrl ${WALLET_DIRECTORY} -deleteCredential ${OTHER_DB_UNIQUE_NAME}_hv >> /dev/null 2>&1
  ${DB_HOME}/bin/mkstore -wrl ${WALLET_DIRECTORY} -createCredential ${OTHER_DB_UNIQUE_NAME}_hv sys ${SYS_PASSWORD} >> /dev/null 2>&1
  # cdb wallet Entry
  ${DB_HOME}/bin/mkstore -wrl ${WALLET_DIRECTORY} -deleteCredential ${DB_NAME} >> /dev/null 2>&1
  ${DB_HOME}/bin/mkstore -wrl ${WALLET_DIRECTORY} -createCredential ${DB_NAME} sys ${SYS_PASSWORD} >> /dev/null 2>&1
done
}

####################################

echo "###[STEP]### Wallet setup " | tee -a ${LOGFILE}

lead='### BEGIN GENERATED CONTENT WALLET DATAGUARD'
tail='### END GENERATED CONTENT WALLET DATAGUARD'

if [[ ! -d "${WALLET_DIRECTORY}" ]] ;
then
    mkdir ${WALLET_DIRECTORY}
fi

if [[ ! -f "${SQLNET_ORA}" ]] ; then
    touch ${SQLNET_ORA}
else
    # check if its oiginal
    if ! grep -q "$lead" "${SQLNET_ORA}"; then
	echo "recreating ${SQLNET_ORA}" >> ${LOGFILE}
	backup_file ${SQLNET_ORA}
	echo "# INIT file out of cr_dg.bash" > ${SQLNET_ORA}
	echo "NAMES.DIRECTORY_PATH = (TNSNAMES, EZCONNECT)" >> ${SQLNET_ORA}
    fi
fi

if [[ $password == "true" ]]; then
  # create Wallet
  ${DB_HOME}/bin/orapki wallet create -wallet ${WALLET_DIRECTORY} -auto_login_only >> /dev/null 2>&1
  # add keys
  addDBsToWallet
  echo "Get details: ${DB_HOME}/bin/mkstore -wrl /orasw/oracle/wallet -listCredential"
else
  echo "wallet stay untouched"
fi

backup_file ${SQLNET_ORA}

# delete old comments
sed -i "/^$lead$/,/^$tail$/d" ${SQLNET_ORA}

echo "${lead}" >> ${SQLNET_ORA}
generateSQLNetEntry  ${SQLNET_ORA}
echo "${tail}" >> ${SQLNET_ORA}


##########
#### Broker

function resetLogArchiveDests(){
for dghost in $(echo $dghosts | tr "," "\n")
do
  dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
       
  RESET_HOST_IDENTIFIER=${dghostname:1:4}
  RESET_DB_UNIQUE_NAME=${dgenv}d${RESET_HOST_IDENTIFIER}${dgnumber} 

  echo "${DB_HOME}/bin/sqlplus -L -S /@${RESET_DB_UNIQUE_NAME} as sysdba <<EOSQL 2>&1" >> ${1}
  echo "alter system set log_archive_dest_2='';" >> ${1}  
  echo "alter system reset log_archive_dest_2;" >> ${1}  
  echo "alter system set log_archive_dest_3='';" >> ${1}  
  echo "alter system reset log_archive_dest_3;" >> ${1}  
  echo "alter system set log_archive_dest_4='';" >> ${1} 
  echo "alter system reset log_archive_dest_4;" >> ${1}   
  echo "alter system set log_archive_dest_5='';" >> ${1}
  echo "alter system reset log_archive_dest_5;" >> ${1}  
  echo "EOSQL" >> ${1}
  echo "" >> ${1}
done 
}

function addRemoteDBs(){

LOCAL_DG_ENTRIES=''

for dghost in $(echo $dghosts | tr "," "\n")
do
    dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
    dghvip=$(echo $dghost| awk -F  ":" '{print $2}')

    if [[ -z ${dghvip} ]]; then
      echo "missing dghvip ${dghostname}" 
      dghvip=${dghostname}
    fi
      
    OTHER_HOST_IDENTIFIER=${dghostname:1:4}
    OTHER_DB_UNIQUE_NAME=${dgenv}d${OTHER_HOST_IDENTIFIER}${dgnumber} 
    
    if [[ "${DB_HOST}" != "${dghostname}" ]]; then
      DGMBG_ADD_DB=$(echo "add database ${OTHER_DB_UNIQUE_NAME} as connect identifier is ${OTHER_DB_UNIQUE_NAME}_hv maintained as physical;" )
    fi
    echo "$DGMBG_ADD_DB" >> $1

    # REMOTE_SYNC_DB_STANDBY
    #if [[ "${OTHER_DB_UNIQUE_NAME}" != "${DG_DBNAMES_4}" ]]; then
    LOG_MODE=$(echo "EDIT DATABASE ${OTHER_DB_UNIQUE_NAME} SET PROPERTY LogXptMode='${syncmode}';")
    echo  "$LOG_MODE" >> $1
    #fi

    generateStaticConnectIdentifier ${OTHER_DB_UNIQUE_NAME}_HV ${dghvip}
    echo "edit database ${OTHER_DB_UNIQUE_NAME} set property StaticConnectIdentifier='${ENTRY}';" >> ${1}
 
done

if [[ $DG_HOST_NUMBERS -eq "4" ]]; then
  echo "EDIT DATABASE ${DG_DBNAMES_1} SET PROPERTY RedoRoutes='(LOCAL : ${DG_DBNAMES_2} ${syncmode}, (${DG_DBNAMES_3} priority=1, ${DG_DBNAMES_4} priority=2 ${syncmode}))(${DG_DBNAMES_3} : ${DG_DBNAMES_4} ASYNC)';" >> ${1}
  echo "EDIT DATABASE ${DG_DBNAMES_2} SET PROPERTY RedoRoutes='(LOCAL : ${DG_DBNAMES_1} ${syncmode}, (${DG_DBNAMES_3} priority=1, ${DG_DBNAMES_4} priority=2 ${syncmode}))(${DG_DBNAMES_3} : ${DG_DBNAMES_4} ASYNC)';" >> ${1}
  echo "EDIT DATABASE ${DG_DBNAMES_3} SET PROPERTY RedoRoutes='(${DG_DBNAMES_1} : ${DG_DBNAMES_4} ASYNC)(${DG_DBNAMES_2} : ${DG_DBNAMES_4} ASYNC)';" >> ${1}
fi

}

checkBrokerActiveIsLocal () {

  ACTIVE_DB_HOST_IDENTIFIER=${activenode:1:4}
  ACTIVE_DB_UNIQUE_NAME=${dgenv}d${ACTIVE_DB_HOST_IDENTIFIER}${dgnumber}

  echo "" >> ${1}
  echo "# Check if primary is on local node" >> ${1}


  echo "GET_INSTANCE_NAME=\`echo \"select instance_name INSTANCE_NAME from v\\\\\$instance;\" | sqlplus -s / as sysdba | grep -v -- '--' | grep -v INSTANCE_NAME | grep -v \"^$\" | cut -d\" \" -f2\` " >> ${1}
  
  echo "if [[ \"\$GET_INSTANCE_NAME\" != \"$ACTIVE_DB_UNIQUE_NAME\" ]];then " >> ${1}
  echo "  echo \"Instance:             \$GET_INSTANCE_NAME\"" >> ${1}
  echo "  echo \"Active  :             $ACTIVE_DB_UNIQUE_NAME\"" >> ${1}
  echo "  echo \"Please Check Active in Config and rerun cr_dg.bash \"" >> ${1}
  echo "  exit 1" >> ${1}
  echo "fi" >> ${1}

  echo "if [[ \"\$GET_INSTANCE_NAME\" != \"$DB_UNIQUE_NAME\" ]];then " >> ${1}
  echo "  echo \"\$GET_INSTANCE_NAME is not like configured instance $DB_UNIQUE_NAME\"" >> ${1}
  echo "  echo \"Please Check Config and rerun cr_dg.bash \"" >> ${1}
  echo "  exit 1" >> ${1}
  echo "fi" >> ${1}

  echo "echo \"\$GET_INSTANCE_NAME ($DB_UNIQUE_NAME) is active Node\"" >> ${1}


  echo "EXIST_DATABASE_ROLE=\`echo \"select database_role DATABASE_ROLE from v\\\\\$database;\" | sqlplus -s / as sysdba | grep -v -- '--' | grep -v DATABASE_ROLE | grep -v \"^$\" | cut -d\" \" -f2\` " >> ${1}
  echo "if [[ \"\$EXIST_DATABASE_ROLE\" != \"PRIMARY\" ]];then " >> ${1}
  echo "  echo \"ROLE:             $EXIST_DATABASE_ROLE\"" >> ${1}
  echo "  echo \"Please Check Role must be Primary\"" >> ${1}
  echo "  exit 1" >> ${1}
  echo "fi" >> ${1}

  echo "echo \"Check success local instance has Primary Role \"" >> ${1}

  echo "" >> ${1}

}

echo "###[STEP]### Broker setup " | tee -a ${LOGFILE}

setdb

${DB_HOME}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE} 2>&1
alter system set dg_broker_start=true scope=both;
EOSQL

DGMGR_CONFIGURATION=$(echo "create configuration ${DB_NAME}_config as primary database is ${DB_UNIQUE_NAME} connect identifier is ${DB_UNIQUE_NAME}_hv;
")

echo "#!/bin/bash" > ${SCRIPT_DIR}/broker.sh
setdbInFile ${SCRIPT_DIR}/broker.sh

#check primary is accessible

checkBrokerActiveIsLocal ${SCRIPT_DIR}/broker.sh

echo "dgmgrl / <<EOSQL 2>&1" >> ${SCRIPT_DIR}/broker.sh
echo "disable configuration" >> ${SCRIPT_DIR}/broker.sh
echo "remove configuration" >> ${SCRIPT_DIR}/broker.sh
echo "EOSQL" >> ${SCRIPT_DIR}/broker.sh
echo "" >> ${SCRIPT_DIR}/broker.sh

## reset archive dests
resetLogArchiveDests ${SCRIPT_DIR}/broker.sh
echo "" >> ${SCRIPT_DIR}/broker.sh

echo "dgmgrl / <<EOSQL 2>&1" >> ${SCRIPT_DIR}/broker.sh
echo "$DGMGR_CONFIGURATION" >> ${SCRIPT_DIR}/broker.sh

# set sync mode
if [[ "${syncmode}" == "ASYNC" ]]; then 
  echo "EDIT CONFIGURATION SET PROTECTION MODE AS MAXPERFORMANCE;" >> ${SCRIPT_DIR}/broker.sh
else
  echo "EDIT CONFIGURATION SET PROTECTION MODE AS MAXAVAILABILITY;" >> ${SCRIPT_DIR}/broker.sh
fi

addRemoteDBs ${SCRIPT_DIR}/broker.sh

echo "enable configuration" >> ${SCRIPT_DIR}/broker.sh
echo "EOSQL" >> ${SCRIPT_DIR}/broker.sh
echo "" >> ${SCRIPT_DIR}/broker.sh

echo "# dgmgrl sys/<password>@${DB_UNIQUE_NAME}_hv <<EOSQL 2>&1" >> ${SCRIPT_DIR}/broker.sh
echo "# VALIDATE NETWORK CONFIGURATION FOR all" >> ${SCRIPT_DIR}/broker.sh
echo "# EOSQL" >> ${SCRIPT_DIR}/broker.sh

chmod u+x ${SCRIPT_DIR}/broker.sh
echo "broker script: ${SCRIPT_DIR}/broker.sh"

#######################
### generate AWR config in standby

function generateDBLinks() {

echo "${DB_HOME}/bin/sqlplus -L -S /@${DB_UNIQUE_NAME} as sysdba <<EOSQL 2>&1" | tee -a $1 $2 > /dev/null

for dghost in $(echo $dghosts | tr "," "\n")
do
  dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
  PRIMARY_HOST_IDENTIFIER=${dghost:1:4}
  PRIMARY_DB_UNIQUE_NAME=${dgenv}d${PRIMARY_HOST_IDENTIFIER}${dgnumber}

  for dghost_remote in $(echo $dghosts | tr "," "\n")
  do
      dghostname_remote=$(echo $dghost_remote| awk -F  ":" '{print $1}')
      REMOTE_HOST_IDENTIFIER=${dghostname_remote:1:4}
      REMOTE_DB_UNIQUE_NAME=${dgenv}d${REMOTE_HOST_IDENTIFIER}${dgnumber}

      if [[ "${PRIMARY_DB_UNIQUE_NAME}" != "${REMOTE_DB_UNIQUE_NAME}" ]]; then
        echo "drop database link DBL_${PRIMARY_DB_UNIQUE_NAME}_to_${REMOTE_DB_UNIQUE_NAME} ;" >> $2
        echo "create database link DBL_${PRIMARY_DB_UNIQUE_NAME}_to_${REMOTE_DB_UNIQUE_NAME} connect to \"SYS\\\$UMF\" identified by \"\${AWR_UMF_GENERATE_PASSWORD}\" using '${REMOTE_DB_UNIQUE_NAME}_HV';" >> $1
        echo "select * from dual@DBL_${PRIMARY_DB_UNIQUE_NAME}_to_${REMOTE_DB_UNIQUE_NAME} ;" >> $1
      fi
  done
done

echo "EOSQL" | tee -a $1 $2 > /dev/null
echo "" | tee -a $1 $2 > /dev/null

}

function generateAWRTopology() {

for dghost in $(echo $dghosts | tr "," "\n")
do
  dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
  DB_HOST_IDENTIFIER=${dghostname:1:4}
  GET_DB_UNIQUE_NAME=${dgenv}d${DB_HOST_IDENTIFIER}${dgnumber}
  LOCAL_DB_UNIQUE_NAME=${DB_UNIQUE_NAME}

  if [[ "${dghostname}" == "${DB_HOST}" ]]; then
    echo "${DB_HOME}/bin/sqlplus -L -S /@${LOCAL_DB_UNIQUE_NAME} as sysdba <<EOSQL 2>&1" | tee -a $1 $2 > /dev/null
    echo "alter system set \"_umf_remote_enabled\"=TRUE scope=BOTH;" | tee -a $2 > /dev/null
    echo "exec DBMS_UMF.UNCONFIGURE_NODE;" | tee -a $2 > /dev/null
    echo "exec DBMS_UMF.configure_node ('${LOCAL_DB_UNIQUE_NAME}');" | tee -a $1 > /dev/null
    echo "EOSQL" | tee -a $1 $2 > /dev/null
    echo "" | tee -a $1 $2 > /dev/null
  else 
    echo "${DB_HOME}/bin/sqlplus -L -S /@${GET_DB_UNIQUE_NAME} as sysdba <<EOSQL 2>&1" | tee -a $1 $2 > /dev/null
    echo "alter system set \"_umf_remote_enabled\"=TRUE scope=BOTH;" | tee -a $2 > /dev/null
    echo "exec DBMS_UMF.UNCONFIGURE_NODE;" | tee -a $2 > /dev/null
    echo "exec DBMS_UMF.configure_node ('${GET_DB_UNIQUE_NAME}', 'DBL_${GET_DB_UNIQUE_NAME}_to_${LOCAL_DB_UNIQUE_NAME}');" | tee -a $1 > /dev/null
    echo "EOSQL" | tee -a $1 $2 > /dev/null
    echo "" | tee -a $1 $2 > /dev/null
  fi

  
done

}

function generateTopologyLinks() {
echo "${DB_HOME}/bin/sqlplus -L -S /@${DB_UNIQUE_NAME} as sysdba <<EOSQL 2>&1" | tee -a $1 $3 > /dev/null
echo "-- select 'generate topo links' from dual;" | tee -a $1 $3 > /dev/null

failoveruniquename=unknown

for dghost in $(echo $dghosts | tr "," "\n")
do
  dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
  PRIMARY_HOST_IDENTIFIER=${dghost:1:4}
  PRIMARY_DB_UNIQUE_NAME=${dgenv}d${PRIMARY_HOST_IDENTIFIER}${dgnumber}

  if [[ "${dghostname}" != "${DB_HOST}" ]]; then
    for dghost_remote in $(echo $dghosts | tr "," "\n")
    do
        dghostname_remote=$(echo $dghost_remote| awk -F  ":" '{print $1}')
        REMOTE_HOST_IDENTIFIER=${dghostname_remote:1:4}
        REMOTE_DB_UNIQUE_NAME=${dgenv}d${REMOTE_HOST_IDENTIFIER}${dgnumber}
        if [[ "${dghostname_remote}" != "${DB_HOST}" ]]; then
          if [[ $failoveruniquename == "unknown" ]]; then
            failoveruniquename=${REMOTE_DB_UNIQUE_NAME}
          fi
          if [[ "${PRIMARY_DB_UNIQUE_NAME}" != "${REMOTE_DB_UNIQUE_NAME}" ]]; then
              if [[ "$failoveruniquename" == "${REMOTE_DB_UNIQUE_NAME}" ]]; then
                echo "exec DBMS_UMF.create_link('T_${DB_NAME}','${PRIMARY_DB_UNIQUE_NAME}','${REMOTE_DB_UNIQUE_NAME}' ,'DBL_${PRIMARY_DB_UNIQUE_NAME}_to_${REMOTE_DB_UNIQUE_NAME}','DBL_${REMOTE_DB_UNIQUE_NAME}_to_${PRIMARY_DB_UNIQUE_NAME}');" | tee -a $1 $3 > /dev/null
              fi
          fi
        fi
    done
  fi
done
echo "EOSQL" | tee -a $1 $3 > /dev/null
echo "" | tee -a $1 $3 > /dev/null
}

function createAWRTopology() {
# /@${DB_UNIQUE_NAME}
#SYS\$UMF/${AWR_UMF_PASSWORD}@${DB_UNIQUE_NAME}
echo "echo \"AWR topology\"" | tee -a $1 $2 > /dev/null
echo "${DB_HOME}/bin/sqlplus -L -S /@${DB_UNIQUE_NAME} as sysdba <<EOSQL 2>&1" | tee -a $1 $2 > /dev/null

for dghost in $(echo $dghosts | tr "," "\n")
do
  dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
  DB_HOST_IDENTIFIER=${dghostname:1:4}
  GET_DB_UNIQUE_NAME=${dgenv}d${DB_HOST_IDENTIFIER}${dgnumber}
  LOCAL_DB_UNIQUE_NAME=${DB_UNIQUE_NAME} 
  
  if [[ "${dghostname}" != "${DB_HOST}" ]]; then
    echo "exec DBMS_UMF.unregister_node ('T_${DB_NAME}','${GET_DB_UNIQUE_NAME}');" | tee -a $2 > /dev/null
  fi
done
echo "exec DBMS_UMF.DROP_TOPOLOGY ('T_${DB_NAME}');" | tee -a $2 > /dev/null
echo "exec DBMS_UMF.create_topology ('T_${DB_NAME}');" | tee -a $1 > /dev/null

failovernode=unknown

for dghost in $(echo $dghosts | tr "," "\n")
do
  dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
  DB_HOST_IDENTIFIER=${dghostname:1:4}
  GET_DB_UNIQUE_NAME=${dgenv}d${DB_HOST_IDENTIFIER}${dgnumber}
  LOCAL_DB_UNIQUE_NAME=${DB_UNIQUE_NAME} 
  
  if [[ "${dghostname}" != "${DB_HOST}" ]]; then
    # echo "exec DBMS_UMF.unregister_node ('T_${DB_NAME}','${GET_DB_UNIQUE_NAME}');" | tee -a $2 > /dev/null
    if [[ $failovernode == "unknown" ]]; then
      echo "exec DBMS_UMF.register_node ('T_${DB_NAME}','${GET_DB_UNIQUE_NAME}', 'DBL_${LOCAL_DB_UNIQUE_NAME}_to_${GET_DB_UNIQUE_NAME}' ,'DBL_${GET_DB_UNIQUE_NAME}_to_${LOCAL_DB_UNIQUE_NAME}','TRUE','TRUE');" | tee -a $1 > /dev/null
      failovernode=${dghostname}
    else
      echo "exec DBMS_UMF.register_node ('T_${DB_NAME}','${GET_DB_UNIQUE_NAME}', 'DBL_${LOCAL_DB_UNIQUE_NAME}_to_${GET_DB_UNIQUE_NAME}' ,'DBL_${GET_DB_UNIQUE_NAME}_to_${LOCAL_DB_UNIQUE_NAME}','TRUE','FALSE');" | tee -a $1 > /dev/null
    fi
  fi
done

# echo "exec DBMS_UMF.DROP_TOPOLOGY ('T_${DB_NAME}');" >> $2

echo "EOSQL" | tee -a ${1} ${2} > /dev/null
echo "" | tee -a ${1} ${2} > /dev/null
echo "echo \"failovernode is $failovernode (the first node found) \"" | tee -a $1 > /dev/null
echo "" | tee -a $1 $2 > /dev/null
}

function registerAWRRepository() {
echo "${DB_HOME}/bin/sqlplus -L -S /@${DB_UNIQUE_NAME} as sysdba <<EOSQL 2>&1" | tee -a $1 $2 > /dev/null
for dghost in $(echo $dghosts | tr "," "\n")
do
  dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
  DB_HOST_IDENTIFIER=${dghostname:1:4}
  GET_DB_UNIQUE_NAME=${dgenv}d${DB_HOST_IDENTIFIER}${dgnumber}
  LOCAL_DB_UNIQUE_NAME=${DB_UNIQUE_NAME}

  if [[ "${dghostname}" != "${DB_HOST}" ]]; then
    echo "exec DBMS_WORKLOAD_REPOSITORY.unregister_remote_database('${GET_DB_UNIQUE_NAME}','T_${DB_NAME}',TRUE);" | tee -a $2 > /dev/null
    echo "exec DBMS_WORKLOAD_REPOSITORY.register_remote_database(node_name=>'${GET_DB_UNIQUE_NAME}',topology_name=>'T_${DB_NAME}');" | tee -a $1 > /dev/null
  fi
done
echo "EOSQL" | tee -a $1 $2 > /dev/null
echo "" | tee -a $1 $2 > /dev/null
}

function readPasswordInFile(){
   FILE_NAME_TO_WRITE=$1
   echo "read -p \"enter sys/system password for UMF Connect - SYS Password creation[[ (return) = default (oracle)]]: \" AWR_UMF_GENERATE_PASSWORD" >> ${FILE_NAME_TO_WRITE}
   echo "[[ -z \${AWR_UMF_GENERATE_PASSWORD} ]] && AWR_UMF_GENERATE_PASSWORD=oracle" >> ${FILE_NAME_TO_WRITE}
   echo "" >> ${FILE_NAME_TO_WRITE}
}

function addFormatToSQLFiles(){
  echo "set line 170" >> ${1}
  echo "set pagesize 270" >> ${1}
  echo "col state format a20" >> ${1}
  echo "col topology_name format a15" >> ${1}
  echo "col node_name format a15" >> ${1}
  echo "col CREATION format a15" >> ${1}
  echo "col snap_start format a25" >> ${1}
  echo "col retention format a20" >> ${1}
  echo "-- " >> ${1}
}



echo "###[STEP]### AWR Standby setup " | tee -a ${LOGFILE}

AWR_GENERATE_DBLINKS=${SCRIPT_DIR}/configure_standby_awr_dblinks.sh
AWR_GENERATE_AWR_ONLY=${SCRIPT_DIR}/configure_standby_awr_topology.sh
AWR_RECREATE_AWR=${SCRIPT_DIR}/recreate_standby_awr_topology.sh
AWR_DELETE_SCRIPT=${SCRIPT_DIR}/remove_standby_awr_topology.sh
AWR_SWITCH_SCRIPT=${SCRIPT_DIR}/switch_awr_topology.sh
AWR_TMP_SCRIPT=${SCRIPT_DIR}/tmp_awr_topology.sh
AWR_UMF_PASSWORD=${SYS_PASSWORD}

echo "#!/bin/bash" > ${AWR_GENERATE_DBLINKS}
setdbInFile ${AWR_GENERATE_DBLINKS}
echo "" >> ${AWR_GENERATE_DBLINKS}
readPasswordInFile ${AWR_GENERATE_DBLINKS}

echo "#!/bin/bash" > ${AWR_GENERATE_AWR_ONLY}
setdbInFile ${AWR_GENERATE_AWR_ONLY}
echo "" >> ${AWR_GENERATE_AWR_ONLY}

echo "#!/bin/bash" > ${AWR_DELETE_SCRIPT}
setdbInFile ${AWR_DELETE_SCRIPT}
echo "" >> ${AWR_DELETE_SCRIPT}

echo "#!/bin/bash" > ${AWR_RECREATE_AWR}
setdbInFile ${AWR_RECREATE_AWR}
echo "" >> ${AWR_RECREATE_AWR}

echo "#!/bin/bash" > ${AWR_SWITCH_SCRIPT}
setdbInFile ${AWR_SWITCH_SCRIPT}
echo "" >> ${AWR_SWITCH_SCRIPT}

echo "echo \"switch to T_${DB_NAME}\"" >> ${AWR_SWITCH_SCRIPT}

echo "${DB_HOME}/bin/sqlplus -L -S /@${DB_UNIQUE_NAME} as sysdba <<EOSQL 2>&1" | tee -a ${AWR_SWITCH_SCRIPT} > /dev/null
echo "EXEC DBMS_UMF.SWITCH_DESTINATION ('T_${DB_NAME}', force_switch=>FALSE);" | tee -a ${AWR_SWITCH_SCRIPT} > /dev/null
echo "EOSQL" | tee -a ${AWR_SWITCH_SCRIPT} > /dev/null

## account
setdb


if [[ $password == "true" ]]; then
echo "alter user sys\$umf " >> ${LOGFILE}
${DB_HOME}/bin/sqlplus -L -S C##BA_DVACCOUNT/"${ACCOUNT_PW}" <<EOSQL >> ${LOGFILE} 2>&1 
alter user "SYS\$UMF" identified by "${AWR_UMF_PASSWORD}" account unlock;
EOSQL
else
  echo "user sys\$umf unchanged" >> ${LOGFILE}
fi

#echo "${DB_HOME}/bin/sqlplus -L -S /@${DB_UNIQUE_NAME} as sysdba <<EOSQL 2>&1" >> ${AWR_GENERATE_DBLINKS}
#echo "alter system set \"_umf_remote_enabled\"=TRUE scope=BOTH;" >> ${AWR_GENERATE_DBLINKS}
#echo "select username,common,account_status from dba_users where username like 'SYS\$UMF%';" >> ${AWR_GENERATE_DBLINKS}
#echo "EOSQL" >> ${AWR_GENERATE_DBLINKS}
#echo "" >> ${AWR_GENERATE_DBLINKS}

## DBLINKS
generateDBLinks ${AWR_GENERATE_DBLINKS} ${AWR_TMP_SCRIPT}

## Topology
generateAWRTopology ${AWR_GENERATE_AWR_ONLY} ${AWR_TMP_SCRIPT}
createAWRTopology ${AWR_GENERATE_AWR_ONLY} ${AWR_TMP_SCRIPT}
registerAWRRepository ${AWR_GENERATE_AWR_ONLY} ${AWR_TMP_SCRIPT}
generateTopologyLinks ${AWR_GENERATE_AWR_ONLY} ${AWR_TMP_SCRIPT}

# delete recreate
registerAWRRepository ${AWR_TMP_SCRIPT} ${AWR_RECREATE_AWR}
createAWRTopology ${AWR_TMP_SCRIPT} ${AWR_RECREATE_AWR} 
generateAWRTopology ${AWR_TMP_SCRIPT} ${AWR_RECREATE_AWR}

# add again
generateAWRTopology ${AWR_RECREATE_AWR} ${AWR_TMP_SCRIPT}
createAWRTopology ${AWR_RECREATE_AWR} ${AWR_TMP_SCRIPT}
registerAWRRepository ${AWR_RECREATE_AWR} ${AWR_TMP_SCRIPT}
generateTopologyLinks ${AWR_RECREATE_AWR} ${AWR_TMP_SCRIPT}

# for Delete
registerAWRRepository ${AWR_TMP_SCRIPT} ${AWR_DELETE_SCRIPT}
createAWRTopology ${AWR_TMP_SCRIPT} ${AWR_DELETE_SCRIPT} 
generateAWRTopology ${AWR_TMP_SCRIPT} ${AWR_DELETE_SCRIPT}
generateDBLinks ${AWR_TMP_SCRIPT} ${AWR_DELETE_SCRIPT}

echo "${DB_HOME}/bin/sqlplus -L -S /@${DB_UNIQUE_NAME} as sysdba <<EOSQL 2>&1" >> ${AWR_GENERATE_AWR_ONLY}

addFormatToSQLFiles ${AWR_GENERATE_AWR_ONLY}

echo "select * from dba_umf_topology;" >> ${AWR_GENERATE_AWR_ONLY}
echo "select TOPOLOGY_NAME, NODE_NAME, NODE_ID, NODE_TYPE from umf\\\$_registration;" >> ${AWR_GENERATE_AWR_ONLY}
echo "select * from dba_umf_registration;" >> ${AWR_GENERATE_AWR_ONLY}
echo "select DBID, SNAP_INTERVAL from dba_hist_wr_control;" >> ${AWR_GENERATE_AWR_ONLY}
echo "EOSQL" >> ${AWR_GENERATE_AWR_ONLY}
echo "" >> ${AWR_GENERATE_AWR_ONLY}

echo "# Examples" >> ${AWR_GENERATE_AWR_ONLY}
echo "# exec dbms_workload_repository.create_remote_snapshot('ed970201');" >> ${AWR_GENERATE_AWR_ONLY}
echo "# @?/rdbms/admin/awrrpti" >> ${AWR_GENERATE_AWR_ONLY}
echo "# awrrpti mit dem i um die Instanz auswählen zu können - DBID der standby" >> ${AWR_GENERATE_AWR_ONLY}
echo "# select DBID, SNAP_INTERVAL from dba_hist_wr_control" >> ${AWR_GENERATE_AWR_ONLY}
echo "# EXECUTE DBMS_WORKLOAD_REPOSITORY.MODIFY_SNAPSHOT_SETTINGS(interval => 15, retention => 20160, dbid => 1720568045);" >> ${AWR_GENERATE_AWR_ONLY}

chmod a+x ${AWR_GENERATE_DBLINKS}
chmod a+x ${AWR_GENERATE_AWR_ONLY}
rm ${AWR_TMP_SCRIPT}

# qs functions

function run_awr_create_snap() {
echo "select 'create local snap' as INFO from dual;" >> $1
echo "exec dbms_workload_repository.create_snapshot;" >> ${1}
for dghost in $(echo $dghosts | tr "," "\n")
do
  dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
  DB_HOST_IDENTIFIER=${dghostname:1:4}
  GET_DB_UNIQUE_NAME=${dgenv}d${DB_HOST_IDENTIFIER}${dgnumber}
  LOCAL_DB_UNIQUE_NAME=${DB_UNIQUE_NAME}
  if [[ "${dghostname}" != "${DB_HOST}" ]]; then
    echo "select 'create snap on ${GET_DB_UNIQUE_NAME}' as INFO from dual;" >> $1
    echo "exec DBMS_WORKLOAD_REPOSITORY.create_remote_snapshot('${GET_DB_UNIQUE_NAME}');" >> $1
  fi
done
}

########################
####
########################

echo "###[STEP]### Generating Service Scripts ${SCRIPT_DIR}/generate_service.sh " | tee -a ${LOGFILE}

function addUsageToFile(){
  echo "fct_usage()" >> ${1}
  echo "{" >> ${1}
  echo "echo -e \"" >> ${1}
  echo "\$0 <PDB Name>" >> ${1}
  echo "Usage:" >> ${1}
  echo "\t<Name PDB> = e.g. ISTATZ" >> ${1}
  echo "\"" >> ${1}
  echo "}" >> ${1}

  echo "if [[ \$# != 1 ]];then" >> ${1}
  echo " fct_usage" >> ${1}
  echo " exit 1" >> ${1}
  echo "fi" >> ${1}
}

SERVICE_GENERATE_SCRIPT=${SCRIPT_DIR}/generate_service.sh

echo "#!/bin/bash" > ${SERVICE_GENERATE_SCRIPT}
setdbInFile ${SERVICE_GENERATE_SCRIPT}

echo "" >> ${SERVICE_GENERATE_SCRIPT}

addUsageToFile ${SERVICE_GENERATE_SCRIPT}

echo "SERVICE_PDB_NAME=\$1" >> ${SERVICE_GENERATE_SCRIPT}

echo "echo \"\"" >> ${SERVICE_GENERATE_SCRIPT}
echo "echo \"CDB:\"" >> ${SERVICE_GENERATE_SCRIPT}
echo "echo \"UNIQUE NAME:               ${DB_UNIQUE_NAME}\"" >> ${SERVICE_GENERATE_SCRIPT}
echo "echo \"Service CDB:               ${DB_NAME}\"" >> ${SERVICE_GENERATE_SCRIPT}
echo "echo \"Remote Listener:           <leer>\"" >> ${SERVICE_GENERATE_SCRIPT}
echo "echo \"PDB:\"" >> ${SERVICE_GENERATE_SCRIPT}
echo "echo \"NAME:                      \${SERVICE_PDB_NAME}\"" >> ${SERVICE_GENERATE_SCRIPT}
echo "echo \"Remote Listener:           CMAN_BI\"" >> ${SERVICE_GENERATE_SCRIPT}

echo "echo \"Services\"" >> ${SERVICE_GENERATE_SCRIPT}
for readservice in $(echo $servicenames | tr "," "\n")
do
  echo "echo \"- $readservice\"" >> ${SERVICE_GENERATE_SCRIPT}
done

echo "echo \" \"" >> ${SERVICE_GENERATE_SCRIPT}
echo "echo \" ##################################\"" >> ${SERVICE_GENERATE_SCRIPT}
echo "echo \" Achtung: Wenn in der Datenbank mehr als eine Pluggable DB vorhanden ist, bitte die Rückfragen beachten.\"" >> ${SERVICE_GENERATE_SCRIPT}
echo "echo \" Zum intitalen Aufbau und die erzeugen der TNSNAmes ist der PDB Name nicht notwendig. Der Service Namen ist durch die Anlage in die TNSNames eingepflegt.\"" >> ${SERVICE_GENERATE_SCRIPT}
echo "echo \" ##################################\"" >> ${SERVICE_GENERATE_SCRIPT}
echo "echo \" \"" >> ${SERVICE_GENERATE_SCRIPT}

addQuestionToFile ${SERVICE_GENERATE_SCRIPT}

for readservice in $(echo $servicenames | tr "," "\n")
do

  echo "echo \"Add Services $readservice to \${SERVICE_PDB_NAME} \" " >> ${SERVICE_GENERATE_SCRIPT}
  echo "echo \"is this correct? (y/n)?\"" >> ${SERVICE_GENERATE_SCRIPT}
  echo "read answer >> \$1" >> ${SERVICE_GENERATE_SCRIPT}
  echo "if [ \"\$answer\" != \"\${answer#[Yy]}\" ] ;then" >> ${SERVICE_GENERATE_SCRIPT}

  if [[ $readservice == *"_RO"* ]]; then
    echo "srvctl add service -d ${DB_UNIQUE_NAME} -service ${readservice} -role physical_standby -pdb \${SERVICE_PDB_NAME} " >> ${SERVICE_GENERATE_SCRIPT}
  else
    echo "srvctl add service -d ${DB_UNIQUE_NAME} -service ${readservice} -role primary -pdb \${SERVICE_PDB_NAME} " >> ${SERVICE_GENERATE_SCRIPT}
  fi

  echo "fi" >> ${SERVICE_GENERATE_SCRIPT}

done

# CDB
echo "srvctl add service -d ${DB_UNIQUE_NAME} -service ${DB_NAME} -role primary" >> ${SERVICE_GENERATE_SCRIPT}

echo "echo \"only at startup the database checks status of primary or standby \" " >> ${SERVICE_GENERATE_SCRIPT}
echo "echo \"to start it: srvctl start service -d ${DB_UNIQUE_NAME} \" " >> ${SERVICE_GENERATE_SCRIPT}

echo "srvctl status service -d ${DB_UNIQUE_NAME} " >> ${SERVICE_GENERATE_SCRIPT}
echo "" >> ${SERVICE_GENERATE_SCRIPT}
echo "echo \"set remote_listener CMAN_BI for \${SERVICE_PDB_NAME}\"" >> ${SERVICE_GENERATE_SCRIPT}
echo "" >> ${SERVICE_GENERATE_SCRIPT}

echo "${DB_HOME}/bin/sqlplus -L -S /@${DB_UNIQUE_NAME} as sysdba <<EOSQL 2>&1" >> ${SERVICE_GENERATE_SCRIPT}
echo "alter system reset remote_listener; " >> ${SERVICE_GENERATE_SCRIPT}
echo "alter system set remote_listener='' scope=memory; " >> ${SERVICE_GENERATE_SCRIPT}
echo "alter session set container=\${SERVICE_PDB_NAME}; " >> ${SERVICE_GENERATE_SCRIPT}
echo "-- alter system reset local_listener scope=spfile; " >> ${SERVICE_GENERATE_SCRIPT}
echo "-- alter system reset listener_networks scope=spfile; " >> ${SERVICE_GENERATE_SCRIPT}
echo "alter system set remote_listener='CMAN_BI'; " >> ${SERVICE_GENERATE_SCRIPT}
echo "EOSQL" >> ${SERVICE_GENERATE_SCRIPT}
echo "" >> ${SERVICE_GENERATE_SCRIPT}

chmod u+x ${SERVICE_GENERATE_SCRIPT}

# qs scripts
echo "###[STEP]### Generating Check Scripts " | tee -a ${LOGFILE}

CHECK_SCRIPT_AWR=${SCRIPT_DIR}/qs_check_awr.sh

echo "#!/bin/bash" > ${CHECK_SCRIPT_AWR}
setdbInFile ${CHECK_SCRIPT_AWR}
echo "" >> ${CHECK_SCRIPT_AWR}

echo "${DB_HOME}/bin/sqlplus -L -S /@${DB_UNIQUE_NAME} as sysdba <<EOSQL 2>&1" >> ${CHECK_SCRIPT_AWR}
addFormatToSQLFiles ${CHECK_SCRIPT_AWR}
echo "select DBID, instance_number, snap_id, snap_level, to_char(begin_interval_time,'yyyy.mm.dd hh24:mi:ss') snap_start, error_count, " >> ${CHECK_SCRIPT_AWR}
echo "decode( SNAP_FLAG, 0 , 'automatic' , 1 , 'manual plsql' , 2 , 'imported' , 4 , 'pack_was_not_enabled') CREATION   " >> ${CHECK_SCRIPT_AWR}
echo "from dba_hist_snapshot where begin_interval_time > (sysdate-3) order by begin_interval_time;" >> ${CHECK_SCRIPT_AWR}
echo "-- " >> ${CHECK_SCRIPT_AWR}
echo "select * from dba_umf_topology;" >> ${CHECK_SCRIPT_AWR}
echo "select TOPOLOGY_NAME, NODE_NAME, NODE_ID, NODE_TYPE from umf\\\$_registration;" >> ${CHECK_SCRIPT_AWR}
echo "select * from dba_umf_registration;" >> ${CHECK_SCRIPT_AWR}
echo "select db.name, wr.DBID, wr.SNAP_INTERVAL, wr.retention, wr.topnsql " >> ${CHECK_SCRIPT_AWR}
echo "from dba_hist_wr_control wr left outer join v\\\$database db on wr.dbid=db.dbid;" >> ${CHECK_SCRIPT_AWR}
echo "-- " >> ${CHECK_SCRIPT_AWR}
run_awr_create_snap ${CHECK_SCRIPT_AWR}
echo "-- " >> ${CHECK_SCRIPT_AWR}
echo "EOSQL" >> ${CHECK_SCRIPT_AWR}
echo "" >> ${CHECK_SCRIPT_AWR}

chmod a+x ${CHECK_SCRIPT_AWR}

# qs scripts
echo "###[STEP]### Correct ports and names in observer tnsnames " | tee -a ${LOGFILE}

echo "s/dg.${DB_DOMAIN}/db.${DB_DOMAIN}/g" >> ${LOGFILE}
sed -i "s/dg.${DB_DOMAIN}/db.${DB_DOMAIN}/g" ${TNSNAMES_OBSERVER}
echo "s/(PORT = ${hvport})/(PORT = ${port})/g" >> ${LOGFILE}
sed -i "s/(PORT = ${hvport})/(PORT = ${port})/g" ${TNSNAMES_OBSERVER}
echo "s/dg)(PORT/db)(PORT/g" >> ${LOGFILE}
sed -i "s/dg)(PORT/db)(PORT/g" ${TNSNAMES_OBSERVER}


####################
####
#### Passwordfile
###

ASM_PWD_FILE="+DG1/${DB_UNIQUE_NAME}/pwd${DB_NAME}"
PWD_FILE_NAME="pwd${DB_NAME}"

setasm

if [[ "${DB_HOST}" == "${activenode}" ]]; then
    echo "###[STEP]### Copy Password file from active node " | tee -a ${LOGFILE}
    echo "populate pwdfile ${ASM_PWD_FILE}" | tee -a ${LOGFILE}
   
    asmcmd pwcopy ${ASM_PWD_FILE} /tmp/${PWD_FILE_NAME}

    if [[ "$SSH_CONECTIVITY" != "true" ]]; then
        echo "scp ${PUBLIC_HOST}:/tmp/${PWD_FILE_NAME} /tmp/${PWD_FILE_NAME}" | tee -a ${LOGFILE}
    fi

    for dghost in $(echo $dghosts | tr "," "\n")
    do
        dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
        dghostname_small=${dghostname::-2}
        OTHER_HOST_IDENTIFIER=${dghostname:1:4}
        OTHER_DB_UNIQUE_NAME=${dgenv}d${OTHER_HOST_IDENTIFIER}${dgnumber}
        PWD_FILE_DST_NAME="${DB_HOME}/dbs/orapw${OTHER_DB_UNIQUE_NAME}"

	if [[ "$SSH_CONECTIVITY" == "true" ]]; then
        	scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /tmp/${PWD_FILE_NAME} ${dghostname}.${DB_DOMAIN}:${PWD_FILE_DST_NAME} >> /dev/null 2>&1
        else
	       echo " scp /tmp/${PWD_FILE_NAME} ${dghostname_small}:${PWD_FILE_DST_NAME}" | tee -a ${LOGFILE}
        fi

        RC=$?
        if [[ $RC != 0 ]];then
          echo "Copy PW file manaually to ${PWD_FILE_DST_NAME} at host $dghostname_small" | tee -a ${LOGFILE}
          # exit 1
        fi
    done
fi

####################
####
#### Check some Paramter in local DB
###

setdb

echo "###[STEP]### Check existing DB parameters " | tee -a ${LOGFILE}

# Check FLASHBACK_ON -> YES
CHECK_FLASHBACK_ON=`echo "select FLASHBACK_ON from v\\$database;" | sqlplus -s / as sysdba | grep -v -- '--' | grep -v FLASHBACK_ON | grep -v "^$" | cut -d" " -f2`
if [[ "$CHECK_FLASHBACK_ON" != "YES" ]];then
  echo "----------> error " | tee -a ${LOGFILE}
  echo "Check FLASHBACK_ON in ${DB_UNIQUE_NAME}" | tee -a ${LOGFILE}
else 
  echo "Flashback OK value: $CHECK_FLASHBACK_ON" | tee -a ${LOGFILE}
fi

# Check STANDBY_FILE_MANAGEMENT -> YES
CHECK_STANDBY_FILE_MANAGEMENT=`echo "select VALUE from v\\$parameter where name='standby_file_management';" | sqlplus -s / as sysdba | grep -v -- '--' | grep -v VALUE | grep -v "^$" | cut -d" " -f2`
if [[ "$CHECK_STANDBY_FILE_MANAGEMENT" != "AUTO" ]];then
  echo "----------> error " | tee -a ${LOGFILE}
  echo "Check STANDBY_FILE_MANAGEMENT in ${DB_UNIQUE_NAME}" | tee -a ${LOGFILE}
else
  echo "STANDBY_FILE_MANAGEMENT ok value: $CHECK_STANDBY_FILE_MANAGEMENT" | tee -a ${LOGFILE}
fi