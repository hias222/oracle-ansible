#!/bin/bash

# Changes
# 19.07.21 MFU INIT Release


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
DB_HOST=$(uname -n)db
WALLET_DIRECTORY="${ORACLE_HOME}/wallet"
DB_UNIQUE_NAME=$activenode
DB_NAME=$dbname
DB_HOME=$ORACLE_HOME
SQLNET_ORA=${ORACLE_HOME}/network/admin/sqlnet.ora
TNSNAMES_ORA=${ORACLE_HOME}/network/admin/tnsnames.ora
DB_DOMAIN=$(nslookup $(uname -n) | grep ^Name: | awk -F' ' '{ print $2 }' | cut -d"." -f2-)

#####
# getting sys/system password
#####
read -p "enter sys/system password for wallet creation[[ (return) = default (oracle)]]: " SYS_PASSWORD
[[ -z ${SYS_PASSWORD} ]] && SYS_PASSWORD=oracle

### validate parameter

if [[ -z ${dbname} ]]; then
  echo "missing parameter dbname in $1"
  exit 1
fi

echo "DB Name          $DB_NAME"


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
LOGFILE=${ORACLE_BASE}/admin/${DB_UNIQUE_NAME}/log/$(echo "install_dg_${DB_UNIQUE_NAME}_$(date '+Y%YM%mD%d_H%HM%MS%S').log")
log_dir=${ORACLE_BASE}/admin/${DB_UNIQUE_NAME}/log

echo "Logfile: ${LOGFILE}" | tee -a ${LOGFILE}

#### Backup Files

backup_file() {
  new_file=$(echo $1 | rev | cut -f 2- -d '.' | rev)
  cp $1 ${new_file}_$(date '+Y%YM%mD%d_H%HM%MS%S').save
  echo "Save: ${1}" | tee -a ${LOGFILE}
}

#### Wallet
#### Functions

function generateSQLNetEntry() {
ENTRY=$(echo "WALLET_LOCATION=
   (SOURCE =
     (METHOD = FILE)
     (METHOD_DATA =
       (DIRECTORY = ${WALLET_DIRECTORY})
     )
   )
SQLNET.WALLET_OVERRIDE = TRUE
")
}

function addDBsToWallet(){
for dghost in $(echo $dghosts | tr "," "\n")
do
  dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
  OTHER_HOST_IDENTIFIER=${dghostname:1:4}
  OTHER_DB_UNIQUE_NAME=${dgenv}d${OTHER_HOST_IDENTIFIER}${dgnumber}
  ${DB_HOME}/bin/mkstore -wrl ${WALLET_DIRECTORY} -deleteCredential ${OTHER_DB_UNIQUE_NAME}  >> /dev/null 2>&1
  ${DB_HOME}/bin/mkstore -wrl ${WALLET_DIRECTORY} -createCredential ${OTHER_DB_UNIQUE_NAME} sys ${SYS_PASSWORD} >> /dev/null 2>&1
done
}

####################################

echo "###[STEP]### Wallet setup " | tee -a ${LOGFILE}

if [[ ! -d "${WALLET_DIRECTORY}" ]] ;
then
    mkdir ${WALLET_DIRECTORY}
fi

if [[ ! -f "${SQLNET_ORA}" ]] ;
then
    touch ${SQLNET_ORA}
fi

# create Wallet
${DB_HOME}/bin/orapki wallet create -wallet ${WALLET_DIRECTORY} -auto_login_only >> /dev/null 2>&1
# add keys
addDBsToWallet
echo "Get details: ${DB_HOME}/bin/mkstore -wrl ${WALLET_DIRECTORY} -listCredential"

lead='### BEGIN GENERATED CONTENT WALLET DATAGUARD'
tail='### END GENERATED CONTENT WALLET DATAGUARD'

backup_file ${SQLNET_ORA}

# delete old comments
sed -i "/^$lead$/,/^$tail$/d" ${SQLNET_ORA}

echo "" >> ${SQLNET_ORA}
echo "${lead}" >> ${SQLNET_ORA}
generateSQLNetEntry
echo "${ENTRY}" >> ${SQLNET_ORA}
echo "${tail}" >> ${SQLNET_ORA}

#####
# generate dataguard tnsnames entry for SINGLE
#####

echo "###[STEP]### create dataguard tnsnames.ora entry ${TNSNAMES_ORA}" | tee -a ${LOGFILE}

if [ ! -f ${TNSNAMES_ORA} ]; then
    touch ${TNSNAMES_ORA}
fi

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

### backup
backup_file ${TNSNAMES_ORA}

#####
# Services

lead='### BEGIN GENERATED TNSNAMES FOR '${DB_NAME}
tail='### END GENERATED TNSNAMES FOR '${DB_NAME}

# delete old comments
sed -i "/^$lead$/,/^$tail$/d" ${TNSNAMES_ORA}

echo "${lead}" >> ${TNSNAMES_ORA}

for dghost in $(echo $dghosts | tr "," "\n")
do
    dghostname=$(echo $dghost| awk -F  ":" '{print $1}')
    OTHER_HOST_IDENTIFIER=${dghostname:1:4}
    OTHER_DB_UNIQUE_NAME=${dgenv}d${OTHER_HOST_IDENTIFIER}${dgnumber}

    generateDirectTNSEntry $dghostname $OTHER_DB_UNIQUE_NAME
    # echo $ENTRY

    echo "${ENTRY}" >> ${TNSNAMES_ORA}
    echo "" >> ${TNSNAMES_ORA}
    ENTRY=''
done

echo "${tail}" >> ${TNSNAMES_ORA}
echo "" >> ${LOGFILE}

