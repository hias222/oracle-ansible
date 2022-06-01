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

# get information about the current compartment
tempfile CURRENT_COMPARTMENT
oci --profile "${PROFILE}" iam compartment get --compartment-id "${COMPARTMENT_ID}" > "${CURRENT_COMPARTMENT}"
COMPARTMENT_NAME="$(cat "${CURRENT_COMPARTMENT}"|jq --raw-output '.data."name"')"
PARENT_COMPARTMENT_ID="$(cat "${CURRENT_COMPARTMENT}"|jq --raw-output '.data."compartment-id"')"
echo "current compartment name : $COMPARTMENT_NAME"
echo "parent_compartment_id    : $PARENT_COMPARTMENT_ID"

# get information about the parent compartment
tempfile PARENT_COMPARTMENT
oci --profile "${PROFILE}" iam compartment get --compartment-id "${PARENT_COMPARTMENT_ID}" > "${PARENT_COMPARTMENT}"
PARENT_COMPARTMENT_NAME="$(cat "${PARENT_COMPARTMENT}"|jq --raw-output '.data."name"')"
PARENT_COMPARTMENT_ID="$(cat "${PARENT_COMPARTMENT}"|jq --raw-output '.data."id"')"
echo "parent compartment name : $PARENT_COMPARTMENT_NAME"
echo "parent_compartment_id   : $PARENT_COMPARTMENT_ID"

# get the compartment used for backups
tempfile COMPARTMENT_LIST
oci --profile "${PROFILE}" iam compartment list --all --compartment-id "${PARENT_COMPARTMENT_ID}" --lifecycle-state active --name "${BCKP_COMPARTMENT_NAME}" > "${COMPARTMENT_LIST}"
num_compartments=$(( $(cat "${COMPARTMENT_LIST}"|jq --raw-output '.data | length') + 0 ))
if [[ $num_compartments != 1 ]]; then
  echo "Could not identify the Compartment used for backups"
  exit
fi
BCKP_COMPARTMENT_ID="$(cat "${COMPARTMENT_LIST}"|jq --raw-output '.data[0]."id"')"


# create a backup subcompartment in backup compartment for current compartment
MY_BCKP_COMPARTMENT_NAME="${COMPARTMENT_NAME}${APPENDIX}"
tempfile COMPARTMENT_LIST
oci --profile "${PROFILE}" iam compartment list --all --compartment-id "${BCKP_COMPARTMENT_ID}" --lifecycle-state active --name "${MY_BCKP_COMPARTMENT_NAME}" > "${COMPARTMENT_LIST}"
num_compartments=$(( $(cat "${COMPARTMENT_LIST}"|jq --raw-output '.data | length') + 0 ))
if [[ $num_compartments != 1 ]]; then
  echo "going to create \"${MY_BCKP_COMPARTMENT_NAME}\" below the \"$BCKP_COMPARTMENT_NAME\" compartment"
  echo oci --profile "${PROFILE}" iam compartment create --compartment-id "${BCKP_COMPARTMENT_ID}" --description "holds backups from \"${COMPARTMENT_NAME}\" compartment" --name "${MY_BCKP_COMPARTMENT_NAME}" --wait-for-state active
  oci --profile "${PROFILE}" iam compartment create --compartment-id "${BCKP_COMPARTMENT_ID}" --description "holds backups from \"${COMPARTMENT_NAME}\" compartment" --name "${MY_BCKP_COMPARTMENT_NAME}" --wait-for-state active
else
  echo "found \"$MY_BCKP_COMPARTMENT_NAME\" below the \"$BCKP_COMPARTMENT_NAME\" compartment"
fi
# get ocid of backup compartment
tempfile COMPARTMENT_LIST
oci --profile "${PROFILE}" iam compartment list --all --compartment-id "${BCKP_COMPARTMENT_ID}" --lifecycle-state active --name "${MY_BCKP_COMPARTMENT_NAME}" > "${COMPARTMENT_LIST}"
num_compartments=$(( $(cat "${COMPARTMENT_LIST}"|jq --raw-output '.data | length') + 0 ))
if [[ $num_compartments != 1 ]]; then
  echo -e "\nthere is more than one compartment \"${MY_BCKP_COMPARTMENT_NAME}\" below \"$BCKP_COMPARTMENT_NAME\"\n or it could not be created.\n\nGiving up. Exiting.\n"
  exit
fi
MY_BCKP_COMPARTMENT="$(cat "${COMPARTMENT_LIST}"|jq --raw-output '.data[0]."id"')"
echo "MY_BCKP_COMPARTMENT=${MY_BCKP_COMPARTMENT}"


# shutdown compute instances in compartment
tempfile INSTANCE_LIST_JSON
oci --profile "${PROFILE}" compute instance list --all --lifecycle-state "RUNNING" --compartment-id "${COMPARTMENT_ID}" > "${INSTANCE_LIST_JSON}"
num_instances=$(( $(cat "${INSTANCE_LIST_JSON}"|jq --raw-output '.data | length') + 0 ))

