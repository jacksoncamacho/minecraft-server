#!/bin/bash
# backup-s3.sh — Optimal incremental world backup to S3
# Called every 15 min by cron. Only uploads changed files. No new folders created.

set -euo pipefail

# Load S3 bucket name written at boot by setup-server.sh
ENV_FILE="/opt/minecraft/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "[backup] ERROR: $ENV_FILE not found. Was setup-server.sh run?" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

MINECRAFT_DIR="/opt/minecraft"
LOG_PREFIX="[backup $(date '+%Y-%m-%d %H:%M:%S')]"

echo "$LOG_PREFIX Starting incremental backup to s3://$S3_BUCKET/backups/latest/"

# 1. Tell Minecraft to flush all chunks to disk, then wait briefly
if sudo -u minecraft screen -list 2>/dev/null | grep -q minecraft; then
  sudo -u minecraft screen -S minecraft -X eval 'stuff "save-all\015"'
  sleep 3
fi

# 2. Incremental sync — only uploads files whose size changed.
#    --size-only avoids re-uploading files just because their timestamp changed.
#    --exclude skips junk files that change every tick but aren't needed for restore.
/usr/local/bin/aws s3 sync \
  "$MINECRAFT_DIR/world/" \
  "s3://$S3_BUCKET/backups/latest/" \
  --size-only \
  --exclude "*.lock" \
  --exclude "session.lock" \
  --exclude "*.tmp" \
  --exclude "logs/*" \
  --exclude "crash-reports/*" \
  --no-progress

echo "$LOG_PREFIX Incremental backup complete."
