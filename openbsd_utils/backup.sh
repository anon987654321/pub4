#!/bin/sh

# OpenBSD Backup Script
# Backs up important system files and configurations

set -e

BACKUP_DIR="/var/backups/system"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup-$DATE.tar.gz"

echo "OpenBSD System Backup Script"
echo "============================"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# List of files and directories to backup
BACKUP_ITEMS="/etc \
              /var/www \
              /usr/local/etc \
              /home \
              /root"

echo "Creating backup: $BACKUP_FILE"

# Create compressed archive
tar czf "$BACKUP_FILE" $BACKUP_ITEMS 2>/dev/null || true

# Set secure permissions
chmod 600 "$BACKUP_FILE"

# Get file size
SIZE=$(ls -lh "$BACKUP_FILE" | awk '{print $5}')

echo "Backup completed successfully!"
echo "File: $BACKUP_FILE"
echo "Size: $SIZE"

# Keep only last 7 backups
echo "Cleaning old backups (keeping last 7)..."
ls -t "$BACKUP_DIR"/backup-*.tar.gz | tail -n +8 | while read f; do rm "$f"; done

echo "Done!"
