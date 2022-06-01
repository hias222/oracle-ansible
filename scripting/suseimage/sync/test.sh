#!/bin/bash -x 

LOGFILE=/orasw/oracle/BA/adm/log/sync_p/l9600022_20211222_160001.log
SED_STRING="##FLASHBLADE_SYNC_JOB##"
CHECK_SCRIPT=/home/oracle/dg_tools/get_dg_state.sh
CHECK_STATE=NEARSTANDBY

function CheckNode() {
	CHECK_CODE=$($1 -d PSDG001 -S)
	
	if [[ "$CHECK_CODE" == "$2" ]]; then
		echo "check success $CHECK_CODE"
		return 0
	fi

	echo Failure $CHECK_CODE $1

	exit 1
}


CheckNode $CHECK_SCRIPT $CHECK_STATE

