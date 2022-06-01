#!/bin/bash
#####################################################
#
# Ermitteln des DG MDE der aktuellen Instanz
#
# _BA-IT-Systemhaus-TEC4-Datenbanken-Exadata <IT-Systemhaus.TEC4-DB-EXA@arbeitsagentur.de>
#
SCRIPT_VERSION=0.1
#######

# 27.12.21 MFU First Version EXA2ZELOS-120

function fct_usage()
{
echo -e "
$0 -d <db_name> [-S] 
Usage:
\t -d <db_name> DB Name
\t-S silent
"
}

silent_mode=false

while getopts d:Sh flag
do
    case "${flag}" in
        S) silent_mode=true
          ;;
        h) fct_usage
           exit 0
          ;;
        d) DB_NAME=${OPTARG}
          ;;
        \? ) fct_usage
           exit 0
          ;;
    esac
done

#DB_NAME=edg0101
ORACLE_BASE=/orasw/oracle
DB_HOME=${ORACLE_BASE}/product/db19

DB_HOST=$(uname -n)db
PUBLIC_HOST=$(uname -n)
DB_HOST_IDENTIFIER=${DB_HOST:1:4}
LOGFILE=${ORACLE_BASE}/admin/${DB_NAME}/log/$(echo "get_dg_state_${DB_NAME}_$(date '+Y%YM%mD%d_H%HM%MS%S').log")
ORG_PATH=$PATH


mkdir -p ${ORACLE_BASE}/admin/${DB_NAME}/log

function log()
{
if [[ $silent_mode == 'false' ]]; then
    echo "[$(date)][${SCRIPT_VERSION}]: $*"
fi
echo "[$(date)][${SCRIPT_VERSION}]: $*" >> $LOGFILE
}


function setdb() {
    export ORACLE_HOME=${DB_HOME}
    export PATH=$ORG_PATH
    export PATH=${ORACLE_HOME}/bin:${ORACLE_HOME}/perl/bin:$PATH
    export PERL5LIB=${ORACLE_HOME}/rdbms/admin:$PERL5LIB
    export ORACLE_BASE=${ORACLE_BASE}
    export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
}


## checks 

log "$LOGFILE"

if [[ $DB_NAME == '' ]];then
    log "missing db_name, use"
    log "$0 -d <db_name>"
    echo "ERROR"
    exit 1
fi

setdb

${DB_HOME}/bin/sqlplus -L -S /@${DB_NAME} as sysdba <<EOSQL >> ${LOGFILE} 2>&1
select sysdate from dual; 
EOSQL

RC=$?
if [[ $RC != 0 ]];then
    log "ERROR check connect to ${DB_NAME}"
    echo "ERROR"
    exit 1
fi

# get hostname
# select DB_UNIQUE_NAME from v$dataguard_config where DB_UNIQUE_NAME like '%${DB_HOST_IDENTIFIER}%';

log "get DB_UNIQUE_NAME"

${DB_HOME}/bin/sqlplus -L -S /@${DB_NAME} as sysdba <<EOSQL >> ${LOGFILE} 2>&1
set pagesize 300
set linesize 300
select ${DB_HOST_IDENTIFIER} as SEARCHSTRING_ON_DB_UNIQUE_NAME from dual;
select DB_UNIQUE_NAME, PARENT_DBUN, DEST_ROLE from v\$dataguard_config;
EOSQL

LOCAL_DB_UNIQUE_NAME_EXIST=`echo "select count(*) DBEXISTS from v\\$dataguard_config where DB_UNIQUE_NAME like '%${DB_HOST_IDENTIFIER}%';" | sqlplus -s /@${DB_NAME} as sysdba | grep -v -- '--' | grep -v DBEXISTS | grep -v "^$" | cut -d" " -f2`

if [[ "$LOCAL_DB_UNIQUE_NAME_EXIST" != "1" ]]; then
    log "ERROR getting local DB"
    echo "ERROR"
    exit 1
fi

LOCAL_DB_UNIQUE_NAME=`echo "select DB_UNIQUE_NAME as DB_UNIQUE_NAME from v\\$dataguard_config where DB_UNIQUE_NAME like '%${DB_HOST_IDENTIFIER}%';" | sqlplus -s /@${DB_NAME} as sysdba | grep -v -- '--' | grep -v DB_UNIQUE_NAME | grep -v "^$" | cut -d" " -f2`

if [[ ${LOCAL_DB_UNIQUE_NAME} == '' ]]; then
    log "ERROR getting DB_UNIQUE_NAME"
    echo "ERROR"
    exit 1
fi

log "unique name is $LOCAL_DB_UNIQUE_NAME"

GLOBAL_DB_NAME=`echo "select NAME as DB_NAME from v\\$database;" | sqlplus -s /@${DB_NAME} as sysdba | grep -v -- '--' | grep -v DB_NAME | grep -v "^$" | cut -d" " -f2`

