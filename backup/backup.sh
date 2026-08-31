#!/usr/bin/env bash
# backup.sh - nightly restic backup of docker-data (+ DB dumps) -> /mnt/data/backup
# Cron (user meow): 17 3 * * * /home/meow/docker/backup/backup.sh
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
set -a; source ./.env; set +a

set -a; [[ -f ../.env.shared ]] && source ../.env.shared; set +a
DOCKER_DATA="${DOCKER_DATA:-/home/meow/docker-data}"
APP_REPOS="${APP_REPOS:-/home/meow/repos}"
REPO_DIR="${RESTIC_REPOSITORY:-/mnt/data/backup}"
REPO_CHECKOUT="${REPO_CHECKOUT:-/home/meow/docker}"
DUMPS="$DOCKER_DATA/.dumps"
METRICS_DIR="$DOCKER_DATA/.backup-metrics"
RESTIC_IMG="restic/restic"

log()  { echo "[$(date '+%F %T')] $*"; }
fail() {
    log "FAILED: $1"
    echo "restic_backup_last_success_timestamp $(cat "$METRICS_DIR/last_success" 2>/dev/null || echo 0)" > "$METRICS_DIR/restic.prom" 2>/dev/null || true
    if [[ -n "${DISCORD_WEBHOOK:-}" ]]; then
        curl -sf -X POST -H 'Content-Type: application/json' \
            -d "{\"content\": \"backup FAILED: $1\"}" "$DISCORD_WEBHOOK" >/dev/null || true
    fi
    exit 1
}

restic_run() {
    docker run --rm \
        -e RESTIC_PASSWORD \
        -e RESTIC_REPOSITORY=/repo \
        -e RESTIC_CACHE_DIR=/cache \
        -v "$REPO_DIR":/repo \
        -v "$DOCKER_DATA":/data:ro \
        -v "$REPO_CHECKOUT":/repo-src:ro \
        -v "$APP_REPOS":/repos:ro \
        -v "backup-restic-cache:/cache" \
        "$RESTIC_IMG" "$@"
}

mkdir -p "$DUMPS" "$METRICS_DIR"

# init repo on first run
if ! restic_run snapshots >/dev/null 2>&1; then
    log "initializing restic repo at $REPO_DIR"
    restic_run init >/dev/null || fail "restic init"
fi

# ---- consistent DB dumps ----
log "dumping litellm postgres"
docker exec litellm-db sh -c 'pg_dumpall -U "$POSTGRES_USER"' | gzip > "$DUMPS/litellm-pgall.sql.gz" \
    || fail "pg_dump litellm-db"

for spec in "paperless /data/db.sqlite3" "vaultwarden /data/db.sqlite3"; do
    set -- $spec
    log "sqlite dump: $1 (hot .backup via forgejo image)"
    rm -f "$DUMPS/$1.sqlite3"
    docker run --rm --entrypoint sqlite3 -v "$DOCKER_DATA":/dd codeberg.org/forgejo/forgejo:16 \
        "/dd/$1/data/db.sqlite3" ".backup '/dd/.dumps/$1.sqlite3'" || fail "sqlite dump $1"
done

log "sqlite dump: forgejo"
docker exec forgejo sqlite3 /data/gitea/gitea.db ".backup '/data/gitea/gitea-backup.sqlite3'" \
    || fail "sqlite dump forgejo"

# ---- restic backup ----
log "restic backup"
backup_targets="/data /repo-src"
[[ -d "$APP_REPOS" ]] && backup_targets+=" /repos"
# shellcheck disable=SC2086
restic_run backup $backup_targets \
    --tag nightly \
    --exclude='jellyfin/cache' \
    --exclude='caddy/logs' \
    --exclude='thelounge/data/logs' \
    --exclude='dockhand/data/.restic-cache' \
    --exclude='.backup-metrics' \
    >/dev/null || fail "restic backup"

# prune + check on Sundays
if [[ $(date +%u) == 7 ]]; then
    log "weekly forget/prune"
    restic_run forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6 >/dev/null || fail "restic forget"
    log "weekly check"
    restic_run check >/dev/null || fail "restic check"
fi

# ---- metrics + done ----
date +%s > "$METRICS_DIR/last_success"
{
    echo "restic_backup_last_success_timestamp $(cat "$METRICS_DIR/last_success")"
    echo "restic_backup_snapshots_total $(restic_run snapshots --json 2>/dev/null | grep -c '"id"' || echo 0)"
} > "$METRICS_DIR/restic.prom"
log "OK"
