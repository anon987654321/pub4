# DEPLOY

Deploy scripts for all pub4 services on OpenBSD 7.8.

## Layout

```
DEPLOY/
  openbsd/    Full VPS stack (pf, relayd, httpd, smtpd, nsd, masterweb)
  rails/      Rails app deploy scripts per project
```

## OpenBSD

Two-stage deploy — run from tmux:

```zsh
tmux new-session -d -s deploy "doas zsh DEPLOY/openbsd/openbsd.sh 2>&1 | tee /tmp/deploy.log"
```

Stage 1: DNS checks, TLS certs (acme-client), pkg_add.
Stage 2: app installs, relayd config, rc.d services.

Resume interrupted run: `doas zsh openbsd.sh --resume`

## Rails

Each subdirectory contains a deploy script for one app:

```
rails/
  amber/       amber.sh
  baibl/       baibl.sh
  blognet/     blognet.sh
  brgen/       brgen*.sh
  bsdports/    bsdports.sh
  hjerterom/   hjerterom.sh
  privcam/     privcam.sh
  __shared/    Common utilities and feature modules
```
