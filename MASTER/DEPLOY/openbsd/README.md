# OpenBSD Deploy

Full VPS stack deploy for OpenBSD 7.8 at 185.52.176.18.

## Run

```zsh
cd ~/pub4/MASTER/DEPLOY/openbsd
tmux new-session -d -s deploy "doas zsh openbsd.sh 2>&1 | tee /tmp/deploy.log"
tmux attach -t deploy
```

Resume after interruption: `doas zsh openbsd.sh --resume`

## What it deploys

**Stage 1** (DNS + TLS + packages):
- DNS validation for brgen.no, ai.brgen.no
- acme-client TLS certificates
- pkg_add: ruby, postgresql, redis, node

**Stage 2** (services):
- pf firewall rules (ports 22, 25, 80, 443, 3000, 4430, 8080–8086)
- relayd TLS termination (443 → 10002, 4430 → 10002)
- httpd static file server
- smtpd mail server
- nsd authoritative DNS
- masterweb rc.d service (127.0.0.1:10002)
- Rails apps under /home/dev/rails/

## Checks

After deploy:
```zsh
doas rcctl check masterweb
doas pfctl -s rules
curl -sk https://ai.brgen.no:4430/chat/metrics
```
