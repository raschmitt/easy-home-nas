#!/usr/bin/env bash
# Interactive setup wizard: walks through .env configuration, the Ansible
# host layer, choosing a remote-access path (direct exposure vs Cloudflare
# Tunnel), the Docker Compose application layer, and provisioning the first
# user — confirming before anything destructive or costly.
#
# Safe to re-run: each stage checks what's already done and offers to skip
# it, the same way the underlying Ansible playbook is itself idempotent.
#
# Usage: scripts/setup.sh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ENV_FILE="$REPO_ROOT/.env"
COMPOSE_PROFILE_ARGS=()
# Overridable so tests can point this at a fixture directory instead of the
# real /dev/disk/by-id.
TANDEM_BY_ID_DIR="${TANDEM_BY_ID_DIR:-/dev/disk/by-id}"

header() {
	echo
	echo "=== $* ==="
}

gen_password() {
	# Not `tr | head -c`: under `set -o pipefail`, head closing the pipe
	# early sends tr a SIGPIPE that turns into a nonzero pipeline status,
	# which would abort the whole script the first time this runs.
	head -c 24 <(tr -dc 'A-Za-z0-9' </dev/urandom)
}

set_env_var() {
	local key="$1" value="$2"
	if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
		sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
	else
		printf '%s=%s\n' "$key" "$value" >>"$ENV_FILE"
	fi
}

get_env_var() {
	local key="$1"
	grep "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-
}

ask() {
	local prompt="$1" default="${2:-}" reply
	if [ -n "$default" ]; then
		read -r -p "$prompt [$default]: " reply
		echo "${reply:-$default}"
	else
		read -r -p "$prompt: " reply
		echo "$reply"
	fi
}

check_dependencies() {
	header "Verificando dependências"
	local missing=()
	for cmd in docker curl; do
		command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
	done
	docker compose version >/dev/null 2>&1 || missing+=("docker compose (plugin)")
	if [ "${#missing[@]}" -gt 0 ]; then
		die "Faltando: ${missing[*]}. Instale antes de continuar (veja README.md)."
	fi
	if ! command -v ansible-playbook >/dev/null 2>&1; then
		log "ansible-playbook não encontrado. Necessário pra camada de host."
		log "Instale com: pipx install ansible-core   (ou: apt install ansible-core)"
		die "Instale o Ansible e rode este script de novo."
	fi
	log "Dependências obrigatórias ok. (terraform só é checado se você escolher o Path B.)"
}

# Pure listing logic, split out from pick_disks so it's testable without
# needing to fake interactive stdin — just point TANDEM_BY_ID_DIR at a
# fixture directory and check stdout.
list_candidate_disks() {
	find "$TANDEM_BY_ID_DIR" -maxdepth 1 \( -type l -o -type f \) ! -name '*-part*' -print0 2>/dev/null | sort -z
}

pick_disks() {
	local disks=()
	while IFS= read -r -d '' d; do
		disks+=("$d")
	done < <(list_candidate_disks)

	if [ "${#disks[@]}" -lt 2 ]; then
		die "Menos de 2 discos em ${TANDEM_BY_ID_DIR}/ — não dá pra montar o mirror ZFS automaticamente. Confira 'ls -la ${TANDEM_BY_ID_DIR}/' e edite o .env manualmente."
	fi

	echo "Discos disponíveis:"
	local i=1
	for d in "${disks[@]}"; do
		printf '  %2d) %s -> %s\n' "$i" "$d" "$(readlink -f "$d")"
		i=$((i + 1))
	done

	local idx1 idx2
	while true; do
		read -r -p "Número do primeiro disco do mirror: " idx1
		read -r -p "Número do segundo disco do mirror: " idx2
		if [ "$idx1" = "$idx2" ]; then
			echo "Tem que ser dois discos diferentes."
			continue
		fi
		if ! [[ "$idx1" =~ ^[0-9]+$ ]] || ! [[ "$idx2" =~ ^[0-9]+$ ]] \
			|| [ "$idx1" -lt 1 ] || [ "$idx1" -gt "${#disks[@]}" ] \
			|| [ "$idx2" -lt 1 ] || [ "$idx2" -gt "${#disks[@]}" ]; then
			echo "Números inválidos."
			continue
		fi
		break
	done
	DISK1="${disks[$((idx1 - 1))]}"
	DISK2="${disks[$((idx2 - 1))]}"
}

configure_env() {
	header "Configurando .env"
	if [ -f "$ENV_FILE" ]; then
		if confirm "Já existe um .env. Manter como está e pular esta etapa?"; then
			log "Mantendo .env existente."
			return
		fi
	else
		cp "$REPO_ROOT/.env.example" "$ENV_FILE"
	fi

	pick_disks
	set_env_var TANDEM_ZFS_DISK_1 "$DISK1"
	set_env_var TANDEM_ZFS_DISK_2 "$DISK2"
	log "Discos selecionados:"
	log "  1: $DISK1"
	log "  2: $DISK2"

	log "Gerando senhas fortes para Nextcloud/Postgres/Redis/restic..."
	local nc_admin_pass
	nc_admin_pass="$(gen_password)"
	set_env_var NEXTCLOUD_ADMIN_PASSWORD "$nc_admin_pass"
	set_env_var POSTGRES_PASSWORD "$(gen_password)"
	set_env_var REDIS_PASSWORD "$(gen_password)"
	set_env_var RESTIC_PASSWORD "$(gen_password)"

	echo
	echo ">>> Senha do admin do Nextcloud (anote agora, só aparece uma vez): $nc_admin_pass"
	echo
}

