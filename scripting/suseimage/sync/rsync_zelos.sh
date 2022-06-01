#!/bin/bash
#####################################################
#
# Inkrementelles backup für Clone DB Erstellen
#
# _BA-IT-Systemhaus-TEC4-Datenbanken-Exadata <IT-Systemhaus.TEC4-DB-EXA@arbeitsagentur.de>
#
# description
# sync filesystem with zelos
#
#####################################################
#
# Release history
# 20.12.2021 MFU 0.3    EXA2ZELOS-118
# 11.11.2021 MFU 0.2    add exclude list
# 19.10.2021 MFU 0.1    Initiale Version
#
#####################################################
##
#
SCRIPT_VERSION="0.4"
#
##
#####################################################
P_COUNT=$#
P1=$1
P2=$2
P3=$3
P4=$4

# Basic variables
# to get instance ID

###

BASE_BCK_DIR=/orasw/oracle/BA/adm/log
SCRIPT_DIR=/home/oracle/dg_tools
SOURCE_SYNC=/batches
DEST_SYNC=/batches
LOCAL_SYNC=/rbatches

CHECK_SCRIPT=/home/oracle/dg_tools/get_dg_state.sh
CHECK_STATE=NEARSTANDBY


# for TESTING
#SOURCE_SYNC=/Users/MFU/tmp
#DEST_SYNC=/batches
#LOCAL_SYNC=/Users/MFU/tmp2
#BASE_BCK_DIR=/Users/MFU/log
#SCRIPT_DIR=/Users/MFU/projects/work/ba/setup/scripting/suseimage/db_creator_19/19c_default_auto

RETAIN_NUM_LINES=1000
RMAN_CHANNELS=4
SED_STRING="##FLASHBLADE_SYNC_JOB##"


## Logging
MY_DATE="`date '+%Y%m%d_%H%M%S'`"
MY_DOW="`date '+%u'`"
MY_HOSTNAME=`/bin/hostname | awk -F '.' '{ print $1 }'`
LOGFILE="${BASE_BCK_DIR}/sync${P2}/${MY_HOSTNAME}_${MY_DATE}.log"
INTERNAL_ERROR_LIST=""

# start as oracle -> use of certs of oracle
# false start as dest user
RSYNC_AS_ACTUAL_USER=false
BASE_SSH_USER_NAME=oracle
CONNECT_AS_SYNC_USER=false
CLONE_NODE=localhost
DRY_RUN=false
DEBUG=false

## detect exadata environment

#----------------------
# BEGINN USAGE FUNKTION
#----------------------
usage_funct()
        {
        echo "-------------------------------------------------------------------------------------"
        echo "Sync Data Batches to Zelos"
	echo "Version $SCRIPT_VERSION " 
        echo " "
        echo "Aufruf:$0 <FUNCTION> [<Verfahren|Ordner _p/_i> <Destinat or DB Nameon> <dry>]"
        echo "Bsp.: $0 sync _p psdg001 dry"
        echo "Bsp.: $0 sync_manual stat"
        echo "Bsp.: $0 sync_batches opda bip4z"
	echo "Bsp.: $0 copy_batches stat bip3z dry"
        echo " "
        echo "  FUNCTION:"
        echo "          sync                    -> synchronize local Files /batches -> /rbatches using RSYNC and delete old data, search for files end with <_p> add db name to check for DG "
        echo "          copy                    -> synchronize local Files /batches -> /rbatches using RSYNC with no delete, search for files end with <_p> add DB Name to check for DG"
        echo "                                     exclude list is possible, sync_exclude.txt in the first subfolder e.g. stat_p "
        echo "          syncall                 -> synchronize local Files /batches -> /rbatches using RSYNC and delete old data, search for files end with <_p> "
        echo "          copyall                 -> synchronize local Files /batches -> /rbatches using RSYNC with no delete, search for files end with <_p>"
        echo "                                     exclude list is ignored "
        echo "          sync_manual             -> synchronize special folders in /batches -> /rbatches using RSYNC and delete old data "
        echo "          copy_manual             -> synchronize special folders in /batches -> /rbatches using RSYNC with no delete"
        echo "          sync_batches            -> synchronize external Files using ssh and RSYNC and delete old data "
        echo "          copy_batches            -> synchronize external Files using ssh and RSYNC with no delete"
	echo "          ?/help                  -> usage wird angezeigt "
        echo " "
        echo "  Options:"
        echo "          <dry>                   -> dry or nothing | only checks -> no rsync, no data changes"
        echo "          <Verfahren>             -> opda or stat | specific configs "
        echo "          <Destination>           -> bip4z, bip3z, bip2z, bip1z "
        echo "--------------------------------------------------------------------------------------"
        echo "  Example Exclude entry"
        echo "          # sync_exclude.txt "
        echo "          # the top folder need to be included "
        echo "          # placed inside the the top folder -> under stat_p"
        echo "          stat_p/prog/konfig"
        exit 2
        }