if [[ ${GLOBAL_DB_NAME^^} != ${DB_NAME^^} ]]; then
    log "WARNING Check with instance name maybe wrong ${GLOBAL_DB_NAME^^}/${DB_NAME^^}"
    echo "# WARNING instance name used"
fi

# log "get DB_UNIQUE_NAME"


# get role

LOCAL_DB_ROLE=`echo "select DEST_ROLE as DEST_ROLE from v\\$dataguard_config where DB_UNIQUE_NAME = '${LOCAL_DB_UNIQUE_NAME}';" | sqlplus -s /@${DB_NAME} as sysdba | grep -v -- '--' | grep -v DEST_ROLE | grep -v "^$"`

RC=$?
if [[ $RC != 0 ]];then
    log "ERROR check DEST_ROLE"
    echo "ERROR"
    exit 1
fi

if [[ ${LOCAL_DB_ROLE} == "UNKNOWN" ]]; then
    log "ERROR role UNKNOWN"
    echo "ERROR"
    exit 1
fi

if [[ ${LOCAL_DB_ROLE} == '' ]]; then
    log "ERROR getting role"
    echo "ERROR"
    exit 1
fi

log "role is $LOCAL_DB_ROLE"

if [[ ${LOCAL_DB_ROLE} == "PRIMARY DATABASE" ]]; then
    log "LOCAL node is primary"
    echo "PRIMARY"
    exit 0
fi

# check if we have more than 2 Instances

INSTANCE_COUNT=`echo "select count(*) as INSTANCE_COUNT from v\\$dataguard_config;" | sqlplus -s /@${DB_NAME} as sysdba | grep -v -- '--' | grep -v INSTANCE_COUNT | grep -v "^$" | awk '{print $1}'`

if [[ ${INSTANCE_COUNT} -lt 2 ]]; then
    log "no standbys"
    echo "ERROR"
    exit 1
fi

if [[ ${INSTANCE_COUNT} -lt 3 ]]; then
    log "only two INSTANCES"
    echo "STANDBY"
    exit 0
fi

if [[ ${INSTANCE_COUNT} -eq 3 ]]; then
    log "we have threee instances, decide on name necassary"
    echo "NOT_IMPLEMENTED"
    exit 1
fi

# search for PRIMARY

PRIMARY_DB_UNIQUE_NAME=`echo "select DB_UNIQUE_NAME as DB_UNIQUE_NAME from v\\$dataguard_config where DEST_ROLE = 'PRIMARY DATABASE';" | sqlplus -s /@${DB_NAME} as sysdba | grep -v -- '--' | grep -v DB_UNIQUE_NAME | grep -v "^$" | cut -d" " -f2`

RC=$?
if [[ $RC != 0 ]];then
    log "ERROR check PRIMARY_DB_UNIQUE_NAME"
    echo "ERROR"
    exit 1
fi

if [[ ${LOCAL_DB_ROLE} == '' ]]; then
    log "ERROR getting PRIMARY_DB_UNIQUE_NAME"
    echo "ERROR"
    exit 1
fi

log "Primary is $PRIMARY_DB_UNIQUE_NAME (self $LOCAL_DB_UNIQUE_NAME)"

# check direct mode

DIRECT_DG_MODE=`echo "select count(*) DIRECT from v\\$dataguard_config where DB_UNIQUE_NAME = '${LOCAL_DB_UNIQUE_NAME}' and PARENT_DBUN = '${PRIMARY_DB_UNIQUE_NAME}';" | sqlplus -s /@${DB_NAME} as sysdba | grep -v -- '--' | grep -v DIRECT | grep -v "^$" | cut -d" " -f2`

if [[ "$DIRECT_DG_MODE" == "0" ]]; then
    log "INSTANCE is in second DS - no direct mode"
    echo "FARSTANDBY"
    exit 0
fi

# check 3 direct connects

NUMBER_DIRECT_NODES=`echo "select count(*) as DIRECT from v\\$dataguard_config where PARENT_DBUN = '${PRIMARY_DB_UNIQUE_NAME}';" | sqlplus -s /@${DB_NAME} as sysdba | grep -v -- '--' | grep -v DIRECT | grep -v "^$" | awk '{print $1}'`

if [[ ${NUMBER_DIRECT_NODES} -gt 2 ]]; then
    log "more than 2 direct connects, please check DG config ($NUMBER_DIRECT_NODES)"
    echo "ERROR"
    exit 1
fi

# check dependend DB

DEPEND_DG_MODE=`echo "select count(*) DEPEND from v\\$dataguard_config where PARENT_DBUN = '${LOCAL_DB_UNIQUE_NAME}';" | sqlplus -s /@${DB_NAME} as sysdba | grep -v -- '--' | grep -v DEPEND | grep -v "^$" | cut -d" " -f2`

if [[ "$DEPEND_DG_MODE" == "0" ]]; then
    log "INSTANCE is in first DS - no dependend mode"
    echo "NEARSTANDBY"
    exit 0
fi

# depending dbs -> must be in second DS

log "Primary, Far instance in seperate DS"
echo "FARSTANDBY"
exit 0
