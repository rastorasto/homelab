# infra

Self-hosted lab. Git = declarative truth; runtime state lives outside the repo.

## Layout

This repo = **platform** (edge, monitoring, backup, tooling, catalog). Services
can also live in their **own repos** (e.g. `rasto/running`), cloned as siblings:

```
lab                     # helper: ./lab up|down|restart|pull|build|logs|ps [stack ...]
bootstrap.sh            # first-run setup (networks, dirs, repos.conf, env checks)
repos.conf              # manifest: service repo URLs cloned into $APP_REPOS by bootstrap
.env.shared             # per-host, gitignored: DOMAIN_NAME, TAILSCALE_IP, DOCKER_DATA, APP_REPOS
stacks/<name>/          # platform-owned compose projects
stacks/templates/service/  # scaffold for new service repos (see "Adding a service")
```

`lab` discovers stacks in **both** `stacks/*/compose.yml` (platform) and
`${APP_REPOS}/*/compose.yml` (service repos, e.g. `/home/meow/repos/running`);
compose project name = directory name. Residence rule: **your own code with its
own history → `$APP_REPOS`; everything else → `stacks/`** (`./lab ls` shows the
split). Runtime state (container configs, databases, metadata) lives in
`$DOCKER_DATA` (default `/home/meow/docker-data`).
Media/torrents/backups live on `/mnt/data` (HDD).

## Access model

- Private services: `https://<service>.mnau.org` via Caddy on the Tailscale IP only
  (wildcard cert via Cloudflare DNS-01; DNS records point at the Tailscale IP).
- Public: blog + counter are served from the Oracle VPS (Pangolin), no tunnel home.
- forgejo git: SSH on `<tailscale-ip>:222`.

## First run on a machine

```sh
git clone ssh://git@forgejo.mnau.org:222/rasto/ubuntu-docker.git infra && cd infra
cp .env.shared.example .env.shared   # adjust values
./bootstrap.sh                       # networks, data dirs, clones repos.conf into $APP_REPOS, env checks
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

Adding a service (see `stacks/templates/service/README`:
1. `forgejo new <svc>` → clone into `$APP_REPOS/<svc>`
2. copy `stacks/templates/service/*` into it (Dockerfile stub, `compose.yml`
   with caddy labels, `.env.example` — the secrets contract)
3. add the repo URL to `repos.conf`, push
4. `./lab up <svc>` — route appears via caddy labels:
```yaml
labels:
  caddy: myservice.${DOMAIN_NAME:-mnau.org}
  caddy.reverse_proxy: "{{upstreams 8080}}"
```
Non-docker targets (e.g. Proxmox UIs) and the public `:8081` block live in `stacks/caddy/Caddyfile`.

Removing = `./lab down <name>`, delete the stack's compose (repo and/or `stacks/<name>/`),
and remove the URL from `repos.conf`. Data under `$DOCKER_DATA/<name>` outlives the app
and stays backed up.

## Backups

Nightly at 03:17 (user crontab): `backup/backup.sh`
1. Dumps databases consistently: `pg_dumpall` from litellm-db and bookorbit-db;
   sqlite `.backup` for paperless, vaultwarden, forgejo -> `$DOCKER_DATA/.dumps/`
2. restic -> `/mnt/data/backup` (HDD; `docker-data`, this repo checkout (all
   tracked/.gitignored files incl. per-stack `.env`), and `$APP_REPOS`)
3. Sundays: forget/prune (7 daily / 4 weekly / 6 monthly) + `restic check`
4. Failure -> Discord webhook (set `DISCORD_WEBHOOK` in `backup/.env`)

Note: `.env` per-stack secrets ARE inside snapshots (restic doesn't honour
`.gitignore`) — restore covers them too. Chicken-and-egg: only two secrets are
needed BEFORE the restore itself works — `RESTIC_PASSWORD` (`backup/.env`) and
`CF_API_TOKEN` (`stacks/caddy/.env`) — have them in vaultwarden ready
(see ansible/README.md for the rebuild flow).

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

- Ownership split: this repo is the platform (edge, monitoring, backup, tooling);
  services that deserve their own history live in their own forgejo repos,
  cloned under `$APP_REPOS` (see `repos.conf`). Their `compose.yml` is the
  deploy spec (e.g. `~/repos/running/compose.yml`); `lab` treats them like any
  platform stack.
- qBittorrent and caddy are excluded from auto-updates on purpose.
- qBittorrent and caddy are excluded from auto-updates on purpose.
- caddy image is built locally (cloudflare DNS + docker-proxy plugins);
  `:latest` tags elsewhere, pinned per stack only where it matters.
- Search configs with secrets are generated into `$DOCKER_DATA` — repo carries
  only `.example` templates.
