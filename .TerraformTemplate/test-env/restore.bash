#!/bin/bash


# get JSON File to feed into jq
# oci --profile ba bv volume-group-backup list --all --compartment-id ocid1.compartment.oc1..aaaaaaaageojzaogxd3ko43ycjgitytvsyg2p6e7hvfjvx4bcdgkemz26t5q --display-name VGasmdisk0

# get number of different timestamps
# jq --raw-output '[.data[] | select(."lifecycle-state"=="AVAILABLE")] | length'
# get list of different timestamps
# jq --raw-output '.data[] | select(."lifecycle-state"=="AVAILABLE") | ."freeform-tags"."Timestamp"'

# bEDy:EU-FRANKFURT-1-AD-1
# bEDy:EU-FRANKFURT-1-AD-2
# bEDy:EU-FRANKFURT-1-AD-3

PROFILE=ba
# the compartment to work with
COMPARTMENT_ID="###IT_SHOULD_BE_OBVIOUS_THIS_MUST_BE_REPLACED_BY_THE_REAL_COMPARTMENT_OCID####"

# name of resource we look for when checking for savepoints in source compartments
VGZERO="VGasmdisk0"

# name of subcompartment for backups
BCKP_COMPARTMENT_NAME="Sicherungen"
# string will be appended to compartment name to distinguish the backup compartment and work compartment
APPENDIX="BCKP"

# Timestamp
TIMESTAMP=$(date "+%Y%m%d%H%M%S")

# generate a unique ID to tag resources created by this script
UNIQUE_ID="k4JgHrt${TIMESTAMP}"
if [ -e /dev/urandom ];then
 UNIQUE_ID=$(cat /dev/urandom|LC_CTYPE=C tr -dc "[:alnum:]"|fold -w 32|head -n 1)
fi

# array keeps a list of temporary files to cleanup
TMP_FILE_LIST=()

# do not change value if set in environment
DEBUG_PRINT="${DEBUG_PRINT:=false}"

# filename of this script
THIS_SCRIPT="$(basename ${BASH_SOURCE})"

# Do cleanup
function Cleanup() {
  for i in "${!TMP_FILE_LIST[@]}"; do
    if [ -f "${TMP_FILE_LIST[$i]}" ]; then
      debug_print "deleting ${TMP_FILE_LIST[$i]}"
      rm -f "${TMP_FILE_LIST[$i]}"
    fi
  done
}

# Do cleanup, display error message and exit
function Interrupt() {
  Cleanup
  exitcode=99
  echo -e "\nScript '${THIS_SCRIPT}' aborted by user."
  exit $exitcode
}

# trap ctrl-c and call interrupt()
trap Interrupt INT
# trap exit and call cleanup()
trap Cleanup   EXIT

debug_print()
{
  if ${DEBUG_PRINT}; then
    echo -e "$1"
  fi
}

# call:
# tempfile my_temp_file
# to create a tempfile. The generated file is $my_temp_file
function tempfile()
{
  local __resultvar=$1
  local __tmp_file=$(mktemp -t ${THIS_SCRIPT}_tmp_file.XXXXXXXXXXX) || {
    echo "*** Creation of ${__tmp_file} failed";
    exit 1;
  }
  TMP_FILE_LIST+=("${__tmp_file}")
  if [[ "$__resultvar" ]]; then
    eval $__resultvar="'$__tmp_file'"
  else
    echo "$__tmp_file"
  fi
}

     FROM_PARAM="--from"
SAVEPOINT_PARAM="--savepoint"

usage()
{
  echo -e "\nUsage :"
  echo -e "        $(basename $0)"
  echo -e "        to list the possible restore points (available backups) for the current compartment\n"
  echo -e "        $(basename $0) ${FROM_PARAM} <compartment_name>"
  echo -e "        to list the possible restore points (available backups) from another compartment\n"
  echo -e "        $(basename $0) [${FROM_PARAM} <compartment_name>] ${SAVEPOINT_PARAM} <savepoint>"
  echo -e "        to restore from a restore point [from another compartment]\n"
  exit
}

