#!/usr/bin/env bash

error_prefix="[ERROR]"
warning_prefix="[WARNING]"
debug_prefix="[DEBUG]"

 # ANSI color codes
RS="\033[0m"    # reset
HC="\033[1m"    # hicolor
UL="\033[4m"    # underline
INV="\033[7m"   # inverse background and foreground
FBLK="\033[30m" # foreground black
FRED="\033[31m" # foreground red
FGRN="\033[32m" # foreground green
FYEL="\033[33m" # foreground yellow
FBLE="\033[34m" # foreground blue
FMAG="\033[35m" # foreground magenta
FCYN="\033[36m" # foreground cyan
FWHT="\033[37m" # foreground white
BBLK="\033[40m" # background black
BRED="\033[41m" # background red
BGRN="\033[42m" # background green
BYEL="\033[43m" # background yellow
BBLE="\033[44m" # background blue
BMAG="\033[45m" # background magenta
BCYN="\033[46m" # background cyan
BWHT="\033[47m" # background white

function setup() {
  export CWD="${PWD}"
  cd "${TOP_LEVEL_DIR}"
  mkdir -p "${TMP_FOLDER}"
}
function cleanup() {
  cd "${TOP_LEVEL_DIR}"
  if [[ "${DEBUG}" != "true" ]]; then
  	log 'Cleanup'
    rm -rf "${TMP_FOLDER}"
  fi
  cd "${CWD}"
}
function log() {
  echo -e "${FGRN}[+] (${SCRIPT_NAME}): $*${RS}"
}

function debug() {
  if [[ "${DEBUG}" == "true" ]]; then
    echo -e "${FMAG}[.] ${debug_prefix} (${SCRIPT_NAME}): $*${RS}"
  fi
}

function warning() {
  echo -e "${FYEL}[*] ${warning_prefix} (${SCRIPT_NAME}): $*${RS}";
}

function error() {
  echo -e "${FRED}[-] ${error_prefix} (${SCRIPT_NAME}): $*${RS}";
  exit 1
}

function error_non_fatal() {
  echo -e "${FRED}[-] ${error_prefix} (${SCRIPT_NAME}): $*${RS}"
}


function check_error() {
  if [[ "${1}" == "${error_prefix}"* ]]; then
    echo "${1}"
    exit 1
  fi
}

function check_env_vars() {
  if [ -z "${!1}" ]; then
    print_menu
    error "environment variable \"${1}\" is not set"
  fi
}

function check_required_parameters_and_env_vars() {
  something_missing="false"
  for var in "${!ENV_VARS[@]}"; do
    if [ "${ENV_VARS_REQUIRED[${var}]}" == "required" ] && [ -z "${!var}" ]; then
      something_missing="true"
      error_non_fatal "environment variable \"${var}\" is not set"
    fi
  done

  missing_params=()
  for par in "${!INPUT_PARS[@]}"; do
    param="${INPUT_PARS_REQUIRED[${par}]}"
    if [ "${param}" != "" ]&& [ -z "${!param}" ]; then
      something_missing="true"
      error_non_fatal "parameter \"${par}\" is not set"
    fi
  done

  if "${something_missing}"; then
    echo "missing: ${something_missing}"
    print_menu
    error "missing required inputs"
  fi
}

function check_required_parameters() {
  if [ -z "${!1}" ]; then
    print_menu
    error "parameter \"${1}\" is not set"
  fi
}


function print_menu() {
  echo "Usage: ./tooling/${SCRIPT_NAME}.sh [-options]"
  req="(required)"
  space_offset=0
  for var in "${!ENV_VARS_REQUIRED[@]}"; do
    l=$(printf "%d" ${#var})
    if (( l > $space_offset )); then
      space_offset=$l
    fi
  done
  for var in "${!INPUT_PARS[@]}"; do
    l=$(printf "%d" ${#var})
    if (( l > $space_offset )); then
      space_offset=$l
    fi
  done
  echo "required environment variables:"
  for var in "${!ENV_VARS[@]}"; do
    if [ "${ENV_VARS_REQUIRED[${var}]}" == "required" ]; then
      offset="$(($space_offset-${#var}+2))"
      spaces="$(printf '%*s' $offset)"
      echo "${var}:${spaces}${req}  ${ENV_VARS[${var}]}"
    else
      offset="$(($space_offset-${#var}+${#req}+2))"
      spaces="$(printf '%*s' $offset)"
      echo "${var}:${spaces}  ${ENV_VARS[${var}]}"
    fi
  done
  echo ""
  echo "Where parameters include:"
  for var in "${!INPUT_PARS[@]}"; do
    if [ "${INPUT_PARS_REQUIRED[${var}]}" == "required" ]; then
      offset="$(($space_offset-${#var}+2))"
      spaces="$(printf '%*s' $offset)"
      echo "${var}:${spaces}${req}  ${INPUT_PARS[${var}]}"
    else
      offset="$(($space_offset-${#var}+${#req}+2))"
      spaces="$(printf '%*s' $offset)"
      echo "${var}:${spaces}  ${INPUT_PARS[${var}]}"
    fi
  done
}


# This is used for Loki S3 secret. A bash function to encode url.
# The function is used in asw_user_key.sh when generating sealed S3 secret for loki.
# The function handle special characters like slash in the S3 secret, encode the secret before generate the sealed secret.
# https://gist.github.com/cdown/1163649#gistcomment-2157284
function  urlencode() {
	local LANG=C i c e=''
	for ((i=0;i<${#1};i++)); do
                c=${1:$i:1}
		[[ "$c" =~ [a-zA-Z0-9\.\~\_\-] ]] || printf -v c '%%%02X' "'$c"
                e+="$c"
	done
        echo "$e"
}
