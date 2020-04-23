#!/usr/bin/env bash

#SUPPORTED_APPS="Jira Confluence Bitbucket"
SUPPORTED_APPLS="Jira"

#
# Default settings
#
BACKUP_RETENTION="3"
DENY_ROOT_EXECUTION="true"
STRICT_USER_EXECUTION="true"
TIMESTAMPFMT="%Y%m%d-%H%M"
TIMESTAMP="date +${TIMESTAMPFMT}"
CONFIG_FILE="./atlasbck.cfg"

DEFAULT_INSTALL_ROOT="/opt/atlassian"
DEFAULT_INSTALL_DIR_JIRA="${DEFAULT_INSTALL_ROOT}/jira"
DEFAULT_INSTALL_DIR_CONFLUENCE="${DEFAULT_INSTALL_ROOT}/confluence"
DEFAULT_INSTALL_DIR_BITBUCKET="${DEFAULT_INSTALL_ROOT}/bitbucket"

DEFAULT_HOME_ROOT="/tmp/var/atlassian/application-data"
DEFAULT_HOME_DIR_JIRA="${DEFAULT_HOME_ROOT}/jira"
DEFAULT_HOME_DIR_CONFLUENCE="${DEFAULT_HOME_ROOT}/confluence"
DEFAULT_HOME_DIR_BITBUCKET="${DEFAULT_HOME_ROOT}/bitbucket"

#
# List of error codes
#
ERR_BACKUP_DIR="1"
ERR_CFG_MISSING="2"
ERR_VAR_MISSING="5"
ERR_RUN_AS_ROOT="10"
ERR_RUN_AS_WRONG_USER="11"
ERR_TOOL_MISSING="12"

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

  # Check if all necessary tools are available
  TOOLS="date find id ln mkdir tar rm"
  for TOOL in $TOOLS; do
    BIN="$(command -v ${TOOL})"
    if [[ -z "${BIN}" ]]; then
      log "FATAL" "Tool ${TOOL} missing or not in path"
      exit ${ERR_TOOL_MISSING}
    else
      log "INFO" "Tool ${TOOL} available"
    fi
  done

  # Check if script is run as root (effective user id is 0)
  if [[ "${DENY_ROOT_EXECUTION}" = "true" && "$(id -u)" == 0 ]]; then
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

  log "INFO" "Check prereqs for application ${APP}"

  # Check if backup dir is set correctly, attempt to create it
  eval BACKUP_DIR='$'BACKUP_DIR_${APP}
  log "INFO" "Check backup dir ${BACKUP_DIR} for application ${APP}."
  if [ -z "${BACKUP_DIR}" ]; then
    log "ERROR" "Backup directory not set"
    RC="${ERR_VAR_MISSING}"
  elif [[ ! -d "${BACKUP_DIR}" || ! -w "${BACKUP_DIR}" || ! -x "${BACKUP_DIR}" ]]; then
    log "WARN" "Backup directory ${BACKUP_DIR} is not a writeable directory"
    RC="${ERR_BACKUP_DIR}"
    log "INFO" "Create backup directory ${BACKUP_DIR}"
    if ! mkdir -p "${BACKUP_DIR}"; then
      log "FATAL" "Create backup directory ${BACKUP_DIR} failed"
      RC="${ERR_BACKUP_DIR}"
    else
      RC="0"
    fi
  fi

  # Check if backup is executed with application's system account
  log "INFO" "Check user executing atlasbck for application ${APP}."
  if [[ "${STRICT_USER_EXECUTION}" = "true" && "$(id -u -n)" != "${APP,,}" ]]; then
    log "FATAL" "Running atlasbck as $(id -u -n) for application ${APP}, has to be done as ${APP,,}."
    exit ${ERR_RUN_AS_WRONG_USER}
  elif [[ "${STRICT_USER_EXECUTION}" == "false" ]]; then
    log "WARN" "Strict user execution disabled."
  fi
  return ${RC}
}

#
# Remove obsolete backups
#
function remove_obsolete_backps() {
  local APPL="${1^^}"
  local BACKUP_DIR=""
  local RC="0"

  log "INFO" "Remove obsolete backups."
  eval BACKUP_DIR='$'BACKUP_DIR_${APPL}
  if [[ -d "${BACKUP_DIR}" && -w "${BACKUP_DIR}" && -x "${BACKUP_DIR}" ]]; then
    find "${BACKUP_DIR}" -user "${USER}" -type f -mtime +${BACKUP_RETENTION} -exec rm -f {} \; > /dev/null 2>&1
    RC=$?
  else
    log "ERROR" "Backup directory ${BACKUP_DIR} is not a writeable directory."
    RC="${ERR_BACKUP_DIR}"
  fi

  return ${RC}
}