case "$#" in
    0)
      unset SOURCE_COMPARTMENT
      unset SAVEPOINT
      ;;
    2)
      case "$1" in
          "${FROM_PARAM}" | "${SAVEPOINT_PARAM}")
            if [[ "$1" == "${FROM_PARAM}" ]]; then
              SOURCE_COMPARTMENT="$2"
              unset SAVEPOINT
            else
              unset SOURCE_COMPARTMENT
              SAVEPOINT="$2"
            fi
            ;;
          *)
            usage;
      esac
      ;;
    4)
      case "$1" in
          "${FROM_PARAM}")
            if [[ "$3" != "${SAVEPOINT_PARAM}" ]]; then
              usage
            fi
            SOURCE_COMPARTMENT="$2"
            SAVEPOINT="$4"
            ;;
          *)
            usage;
      esac
      ;;
    *)
      usage;
esac
debug_print "#### Parameter provided:"
debug_print "      SOURCE_COMPARTMENT : \"${SOURCE_COMPARTMENT}\""
debug_print "               SAVEPOINT : \"${SAVEPOINT}\"\n"

# get information about the current compartment
tempfile CURRENT_COMPARTMENT
oci --profile "${PROFILE}" iam compartment get --compartment-id "${COMPARTMENT_ID}" > "${CURRENT_COMPARTMENT}"
COMPARTMENT_NAME="$(cat "${CURRENT_COMPARTMENT}"|jq --raw-output '.data."name"')"
PARENT_COMPARTMENT_ID="$(cat "${CURRENT_COMPARTMENT}"|jq --raw-output '.data."compartment-id"')"
       echo "current compartment name : $COMPARTMENT_NAME"
debug_print "   parent_compartment_id : $PARENT_COMPARTMENT_ID"

# get information about the parent compartment
tempfile PARENT_COMPARTMENT
oci --profile "${PROFILE}" iam compartment get --compartment-id "${PARENT_COMPARTMENT_ID}" > "${PARENT_COMPARTMENT}"
PARENT_COMPARTMENT_NAME="$(cat "${PARENT_COMPARTMENT}"|jq --raw-output '.data."name"')"
PARENT_COMPARTMENT_ID="$(cat "${PARENT_COMPARTMENT}"|jq --raw-output '.data."id"')"
debug_print " parent compartment name : $PARENT_COMPARTMENT_NAME"
debug_print "   parent_compartment_id : $PARENT_COMPARTMENT_ID"

# get the compartment used for backups e.g. "Sicherungen"
tempfile COMPARTMENT_LIST
oci --profile "${PROFILE}" iam compartment list --all --compartment-id "${PARENT_COMPARTMENT_ID}" --lifecycle-state active --name "${BCKP_COMPARTMENT_NAME}" > "${COMPARTMENT_LIST}"
num_compartments=$(( $(cat "${COMPARTMENT_LIST}"|jq --raw-output '.data | length') + 0 ))
if [[ $num_compartments != 1 ]]; then
  echo "Could not identify the Compartment used for backups"
  exit
fi
BCKP_COMPARTMENT_ID="$(cat "${COMPARTMENT_LIST}"|jq --raw-output '.data[0]."id"')"


# create a backup subcompartment in backup compartment for current compartment
if [ -z ${SOURCE_COMPARTMENT+x} ]; then
  # SOURCE_COMPARTMENT was not set
  MY_BCKP_COMPARTMENT_NAME="${COMPARTMENT_NAME}${APPENDIX}"
else
  MY_BCKP_COMPARTMENT_NAME="${SOURCE_COMPARTMENT}${APPENDIX}"
