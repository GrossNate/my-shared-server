# My Shared Server

This repository configures an Ubuntu VPS for hosting multiple applications. Each app supplies its own container images. To add an app, give it a Compose file, include it in the shared project, and add a Caddy route and DNS record. Existing apps can stay as they are.

gross.dev and RequestHole are the first two apps. Both use the same Caddy proxy and Grafana Cloud monitoring.

[Update an app](#update-an-app) · [Apply server changes](#apply-server-changes) · [Check status and logs](#check-status-and-logs) · [Add an app](#add-an-app) · [Set up a VPS](#set-up-a-vps)

## Update an app

Run the server commands as your regular SSH user. Use `dotenvx run --strict --` when starting or recreating Alloy, including when bringing up the full stack. The other routine commands use plain Compose.

### gross.dev

Wait for the [grossdev image build](https://github.com/GrossNate/grossdev/actions/workflows/publish-image.yml) to succeed.

```bash
cd /srv/server &&
  docker compose up --wait --pull always grossdev &&
  curl -fsS -o /dev/null https://gross.dev/
```

### RequestHole

Wait for the [RequestHole image build](https://github.com/GrossNate/requesthole/actions/workflows/docker.yml) to finish publishing both images. The commands pull both before updating either container.

```bash
cd /srv/server &&
  docker compose up --wait --pull always requesthole-backend requesthole-nginx &&
  curl -fsS -o /dev/null https://requesthole.com/
```

For a functional check, open RequestHole, create a hole, send it a request, and confirm the request appears.

Both apps currently select `latest` in `.env`. `--pull always` checks the registry even if the selected tag is already cached. Compose reuses layers it already has and replaces containers whose image or service configuration changed. Replacement can briefly interrupt the app.

`--wait` runs services in the background and waits for them to be healthy or, without a health check, running. The `curl` command checks the public HTTPS route. A failed check does not roll back the deployment. See [Docker Compose up](https://docs.docker.com/reference/cli/docker/compose/up/).

### Deploy a specific version or roll back

Change the app’s version in `.env` locally, commit and push, then run `git pull --ff-only` on the VPS before repeating the app’s update block.

| App         | Variable              | Published commit tag                |
| ----------- | --------------------- | ----------------------------------- |
| gross.dev   | `GROSSDEV_VERSION`    | `sha-<full commit SHA>`             |
| RequestHole | `REQUESTHOLE_VERSION` | `<full commit SHA>` for both images |

Use a previously working tag to roll back. Reverting an image does not undo database migrations.

## Apply server changes

After pushing configuration changes, fetch and validate them on the VPS.

```bash
cd /srv/server &&
  git pull --ff-only &&
  docker compose config --quiet
```

A Git pull updates the checkout. Use the relevant command below to apply the change to running services. For changes spanning several components, start any new upstream services before reloading Caddy.

### Caddy routes or domains

```bash
cd /srv/server &&
  docker compose exec -T caddy \
    caddy reload --config - --adapter caddyfile < Caddyfile
```

`-T` disables terminal allocation so the host’s `Caddyfile` can be piped into Caddy even if Git replaced the mounted file. Caddy reloads without restarting the container and keeps its previous configuration if it rejects the new one. See [Caddy reload](https://caddyserver.com/docs/command-line#caddy-reload).

### Compose service settings

Target the service you changed. For example, after editing Caddy’s Compose settings:

```bash
cd /srv/server &&
  docker compose up --wait --pull never caddy
```

`--pull never` keeps a configuration update from fetching a new image. It uses the local image for the configured tag, which may differ from the running container’s image if someone already pulled that tag. To intentionally change an image, use the app update command or `up --wait --pull always` for the affected service. Use dotenvx if the command includes Alloy. Plan shared network changes separately because they can affect several services.

### Alloy configuration or Grafana Cloud credential

```bash
cd /srv/server &&
  docker compose run --rm --pull never alloy validate /etc/alloy &&
  dotenvx run --strict -- docker compose up --wait --pull never --force-recreate alloy
```

The temporary validator checks the files without sending telemetry. `--force-recreate` then makes the running service pick up the current credential and any mounted files Git replaced. Check Alloy health and logs below and confirm fresh data in Grafana Cloud. See [Alloy validation](https://grafana.com/docs/alloy/latest/reference/cli/validate/) and [Alloy health endpoints](https://grafana.com/docs/alloy/latest/reference/http/).

### Mounted nginx configuration

If `monitoring/nginx-status.conf` changed, recreate both nginx frontends.

```bash
cd /srv/server &&
  docker compose up --wait --pull never --force-recreate --no-deps grossdev requesthole-nginx
```

If only `apps/requesthole/nginx/realip.conf` changed, recreate the RequestHole frontend.

```bash
cd /srv/server &&
  docker compose up --wait --pull never --force-recreate --no-deps requesthole-nginx
```

Use these commands when RequestHole’s backend is already healthy. `--no-deps` leaves it alone. Recreating the frontends picks up the current files and can briefly interrupt the sites.

> [!CAUTION]
> Use `up` for routine changes. `restart` reuses existing containers and does not apply new images or Compose settings. `down` stops the entire project, and `down -v` can delete persistent data.

## Check status and logs

Run these on the VPS.

```bash
cd /srv/server
docker compose ps
docker compose logs --tail=100 caddy
docker compose logs --tail=100 grossdev
docker compose logs --tail=100 requesthole-backend requesthole-nginx
docker compose logs --tail=100 alloy nginx-exporter
```

Add `--follow` to a `logs` command to stream new entries. Check public HTTPS and Alloy separately.

```bash
curl -fsS https://health.gross.dev/
curl -fsS -o /dev/null https://gross.dev/
curl -fsS -o /dev/null https://requesthole.com/
curl -fsS http://127.0.0.1:12345/-/healthy
```

`health.gross.dev` is served by Caddy and verifies its public HTTPS route. The site URLs check their respective routes. The Alloy endpoint is reachable from the VPS.

## Add an app

1. Create `apps/<app>/compose.yml`. Start with [grossdev](apps/grossdev/compose.yml) for a single service or [RequestHole](apps/requesthole/compose.yml) for a frontend and backend. Use unique service names, define a health check, and use named volumes for persistent data.
2. Add the app’s Compose file to `include` in the [root Compose file](compose.yml). If the image reference uses a version variable, add its value to `.env`.
3. Attach the public-facing service to `edge`. Let Caddy handle public traffic. Put private dependencies on an app-specific network and leave their host ports unpublished.
4. Add the domain to `Caddyfile` and point its DNS at the VPS. In the Caddy route, use the Compose service name and its internal listening port.
5. Commit and push. On the VPS, fetch and validate the changes, then run `docker compose up --wait --pull always` followed by the new app’s service names. Reload Caddy once the app is ready, then test the public URL.

All deployment commands run from the root project at `/srv/server`. Docker’s [Compose include reference](https://docs.docker.com/reference/compose-file/include/) explains how it resolves each app’s local paths.

Alloy discovers container logs automatically. Use the same `logging.app` label across an app’s services to group their logs. Adding nginx metrics is optional and requires a scrape target in [monitoring/compose.yml](monitoring/compose.yml).

### Validate changes locally

```bash
npm ci
npm run check:format
docker compose config --quiet
```

Formatting uses Node.js/npm, Docker, and shfmt 3.14.1. Use `npm run format` to fix formatting failures. The GitHub workflow checks formatting. Deployments are manual.

## Configuration and secrets

| File        | Contents                                                                           |
| ----------- | ---------------------------------------------------------------------------------- |
| `.env`      | Committed app image tags, dotenvx public key, and encrypted `GCLOUD_RW_API_KEY`    |
| `.env.keys` | Private decryption key. Git ignores this file. Keep a secure copy outside the VPS. |

`dotenvx run --strict --` decrypts the Grafana Cloud credential for Compose and stops if dotenvx encounters an error. A new clone needs the matching `.env.keys` file to start Alloy. See [dotenvx run](https://dotenvx.com/docs/cli/run/).

Use `docker compose config --quiet` to validate the Compose model or `docker compose config --images` to list its images. Plain Compose can accept the encrypted value, so successful validation alone does not prove Alloy has a usable credential. Full resolved configuration and container inspection can expose decrypted secrets.

To rotate the Grafana Cloud credential, use [dotenvx set](https://dotenvx.com/docs/cli/set/) to update `GCLOUD_RW_API_KEY` with encryption. Commit the encrypted `.env`, pull it on the VPS, and follow the Alloy update procedure.

## Observability

Open **GrossNate Shared Server Overview** in Grafana Cloud to see availability, host capacity, HTTP traffic, container logs, and alerts.

| Signal                              | How it gets to Grafana Cloud                                                           |
| ----------------------------------- | -------------------------------------------------------------------------------------- |
| Host CPU, memory, disk, and network | Alloy’s Unix exporter                                                                  |
| HTTP request metrics by site        | Alloy scrapes Caddy on `172.30.0.2:9180`                                               |
| nginx requests and connections      | `nginx-exporter` reads `/stub_status` from both frontends. Alloy scrapes the exporter. |
| Container stdout and stderr         | Alloy discovers Docker containers and sends their logs to Loki                         |

Alloy listens on `127.0.0.1:12345`. Metrics and exporter ports stay off the public firewall. The Alloy configuration labels this VPS `vm2323` and the environment `production`. Review those labels when moving to a different host.

### Find logs in Grafana Cloud

In Explore, select the Loki data source. To see both RequestHole services:

```logql
{compose_project="shared-server", app="requesthole"}
```

For gross.dev:

```logql
{compose_project="shared-server", service_name="grossdev"}
```

The pipeline preserves original log messages and attaches normalized severity and HTTP status as structured metadata when it can extract them. Local Docker logs rotate at 10 MB per file, with up to three files per container. See [compose.defaults.yml](compose.defaults.yml).

### Grafana Cloud settings

[The dashboard export](monitoring/shared-server-overview.json) and [nginx Knowledge Graph configuration](monitoring/knowledge-graph/nginx.yml) are kept in this repository for reference. Manage them in Grafana Cloud. Compose applies the VPS collector configuration only. Review synthetic checks, data sources, alerts, and notifications separately when restoring monitoring.

## Network and data

Caddy publishes ports 80 and 443 and forwards traffic over `edge`. Services on `edge` can reach one another. RequestHole’s backend is on the separate internal `requesthole_private` network.

Preserve the Caddy address `172.30.0.2` and the RequestHole nginx address `172.31.255.2` when making network changes. RequestHole uses those addresses to trust its proxy chain and recover the client IP.

| Volume                       | Data                         |
| ---------------------------- | ---------------------------- |
| `requesthole_data`           | RequestHole database         |
| `caddy_data`, `caddy_config` | Caddy certificates and state |
| `alloy_data`                 | Alloy collection state       |

A fresh VPS starts with empty volumes. RequestHole data is currently treated as disposable and has no configured backup. Before hosting an app that needs to survive host loss, set up and test its backup and restore procedure.

## Set up a VPS

### 1. Prepare the host

Use a Docker-supported Ubuntu release and a regular SSH user with sudo access. The current application images target `linux/amd64`.

Allow inbound TCP on your SSH port and ports 80 and 443. Point `gross.dev`, `requesthole.com`, and `health.gross.dev` at the VPS. Point each `www` name at its respective apex domain. Keep IPv6 records only if the VPS can serve those names over IPv6.

### 2. Install Docker and dotenvx

Clone the public repository and run the bootstrap script.

```bash
sudo apt-get update &&
  sudo apt-get install -y git &&
  sudo install -d -o "$USER" -g "$(id -gn)" -m 0755 /srv/server &&
  git clone https://github.com/GrossNate/my-shared-server.git /srv/server &&
  cd /srv/server &&
  ./bootstrap.sh
```

Bootstrap installs Docker and adds your user to the `docker` group, which grants root-equivalent access. Log out and reconnect, then check `docker compose version` and `docker ps`.

Install dotenvx using the [official installation instructions](https://dotenvx.com/docs/install/). Securely copy the existing private key file to `/srv/server/.env.keys`.

### 3. Start and verify the stack

```bash
cd /srv/server &&
  chmod 600 .env.keys &&
  dotenvx run --strict -- docker compose up --wait
```

Compose creates the networks and volumes. Caddy obtains HTTPS certificates once DNS and inbound connectivity are working.

Use [Check status and logs](#check-status-and-logs) to verify both apps and Alloy. Check HTTP-to-HTTPS and `www` redirects, send a request through RequestHole, and confirm that Grafana Cloud receives fresh metrics and logs.
