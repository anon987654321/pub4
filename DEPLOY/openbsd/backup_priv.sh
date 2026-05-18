#!/usr/bin/env zsh
# Backs up ~/priv/ to OpenBSD Amsterdam wingman1 backup server.
# Run on VPS as dev@46.23.89.226.
# Backup host: s4vm23@wingman1.openbsd.amsterdam (same SSH key, auto-provisioned)

set -euo pipefail

typeset backup_host="s4vm23@wingman1.openbsd.amsterdam"
typeset stamp=$(date +%Y%m%d_%H%M%S)
typeset enc_file="/tmp/priv_${stamp}.tar.enc"

[[ -d ~/priv ]] || { print "~/priv does not exist"; exit 1 }

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
print "Done. priv_${stamp}.tar.enc on wingman1 (${local_size} bytes)."
print "Decrypt: openssl enc -d -aes-256-cbc -pbkdf2 -in priv_DATE.tar.enc | tar -xzf -"
