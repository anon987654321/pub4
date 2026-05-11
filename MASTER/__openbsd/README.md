# __openbsd — live system snapshot

Mirror of OpenBSD VPS `/etc/*`, `/var/nsd/etc/*`, `/home/dev/.zshrc` as deployed on `dev@brgen.no`. Snapshot, not a template: `DEPLOY/openbsd/` is what actually provisions.

Secrets are redacted to `__REDACTED__`. Pull a fresh snapshot:

    doas ruby ~/pub4/MASTER/__openbsd/sync.rb

Sources tracked: `rc.d/{master,brgen,brgen_tv,brgen_rails,amber,amber_rails,baibl,blognet,blognet_rails,bsdports,bsdports_rails,hjerterom,hjerterom_rails}`, `relayd.conf`, `httpd.conf`, `pf.conf`, `acme-client.conf`, `nsd.conf`, `login.conf`, `rc.conf.local`, `.zshrc`.

Use cases: cross-host diffing, regression hunting, agent context. Never deploy from here — drift between snapshot and live is expected.
