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

Also waiting on this: bsdports now imports its catalogue, but only from the
mirror's published package index, which carries names and versions and nothing
else. The full metadata — category, COMMENT, maintainer, dependencies, i.e. the
three questions `ports/index` says the page answers — comes from `ports.tar.gz`,
56 MB compressed and several hundred MB extracted. `Ports::Openbsd::PortsTarball`
implements that path and declines while free disk is under 2 GB, which on this
box it is (see item 3). Enable with `BSDPORTS_PORTS_TARBALL=1` once resized.

## 3. `/home` is at 95% and the cause is in git, not on disk

962 MB free of 17 G. `/home/dev/pub4` is 7.7 G of the 8.3 G under `/home/dev`,
and `.git` alone is 3.3 G. The ten largest objects in history are 80–87 MB WAV
renders under `DEPLOY/dilla/renders/beats/` — a path that no longer exists in
the tree and never will again.

Every `git pull` deploy carries that history. More RAM does not touch it, and
today added more audio (`42bb88375`). If the history rewrite in item 1 happens,
strip these in the same pass: one disruptive operation instead of two.

## 4. The MASTER-over-MASTER gate run is unfinished

Opened 2026-08-09. This is the one entry here that is not a production blocker —
it is parked work with a defined end, and it should be deleted the moment the
chain completes rather than allowed to become a second debt register.

`bin/gate`'s chain is `/scan → /fix → /scan → /critique → /review`, over MASTER
and then over RAILS and OPENBSD. **Only the first `/scan .` on MASTER ran, and it
was interrupted.** `/fix`, the second `/scan`, `/critique` and `/review` have not
run against either tree, so nothing below the scanner layer has been measured.

What the run established before it stopped:

- `bundle exec rake test` is green — 1010 runs, 0 failures, 0 errors, 8 skips.
  It was red at the start of the session; see `22e012e52`.
- `rake spec`, `test:subsystems`, `security_sweep`, `test:core` and
  `lint:data_singularity` all pass. `lint:frozen` and `lint:autoload` pass.
  `lint:principle_trace` reports 101/101 untraced, at its ceiling.
- `rake constitution` reports 3876 findings, 129 actionable against a budget of
  1500. `rake selftest` reports 0.
- The two files the interrupted scan modified — `MASTER/test/test_rule_fixtures.rb`
  and `MASTER/tools/runs.rb` — are its own TRAILING_COMMAS autofix. Both are
  correct and are kept, but they are 2 of roughly 232 such findings, so the pass
  is arbitrary rather than complete.

### 4a. `lint:spine` is red on a clean tree and has no dead code left to pay it

`lib/` is 47,577 lines against a 47,458 ceiling (+119). 93 of those lines predate
this session, spread over seven scan/fix tooling commits since the 2026-08-03
ratchet; 26 are the TTS lock fix in `22e012e52`.

The previous three breaches were each closed by deleting orphaned code. **That
seam is empty.** A sweep of every constant and constant-path declared in each
`lib/**/*.rb` against `lib core bin test spec web tools data script completions
docs runtime`, the Rakefile, the Gemfile and the gemspec — the method
`MASTER/DEBT.md` prescribes after the first, filename-based sweep produced a
mostly-wrong list — returns **zero unreferenced files**.

So this is the decision `data/spine.yml` said would eventually be owed: "if it is
raised again without `lib/` ever falling back, the honest conclusion is that 'the
spine never grows' is not the invariant anyone is holding, and the number should
be replaced by one that is." The raise allowance is 0 of 2 used, so a raise is
mechanically permitted — which is exactly why it needs a sponsor rather than an
edit.

The measurement that bears on it, and on the tension three passes have now
deferred: of `lib/`'s 47,577 lines, **38,077 are code, 2,577 are comment and
6,923 are blank**. `lint:spine` counts all three. `[DENSITY]` was deliberately
changed on 2026-07-28 to count code lines only, so that a rationale paragraph
above a tricky line is not penalised — this repo's stated convention. The two
rules therefore still pull opposite ways on the same edit, and 20% of what the
ceiling measures is whitespace and prose the codebase asks for.

Three options, none taken: raise the ceiling with a reason; re-express it in code
lines and re-ratchet; or absorb into `core/`, which its own standard (a handler
per verb, a rule per constraint) does not accommodate for any of the 119 lines.

### 4b. `MASTER_AUTOFIX=0` does not stop `/scan` writing to the tree

`bin/gate`'s `SAFE_ENV` sets `MASTER_AUTOFIX=0`, and the comment above `COMMANDS`
reads "Full chain mutates the tree via /fix" — i.e. the gate believes `/scan` is
read-only under that env. It is not. `MechanicalAutofix.enabled?` reads
`MASTER_SCAN_AUTOFIX`, defaulting to `"1"`, and consults `MASTER_AUTOFIX` nowhere
(`lib/review/scan/mechanical_autofix.rb:15`).

Scan-only mode is safe by accident: it passes `--no-autofix` explicitly on the
command line. The full-fix chain's *first* `/scan .` writes files before `/fix`
is reached, and the env var set to prevent that is inert — the dominant defect
class in this repo, a declaration with no reader.

Decide whether `MASTER_AUTOFIX=0` should gate scan autofix too, or whether
`SAFE_ENV` should set `MASTER_SCAN_AUTOFIX=0` and the comment should stop
claiming what it does not enforce.

## Not blocking, but unverified

Both entries here were closed on 2026-08-03 by booting the four surfaces locally
(`RAILS/bin/triangle`, new — there had been no supported way to do it, which is
why the live gates ran nowhere). `constitutional_scan` re-measured all four
targets, every one under its ceiling. The browser suite ran on this Mac rather
than the deploy host; vm23 still needs the resize for that to be routine.

What booting them proved, and the reason `GATE_REQUIRE_LIVE=1` now exists: with
the ports closed, eight visual and user-flow gates reported PASSED having
measured nothing live. With the apps up, `page_simulation` failed immediately.
Set the flag on any run that means to measure the live half.

- `page_simulation` covered 43 of brgen's 100 full-page views. The five verticals
  became engines and `PageInventory` never followed them, so 57 views left the
  simulation with nothing reporting it. Page URLs now come from a generated route
  manifest (`RAILS/tools/generate_route_manifest.rb`) rather than a filename
  convention. The same blind spot had also gone unnoticed in
  `chrome_i18n_lint.rb` (aria_label read 89 against a baseline of 169 — the lint
  had gone blind to the engine views, not improved) and in six RAILS contract
  tests. Worth grepping for `app/views` and `app/controllers` globs that stop at
  one level before assuming any other count is real.