fi
echo "MY_BCKP_COMPARTMENT_NAME : ${MY_BCKP_COMPARTMENT_NAME}"
tempfile COMPARTMENT_LIST
oci --profile "${PROFILE}" iam compartment list --all --compartment-id "${BCKP_COMPARTMENT_ID}" --lifecycle-state active --name "${MY_BCKP_COMPARTMENT_NAME}" > "${COMPARTMENT_LIST}"
num_compartments=$(( $(cat "${COMPARTMENT_LIST}"|jq --raw-output '.data | length') + 0 ))
if [[ $num_compartments != 1 ]]; then
  echo "the backup compartment \"$MY_BCKP_COMPARTMENT_NAME\" does not exist in \"$BCKP_COMPARTMENT_NAME\""
  exit
else
  echo "found \"$MY_BCKP_COMPARTMENT_NAME\" below the \"$BCKP_COMPARTMENT_NAME\" compartment"
fi
# get ocid of backup compartment
tempfile COMPARTMENT_LIST
oci --profile "${PROFILE}" iam compartment list --all --compartment-id "${BCKP_COMPARTMENT_ID}" --lifecycle-state active --name "${MY_BCKP_COMPARTMENT_NAME}" > "${COMPARTMENT_LIST}"
num_compartments=$(( $(cat "${COMPARTMENT_LIST}"|jq --raw-output '.data | length') + 0 ))
if [[ $num_compartments != 1 ]]; then
  echo -e "\nthere is more than one or no compartment \"${MY_BCKP_COMPARTMENT_NAME}\" below \"$BCKP_COMPARTMENT_NAME\"\n\nGiving up. Exiting.\n"
  exit
fi
MY_BCKP_COMPARTMENT="$(cat "${COMPARTMENT_LIST}"|jq --raw-output '.data[0]."id"')"
debug_print "MY_BCKP_COMPARTMENT=${MY_BCKP_COMPARTMENT}"



tempfile SAVEPOINT_LIST
debug_print "oci --profile \"${PROFILE}\" bv volume-group-backup list --all --compartment-id \"${MY_BCKP_COMPARTMENT}\" --display-name \"${VGZERO}\" > \"${SAVEPOINT_LIST}\""
oci --profile "${PROFILE}" bv volume-group-backup list --all --compartment-id "${MY_BCKP_COMPARTMENT}" --display-name "${VGZERO}" > "${SAVEPOINT_LIST}"
num_savepoints=$(( $(cat "${SAVEPOINT_LIST}"|jq --raw-output '[.data[] | select(."lifecycle-state"=="AVAILABLE")] | length') + 0 ))
debug_print "Number of Savepoints : $num_savepoints"
if [[ $num_savepoints == 0 ]]; then
  echo "no savepoints in compartment ${MY_BCKP_COMPARTMENT_NAME}"
  exit
fi
if [ -z ${SAVEPOINT+x} ]; then
  # display the list of savepoints and exit
  echo "#### Available Savepoints in Compartment ${MY_BCKP_COMPARTMENT_NAME}:"
  cat "${SAVEPOINT_LIST}"|jq --raw-output '.data[] | select(."lifecycle-state"=="AVAILABLE") | ."freeform-tags"."Timestamp"'
  exit
else
  # check if the provided savepoint exists
num_hits=$(( $(jq --raw-output '[.data[] | select(."freeform-tags"."Timestamp"=="'${SAVEPOINT}'" and ."lifecycle-state"=="AVAILABLE")] | length' "${SAVEPOINT_LIST}") + 0 ))
  debug_print "num_hits = $num_hits"
  if [[ $num_hits == 0 ]]; then
    echo "#### I could not find the savepoint $SAVEPOINT in compartment $MY_BCKP_COMPARTMENT_NAME"
    exit
  fi
  if [[ $num_hits > 1 ]]; then
    echo "#### savepoint $SAVEPOINT seems to exist more than once in compartment $MY_BCKP_COMPARTMENT_NAME"
    exit
  fi
fi
# source compartment and requested savepoint do exist at this point

# start with housekeeping

