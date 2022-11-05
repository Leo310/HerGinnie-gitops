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
  ["CF_CA_API_KEY"]="Cloudflare access ca key to get cert.pem for encrpyted tunnel"
  ["CF_TUNNEL_CREDS"]="Cloudflare access creds to create tunnel"
  ["DO_INLETS_TOKEN"]="Digitalocean access token to create inlets server droplet"
  ["MYSQL_SECRET"]="Mysql Database secret"
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
	
	install_sealed_secrets
	wait_for_sealed_secrets_controller

	# seal gitops repo access secret, dont need it know because repo is public
	# secret_name="git-access"
	# dest_directory="${TOP_LEVEL_DIR}/applications/argocd/overlay/argocd-secret.yaml"	
	# env_secrets=('GITHUB_USERNAME' 'GITHUB_PASSWORD')
	# dest_secrets=('username' 'password')
	# create_secret $secret_name $dest_directory "${env_secrets[@]}" "${dest_secrets[@]}"

	# seal dns access secret for aws, dont need it know becuase using cloudflare
	# secret_name="aws-credentials"
	# dest_directory="${TOP_LEVEL_DIR}/applications/external-dns/helm-patches/aws-credentials-secret.yaml"	
	# printf -v AWS_CREDENTIALS \
	# 	"\n[default]\naws_access_key_id = %s\naws_secret_access_key = %s" \
	# 	"${AWS_ACCESS_KEY_ID}" "${AWS_SECRET_ACCESS_KEY}"
	# env_secrets=('AWS_CREDENTIALS')
	# dest_secrets=('credentials')
	# create_secret $secret_name $dest_directory "${env_secrets[@]}" "${dest_secrets[@]}"
	
	secret_name="cloudflare-ca-key"
	dest_directory="${TOP_LEVEL_DIR}/applications/cloudflared/origin-ca-issuer/cf-ca-secret.yaml"	
	env_secrets=('CF_CA_API_KEY')
	dest_secrets=('key')
	create_secret $secret_name $dest_directory "${env_secrets[@]}" "${dest_secrets[@]}"

	secret_name="tunnel-credentials"
	dest_directory="${TOP_LEVEL_DIR}/applications/cloudflared/cloudflared/tunnel-credentials.yaml"	
	env_secrets=('CF_TUNNEL_CREDS')
	dest_secrets=('credentials.json')
	create_secret $secret_name $dest_directory "${env_secrets[@]}" "${dest_secrets[@]}"

	secret_name="mysql"
	dest_directory="${TOP_LEVEL_DIR}/applications/webapp/matomo/mysql-secret.yaml"	
	env_secrets=('MYSQL_SECRET')
	dest_secrets=('password')
	create_secret $secret_name $dest_directory "${env_secrets[@]}" "${dest_secrets[@]}"

	# secret_name="cloudflare"
	# dest_directory="${TOP_LEVEL_DIR}/applications/external-dns/helm-patches/cloudflare-secret.yaml"	
	# env_secrets=('CF_API_EMAIL' 'CF_API_TOKEN')
	# dest_secrets=('CF_API_EMAIL' 'CF_API_TOKEN')
	# create_secret $secret_name $dest_directory "${env_secrets[@]}" "${dest_secrets[@]}"
	
	# secret_name="inlets-access"
	# dest_directory="${TOP_LEVEL_DIR}/applications/inlets/helm-patches/inlets-access-secret.yaml"	
	# env_secrets=('DO_INLETS_TOKEN')
	# dest_secrets=('inlets-access-key')
	# create_secret $secret_name $dest_directory "${env_secrets[@]}" "${dest_secrets[@]}"

	push_secrets_to_repo
	install_argocd
	install_application_list

	log "Cluster should be up and running in a few minutes"
}

function install_sealed_secrets {
  log "install sealed-secrets"
	kubectl apply -k "${TOP_LEVEL_DIR}/applications/sealed-secrets/overlay"
}

function wait_for_sealed_secrets_controller {
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

function create_secret() {
	secret_name=$1
	dest_directory=$2
	env_variables=$3
	dest_variables=$4

	replace_args=()
	i=0
	for secret_env in "${env_variables[@]}"; do
		if ! [[ -v "$secret_env" ]]; then
			log "no ${secret_name} credentials specified -> will use existing one"
			return
		fi
		replace_args+=("| yq --arg value ${secret_env} '.stringData.\"${dest_variables[$i]}\" = \$value'")	
		i+=1
	done
	log "create ${secret_name} secret"
	cat_template_yaml="cat ${TOP_LEVEL_DIR}/tooling/secret-templates/${secret_name}-secret.yaml"
	pipe_into_tmp_secret="> ${TMP_FOLDER}/${secret_name}-secret.yaml"
	whole_command="$cat_template_yaml ${replace_args[*]} $pipe_into_tmp_secret"
	eval $whole_command

	${TOP_LEVEL_DIR}/tooling/utils/seal-secret.sh -cn sealed-secrets \
		-sf ${TMP_FOLDER}/${secret_name}-secret.yaml \
		-o ${dest_directory}
}

function push_secrets_to_repo {
  set +e
	log "push updated secrets to repo"
	local -r branch=$(git rev-parse --abbrev-ref HEAD)
	git checkout &>/dev/null || git checkout -b "${branch}"
  git add '.' 
	git commit -m "update commit for upto date secrets"
  git push &>/dev/null || git push --set-upstream origin "${branch}"
  set -e
}

function install_argocd {
  log "install argocd"
	kubectl apply -k "${TOP_LEVEL_DIR}/applications/argocd/overlay"
}

function install_application_list {
  log "install application-list"
	helm template "${TOP_LEVEL_DIR}/application-list" | kubectl apply -f -
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
