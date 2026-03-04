#!/usr/bin/env zsh
# Restores .tgz backups from pub/__OLD_BACKUPS into pub3
# Usage: ./restore_backups.sh [pub_repo_path]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get pub repository path
PUB_REPO="${1:-../pub}"
PUB3_ROOT="$(pwd)"
BACKUP_DIR="$PUB_REPO/__OLD_BACKUPS"
TEMP_DIR="/tmp/pub3_restore_$$"

if [[ ! -d "$BACKUP_DIR" ]]; then
    log_error "Backup directory not found: $BACKUP_DIR"
    log_info "Clone pub repository first: gh repo clone anon987654321/pub ../pub"
    exit 1
fi

log_info "Starting backup restoration from $BACKUP_DIR"
mkdir -p "$TEMP_DIR"

# Priority 1: Extract egpt → aight/
restore_egpt() {
    log_info "Priority 1: Extracting egpt_20240806.tgz → aight/"
    
    local archive="$BACKUP_DIR/egpt_20240806.tgz"
    if [[ ! -f "$archive" ]]; then
        log_warn "Archive not found: $archive"
        return 1
    fi
    
    # Extract to temp
    tar -xzf "$archive" -C "$TEMP_DIR"
    
    # Rename AI3 → Aight, ai3 → aight
    log_info "Renaming AI3 → Aight throughout codebase..."
    find "$TEMP_DIR" -type f -name "*.rb" -exec sed -i.bak 's/AI3/Aight/g' {} \;
    find "$TEMP_DIR" -type f -name "*.rb" -exec sed -i.bak 's/ai3/aight/g' {} \;
    find "$TEMP_DIR" -type f -name "*.yml" -exec sed -i.bak 's/ai3/aight/g' {} \;
    
    # Remove backup files
    find "$TEMP_DIR" -name "*.bak" -delete
    
    # Rename main file
    [[ -f "$TEMP_DIR/ai3.rb" ]] && mv "$TEMP_DIR/ai3.rb" "$TEMP_DIR/aight.rb"
    
    # Scan for credentials
    log_info "Scanning for credentials..."
    if grep -r -i "api_key\|password\|secret\|token" "$TEMP_DIR" | grep -v "README\|\.md\|example"; then
        log_error "Found potential credentials! Review before committing."
        return 1
    fi
    
    # Copy to pub3
    mkdir -p "$PUB3_ROOT/aight"
    cp -r "$TEMP_DIR/"* "$PUB3_ROOT/aight/"
    
    log_info "✓ egpt extracted to aight/"
}

# Main execution
main() {
    log_info "================================================"
    log_info "pub3 Backup Restoration Script"
    log_info "================================================"
    
    # Execute restoration priority 1
    restore_egpt || log_warn "egpt restoration failed"
    
    log_info "Restoration complete. Run with full implementation for all priorities."
}

# Run main
main "$@"
