#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  setup.sh --control-hostname CHOST --control-ip CIP --group GROUP \
           [--node NHOST NIP ...] [--ssh-user USER]

Flags:
  --control-hostname   Control hostname (required)
  --control-ip         Control IP (required)
  --group              Inventory group name (required)
  --node               Repeatable pair "HOSTNAME IP" (optional, zero or more)
  --ssh-user           SSH user for Ansible (default: current user)
  -h, --help           Show help
USAGE
  exit "${1:-1}"
}

SSH_USER="$(whoami)"
CONTROL_HOSTNAME=""
CONTROL_IP=""
GROUP_NAME=""
declare -a NODES=()

[[ $# -gt 0 ]] || usage 0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --control-hostname) CONTROL_HOSTNAME="${2:-}"; shift 2 ;;
    --control-ip)       CONTROL_IP="${2:-}";       shift 2 ;;
    --group)            GROUP_NAME="${2:-}";       shift 2 ;;
    --node)
      [[ $# -ge 3 ]] || { echo "ERR: --node requires two args" >&2; exit 1; }
      NODES+=("$2" "$3"); shift 3 ;;
    --ssh-user)         SSH_USER="${2:-}";         shift 2 ;;
    -h|--help)          usage 0 ;;
    *) echo "ERR: unknown flag $1" >&2; usage 1 ;;
  esac
done

[[ -n "$CONTROL_HOSTNAME" ]] || { echo "ERR: --control-hostname required" >&2; exit 1; }
[[ -n "$CONTROL_IP"       ]] || { echo "ERR: --control-ip required" >&2; exit 1; }
[[ -n "$GROUP_NAME"       ]] || { echo "ERR: --group required" >&2; exit 1; }

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$BASE_DIR/ansible"

if [[ "$(hostname)" != "$CONTROL_HOSTNAME" ]]; then
  echo "WARN: expected control host '$CONTROL_HOSTNAME', actual '$(hostname)'; continuing" >&2
fi

if command -v sudo >/dev/null 2>&1 && [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  SUDO="sudo"
else
  SUDO=""
fi
command -v apt-get >/dev/null 2>&1 || { echo "ERR: apt-get not found" >&2; exit 1; }

for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
  [[ -f "$f" ]] || continue
  if grep -Eq 'ansible/ansible' "$f"; then
    $SUDO cp -a "$f" "$f.bak.$(date +%s)"
    $SUDO sed -E -i 's/^\s*deb\b.*ansible\/ansible.*$/# disabled: &/' "$f"
  fi
done
for f in /etc/apt/sources.list.d/*.sources; do
  [[ -f "$f" ]] || continue
  if grep -Eq 'ansible/ansible' "$f"; then
    $SUDO cp -a "$f" "$f.bak.$(date +%s)"
    $SUDO sed -E -i 's/^Enabled:\s*yes/Enabled: no/' "$f"
  fi
done

export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get -yq update
$SUDO apt-get -yq dist-upgrade
$SUDO apt-get -yq install ansible-core python3 git

umask 077
mkdir -p "$HOME/.ssh"
touch "$HOME/.ssh/known_hosts"
chmod 600 "$HOME/.ssh/known_hosts"
for ((i=0; i<${#NODES[@]}; i+=2)); do
  host="${NODES[i]}"; ip="${NODES[i+1]}"
  for h in "$ip" "$host"; do
    [[ -n "$h" ]] || continue
    if ! ssh-keygen -F "$h" >/dev/null 2>&1; then
      ssh-keyscan -T 5 -t ed25519 "$h" 2>/dev/null >> "$HOME/.ssh/known_hosts" || true
    fi
  done
done

mkdir -p "$PROJECT_DIR"

if [[ ! -f "$PROJECT_DIR/hosts.ini" ]]; then
  {
    echo "[$GROUP_NAME]"
    echo "$CONTROL_HOSTNAME ansible_connection=local ansible_user=$SSH_USER ansible_host=$CONTROL_IP"
    for ((i=0; i<${#NODES[@]}; i+=2)); do
      host="${NODES[i]}"; ip="${NODES[i+1]}"
      echo "$host ansible_user=$SSH_USER ansible_host=$ip"
    done
  } > "$PROJECT_DIR/hosts.ini"
fi

if [[ ! -f "$PROJECT_DIR/ansible.cfg" ]]; then
  cat > "$PROJECT_DIR/ansible.cfg" <<CFG
[defaults]
inventory = ./hosts.ini
forks = 10
timeout = 30
interpreter_python = auto_silent
retry_files_enabled = False
deprecation_warnings = False
host_key_checking = True

[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o ServerAliveInterval=30 -o ServerAliveCountMax=3
CFG
fi

cd "$PROJECT_DIR"
ansible "$GROUP_NAME" -m ping -o || true
ansible --version
