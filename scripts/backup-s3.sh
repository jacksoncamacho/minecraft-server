#!/bin/bash
# --- Configuration ---
MINECRAFT_DIRECTORY="/opt/minecraft"
S3_BUCKET="${s3_bucket}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# --- Backup ---
echo "Starting backup at $TIMESTAMP..."

# Sync world folder to S3
# We use sync to avoid uploading everything every time, but also keep versioned backups?
# Let's do a simple sync for now as requested for "nothing fragile"
aws s3 sync $MINECRAFT_DIRECTORY/world s3://$S3_BUCKET/backups/world/

# Optional: Periodic full zip for safety
# zip -r backup_$TIMESTAMP.zip world/
# aws s3 cp backup_$TIMESTAMP.zip s3://$S3_BUCKET/full_backups/

echo "Backup completed."
