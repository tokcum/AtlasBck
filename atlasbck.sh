#!/usr/bin/env bash

#SUPPORTED_APPS="Jira Confluence Bitbucket"
SUPPORTED_APPLS="Jira"

#
# Default settings
#
BACKUP_RETENTION="3"
DENY_ROOT_EXECUTION="true"
TIMESTAMPFMT="%Y-%m-%d-%H-%M-%S"
TIMESTAMP="date +${TIMESTAMPFMT}"
CONFIG_FILE="./atlasbck.cfg"

#
# List of error codes
#
ERR_BACKUP_DIR="1"
ERR_CFG_MISSING="2"
ERR_VAR_MISSING="5"
ERR_RUN_AS_ROOT="10"

# Default return code
RC="0"

function log() {
  local LEVEL="$1"
  local MSG="$2"

  local LOG="$(eval ${TIMESTAMP})"
  LOG+=" ${LEVEL}: "
  LOG+=" ${MSG}"

  echo ${LOG}
}

#
# Read configuration file
#
if [ -r "${CONFIG_FILE}" ]; then
  source ${CONFIG_FILE}
else
  log "ERROR" "${CONFIG_FILE} not readable."
  exit ${ERR_CFG_MISSING}
fi

#
# Check all global prerequisites before starting backups
# of applications
#
function check_prereqs_global() {
  local RC="0"

  # Check if script is run as root (effective user id is 0)
  if [[ "${DENY_ROOT_EXECUTION}" == "true" && "$(id -u)" == 0 ]]; then
    log "FATAL" "Running atlasbck as root is denied."
    exit ${ERR_RUN_AS_ROOT}
  elif [[ "${DENY_ROOT_EXECUTION}" == "false" ]]; then
    log "WARN" "Check root execution disabled."
  fi

  return ${RC}
}

#
# Check all application specific prerequisites
#
function check_prereqs_appl() {
  local RC="0"

  local APP="${1^^}"
  local BACKUP_DIR=""
  local RC="0"

  eval BACKUP_DIR='$'BACKUP_DIR_${APP}
  if [ -z "${BACKUP_DIR}" ]; then
    log "ERROR" "Backup directory not set."
    RC="${ERR_VAR_MISSING}"
  elif [[ ! -d "${BACKUP_DIR}" || ! -w "${BACKUP_DIR}" || ! -x "${BACKUP_DIR}" ]]; then
    log "WARN" "Backup directory ${BACKUP_DIR} is not a writeable directory."
    RC="${ERR_BACKUP_DIR}"
    log "INFO" "Create backup directory ${BACKUP_DIR}."
    if ! mkdir "${BACKUP_DIR}"; then
      log "FATAL" "Create backup directory ${BACKUP_DIR} failed."
      RC="${ERR_BACKUP_DIR}"
    fi
  fi

  return ${RC}
}

#
# Remove obsolete backups
#
function remove_obsolete_backps() {
  local APP="${1^^}"
  local BACKUP_DIR=""
  local RC="0"

  log "INFO" "Remove obsolete backups."
  eval BACKUP_DIR='$'BACKUP_DIR_${APP}
  if [[ -d "${BACKUP_DIR}" && -w "${BACKUP_DIR}" && -x "${BACKUP_DIR}" ]]; then
    find "${BACKUP_DIR}" -user "${USER}" -type f -mtime +${BACKUP_RETENTION} -exec rm -f {} \; > /dev/null 2>&1
    RC=$?
  else
    log "ERROR" "Backup directory ${BACKUP_DIR} is not a writeable directory."
    RC="${ERR_BACKUP_DIR}"
  fi

  return ${RC}
}

function main() {
  local RC="0"

  if ! check_prereqs_global; then
    RC=$?
  else
    for APPL in ${SUPPORTED_APPLS}; do
      check_prereqs_appl ${APPL}
      _RC=$?
      if [[ "$_RC" -ne 0 ]]; then
        RC=$(($RC+$_RC))
        log "ERROR" "Skip backup of ${APPL}"
        continue
      fi

      remove_obsolete_backps ${APPL}
      RC=$(($RC+$?))

    done
  fi

  return ${RC}
}

main
RC=$(($RC+$?))

exit $RC
