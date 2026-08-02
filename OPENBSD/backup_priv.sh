#!/usr/bin/env zsh
# Backs up ~/priv/ to OpenBSD Amsterdam wingman1 backup server.
# Run on VPS as dev@46.23.89.226.
# Backup host: s4vm23@wingman1.openbsd.amsterdam (same SSH key, auto-provisioned)

set -euo pipefail

typeset backup_host="s4vm23@wingman1.openbsd.amsterdam"
typeset stamp=$(date +%Y%m%d_%H%M%S)

[[ -d ~/priv ]] || { print "~/priv does not exist"; exit 1 }

# The archive used to be written to /tmp/priv_<timestamp>.tar.enc: a
# second-granularity predictable name in a world-writable directory, holding the
# whole of ~/priv. Encrypted, but an attacker who pre-creates the path as a symlink
# decides where it lands, and one who merely reads it gets the ciphertext to attack
# offline at leisure. A 0700 directory under $HOME plus mktemp removes both.
typeset stage_dir="${HOME}/.cache/pub4-backup"
mkdir -p "$stage_dir"
chmod 700 "$stage_dir"
typeset enc_file
enc_file=$(mktemp "${stage_dir}/priv_${stamp}.XXXXXXXXXX.tar.enc") || exit 1
chmod 600 "$enc_file"
trap 'rm -f "$enc_file"' EXIT INT TERM

# Create encrypted archive using LibreSSL (OpenBSD openssl).
# -pbkdf2 uses PBKDF2 key derivation — required on LibreSSL 3.x.
# Passphrase entered interactively; never passed as argument.
print "Encrypting ~/priv/ …"
tar -czf - -C ~ priv | openssl enc -aes-256-cbc -pbkdf2 -out "$enc_file"

print "Uploading to $backup_host …"
openrsync -ae ssh "$enc_file" "${backup_host}:backup/"

# Verify upload
typeset remote_size
remote_size=$(ssh "$backup_host" "wc -c < backup/$(basename $enc_file)")
typeset local_size
local_size=$(wc -c < "$enc_file")
[[ $remote_size -eq $local_size ]] || { print "Size mismatch — verify manually"; exit 1 }

rm -f "$enc_file"
print "Done. $(basename $enc_file) on wingman1 (${local_size} bytes)."
print "Decrypt: openssl enc -d -aes-256-cbc -pbkdf2 -in priv_DATE.tar.enc | tar -xzf -"