# delete all volume-group backups
tempfile BACKUP_LIST
DEBUG_PRINT=true debug_print "oci --profile \"${PROFILE}\" bv volume-group-backup list --all --compartment-id \"${COMPARTMENT_ID}\" | jq --raw-output '[.data[] | select(.\"lifecycle-state\"==\"AVAILABLE\")]' > \"${BACKUP_LIST}\""
oci --profile "${PROFILE}" bv volume-group-backup list --all --compartment-id "${COMPARTMENT_ID}" | jq --raw-output '[.data[] | select(."lifecycle-state"=="AVAILABLE")]' > "${BACKUP_LIST}"
num_vols=$(( $(jq --raw-output 'length' "${BACKUP_LIST}") + 0))
debug_print "will delete $num_vols volume group backups"
for ((i=0; i<$num_vols; i++)); do
  BV_ID=$(jq --raw-output '.['$i'] | ."id"' "${BACKUP_LIST}")
  debug_print "oci --profile \"${PROFILE}\" bv volume-group-backup delete --force --volume-group-backup-id \"${BV_ID}\" --wait-for-state TERMINATED"
  oci --profile "${PROFILE}" bv volume-group-backup delete --force --volume-group-backup-id "${BV_ID}" --wait-for-state TERMINATED
done

# delete all Volume Backups in the current compartment
DEBUG_PRINT=true debug_print "oci --profile \"${PROFILE}\" bv backup list --all --compartment-id \"${COMPARTMENT_ID}\" | jq --raw-output '[.data[] | select(.\"lifecycle-state\"==\"AVAILABLE\")]' > \"${BACKUP_LIST}\""
oci --profile "${PROFILE}" bv backup list --all --compartment-id "${COMPARTMENT_ID}" | jq --raw-output '[.data[] | select(."lifecycle-state"=="AVAILABLE")]' > "${BACKUP_LIST}"
num_vols=$(( $(jq --raw-output 'length' "${BACKUP_LIST}") + 0))
debug_print "will delete $num_vols volume backups"
for ((i=0; i<$num_vols; i++)); do
  BV_ID=$(jq --raw-output '.['$i'] | ."id"' "${BACKUP_LIST}")
  debug_print "oci --profile \"${PROFILE}\" bv backup delete --force --volume-backup-id \"${BV_ID}\" --wait-for-state TERMINATED"
  oci --profile "${PROFILE}" bv backup delete --force --volume-backup-id "${BV_ID}" --wait-for-state TERMINATED
done

# delete all Boot Volume Backups in the current compartment
debug_print "oci --profile \"${PROFILE}\" bv boot-volume-backup list --all --compartment-id \"${COMPARTMENT_ID}\" | jq --raw-output '[.data[] | select(.\"lifecycle-state\"==\"AVAILABLE\")]' > \"${BACKUP_LIST}\""
oci --profile "${PROFILE}" bv boot-volume-backup list --all --compartment-id "${COMPARTMENT_ID}" | jq --raw-output '[.data[] | select(."lifecycle-state"=="AVAILABLE")]' > "${BACKUP_LIST}"
num_vols=$(( $(jq --raw-output 'length' "${BACKUP_LIST}") + 0))
debug_print "will delete $num_vols boot volume backups"
for ((i=0; i<$num_vols; i++)); do
  BV_ID=$(jq --raw-output '.['$i'] | ."id"' "${BACKUP_LIST}")
  debug_print "oci --profile \"${PROFILE}\" bv boot-volume-backup delete --force --boot-volume-backup-id \"${BV_ID}\" --wait-for-state TERMINATED"
  oci --profile "${PROFILE}" bv boot-volume-backup delete --force --boot-volume-backup-id "${BV_ID}" --wait-for-state TERMINATED
done
# end of housekeeping

# generate array of availability domain names
tempfile AD_LIST_JSON
AD_NAME=()
oci --profile "${PROFILE}" iam availability-domain list --all > "${AD_LIST_JSON}"
num_ads=$(( $(cat "${AD_LIST_JSON}"|jq --raw-output '.data | length') + 0 ))
debug_print "#ADs : $num_ads"
for ((i=0; i<$num_ads; i++)); do
  AD_NAME+=("$(cat "${AD_LIST_JSON}"|jq --raw-output '.data['$i']."name"')")
