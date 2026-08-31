# infra

Self-hosted lab. Git = declarative truth; runtime state lives outside the repo.

## Layout

```
lab                     # helper: ./lab up|down|restart|pull|logs|ps [stack ...]
bootstrap.sh            # first-run setup on a fresh machine (networks, dirs, env checks)
.env.shared             # per-host, gitignored: DOMAIN_NAME, TAILSCALE_IP, DOCKER_DATA
stacks/<name>/          # one self-contained docker compose project per service
```

Runtime state (container configs, databases, metadata) lives in `$DOCKER_DATA`
(default `/home/meow/docker-data`). Media/torrents/backups live on `/mnt/data` (HDD).

## Access model

- Private services: `https://<service>.mnau.org` via Caddy on the Tailscale IP only
  (wildcard cert via Cloudflare DNS-01; DNS records point at the Tailscale IP).
- Public: blog + counter are served from the Oracle VPS (Pangolin), no tunnel home.
- forgejo git: SSH on `<tailscale-ip>:222`.

## First run on a machine

```sh
git clone --recurse-submodules ssh://git@forgejo.mnau.org:222/rasto/ubuntu-docker.git infra && cd infra
cp .env.shared.example .env.shared   # adjust values
./bootstrap.sh                       # creates networks + data dirs, reports missing .env files
./lab up                             # starts all stacks
./lab ps                             # status
```

Secrets are per-stack `.env` files (gitignored); `.env.example` files document what is needed.
Keep a copy of every `.env` (and the restic password) in vaultwarden.

## Everyday operations

```sh
./lab up jellyfin         # (re)start one stack after editing its compose.yml
./lab pull && ./lab up    # manual image update of everything
./lab logs caddy -f
```

Adding a service = new `stacks/<name>/compose.yml` with caddy labels:
```yaml
labels:
  caddy: myservice.${DOMAIN_NAME:-mnau.org}
  caddy.reverse_proxy: "{{upstreams 8080}}"
```
The route appears/disappears with the container (caddy-docker-proxy); no central file to edit.
Non-docker targets (e.g. Proxmox UIs) and the public `:8081` block live in `stacks/caddy/Caddyfile`.
Removing = `./lab down <name>` and delete the dir. Data is state under `$DOCKER_DATA/<name>`.

## Backups

Nightly at 03:17 (user crontab): `backup/backup.sh`
1. Dumps databases consistently: `pg_dumpall` from litellm-db; sqlite `.backup`
   for paperless, vaultwarden, forgejo -> `$DOCKER_DATA/.dumps/`
2. restic -> `/mnt/data/backup` (HDD; docker-data + this repo; caches/logs excluded)
3. Sundays: forget/prune (7 daily / 4 weekly / 6 monthly) + `restic check`
4. Failure -> Discord webhook (set `DISCORD_WEBHOOK` in `backup/.env`)

**The repo password is in `backup/.env` (chmod 600) - keep a copy in vaultwarden.
Without it, `/mnt/data/backup` is unreadable.**

Restore drill:
```sh
set -a && . backup/.env && set +a
docker run --rm -e RESTIC_PASSWORD -v /mnt/data/backup:/repo restic/restic -r /repo snapshots
docker run --rm -e RESTIC_PASSWORD -v /mnt/data/backup:/repo -v /tmp/restore:/restore \
  restic/restic -r /repo restore latest --target /restore --include /data/vaultwarden
```

## Monitoring

`stacks/monitoring`: Prometheus (7d retention) + Grafana + Alertmanager +
node-exporter (incl. backup textfile metrics) + cAdvisor + blackbox exporter.

- UIs: https://grafana.mnau.org (admin pw in `stacks/monitoring/.env`, also in vaultwarden) and https://prometheus.mnau.org
- Alerts -> Discord once `DISCORD_WEBHOOK` is set in `stacks/monitoring/.env`
  (until then Alertmanager fires to a blackhole - set it and `./lab up monitoring`).
- Backup freshness alert fires if the nightly restic run is >36h stale.
- Public checks: blog/counter/pangolin via blackbox (from here, through the VPS).
- Remote nodes (PVE host, VPS): see `stacks/monitoring/agents/README.md` -
  their `up` targets stay down until you run `install-node-exporter.sh` there
  (from your MacBook where ssh works).

Delete nothing under `$DOCKER_DATA` unless you mean it.

## Notes

- `stacks/running` is a git submodule (rasto/running on forgejo). App code
  changes: commit/push from inside it (`docker-compose.yml` there = MacBook
  local dev, `compose.yml` = deployment here), then `./lab build running &&
  ./lab up running` and bump the pinned commit in this repo.
- qBittorrent and caddy are excluded from auto-updates on purpose.
- caddy image is built locally (cloudflare DNS + docker-proxy plugins);
  `:latest` tags elsewhere, pinned per stack only where it matters.
- Search configs with secrets are generated into `$DOCKER_DATA` — repo carries
  only `.example` templates.