#
# Backup install dir
#
function backup_install_dir() {
  local APPL="${1^^}"
  local INSTALL_DIR=""
  local RC="0"

  eval INSTALL_DIR='$'INSTALL_DIR_${APPL}
  eval TMP='$'DEFAULT_INSTALL_DIR_${APPL}
  if [[ -z "${INSTALL_DIR}" && ! -z "${TMP}" ]]; then
    INSTALL_DIR="${TMP}"
    log "INFO" "Install directory not set, use default ${INSTALL_DIR}"
  elif [[ -z "${INSTALL_DIR}" && -z "${TMP}" ]]; then
    log "ERROR" "Install directory not set and default not available."
    RC="${ERR_VAR_MISSING}"
    exit $RC
  fi

  eval BACKUP_DIR='$'BACKUP_DIR_${APPL}
  local T="$(eval ${TIMESTAMP})"
  local BACKUP_FILE="${BACKUP_DIR}/${APPL,,}-install-${T}.tar.gz"

  cd $(dirname "${INSTALL_DIR}") && ln -s $(basename ${INSTALL_DIR}) $(basename ${INSTALL_DIR})-bck-${T} && tar -chzf ${BACKUP_FILE} $(basename ${INSTALL_DIR})
  RC=$(($RC+$_RC))
  rm -f ${INSTALL_DIR}-bck-${T}
  RC=$(($RC+$_RC))

  return ${RC}
}

#
# Backup home dir
#
function backup_home_dir() {
  local APPL="${1^^}"
  local HOME_DIR=""
  local RC="0"

  eval HOME_DIR='$'HOME_DIR_${APPL}
  eval TMP='$'DEFAULT_HOME_DIR_${APPL}
  if [[ -z "${HOME_DIR}" && ! -z "${TMP}" ]]; then
    HOME_DIR="${TMP}"
    log "INFO" "Home directory not set, use default ${HOME_DIR}"
  elif [[ -z "${HOME_DIR}" && -z "${TMP}" ]]; then
    log "ERROR" "Home directory not set and default not available."
    RC="${ERR_VAR_MISSING}"
    exit $RC
  fi

  eval BACKUP_DIR='$'BACKUP_DIR_${APPL}
  local T="$(eval ${TIMESTAMP})"
  local BACKUP_FILE="${BACKUP_DIR}/${APPL,,}-home-${T}.tar.gz"

  cd $(dirname "${HOME_DIR}") && ln -s $(basename ${HOME_DIR}) $(basename ${HOME_DIR})-bck-${T} && tar -chzf ${BACKUP_FILE} $(basename ${HOME_DIR})
  RC=$(($RC+$_RC))
  rm -f ${HOME_DIR}-bck-${T}
  RC=$(($RC+$_RC))

  return ${RC}
}

#
# Dump database
#
function dump_database() {
  local APPL="${1^^}"
  local DB_NAME=""
  local DB_HOST=""
  local DB_USER=""
  local DB_PASS=""
  local RC="0"

  eval DB_NAME='$'DB_NAME_${APPL}
  eval DB_HOST='$'DB_HOST_${APPL}
  eval DB_USER='$'DB_USER_${APPL}
  eval DB_PASS='$'DB_PASS_${APPL}

  if [[ -z "${DB_NAME}" ]]; then
    DB_NAME="${1,,}"
  fi
  if [[ -z "${DB_HOST}" ]]; then
    DB_HOST="localhost"
  fi
  if [[ -z "${DB_USER}" ]]; then
    DB_USER="${1,,}"
  fi

  eval BACKUP_DIR='$'BACKUP_DIR_${APPL}
  local T="$(eval ${TIMESTAMP})"
  local BACKUP_DUMP="${BACKUP_DIR}/${APPL,,}-db-${T}"

  log "INFO" "Dumping database ${DB_NAME} to ${BACKUP_DUMP}"
  pg_dump -Fd "${DB_NAME}" -j 5 -U "${DB_USER}" -h "${DB_HOST}" -f ${BACKUP_DUMP}
  RC=$(($RC+$_RC))

  return $RC
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

      backup_install_dir ${APPL}
      RC=$(($RC+$?))

      backup_home_dir ${APPL}
      RC=$(($RC+$?))

      dump_database ${APPL}
      RC=$(($RC+$?))
    done
  fi

  return ${RC}
}

main
RC=$(($RC+$?))

exit $RC