done
for i in "${!AD_NAME[@]}"; do
  DEBUG_PRINT=false debug_print "#### ${AD_NAME[$i]}"
done

# because boot volume backups can't be copied, create boot volumes from boot volume backups,
# create boot volume backups from the newly created boot volumes,
# move the newly created boot volume backups to the target compartment

# create boot volumes
tempfile BOOT_VOLUMES
DEBUG_PRINT=true debug_print "oci --profile \"${PROFILE}\" bv boot-volume-backup list --all --compartment-id \"${MY_BCKP_COMPARTMENT}\" | jq --raw-output '[.data[] | select(.\"freeform-tags\".\"Timestamp\"==\"'${SAVEPOINT}'\" and .\"lifecycle-state\"==\"AVAILABLE\")]' > \"${BOOT_VOLUMES}\""
oci --profile "${PROFILE}" bv boot-volume-backup list --all --compartment-id "${MY_BCKP_COMPARTMENT}" | jq --raw-output '[.data[] | select(."freeform-tags"."Timestamp"=="'${SAVEPOINT}'" and ."lifecycle-state"=="AVAILABLE")]' > "${BOOT_VOLUMES}"
num_vols=$(( $(jq --raw-output 'length' "${BOOT_VOLUMES}") + 0))
debug_print "num_vols = $num_vols"
for ((i=0; i<$num_vols; i++)); do
  BV_ID=$(jq --raw-output '.['$i'] | ."id"' "${BOOT_VOLUMES}")
  BV_NAME=$(jq --raw-output '.['$i'] | ."display-name"' "${BOOT_VOLUMES}")
  BV_AD=$(jq --raw-output '.['$i'] | ."freeform-tags"."availability-domain"' "${BOOT_VOLUMES}")
  debug_print "oci --profile \"${PROFILE}\" bv boot-volume create --display-name \"${BV_NAME}\" --freeform-tags \"{\"unique-id\": \"$UNIQUE_ID\"}\" --boot-volume-backup-id \"${BV_ID}\" --availability-domain \"${BV_AD}\" --wait-for-state AVAILABLE"
  oci --profile "${PROFILE}" bv boot-volume create --display-name "${BV_NAME}" --freeform-tags "{\"unique-id\": \"$UNIQUE_ID\"}" --boot-volume-backup-id "${BV_ID}" --availability-domain "${BV_AD}" --wait-for-state AVAILABLE
done

# create boot volume backups from the newly created boot volumes and delete the boot volumes afterward
for i in "${!AD_NAME[@]}"; do
  DEBUG_PRINT=true debug_print "#### processing boot volumes in ${AD_NAME[$i]}"
  oci --profile "${PROFILE}" bv boot-volume list --all --compartment-id "${MY_BCKP_COMPARTMENT}" --availability-domain "${AD_NAME[$i]}"| jq --raw-output '[.data[] | select(."freeform-tags"."unique-id"=="'${UNIQUE_ID}'" and ."lifecycle-state"=="AVAILABLE")]' > "${BOOT_VOLUMES}"
  num_vols=$(( $(jq --raw-output 'length' "${BOOT_VOLUMES}") + 0 ))
  debug_print "num_vols = $num_vols"
  for ((k=0; k<$num_vols; k++)); do
    BV_ID=$(jq --raw-output '.['$k'] | ."id"' "${BOOT_VOLUMES}")
    BV_NAME=$(jq --raw-output '.['$k'] | ."display-name"' "${BOOT_VOLUMES}")
    debug_print "oci --profile \"${PROFILE}\" bv boot-volume-backup create --display-name \"${BV_NAME}\" --type full --freeform-tags \"{\"unique-id\": \"$UNIQUE_ID\"}\" --boot-volume-id \"${BV_ID}\" --wait-for-state AVAILABLE"
    debug_print "oci --profile \"${PROFILE}\" bv boot-volume delete --boot-volume-id \"${BV_ID}\" --wait-for-state TERMINATED --force"
    # create boot volume backup
    oci --profile "${PROFILE}" bv boot-volume-backup create --display-name "${BV_NAME}" --type full --freeform-tags "{\"unique-id\": \"$UNIQUE_ID\"}" --boot-volume-id "${BV_ID}" --wait-for-state AVAILABLE
    # delete boot volume
    oci --profile "${PROFILE}" bv boot-volume delete --boot-volume-id "${BV_ID}" --wait-for-state TERMINATED --force
  done
