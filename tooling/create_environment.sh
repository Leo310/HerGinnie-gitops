#!/usr/bin/env bash
# bootstrapping script

set -e

declare -A ENV_VARS
ENV_VARS=( \
  ["KUBECONFIG"]="Kubeconfig of the target cluster."
  # ["GITHUB_USERNAME"]="Github-Username for argocd accesstoken."
  # ["GITHUB_PASSWORD"]="Github-Password for argocd accesstoken."
  # ["AWS_ACCESS_KEY_ID"]="Aws access key id for external dns accesstoken."
  # ["AWS_SECRET_ACCESS_KEY"]="Aws access secret for external dns accesstoken."
  ["CF_API_EMAIL"]="Cloudflare email of account"
  ["CF_API_KEY"]="Cloudflare access api key to update dns records"
)

declare -A ENV_VARS_REQUIRED
ENV_VARS_REQUIRED=( \
  ["KUBECONFIG"]="required"
)

declare -A INPUT_PARS
INPUT_PARS=( \
  ["-d  | --debug"]="Debug flag for more noisy logging." \
  ["-cn | --cluster-name"]="Clustername to specify right overlays" \
  ["-h  | --help"]="Prints the help."
)

declare -A INPUT_PARS_REQUIRED
INPUT_PARS_REQUIRED=( \
  ["-cn | --cluster-name"]="CLUSTER_NAME" \
)

function main() {
  export TOP_LEVEL_DIR=$(git rev-parse --show-toplevel)
  export SCRIPT_NAME=$(basename $0 | cut -f1 -d".")
	# basic function to log...
  source "${TOP_LEVEL_DIR}/tooling/utils/script_utils.sh"

	# setup() creates tmp folder and sets CWD to PWD
  export TMP_FOLDER="${TOP_LEVEL_DIR}/tmp/${SCRIPT_NAME}"
	setup

  trap cleanup EXIT

  parse_parameters "${@}"
	
	# apply sealed secret to cluster
	install_sealed_secrets

	wait_for_sealed_secrets_controller

	# seal gitops repo access secret, dont need it know because repo is public
	# create_github_read_secret

	# seal dns access secret for aws, dont need it know becuase using cloudflare
	# create_aws_route53_secret

	# TODO
	create_cloudflare_secret

	# push secrets to repo	
	push_to_repo

	# apply cluster specific argocd
	install_argocd

	# sync argocd via argocd cli
	install_application_list

	log "Cluster should be up and running in a few minutes"
}

function push_to_repo() {
  set +e
	log "push updated secrets to repo"
	local -r branch=$(git rev-parse --abbrev-ref HEAD)
	git checkout &>/dev/null || git checkout -b "${branch}"
  git add '.' 
	git commit -m "update commit for ${CLUSTER_NAME} (for upto date secrets)"
  git push &>/dev/null || git push --set-upstream origin "${branch}"
  set -e
}

function wait_for_sealed_secrets_controller() {
	set +e
	# wait until sealed-secrets-controller is up
	log "Waiting for sealed-secrets-controller"
	kubeseal --controller-namespace sealed-secrets --fetch-cert &>/dev/null
	while [[ "$?" == 1 ]]; do 
		sleep 1
		debug "sealed-secrets-controller not up yet"
		kubeseal --controller-namespace sealed-secrets --fetch-cert &>/dev/null
	done
	set -e
}

function install_sealed_secrets() {
  log "install sealed-secrets"

	kubectl apply -k "${TOP_LEVEL_DIR}/applications/sealed-secrets/overlays/${CLUSTER_NAME}"
}

function install_argocd() {
  log "install argocd"

	kubectl apply -k "${TOP_LEVEL_DIR}/applications/argocd/overlays/argocd/${CLUSTER_NAME}"
}

function install_application_list() {
  log "install application-list"

	# kubectl apply -k "${TOP_LEVEL_DIR}/application-list/overlays/${CLUSTER_NAME}/application-list.yaml"
	# kubectl apply -f "${TOP_LEVEL_DIR}/application-list/application-list.yaml"
	helm template -f "${TOP_LEVEL_DIR}/global-values/${CLUSTER_NAME}.yaml" "${TOP_LEVEL_DIR}/application-list" | kubectl apply -f -
	# argocd app sync application-list
}

function create_aws_route53_secret() {
	if [ -z "${AWS_ACCESS_KEY_ID}" ] || [ -z "${AWS_SECRET_ACCESS_KEY}" ]; then
		log "no aws credentials specified -> will use existing one"
	else 	
		log "create aws route53 secret for external-dns"
		printf -v AWS_CREDENTIALS \
      "\n[default]\naws_access_key_id = %s\naws_secret_access_key = %s" \
      "${AWS_ACCESS_KEY_ID}" "${AWS_SECRET_ACCESS_KEY}"
		cat ${TOP_LEVEL_DIR}/tooling/secret-templates/aws-credentials-secret.yaml | \
			yq --arg credentials "$AWS_CREDENTIALS" '.stringData.credentials = $credentials' > \
			${TMP_FOLDER}/aws-credentials.yaml

		${TOP_LEVEL_DIR}/tooling/utils/seal-secret.sh -cn sealed-secrets \
			-sf ${TMP_FOLDER}/aws-credentials.yaml \
			-o ${TOP_LEVEL_DIR}/applications/external-dns/helm-patches/overlays/${CLUSTER_NAME}/aws-credentials-secret.yaml
	fi
}

function create_github_read_secret() {
	if [ -z "${GITHUB_USERNAME}" ] || [ -z "${GITHUB_PASSWORD}" ]; then
		log "no github credentials specified -> will use existing one"
	else 	
	log "create argocd github token for argocd"
	cat ${TOP_LEVEL_DIR}/tooling/secret-templates/gitaccesssecret.yaml | \
		yq --arg username "$GITHUB_USERNAME" '.stringData.username = $username' | \
		yq --arg password "$GITHUB_PASSWORD" '.stringData.password = $password' > \
		${TMP_FOLDER}/access-token-secret.yaml

	${TOP_LEVEL_DIR}/tooling/utils/seal-secret.sh -cn sealed-secrets \
		-sf ${TMP_FOLDER}/access-token-secret.yaml \
		-o ${TOP_LEVEL_DIR}/applications/argocd/overlays/argocd/${CLUSTER_NAME}/argocd-secret.yaml
	fi
}

function create_cloudflare_secret() {
	if [ -z "${CF_API_EMAIL}" ] || [ -z "${CF_API_KEY}" ]; then
		log "no cloudflare credentials specified -> will use existing one"
	else 	
	log "create sealed cloudflare secret to access dns"
	cat ${TOP_LEVEL_DIR}/tooling/secret-templates/cloudflare-secret.yaml | \
		yq --arg username "$CF_API_EMAIL" '.stringData.CF_API_EMAIL = $username' | \
		yq --arg password "$CF_API_KEY" '.stringData.CF_API_KEY = $password' > \
		${TMP_FOLDER}/cloudflare-secret.yaml

	${TOP_LEVEL_DIR}/tooling/utils/seal-secret.sh -cn sealed-secrets \
		-sf ${TMP_FOLDER}/cloudflare-secret.yaml \
		-o ${TOP_LEVEL_DIR}/applications/external-dns/helm-patches/overlays/${CLUSTER_NAME}/cloudflare-secret.yaml
	fi
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
			-cn|--cluster-name)
				CLUSTER_NAME=$2
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

main "$@"