for ((i=0; i<$num_instances; i++)); do
  INSTANCE_ID="$(cat "${INSTANCE_LIST_JSON}"|jq --raw-output '.data['$i']."id"')"
  AD_NAME="$(cat "${INSTANCE_LIST_JSON}"|jq --raw-output '.data['$i']."availability-domain"')"
  debug_print "instance_id = $INSTANCE_ID, ad_name = $AD_NAME"
  echo oci --profile $PROFILE compute instance action --action stop --instance-id $INSTANCE_ID --wait-for-state STOPPED
  oci --profile $PROFILE compute instance action --action stop --instance-id $INSTANCE_ID --wait-for-state STOPPED | jq '.data|{"Server": ."display-name", "Status": ."lifecycle-state"}'
done

## generate array of availability domain names
#tempfile AD_LIST_JSON
#AD_NAME=()
#oci --profile "${PROFILE}" iam availability-domain list --all > "${AD_LIST_JSON}"
#num_ads=$(( $(cat "${AD_LIST_JSON}"|jq --raw-output '.data | length') + 0 ))
#debug_print "#ADs : $num_ads"
#for ((i=0; i<$num_ads; i++)); do
#  AD_NAME+=("$(cat "${AD_LIST_JSON}"|jq --raw-output '.data['$i']."name"')")
#done
#for i in "${!AD_NAME[@]}"; do
#  DEBUG_PRINT=false debug_print "#### ${AD_NAME[$i]}"
#done

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

# iterate all availability domains
tempfile AD_LIST_JSON
oci --profile "${PROFILE}" iam availability-domain list --all > "${AD_LIST_JSON}"
num_ads=$(( $(cat "${AD_LIST_JSON}"|jq --raw-output '.data | length') + 0 ))
debug_print "#ADs : $num_ads"
for ((i=0; i<$num_ads; i++)); do
  AD_NAME=("$(cat "${AD_LIST_JSON}"|jq --raw-output '.data['$i']."name"')")

  # create new boot volume backups in compartment and availability domain
  tempfile BV_LIST_JSON
  oci --profile "${PROFILE}" bv boot-volume list --all --compartment-id "${COMPARTMENT_ID}" --availability-domain "${AD_NAME}" > "${BV_LIST_JSON}"
  num_bvs=$(( $(cat "${BV_LIST_JSON}"|jq --raw-output '.data | length') + 0 ))
  echo "#boot_volumes in AD \"$AD_NAME\" = \"$num_bvs\""
  for ((k=0; k<$num_bvs; k++)); do
    BV_ID=("$(cat "${BV_LIST_JSON}"|jq --raw-output '.data['$k']."id"')")
    BV_NAME="$(cat "${BV_LIST_JSON}"|jq --raw-output '.data['$k']."display-name"')"
    BV_STATE="$(cat "${BV_LIST_JSON}"|jq --raw-output '.data['$k']."lifecycle-state"')"
    if [ "$BV_STATE" == "AVAILABLE" ]; then
      echo oci --profile "${PROFILE}" bv boot-volume-backup create --boot-volume-id "${BV_ID}" --display-name "${BV_NAME}" --type FULL --wait-for-state AVAILABLE --freeform-tags "{\"Timestamp\": \"${TIMESTAMP}\", \"availability-domain\": \"${AD_NAME}\"}"
      oci --profile "${PROFILE}" bv boot-volume-backup create --boot-volume-id "${BV_ID}" --display-name "${BV_NAME}" --type FULL --wait-for-state AVAILABLE --freeform-tags "{\"Timestamp\": \"${TIMESTAMP}\", \"availability-domain\": \"${AD_NAME}\"}"
    fi
  done

  # create new volume group backups in compartment and availability domain
  tempfile VG_LIST_JSON
  oci --profile "${PROFILE}" bv volume-group list --all --lifecycle-state AVAILABLE --compartment-id "${COMPARTMENT_ID}" --availability-domain "${AD_NAME}" > "${VG_LIST_JSON}"
  num_vgs=$(( $(cat "${VG_LIST_JSON}"|jq --raw-output '.data | length') + 0 ))
  echo "#volume groups in AD \"$AD_NAME\" = \"$num_vgs\""
  for ((k=0; k<$num_vgs; k++)); do
    VG_ID=("$(cat "${VG_LIST_JSON}"|jq --raw-output '.data['$k']."id"')")
    VG_NAME="$(cat "${VG_LIST_JSON}"|jq --raw-output '.data['$k']."display-name"')"
    echo oci --profile "${PROFILE}" bv volume-group-backup create --volume-group-id "${VG_ID}" --display-name "${VG_NAME}" --type FULL --wait-for-state AVAILABLE --freeform-tags "{\"Timestamp\": \"${TIMESTAMP}\", \"availability-domain\": \"${AD_NAME}\"}"
    oci --profile "${PROFILE}" bv volume-group-backup create --volume-group-id "${VG_ID}" --display-name "${VG_NAME}" --type FULL --wait-for-state AVAILABLE --freeform-tags "{\"Timestamp\": \"${TIMESTAMP}\", \"availability-domain\": \"${AD_NAME}\"}"
  done

