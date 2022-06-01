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
# 19.10.2021 MFU 0.1    Initiale Version
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
 
# BASE_BCK_DIR=/clonebackup
# SCRIPT_DIR=$BASE_BCK_DIR/scripts
 
BASE_BCK_DIR=/orasw/oracle/BA/adm/log
SCRIPT_DIR=/home/oracle/scripts
 
RETAIN_NUM_LINES=1000
RMAN_CHANNELS=4
 
## Logging
MY_DATE="`date '+%Y%m%d_%H%M%S'`"
MY_DOW="`date '+%u'`"
MY_HOSTNAME=`/bin/hostname | awk -F '.' '{ print $1 }'`
LOGFILE="$BASE_BCK_DIR/$P2/${MY_HOSTNAME}_${MY_DATE}.log"
SOURCE_SYNC=/batches
DEST_SYNC=/batches
LOCAL_SYNC=/rbatches
#
#SOURCE_SYNC=/Users/MFU/tmp
#LOCAL_SYNC=/Users/MFU/tmp2
# start as oracle -> use of certs of oracle
# false start as dest user
RSYNC_AS_ACTUAL_USER=false
BASE_SSH_USER_NAME=oracle
CONNECT_AS_SYNC_USER=false
CLONE_NODE=localhost
DRY_RUN=false
 
DEBUG=true
 
NUMBER_FILES=0
NUMBER_DIRS=0
 
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
        echo "Aufruf:$0 <Folder> "
        echo "Bsp.: $0 count /batches"
        echo " "
        echo "  FUNCTION:"
        echo "          count                    -> count files in folde "
        echo "--------------------------------------------------------------------------------------"
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
 
function check_environment
{
        log BASE_BCK_DIR $BASE_BCK_DIR
        log SCRIPT_DIR $SCRIPT_DIR
        log CLONE_NODE $CLONE_NODE
        log LOGFILE $LOGFILE
        log DEST_SYNC $DEST_SYNC
 
        ##### LOG Dir
        ##$BASE_BCK_DIR/logs/$P2
        if [ -d "$BASE_BCK_DIR/$P2" ]; then
                log "Directory $BASE_BCK_DIR/$P2 exists."
                chmod a+rw $BASE_BCK_DIR/$P2
                touch $LOGFILE
                chmod a+w $LOGFILE
        else
                mkdir -p $BASE_BCK_DIR/$P2
                chmod a+rw $BASE_BCK_DIR/$P2
                logsetup
                log "Directory $BASE_BCK_DIR/$P2 created."
        fi
 
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
 
count_auto_command()
{
        local auto_folder=$(echo "$1" | tr -d '"')
        count_value=$(ls -f $auto_folder |wc -l)
        let NUMBER_FILES=NUMBER_FILES+count_value
        let NUMBER_DIRS++
        if [ $count_value -gt 100 ]; then
                log "in $auto_folder $count_value ($NUMBER_FILES - $NUMBER_DIRS)"
        fi
 
}
 
 
count_auto()
{
        local base_folder=$(echo "$1" | tr -d '"')
 
        for d in `find ${base_folder} -maxdepth 1 -type d ` ; do
            if [ -d "$d" ]; then
                if [[ $d != ${base_folder} ]];then
                    count_auto_command \"${d}\"
                    count_auto \"${d}\"
                fi
            fi
        done
}
 
####
 
###########################################################
 
if [ $P_COUNT -lt 2 -o $P_COUNT -gt 2 ] ; then
        echo "wrong numbers of parameter (1-4)"
        usage_funct
        exit
fi
 
 
# logging
logsetup
log Log to $LOGFILE
 
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
SED_STRING=""
OBRONLINE=""
 
##################################
## program steps
###################################
 
count () {
 
       log "start $P1 $P2 "
       count_auto "$P2"
 
}
 
case $P1 in
        count) count
                ;;
        *)      usage_funct
                ;;
esac