done

# move the just created boot volume backups to target compartment
# the just created boot volume backups distinguish themselves from boot volume backups
# created by savepoint.bash by having the unique-id in the freeform-tags
DEBUG_PRINT=true debug_print "oci --profile \"${PROFILE}\" bv boot-volume-backup list --all --compartment-id \"${MY_BCKP_COMPARTMENT}\" | jq --raw-output '[.data[] | select(.\"freeform-tags\".\"unique-id\"==\"'${UNIQUE_ID}'\" and .\"lifecycle-state\"==\"AVAILABLE\")]' > \"${BOOT_VOLUMES}\""
oci --profile "${PROFILE}" bv boot-volume-backup list --all --compartment-id "${MY_BCKP_COMPARTMENT}" | jq --raw-output '[.data[] | select(."freeform-tags"."unique-id"=="'${UNIQUE_ID}'" and ."lifecycle-state"=="AVAILABLE")]' > "${BOOT_VOLUMES}"
num_vols=$(( $(jq --raw-output 'length' "${BOOT_VOLUMES}") + 0))
for ((i=0; i<$num_vols; i++)); do
  BV_ID=$(jq --raw-output '.['$i'] | ."id"' "${BOOT_VOLUMES}")
  echo "oci --profile $PROFILE bv boot-volume-backup change-compartment --boot-volume-backup-id $BV_ID --compartment-id \"${COMPARTMENT_ID}\""
  oci --profile $PROFILE bv boot-volume-backup change-compartment --boot-volume-backup-id $BV_ID --compartment-id "${COMPARTMENT_ID}"
done



################################################################################
################################################################################
# create block volumes
tempfile BLOCK_VOLUMES
DEBUG_PRINT=true debug_print "oci --profile \"${PROFILE}\" bv backup list --all --compartment-id \"${MY_BCKP_COMPARTMENT}\" | jq --raw-output '[.data[] | select(.\"freeform-tags\".\"Timestamp\"==\"'${SAVEPOINT}'\" and .\"lifecycle-state\"==\"AVAILABLE\")]' > \"${BLOCK_VOLUMES}\""
oci --profile "${PROFILE}" bv backup list --all --compartment-id "${MY_BCKP_COMPARTMENT}" | jq --raw-output '[.data[] | select(."freeform-tags"."Timestamp"=="'${SAVEPOINT}'" and ."lifecycle-state"=="AVAILABLE")]' > "${BLOCK_VOLUMES}"
num_vols=$(( $(jq --raw-output 'length' "${BLOCK_VOLUMES}") + 0))
debug_print "num_vols = $num_vols"
for ((i=0; i<$num_vols; i++)); do
  BV_ID=$(jq --raw-output '.['$i'] | ."id"' "${BLOCK_VOLUMES}")
  BV_NAME=$(jq --raw-output '.['$i'] | ."display-name"' "${BLOCK_VOLUMES}")
  BV_AD=$(jq --raw-output '.['$i'] | ."freeform-tags"."availability-domain"' "${BLOCK_VOLUMES}")
  debug_print "oci --profile \"${PROFILE}\" bv volume create --display-name \"${BV_NAME}\" --freeform-tags \"{\"unique-id\": \"$UNIQUE_ID\"}\" --volume-backup-id \"${BV_ID}\" --availability-domain \"${BV_AD}\" --wait-for-state AVAILABLE"
  oci --profile "${PROFILE}" bv volume create --display-name "${BV_NAME}" --freeform-tags "{\"unique-id\": \"$UNIQUE_ID\"}" --volume-backup-id "${BV_ID}" --availability-domain "${BV_AD}" --wait-for-state AVAILABLE
