#!/bin/bash

# offene Punkte
# ASM Parameter gerade ziehen
# Diskgroups gerade ziehen
# dgmgrl config nach duplicate entfernen

# Changes
# 01.12.21 MFU Init

DB_UNIQUE_NAME=SRCDB001
DB_HOME=/orasw/oracle/product/db19
ORACLE_BASE=/orasw/oracle

function fct_usage()
{
echo -e "
$0 -o <SID>
Usage:
\t-o <ORACLE_SID>
"
}

if [[ $# -lt 1 ]];then
 fct_usage
 exit 1
fi


while getopts o:h flag
do
    case "${flag}" in
        o) DB_UNIQUE_NAME=${OPTARG}
          ;;
        h) fct_usage
           exit 0
          ;;
        \? ) fct_usage
           exit 0
          ;;
    esac
done


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
SCRIPT_DIR=${WORK_DIR}/${DB_UNIQUE_NAME}
HOST_SCRIPT_DIR=${WORK_DIR}/${DB_HOST}
DB_DOMAIN=$(nslookup $(uname -n) | grep ^Name: | awk -F' ' '{ print $2 }' | cut -d"." -f2-)
ORG_PATH=$PATH
CRS_HOME=$(cat ${ORATAB} | grep -v ^# | grep -v ^$ | grep -E "^[+|-]" | cut -d":" -f2 | sort | uniq)
WALLET_DIRECTORY="/orasw/oracle/wallet"

LISTENER_ORA=${DB_HOME}/network/admin/listener.ora
SQLNET_ORA=${DB_HOME}/network/admin/sqlnet.ora
TNSNAMES_ORA=${DB_HOME}/network/admin/tnsnames.ora
TNSNAMES_OBSERVER=${HOST_SCRIPT_DIR}/tnsnames.observer
TNSNAMES_ODI=${HOST_SCRIPT_DIR}/tnsnames.odi

GI_LISTENER_ORA=${CRS_HOME}/network/admin/listener.ora
GI_TNSNAMES_ORA=${CRS_HOME}/network/admin/tnsnames.ora

LOGFILE=${ORACLE_BASE}/admin/${DB_UNIQUE_NAME}/log/$(echo "install_dg_${DB_UNIQUE_NAME}_$(date '+Y%YM%mD%d_H%HM%MS%S').log")

## passwords

if [[ -f ${WORK_DIR}/resources/.dbvpw.enc ]];then
  export $(openssl enc -aes-256-cbc -d -in ${WORK_DIR}/resources/.dbvpw.enc -k DBVAULT2020)
else
  echo "${WORK_DIR}/resources/.dbvpw.enc not found, please check." 
  exit 1
fi
## set homes

function setdb () {
    export ORACLE_SID=${DB_UNIQUE_NAME} 
    export ORACLE_HOME=${DB_HOME}
    export PATH=$ORG_PATH
    export PATH=${ORACLE_HOME}/bin:${ORACLE_HOME}/perl/bin:$PATH
    export PERL5LIB=${ORACLE_HOME}/rdbms/admin:$PERL5LIB
    export ORACLE_BASE=${ORACLE_BASE}
    export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
}

### validate parameter

echo "Host:            ${DB_HOST}.${DB_DOMAIN}"
echo "ORACLE_SID       ${DB_UNIQUE_NAME}"


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

echo "LOG $LOGFILE"

#################

#####
# getting sys/system password
#####
read -p "enter sys/system password[[ (return) = default (oracle)]]: " SYS_PW
[[ -z ${SYS_PW} ]] && SYS_PW=oracle

#############################

function setDbCloneAccount() {

CLONE_DG_USER=$1
echo "###[STEP]### Setupe for PDB clone - C##$CLONE_DG_USER  " | tee -a ${LOGFILE}

echo "manage user C##$CLONE_DG_USER" >> ${LOGFILE} 2>&1
CLONEUSER_EXIST=`echo "select count(*) CLONEUSER from dba_users where username='C##${CLONE_DG_USER}';" | sqlplus -s / as sysdba | grep -v -- '--' | grep -v CLONEUSER | grep -v "^$" | cut -d" " -f2`

if [[ "$CLONEUSER_EXIST" == "1" ]]; then
    echo "user C##${CLONE_DG_USER} exists" >> ${LOGFILE} 2>&1
    ${DB_HOME}/bin/sqlplus -L -S C##BA_DVACCOUNT/${ACCOUNT_PW} <<EOSQL >> ${LOGFILE} 2>&1 
     alter user C##$CLONE_DG_USER account unlock;
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


## account
setdb

setDbCloneAccount PDB_CLONEUSER
