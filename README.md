# Homelab

My self-hosted server — one box running ~20 services, fully declarative.

## Running here

| Area | Services |
|------|----------|
| Media | Jellyfin, Audiobookshelf |
| Docs / feeds | Paperless, FreshRSS |
| Dev | Forgejo + CI runner, Dockhand |
| Secrets / auth | Vaultwarden |
| LLM tooling | LiteLLM + OmniRoute gateways, OpenWebUI |
| Monitoring | Prometheus, Grafana, Alertmanager |

## How it's wired

- **Declarative GitOps** — this repo is the source of truth;
  `./lab up <stack>` applies any change at runtime
- **Ansible** provisions a blank Ubuntu box end to end
- **Networking** — Caddy with one wildcard TLS cert, bound to Tailscale only,
  nothing exposed publicly
- **Backups** — nightly restic dumps (Postgres / SQLite / configs) to an HDD
- **One service per compose project** in `stacks/`, secrets kept in
  gitignored per-stack `.env` files

## Layout

```text
stacks/<service>/compose.yml   # one self-contained project per service
lab                            # helper: up / down / logs / ps / pull / build
bootstrap.sh                   # first-run setup
ansible/                       # host provisioning
```
