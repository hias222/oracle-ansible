#!/bin/bash
#####################################################
#
# Check File Permissions
#
# _BA-IT-Systemhaus-TEC4-Datenbanken-Exadata <IT-Systemhaus.TEC4-DB-EXA@arbeitsagentur.de>
#
# description
# check and correct file permissions to copy it to second storage
#
#####################################################
#
# Release history
# 22.12.2021 MFU first release
#
#####################################################
##
#
SCRIPT_VERSION="0.1"
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
SCRIPT_DIR=/home/oracle/sync
SOURCE_SYNC=/batches
DEST_SYNC=/batches
LOCAL_SYNC=/rbatches

# for TESTING
#SOURCE_SYNC=/Users/MFU/tmp
#DEST_SYNC=/batches
#LOCAL_SYNC=/Users/MFU/tmp2
#BASE_BCK_DIR=/Users/MFU/log
#SCRIPT_DIR=/Users/MFU/projects/work/ba/setup/scripting/suseimage/sync

RETAIN_NUM_LINES=1000
RMAN_CHANNELS=4

## Logging
MY_DATE="`date '+%Y%m%d_%H%M%S'`"
MY_DOW="`date '+%u'`"
MY_HOSTNAME=`/bin/hostname | awk -F '.' '{ print $1 }'`
LOGFILE="${BASE_BCK_DIR}/check${P2}/${MY_HOSTNAME}_${MY_DATE}.log"

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
        echo "Aufruf:$0 <FUNCTION> <option>"
        echo "Bsp.: $0 check <_p>"
        echo " "
        echo "  FUNCTION:"
        echo "          check                    -> check files in files /batches"
        echo "          correct                  -> change files in files /batches to group of top owner and 2770"
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

function check_environment
{
        ##### LOG Dir
        ##$BASE_BCK_DIR/logs/$P2
        if [ -d "${BASE_BCK_DIR}/check${P2}" ]; then
                log "Directory $BASE_BCK_DIR/check$P2 exists."
                chmod a+rw ${BASE_BCK_DIR}/sync${P2}
                touch $LOGFILE
                chmod a+rw $LOGFILE
        else
                mkdir -p $BASE_BCK_DIR/check${P2}
                chmod a+rw $BASE_BCK_DIR/check${P2}
                touch $LOGFILE
                chmod a+rw $LOGFILE
                logsetup
                log "Directory $BASE_BCK_DIR/check${P2} created."
        fi

	echo BASE_BCK_DIR $BASE_BCK_DIR
        echo SCRIPT_DIR $SCRIPT_DIR
        echo CLONE_NODE $CLONE_NODE
        echo LOGFILE $LOGFILE
        echo DEST_SYNC $DEST_SYNC

}

function check_file_readable()
{
    FILE_NAME_CHECK=$1
    if [[ ! -r $FILE_NAME_CHECK ]]; then
        return 1
    else
        return 0 
    fi
}

function correct_file_rights() {

        FILE_USER_NAME=$1
        GROUP_NAME=$2
        fname=$3

        sudo sudo -u $FILE_USER_NAME chgrp ${GROUP_NAME} $fname
        if [[ $? != 0 ]]; then
                sudo chgrp ${GROUP_NAME} $fname
                if [[ $? != 0 ]]; then
                        echo "sudo sudo -u $FILE_USER_NAME chgrp ${GROUP_NAME} $fname"
                        echo "failed correct group $fname as $FILE_USER_NAME and root "
                fi
        fi

        sudo sudo -u $FILE_USER_NAME chmod 2770 $fname
        if [[ $? != 0 ]]; then
                sudo chmod 2770 $fname
                if [[ $? != 0 ]]; then
                        echo "sudo sudo -u $FILE_USER_NAME chmod 2770 $fname"
                        echo "failed correct mod 2770 $fname as $FILE_USER_NAME and root"
                fi
        fi

        log "changed $fname"

}

function check_source_folder()
{
        USER_NAME=$2
        GROUP_NAME=$3
        auto_folder=$1
        check_mode=$4

        error_files=false

        if [[ ${check_mode} == 'correct' ]]; then
                log "correct on groupname ${GROUP_NAME}"
        else
                log "check on groupname ${GROUP_NAME}"
        fi

        # check folder with files without group read permission 

        sudo -u $USER_NAME find ${auto_folder} ! -group ${GROUP_NAME} |while read fname; do

                #check_file_readable as User
                sudo sudo -u $USER_NAME bash -c "$(declare -f check_file_readable); check_file_readable $fname"

                if [[ $? != 0 ]]; then
                        FILE_USER_NAME=$(ls -ld $fname | awk '{print $3}')
                        FILE_GROUP_NAME=$(ls -ld $fname | awk '{print $4}')
                        errorlog "not readable as $USER_NAME on $fname (user: $FILE_USER_NAME group: $FILE_GROUP_NAME)"
                        if [[ ${check_mode} == 'correct' ]]; then
                                correct_file_rights $FILE_USER_NAME $GROUP_NAME $fname
                        fi
                        error_files=true
                fi       

                if [[ ${DEBUG} == "true" ]]; then
                        log "different group $fname"
                fi 
               
        done

        if [[ $error_files == "true" ]]; then
                errorlog "found files without read access"
        fi

        return 0
}

check_auto_command()
{
        check_mode=$1
        USER_NAME=$2
        GROUP_NAME=$3
        auto_folder=$4
        folder_end=$5

        if [[ $auto_folder == *"$folder_end" ]]; then
                log "check_source_folder $SOURCE_SYNC/${auto_folder}"
                check_source_folder $SOURCE_SYNC/${auto_folder} ${USER_NAME} ${GROUP_NAME} ${check_mode}
        else
                log "skipping directory $auto_folder"
                return 0
        fi

} 

check_auto()
{       
        log "mode is $1 with end $2 "
        check_mode=$1
        folder_end=$2

        for d in $SOURCE_SYNC/* ; do
            if [ -d "$d" ]; then
                USER_NAME=$(ls -ld $d | awk '{print $3}')
                GROUP_NAME=$(ls -ld $d | awk '{print $4}')
                FOLDER_NAME=$(basename "$d")

                if [[ $USER_NAME == "oracle" ]] || [[ $USER_NAME == "nobody" ]]; then
                        log "skip $FOLDER_NAME - $USER_NAME - check on oracle and nobody"
                else
                        log do_${check_mode} $FOLDER_NAME with $USER_NAME
                        check_auto_command ${check_mode} $USER_NAME $GROUP_NAME $FOLDER_NAME $folder_end
                fi

            fi
        done
}

check_files()
{       
        folder_end=$1
        log "check files with end ${folder_end} in ${SOURCE_SYNC}"
        check_auto checkonly ${folder_end}
}

correct_files()
{       
        folder_end=$1
        log "correct files with end ${folder_end} in ${SOURCE_SYNC}"
        check_auto correct ${folder_end}
}

# logging
check_environment
logsetup
echo "Log $LOGFILE"

if [[ ${DEBUG} == "true" ]]; then
        log "debug is on"
fi

case $P1 in
        check) check_files $P2
                ;;
        correct) correct_files $P2
                ;;
        *)      usage_funct
                ;;
esac
