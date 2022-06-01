#!/bin/bash 
#
# Erzeugen einer aktuellen Liste von CDBs + PDBs des Systems via crontab
#
# Idee + Original von R. Zanter
#
# crontab-Einrag:       */5 * * * *    /home/oracle/.profile_addon.sh
#
# Log:
# 20210128,khs: mit einigen Aenderungen nach $Z kopiert
#               insbesondere: <echo "DB: ${DB}"> gewandelt nach <echo "CDB: ${DB}">
# 20210130,khs: Programm-Namen vorne um '.' strippen
# khs,20210211:  - STDBY-CDBs gekennzeicnet mit '@' anzeigen
# khs,20210307: evtl. alte Abhaengigk. beruecksichtigen durch verlinken i
#               von ~/.profile_dbs + ~/.profile_addon.sh, (z Zt. auskommentiert)
# khs,20210308: bei "if [[ -z ${PDBS} ]] ..." auch "OFF_or_FAIL_or_NONE" ausgeben
#
#
ME=$(basename $0 .sh)
ME=${ME#.}
ORACLE_BASE=${ORACLE_BASE:=/orasw/oracle}
Z=${Z:=$ORACLE_BASE/BA/adm}

echo $PATH | grep -q /BA/bin || PATH=$PATH:.:$ORACLE_BASE/BA/bin:$Z/bin

oenv_save() {
 _PATH=$PATH _LD_LIBRARY_PATH=$LD_LIBRARY_PATH _ORA_NLS10=$ORA_NLS10
}
oenv_set() {
 PATH=$O/bin:$PATH LD_LIBRARY_PATH=$O/lib:$LD_LIBRARY_PATH ORA_NLS10=$O/nls/data
}
oenv_restore() {
 PATH=$_PATH LD_LIBRARY_PATH=$_LD_LIBRARY_PATH ORA_NLS10=$_ORA_NLS10
}

{
#rac check, setting vars
if [[ ! -z $(ps -ef | grep lms | grep -v grep) ]];
then
HOST_FQDN=$(uname -n)
HOST=`echo ${HOST_FQDN}|cut -d'.' -f1`
CRS_HOME=$(cat /etc/oratab | grep -v ^# | grep -v ^$ | grep -E "^[+|-]" | cut -d":" -f2 | sort | uniq)
HOST_NUM=$(${CRS_HOME}/bin/olsnodes -n | grep  ${HOST} | awk -F' ' '{ print $2 }')
fi

for DB in $(cat /etc/oratab | grep -vE "^#|^$|MGMTDB|ASM" | cut -d':' -f1 | sort)
do
oenv_save
# export ORACLE_SID=${DB}${HOST_NUM}
export ORACLE_HOME=$(cat /etc/oratab | grep ^${DB}: | cut -d':' -f2)
O=$ORACLE_HOME oenv_set

export ORACLE_SID=$(srvctl status database -d ${DB}|grep $(uname -n|cut -d'.' -f1)|cut -d' ' -f2)

#NEU:stdby-check
echo "select '_XYZ_'||DATABASE_ROLE from v\$database;"| ${ORACLE_HOME}/bin/sqlplus -S -L / as sysdba | grep -q '_XYZ_PHYSICAL STANDBY' && DB="@${DB}"
# Ende NEU::stdby-check

PDBS=$(${ORACLE_HOME}/bin/sqlplus -S -L / as sysdba <<EOSQL
set heading off;
set feedback off;
WHENEVER SQLERROR EXIT 1;
select name from v\$pdbs;
EOSQL
)

if [[ $? != 0 ]];then
PDBS='OFF_or_FAIL_or_NONE'
fi

#khs-hack
PDBS=$(echo "$PDBS" | grep -v 'PDB$SEED')
PDBS=${PDBS:='OFF_or_FAIL_or_NONE'}

if [[ -z ${PDBS} ]];then
 echo -en "CDB: ${DB}\t PDBS: OFF_or_FAIL_or_NONE " && echo ""
else
 echo -en "CDB: ${DB}\t PDBS: "
 for i in ${PDBS}
 do
  if [[ ${i} != 'PDB$SEED' ]];then
  echo -n "${i} "
 fi
 done
 echo ""
 PDBS=''
fi
oenv_restore
done
} > $Z/tmp/profile_dbs.$$ 2>/dev/null
# 2>/dev/null
mv $Z/tmp/profile_dbs.$$ $Z/etc/profile_dbs
#
# die $Z/etc/ora_pdb auch erneuern
ora_pdb
#
# und noch alte Abhaengigkeiten beruecksichtigen:
#set -x
#(
#set -x
# ls -l $HOME/.$ME.sh | grep -q $(basename $Z/bin/$ME.sh) \
# || {
#       cp -p  $HOME/.$ME.sh $HOME/.$ME.sh.SAVE
#       rm -f $HOME/.${ME}.sh && ln -s $Z/bin/$ME.sh $HOME/.${ME}.sh
# }
# ls -l $HOME/.profile_dbs | grep -q $(basename $Z/etc/profile_dbs) \
# || {
#        cp -p  $HOME/.profile_dbs $HOME/.profile_dbs.SAVE
#        rm -f $HOME/.profile_dbs && ln -s $Z/etc/profile_dbs $HOME/.profile_dbs
# }
#) 2>&1 | cat - >/tmp/p_add

