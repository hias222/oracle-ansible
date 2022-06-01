#!/bin/bash

export ORACLE_SID=ed970101
export ORACLE_PDB_SID=PSTATX

LOGFILE={{common.log_dir}}/$(echo "test_dg_$(date '+Y%YM%mD%d_H%HM%MS%S').log")

echo "Logfile: $LOGFILE"

{{db.home}}/bin/sqlplus -L -S / as sysdba <<EOSQL >> ${LOGFILE} 2>&1
@{{common.test_dir}}/sql/{{test_script}}
EOSQL
