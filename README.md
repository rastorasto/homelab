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
git clone ssh://git@forgejo.mnau.org:222/rasto/ubuntu-docker.git infra && cd infra
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

Delete nothing under `$DOCKER_DATA` unless you mean it — there is no second copy
until the restic backups (Phase 3) are in place.

## Notes

- qBittorrent and caddy are excluded from auto-updates on purpose.
- caddy image is built locally (cloudflare DNS + docker-proxy plugins);
  `:latest` tags elsewhere, pinned per stack only where it matters.
- Search configs with secrets are generated into `$DOCKER_DATA` — repo carries
  only `.example` templates.
