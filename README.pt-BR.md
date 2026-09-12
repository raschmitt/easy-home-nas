# Tandem NAS

[![CI](https://github.com/OWNER/tandem-nas/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/tandem-nas/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

*[Read in English](README.md)*

> Esta é uma tradução de apoio. Em caso de divergência, o
> [`README.md`](README.md) em inglês é a referência.

Uma stack de NAS caseiro open source: dois discos trabalhando em espelho
sincronizado ("tandem"), storage redundante, backup automático e versionado,
multiusuário com cotas individuais, e acesso remoto pelos apps oficiais ou
por navegador — sem depender de VPN.

Feito para rodar numa **máquina Ubuntu Desktop já em uso**, não num
appliance dedicado limpo — a ideia é conviver com o que já está rodando na
sua máquina.

## O que isso entrega

- **Storage redundante**: dois discos em espelho ZFS, com checksums
  (autocorreção contra corrupção silenciosa) e snapshots baratos.
- **Backup automático**: ao conectar um HD externo, um backup
  incremental/versionado via `restic` começa sozinho — sem cron, sem clicar
  em nada.
- **Multiusuário**: cada pessoa tem sua própria conta com cota de espaço
  configurável, provisionada com um único comando.
- **Acesso remoto de qualquer lugar**: apps oficiais iOS/Android do Nextcloud
  e qualquer navegador, via HTTPS com certificado real — de fora da sua rede
  local, sem VPN.
- **Seguro por padrão**: HTTPS automático (Caddy + Let's Encrypt), rate
  limiting, headers de segurança, fail2ban, e 2FA obrigatório nas contas do
  Nextcloud.
- **Pronto pra nuvem, sem ficar preso a uma**: o destino do backup é só uma
  URL de repositório restic — adicione um destino S3/B2/Wasabi/GCS/Azure
  depois sem mexer no script de backup.

Veja [`ARCHITECTURE.md`](ARCHITECTURE.md) (em inglês) para o diagrama
completo e o raciocínio por trás de cada decisão de design.

## Hardware de referência

- 2× HDD SATA de 1TB → espelho ZFS (pool principal)
- 1× HD externo USB de 2TB → destino de backup, conectado de forma
  intermitente
- Host: Ubuntu Desktop 24.04 (GNOME), já rodando outras cargas

Nada disso é fixo no código — quantidades/tamanhos diferentes de disco
também funcionam, veja `.env.example`.

## Pré-requisitos

- Ubuntu 22.04+ (Desktop ou Server) na máquina que vai rodar isso.
- Pelo menos dois discos para o espelho (mais de dois também funciona — um
  mirror ZFS aceita mais de 2 membros) e, idealmente, um disco removível
  para backup.
- Um domínio ou subdomínio seu, apontando para o IP público desta máquina
  (veja [`docs/remote-access.md`](docs/remote-access.md), em inglês —
  inclui como lidar com IP dinâmico via DDNS).
- `git`, `ansible` (`pipx install ansible-core` ou `apt install
  ansible-core`), e Docker Engine + o plugin Compose.
- Acesso sudo na máquina alvo (o playbook Ansible precisa dele para mexer em
  disco e systemd — espere um prompt de senha interativo; este projeto não
  assume sudo sem senha).

## Quickstart

```bash
git clone https://github.com/OWNER/tandem-nas.git
cd tandem-nas
cp .env.example .env
$EDITOR .env   # preencha os by-id dos discos, domínio, senhas, etc.
```

Identifique seus discos pelo ID estável (nunca use `/dev/sdX`, que pode
mudar entre boots):

```bash
ls -la /dev/disk/by-id/
```

### 1. Camada de host (Ansible) — discos, trigger de backup, energia, firewall

```bash
cd ansible
cp inventory.example.ini inventory.ini
$EDITOR inventory.ini   # defina tandem_desktop_user; adicione hosts remotos se for replicar em outra máquina
ansible-galaxy collection install -r requirements.yml

set -a && source ../.env && set +a
ansible-playbook -i inventory.ini playbook.yml --ask-become-pass
```

Isso cria o pool ZFS em espelho, instala a regra udev + serviço systemd que
disparam backup ao conectar o disco externo, desabilita suspensão/bloqueio
de tela (um desktop normal dormiria por inatividade e derrubaria o NAS), e
aplica regras básicas de firewall.

### 2. Camada de aplicação (Docker Compose) — Nextcloud, Caddy, fail2ban

```bash
cd ..
docker compose up -d
```

Acompanhe a subida:

```bash
docker compose logs -f nextcloud
```

Quando estiver saudável, acesse `https://<TANDEM_PUBLIC_DOMAIN>` e entre com
`NEXTCLOUD_ADMIN_USER` / `NEXTCLOUD_ADMIN_PASSWORD` do seu `.env`. Depois
ative a exigência de 2FA (veja
[`docs/remote-access.md`](docs/remote-access.md)) antes de adicionar mais
alguém.

### 3. Adicionar usuários

```bash
scripts/provision-user.sh alice --quota 50G
```

Veja [`docs/adding-users.md`](docs/adding-users.md).

### 4. Preparar o disco de backup (uma vez só)

```bash
sudo scripts/prepare-backup-disk.sh /dev/disk/by-id/<seu-disco-externo>
```

A partir daí, conectar esse disco dispara backup automaticamente
(`journalctl -u tandem-backup.service` para acompanhar). Veja
[`docs/disaster-recovery.md`](docs/disaster-recovery.md) para restaurar a
partir dele, incluindo recuperação de perda total do pool.

## Estrutura do repositório

```
tandem-nas/
├── docker-compose.yml       # Nextcloud, Postgres, Redis, Caddy, fail2ban
├── docker/                  # Build customizado do Caddy + config do fail2ban
├── ansible/                 # Camada de host: ZFS, udev/systemd, energia, firewall
│   └── roles/
│       ├── zfs-mirror/
│       ├── udev-backup-trigger/
│       ├── desktop-power/
│       └── hardening/
├── scripts/                 # backup.sh, restore.sh, provision-user.sh, ...
└── docs/                    # Disaster recovery, gestão de usuários, acesso remoto
```

## Status / trade-offs conhecidos

Tudo que foi aceito como trade-off deliberado, em vez de simplesmente
corrigido, está registrado em [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md) com a
justificativa — confira lá antes de assumir que algo passou batido.

## Contribuindo

Veja [`CONTRIBUTING.md`](CONTRIBUTING.md) (em inglês). Leia também o
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

## Licença

[MIT](LICENSE).