#######################
## Help Functions 
######################

function logsetup {  
    TMP=$(tail -n $RETAIN_NUM_LINES $LOGFILE 2>/dev/null) && echo "${TMP}" > $LOGFILE
    TMP_NUMBER=1
    exec > >(tee -a $LOGFILE)
    exec 2>&1
}

function log {  
    echo -e ${Colour_Green} "[$(date)][${SCRIPT_VERSION}]: $*"
    echo -ne ${Colour_NO}
}

function debug {
    echo "[$(date)][DEBUG][${SCRIPT_VERSION}]: $*"
}


function errorlog {
    echo -e ${Colour_Red} "[$(date)][error]: $*"
    echo -ne ${Colour_NO}
}

function newsectionlog {
     echo -e ${Colour_Green} "[$(date)][${SCRIPT_VERSION}]: #####################################################"
     echo -e ${Colour_Green} "[$(date)][${SCRIPT_VERSION}]: ### ${TMP_NUMBER}: Starting Section $*"	
     let "TMP_NUMBER++"
     echo -ne ${Colour_NO}
}

function set_remote_node
{
        clustername=$(echo "$P3"|awk '{print toupper($0)}')
        case ${clustername} in
             BIP4Z)  CLONE_NODE=l9600022.dst.baintern.de
                ;;
             BIP3Z)  CLONE_NODE=l9800022.dst.baintern.de
                ;;
             BIP2Z)  CLONE_NODE=unknown
                log "not implemented $P3"
                exit 1;
                ;;
             BIP1Z)  CLONE_NODE=unknown
                log "not implemented $P3"
                exit 1;
                ;;
             *)
             log "Remote side ${P3} error"
             log "known vlaues bip1z, bip2z, bip3z, bip4z"
             exit 1 
                ;;
        esac
}

function check_ssh_connection
{
        log "check host $1 - user $2"
        
        ssh -o StrictHostKeyChecking=no $1 hostname > /dev/null 2>&1

        # for rsync -e "ssh -o StrictHostKeyChecking=no"

        if [[ $? != "0" ]];then
                errorlog "failed ssh as actual user $?"
                return 1
        fi
        return 0
}

function check_environment
{
        ##### LOG Dir
        ##$BASE_BCK_DIR/logs/$P2
        if [ -d "${BASE_BCK_DIR}/sync${P2}" ]; then
                log "Directory $BASE_BCK_DIR/sync$P2 exists."
                chmod a+rw ${BASE_BCK_DIR}/sync${P2}
                touch $LOGFILE
                chmod a+rw $LOGFILE
        else
                mkdir -p $BASE_BCK_DIR/sync${P2}
                chmod a+rw $BASE_BCK_DIR/sync${P2}
		touch $LOGFILE
                chmod a+rw $LOGFILE
                logsetup
                log "Directory $BASE_BCK_DIR/sync${P2} created."
        fi

	echo "start logrotate "
	/usr/sbin/logrotate ${SCRIPT_DIR}/logrotate.conf --state ${SCRIPT_DIR}/logrotate-state >> $LOGFILE
	if [[ $? != "0" ]]; then
                INTERNAL_ERROR_LIST="LOGRROTATEFAILURE"
        fi


	echo BASE_BCK_DIR $BASE_BCK_DIR
        echo SCRIPT_DIR $SCRIPT_DIR
        echo CLONE_NODE $CLONE_NODE
        echo LOGFILE $LOGFILE
        echo DEST_SYNC $DEST_SYNC

}

