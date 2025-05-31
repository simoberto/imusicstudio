#!/bin/bash
set -euo pipefail

# Configuration - these should be passed as environment variables to the Docker container
readonly BACKUP_DIR="${BACKUP_DIR_PATH:-/backups}" # Default path inside the container
readonly RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
readonly DATE_FORMAT=$(date +%Y%m%d_%H%M%S)

# Database connection details (expected as environment variables)
readonly PG_HOST="${POSTGRES_HOST:-postgres}"
readonly PG_USER="${POSTGRES_USER:-n8n}"
readonly PG_DB_NAME="${POSTGRES_DB:-n8n}"
# PGPASSWORD should be set as an environment variable for the container running this script.

# Log function
log_backup() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [backup.sh]: $1"
}

log_backup "Starting backup process..."

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"
log_backup "Backup directory: $BACKUP_DIR"

# Database backup
DB_BACKUP_FILE="$BACKUP_DIR/db_dump_${PG_DB_NAME}_${DATE_FORMAT}.sql.gz"
log_backup "Backing up PostgreSQL database '$PG_DB_NAME' from host '$PG_HOST' to $DB_BACKUP_FILE..."
if pg_dump -h "$PG_HOST" -U "$PG_USER" -d "$PG_DB_NAME" --clean --if-exists | gzip > "$DB_BACKUP_FILE"; then
    log_backup "Database backup successful: $(basename "$DB_BACKUP_FILE")"
else
    log_backup "ERROR: Database backup failed for $PG_DB_NAME. Removing potentially incomplete file."
    rm -f "$DB_BACKUP_FILE" # Remove partial backup
    # Optionally, send a notification here
fi

# Data directory backup (e.g., /data volume mounted from host or other containers)
# This part is highly dependent on what exactly needs to be backed up from /data.
# If /data contains generated files, n8n user files, etc.
# This example assumes a generic backup of a directory named 'app_data_volume' mounted at /app_data_to_backup
# In the context of this project, it's likely the shared '/data' volume.

SHARED_DATA_DIR_TO_BACKUP="/data" # Path inside this backup container where the shared volume is mounted
if [[ -d "$SHARED_DATA_DIR_TO_BACKUP" ]]; then
    DATA_BACKUP_FILE="$BACKUP_DIR/shared_data_volume_${DATE_FORMAT}.tar.gz"
    log_backup "Backing up shared data directory '$SHARED_DATA_DIR_TO_BACKUP' to $DATA_BACKUP_FILE..."
    # Exclude potentially very large or temporary subdirectories if necessary
    # Example: --exclude='*.tmp' --exclude='cache/*'
    if tar -czf "$DATA_BACKUP_FILE" -C "$(dirname "$SHARED_DATA_DIR_TO_BACKUP")" "$(basename "$SHARED_DATA_DIR_TO_BACKUP")"; then
        log_backup "Shared data backup successful: $(basename "$DATA_BACKUP_FILE")"
    else
        log_backup "ERROR: Shared data backup failed for $SHARED_DATA_DIR_TO_BACKUP. Removing potentially incomplete file."
        rm -f "$DATA_BACKUP_FILE"
    fi
else
    log_backup "Shared data directory '$SHARED_DATA_DIR_TO_BACKUP' not found. Skipping data backup."
fi


# Cleanup old backups
log_backup "Cleaning up old backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "*.sql.gz" -mtime "+$RETENTION_DAYS" -print -delete
find "$BACKUP_DIR" -name "*.tar.gz" -mtime "+$RETENTION_DAYS" -print -delete
log_backup "Cleanup of old backups complete."

log_backup "Backup process finished."
echo # Trailing newline for cron jobs if any issue with output buffering
