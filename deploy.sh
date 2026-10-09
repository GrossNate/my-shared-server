#!/usr/bin/env bash
set -Eeuo pipefail

SERVER_DIR="/srv/server"
APPS_DIR="/srv/apps"
REQUESTHOLE_DIR="$APPS_DIR/requesthole"

log() {
  printf '\n==> %s\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

cd "$SERVER_DIR"

command -v docker >/dev/null || die "Docker is not installed."
docker compose version >/dev/null || die "Docker Compose is not installed."
docker info >/dev/null 2>&1 || die "Cannot access Docker."

# Prepare app directory.
mkdir -p "$APPS_DIR"

# Clone or update RequestHole.
if [[ ! -d "$REQUESTHOLE_DIR/.git" ]]; then
  [[ ! -e "$REQUESTHOLE_DIR" ]] ||
    die "$REQUESTHOLE_DIR exists but is not a Git repository."

  log "Cloning RequestHole"
  git clone \
    https://github.com/GrossNate/requesthole.git \
    "$REQUESTHOLE_DIR"
else
  log "Updating RequestHole"
  git -C "$REQUESTHOLE_DIR" pull --ff-only
fi

# Validate edge configuration.
log "Validating Caddy configuration"
docker compose run --rm --no-deps caddy \
  caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

# Start the server edge first.
# This also creates the shared external network for applications.
log "Starting Caddy"
docker compose up -d

# Apply the RequestHole production configuration.
log "Validating RequestHole Compose configuration"
docker compose \
  -p requesthole \
  -f "$REQUESTHOLE_DIR/compose.yml" \
  -f "$SERVER_DIR/apps/requesthole.yml" \
  config --quiet

log "Building and starting RequestHole"
docker compose \
  -p requesthole \
  -f "$REQUESTHOLE_DIR/compose.yml" \
  -f "$SERVER_DIR/apps/requesthole.yml" \
  up --build -d

log "Deployment status"
docker compose ps

docker compose \
  -p requesthole \
  -f "$REQUESTHOLE_DIR/compose.yml" \
  -f "$SERVER_DIR/apps/requesthole.yml" \
  ps

log "Deployment complete"
printf 'Visit https://requesthole.com\n'