function log_end_backup() {

        qc_satisfy1=0
        qc_satisfy2=0
        qc_satisfy3=0

	SEARCH_STRING=$1
	FAILURE_CODE=$2

	if [[ $FAILURE_CODE != "" ]];then
		echo "<<< $FAILURE_CODE >>>"
		FAIL="$FAILURE_CODE"
		qc_satisfy3="1"
	fi


        #sed sucht vom SED_STRING im logfile bis Ende Lofile. WG. kombination DB+ARCH Sicherung um Fehler zu unterscheiden DB oder ARCH
        sed -n '/'${SEARCH_STRING}'/,$p' $LOGFILE | grep -i "failed "
        if [ $? = 0 ]
        then
                echo "<<< FAILED-Fehler im Log >>>"
		FAIL="sync_flashblade"
                qc_satisfy1="1"
        else
                echo "Keine FAILED-Fehler im Log"
                qc_satisfy1="0"
        fi

        sed -n '/'${SEARCH_STRING}'/,$p' $LOGFILE | grep -i "Permission denied (13)"
        if [ $? = 0 ]
        then
                echo "<<< Permission-Fehler im Log >>>"
		FAIL="sync_flashblade"
                qc_satisfy2="1"
        else
                echo "Keine Permission-Fehler im Log"
                qc_satisfy2="0"
        fi



        if [ $qc_satisfy1 -eq 0 ] && [ $qc_satisfy2 -eq 0 ] && [ $qc_satisfy3 -eq 0 ]
        then
                END_ERROR_LISTE="$INTERNAL_ERROR_LIST"
        else
                END_ERROR_LISTE="$INTERNAL_ERROR_LIST $FAIL"
        fi

	echo "Komplettes Log: $LOGFILE"
        echo "ERROR-Liste := < $END_ERROR_LISTE >"
        echo ""
        echo ""
        echo "-- END SYNC `date '+%Y%m%d_%H%M%S'` --"

}


function CheckNode() {

	CHECK_DB_NAME=$3
        CHECK_CODE=$($1 -d $CHECK_DB_NAME -S)

	if [[ "$CHECK_DB_NAME" == "" ]];then
		log Failure missing db Name
	        log_end_backup $SED_STRING FAILURE_MISSING_DB_NAME
		exit 1
	fi


        if [[ "$CHECK_CODE" == "$2" ]]; then
                log "check success for $CHECK_DB_NAME with $CHECK_CODE"
                return 0
        fi

        log Failure $CHECK_CODE $1 at $CHECK_DB_NAME
	log_end_backup $SED_STRING info_failure_dg_not_$2

        exit 1
}



###############################################
## RSYNC for /batches
###############################################

function check_source_folder()
{
        # check folder with files without group read permission 
        log "folder to check $1"
        # find files with no group access
        WRONG_FILES=$(find $1 ! -perm /g+rwx | wc -l)
        if [[ $WRONG_FILES != "0" ]];then
                log "find $1 ! -perm /g+rwx -exec chmod g+r {} \;" 
                errorlog "Files without group rights"
                return 1
        fi
        return 0
}

