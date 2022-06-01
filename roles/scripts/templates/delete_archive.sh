#!/bin/bash

# -- delete noprompt archivelog all;

export ORACLE_SID=ed970101
export ORACLE_HOME=/orasw/oracle/product/db19
export PATH=/orasw/oracle/product/db19/bin:/orasw/oracle/product/db19/OPatch:/opt/oracle/bin:.:/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/X/bin:/usr/dt/bin:/usr/xpg4/bin:/orasw/oracle/BA/bin:/usr/local/bin:/usr/bin:/bin:/usr/lib/mit/bin
export PATH=/orasw/oracle/product/db19/bin:/orasw/oracle/product/db19/perl/bin:/orasw/oracle/product/db19/bin:/orasw/oracle/product/db19/perl/bin:/orasw/oracle/product/db19/bin:/orasw/oracle/product/db19/OPatch:/opt/oracle/bin:.:/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/X/bin:/usr/dt/bin:/usr/xpg4/bin:/orasw/oracle/BA/bin:/usr/local/bin:/usr/bin:/bin:/usr/lib/mit/bin
export PERL5LIB=/orasw/oracle/product/db19/rdbms/admin:/orasw/oracle/product/db19/rdbms/admin:/orasw/oracle/product/db19/rdbms/admin:/orasw/oracrs/product/crs19/rdbms/admin:/orasw/oracrs/product/crs19/rdbms/admin:/orasw/oracle/product/db19/rdbms/admin:/orasw/oracle/product/db19/rdbms/admin:/orasw/oracle/product/db19/rdbms/admin:/orasw/oracrs/product/crs19/rdbms/admin:/orasw/oracrs/product/crs19/rdbms/admin:
export ORACLE_BASE=/orasw/oracle
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8


${ORACLE_HOME}/bin/rman target /@ed970101 <<EOSQL 2>&1
delete noprompt archivelog until time 'SYSDATE-1/48';
EOSQL

${ORACLE_HOME}/bin/rman target /@ed970201 <<EOSQL 2>&1
delete noprompt archivelog all;
EOSQL

${ORACLE_HOME}/bin/rman target /@ed970301 <<EOSQL 2>&1
delete noprompt archivelog all;

EOSQL