run_ansible() {
	header "Camada de host (Ansible)"
	echo "Isso vai: criar o pool ZFS nos discos escolhidos, instalar o gatilho"
	echo "de backup automático, desligar suspensão/bloqueio de tela, e ligar"
	echo "o firewall (ufw)."
	confirm "Continuar?" || {
		log "Pulando etapa Ansible."
		return
	}

	cd "$REPO_ROOT/ansible"
	if [ ! -f inventory.ini ]; then
		cp inventory.example.ini inventory.ini
		sed -i "s/tandem_desktop_user=youruser/tandem_desktop_user=$(whoami)/" inventory.ini
	fi
	if [ ! -d "$HOME/.ansible/collections/ansible_collections/community/general" ]; then
		ansible-galaxy collection install -r requirements.yml
	fi

	set -a
	# shellcheck source=/dev/null
	source "$ENV_FILE"
	set +a

	if ! ansible-playbook -i inventory.ini playbook.yml --ask-become-pass; then
		echo
		echo "O Ansible falhou. Se a mensagem acima foi sobre um disco já ter"
		echo "assinatura de filesystem/partição, e você tem certeza que pode"
		echo "apagar os dois discos escolhidos, posso tentar de novo forçando."
		if confirm "Tentar de novo com TANDEM_ZFS_CONFIRM_WIPE=true?"; then
			set_env_var TANDEM_ZFS_CONFIRM_WIPE "true"
			set -a
			# shellcheck source=/dev/null
			source "$ENV_FILE"
			set +a
			ansible-playbook -i inventory.ini playbook.yml --ask-become-pass
		else
			die "Ajuste o que for preciso e rode scripts/setup.sh de novo."
		fi
	fi
	cd "$REPO_ROOT"
}

# Pure decision logic, split out so it's testable with a canned
# check-host.net response instead of a real network call. Returns 0 (true,
# i.e. "suggest Path A") if any node's result contains a successful check.
reachability_suggests_path_a() {
	local check_result="$1"
	grep -q '"OK"' <<<"$check_result"
}

# Extracts the request_id from a check-host.net check-tcp response. Empty
# output (not an error) means the caller couldn't parse it and should treat
# the automatic test as unavailable.
extract_check_host_request_id() {
	local response="$1"
	python3 -c "import json,sys; print(json.load(sys.stdin).get('request_id',''))" <<<"$response" 2>/dev/null || true
}

detect_access_path() {
	header "Escolhendo caminho de acesso público"
	local public_ip
	public_ip="$(curl -s https://api.ipify.org || true)"
	local suggestion=""

	if [ -n "$public_ip" ]; then
		log "IP público detectado: $public_ip"
		log "Testando alcance externo da porta 80 (uns 10s)..."
		local resp req_id result
		resp="$(curl -s "https://check-host.net/check-tcp?host=${public_ip}:80&max_nodes=3" -H "Accept: application/json" || true)"
		req_id="$(extract_check_host_request_id "$resp")"
		if [ -n "$req_id" ]; then
			sleep 6
			result="$(curl -s "https://check-host.net/check-result/${req_id}" -H "Accept: application/json" || true)"
			if reachability_suggests_path_a "$result"; then
				suggestion="A"
				log "Pelo menos um ponto externo conectou — Path A (exposição direta) deve funcionar, contanto que a porta 80/443 esteja liberada no roteador."
			else
				suggestion="B"
				log "Nenhum ponto externo conseguiu conectar — provável bloqueio do provedor. Recomendo Path B (Cloudflare Tunnel)."
			fi
		fi
	fi
	if [ -z "$suggestion" ]; then
		log "Não consegui rodar o teste automático — decida manualmente (docs/remote-access.md)."
	fi

	local choice
	choice="$(ask "Qual caminho usar? (A = exposição direta, B = Cloudflare Tunnel)" "${suggestion:-A}")"
	ACCESS_PATH="$(echo "$choice" | tr '[:lower:]' '[:upper:]')"
}

setup_path_a() {
	header "Path A: exposição direta (Caddy + Let's Encrypt)"
	local domain email
	domain="$(ask "Domínio público completo (ex: nas.seudominio.com)")"
	email="$(ask "E-mail para o Let's Encrypt")"
	set_env_var TANDEM_PUBLIC_DOMAIN "$domain"
	set_env_var TANDEM_ACME_EMAIL "$email"
	set_env_var NEXTCLOUD_TRUSTED_DOMAIN "$domain"
	set_env_var TANDEM_CADDY_ADDRESS_PREFIX ""
	echo
	echo "Lembrete: libere as portas TCP 80 e TCP+UDP 443 no seu roteador pro"
	echo "IP local desta máquina, e configure DDNS se seu IP for dinâmico."
	echo "Veja docs/remote-access.md, Path A, se precisar de ajuda."
	COMPOSE_PROFILE_ARGS=()
}

