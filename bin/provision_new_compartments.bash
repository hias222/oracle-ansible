#!/bin/bash

# bEDy:EU-FRANKFURT-1-AD-1
# bEDy:EU-FRANKFURT-1-AD-2
# bEDy:EU-FRANKFURT-1-AD-3

# let only run one instance of this script at a time
if [[ $(pgrep -f ${0##*/} | wc -l) > 2 ]]; then
  echo -e "####\n#### another instance of this script is running\n####\n#### try again later. exiting...\n####"
  exit
fi

# the profile must exist in ~/.oci/config
PROFILE=ba
# this string in terraform.tfvars must be replaced by the compartment_id
COMPARTMENT_SUBSTITUTION_STRING="###IT_SHOULD_BE_OBVIOUS_THIS_MUST_BE_REPLACED_BY_THE_REAL_COMPARTMENT_OCID####"

# some compartments below the DB-Test Compartment have a special meaning.
# don't provision a directory for those
EXCEPTION_COMPARTMENTS=()
EXCEPTION_COMPARTMENTS+=("Operations")
EXCEPTION_COMPARTMENTS+=("Sicherungen")
EXCEPTION_COMPARTMENTS+=("Multitenant")

# Files not to include in the rsync
EXCLUDE_FILES=()
EXCLUDE_FILES+=("terraform.tfvars")
EXCLUDE_FILES+=("savepoint.bash")
EXCLUDE_FILES+=("restore.bash")

# patterns match the EXCLUDE_FILES
RSYNC_EXCLUDE_PATTERNS=()
RSYNC_EXCLUDE_PATTERNS+=("'*.bash'")
RSYNC_EXCLUDE_PATTERNS+=("'*.tfvars'")
RSYNC_EXCLUDE_OPTION=""
for i in "${!RSYNC_EXCLUDE_PATTERNS[@]}"; do
  RSYNC_EXCLUDE_OPTION="${RSYNC_EXCLUDE_OPTION} --exclude ${RSYNC_EXCLUDE_PATTERNS[$i]}"
done

# Template Directory the terraform template files are copied from here
# to the compartment subdirectroy
TEMPLATE_DIRECTORY="${HOME}/.TerraformTemplate/test-env"

# subdirectories in this directory have the same names as the
# compartments in DB-Test (or whatever $COMPARTMENT_ID points to)
TERRAFORM_BASE_DIR="${HOME}/terraform"

# array keeps a list of temporary files to cleanup
TMP_FILE_LIST=()

# do not change value if set in environment
DEBUG_PRINT="${DEBUG_PRINT:=false}"

# rsync options
RSYNC_OPTIONS="--archive --hard-links --whole-file --one-file-system"

# let rsync only be verbose if DEBUG_PRINT is true
if [ "$DEBUG_PRINT" == true ]; then
  RSYNC_VERBOSE="--verbose"
else
  RSYNC_VERBOSE=""
fi

# this string in terraform.tfvars must be replaced by the compartment_id
COMPARTMENT_SUBSTITUTION_STRING="ocid1.compartment.oc1..aaaaaaaa6yayxjg6jb6aedb2wouqmkiyppikf3atfked4tgowzenp2x3zk7a"

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

# get a list of compartments in the DB-Test Compartment
tempfile COMPARTMENT_LIST_JSON
oci --profile "${PROFILE}" iam compartment list --lifecycle-state active --compartment-id "${COMPARTMENT_ID}" > "${COMPARTMENT_LIST_JSON}"
num_compartments=$(( $(cat "${COMPARTMENT_LIST_JSON}"|jq --raw-output '.data | length') + 0 ))
debug_print "### $num_compartments compartments in compartment DB-Test"

for ((i=0; i<$num_compartments; i++)); do
  COMPARTMENT_ID="$(cat "${COMPARTMENT_LIST_JSON}"|jq --raw-output '.data['$i']."id"')"
  COMPARTMENT_NAME="$(cat "${COMPARTMENT_LIST_JSON}"|jq --raw-output '.data['$i']."name"')"
  COMPARTMENT_EXCEPTION=false
  for k in "${!EXCEPTION_COMPARTMENTS[@]}"; do
    if [ "$COMPARTMENT_NAME" == "${EXCEPTION_COMPARTMENTS[$k]}" ]; then
      COMPARTMENT_EXCEPTION=true
      break
    fi
  done
  if [[ "$COMPARTMENT_EXCEPTION" == true ]]; then
    debug_print "#### skipping compartment \"${COMPARTMENT_NAME}\""
    continue
  fi
  debug_print "compartment_id = $COMPARTMENT_ID, compartment_name = $COMPARTMENT_NAME"
  COMPDIR="${TERRAFORM_BASE_DIR}/${COMPARTMENT_NAME}"
  if [ -d "${COMPDIR}" ]; then
    debug_print "#### directory \"$COMPDIR\" does exist. Skipping..."
    continue
  fi
  # $COMPDIR does not exist. Create it, put a new terrafrom environment from the template
  # into it and write the COMPARTMENT_ID into terraform.tfvars
  echo "### provisioning directory \"$COMPDIR\""
  mkdir "${COMPDIR}"
  debug_print "rsync ${RSYNC_OPTIONS} ${RSYNC_VERBOSE} ${RSYNC_EXCLUDE_OPTION} \"${TEMPLATE_DIRECTORY}/\" \"${COMPDIR}/\""
  rsync ${RSYNC_OPTIONS} ${RSYNC_VERBOSE} ${RSYNC_EXCLUDE_OPTION} "${TEMPLATE_DIRECTORY}/" "${COMPDIR}/"
  for k in "${!EXCLUDE_FILES[@]}"; do
    debug_print "cat \"${TEMPLATE_DIRECTORY}/${EXCLUDE_FILES[$k]}\" | sed \"s/$COMPARTMENT_SUBSTITUTION_STRING/$COMPARTMENT_ID/\" > \"${COMPDIR}/${EXCLUDE_FILES[$k]}\""
    cat "${TEMPLATE_DIRECTORY}/${EXCLUDE_FILES[$k]}" | sed "s/$COMPARTMENT_SUBSTITUTION_STRING/$COMPARTMENT_ID/" > "${COMPDIR}/${EXCLUDE_FILES[$k]}"
  done
  chmod 755 "${COMPDIR}/${SCRIPT_FILE}"
done

