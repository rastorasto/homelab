#!/usr/bin/env bash
# blog-sync.sh - push-to-publish for the blog.
# Pulls the latest blog repo on the ubuntu-vm and rsyncs it to the VPS clone at
# smol:/home/ubuntu/repos/blog (its hugo container rebuilds on change).
#
# Why push, not pull: forgejo git is tailnet-only and the VPS has no tailscale,
# so VPS can't clone. Runs from cron every 5 min (ubuntu-vm, user meow):
#   */5 * * * * /home/meow/docker/blog-sync.sh
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

BLOG_DIR="${APP_REPOS:-/home/meow/repos}/blog"
cd "$BLOG_DIR"
git pull -q --ff-only

rsync -az --delete \
    --exclude='.git' \
    --exclude='site/public' \
    --exclude='site/resources/_gen' \
    --exclude='.DS_Store' \
    --exclude='.hugo_build.lock' \
    ./ "smol:/home/ubuntu/repos/blog/"