done

# display the display_name and OCID of boot volume backups
tempfile BV_BCKP_IDS
oci --profile "${PROFILE}" bv boot-volume-backup list --all --lifecycle-state "AVAILABLE" --compartment-id "${COMPARTMENT_ID}" > "${BV_BCKP_IDS}"
num_bvs=$(( $(cat "${BV_BCKP_IDS}"|jq --raw-output '.data | length') + 0 ))
echo "#boot_volume_backups = \"$num_bvs\""
for ((k=0; k<$num_bvs; k++)); do
  BV_BCKP_ID=("$(cat "${BV_BCKP_IDS}"|jq --raw-output '.data['$k']."id"')")
  BV_NAME="$(cat "${BV_BCKP_IDS}"|jq --raw-output '.data['$k']."display-name"')"
  echo "\"$BV_NAME\" = \"$BV_BCKP_ID\","
done





# move all boot volume backups into backup compartment
tempfile BVBCKUP_LIST_JSON
oci --profile "${PROFILE}" bv boot-volume-backup list --all --lifecycle-state "AVAILABLE" --compartment-id "${COMPARTMENT_ID}"> "${BVBCKUP_LIST_JSON}"
num_backups=$(( $(cat "${BVBCKUP_LIST_JSON}"|jq --raw-output '.data | length') + 0 ))
echo "#### \"$num_backups\" boot volume backups with status AVAILABLE"
for ((i=0; i<$num_backups; i++)); do
  BACKUP_ID=("$(cat "${BVBCKUP_LIST_JSON}"|jq --raw-output '.data['$i']."id"')")
  echo oci --profile $PROFILE bv boot-volume-backup change-compartment --boot-volume-backup-id $BACKUP_ID --compartment-id "${MY_BCKP_COMPARTMENT}"
  oci --profile $PROFILE bv boot-volume-backup change-compartment --boot-volume-backup-id $BACKUP_ID --compartment-id "${MY_BCKP_COMPARTMENT}"
done


# move all volume group backups into backup compartment
tempfile VGBCKUP_LIST_JSON
oci --profile "${PROFILE}" bv volume-group-backup list --all --compartment-id "${COMPARTMENT_ID}"> "${VGBCKUP_LIST_JSON}"
num_backups=$(( $(cat "${VGBCKUP_LIST_JSON}"|jq --raw-output '.data | length') + 0 ))
echo "#### \"$num_backups\" volume group backups"
# iterate volume group backups
for ((i=0; i<$num_backups; i++)); do
  BACKUP_ID=("$(cat "${VGBCKUP_LIST_JSON}"|jq --raw-output '.data['$i']."id"')")
  BACKUP_STATE=("$(cat "${VGBCKUP_LIST_JSON}"|jq --raw-output '.data['$i']."lifecycle-state"')")
  if [ "$BACKUP_STATE" == "AVAILABLE" ]; then
    echo oci --profile $PROFILE bv volume-group-backup change-compartment --volume-group-backup-id $BACKUP_ID --compartment-id "${MY_BCKP_COMPARTMENT}"
    oci --profile $PROFILE bv volume-group-backup change-compartment --volume-group-backup-id $BACKUP_ID --compartment-id "${MY_BCKP_COMPARTMENT}"
    # iterate block volume backups
    num_vol_bckps=$(( $(cat "${VGBCKUP_LIST_JSON}"|jq --raw-output '.data['$i']."volume-backup-ids" | length') + 0 ))
    for ((k=0; k<$num_vol_bckps; k++)); do
      VOL_BCKP_ID="$(cat "${VGBCKUP_LIST_JSON}"|jq --raw-output '.data['$i']."volume-backup-ids"['$k']')"
      echo oci --profile "${PROFILE}" bv backup change-compartment --volume-backup-id "${VOL_BCKP_ID}"  --compartment-id "${MY_BCKP_COMPARTMENT}"
      oci --profile "${PROFILE}" bv backup change-compartment --volume-backup-id "${VOL_BCKP_ID}"  --compartment-id "${MY_BCKP_COMPARTMENT}"
    done
  fi
done





# startup compute instances in compartment
num_instances=$(( $(cat "${INSTANCE_LIST_JSON}"|jq --raw-output '.data | length') + 0 ))

for ((i=0; i<$num_instances; i++)); do
  INSTANCE_ID="$(cat "${INSTANCE_LIST_JSON}"|jq --raw-output '.data['$i']."id"')"
  AD_NAME="$(cat "${INSTANCE_LIST_JSON}"|jq --raw-output '.data['$i']."availability-domain"')"
  debug_print "instance_id = $INSTANCE_ID, ad_name = $AD_NAME"
  echo oci --profile $PROFILE compute instance action --action start --instance-id $INSTANCE_ID --wait-for-state RUNNING
  oci --profile $PROFILE compute instance action --action start --instance-id $INSTANCE_ID --wait-for-state RUNNING | jq '.data|{"Server": ."display-name", "Status": ."lifecycle-state"}'
done