# Pure JSON parsing, split out so it's testable with a canned Cloudflare
# API response instead of a real API call. Empty output means "not found /
# unparseable" — the caller decides what that means, not these.
extract_cloudflare_account_id() {
	local zone_json="$1"
	python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'][0]['account']['id'])" <<<"$zone_json" 2>/dev/null || true
}

extract_cloudflare_zone_id() {
	local zone_json="$1"
	python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'][0]['id'])" <<<"$zone_json" 2>/dev/null || true
}

setup_path_b() {
	header "Path B: Cloudflare Tunnel"
	echo "Pré-requisito: o domínio (a zona inteira, não só o subdomínio) já"
	echo "precisa estar migrado pra Cloudflare — veja docs/remote-access.md,"
	echo "Path B, passos 1-2, antes de continuar."
	confirm "Já migrou a zona e trocou os nameservers?" || {
		log "Faça isso primeiro (docs/remote-access.md) e rode scripts/setup.sh de novo."
		return 1
	}

	require_cmd terraform

	local domain token zone_json account_id zone_id root_domain
	domain="$(ask "Domínio/subdomínio completo pro NAS (ex: drive.seudominio.com)")"
	root_domain="$(ask "Domínio raiz da zona no Cloudflare (ex: seudominio.com)")"
	read -r -s -p "Cloudflare API Token (Account>Cloudflare Tunnel>Edit + Zone>DNS>Edit): " token
	echo

	zone_json="$(curl -s "https://api.cloudflare.com/client/v4/zones?name=${root_domain}" -H "Authorization: Bearer ${token}")"
	account_id="$(extract_cloudflare_account_id "$zone_json")"
	zone_id="$(extract_cloudflare_zone_id "$zone_json")"
	if [ -z "$account_id" ] || [ -z "$zone_id" ]; then
		die "Não encontrei a zona '$root_domain' nessa conta Cloudflare. Confirme o domínio e o token (veja terraform/README.md)."
	fi
	log "account_id e zone_id encontrados automaticamente."

	(
		cd "$REPO_ROOT/terraform"
		cat >terraform.tfvars <<-EOF
			cloudflare_account_id = "$account_id"
			cloudflare_zone_id     = "$zone_id"
			public_hostname        = "$domain"
		EOF
		export CLOUDFLARE_API_TOKEN="$token"
		terraform init
		terraform apply
	)

	set_env_var TANDEM_PUBLIC_DOMAIN "$domain"
	set_env_var NEXTCLOUD_TRUSTED_DOMAIN "$domain"
	set_env_var TANDEM_CADDY_ADDRESS_PREFIX "http://"
	COMPOSE_PROFILE_ARGS=(--profile tunnel)
}

configure_access_path() {
	detect_access_path
	if [ "$ACCESS_PATH" = "B" ]; then
		setup_path_b || setup_path_a
	else
		setup_path_a
	fi
}

start_stack() {
	header "Camada de aplicação (Docker Compose)"
	confirm "Subir Nextcloud, Postgres, Redis, Caddy${COMPOSE_PROFILE_ARGS:+ e cloudflared} agora?" || {
		log "Pulando — rode 'docker compose ${COMPOSE_PROFILE_ARGS[*]:-} up -d' quando quiser."
		return
	}
	(cd "$REPO_ROOT" && docker compose "${COMPOSE_PROFILE_ARGS[@]}" up -d)
	log "Acompanhe com: docker compose logs -f nextcloud"
}

provision_first_user() {
	header "Primeiro usuário"
	confirm "Criar um usuário do Nextcloud agora?" || return
	local uname quota
	uname="$(ask "Nome de usuário")"
	quota="$(ask "Cota de espaço" "20G")"
	"$REPO_ROOT/scripts/provision-user.sh" "$uname" --quota "$quota"
}

final_summary() {
	header "Pronto"
	local domain
	domain="$(get_env_var TANDEM_PUBLIC_DOMAIN)"
	cat <<EOF

Próximos passos que ainda valem a pena:
  - Ativar 2FA antes de convidar mais gente: docs/remote-access.md
  - Preparar o HD externo de backup: sudo scripts/prepare-backup-disk.sh /dev/disk/by-id/<seu-disco>
  - Configurar os apps mobile: docs/mobile-access.md
EOF
	if [ -n "$domain" ]; then
		echo "  - Acesse: https://${domain}"
	fi
}

main() {
	echo "Tandem NAS — assistente de instalação"
	check_dependencies
	configure_env
	run_ansible
	configure_access_path
	start_stack
	provision_first_user
	final_summary
}

# Only run the wizard when executed directly — not when sourced (tests
# source this file to exercise the pure functions in isolation).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
