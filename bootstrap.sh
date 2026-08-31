#!/usr/bin/env bash
# bootstrap - prepare a fresh machine for this repo.
# Safe to re-run (idempotent).
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

echo "== checking docker"
docker version >/dev/null
docker compose version >/dev/null

echo "== fetching git submodules"
git submodule update --init --recursive

if [[ ! -f .env.shared ]]; then
    cp .env.shared.example .env.shared
    echo "!! .env.shared created from example - EDIT IT before continuing"
    exit 1
fi
set -a; source .env.shared; set +a
: "${DOCKER_DATA:?DOCKER_DATA missing in .env.shared}"

echo "== creating networks"
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy

echo "== creating data dirs under $DOCKER_DATA"
for d in \
    audiobookshelf/config audiobookshelf/metadata \
    caddy/data caddy/config caddy/logs \
    freshrss/data freshrss/extensions \
    jellyfin jellyfin/cache \
    paperless/data paperless/media paperless/export paperless/consume paperless/redis \
    qbittorrent/config running/data \
    thelounge/data forgejo/data vaultwarden/data \
    dockhand/data litellm/postgres searxng/config; do
    mkdir -p "$DOCKER_DATA/$d"
done

echo "== checking per-stack secrets"
missing=0
for ex in stacks/*/.env.example; do
    [[ -e $ex ]] || continue
    env_file="${ex%.example}"
    if [[ ! -f $env_file ]]; then
        echo "  MISSING: $env_file  (template: $ex)"
        missing=1
    fi
done
[[ $missing == 0 ]] && echo "  all .env files present"

echo "== done. Next: ./lab up"
