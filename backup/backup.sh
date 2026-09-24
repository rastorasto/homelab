#!/usr/bin/env bash
# backup.sh - nightly restic backup of the three trees that matter:
#   ~/docker  ~/docker-data  ~/repos   ->   /mnt/data/backup
# Snapshot trees are named exactly that: /docker /docker-data /repos.
# Cron (admin_user, created by ansible/tasks/deploy.yml):
#   17 3 * * * <checkout>/backup/backup.sh >> $DOCKER_DATA/.backup-metrics/backup.log 2>&1
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
set -a; source ./.env; set +a          # RESTIC_PASSWORD, DISCORD_WEBHOOK
set -a; source ../.env.shared; set +a  # DOCKER_DATA, APP_REPOS

# fail loudly on missing vars: docker auto-creates missing mount dirs as
# root-owned empty dirs, and restic backs them up silently (Sep 2026 incident).
: "${DOCKER_DATA:?missing - set it in ../.env.shared}"
: "${APP_REPOS:?missing - set it in ../.env.shared}"
CHECKOUT="$(cd .. && pwd)"   # this script lives inside the checkout
REPO_DIR="${RESTIC_REPOSITORY:-/mnt/data/backup}"
DUMPS="$DOCKER_DATA/.dumps"
METRICS_DIR="$DOCKER_DATA/.backup-metrics"
mkdir -p "$METRICS_DIR" "$DUMPS"

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

restic() {
    docker run --rm \
        -e RESTIC_PASSWORD \
        -e RESTIC_REPOSITORY=/repo \
        -e RESTIC_CACHE_DIR=/cache \
        -v "$REPO_DIR":/repo \
        -v "$CHECKOUT":/docker:ro \
        -v "$DOCKER_DATA":/docker-data:ro \
        -v "$APP_REPOS":/repos:ro \
        -v "backup-restic-cache:/cache" \
        restic/restic "$@"
}

# init repo on first run
if ! restic snapshots >/dev/null 2>&1; then
    log "initializing restic repo at $REPO_DIR"
    restic init >/dev/null || fail "restic init"
fi

# ---- consistent DB dumps (land in docker-data, ride along in the backup) ----
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
log "sqlite dump: omniroute"
rm -f "$DUMPS/omniroute.sqlite3"
docker run --rm --entrypoint sqlite3 -v "$DOCKER_DATA":/dd codeberg.org/forgejo/forgejo:16 \
    "/dd/omniroute/storage.sqlite" ".backup '/dd/.dumps/omniroute.sqlite3'" || fail "sqlite dump omniroute"
log "sqlite dump: forgejo"
docker exec forgejo sqlite3 /data/gitea/gitea.db ".backup '/data/gitea/gitea-backup.sqlite3'" \
    || fail "sqlite dump forgejo"

# ---- restic backup ----
log "restic backup"
restic backup /docker /docker-data /repos --tag nightly \
    --exclude='jellyfin/cache' \
    --exclude='caddy/logs' \
    --exclude='thelounge/data/logs' \
    --exclude='dockhand/data/.restic-cache' \
    --exclude='.backup-metrics' \
    >/dev/null || fail "restic backup"

# prune on Sundays (7d/4w/6m)
if [[ $(date +%u) == 7 ]]; then
    log "weekly forget/prune"
    restic forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6 >/dev/null || fail "restic forget"
fi

# ---- metrics ----
date +%s > "$METRICS_DIR/last_success"
{
    echo "restic_backup_last_success_timestamp $(cat "$METRICS_DIR/last_success")"
    echo "restic_backup_snapshots_total $(restic snapshots --json 2>/dev/null | grep -oE '"id":"[0-9a-f]+"' | wc -l || echo 0)"
} > "$METRICS_DIR/restic.prom"
log "OK"
