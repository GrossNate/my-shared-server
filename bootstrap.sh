#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '\n==> %s\n' "$*"; }
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

if [[ "$EUID" -eq 0 ]]; then
  die "Run as your normal SSH user, not root."
fi

command -v sudo >/dev/null || die "sudo is required."

[[ -r /etc/os-release ]] || die "Cannot identify OS."
# shellcheck disable=SC1091
source /etc/os-release

[[ "${ID:-}" == "ubuntu" ]] || die "Ubuntu is required."

suite="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
[[ -n "$suite" ]] || die "Could not determine Ubuntu codename."

repo="https://download.docker.com/linux/ubuntu"

log "Install prerequisites"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl git

log "Configure Docker's official apt repository"
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL "$repo/gpg" \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

arch="$(dpkg --print-architecture)"

sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: ${repo}
Suites: ${suite}
Components: stable
Architectures: ${arch}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

log "Install Docker Engine and Compose"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

sudo systemctl enable --now docker

log "Configure Docker access"
sudo usermod -aG docker "$USER"

log "Create server directories"
sudo install -d -o "$USER" -g "$(id -gn)" -m 0755 \
  /srv/server /srv/apps

sudo install -d -o "$USER" -g "$(id -gn)" -m 0700 \
  /srv/secrets

log "Verify installation"
sudo docker --version
sudo docker compose version
sudo docker run --rm hello-world

cat <<'EOF'

Bootstrap complete.

Log out and SSH back in, then verify:
  docker ps

Next: configure the firewall, DNS, 1Password access,
and the server repository's deployment workflow.

Security note: membership in the docker group is
effectively root access. Restrict it to trusted users.
EOF