done

################################################################################
################################################################################
# create volume backups from the newly created volumes and delete the volumes afterward
for i in "${!AD_NAME[@]}"; do
  DEBUG_PRINT=true debug_print "#### processing block volumes in ${AD_NAME[$i]}"
  oci --profile "${PROFILE}" bv volume list --all --compartment-id "${MY_BCKP_COMPARTMENT}" --availability-domain "${AD_NAME[$i]}"| jq --raw-output '[.data[] | select(."freeform-tags"."unique-id"=="'${UNIQUE_ID}'" and ."lifecycle-state"=="AVAILABLE")]' > "${BLOCK_VOLUMES}"
  num_vols=$(( $(jq --raw-output 'length' "${BLOCK_VOLUMES}") + 0 ))
  debug_print "num_vols = $num_vols"
  for ((k=0; k<$num_vols; k++)); do
    BV_ID=$(jq --raw-output '.['$k'] | ."id"' "${BLOCK_VOLUMES}")
    BV_NAME=$(jq --raw-output '.['$k'] | ."display-name"' "${BLOCK_VOLUMES}")
    debug_print "oci --profile \"${PROFILE}\" bv backup create --display-name \"${BV_NAME}\" --type full --freeform-tags \"{\"unique-id\": \"$UNIQUE_ID\"}\" --volume-id \"${BV_ID}\" --wait-for-state AVAILABLE"
    debug_print "oci --profile \"${PROFILE}\" bv volume delete --volume-id \"${BV_ID}\" --wait-for-state TERMINATED --force"
    # create boot volume backup
    oci --profile "${PROFILE}" bv backup create --display-name "${BV_NAME}" --type full --freeform-tags "{\"unique-id\": \"$UNIQUE_ID\"}" --volume-id "${BV_ID}" --wait-for-state AVAILABLE
    # delete boot volume
    oci --profile "${PROFILE}" bv volume delete --volume-id "${BV_ID}" --wait-for-state TERMINATED --force
  done
done

################################################################################
################################################################################
# move the just created block volume backups to target compartment
# the just created block volume backups distinguish themselves from block volume backups
# created by savepoint.bash by having the unique-id in the freeform-tags
DEBUG_PRINT=true debug_print "oci --profile \"${PROFILE}\" bv backup list --all --compartment-id \"${MY_BCKP_COMPARTMENT}\" | jq --raw-output '[.data[] | select(.\"freeform-tags\".\"unique-id\"==\"'${UNIQUE_ID}'\" and .\"lifecycle-state\"==\"AVAILABLE\")]' > \"${BLOCK_VOLUMES}\""
oci --profile "${PROFILE}" bv backup list --all --compartment-id "${MY_BCKP_COMPARTMENT}" | jq --raw-output '[.data[] | select(."freeform-tags"."unique-id"=="'${UNIQUE_ID}'" and ."lifecycle-state"=="AVAILABLE")]' > "${BLOCK_VOLUMES}"
num_vols=$(( $(jq --raw-output 'length' "${BLOCK_VOLUMES}") + 0))
for ((i=0; i<$num_vols; i++)); do
  BV_ID=$(jq --raw-output '.['$i'] | ."id"' "${BLOCK_VOLUMES}")
  echo "oci --profile $PROFILE bv backup change-compartment --volume-backup-id $BV_ID --compartment-id \"${COMPARTMENT_ID}\""
  oci --profile $PROFILE bv backup change-compartment --volume-backup-id $BV_ID --compartment-id "${COMPARTMENT_ID}"
done
################################################################################
################################################################################
