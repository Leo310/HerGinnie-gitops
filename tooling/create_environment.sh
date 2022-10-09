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
  ["CF_API_TOKEN"]="Cloudflare access api token to update dns records"
  ["DO_INLETS_TOKEN"]="Digitalocean access token to create inlets server droplet"
)

declare -A ENV_VARS_REQUIRED
ENV_VARS_REQUIRED=( \
  ["KUBECONFIG"]="required"
)

declare -A INPUT_PARS
INPUT_PARS=( \
  ["-d  | --debug"]="Debug flag for more noisy logging." \
  ["-h  | --help"]="Prints the help."
)

declare -A INPUT_PARS_REQUIRED
INPUT_PARS_REQUIRED=( \
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

	create_cloudflare_secret
	create_digitalocean_inlets_secret

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
	git commit -m "update commit for upto date secrets"
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

	kubectl apply -k "${TOP_LEVEL_DIR}/applications/sealed-secrets/overlay"
}

function install_argocd() {
  log "install argocd"

	kubectl apply -k "${TOP_LEVEL_DIR}/applications/argocd/overlay"
}

function install_application_list() {
  log "install application-list"

	helm template "${TOP_LEVEL_DIR}/application-list" | kubectl apply -f -
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
			-o ${TOP_LEVEL_DIR}/applications/external-dns/helm-patches/aws-credentials-secret.yaml
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
		-o ${TOP_LEVEL_DIR}/applications/argocd/overlay/argocd-secret.yaml
	fi
}

function create_cloudflare_secret() {
	if [ -z "${CF_API_EMAIL}" ] || [ -z "${CF_API_TOKEN}" ]; then
		log "no cloudflare credentials specified -> will use existing one"
	else 	
	log "create sealed cloudflare secret to access dns"
	cat ${TOP_LEVEL_DIR}/tooling/secret-templates/cloudflare-secret.yaml | \
		yq --arg email "$CF_API_EMAIL" '.stringData.CF_API_EMAIL = $email' | \
		yq --arg token "$CF_API_TOKEN" '.stringData.CF_API_TOKEN = $token' > \
		${TMP_FOLDER}/cloudflare-secret.yaml

	${TOP_LEVEL_DIR}/tooling/utils/seal-secret.sh -cn sealed-secrets \
		-sf ${TMP_FOLDER}/cloudflare-secret.yaml \
		-o ${TOP_LEVEL_DIR}/applications/external-dns/helm-patches/cloudflare-secret.yaml
	fi
}

function create_digitalocean_inlets_secret() {
	if [ -z "${DO_INLETS_TOKEN}" ]; then
		log "no Digitalocean access token specified -> will use existing one"
	else 	
	log "create sealed Digitalocean secret to create inlet droplet"
	cat ${TOP_LEVEL_DIR}/tooling/secret-templates/inlets-access-secret.yaml | \
		yq --arg token "$DO_INLETS_TOKEN" '.stringData."inlets-access-key" = $token' > \
		${TMP_FOLDER}/inlets-access-secret.yaml

	${TOP_LEVEL_DIR}/tooling/utils/seal-secret.sh -cn inlets \
		-sf ${TMP_FOLDER}/inlets-access-secret.yaml \
		-o ${TOP_LEVEL_DIR}/applications/inlets/helm-patches/inlets-access-secret.yaml
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
