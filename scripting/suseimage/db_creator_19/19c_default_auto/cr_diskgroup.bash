#!/bin/bash


fct_usage()
{
echo -e "
$0 <check/apply> <disklist>
Usage:
\t<check/apply>
\t<dikslist> List to add to DG3
"
}

if [[ $# -lt 0 ]] || [[ $# -gt 2 ]];then
 fct_usage
 exit 1
fi

START=$(date +%s)
WORK_DIR=$(pwd)
SSH_CONECTIVITY=false
ORATAB=/etc/oratab
DB_HOST=$(uname -n)db
SCRIPT_DIR=${WORK_DIR}/${DB_HOST}
DB_DOMAIN=$(nslookup $(uname -n) | grep ^Name: | awk -F' ' '{ print $2 }' | cut -d"." -f2-)
ORG_PATH=$PATH
CRS_HOME=$(cat ${ORATAB} | grep -v ^# | grep -v ^$ | grep -E "^[+|-]" | cut -d":" -f2 | sort | uniq)
RUN_MODE=$1
NEW_DISKGROUP=dg3

echo "Modus: $RUN_MODE"

echo "is this correct? (y/n)?"
read answer
if [ "$answer" != "${answer#[Yy]}" ] ;then
echo ""
else
echo "ERROR-99: installation aborted by user"
exit 1
fi


mkdir -p ${ORACLE_BASE}/admin/+ASM/log
LOGFILE=${ORACLE_BASE}/admin/+ASM/log/$(echo "install_dg_${DB_UNIQUE_NAME}_$(date '+Y%YM%mD%d_H%HM%MS%S').log")
log_dir=${ORACLE_BASE}/admin/+ASM/log

mkdir -p $SCRIPT_DIR

echo "Logfile: ${LOGFILE}" | tee -a ${LOGFILE}

function setasm () {
    export ORACLE_SID=+ASM
    export ORACLE_HOME=$CRS_HOME
    export PATH=$ORG_PATH
    export PATH=${ORACLE_HOME}/bin:${ORACLE_HOME}/perl/bin:$PATH
    export PERL5LIB=${ORACLE_HOME}/rdbms/admin:$PERL5LIB
    export ORACLE_BASE=/orasw/oracle
    export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
}

function setasmInFile () {
    echo "export ORACLE_SID=+ASM" >> ${1}
    echo "export ORACLE_HOME=$CRS_HOME" >> ${1}
    echo "export PATH=$ORG_PATH" >> ${1}
    echo "export PATH=${ORACLE_HOME}/bin:${ORACLE_HOME}/perl/bin:$PATH" >> ${1}
    echo "export PERL5LIB=${ORACLE_HOME}/rdbms/admin:$PERL5LIB" >> ${1}
    echo "export ORACLE_BASE=/orasw/oracle" >> ${1}
    echo "export NLS_LANG=AMERICAN_AMERICA.AL32UTF8" >> ${1}
}


## check diskgroup details

setasm

${CRS_HOME}/bin/sqlplus -L -S / as sysasm <<EOSQL >> ${LOGFILE} 2>&1
-- check disks
select sysdate from dual;
show parameter asm_diskstring;
set pagesize 200 linesize 400 long 100
col DISK_PATH  format a30
col DISK_FAILGROUP format a20
col DISK_NAME format a20
col DG_NAME format a10
col STATUS format a15
select  dg.name as dg_name,
d.name as disk_name,
d.path as disk_path,
d.failgroup as disk_failgroup,
d.FREE_MB as free,
d.mount_status as status
from v\$asm_disk d, v\$asm_diskgroup dg
where d.group_number = dg.group_number(+);
--
select GROUP_NUMBER,NAME,VALUE from v\$asm_attribute where NAME = 'compatible.asm';
select GROUP_NUMBER,NAME,VALUE from v\$asm_attribute where NAME = 'compatible.rdbms';
EOSQL

## alter DISKGROUP DB_DATA_GRP02 drop disk C4T4D0S6,C4T5D0S6,C4T6D0S6;

SCRIPT_DIR_FILE=${SCRIPT_DIR}/drop_asm_disks.sh
echo "script in  ${SCRIPT_DIR_FILE}"


echo "#!/bin/bash" > ${SCRIPT_DIR_FILE}
setasmInFile ${SCRIPT_DIR_FILE}
echo "" >> ${SCRIPT_DIR_FILE}
echo "${CRS_HOME}/bin/sqlplus -L -S / as sysasm <<EOSQL 2>&1" >> ${SCRIPT_DIR_FILE}

${CRS_HOME}/bin/sqlplus -L -S / as sysasm <<EOSQL >> ${SCRIPT_DIR_FILE} 2>&1
col command format a200
set pagesize 200 linesize 400 long 100
SET HEADING OFF
SET FEEDBACK OFF
select  
'alter diskgroup ' || dg.name || ' drop disk ' ||  d.name || ' rebalance power 100;' command
from v\$asm_disk d, v\$asm_diskgroup dg
where d.group_number = dg.group_number(+)
and dg.name='DG1' and d.name like '%ASMN8';
EOSQL

${CRS_HOME}/bin/sqlplus -L -S / as sysasm <<EOSQL >> ${SCRIPT_DIR_FILE} 2>&1
col command format a200
set pagesize 200 linesize 400 long 100
SET HEADING OFF
SET FEEDBACK OFF
select * from v\$asm_operation;
select NAME,STATE from v\$asm_diskgroup;
EOSQL

${CRS_HOME}/bin/sqlplus -L -S / as sysasm <<EOSQL >> ${SCRIPT_DIR_FILE} 2>&1
col command format a200
set pagesize 200 linesize 400 long 100
SET HEADING OFF
SET FEEDBACK OFF
select 'create diskgroup ${NEW_DISKGROUP} external redundancy disk ''' ||
PATH ||
''' attribute ''compatible.asm''= ''19.0.0.0.0'', ''compatible.rdbms'' = ''19.0.0'';' as command
from v\$asm_disk where name like '%ASMN8' and rownum=1 ;
--
select 'alter diskgroup ${NEW_DISKGROUP} add disk ''' || PATH || ''' ;' from (
select PATH from v\$asm_disk where name like '%ASMN8'
minus
select PATH from v\$asm_disk where name like '%ASMN8' and rownum=1) ;
-- free
select 'alter diskgroup ${NEW_DISKGROUP} add disk ''' || PATH || ''' ;' from v\$asm_disk where HEADER_STATUS='FORMER';
EOSQL


#lter diskgroup add disk ''
# create diskgroup dg3 external redundancy disk ''  name dg3
#attribute 'compatible.asm' = '19.0.0.0.', 'compatible.rdbms' = '19.0.0';

echo "EOSQL" >> ${SCRIPT_DIR_FILE}
echo "" >> ${SCRIPT_DIR_FILE}
