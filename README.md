# My Shared Server

> [!CAUTION]
> I set this up as a private repo. As cool as it would be to show off the
> thought that went into it, I don't necessarily want a public list of all the
> sites/applications I'm running on the server.

What follows was written by ChatGPT (as was most of this repo) with a lot of
guidance and attention from me (a human).

Infrastructure-as-code repository for a DreamHost VPS hosting multiple containerized applications.

The goal is to make the server reproducible from GitHub, with minimal manual setup, centralized infrastructure management, and independent application development.

## Overview

| Component                 | Technology                             |
| ------------------------- | -------------------------------------- |
| VPS provider              | DreamHost                              |
| Operating system          | Ubuntu                                 |
| Server IP                 | `208.113.214.65`                       |
| Infrastructure repository | `GrossNate/my-shared-server` (private) |
| Server directory          | `/srv/server`                          |
| Container orchestration   | Docker Compose                         |
| Reverse proxy             | Caddy                                  |
| TLS certificates          | Let's Encrypt                          |
| Container registry        | GitHub Container Registry (GHCR)       |
| Continuous integration    | GitHub Actions                         |
| DNS provider              | DreamHost                              |

### Architecture

Each application lives in its own GitHub repository, where GitHub Actions runs tests, builds Docker images, and publishes them to GHCR.

The VPS pulls those images and runs them using Docker Compose. Application source code does not need to be cloned onto the server.

```text
GitHub: Application repositories
         |
         | GitHub Actions
         | Test → Build → Publish
         v
GitHub Container Registry
         |
         | docker compose pull
         v
DreamHost VPS
         |
         +-- Caddy
         |     |
         |     +-- requesthole.com
         |     |       |
         |     |       v
         |     |   RequestHole nginx
         |     |       |
         |     |       v
         |     |   RequestHole backend
         |     |       |
         |     |       v
         |     |   SQLite volume
         |     |
         |     +-- Future applications
         |
         +-- Docker networks and volumes
```

Caddy is the only service that publishes HTTP and HTTPS ports to the host.

Each application has its own private Docker network. Only its public-facing service connects to the shared edge network.

## Repository structure

The private infrastructure repository is cloned to `/srv/server`.

```text
/srv/
└── server/
    ├── .env
    ├── .gitignore
    ├── bootstrap.sh
    ├── compose.yml
    ├── Caddyfile
    ├── README.md
    │
    └── apps/
        └── requesthole/
            ├── compose.yml
            └── nginx/
                └── realip.conf
```

### File responsibilities

| File                                 | Responsibility                                                                    |
| ------------------------------------ | --------------------------------------------------------------------------------- |
| `bootstrap.sh`                       | Prepares Ubuntu, installs Docker and configures required host settings            |
| `compose.yml`                        | Defines Caddy and includes application configurations                             |
| `Caddyfile`                          | Configures domain routing, HTTPS, and redirects                                   |
| `.env`                               | Stores nonsecret deployment settings such as application image versions           |
| `apps/requesthole/compose.yml`       | Defines RequestHole's production containers, networks, volumes, and health checks |
| `apps/requesthole/nginx/realip.conf` | Configures trusted proxy handling for RequestHole                                 |

Application-specific deployment files are grouped under `apps/<application>/`.

Shared infrastructure stays at the repository root.

### Docker Compose organization

The root `compose.yml` defines Caddy and includes the applications:

```yaml
name: shared-server

include:
  - ./apps/requesthole/compose.yml
```

The remainder of the root file defines Caddy and its supporting resources.

Each included Compose file defines the services and resources required by that application.

Docker Compose's `include` feature allows a single deployment command while keeping application definitions in separate files. Relative file paths in an included project are resolved from that project's directory.

All included services ultimately belong to the same Compose application model. Service and resource names must therefore be unique across applications, and shared resources must not have conflicting definitions.

**Important:** The included RequestHole configuration is production-specific. It is not the same file as the standalone Compose configuration in RequestHole's public repository.

## Application repositories

Each application is developed independently of this server.

For example, RequestHole is maintained at:

https://github.com/GrossNate/requesthole

Its public repository contains:

- Application source code
- Dockerfiles
- Standalone Docker Compose configuration
- Automated tests
- GitHub Actions workflows

Anyone can clone RequestHole and run it independently:

```bash
docker compose up --build -d
```

The production server instead consumes published Docker images from GHCR.

Application repositories do not need to know which VPS, domain, or reverse proxy is used in production.

## Initial server setup

### 1. Provision Ubuntu

Create an Ubuntu VPS and configure SSH key authentication.

Use a regular SSH user with the necessary sudo permissions.

Ensure inbound traffic is allowed on:

- The configured SSH port
- TCP port 80 (HTTP)
- TCP port 443 (HTTPS)

### 2. Configure GitHub access

The infrastructure repository is private, so the VPS requires read-only access.

Generate a dedicated SSH key:

```bash
ssh-keygen -t ed25519 \
  -f ~/.ssh/github-server-deploy \
  -C "dreamhost-server-deploy"
```

Add the public key to the private repository under **Settings → Deploy keys**, without enabling write access:

```bash
cat ~/.ssh/github-server-deploy.pub
```

Configure `~/.ssh/config`:

```sshconfig
Host github-server
    HostName github.com
    User git
    IdentityFile ~/.ssh/github-server-deploy
    IdentitiesOnly yes
```

Protect the SSH configuration:

```bash
chmod 600 ~/.ssh/config
```

Verify GitHub's SSH host fingerprint against GitHub's official documentation before accepting it.

Test authentication:

```bash
ssh -T github-server
```

### 3. Clone the server repository

Prepare the destination:

```bash
sudo install -d \
  -o "$USER" \
  -g "$(id -gn)" \
  /srv/server
```

Clone the repository:

```bash
git clone \
  git@github-server:GrossNate/my-shared-server.git \
  /srv/server
```

### 4. Bootstrap Ubuntu

```bash
cd /srv/server
./bootstrap.sh
```

The bootstrap script installs Docker Engine, Docker Compose, and the necessary Ubuntu prerequisites.

If the script changes Docker group membership, log out and reconnect.

Verify:

```bash
docker version
docker compose version
docker ps
```

Docker Compose must support the `include` feature (version 2.20.3 or later).

Confirm that the firewall permits HTTP and HTTPS traffic without blocking SSH:

```bash
sudo ufw status verbose
```

## DNS configuration

DNS records are managed through DreamHost.

For RequestHole:

| Hostname              | Record | Value             |
| --------------------- | ------ | ----------------- |
| `requesthole.com`     | A      | `208.113.214.65`  |
| `www.requesthole.com` | CNAME  | `requesthole.com` |

Remove conflicting A or AAAA records for these hostnames if necessary, but preserve unrelated DNS records.

Verify:

```bash
dig +short A requesthole.com
dig +short A www.requesthole.com
```

Both hostnames should resolve to `208.113.214.65`.

Public DNS and inbound HTTP/HTTPS connectivity must work for Caddy to obtain TLS certificates.

## Continuous integration and container images

Each application repository owns its CI workflow.

For RequestHole:

```text
.github/workflows/docker.yml
```

The workflow performs the following operations:

1. Runs on pull requests and pushes to `main`.
2. Installs dependencies.
3. Runs linting and automated tests.
4. Builds production Docker images after tests succeed.
5. Publishes images to GHCR for successful pushes to `main`.
6. Tags images with `latest` and the source commit SHA.

### RequestHole images

```text
ghcr.io/grossnate/requesthole-backend
ghcr.io/grossnate/requesthole-frontend
```

These packages must be publicly accessible for anonymous pulls from the VPS.

Verify:

```bash
docker manifest inspect \
  ghcr.io/grossnate/requesthole-backend:latest

docker manifest inspect \
  ghcr.io/grossnate/requesthole-frontend:latest
```

### Image version management

The root `.env` specifies the image version:

```dotenv
REQUESTHOLE_VERSION=latest
```

For reproducible deployments, prefer a successfully published commit SHA over `latest`.

Both frontend and backend should use the same version so that they originate from the same source revision.

The `.env` file contains nonsecret image-version settings and can be committed to Git.

Docker Compose automatically reads it when run from `/srv/server`; dotenvx is unnecessary for this setting.

Actual application secrets should be handled separately.

## Deploying the server

All production containers are managed by the central Docker Compose configuration.

### 1. Validate

```bash
cd /srv/server
docker compose config --quiet
```

Inspect the resolved configuration when needed:

```bash
docker compose config
```

