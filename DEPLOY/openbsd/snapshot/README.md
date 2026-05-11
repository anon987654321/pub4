# snapshot — live VPS state

Mirror of OpenBSD `dev@brgen.no`: `/etc/*`, `/var/nsd/etc/*`, `/home/dev/.zshrc`. Sibling to `files/` (templates we deploy from). Diff the two to see drift.

Secrets are redacted to `__REDACTED__`. Refresh:

    doas ruby ~/pub4/DEPLOY/openbsd/snapshot/sync.rb

Sources tracked: `rc.d/{master,brgen,brgen_tv,brgen_rails,amber,amber_rails,baibl,blognet,blognet_rails,bsdports,bsdports_rails,hjerterom,hjerterom_rails}`, `relayd.conf`, `httpd.conf`, `pf.conf`, `acme-client.conf`, `nsd.conf`, `login.conf`, `rc.conf.local`, `.zshrc`.

Use cases: cross-host diffing, regression hunting, agent context. Never deploy from here — drift between snapshot and live is expected.
