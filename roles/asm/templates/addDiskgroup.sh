#!/bin/bash
#  sqlplus / as sysasm

export ORACLE_HOME={{grid.oracle_home}}
export ORACLE_SID=+ASM
export PATH=$ORACLE_HOME/bin:$PATH

sqlplus / as sysasm << EOF

SET SERVEROUTPUT ON
SET VERIFY OFF

select sysdate from dual;
-- SELECT name, type, total_mb, free_mb, required_mirror_free_mb, usable_file_mb FROM V$ASM_DISKGROUP;

-- create diskgroup dg1 external redundancy disk '/dev/nvme0n1' name dg1 ATTRIBUTE 'compatible.asm' = '19.0.0.0.0', 'compatible.rdbms' = '12.1.0.0.0';

-- create diskgroup dg2 external redundancy disk '/dev/nvme0n2' name dg2 ATTRIBUTE 'compatible.asm' = '19.0.0.0.0', 'compatible.rdbms' = '12.1.0.0.0';

create diskgroup dg3 external redundancy disk '/dev/nvme0n3' name dg3 ATTRIBUTE 'compatible.asm' = '19.0.0.0.0', 'compatible.rdbms' = '12.1.0.0.0';

alter diskgroup dg1 add disk '/dev/nvme0n2';
-- alter diskgroup dg1 add disk '/dev/nvme0n3';

exit;
EOF