Verify selected images:

```bash
docker compose config --images
```

### 2. Pull images

```bash
docker compose pull
```

This downloads the configured images from GHCR without altering running containers.

### 3. Start services

```bash
docker compose up -d
```

Compose starts Caddy and all included application services.

Caddy automatically obtains and renews Let's Encrypt certificates. No Certbot installation or manual certificate issuance is required.

### 4. Verify

```bash
docker compose ps
```

Expected RequestHole-related services:

```text
shared-server-requesthole-backend-1
shared-server-requesthole-nginx-1
```

Caddy runs as:

```text
shared-server-caddy-1
```

Check the public site:

- https://requesthole.com
- https://www.requesthole.com

The `www` hostname should redirect to the root domain, and HTTP should redirect to HTTPS.

Verify responses:

```bash
curl -I https://requesthole.com
curl -I https://www.requesthole.com
curl -I http://requesthole.com
```

Test RequestHole by creating a hole, submitting a request, and confirming that the request is displayed.

Check published ports:

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

Only Caddy should publish host ports 80 and 443.

## Updating the server

### Application updates

After an application's GitHub Actions workflow successfully publishes new Docker images:

1. Update the application's version in the server's `.env`.
2. Commit and push the infrastructure change.
3. Deploy the updated version on the VPS.

```bash
cd /srv/server

git pull --ff-only
docker compose config --quiet
docker compose pull
docker compose up -d
```

Compose updates the affected containers while preserving persistent volumes.

### Caddy configuration updates

After modifying `Caddyfile` and pulling the changes onto the VPS, validate the configuration:

```bash
docker compose exec -T caddy \
  caddy validate --config /etc/caddy/Caddyfile
```

Apply the configuration:

```bash
docker compose exec -T caddy \
  caddy reload --config /etc/caddy/Caddyfile
```

This reloads Caddy without stopping the server.

### Compose configuration updates

After modifying `compose.yml` or any file under `apps/`:

```bash
cd /srv/server

git pull --ff-only
docker compose config --quiet
docker compose pull
docker compose up -d
```

If a change also modifies `Caddyfile`, reload Caddy separately.

## Adding an application

Every new application should have its own public or private GitHub repository, with Dockerfiles and a CI workflow that publishes images to GHCR.

### 1. Create an application directory

For example:

```text
apps/
├── requesthole/
│   ├── compose.yml
│   └── nginx/
│       └── realip.conf
│
└── gross-dev/
    └── compose.yml
```

Keep application-specific production configuration within its own directory.

### 2. Define production services

Create `apps/<application>/compose.yml`.

Define:

- Published GHCR images
- Environment variables
- Private application networks
- Persistent volumes
- Health checks and dependencies
- Connection to the shared edge network for the public-facing service

Avoid publishing application ports directly to the host.

Use application-specific service, network, and volume names to prevent collisions within the central Compose project.

### 3. Include the application

Add the new Compose file to the root `compose.yml`:

```yaml
include:
  - ./apps/requesthole/compose.yml
  - ./apps/gross-dev/compose.yml
```

Ensure shared Docker resources are declared consistently, without conflicting definitions across included files.

### 4. Configure Caddy

Add the application's domain and upstream to `Caddyfile`.

Caddy automatically provisions HTTPS certificates for newly configured public domains.

### 5. Configure DNS

Point the new domain to the VPS using the appropriate DNS records.

### 6. Deploy

```bash
cd /srv/server

docker compose config --quiet
docker compose pull
docker compose up -d
```

Reload Caddy to apply any changes to its routing configuration.

No application-specific deployment scripts are required.

## Persistent data and backups

Application container images and infrastructure configuration can be reproduced from GitHub and GHCR.

Persistent data must be backed up separately.

### RequestHole

RequestHole uses the Docker named volume:

```text
requesthole_data
```

This volume stores its SQLite database.

The explicit volume name allows the current server deployment to reuse the database from the previous standalone RequestHole Compose project.

On migrated servers, Docker Compose may report a project-ownership warning when attaching this volume. The warning does not necessarily indicate a problem; verify that the volume is mounted and the existing application data is present.

On fresh servers, Compose can create the volume.

RequestHole uses SQLite WAL mode. Backups must use a SQLite-aware method rather than copying only the `.db` file while the application is running.

