# POSIX sh — sourced by zsh and sh callers alike.
#
# The one definition of the pub4 CI mutex path, and the safe way to create it.
#
# It used to live at /var/tmp/pub4-ci.lock, created by
#   doas sh -c "touch /var/tmp/pub4-ci.lock; chmod 666 /var/tmp/pub4-ci.lock"
# — a fixed, predictable path in a world-writable directory, chmod'ed by root
# with no -h/-P (OPENBSD/data/debt.yml:
# secrets_in_process_argv_and_world_readable_home). Any local account could
# pre-plant a symlink at that name and redirect the root chmod onto a file of its
# choosing. `PUB4_CI_LOCK` being env-overridable made it worse: the caller chose
# the path root then chmod'ed.
#
# The fix is the directory, not the flags. /var/db/pub4 is root-owned and 0755, so
# an unprivileged account cannot create anything inside it — there is no symlink to
# follow. That also lets the mode drop from 666 to 644.
#
# Three scripts held their own copy of the path (vps_ci.sh, vps_master_scan.sh,
# vps_weekly_integrity.sh); this is the single source. The lock is opened with
# lockf(1) by dev, so it stays dev-owned; only the directory is root's.

PUB4_CI_LOCK_DIR=/var/db/pub4
PUB4_CI_LOCK_NAME=ci.lock
PUB4_CI_LOCK_OWNER=${PUB4_CI_LOCK_OWNER:-dev}

# An override is honoured only inside the root-owned directory. Outside it, the
# override is the vulnerability rather than a convenience.
pub4_ci_lock_path() {
  case "${PUB4_CI_LOCK:-}" in
    "${PUB4_CI_LOCK_DIR}"/*) printf '%s\n' "$PUB4_CI_LOCK" ;;
    "") printf '%s/%s\n' "$PUB4_CI_LOCK_DIR" "$PUB4_CI_LOCK_NAME" ;;
    *)
      printf 'ci_lock: ignoring PUB4_CI_LOCK=%s outside %s\n' "$PUB4_CI_LOCK" "$PUB4_CI_LOCK_DIR" >&2
      printf '%s/%s\n' "$PUB4_CI_LOCK_DIR" "$PUB4_CI_LOCK_NAME"
      ;;
  esac
}

# Creates the directory root-owned, then the lock file dev-owned. The lock file is
# never removed here: a holder may have it open, and unlinking it would let a
# second holder open a fresh inode and run concurrently — the one thing a mutex
# exists to prevent.
#
# The lock itself is taken by OPENBSD/bin/with-ci-lock and Pub4::CiGuard, both
# flock(2). This comment used to say lockf(1), and vps_master_scan.sh called it:
# OpenBSD has no lockf(1) and no flock(1) either, so that line was `command not
# found` on every run and the documented way to scan vm23 never took a lock or
# ran a scan.
#
# Note what this function does and does not do. It ENSURES the file — creates it
# with the right owner and mode. It does not lock anything. vps_ci.sh calls it
# and prints "sync + mutex + load gate"; the mutex in that sentence is the one
# bin/ci takes through CiGuard, on this same path since 2026-08-14. Before that
# CiGuard locked /var/tmp/pub4-ci.lock instead, so the file created here was
# never locked by anyone and the file that was locked was the world-writable one
# this helper exists to replace.
pub4_ensure_ci_lock() {
  lock=$(pub4_ci_lock_path)
  doas sh -c "
    mkdir -p '${PUB4_CI_LOCK_DIR}'
    chown root:wheel '${PUB4_CI_LOCK_DIR}'
    chmod 755 '${PUB4_CI_LOCK_DIR}'
    rm -f '${lock}.holder' 2>/dev/null || true
    [ -e '${lock}' ] || : > '${lock}'
    chown '${PUB4_CI_LOCK_OWNER}' '${lock}'
    chmod 644 '${lock}'
  "
  printf '%s\n' "$lock"
}
