# Log rotation strategies (vm23)

## Canonical: newsyslog

OpenBSD uses `newsyslog(8)`, not logrotate. The repo mirror is
`OPENBSD/etc/newsyslog.conf` and is installed only by a deliberate
`OPERATOR.sh` run.

| Log | count | size (KB) | when | flags |
|-----|-------|-----------|------|-------|
| `/var/log/pub4/vps-deploy.log` | 12 | 512 | weekly | Z (compress) |
| `/home/dev/vps-deploy.log` | 12 | 512 | weekly | Z |
| base `/var/log/messages` etc. | see conf | | | |

`count` is how many rotated siblings to keep. `size` is a threshold in
kilobytes; `when` is a time rule (`$W0D0` = weekly Sunday). Either size or
time can trigger. `Z` compresses the rotated file with gzip.

Validate before install:

```sh
doas newsyslog -nv -f OPENBSD/etc/newsyslog.conf
```

## Safety net inside vps-deploy

`rotate_deploy_log` renames the aggregate log to `.1` if it exceeds
`VPS_DEPLOY_LOG_MAX_BYTES` (default 10 MB) at deploy start. It does not
replace newsyslog; it only protects `/var` if newsyslog has not run.

## Per-run logs

Files under `/var/log/pub4/runs/deploy-*.log` have unique names, so
newsyslog rules that match a single path do not apply. Options:

1. **Age prune (recommended)** — weekly job deletes runs older than N days.
2. **Directory size cap** — delete oldest until under a byte budget.
3. **newsyslog with filename pattern** — not supported; newsyslog needs fixed paths.

Prefer (1): keep the last 30 days of runs (roughly one deploy/day → 30 files).

## SSH connection log (operator workstation)

`~/.pub4/ssh-connections.log` is written by `MASTER/bin/operator` on each
remote action. Rotate locally (macOS/Linux) with a weekly launchd/cron or:

```sh
# keep ~5 MB
[[ $(stat -f%z ~/.pub4/ssh-connections.log 2>/dev/null || echo 0) -gt 5000000 ]] \
  && mv ~/.pub4/ssh-connections.log{,.1}
```

OpenSSH `-E` also appends protocol diagnostics to the same file when
`LogLevel` is INFO or higher (`PUB4_SSH_LOG_LEVEL`).

## What not to do

- Do not install a partial `newsyslog.conf` (wiped base rules in 2026-08 and
  filled `/var`).
- Do not send deploy logs to a remote syslog until `/var` headroom and
  privacy of receipt lines are reviewed.
