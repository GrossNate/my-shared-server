# My Shared Server

Production configuration for gross.dev and RequestHole on one Ubuntu VPS.

Docker Compose manages the shared-server project. Caddy handles routing and HTTPS. Grafana Alloy sends host metrics, web-server metrics, and container logs to Grafana Cloud.

Application source code and image builds live in their own repositories. Deployments are manual.

## Everyday commands

Run server commands from /srv/server as your regular SSH user:

cd /srv/server

Use dotenvx run -- docker compose for Compose commands. It decrypts the Grafana Cloud credential from .env before Compose reads the configuration.

Run commands in order and stop if one fails.

### Update gross.dev

Wait for the application's image-publishing workflow to finish successfully, then run:

dotenvx run -- docker compose pull grossdev
dotenvx run -- docker compose up -d --wait --pull never grossdev
curl --fail --silent --show-error --output /dev/null <https://gross.dev/>

### Update RequestHole

Wait for both application images to publish successfully, then run:

dotenvx run -- docker compose pull requesthole-backend requesthole-nginx
dotenvx run -- docker compose up -d --wait --pull never requesthole-backend requesthole-nginx
curl --fail --silent --show-error --output /dev/null <https://requesthole.com/>

Open RequestHole, create a hole, send a request, and confirm it appears.

Both applications currently use latest. Pulling downloads the currently published images; up replaces containers whose images changed. Pulling alone leaves running containers untouched.

These updates can briefly interrupt the affected application. Health checks do not automatically roll back a failed deployment.

### Apply changes from this repository

After committing and pushing configuration changes, fetch them on the VPS:

git pull --ff-only
dotenvx run -- docker compose config --quiet

Then use the relevant procedure below.

