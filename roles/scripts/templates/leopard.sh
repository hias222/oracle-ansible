#!/bin/bash

LOGFILE={{common.log_dir}}/$(echo "test_leonard_$(date '+Y%YM%mD%d_H%HM%MS%S').log")

export ORACLE_HOME={{db.oracle_home}}
export ORACLE_BASE={{common.oracle_base}}
export ORACLE_SID=ed970101

export PATH={{ common.user_home }}/leopard/jdkdb815/bin:${ORACLE_HOME}/bin:$PATH

cd {{ common.user_home }}/leopard/java

which java

java -Xms16384m -Xmx16384m -cp {{ common.user_home }}/leopard/java:{{ common.user_home }}/leopard/java/jdbc/ojdbc8.jar LeopardO 2>&1 ${LOGFILE}