function rsync_local_command
{
        # Parameter 
        # $1 mode 
        # $3 zieluser
        # $4 Verzeichnis
        #
        # rsync_command sync opdaadm_p test_p

        if [[ $# -ne 3 ]];then
                errorlog "internal error wrong parameter"
                exit 1
        fi

        rsync_command_mode=$1
        rsync_command_destuser=$2
        rsync_command_folder=$3
        rsync_command_exclude=true
	rsync_exlude_file=${SOURCE_SYNC}/${rsync_command_folder}/sync_exclude.txt
        rsync_command_start="sudo sudo -u $rsync_command_destuser /usr/bin/rsync"
        
        log " ${SOURCE_SYNC}/${rsync_command_folder} to $LOCAL_SYNC as $rsync_command_destuser"

        # ?? bei anderem user
        # check_source_folder ${SOURCE_SYNC}/${rsync_command_folder}

        if [[ $? != "0" ]]; then
		INTERNAL_ERROR_LIST="LOGFAILURE"
                return 1
        fi 
        
        if [[ $RSYNC_AS_ACTUAL_USER == "true" ]]; then
          rsync_command_start="/usr/bin/rsync"
	  # --rsync-path=\"sudo sudo -u ${rsync_command_destuser} rsync\"
        fi

        if [[ ${P4} == "dry" ]]; then
                log "dry run end for ${SOURCE_SYNC}/${rsync_command_folder} to $LOCAL_SYNC"
                return 0
        fi

        if [[ ${rsync_command_mode} == "syncall" ]]; then
                log "complete sync"
                rsync_command_exclude=false
                rsync_command_mode="sync"
        fi

        if [[ ${rsync_command_mode} == "copyall" ]]; then
                log "complete copy"
                rsync_command_exclude=false
                rsync_command_mode="copy"
        fi

	# check exclude file 
        if [ $rsync_command_exclude == 'true' ]; then
	log "check if exclude file exists $rsync_exlude_file"
                if [ -f $rsync_exlude_file ]; then
                log "exclude exists $rsync_exlude_file"
                rsync_command_start="${rsync_command_start} --exclude-from=$rsync_exlude_file"
                fi
        fi

        # archive --> -rlptgD without o
        # remove --perms
        log "setting permissions to Directory: 2770 Files: 770"
        log "owner is set to ${rsync_command_destuser}"
       
        if [[ ${rsync_command_mode} == "sync" ]]; then
                log do_rsync 
                if [[ $DEBUG == "true" ]];then
                        log "${rsync_command_start} --chmod=D2770,F770 -rltpgD --delete-after --log-file=$LOGFILE ${SOURCE_SYNC}/${rsync_command_folder} $LOCAL_SYNC"
                fi
                ${rsync_command_start} --chmod=D2770,F770 -rltpgD --delete-after --log-file=$LOGFILE ${SOURCE_SYNC}/${rsync_command_folder} $LOCAL_SYNC
        fi

        if [[ ${rsync_command_mode} == "copy" ]]; then
                if [[ $DEBUG == "true" ]];then
                        log "${rsync_command_start} --chmod=D2770,F770 -rltpgD --log-file=$LOGFILE ${SOURCE_SYNC}/${rsync_command_folder} $LOCAL_SYNC"
                fi
                ${rsync_command_start} --chmod=D2770,F770 -rltpgD --log-file=$LOGFILE ${SOURCE_SYNC}/${rsync_command_folder} $LOCAL_SYNC
        fi

        rsync_exit_code=$?

        if [ "$rsync_exit_code" -ne "0" ] ; then
		INTERNAL_ERROR_LIST="${INTERNAL_ERROR_LIST} ${rsync_command_mode}error" 
                log Error when calling RSYNC - exit code: $rsync_exit_code
        fi

        log Finished Synchronization of Files 
}


function rsync_command
{
        # Parameter 
        # $1 mode 
        # $3 zieluser
        # $4 Verzeichnis
        #
        # rsync_command sync opdaadm_p test_p

        if [[ $# -ne 3 ]];then
                errorlog "internal error wrong parameter"
                exit 1
        fi

        rsync_command_mode=$1
        rsync_command_destuser=$2
        rsync_command_connectuser=$2
        rsync_command_folder=$3
        rsync_command_start="sudo -u ${rsync_command_destuser} $/usr/bin/rsync"
        rsync_command_connect_user=$BASE_SSH_USER_NAME

        log "${rsync_command_mode} ${SOURCE_SYNC}/${rsync_command_folder} to $DEST_SYNC as $rsync_command_destuser"

        check_ssh_connection $CLONE_NODE $rsync_command_connect_user

        if [[ $? != "0" ]]; then
                return 1
        fi 

        check_source_folder ${SOURCE_SYNC}/${rsync_command_folder}

        if [[ $? != "0" ]]; then
                return 1
        fi 
        
        if [[ $RSYNC_AS_ACTUAL_USER == "true" ]]; then
          rsync_command_start="/usr/bin/rsync"
        fi

        if [[ $CONNECT_AS_SYNC_USER == "true" ]]; then
          rsync_command_connect_user=$2
        fi

        if [[ ${P4} == "dry" ]]; then
                log "dry run end for ${SOURCE_SYNC}/${rsync_command_folder} to $DEST_SYNC"
                return 0
        fi

	# Check exclude file

        # archive --> -rlptgD without o
        # remove --perms
        log "setting permissions to Directory: 2770 Files: 0770"
        log "owner is set to ${rsync_command_destuser}"
       
        if [[ ${rsync_command_mode} == "sync" ]]; then
                log do_rsync test_p
                if [[ $DEBUG == "true" ]];then
                        log "${rsync_command_start} --rsync-path=\"sudo sudo -u ${rsync_command_destuser} rsync\" --chmod=D2770,F770 -rltpgD --delete-after --log-file=$LOGFILE --rsh=\"ssh -o StrictHostKeyChecking=no\" ${SOURCE_SYNC}/${rsync_command_folder} \"${rsync_command_connect_user}\"@$CLONE_NODE:$DEST_SYNC"
                fi
                ${rsync_command_start} --rsync-path="sudo sudo -u ${rsync_command_destuser} rsync" --chmod=D2770,F770 -rltpgD --delete-after --log-file=$LOGFILE --rsh="ssh -o StrictHostKeyChecking=no" ${SOURCE_SYNC}/${rsync_command_folder} "${rsync_command_connect_user}"@$CLONE_NODE:$DEST_SYNC
        fi

        if [[ ${rsync_command_mode} == "copy" ]]; then
                if [[ $DEBUG == "true" ]];then
                        log "${rsync_command_start} --rsync-path=\"sudo sudo -u ${rsync_command_destuser} rsync\" --chmod=D2770,F770 -rltpgD --log-file=$LOGFILE --rsh=\"ssh -o StrictHostKeyChecking=no\" ${SOURCE_SYNC}/${rsync_command_folder} \"${rsync_command_connect_user}\"@$CLONE_NODE:$DEST_SYNC"
                fi
                ${rsync_command_start} --rsync-path="sudo sudo -u ${rsync_command_destuser} rsync" --chmod=D2770,F770 -rltpgD --log-file=$LOGFILE --rsh="ssh -o StrictHostKeyChecking=no" ${SOURCE_SYNC}/${rsync_command_folder} "${rsync_command_connect_user}"@$CLONE_NODE:$DEST_SYNC
        fi

        rsync_exit_code=$?

        if [ "$rsync_exit_code" -ne "0" ] ; then
                log Error when calling RSYNC - exit code: $rsync_exit_code
        fi

        log Finished Synchronization of Files 

}

rsync_auto_command()
{
        auto_folder=$3
        folder_end=$4

        if [[ $auto_folder == *"$folder_end" ]]; then
                log "rsync_local_command $1 $2 $3"
                rsync_local_command $1 $2 $3
        else
                log "skipping directory $auto_folder"
                return 0
        fi

} 


rsync_auto()
{       
        log "sync mode is $1 - $P4"
        copy_mode=$1
        folder_end=$2

        for d in $SOURCE_SYNC/* ; do
            if [ -d "$d" ]; then
                USER_NAME=$(ls -ld $d | awk '{print $3}')
                FOLDER_NAME=$(basename "$d")

                if [[ $USER_NAME == "oracle" ]] || [[ $USER_NAME == "nobody" ]]; then
                        log "skip $FOLDER_NAME - $USER_NAME - check on oracle and nobody"
                else
                        log do_${copy_mode} $FOLDER_NAME with $USER_NAME
                        rsync_auto_command ${copy_mode} $USER_NAME $FOLDER_NAME $folder_end
                fi

            fi
        done
}

rsync_local()
{
        if [[ $# -ne 1 ]];then
                errorlog "internal error wrong parameter"
                exit 1
        fi

        local copy_mode=$1

        log "rsync local mode is ${copy_mode}"

        log Performing RSYNC

	if [ ${P2} == 'admin' ]; then
	    log do_${copy_mode} opda_p
	    rsync_local_command ${copy_mode} opdaadm_p opda_p
	fi

        if [ ${P2} == 'opda' ]; then
            log do_${copy_mode} opda_p
        fi

        if [ ${P2} == 'stat' ]; then
            log do_${copy_mode} ast_p
            rsync_local_command ${copy_mode} statadm_p ast_p
            log do_${copy_mode} bst_p
            rsync_local_command ${copy_mode} statadm_p bst_p
            log do_${copy_mode} eco_p
            rsync_local_command ${copy_mode} statadm_p eco_p
            log do_${copy_mode} fst_p
            rsync_local_command ${copy_mode} statadm_p fst_p
            log do_${copy_mode} ls2_p
            rsync_local_command ${copy_mode} statadm_p ls2_p
        fi

}

rsync_batch()
{
        if [[ $# -ne 1 ]];then
                errorlog "internal error wrong parameter"
                exit 1
        fi

        local copy_mode=$1

        log "rsync mode is ${copy_mode}"

	if [ ${P2} == 'admin' ]; then
            log do_${copy_mode} opda_p
            rsync_command ${copy_mode} opdaadm_p opda_p
        fi


        log Performing RSYNC
        if [ ${P2} == 'opda' ]; then
            log do_${copy_mode} opda_p
            rsync_command ${copy_mode} opdaadm_p opda_p
            log do_${copy_mode} odrdwh_p
            rsync_command ${copy_mode} opdaadm_p odrdwh_p
            log do_${copy_mode} odrods_p
            rsync_command ${copy_mode} odsadm_p odrods_p
            log do_${copy_mode} odsftpin_p
            rsync_command ${copy_mode} odsftpin_p odsftpin_p
            log do_${copy_mode} ods_p
            rsync_command ${copy_mode} odsadm_p ods_p
        fi
}

sync () {
       
        log "start $P1 $P2 $P3 $P4 "
        if [ ! -z "$P4" ] && [ $P4 != "dry"  ]; then
                        log "wrong parameter $P2 not allowed"
                        exit 1
        fi

	# DG CHeck
	CheckNode $CHECK_SCRIPT $CHECK_STATE $P3

        rsync_auto sync $P2 

	log_end_backup $SED_STRING
}

copy () {
        
        log "start $P1 $P2 $P3 "
       if [ ! -z "$P4" ] && [ $P4 != "dry"  ]; then
                log "wrong parameter $P2 not allowed"
                exit 1
        fi

	# DG CHeck
	CheckNode $CHECK_SCRIPT $CHECK_STATE $P3

        rsync_auto copy $P2

	log_end_backup $SED_STRING

}

syncall () {
       
        log "syncall: start $P1 $P2 $P3"
        if [ ! -z "$P3" ] && [ $P3 != "dry"  ]; then
                        log "wrong parameter $P2 not allowed"
                        exit 1
        fi

        rsync_auto syncall $P2

	log_end_backup $SED_STRING
}

copyall () {
        
        log "copyall: start $P1 $P2 "
       if [ ! -z "$P3" ] && [ $P3 != "dry"  ]; then
                log "wrong parameter $P2 not allowed"
                exit 1
        fi

        rsync_auto copyall $P2

	log_end_backup $SED_STRING

}

sync_manual()
{
        if [[ $P2 == "dry" ]]; then
                log "wrong folder name $P2 not allowed"
                exit 1
        fi

        log "start $P1 $P2 sync_batches"

  	newsectionlog sync_local
	rsync_local sync

	log "end $P1 $P2 sync_batches"

	log_end_backup $SED_STRING
}

copy_manual()
{
        if [[ $P2 == "dry" ]]; then
                log "wrong folder name $P2 not allowed"
                exit 1
        fi

	log "start $P1 $P2 copy_batches"

	newsectionlog copy_local
	rsync_local copy

	log "end $P1 $P2 copy_batches"

	log_end_backup $SED_STRING
}

sync_batches()
{
        set_remote_node
        log "start $P1 $P2 sync_batches"
  	newsectionlog sync_batches
	rsync_batch sync
	log "end $P1 $P2 sync_batches"
	log_end_backup $SED_STRING
}

copy_batches()
{
        set_remote_node
	log "start $P1 $P2 copy_batches"
	newsectionlog copy_batches
	rsync_batch copy
	log "end $P1 $P2 copy_batches"
	log_end_backup $SED_STRING
}


##################################
## program steps
###################################

check_environment


if [ $P_COUNT -lt 2 -o $P_COUNT -gt 4 ] ; then
        echo "wrong numbers of parameter (1-4)"
        usage_funct
        exit
fi


if [[ ${P4} != "dry" &&  $P_COUNT == "4" ]]; then
        echo "wrong numbers of parameter (4-dry)"
        usage_funct
        exit
fi

if [[ ${P4} == "dry" ]];then
        echo " ===========  dry run  =============="
fi

if [[ ${P3} == "dry" ]];then
        echo " ===========  dry run  =============="
        P4=dry
fi

if [[ ${P2} == "dry" ]];then
        echo " ===========  dry run  =============="
        P4=dry
fi

# logging
logsetup

#sed Suchstring fuer chk_err_func
echo "Starting...." >> $LOGFILE
echo "$SED_STRING" >> $LOGFILE
echo "" >> $LOGFILE

log $SED_STRING

#--------------
#Hilfsvariablen
#--------------
WAIT_COUNT=0
X=0
Y=0
ALLOC_CHANNEL=""
RELEASE_CHANNEL=""
AC=""
FAIL=""
OBRONLINE=""

case $P1 in
        sync) sync
                ;;
        copy) copy
                ;;
        syncall) syncall
                ;;
        copyall) copyall
                ;;
        sync_manual) sync_manual
                ;;
        copy_manual) copy_manual
                ;;
        sync_batches) sync_batches
                ;;
        copy_batches) copy_batches
                ;;
	rsync_batch) rsync_batch
	        ;;
        rsync_batch_no_delete) rsync_batch_no_delete
                ;;
        *)      usage_funct
                ;;
esac