| Changed files                                  | Apply with                             |
| ---------------------------------------------- | -------------------------------------- |
| Caddyfile                                      | Reload Caddy                           |
| Compose files or application version variables | Apply Compose configuration            |
| monitoring/*.alloy or Grafana Cloud credential | Recreate Alloy                         |
| nginx configuration mounted into applications  | Recreate the affected nginx containers |
| Grafana dashboard or Knowledge Graph files     | Apply separately in Grafana Cloud      |
| Documentation or formatting tools              | No server action                       |

A Git pull updates files on disk. It does not reload running services.

#### Reload Caddy

dotenvx run -- docker compose exec -T caddy \
caddy reload --config - --adapter caddyfile < Caddyfile

This sends the current host file directly to Caddy. It avoids stale bind-mounted contents when Git replaces the file.

Caddy reload (<https://caddyserver.com/docs/command-line#caddy-reload>) applies valid configuration without restarting the container. A rejected configuration leaves the previous configuration active.

If adding an application, start its services before reloading routes that point to them.

#### Apply Compose configuration

dotenvx run -- docker compose up -d --wait --pull never
dotenvx run -- docker compose ps

This applies service configuration changes using locally available images. To deploy a new image, pull it first using the application commands above.

Review shared-network changes before applying them: they may affect multiple applications.

Compose does not detect changes to the contents of bind-mounted configuration files. Use the explicit procedures below for those files.

#### Apply Alloy configuration or credential changes

Validate the current files in a temporary container:

dotenvx run -- docker compose run --rm --no-deps alloy validate /etc/alloy

Then recreate Alloy:

dotenvx run -- docker compose up -d --wait --pull never --force-recreate alloy
curl --fail --silent --show-error <http://127.0.0.1:12345/-/healthy>
dotenvx run -- docker compose logs --tail=50 alloy

Alloy mounts individual configuration files. Recreating the container ensures it reads files replaced by Git and receives the current credential.

Configuration validation checks structure; it does not prove Grafana Cloud accepts the credential or receives telemetry. Confirm fresh data in Grafana Cloud afterward.

#### Apply mounted nginx configuration

For changes to monitoring/nginx-status.conf, recreate both frontend containers:

dotenvx run -- docker compose up -d --wait --pull never --force-recreate grossdev requesthole-nginx

For changes only to apps/requesthole/nginx/realip.conf:

dotenvx run -- docker compose up -d --wait --pull never --force-recreate requesthole-nginx

These commands briefly interrupt the affected sites.

### Check status and logs

dotenvx run -- docker compose ps
dotenvx run -- docker compose logs --tail=100 caddy
dotenvx run -- docker compose logs --tail=100 grossdev
dotenvx run -- docker compose logs --tail=100 requesthole-backend requesthole-nginx
dotenvx run -- docker compose logs --tail=100 alloy nginx-exporter

Follow RequestHole logs while reproducing a problem:

dotenvx run -- docker compose logs --follow --tail=100 requesthole-backend requesthole-nginx

Check public endpoints and Alloy:

curl --fail --silent --show-error <https://health.gross.dev/>
curl --fail --silent --show-error --output /dev/null <https://gross.dev/>
curl --fail --silent --show-error --output /dev/null <https://requesthole.com/>
curl --fail --silent --show-error <http://127.0.0.1:12345/-/healthy>

health.gross.dev checks the public route to Caddy. It does not check either application's behavior.

> [!CAUTION]
> Do not use docker compose down for routine updates. It stops the whole project. Adding -v can delete persistent volumes.
>
> Use targeted pull and up commands. restart does not deploy new images or apply changed Compose settings.

## Configuration and secrets

| File      | Purpose                                                                        | Committed? |
| --------- | ------------------------------------------------------------------------------ | ---------- |
| .env      | Application image tags, dotenvx public key, encrypted Grafana Cloud credential | Yes        |
| .env.keys | Private key used to decrypt .env                                               | No         |

The application version variables are plaintext:

REQUESTHOLE_VERSION=latest
GROSSDEV_VERSION=latest

GCLOUD_RW_API_KEY is encrypted. Alloy uses it to send metrics and logs to the configured Grafana Cloud endpoints.

Keep a secure copy of the existing .env.keys outside this repository. A new clone does not include it. Generating a different key will not decrypt the existing credential.

dotenvx (<https://dotenvx.com/docs/cli/run/>) decrypts values when running a command:

dotenvx run -- docker compose config --quiet

Use config --quiet to validate configuration and config --images to inspect image references:

dotenvx run -- docker compose config --images

Avoid sharing unredacted output from docker compose config or container inspection: resolved configuration can contain the decrypted credential.

### Select a version or roll back an application

Edit the application's version variable in .env in your local checkout, preserving the encrypted credential and public key. Commit and push the change.

The current image workflows publish these commit tags:

| Application                      | Tag format            |
| -------------------------------- | --------------------- |
| grossdev                         | sha-<full commit SHA> |
| RequestHole frontend and backend | <full commit SHA>     |

On the VPS, pull the configuration change, then follow the relevant application-update procedure.

Both RequestHole images must have the selected tag. latest moves as images are published; a previous commit tag lets you select a known revision.

Rollback uses the same deployment commands with the previous tag. Reverting an image does not reverse database migrations.

### Change the Grafana Cloud credential

Use dotenvx set (<https://dotenvx.com/docs/cli/set/>) to update GCLOUD_RW_API_KEY with encryption. Commit the encrypted .env, keeping .env.keys out of Git.

Pull the change on the VPS and follow “Apply Alloy configuration or credential changes.”

## Observability

Grafana Cloud stores the collected metrics and logs. Grafana and Loki are not hosted on this VPS.

| Signal                                      | Source                                     | Configuration                                                                |
| ------------------------------------------- | ------------------------------------------ | ---------------------------------------------------------------------------- |
| Host CPU, memory, disk, and network metrics | Alloy's Unix exporter                      | monitoring/config.alloy                                                      |
| Container stdout/stderr logs                | Docker discovery and Alloy's Loki pipeline | monitoring/logs.alloy                                                        |
| HTTP request metrics by site                | Caddy metrics endpoint                     | Caddyfile, monitoring/caddy.alloy                                            |
| nginx connections and request counts        | Shared nginx exporter                      | monitoring/nginx-status.conf, monitoring/nginx.alloy, monitoring/compose.yml |

Metrics are scraped every 60 seconds. Container discovery refreshes every 30 seconds.

Telemetry identifies this host as vm2323 and the environment as production. When replacing or adding a host, review those labels in the Alloy files.

### Find application logs

In Grafana Cloud's Loki query editor, use:

{compose_project="shared-server", app="requesthole"}

For gross.dev:

{compose_project="shared-server", service_name="grossdev"}

Logs carry stable Compose service names. Both RequestHole services share app="requesthole".

The pipeline normalizes recognized severity levels and attaches detected_level and http_status as structured metadata when available. It preserves original log messages; URLs and client IPs may remain in those messages.

All services inherit local Docker log rotation from compose.defaults.yml: JSON logs, 10 MB per file, up to three files per container.

### Dashboards and Grafana Cloud configuration

monitoring/shared-server-overview.json is a saved Grafana dashboard resource titled GrossNate Shared Server Overview. It includes public availability, host capacity, request metrics, recent logs, and alert information.

monitoring/knowledge-graph/nginx.yml contains the nginx Knowledge Graph configuration.

These files are not deployed by Compose. Changes must be applied separately in Grafana Cloud. After editing the dashboard in Grafana Cloud, export the updated resource back into the repository.

Synthetic checks, alert rules, notification routing, and data sources are not fully provisioned by this repository. Recreating the VPS alone does not recreate those Grafana Cloud settings.

### Monitoring endpoints

| Endpoint                                        | Reachable from                         |
| ----------------------------------------------- | -------------------------------------- |
| Alloy UI and health endpoints: 127.0.0.1:12345  | VPS                                    |
| Caddy metrics: 172.30.0.2:9180/metrics          | VPS and containers that can reach edge |
| nginx stub status: port 8080, path /stub_status | Allowed clients on the Docker network  |
| nginx exporter: port 9113                       | edge network                           |

No additional public firewall ports are needed for monitoring.

Alloy uses host networking and reads host filesystems and the Docker socket. Treat it as a privileged component, even though its mounts are configured read-only.

## Architecture and files

Internet → Caddy → grossdev
→ requesthole-nginx → requesthole-backend → requesthole_data

Host metrics ────────────────┐
Docker container logs ───────┤
Caddy metrics ───────────────┼→ Alloy → Grafana Cloud
nginx → nginx-exporter ──────┘

Caddy publishes ports 80 and 443. Alloy uses host networking, with its HTTP listener bound to localhost.

Public-facing application containers share the edge network. It allows communication between those containers; it does not isolate applications from one another.

RequestHole's backend uses the internal requesthole_private network and has no direct internet connection.

Fixed addresses support the trusted-proxy chain:

- Caddy: 172.30.0.2
- RequestHole nginx: 172.31.255.2
- RequestHole backend: 172.31.255.3

Preserve these addresses unless updating the corresponding trust configuration.

| Location                     | Purpose                                                             |
| ---------------------------- | ------------------------------------------------------------------- |
| compose.yml                  | Project, shared network, Caddy, and application includes            |
| compose.defaults.yml         | Shared Docker logging settings                                      |
| Caddyfile                    | Domains, routing, HTTPS, and Caddy metrics                          |
| apps/                        | Application services and supporting configuration                   |
| monitoring/                  | Alloy, nginx exporter, dashboard, and Knowledge Graph configuration |
| bootstrap.sh                 | Docker installation and initial server directories                  |
| .github/workflows/format.yml | Formatting checks; no deployment                                    |

## Change or add an application

Make configuration changes locally, commit and push them, then apply them on the VPS.

For a new application:

1. Add apps/<application>/compose.yml with its image, required environment, health check, and storage.
2. Include it in the root compose.yml, preserving the existing application and monitoring includes.
3. Add any image-version variable to .env.
4. Connect its public-facing service to edge, without publishing host ports.
5. Add domain routing to Caddyfile and configure DNS.
6. Start the application, reload Caddy, and verify public behavior.

Use the existing application files as examples. Launch everything from the root project rather than starting included Compose files separately.

Use named volumes for persistent application data. Place supporting services on application-specific networks. internal: true prevents direct external connectivity, so use it only when those services do not need outbound access.

New Compose containers are discovered automatically for logs. An optional logging.app Docker label groups multiple services under one application.

For another nginx service, mount monitoring/nginx-status.conf and add its scrape URI to nginx-exporter in monitoring/compose.yml.

### Local checks

Formatting requires Node.js/npm, Docker, and shfmt 3.14.1. Compose validation also requires dotenvx and the decryption key.

npm ci
npm run format
npm run check:format
dotenvx run -- docker compose config --quiet

Formatting checks do not validate application behavior, Alloy configuration, or Grafana Cloud connectivity.

## Set up a new VPS

Use a Docker-supported Ubuntu release, a regular SSH user with sudo access, and images compatible with the host architecture. The current application publishing workflows build for linux/amd64.

### 1. Configure network access

Allow inbound TCP on:

- Your SSH port
- Port 80
- Port 443

Preserve SSH access while changing firewall rules. Application and monitoring ports should remain unpublished.

Docker-published ports can bypass UFW rules. See Docker's firewall guidance (<https://docs.docker.com/engine/install/ubuntu/#firewall-limitations>).

Point these DNS names at the VPS:

| Name                | Record                            |
| ------------------- | --------------------------------- |
| gross.dev           | A record for the VPS IPv4 address |
| <www.gross.dev>       | CNAME to gross.dev                |
| requesthole.com     | A record for the VPS IPv4 address |
| <www.requesthole.com> | CNAME to requesthole.com          |
| health.gross.dev    | A record for the VPS IPv4 address |

Keep AAAA records only if IPv6 reaches this server.

### 2. Clone and install Docker

The repository is public; cloning over HTTPS requires no GitHub deploy key.

sudo apt-get update
sudo apt-get install -y git curl ca-certificates

sudo install -d -o "$USER" -g "$(id -gn)" -m 0755 /srv/server

git clone <https://github.com/GrossNate/my-shared-server.git> /srv/server

cd /srv/server
./bootstrap.sh

Bootstrap installs Docker Engine and Compose, enables Docker at boot, and adds your user to the Docker group. It does not configure DNS, firewall rules, dotenvx, or secrets.

Log out and reconnect, then verify:

docker version
docker compose version
docker ps

Docker group membership grants privileges equivalent to root.

### 3. Install dotenvx and restore the key

Install dotenvx using its official installation instructions (<https://dotenvx.com/docs/install/>):

curl -sfS <https://dotenvx.sh> | sh
dotenvx --version

Securely transfer the existing .env.keys into /srv/server/.env.keys, then restrict access:

cd /srv/server
chmod 600 .env.keys
dotenvx run -- docker compose config --quiet

Do not commit the key or generate a replacement for the existing encrypted .env.

### 4. Pull images and start services

Review the selected images, then start the project:

dotenvx run -- docker compose config --images
dotenvx run -- docker compose pull
dotenvx run -- docker compose up -d --wait --pull never
dotenvx run -- docker compose ps

Public application images require no registry login.

Compose creates the required networks and volumes. Caddy obtains and renews HTTPS certificates once DNS and inbound connectivity work.

--wait checks configured container health checks and whether other services are running. It does not verify public routing or telemetry delivery.

### 5. Verify applications and monitoring

Use the checks under “Check status and logs.” Also verify:

- Both sites load and their www and HTTP redirects work.
- RequestHole can receive and display a request.
- Grafana Cloud receives fresh metrics and container logs.
- External checks and alert notifications are configured as intended.

## Data and recovery

Persistent volumes hold:

- RequestHole application data: requesthole_data
- Caddy certificates and state: caddy_data, caddy_config
- Alloy collection state: alloy_data

No application-data backup and restore process is configured. RequestHole data is currently treated as disposable.

A new VPS starts with empty volumes unless data is restored separately. Preserve the dotenvx private key independently of the host.

Before hosting an application whose data must survive host loss, establish and test its backup and restore procedure.

When replacing a host, verify the new server before retiring the old one. DNS changes and container replacement can cause downtime.
