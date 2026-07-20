#!/usr/bin/env zsh
# Repo-archaeology helper — NOT disaster recovery.
# Extracts pub3-era installer heredocs from RAILS deploy scripts into railsy/restored_apps/.
#
# Usage: zsh OPENBSD/extract_legacy_installers.sh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
RESTORE_TMP="$ROOT_DIR/tmp/restore"

log() { printf '[extract] %s\n' "$*"; }

restore_repo_tree() {
  local src="$1"
  local dest="$2"
  if [[ -d "$src" ]]; then
    log "restoring $(basename "$dest") from ${src#$ROOT_DIR/}"
    rm -rf "$dest"
    mkdir -p "$dest"
    rsync -a --delete --exclude '.git' "$src/" "$dest/"
  else
    log "missing source: ${src#$ROOT_DIR/}"
  fi
}

extract_archives() {
  local archive_root="$RESTORE_TMP/archives"
  mkdir -p "$archive_root"
  local count=0
  while IFS= read -r archive; do
    count=$((count + 1))
    local rel="${archive#$ROOT_DIR/}"
    local safe_name
    safe_name="$(echo "$rel" | tr '/ ' '__')"
    local out_dir="$archive_root/$safe_name"
    mkdir -p "$out_dir"
    case "$archive" in
      *.tgz|*.tar.gz)
        log "extracting $rel"
        tar -xzf "$archive" -C "$out_dir" || log "failed to extract $rel"
        ;;
      *.zip)
        log "extracting $rel"
        unzip -q "$archive" -d "$out_dir" || log "failed to extract $rel"
        ;;
    esac
  done < <(find "$ROOT_DIR" -type f \( -name '*.tgz' -o -name '*.tar.gz' -o -name '*.zip' \) -print)

  if [[ "$count" -eq 0 ]]; then
    log "no .tgz/.tar.gz/.zip archives found in repo"
  fi
}

extract_rails_from_installers() {
  local scripts_root="$ROOT_DIR/RAILS"
  local out_root="$ROOT_DIR/railsy"
  mkdir -p "$out_root"

  ruby - "$scripts_root" "$out_root" <<'RUBY'
require 'fileutils'
scripts_root, out_root = ARGV

script_files = Dir.glob(File.join(scripts_root, '**', '*.{sh,zsh}')).sort

script_files.each do |script|
  rel = script.sub(%r{^#{Regexp.escape(scripts_root)}/?}, '')
  scope = rel.sub(/\.(sh|zsh)\z/, '')
  lines = File.readlines(script, chomp: false)
  i = 0

  while i < lines.length
    line = lines[i]
    m = line.match(/^\s*cat\s*(>>?)\s*(["']?)([^"'\s]+)\2\s*<<\s*['"]?([A-Za-z0-9_]+)['"]?\s*$/)
    unless m
      i += 1
      next
    end

    mode = m[1]
    target = m[3]
    terminator = m[4]

    i += 1
    body = +""
    while i < lines.length && lines[i].strip != terminator
      body << lines[i]
      i += 1
    end

    target = target.sub(%r{^\./}, '')
    target = target.sub(%r{^\$\{?[A-Z_][A-Z0-9_]*\}?/}, '')
    next if target.empty? || target.start_with?('$')

    out_file = File.join(out_root, 'restored_apps', scope, target)
    FileUtils.mkdir_p(File.dirname(out_file))

    if mode == '>>' && File.exist?(out_file)
      File.open(out_file, 'a') { |f| f.write(body) }
    else
      File.write(out_file, body)
    end

    i += 1
  end
end
RUBY

  log "restored installer-embedded app files into railsy/restored_apps"
}

main() {
  mkdir -p "$RESTORE_TMP"

  restore_repo_tree "$ROOT_DIR/MASTER" "$ROOT_DIR/pub"
  restore_repo_tree "$ROOT_DIR/archive/recovery" "$ROOT_DIR/tmp/recovery_snapshot"
  restore_repo_tree "$ROOT_DIR/RAILS" "$ROOT_DIR/railsy"

  extract_archives
  extract_rails_from_installers

  log "done"
}

main "$@"
