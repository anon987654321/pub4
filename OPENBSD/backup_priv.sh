#!/usr/bin/env zsh
# Backs up ~/priv/ to the OpenBSD Amsterdam backup account.
# Interactive:  sh OPENBSD/backup_priv.sh
# Unattended:   run from /etc/daily.local; needs $PASSFILE (see below).
#
# Nothing had ever been backed up. Four separate faults, each of which alone was
# enough, and the only symptom was two lines in /var/log/daily.out that nobody
# read:
#
#   1. Port. SSH_ACCESS.md has said `wingman1.openbsd.amsterdam 31415` since it
#      was written; this script and ~/.ssh/config both used the default 22, where
#      the host does not listen. It pings from 1ms away and refuses the port.
#   2. The script passed the full `s4vm23@wingman1.openbsd.amsterdam`, which does
#      not match the `Host wingman1` stanza in ~/.ssh/config — so the user, key,
#      port and host-key policy in that stanza were all bypassed.
#   3. The destination directory did not exist. `backup/` was never created, and
#      the account's home is empty: `total 0`.
#   4. openssl prompts for the passphrase on a terminal. Under cron there is no
#      terminal, so daily.local produced "Must be connected to a terminal" and
#      "bad password read", every night, and carried on to report success for the
#      rest of the file.
#
# 1-3 are fixed here. 4 cannot be fixed by this script alone and must not be
# faked: a passphrase stored on vm23 next to the data it encrypts dies with the
# machine, which makes the off-host copy undecryptable exactly when it is needed.
# So the passphrase comes from a file the operator puts there, and without one
# this exits non-zero and says so rather than hanging on a prompt that nothing
# will ever answer.

set -euo pipefail

typeset backup_host="wingman1"          # the ~/.ssh/config stanza, not the FQDN
typeset remote_dir="backup"
typeset stamp=$(date +%Y%m%d_%H%M%S)
typeset passfile="${PRIV_BACKUP_PASSFILE:-$HOME/.config/pub4/priv-backup.pass}"

[[ -d ~/priv ]] || { print -ru2 -- "backup_priv: ~/priv does not exist"; exit 1 }

# How the passphrase reaches openssl. A terminal means a human is here and can
# type it; otherwise it must already be on disk, readable only by this user.
typeset -a pass_arg
if [[ -r $passfile ]]; then
  typeset perms=$(stat -f %Lp "$passfile")
  [[ $perms == 600 ]] || { print -ru2 -- "backup_priv: $passfile is mode $perms, must be 600"; exit 1 }
  pass_arg=(-pass "file:$passfile")
elif [[ -t 0 ]]; then
  pass_arg=()
else
  print -ru2 -- "backup_priv: no terminal and no passphrase file at $passfile — nothing backed up."
  print -ru2 -- "backup_priv: create it with a passphrase you also keep OFF this machine:"
  print -ru2 -- "backup_priv:   mkdir -p ~/.config/pub4 && (umask 077; printf '%s' 'YOUR PASSPHRASE' > $passfile)"
  print -ru2 -- "backup_priv: a passphrase stored only here dies with the box, and the backup with it."
  exit 1
fi

# Reachability before work. Encrypting first and discovering the destination is
# gone afterwards is how this failed quietly for months.
if ! ssh -o ConnectTimeout=15 -o BatchMode=yes "$backup_host" true 2>/dev/null; then
  print -ru2 -- "backup_priv: cannot reach $backup_host — check the Port line in ~/.ssh/config"
  print -ru2 -- "backup_priv: expected wingman1.openbsd.amsterdam:31415 (OPENBSD/SSH_ACCESS.md)"
  exit 1
fi
ssh -o BatchMode=yes "$backup_host" "mkdir -p $remote_dir"

# The archive stages in a 0700 directory under $HOME, never /tmp. A name like
# /tmp/priv_<timestamp>.tar.enc is predictable to the second, sits in a
# world-writable directory and holds the whole of ~/priv. Encrypted, but an
# attacker who pre-creates the path as a symlink decides where it lands, and one
# who merely reads it gets the ciphertext to attack offline at leisure. The
# private directory plus mktemp closes both.
typeset stage_dir="${HOME}/.cache/pub4-backup"
mkdir -p "$stage_dir"
chmod 700 "$stage_dir"
typeset enc_file
enc_file=$(mktemp "${stage_dir}/priv_${stamp}.XXXXXXXXXX.tar.enc") || exit 1
chmod 600 "$enc_file"
trap 'rm -f "$enc_file"' EXIT INT TERM

# -pbkdf2 uses PBKDF2 key derivation — required on LibreSSL 3.x.
print -r -- "backup_priv: encrypting ~/priv"
tar -czf - -C ~ priv | openssl enc -aes-256-cbc -pbkdf2 "${pass_arg[@]}" -out "$enc_file"

print -r -- "backup_priv: uploading to ${backup_host}:${remote_dir}/"
openrsync -ae ssh "$enc_file" "${backup_host}:${remote_dir}/"

# stat, not wc: `wc -c` pads its output on BSD and is on this repo's banned list
# along with the rest of the GNU text tools.
typeset name=$(basename "$enc_file")
typeset remote_size local_size
remote_size=$(ssh -o BatchMode=yes "$backup_host" "stat -f %z $remote_dir/$name")
local_size=$(stat -f %z "$enc_file")
[[ $remote_size == "$local_size" ]] || {
  print -ru2 -- "backup_priv: size mismatch, local $local_size remote $remote_size"
  exit 1
}

# Keep the newest 14. The account is 10G and ~/priv is 10K, so this is about
# being able to find the right one, not about space. A POSIX sh counter rather
# than `tail -n +15 | xargs -r`: OpenBSD's xargs has no -r, and tail is banned in
# committed scripts here because the GNU idioms do not survive the BSD versions.
ssh -o BatchMode=yes "$backup_host" "
  i=0
  for f in \$(ls -t $remote_dir/priv_*.tar.enc 2>/dev/null); do
    i=\$((i+1))
    [ \$i -gt 14 ] && rm -f \"\$f\"
  done
  exit 0
" || true

print -r -- "backup_priv: ok — $name on $backup_host (${local_size} bytes)"
print -r -- "backup_priv: decrypt with openssl enc -d -aes-256-cbc -pbkdf2 -in $name | tar -xzf -"
