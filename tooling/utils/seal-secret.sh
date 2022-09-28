#!/usr/bin/env bash

declare -A INPUT_PARS
INPUT_PARS=( \
  ["-d  | --debug"]="Debug flag for more noisy logging." \
  ["-sf | --secret-file"]="Kubernetes secret that will be encrypted." \
  ["-cn | --sealed-secret-namespace"]="Namespace where the sealed-secret controller is installed." \
  ["-o  | --output"]="Output file of the sealed-secret." \
  ["-h  | --help"]="Prints the help."
)

declare -A INPUT_PARS_REQUIRED
INPUT_PARS_REQUIRED=( \
  ["    | --secret-file"]="SECRET_FILE" \
)

function main() {
  export TOP_LEVEL_DIR=$(git rev-parse --show-toplevel)
  export SCRIPT_NAME=$(basename $0 | cut -f1 -d".")
	# basic function to log...
  source "${TOP_LEVEL_DIR}/tooling/utils/script_utils.sh"

  export TMP_FOLDER="${TOP_LEVEL_DIR}/tmp/${SCRIPT_NAME}"
	setup
	cd $CWD # because setup cds into TOP_LEVEL_DIR which would destroy relative paths
	trap cleanup EXIT

  parse_parameters "${@}"

	if ! kubectl cluster-info 1>/dev/null; then
		error "KUBECONFIG is not configured"
	fi
	# outputs secret in same CWD
	create_sealed_secret
}

function create_sealed_secret() {
	kubeseal --controller-namespace $SEALED_SECRET_NAMESPACE < $SECRET_FILE -o yaml > ${TMP_FOLDER}/sealed-secret.yaml
	cp ${TMP_FOLDER}/sealed-secret.yaml ${OUTPUT_FILE}
}

function parse_parameters() {
	while [[ "$#" > 0 ]]
	do
		case "$1" in 
			-h|--help)
				print_menu
				exit 0
				;;
			-d|--debug)
				export DEBUG="true"
				;;
			-cn|--sealed-secret-namespace)
				SEALED_SECRET_NAMESPACE=$2
				shift
				;;
			-sf|--secret-file)
				SECRET_FILE=$2
				shift
				;;
			-o|--output)
				OUTPUT_FILE=$2
				shift
				;;
			--)
				break
				;;
			-*)
				echo "Invalid option '$1'. Use --help to see the valid options" >&2
				exit 1
				;;
			*)
				break	
				;;
		esac
		shift
	done	

  check_required_parameters_and_env_vars
}

main $@
