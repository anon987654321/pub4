# TODO — criticals

Ordinary debt lives in `MASTER/DEBT.md` and `OPENBSD/data/debt.yml`. This file
carries only what blocks a healthy production claim. Delete an entry when it is
closed; do not let it rot into a debt register.

Verified 2026-08-02 21:30 CEST against vm23 and `origin/main`.

## 1. Credentials for six apps are decryptable from public git history

`github.com/anon987654321/pub4` is public and its history holds **seven
`master.key` blobs** beside the `credentials.yml.enc` they decrypt:

    MASTER/web/config/master.key                 2 versions
    DEPLOY/rails/brgen/config/master.key         + credentials.yml.enc
    DEPLOY/rails/amber/config/master.key         + credentials.yml.enc
    DEPLOY/rails/bsdports/config/master.key      + credentials.yml.enc
    DEPLOY/rails/baibl/config/master.key         + credentials.yml.enc
    DEPLOY/rails/blognet/config/master.key       + credentials.yml.enc
    DEPLOY/rails/hjerterom/config/master.key     + credentials.yml.enc

Verified without decrypting: `DEPLOY/rails/brgen/config/master.key` is 32 hex
characters — a real key — and its 548-byte `credentials.yml.enc` is in the same
history. Anyone who has cloned the repo holds both.

`139c907e6` untracked only `MASTER/web/config/master.key` and scoped the blast
radius to that one file, correctly for that file. The six deploy-tree pairs were
not in scope and are still exposed. Untracking removes nothing from history.

**Rotate before purging.** Rotation closes the exposure; the purge only stops
future clones. brgen, amber and bsdports read `SECRET_KEY_BASE` from
`/etc/<app>.env`, so rotating is a value change plus `rcctl restart`, not a code
change. baibl, blognet and hjerterom are not live services — confirm that before
deciding whether they need anything beyond the purge.

Purge is a force-push to a public repo. It invalidates every clone including the
VPS checkout that `git pull` deploys from, so it needs a window, not a moment.

## 2. vm23 has no memory headroom

1 GB physical, 1 vCPU (`hw.physmem=1056952320`, `hw.ncpuonline=1`). Running
MASTER and the three Rails apps together drove swap to 966 MB of 1264 MB, load
to 3.2, and amber's home action to a 3–36 s spread on an identical response.
CPU sat 83% idle throughout: page faults, not compute.

amber and bsdports are **stopped** as of 2026-08-02 20:45 CEST to hold the box
up. Stopped, not disabled — the reboot that comes with the resize restarts them.
Both domains currently answer an empty reply rather than a 503.

Resize is the fix and is already the operator's plan. 2 GB is the floor: brgen
alone reached 284 MB RSS with two apps paused, MASTER 194 MB. 4 GB is what
leaves room for the browser gates to run on the box where they belong.

Watch after the resize: brgen grew 170 MB → 284 MB RSS in about an hour under
contention. Warming cache or leak is not yet distinguishable.

## 3. `/home` is at 95% and the cause is in git, not on disk

962 MB free of 17 G. `/home/dev/pub4` is 7.7 G of the 8.3 G under `/home/dev`,
and `.git` alone is 3.3 G. The ten largest objects in history are 80–87 MB WAV
renders under `DEPLOY/dilla/renders/beats/` — a path that no longer exists in
the tree and never will again.

Every `git pull` deploy carries that history. More RAM does not touch it, and
today added more audio (`42bb88375`). If the history rewrite in item 1 happens,
strip these in the same pass: one disruptive operation instead of two.

## Not blocking, but unverified

- Browser-backed gates (`geometry`, `reflow`, `keyboard_flow`, `mobile_flow`,
  `journey_invariant`, `cross_app`, `layout_snapshot`) have not run this cycle.
  They belong on the deploy host and need the resize first.
- `constitutional_scan` re-measure was killed mid-run after brgen, amber and
  bsdports scanned; no counts were printed. Ceilings were re-baselined in
  `837679299` and have not been confirmed against the current tree.