Store backups off-server and periodically test recovery.

### Caddy

Caddy stores TLS certificates and ACME state in persistent Docker volumes.

Certificates can be reissued automatically after VPS replacement, subject to Let's Encrypt rate limits.

### Important

Do not run `docker compose down -v` during routine maintenance.

That command can remove persistent application data.

Use `docker compose up -d` for normal updates.

## Rolling back an application

To roll back RequestHole:

1. Select a previously published commit SHA.
2. Update `REQUESTHOLE_VERSION` in the server's `.env`.
3. Commit and push the change.
4. Deploy the selected images:

```bash
cd /srv/server

git pull --ff-only
docker compose pull
docker compose up -d
```

Rolling back images does not reverse database schema migrations. Verify database compatibility before reverting application versions that modify persistent data.

## Logs and troubleshooting

### List services

```bash
docker compose ps
```

### Follow all logs

```bash
docker compose logs -f --tail=100
```

### View individual services

```bash
docker compose logs -f caddy
docker compose logs -f requesthole-nginx
docker compose logs -f requesthole-backend
```

### Validate Compose

```bash
docker compose config --quiet
```

### Check selected images

```bash
docker compose config --images
```

### Common problems

**GHCR image cannot be pulled**

Confirm that the image exists, is accessible to the VPS, and has the configured version tag.

**Caddy cannot obtain a certificate**

Check DNS records, public connectivity on ports 80 and 443, and Caddy logs.

**Caddy returns HTTP 502**

Confirm that the application is running and that its public-facing container is reachable through the edge network.

**Backend is unhealthy**

Inspect its logs, environment variables, health check, and persistent storage.

**IP address already in use**

Inspect Docker networks and container addresses. Fixed IP assignments must not conflict with existing containers.

**Bind mount fails after reorganizing files**

Check the path relative to the included application's Compose directory.

For RequestHole, the nginx configuration mount is:

```yaml
volumes:
  - ./nginx/realip.conf:/etc/nginx/conf.d/00-edge-realip.conf:ro
```

The file must exist at:

```text
/srv/server/apps/requesthole/nginx/realip.conf
```

## Rebuilding the server

On a fresh Ubuntu VPS:

1. Provision Ubuntu and configure SSH.
2. Set up read-only access to the private infrastructure repository.
3. Clone the repository to `/srv/server`.
4. Run `./bootstrap.sh`.
5. Reconnect if Docker group membership changed.
6. Verify firewall settings and public DNS.
7. Restore required secrets and persistent application data.
8. Deploy:

```bash
cd /srv/server

docker compose config --quiet
docker compose pull
docker compose up -d
```

9. Verify HTTPS, container health, application functionality, and restored data.

Restore database backups before starting applications when recovery requires preserving existing state.

The following are reproducible from GitHub and GHCR:

- Docker Compose configuration
- Caddy routing configuration
- Application image versions
- Docker network definitions
- Container runtime settings
- Bootstrap instructions

The following require external recovery or configuration:

- Application data and backups
- Secrets and decryption credentials
- DNS records
- GitHub access credentials

## Security principles

- Caddy is the only public HTTP/HTTPS entry point.
- Application backends and databases remain on private Docker networks.
- Public-facing application services connect to the shared edge network.
- Client IP forwarding is restricted to trusted proxies.
- GitHub Actions runs automated checks before image publication.
- Production uses known image versions whenever practical.
- Secrets and private keys are not stored in plaintext in Git.
- Docker access is treated as privileged host access.
- Application data is backed up off-server.
- Ubuntu, Docker, dependencies, and container images are kept updated.

## Quick reference

Run these commands from `/srv/server`.

| Task                   | Command                                      |
| ---------------------- | -------------------------------------------- |
| Validate configuration | `docker compose config --quiet`              |
| Inspect configuration  | `docker compose config`                      |
| Show selected images   | `docker compose config --images`             |
| Pull images            | `docker compose pull`                        |
| Deploy                 | `docker compose up -d`                       |
| List containers        | `docker compose ps`                          |
| Follow logs            | `docker compose logs -f --tail=100`          |
| Backend logs           | `docker compose logs -f requesthole-backend` |
| Stop services          | `docker compose stop`                        |

The normal update process is:

```bash
git pull --ff-only
docker compose pull
docker compose up -d
```
