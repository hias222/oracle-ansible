#!/bin/bash

# Dokumentation in Confluence TEC4-Datenbanken

# Changes
# 12.12.21 MFU Initial Version 1.0

function fct_usage()
{
echo -e "
$0 -f <DG_CONFIG> [-c]
Usage:
\t-f <DG_CONFIG>
\t-c don't check always run all steps
"
}

if [[ $# -lt 2 ]];then
 fct_usage
 exit 1
fi

runchecks=true

while getopts f:ch flag
do
    case "${flag}" in
        f) configfile=${OPTARG}
          ;;
        h) fct_usage
           exit 0
          ;;
        c) runchecks=false
          ;;
        \? ) fct_usage
           exit 0
          ;;
    esac
done

if test -f ${configfile} ; then
  echo "-f :   using config file ${configfile}" | tee -a ${LOGFILE}
  . ${configfile}
else
    echo "config file: ${configfile} not found " | tee -a ${LOGFILE}
    exit 1
fi

DB_NAME=${dbname}
WORK_DIR=$(pwd)
START=$(date +%s)
ORATAB=/etc/oratab
DB_HOST=$(uname -n)db
DB_HOST_IDENTIFIER=${DB_HOST:1:4}
DB_UNIQUE_NAME=${dgenv}d${DB_HOST_IDENTIFIER}${dgnumber}
DB_DOMAIN=$(nslookup $(uname -n) | grep ^Name: | awk -F' ' '{ print $2 }' | cut -d"." -f2-)
ORG_PATH=$PATH
DB_HOME=/orasw/oracle/product/db19
CRS_HOME=$(cat ${ORATAB} | grep -v ^# | grep -v ^$ | grep -E "^[+|-]" | cut -d":" -f2 | sort | uniq)

PUBLIC_HOST=$(uname -n)
DB_UNIQUE_NAME=${dgenv}d${DB_HOST_IDENTIFIER}${dgnumber}
DB_ACTIVE_IDENTIFIER=${activenode:1:4}
DB_ACTIVE_NAME=${dgenv}d${DB_ACTIVE_IDENTIFIER}${dgnumber}

HOST_SCRIPT_DIR=${WORK_DIR}/${DB_HOST}
GI_LISTENER_ORA=${CRS_HOME}/network/admin/listener.ora
TNSNAMES_ORA=${DB_HOME}/network/admin/tnsnames.ora
TNSNAMES_OBSERVER=${HOST_SCRIPT_DIR}/tnsnames.observer
TNSNAMES_ODI=${HOST_SCRIPT_DIR}/tnsnames.odi

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


echo "DB:                    ${DB_NAME}"
echo "Delete DB Instance:    ${DB_UNIQUE_NAME}"
echo "Active Node:           ${DB_ACTIVE_NAME}"

echo "is this correct? (y/n)?"
read answer
if [ "$answer" != "${answer#[Yy]}" ] ;then
echo ""
else
echo "ERROR-99: installation aborted by user"
exit 1
fi


# delete stdby

setdb


## checks

function checkRedoRoutes() {
  for readhosts in $(echo $dghosts | tr "," "\n")
  do
        dghostname=$(echo $readhosts| awk -F  ":" '{print $1}')
        dghvip=$(echo $readhosts| awk -F  ":" '{print $2}')

        OTHER_HOST_IDENTIFIER=${readhosts:1:4}
        TEMP_DB_UNIQUE_NAME=${dgenv}d${OTHER_HOST_IDENTIFIER}${dgnumber}

        CHECK_REDO_CONFIGURED=`echo "SHOW database verbose ${TEMP_DB_UNIQUE_NAME};" | dgmgrl /@${DB_ACTIVE_NAME} | grep RedoRoutes | grep ${DB_UNIQUE_NAME} | wc -l`

        if [[ $CHECK_REDO_CONFIGURED == "1" ]]; then
           echo `echo "SHOW database verbose ${TEMP_DB_UNIQUE_NAME};" | dgmgrl /@${DB_ACTIVE_NAME} | grep RedoRoutes`
           echo "please remove REDO route with entries of ${DB_UNIQUE_NAME}"
           echo "edit database ${TEMP_DB_UNIQUE_NAME} set PROPERTY RedoRoutes='';"
           exit 1
        fi
  done

}

backup_file() {
  new_file=$(echo $1 | rev | cut -f 2- -d '.' | rev)
  cp $1 ${new_file}_$(date '+Y%YM%mD%d_H%HM%MS%S').save
  echo "Save: ${1}" | tee -a ${LOGFILE}
}

exitScript() {
    if [ ${runchecks} == "true" ]; then
        echo "to ignore check use "
        echo "      $0 -f $configfile -c"
        exit 1
    else
        echo " <----- ignore checks used"
    fi
}


##########################
# Checks
##########################

CHECK_FSFO_ON=`echo "SHOW FAST_START FAILOVER;" | dgmgrl /@${DB_ACTIVE_NAME} | grep 'Fast-Start Failover' | grep Enabled | wc -l`

if [[ $CHECK_FSFO_ON == "1" ]]; then
        echo "FSFO enabled, disable it and restart"
        echo "STOP OBSERVER [<observer name> | ALL];"
        echo "DISABLE FAST_START FAILOVER [FORCE | CONDITION <condition>];"
        echo "Example to run dgm/dgmgrl"
        echo "STOP OBSERVER ALL;"
        echo "DISABLE FAST_START FAILOVER ;"
        exitScript

else
        echo "no observer enabled, going on"
fi

checkRedoRoutes
echo "no REDO Routes found"


echo "remove ${DB_UNIQUE_NAME} from DG"

dgmgrl /@${DB_ACTIVE_NAME} <<EOSQL
edit database ${DB_UNIQUE_NAME} set state='apply-off';
disable configuration;
edit database ${DB_UNIQUE_NAME} SET PROPERTY LogXptMode='ASYNC';
remove database ${DB_UNIQUE_NAME};
enable configuration;
EOSQL

echo "stop ${DB_UNIQUE_NAME}"

srvctl stop database -d ${DB_UNIQUE_NAME}
echo ""
srvctl remove database -d ${DB_UNIQUE_NAME}

if [ -e ${DB_HOME}/dbs/orapw${DB_UNIQUE_NAME} ]; then
    echo "delete pwd file ${DB_HOME}/dbs/orapw${DB_UNIQUE_NAME}"
    rm ${DB_HOME}/dbs/orapw${DB_UNIQUE_NAME}
else
    echo "pwd file not exists ${DB_HOME}/dbs/orapw${DB_UNIQUE_NAME}"
fi

if [ -e ${DB_HOME}/dbs/${DB_UNIQUE_NAME}_DR2.DAT ]; then
    echo "delete broker file"
    rm ${DB_HOME}/dbs/${DB_UNIQUE_NAME}_DR2.DAT
else
    echo "broker file not exist ${DB_HOME}/dbs/${DB_UNIQUE_NAME}_DR2.DAT"
fi

if [ -e ${DB_HOME}/dbs/init${DB_UNIQUE_NAME}.ora ]; then
    echo "delete spfile"
    rm ${DB_HOME}/dbs/init${DB_UNIQUE_NAME}.ora
    rm ${DB_HOME}/dbs/hc_${DB_UNIQUE_NAME}.dat
else
    echo "spfile not exist ${DB_HOME}/dbs/init${DB_UNIQUE_NAME}.ora"
fi


###############################
# empty existing entries
#############################

#####

echo "###[STEP]### check existing entries for ${DB_UNIQUE_NAME}"

grep -i  "${DB_UNIQUE_NAME}[: $=]" ${ORATAB} >/dev/null
RC=$?
if [[ $RC != 0 ]];then
    echo "${DB_UNIQUE_NAME} removed from ${ORATAB}" 
else
    echo "---------------> error"
    echo "please remove ${DB_UNIQUE_NAME} from ${ORATAB}"
    echo "after this run cr_dg.bash script"
    echo "     ./cr_dg.bash -f <other than $configfile> -p"
    exitScript
fi

setasm

lsnrctl status LISTENER_DG | grep ${DB_UNIQUE_NAME}_HV >/dev/null

RC=$?
if [[ $RC != 0 ]];then
    echo "Service ${DB_UNIQUE_NAME}_HV in LISTENER_DG not found" 
else
    echo "---------------> error"
    echo "run cr_dg.bash script from other DB environment to correct services"
    echo "     ./cr_dg.bash -f <other than $configfile> -p"
    echo "cr_dg.bach cleanups DG listener configuration"
    exitScript
fi

lsnrctl status LISTENER | grep ${DB_UNIQUE_NAME} >/dev/null
RC=$?
if [[ $RC != 0 ]];then
    echo "Service ${DB_UNIQUE_NAME} in LISTENER not found" 
else
    echo "---------------> error"
    echo "manuel correct services in ASM Home listener.ora"
    exitScript
fi

##################################
#####
# Services

echo "###[STEP]### update tnsnames ${TNSNAMES_ORA}"

lead='### BEGIN GENERATED TNSNAMES FOR '${DB_NAME}
tail='### END GENERATED TNSNAMES FOR '${DB_NAME}

# delete old comments
sed -i "/^$lead$/,/^$tail$/d" ${TNSNAMES_ORA}
sed -i "/^$lead$/,/^$tail$/d" ${TNSNAMES_ODI}
sed -i "/^$lead$/,/^$tail$/d" ${TNSNAMES_OBSERVER}

###############################
# end empty existing entries
#############################

setasm

echo "delete ASM entries for ${DB_UNIQUE_NAME} "
asmcmd rm -rf +DG1/${DB_UNIQUE_NAME}
asmcmd rm -rf +DG3/${DB_UNIQUE_NAME}

echo "finished delete files"

