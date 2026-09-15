# pub4 backlog

The single backlog for the repo. Authority: `MASTER/data/soul.yml` >
`MASTER/data/rules.yml` > root `CLAUDE.md` > the per-tree contract. Feature
truth is `RAILS/apps.yml`; aspiration is `RAILS/apps.horizon.yml`; rationale sits
in the comment beside the code and in the Refused lists in `MASTER/AGENTS.md` and `OPENBSD/CLAUDE.md`. A record is deleted when it
closes, and `git log` keeps the history.

**A finding is a hypothesis.** When 645 entries here were re-measured on
2026-09-12, 46% were already built or false, and a third of the layout
citations named the wrong file, line or figure. The guards that keep paying:

- The tree rarely spells a mechanism the way an entry does. `QueryBudgetTest`,
  `Bullet.raise` and `strict_loading_by_default` are the RAILS performance work
  and none says "performance". Find the reader before calling anything open.
- An entry asking for a *gate* over something the tree already does is a
  detector, not a feature, and much smaller than its wording.
- A census has more than one end: gem callers include `Gemfile.lock`
  dependents, every bus topic reaches the `"*"` subscriber, and all four trees
  count. `MASTER/AGENTS.md` carries the examples.
- Anything that moves a rendered value is the operator's, however it is filed.

**Search this file for a subject before adding an entry, and fold rather than
append.** Subjects named in four or more sections:

```zsh
ruby -e 'ls=File.readlines("TODO.md"); s=[]; ls.each_with_index{|l,i| s<<[i,l.chomp.sub("## ","")] if l.start_with?("## ")}; o=Array.new(ls.size); s.each_with_index{|(i,t),n| (i...(s[n+1]?s[n+1][0]:ls.size)).each{|k| o[k]=t}}; h=Hash.new{|x,k| x[k]=[]}; ls.each_with_index{|l,i| l.scan(/`([A-Za-z0-9_\/.:-]{6,})`/).flatten.each{|t| h[t]<<o[i] if t=~%r{[/._]}}}; h.map{|t,v| [t,v.compact.uniq]}.select{|_,v| v.size>=4}.sort_by{|_,v| -v.size}.each{|t,v| puts "#{v.size}  #{t}"}'
```

Forward work is the last section of this file.

---

## MASTER

### Operator decisions

- **Whether the one scheme keeps an accent.** `vertical_accents` gives each
  vertical its own ink, and most of `magic_hex` and `contrast_below_aaa` is
  `--danger`. Decide whether one accent survives for interactive affordance; a
  link without colour needs an underline. Both ratchets count RAILS.
- **tv and maps hover fills fail AA under the vertical ink** (3.34 and 4.31
  against 4.5) and reach no pixel until their hover is wired. Pick the colours
  before wiring them; `_vertical_shell.scss` records the measurement.
- **dilla is fenced, because it renders audio.** Whether
  `STUDIO/dilla/data/dilla_principles.yml` gets a reader (it has none, and
  wiring it changes what dilla generates) or goes; narrowing dilla's
  `SILENT_RESCUE` sites.

### Needs vm23

- **One `MASTER/Gemfile.lock` for the Mac and the box, in a watched deploy.**
  `MASTER/Gemfile` guards `rb-kqueue` with a runtime `if RUBY_PLATFORM`, so the
  lock is host-dependent; `install_if -> { RUBY_PLATFORM =~ /bsd|dragonfly/i }`
  fixes it. The same regenerated lock should fill the 25 empty `CHECKSUMS`
  entries and drop `flay` (`MASTER/Gemfile:30`, no caller, no lock dependents).
  It cannot land alone: `BUNDLE_FROZEN=true` fails on a Gemfile the lock does
  not match, and any commit touching the lock conflicts with the box's
  hand-repaired copy, CHECKSUMS deleted, that keeps TTS alive. Apply during a
  deploy and verify with `rcctl restart master` and `vps state --remote`
  reading `tts_socket=true`.
- **After the next deploy, confirm `.master/tts-worker-*.log` stay
  `master`-owned.** `cable_bridge.rb`, one path a root `assets:precompile` could
  build a container through, is deleted, and `MasterContainerLoader.ensure!`
  refuses under an assets task. If the logs turn root again, the writer is
  elsewhere.
- **Deploy hazards.** Never stash the box's locks to fast-forward; a plain
  `git pull --ff-only` succeeds with them dirty. relayd has died mid-deploy with
  every app port open (`curl 000` on all hosts), so run `rcctl check relayd`
  after any deploy that restarts master.
- **What the 2026-09-14 merges carry to the box.** `MASTER/web/Gemfile.lock`
  drops `solid_cable`, so check the box's copy of that lock is clean before
  `git pull`, and MASTER web runs a migration dropping `solid_cable_messages`.
  brgen runs a migration that nulls orphaned `dating_profiles.neighborhood_id`
  and adds the foreign key. `nsd-resign` now reads `NSD_ZONES_DIR` and
  `renew-certs.sh` reads `RENEW_CERTS_ACME_CONF` and `RENEW_CERTS_SSL_DIR`, each
  defaulting to today's path, from the next `OPERATOR.sh` install. dev's
  `/home/dev/.zshrc` still sources the missing `FUN/zshrc.shared`, and
  `OPERATOR.sh` no longer installs over it.

### The face's mood, and TTS on the box — operator-owned

- **The face's `mood` tint has a listener and no producer.** Nothing publishes
  `agent:mood`, so `face.part5.txt`'s tint never fires. Decide: wire a producer
  from `voice/emotion.rb`'s state (the face starts changing colour on its own)
  or delete the listener. The seam is recorded in `MASTER/web/CLAUDE.md`.
- **vm23, after the next deploy:** re-probe the one-shot Edge fallback
  (`synthesize_edge_oneshot`) with a real MP3 write, and `test -S
  .master/tts.sock`; `/health` alone is a capability check.

### Tag legend

- **agent-ignore** — do not chase during narrow patches (constitution scan noise,
  horizon features).
- **operator-priority** — humans should fix before declaring deploy healthy.

## RAILS

### Audit findings — 2026-09-12

- **`constitutional_scan` is over two ceilings, and every finding is a design
  value.** Re-measured 2026-09-13 on the aesthetic profile the budget counts:
  bsdports 5 against 3 (`EIGHT_PX_RHYTHM` ×3, `CHOICE_OVERLOAD`,
  `SIGNAL_NOISE`) and shared 15 against 8 (`EIGHT_PX_RHYTHM` ×6, `MAGIC_COLOR`
  ×3, and one each of `NO_DECORATIVE_FX`, `TOUCH_TARGET_MIN`,
  `CONTRAST_TOKENS`, `RAMS_UNOBTRUSIVE`, `REDUCED_MOTION`,
  `WHITESPACE_RHYTHM`). The operator decides: change the spacing, colour and
  motion values, or record new ceilings with a reason in
  `RAILS/gates/data/constitutional_budget.yml`.

### Instant — what the operator still decides

The "134 ways to feel instant" intake, once `RAILS/INSTANT.md`, closed on
2026-09-13. What was already built and what the tree refuses are both recorded
in `RAILS/shared/WIRING_NOTES.md` under "Speed proposals decided against". What
is left changes how a surface looks, or needs vm23.

- **Motion is a rendered value.** Cross-document view transitions (feed to post,
  the theme crossfade); Turbo's progress bar delay, set to 100 ms in
  `shared/frontend/hotwire.js` against Turbo's 500 ms default; feed skeletons
  shown only past ~200 ms; `:active` states; and `transition_normal`, 300 ms in
  `shared/design_tokens.yml`, against a proposed 200 ms ceiling.
- **Two failures a reader cannot see.** `action_controller.js#_rollback` reverts
  a rejected like or vote with no message, and nothing shows when the cable
  socket is down. Each needs a visible element and its copy.
- **The feed card paints no blurhash.** `lazy_image_tag` carries the
  placeholder; `posts/_post` renders `responsive_image_tag`, which does not.
- **Needs vm23.** A p95 server-time ceiling per route means something only when
  measured on the box, warm and cold; and whether relayd serves HTTP/2 or
  compresses anything is a man-page-then-measure question there.
- **Seller payouts need money.** One Stripe Connect account per seller and a
  platform balance; `Marketplace::Payout` fails closed and stays pending with a
  reason until then.

### Deploy blockers

What stops a RAILS deploy from being one command. A blocker leaves when its
unblock criteria are met. Operator-side debt is the OPENBSD section.

**1. City vanity TLS** — operator; registrar action. Blocks the first install
of a new city apex, not deploys of the live apps. `OPERATOR.sh` stage 1 issues a
certificate for every apex in `ALL_DOMAINS`, and relayd will not load a keypair
whose certificate is absent — a `relayd.conf` naming one downs every site on the
box. Unblocked when every apex resolves and serves its own certificate and
`relayd -n` passes against the repo copy on the box before install.
`domain_alignment` checks the four live apexes.

**2. relayd restart after route changes** — operator. Built; open until a real
deploy exercises it on vm23. On 2026-08-10 a restart killed relayd's `ca`
process and every site for nine minutes, seconds after the deploy logged
`relayd(ok)`. `relayd_confirm_live` in `RAILS/_service.sh` re-checks 443 for
20 s after the restart and names the shape: 443 refused with the app port
answering is relayd, both refused is the app.

## OPENBSD

### Operator debt — still open

Each item carries a hidden HTML-comment marker on its own line under its heading;
`MASTER/lib/operator/operator_docs.rb:55` counts those markers for the
`MASTER/bin/operator status` debt line, so keep exactly one per open item.

#### `libvips_local_build`  — tag: operator-priority

<!-- open-debt -->

vm23 runs a locally built libvips with svgload; `pkg_add -u` swaps in the stock
package, which has none, and amber's garment cut-outs quietly stop regenerating.
`/etc/daily.local:71` detects it. After any `pkg_add -u` touching graphics, run
`make reinstall` in /usr/ports/graphics/libvips and confirm `vips -l` lists four
svgload operators.

#### `off_host_dr`  — tag: operator-priority

<!-- open-debt -->

One purchase, an off-host object store, closes three gaps. `OPENBSD/bin/dr-pull`
keeps seven verified pulls, but on the operator Mac. `STUDIO/dilla/samples/`
(84 MB, 75 MB of it `own/` recordings) is gitignored and on one disk, and dr-pull
cannot help because the crate is already on that disk. `Shared::DatabaseSnapshotJob`
writes `VACUUM INTO` copies beside the database, and `restore_litestream.sh` restores from
an empty litestream directory. litestream is absent by decision (not in ports).

#### `multi_app_ram`  — tag: operator-priority

<!-- open-debt -->

A provider resize of vm23; done when `sysctl hw.physmem` reads at least
2147483648 (1056952320 on 2026-09-11). The standing decision is 1 GB with one
resident worker, brgen_jobs. Reproduce a start by hand only with
`--health-check-timeout 300`, and do not stand a job worker down before
`bin/vps-deploy`, which does it.

#### `home_partition_full_from_git_history`  — tag: operator-priority

<!-- open-debt -->

A coordinated history rewrite: strip the 80–87 MB WAV renders under the old
`DEPLOY/dilla/renders/beats/` and the key purge in one force-push, with a vm23
re-clone in the same hour and every session quiescent. Not pressure: /home was
69 percent on 2026-09-11.

#### `bsdports_org_delegated_to_parking`  — tag: operator-priority

<!-- open-debt -->

At Domeneshop, set bsdports.org's nameservers to ns.hyp.net and ns.brgen.no; the
registration is paid to 2027-08-08. The deadline is the certificate
(`notAfter=Nov 10 2026`), because acme-client's HTTP-01 needs the name to resolve
here. Done when `ruby RAILS/gates/runner.rb dns_zones` passes. `ALLOW_BSDPORTS_DOWN=1`
on the uptime-check crontab line comes off the same day; `bin/deploy-smoke.sh`
names the delegation until then.

### Waiting for the box

Each of these needs vm23: a root run, a man page read there, or a measurement
only the box can take.

- **One `doas zsh OPENBSD/OPERATOR.sh` run closes the drift.** Ask
  `SSH_HOST=dev@brgen.no ruby OPENBSD/config_drift_gate.rb --remote`, never a
  list; the repo is the newer side everywhere. `emergency_cpu.sh` (the only thing
  `resource_guard.sh`'s crisis tier runs), `vps_weekly_integrity.sh`, its root
  crontab line and `/var/log/pub4/` are absent, so the weekly integrity pass has
  never run.
- **relayd restarts five times per `vps-deploy all`.** Each rc.d script and
  `start_all_apps.sh` run `rcctl restart relayd` once an app answers `/up`,
  dropping the one TLS listener; the 2026-08-10 nine-minute outage was that.
  `relayctl table disable|enable` and `relayctl poll` do the kick without touching
  the listener. Read relayd.conf(5) and relayctl(8) on vm23 and bracket one app by
  hand first.
- **The `rails` login.conf class caps datasize at 4096M on a 1 GB box**, and
  `openfiles-cur` inherits 128. Set per-app `datasize-cur` from each app's
  steady-state RSS measured on vm23; a number guessed low kills a healthy app.

## STUDIO

Re-measured 2026-09-11 against the real crate. `samples/` is gitignored, so a
worktree shows an empty crate that is not; dilla is under active edit, so trust
symbol names over line numbers.

### The owner's calls

- **The crate holds `drums`, `dug` and `own`, and no 124 racks.**
  `74d9e4c1b` cleared it on 2026-08-16 on the operator's call; only he can say
  whether he expected the racks back. `samples/dug/` is down to one record, and
  the other 160 sources cannot be re-fetched to the same bytes.
- **Two ways into the crate.** The engine reads `samples/chopped/loops.json`
  through `RadioChop.registered_loops`; `lib/sampling.rb` writes `samples/dug/`
  from public-domain archives; `ruby dilla_live.rb dig` (`lib/livesets.rb`) rips
  YouTube into `samples/chopped/` and warns on every run. Those two are the crate.
- **`ruby STUDIO/dilla/dilla.rb assets` exits 1**: three loops missing, seven files
  changed (re-synthesised one-shots).
  `dilla assets record` blesses whatever is on disk, so it is the operator's.
- **Two staging directories outside the repo.** `~/dilla-crate-incoming` holds two
  source FLACs and their demucs stems from an abandoned 61-track fetch;
  `~/Music/dilla_sines/` is a running installation beside three drifted twins of
  tracked scripts. Keep, move or delete is his, never an agent's.
- **Sound that moves under a pinned seed.** Eight bare `rand` calls and one
  `.sample` in `dilla.rb` escape `render_rng`, which is why a pinned render moves
  about 0.012 dB. Routing each changes what that site renders: one site at a
  time, by ear.
- **The `HARM_VOL` bump stays a pass behind itself**: 2.4 plus 0.05 is the 2.45
  default, and raising the base is a mix value (`harmony.rb`).
- **Chop rows in `TRACK_PRESETS`**, when there are chops again. A slug with no row
  falls through to `:timeless`; the `sheger_*` derivation in `dilla.rb` is
  mechanical and whether it sounds right is his.

### Blocked while `dilla.rb` is under another session's edit

- **Classify dilla's default-off flags** into additive, exclusive fork and
  operational, and delete the dead ones. `lib/ledger.rb` is the instrument (727
  knobs, 286 flags, 206 default-off); the counts in `dilla.rb`'s own comments
  are stale.

### Guards

- The eight `sheger_*` rows are half alive: the preset rows are live and tuned,
  the bed aliases point at a cleared chop. A test pins both halves; delete
  neither.
- The monolith stays. `DILLA_SUPPORT_CEILING` (56, any depth) leaves no room for a
  destination file, so any split starts by folding support code, and 14 support
  files use `__dir__`/`__FILE__`. `dilla parts` indexes the engine.
- Not worth chasing, each measured: merging the three techno renderers (three
  sounds); blanket rescues in STUDIO (optional probes and teardown); preset reach
  in `postpro`/`lora` (selected by name from argv; `vocab_check` owns it); the 37
  stale `sample_worth.json` slugs (pruned on the next chop); the sample rate
  declared under three names (all namespaced; `sampling.rb`'s 11,025 is
  deliberate); the `cohesion.rb` regroups; the three engine probes that skip
  under suite load while passing alone; and the four hand-packed RIFF headers
  (`wavefile` loads only when MASTER's bundle is present, so a writer through it
  still needs the four-line pack as its fallback).

## The layout pass — open

**Seventeen control classes paint a border beside a fill**, from `.deal-cat`
(`_marketplace.scss:48`) to `.pager-link`, which the 2026-08-04 decision traded
away (`WIRING_NOTES.md`). Whether that decision reaches controls is a rendering
call, and the operator's. The pass's doctrine lives in `WIRING_NOTES.md`.

## From the 2026-09-01 audit

- **The browser half of the gates runs nowhere unattended.** vm23 cannot host it
  (Chrome under 1 GB sheds amber and bsdports; the argument sits beside
  `PUB4_DEPLOY_BROWSER_GATES` in `vps-deploy`), so it needs a second host.
  `GATE_STRICT_ERRORS=1` can join the deploy line once someone has read one
  ledger's worth of errored gates.

---

# Forward work

Wishes and measured proposals not yet shipped; each section is dated.

## Found by the backlog pass — opened 2026-09-14

The agents that worked this file on 2026-09-14 and noticed these outside their
slices. Each is a hypothesis with its seam.

### MASTER

- **The face reads event fields where the stream does not put them.**
  `/events/stream` nests each event's fields under `data`, and
  `visual_bridge.js` reads `event.pct`, `event.modules` and `event.spirit_radius`
  from the top level, so they arrive undefined. Fixing it changes what the face
  shows: the operator's.
- **`test_ratchets` is red on rows nobody moved on purpose.** Over the ceiling:
  `rule_audit.silent` 44/40, `growth.rails` 1998/1980 (model tests and a
  migration), and `namespace` 3/2 from `STUDIO/dilla/lib/sine_stream.rb`. Slack
  on `spine.lib_body_ceiling`, `growth.master`, `self_findings`, `data_reach`
  and `sprawl.lone_dirs`. Each row wants its fall recorded or its raise named,
  never absorbed.
- **The CLI's last seams.** Rotate the web token printed at boot on 2026-09-13;
  it sits in two saved terminal transcripts in `~/Downloads` (operator).
  `/status` prints its event rows as `key=value`, short of the dmesg grammar the
  rest of the CLI keeps. The review report prints its posture twice, in the
  `mode0` line and as a section. `CLI::Propose` and `Ground::OperatorPlaybook`
  have no caller outside their tests. `/soul approve` bumps a `Version:` line
  `SOUL.md` does not have.
- **`solid_queue` and `solid_cache` sit in the web Gemfile with nothing loading
  them.** Dropping them is a lockfile change, so it lands with a watched deploy.
- **`Policy::FALLBACK` speaks at `+0%` where `voice.yml` says `-18%`,** a sound
  value and the operator's.
- **A session receipt waits for a reader.** Joining the memory store version,
  worktree HEAD and model id to `Ground::BootReceipt` would let two runs be
  diffed; it is built when `/why` or `bin/doctor` asks.

### RAILS

- **`reveal` is registered and mounted by no app view,** only by the snippet
  library, and the reverse Stimulus contract exempts it with that reason.
  Drag-only reorder (amber outfits, marketplace variants) has no keyboard path
  (WCAG 2.5.7), and a keyboard path means visible controls: the operator's.
- **maplibre loses its DOM on a morph.** Nothing refreshes the maps home today;
  `WIRING_NOTES.md` records why it is unguarded.
- **The playlist set page prints "likes" in English.**
- **42 `needs_id` guest pages get no live probe;** `page_inventory` names them
  now, and giving them record ids needs a booted triangle.

### OPENBSD

- **Stale paths after renames.** `tools/tree.rb --ground-policies` targets
  `*_policy.rb` files that no longer exist in `MASTER/lib/ground/`, and
  `RAILS/shared/app/services/shared/strunk_white_pass.rb` names the pre-rename
  `MASTER/lib/now/stages/prune.rb`. `bin/vps-deploy` still carries comments that
  narrate what the code used to do, and `OPENBSD/solid_queue_proof.rb` says the
  jobs workers are disabled at boot while `brgen_jobs` sits in `pkg_scripts`.
- **`reach.rb` is a third cron-line parser** beside the drift gate's and
  installed-targets'.
- **The bare IP lingers** as `lib/ssh_vm23.sh`'s `SSH_HOST` default and
  `data/operator.yml` `meta.vps`, where the contract names `dev@brgen.no`.
- **`rc.d/*_jobs` scripts carry no login.conf class,** so the job workers run
  under `daemon` without the `rails` limits.
- **`rottrdam.nl` reads unknown with the note "is free",** which the AVAILABLE
  regex should match; `_net.sh`'s remaining functions may have no callers.

## The refinement inventory — opened 2026-09-11, instrument pass 2026-09-14

`ruby MASTER/tools/refinements.rb` scans every tracked file in the four trees
and groups what it finds into batches: one rule, one kind of edit, a known file
list. `--items` prints every finding, `--tree` and `--rule` narrow it. The list
is not written down anywhere, because a written copy of a scan is stale the day
it is made. Run the tool.

The 2026-09-14 pass fixed rules rather than files: `magic_number` 4,679 to
3,108, `NO_PUTS` 941 to 91, `FILE_SPRAWL` 654 to 52, `SMALL_FILES` 280 to 152,
`CONFIG_HIERARCHY` 1,007 to 138, and `TRAILING_COMMAS` 510 to 74, because the
three apps' RuboCop forbids the comma the rule asked for. Re-run before quoting
a count. What is left:

- **`duplicate_code` matches the words copy, duplicate and "same as",** and 0 of
  25 samples were duplicated code. Retiring it edits `data/rules.yml`, which is
  immutable: the operator's.
- **Lint reach that surfaces rendered values.** ScaleLint reading the `font:`
  shorthand and `clamp()` finds 22 off-scale line-heights and 1 tracking against
  a ceiling of 0. `NO_LONG_TRANSITION` on seconds and JS `duration-value`,
  `LOGICAL_PROPERTIES` on every box property and `MEASURE_OPTIMUM` at any width
  surface 27 more and take `self_findings.law` past its ceiling. Both extensions
  wait for the values to be decided.
- **`NO_GOD_CLASS` (29)** wants each class read; it is not mechanical.
- **Sampled five and right:** `DOUBLE_BRACKET` (the eight files are ksh, which
  has `[[ ]]`, and they are rc.d files, so the edit is vm23's), `NO_ASCII_LINE_ART`,
  `SILENT_RESCUE` (one kill on a dead process should name its error),
  `NO_COLUMN_ALIGN` (`.muttrc` is a misread) and `FROZEN_STRING_LITERAL` (the 25
  are mostly generated binstubs and Gemfiles). `TAB_CHARACTER` is down to 1;
  `DOLLAR_PAREN` and `STRICT_MODE_ZSH` read 0.
- **Geometry.** wiki and post show want geometry surfaces with seeded ids, which
  needs triangle; `void_target` and the `list_marker_hang` note live in
  `data/rules.yml`.
- **`layout_snapshot --explain`** needs a map from computed values to tokens and
  is checkable only in a rendered run; centred body text inside `main` is a
  rendered question.

### Before working any other group

Sample five findings, open the five lines, and decide whether the rule is right
before opening the sixth. Where it is wrong, the fix is the rule and the
exemption it should carry — not the file. That is how the 981-finding design
backlog turned out to be 596 misreadings of correct markup, and it is why this
section leads with the instrument rather than the total.

## One chrome — opened 2026-09-11

Operator decision: every surface wears brgen's front page chrome — its shell,
its type, its flat light palette — and any other chrome may be discarded. That
settles three questions this repo kept reopening, and it applies to the six
verticals, to amber, and to MASTER's web face.

Measured in headless Chrome at 1440x900 against the four local surfaces, which
`RAILS/bin/triangle status` already had running. Two claims died on that
measurement and are recorded here so nobody re-derives them:

- **The verticals do not lack layouts.** All six render through brgen's
  `application.html.erb` by design — the Rails engine pattern — so they already
  carry the wordmark, the nav, the search palette, the theme and the footer.
  Counting `app/views/layouts/*.erb` per engine reads zero and means the
  opposite of what it looks like.
- **The per-vertical accent is live and correct.** tv resolves `--accent` to
  `#dc635c`, dating to `#009579`, playlist to `#0e8a94`, each the
  contrast-tuned light-mode variant. An earlier reading of `#000000` was taken
  off `documentElement`, and the accents are declared on `body` — the
  instrument, not the tree.

What is actually wrong, each seen rather than inferred:

- **The browsable verticals have no content column.** On `tv.brgen.no` the
  section intro starts at x=439, "POPULÆRE VIDEOER" at x=419, and the empty
  state is centred at 720. Three left edges on one page, where the front page
  holds a single column. This is the largest visible difference between a
  vertical and the front page, and it is a container, not a palette.
- **dating is a second chrome, and it goes.** `dating.brgen.no` renders
  full-bleed with the nav hidden, a neon heart and a 200px wordmark — the
  "immersive" variant in `_vertical_shell.scss`. Under the decision above it
  gets the nav and the column like everything else. messenger is the other
  immersive surface; same treatment.
- **marketplace 500s.** `marketplace.brgen.no` raises where tv, dating and
  playlist render. Nothing about layout can be judged there until it serves.
- **amber speaks a different language entirely.** A serif tagline against
  brgen's sans, pastel-green wordmark at roughly 1.3:1 against its own
  background, a floating "Style notes" card aligned to nothing, and a hero SVG
  whose wordmark is clipped at the left edge of its own box. Its header mark
  sat flush at y=0 — 52px of mark inside a 44px bar with no block padding —
  and that one is fixed.
- **MASTER's web face shares 13 tokens with RAILS out of 87, and all 13 are
  motion and z-index.** No colour, no type. It renders black with a particle
  face and a terminal prompt where every other surface is flat light. Under the
  decision above the face keeps its canvas and the chrome around it becomes
  brgen's. The `#primer-voice` button can go; the full-viewport `#primer`
  behind it cannot, because a browser will not start an AudioContext without a
  gesture.
- **The layout's own comment is stale.** `application.html.erb` opens with a
  long paragraph explaining that `data-theme="dark"` is load-bearing.
  `DEFAULT_SURFACE_THEME` is `"light"` and has been; the surfaces render
  `#efefef`. A comment states the present-tense reason.

Order of work: the content column first, because it is one container shared by
six verticals and it is what makes them read as one product; then amber's type
and palette; then MASTER's chrome; marketplace's 500 whenever someone is in
that engine. Screenshot before and after — this section exists because two
confident readings of the source were both wrong.

## The ad design system, and the marketplace study — opened 2026-09-11

Operator direction. marketplace and takeaway take **www.kaufland.de** as their
shell, studied against nineteen more marketplaces rather than copied from one.
Beside that, an ad design system built on photography and bold typography,
because a marketplace front page is mostly large product images and large
type — and the same system makes brgen's own ads, for the front page, the
verticals and amber. Expected to take a while and to end up automated.

The stated target is worth keeping verbatim, because it names what this is
not: **Kaufland's catalogue + bol's cleanliness + eBay's marketplace depth +
Vinted's simplicity + brgen's local and social layer** — rather than a
Norwegian Amazon. That lands on an irony the tree already recorded:
`_marketplace_nav_bar.scss` opens by saying it "was a two-row Amazon clone",
and its eleven Amazon hex literals came out on 2026-09-11.

This is a program, not an item.

### The study — twenty marketplaces, and what each is for

Research each thoroughly, and record measurements rather than impressions: a
viewport, a screenshot, the grid's column count and gutter, the type scale of
a price, the aspect ratio of a card.

- **Kaufland** — the overall shell and catalogue UX. The model for our own.
- **bol** — visual cleanliness, and the closest thing to this fleet's flat taste.
- **Allegro** — search, filtering, and handling an enormous catalogue.
- **OTTO** — merchandising and category presentation.
- **Mercado Libre** — marketplace mechanics, seller and buyer interaction.
- **eBay** — seller ecosystem and discovery depth.
- **Walmart Marketplace** — the retail and marketplace hybrid.
- **Rakuten** — marketplace ecosystem.
- **Cdiscount** — European general merchandise.
- **ManoMano** — a category-specific marketplace done extremely well; structured category expertise.
- **Etsy** — seller identity and discovery; the human half.
- **Vinted** — frictionless second-hand, and effortless listing.
- **Back Market** — condition and quality communication; trust information.
- **Shopee** — mobile-first marketplace mechanics.
- **Taobao** — catalogue depth and social commerce.
- **JD.com** — product information and logistics.
- **Temu** — discovery and conversion mechanics.
- **Zalando** — fashion marketplace and personalisation. Read this one for amber too.
- **Mercari** — extremely simple peer-to-peer selling.
- **Newegg** — electronics and product comparison.

Check every idea against the tree before calling it missing. That habit is in
this file for a measured reason: of the last external enumeration, thirty-nine
items declared themselves done and another fourteen proved already true on a
grep. A list arriving from outside is a hypothesis about this repo.

### What exists already

- **`Shared::Affiliate` is the one path over every network**, and
  `affiliate_deals_for(category:, limit:)` is its reader. A new network appears
  in every unit without editing a view.
- **`shared/_affiliate_feed_unit`** is an in-feed band: product tiles packed
  edge to edge by CSS grid with call-to-action tiles among them, a
  `parallax-tilt` Stimulus controller over it, and an `--in_grid` modifier for
  surfaces that are grids (amber's wardrobe and outfit galleries) rather than
  lists (brgen's feed). It replaced a CodePen banner that needed five CDN
  scripts, one of them GPLv3-or-paid.
- **Models**: `Shared::AffiliateProduct`, `AffiliateVoucher`,
  `AffiliateConversion`, plus amber's `AffiliateLink`. brgen has
  `AffiliateImportJob` and `Brgen::AffiliatePlaceholders`.
- **Disclosure** is its own partial, `shared/_affiliate_disclosure`, and the
  band labels itself `affiliate.sponsored`. Whatever the ad system becomes, it
  inherits that: an ad says it is one.
- **Photography has a producer.** STUDIO's repligen generates imagery and fills
  tv; lora trains on real subjects. An ad system needing product photography
  has a generator in this repo rather than a stock budget.

### What Kaufland does that markedsplass does not

Read against markedsplass.brgen.no as it renders today, and not yet verified
against the live site at a set viewport — do that first and record numbers,
because this list is a description.

- A full-bleed hero of photographic banners. markedsplass opens with a text
  headline at display size and no image at all.
- Category tiles as pictures rather than a text row. markedsplass has
  `Ting Jobb Bolig Oppdrag` as plain links.
- Offer grids with price as display type. A listing card's price here is body type.
- Image-first cards at a consistent aspect ratio, which is what makes a dense
  grid read as one surface rather than a ransom note.

### Amazon is the functional model; the visual is ours

Operator position: Amazon remains the main inspiration for how a storefront
works, and its visual execution is below this fleet's standard. So the
storefront bar keeps its Amazon structure — a search field dominating the row,
deliver-to, account, cart, and a sections row beneath — because the structure
is the part that was right. What came out on 2026-09-11 was the execution:
eleven hardcoded Amazon hex values, #131921 and #232f3e navy, #febd69 and
#f3a847 amber, #cd9042 on the cart count, in a fleet that paints from tokens
everywhere else. The bar reads --surface, --text, --text-secondary and
--accent now, so it follows the theme and carries the marketplace accent
_vertical_shell already tuned for contrast in both directions.

Kaufland and the nineteen beside it are read the same way: take the mechanism,
leave the paint.

### The external Kaufland patch, assessed 2026-09-11

A fifth log arrived proposing the catalogue redesign as one patch: replace the
storefront header with a Kaufland utility strip and an `Alle Kategorien`
control, repaint the chrome white with red, rebuild the product card, drop the
hero, and move the filters into a persistent left rail. Most of it is either
already done, already decided against, or a rendered value. Two parts are real
and are the ones worth starting from.

**Its premise was a comment rather than the code.** The patch opens by removing
Amazon's dark palette wholesale, quoting `_marketplace_nav_bar.scss` calling
itself "a faithful two-row Amazon clone". That sentence is history and the file
says so; all eleven hex literals came out earlier the same day, and `#131921`,
`#232f3e`, `#febd69`, `#f3a847` and `#cd9042` appear nowhere in RAILS source
now. The bar has read `--surface`, `--text`, `--text-secondary` and `--accent`
since. Its headline target — Kaufland's catalogue plus bol's cleanliness plus
eBay's depth plus Vinted's simplicity plus brgen's local layer — is the
operator's own sentence from the top of this section, handed back.

**And it overturns a recorded position without knowing it existed.** The
subsection above states that the storefront bar keeps Amazon's structure — a
search field dominating the row, deliver-to, account, cart, sections beneath —
because the structure was the part that was right. The patch replaces exactly
that structure. The rule for all twenty references is the same one: take the
mechanism, leave the paint.

**The DOM is the real finding, and the log names it itself.**
`shared/_live_search_index.html.erb` renders the search form — with the filter
`<details>` captured inside it — and the results turbo frame as siblings. A
persistent filter rail beside a product grid cannot be built over that shape
with CSS; the helper has to let a caller place the form and the frame
separately, or wrap both in a container it does not currently provide. That is
structural, it is testable, and it blocks the catalogue layout whoever builds
it. Do this one first.

**The second is a card contract rather than a card look.** Kaufland's density
comes from every product exposing the same fields at the same vertical
positions: image, title, rating and count, price, reference price, discount,
shipping, delivery window, seller, condition, unit price. markedsplass has the
data — listings carry variants, facets, ratings, reviews and distance — and
renders a subset in a different order per surface. A fixed ladder is a contract
a gate can hold, and `distance_km` is the field Kaufland has no answer to.

Everything else in the patch is a rendered value: the white canvas, the red
accent, `object-fit: contain` on product photography, the card's borders and
type scale, and removing the hero. Fenced, as the section below says. Build the
information architecture, measure it at a set viewport, and bring the look back
for a decision.

### Every unit is multi-city, multi-domain and multi-language

brgen is one app over roughly twenty city domains, and the marketplace
subdomain is localised per country: `markedsplass.brgen.no` in Bergen,
`marketplace.lsangeles.com` in Los Angeles, and nine more spellings in
`Brgen::DomainRegistry::SUBAPP_ALIASES` — marche, markadur, markedsplads,
markkinapaikka, marknadsplats, marktplaats, marktplatz, mercado, mercato.
`DomainRegistry.resolve(host)` is the one way to ask which city and which
vertical; never re-derive a subdomain.

That constraint already caught something. The storefront header carried a
hand-written logotype reading `markedsplass` + `.no`, and takeaway's read
`takeaway` + `.no` — hardcoded Norwegian words and a Norwegian TLD rendered on
every city, so `marketplace.lsangeles.com` said "markedsplass.no" in its own
header. Both came out with the second wordmark on 2026-09-11, which means the
fix landed as a side effect of the chrome decision rather than on its own
merits. Anything the ad system renders — a category name, a price, a call to
action, a crop with words burnt into it — carries the same exposure.

Some city domains are expired or expiring, with funding for renewal in
progress. Treat the domain list as a live set: read it, never hardcode it, and
expect a surface to be unreachable without that being a defect in the surface.

### Two search fields on one storefront, and the better-placed one is the worse one

Measured on takeaway.brgen.no and markedsplass.brgen.no at 1440x900: two
`input[type=search]` on the page with the same placeholder. The storefront
bar's sits at y=131 and is a plain `form_with method: :get` — a full page
navigation. The one in the page body sits at y=390 and is `live_search_index`,
a turbo frame with results as you type.

So the field in the right place does the worse thing, and the field doing the
right thing is below the fold. Amazon — the functional model — has one, in the
bar. The fix is to make the bar's field drive the live frame and drop the body
copy, which is a decision about where search lives on these surfaces rather
than a tidy-up, and the Kaufland pass will answer it. Left here so that pass
starts from the measurement.

### The shape to aim for

One unit vocabulary, declared once and rendered by every surface that takes
ads: hero banner, category tile, offer tile, in-feed band. Each reads
`Shared::Affiliate` or a brgen-authored equivalent through the same interface,
so a house ad and an affiliate ad differ in their source and not in their
markup. Typography comes from the existing scale rather than a second one, and
each unit fixes one aspect ratio so the grid holds.

Automation is the last step. A unit a person can fill by hand and that looks
right is the thing to automate; automating the layout first produces a
generator for a design nobody approved.

### Fenced

Every colour, typeface and crop here is a rendered value and the operator is a
trained architect. Build the structure, measure the geometry, and bring the
look back for a decision rather than choosing it.

## Bottom chrome and the peel handle — opened 2026-09-11

Fixing the walk unmasked `rendered_geometry`, which had been reporting against
the same corrupted keys. Six hard findings, in two groups, and both want an
operator decision rather than a guess.

**Three occlusions, and they are a consequence of one chrome.** On
`brgen/dating` and `brgen/channels`, the `.tab-bar-peel` handle's centre pixel
is owned by a link in the page — the dating intro's trust footer, a channel
card's blurb. Fixed chrome cannot be scrolled out from under a blocker, so the
handle is dead for the life of the page. It appeared because dating and
messenger left the immersive list and got their bottom chrome back, over
content written when there was none.

The fix is a design decision that `_tab_bar.scss` has already half-stated:
"Content and bottom-pinned chrome reclaim the space via --tab-bar-h → 0". So
the intent is that content takes the space and the peel floats above it, which
is exactly the overlap the gate is reporting. Either the peel floats and this
finding is exempt, or bottom-reaching content clears it and the clearance
wants a token of its own — the peel's height is `--tap-min` and nothing
publishes it. `#install-prompt` needed the same clearance and now spells
`max(var(--tab-bar-h, 0px), var(--tap-min, 44px))` inline; if a token is
wanted, that is its first caller.

**Three contrast failures, all one shape: an accent used as ink on a light
surface.** messenger's `#6b7fd7` on white at 3.72, playlist's `#0e8a94` on the
tunnel's `#14141a` at 4.44, and the storefront cart count, which ran Amazon's
`#cd9042` at 2.74 and the marketplace accent at 3.48 before taking `--text` at
12.63 on 2026-09-11.

An accent is tuned to be legible as a fill carrying ink, which is the opposite
job from reading as small text on white. The hover slot is not the answer
either: marketplace's `#6f6149` clears at 6.03 but takeaway's `#c26a30` is
3.89, and they share one storefront bar. What the map wants is a fourth slot —
a darkened per-vertical ink for text-on-light, the way `--food-dash-ink` was
picked for takeaway's eta chip. Seven colours, and every one of them the
operator's.

## Operator-owned, recorded not opened — from the 2026-09-11 reassessment

Two refusals from that pass stay closed, argued beside the code they concern:
`Core::Constitution` keeps its own read of `rules.yml`, and cognition phases 3
to 8 wait for weeks of real event history. What needs the box, money or a
rendered decision, and is not already listed above:

- **Per-process resource evidence.** `resource_guard.sh` sheds on aggregate box
  load, so the log never says which process took the memory. Add per-process RSS
  for the managed services, record an exited process as unavailable rather than
  zero, and change no threshold in the same patch.
- **TTS daemon ownership.** Worker logs and sockets can be created as root while
  the daemon runs as `master`. Find the writer before adding a periodic chown,
  expose `tts_socket` in `bin/operator vps state --remote`, and make health
  distinguish process-up from socket-usable.
- **The face's shader brightness floor.** Probe the live face at production
  defaults against the README-sized render and change the shader, not a
  recorder-only uniform. A rendered value: bring the number back for a decision.
- **Deep visual gates need a browser.** The measure output has CSS budget rows
  that cannot be read without one, and an unreadable row must never count as
  green. Run the deep audit only when a browser is present, keep screenshots and
  geometry as the receipt, and report unavailable as unavailable.

## Wishes, not work

Directions rather than tasks. They belong to the operator, and nobody should open
one as a ticket without asking first.

- **The face's brightness is a look, not a bug.** It renders at 0.4% of pixels
  lit, and whether that is right is the operator's eye.
- **Retire the rolling pixel baseline.** `RAILS/gates/visual_contract.rb`
  re-baselines to zero on the next run by design, so a regression reports once
  and then becomes the reference. `layout_snapshot` commits reviewable JSON —
  71 tracked files — and is the candidate for the fleet's only visual baseline.
- **repligen has no Replicate access, so the whole tool is unreachable.** Fund it
  or retire it; leaving it is the inert-wiring defect with a price tag.
- **One box per city rather than one box for every city.** brgen's verticals are
  already engines and vm23 sits at its capacity ceiling, so a cell per city is
  the shape that scales. It is a business decision before it is an architecture.
- **MASTER should judge its own edits to the constitution**, with the diff
  attached — the governor governed. The constitution should also be short enough
  to read in one sitting and complete enough that nothing outside it governs.
- **Aegis's drift model is the one buildable piece** of the section below: a pure
  function from entry position, sea state, current and elapsed time to a
  probable-position ellipse. Everything else there waits on hardware.

---

## In-depth refinement — what survived 2026-09-14

Opened 2026-09-11 as a numbered inventory across the four trees. The 2026-09-14
pass closed the OPENBSD lists and the RAILS larger-than-a-sitting list by doing,
measuring or arguing each item (comments beside the code, the OPENBSD Refused
list and `RAILS/shared/WIRING_NOTES.md` carry the arguments). What remains needs the
operator, vm23, a browser or the dilla owner. Numbers are kept for citation.

### MASTER

5. **Operator: the Pixel Field palettes reach the chrome.** `topologies.yml` `palettes.operator.accent` is the fallback in `master_events.js#paletteForProvider`, which `visual_bridge.js:220` writes to `--master-accent`, which colours `.provider-chip` (`face.css:643`). Decide whether the chip takes a canvas colour or a CSS token.
8. **Operator: `soul.yml` is the last duplicate voice and still names `bin/cli` sacred.** `voice:` and `negotiable.tts_voice` repeat `voice.yml` `neural:`, and `absolute.sacred_paths` lists `bin/cli`. The file is `paths.immutable`, so both one-line edits are yours.

### MASTER — web face

141. **Operator: the FOUC guard's colours.** `index.html.erb` keeps `data-theme="dark"` and three inline `#000` rules as the paint before `face.css` loads. They move with the stylesheet, and the values are yours.
145. **vm23: `face.modules.bundle.js` is built and loaded by nothing.** `face.js` imports modules through `MASTER_ASSET_PATHS`; only the rake task, `face_boot.test.mjs`, `script/ci_web_probe`, `OPENBSD/etc/rc.d/master` and the OPENBSD deploy scripts name the bundle. Removing it edits rc.d, so do it with a `rcctl restart master` watched on vm23.
152. **Operator: the dashboard is a second chrome.** `views/dashboard/index.html.erb` links `/face.css` and draws its own panels. Fold it into the face or give it brgen's shell; either changes how it looks.
239. **vm23: CSP is report-only.** `content_security_policy.rb` enforces only when `PUB4_CSP_ENFORCE=1`, and only `OPENBSD/etc/master.env.sample` names it. Check `/etc/master.env` on vm23, set it, reload the face, and read the console for refusals before keeping it.

### RAILS — brgen core

Closed 2026-09-13 by doing, measuring or deciding; the declined proposals and
their reasons are in `RAILS/shared/WIRING_NOTES.md` under "Declined, with the
reason". What is left needs the operator, vm23, a browser, or is larger than a
sitting.

**Operator — the look.**

- **Static error pages keep a dark palette the app no longer uses.**
  `{brgen,amber,bsdports}/public/{404,422,500}.html` set `color-scheme: dark`
  and inline `--x-*` colours over `shared/public/styles/errors.css`, while every
  app renders light; bsdports' 404 and 500 are still Rails' English defaults.
  Decide the palette; the seam is `errors.css` plus each page's inline `:root`.
- **`.page-header` is five different elements across the verticals.** Measured
  at 1440px on 2026-09-12: absent on markedsplass and playlist, 0px wide on
  dating, 747px on takeaway, 600px on tv, and brgen's front page uses
  `.feed-header`. The contract in `shared/LAYOUT.md` describes an element four
  of seven surfaces do not render. Whether the contract or the verticals are
  wrong is a layout call. Two inert `grid-template-*` pairs remain on `.layout`
  (a flex box) in `_vertical_messenger_list.scss:20-21` and
  `engines/maps/.../_vertical_maps_shell.scss:45-46`; remove them with a
  before/after measurement.

**vm23.**

- **Zombie amber jobs.** `RemoveBackgroundJob` and `SegmentGarmentImageJob` have
  no enqueuer; count their rows in amber's production queue, then delete both
  classes (their headers state the precondition).
- **Two recurring schedules never fire.** amber's `declutter_hygiene` (6am) and
  bsdports' nightly import (3am) sit in `recurring.yml`, but those apps have no
  resident worker and `drain-jobs.sh` runs three minutes at :05 only when jobs
  are due, so the scheduler is never up at that minute. Choose: an hourly
  schedule, or a cron line on the box that enqueues them.
- **After the next deploy, check:** a signed Stripe test event returns 200 at
  both `https://<city>/webhooks/stripe` and the markedsplass host; a Vipps
  checkout redirect lands on `*.vipps.no`; `/deals` with a badged deal; a kitchen
  status button redirects; editing a dating profile keeps its photos;
  `/etc/brgen.env` carries `VIPPS_CLIENT_ID`; `curl -I` shows `Server-Timing`
  under relayd's 8 KB header limit; migration `20260913140000` ran; after an
  amber drain, `SolidQueue::BlockedExecution` and `Semaphore` rows are not left
  behind; bsdports' next import rewrites every port's distfiles flag.

**Needs a browser or triangle.**

- **`stimulus_boot.js` boots all 56 imports, 14 of them `@stimulus-components`,
  in every app.** Register each component only in the apps whose views mount
  it; verify on a booted triangle, because a missed registration fails silently.
- **Signed-in personas** (`GATE_ADEQUACY.md` gap 1) need a seeded fixture user
  in triangle.
- **A listing's postpro photo has no status.** `PostproJob` adds the processed
  photo after create; a busy worker leaves the listing with originals only and
  nothing says so. A status column needs a reader on the listing page, and
  whether "pending" ever resolves depends on the postpro script being present
  on vm23.

### OPENBSD

789. **vm23: `/home/dev/.zshrc` still sources the missing `FUN/zshrc.shared`.**
     The Mac side is fixed and `OPERATOR.sh` no longer installs the redacted
     mirror over the live file; the box's own copy needs editing there.
1062. **`.dash-stats dl` wants auto-fit and could not be verified for it.** Amber's
     stat grid is four columns, two below md, and nothing between — a tablet gets
     the phone grid. `repeat(auto-fit, minmax(<floor>, 1fr))` computes the count and
     adds the three-column step, which is the right shape. It was written and then
     reverted on 2026-09-12: the floor has to be measured against the real dashboard
     container, that page is behind a login the CDP probe cannot reach, and a floor
     guessed wider than the column silently drops desktop from four columns to
     three. Measure the container, then set the floor.

### STUDIO — dilla

Re-measured 2026-09-13; 190 entries became these. The first group is real and
blocked only because `STUDIO/dilla/dilla.rb`, `lib/groove.rb`,
`README.md` and `ENV_AND_RENDER.md` carry another session's uncommitted work.
Take them the day those files are clean.

811. **dilla.rb comments that describe the split.** 80 `# engine part:` headers still say "split out of dilla.rb"; `:230` says load order lives in `engine_sources.rb`; `:248`, `:13733`, `:14870`, `:20805` still name `lib/engine/`; `:14900` names the gone `ENGINE_PARTS`; `:14672` hardcodes "35,000 lines / 83 markers" instead of asking `parts_report`. `:35237` should say the gate and tests depend on the CLI guard.
812. **`ENGINE_SOURCES = DillaSources.all` sits at `:34385`,** after `wiring_dead_constants` and `parts_report` close over it. Move it up to the require at `:36`.
814. **`scan` probes `dilla.html` (`:13165`),** a file that does not exist. Drop the key.
815. **`help` is one 170-line dump.** Topic index (`help render|chop|knobs|sample`) with the wall behind `help all`. The topics owe these lines: `industrial`/`techno`/`analog` bypass AudioGraph; `characterize` under READING THE ENGINE; `source` points at `lib/sampling.rb` before `project/crate.yml`, and `dilla_live.rb dig` is the YouTube digger; chop lists RadioChop's operations in order; `STREAM_DEMO` overwrites the rolling `demo.wav`, not a take; `DILLA_OVERWRITE=1` is the only overwrite; `SWING=` is the fallback and per-role offsets are the Charnas move.
816. **`council` (`:13184`) prints five slogans.** Delete it or make it run a command.
822. **Lazy requires are undocumented.** Say beside the requires which of `console_strip`, `tape_hysteresis`, `mix_score`, `verify_fx`, `kit_dig` are command-only, so a fold does not pull DSP into boot.
829. **Locale.** brgen's CI loads dilla.rb as user brgen; set `Encoding.default_external = Encoding::UTF_8` at the top of dilla.rb rather than touching 37 `File.read` sites.
853. **`dilla stems` should refuse** when `data/stems.json` names `samples/demux/…` paths not on disk, as `dilla assets` does.
855. **"~60 presets"** in `groove.rb` and the README: count in `dilla knobs` instead of restating.
868. **Chop registry JSON is parsed twice** (`:18223` warns, `registered_loops` rescues again). Parse once; drop bad rows by slug.
871. **`rap-vocal list`** should mark sidecar-only rows "audio missing", and say `_mislabelled_untitled_flac/` is deliberate so nobody cleans it.
873. **`dilla assets` exits 0 on an unreadable `data/assets.json`.** The module warns and returns an empty crate; the command should exit non-zero.
965. **dilla README and ENV_AND_RENDER.md.** README names `sample_loops.rb` (it is an engine part), tells a stale restore story, and never says a worktree has no crate so crate tests skip; ENV_AND_RENDER.md says command aliases are gone while `loose_pocket`, `industrial` and `techno` remain as genre renderers. One sentence should name the three ways to hear it: `dilla.html`, `dilla_live.rb`, `bin/sine_stream.rb`.
1000. **Provenance pins.** Confirm a probe asserts the sidecar note carries a non-seed pin when `USER_PINNED_ENV` is set; add one to `test_dilla_engine_probes.rb` if not.

These are the operator's, because each changes a sound or accepts a changed input:

850. **`data/modes.yml` has no reader.** Nothing in STUDIO loads it — `tizita`, `bati`, `ambassel` appear only in the file, and the `chord_theory.rb` it names is gone. Wiring it into the harmony spine changes what dilla generates; the other choice is deleting it. Same decision as `dilla_principles.yml`.
859. **The crate on main disagrees with `data/assets.json`.** `DillaAssets.verify` there: `samples/{kembara_rindu,lo_borges,semua_untuk_mu}/loop.wav` missing, and seven one-shots under `samples/drums/` changed hash at the same size. Restore them, or `dilla assets record` to accept the new drums as the inputs.

### STUDIO — postpro, repligen, lora

907. **Chains are ungraded by default.** `generate` applies `HOUSE_POSTPRO` (`portrait`); `chain` grades its final frame only when `--postpro` is given. Whether chains share the house grade is a graded-look call.
926. **`lora/guides/*.m4a` are tracked TTS output** beside their `.txt` scripts. Keep them in git or untrack them; either is the operator's.
931. **`lora/_toolkit/judge_thresholds.yml` was calibrated on seven images;** `ragnhild/dataset/` now holds six. Recalibrating moves the quality floors.

---

## Wiring, type and Rails leftovers — the 2026-09-11 second pass

Worked 2026-09-13 and 2026-09-14. Refusals are in `MASTER/AGENTS.md`, Refused, and
`RAILS/shared/WIRING_NOTES.md` ("Toggles redirect", "System tests stay on
Selenium"). `data/modes.yml` has no reader (see STUDIO 850), so entries
elsewhere that treat it as the live scale are wrong.

### The operator's — behaviour the face or a page shows

2. **Face regexes name topics nothing publishes.** `phantom:retry` (`face_semantics.js:162`, `topology_registry.js:22`, `data/topologies.yml:7`) where the bus publishes `phantom:recovery|occurrence|halt`; `pipeline:start` (`face_semantics.js:192`, `face_perf_guards.js:68`, `topologies.yml:13`) where it publishes `pipeline:stage_start`; `council:deliberation` in `face_semantics.js`, `face_council_multi.js`, `cognition_ecology.js`. Renaming makes the face flinch and tint on events it ignores today, so the operator should see it once; the bundle rebuilds at `assets:precompile`.
29. **Identity, reputation, neighbourhoods and mentions are models without an inlet or a page.** `IdentityAssurer` is called only by a test; `IdentityAssurance` and `ReputationScore` have no reader outside their model files; `Neighborhood` is read by dating profiles and the demo seeder; `Mention` rows are written by `Shared::Mentionable` and shown nowhere. Every one has a table behind it, so each is a product call per model.
R12. **Dating prompt order.** Prompts have routes and a model, but no view creates or lists them, so there is nothing to order until one does.
R23. **Native `<dialog>` for confirms.** The dating match overlay is a celebration card rather than a confirm. The report confirm, the takeaway cancel and amber's "let go" would each put a new modal surface on screen, and how it looks is the operator's.

### The operator's — each changes how a page looks

55. **Reading surfaces that do not wear `.prose`:** legal (`legal-prose`), mailer, listing description (`66ch` literal), dating bio, errors. Joining `.prose` brings measure, hanging, hyphenation, `text-wrap: pretty`, orphans, oldstyle numerals; `.reading-column` and `.form-measure` exist and no view wears them.
59. **The mailer is a third type system** — three families, private size ladder, tracking 0.04–0.28em, off-scale radius and leading, dark `#050505`, no tabular price. Snap to the tokens; the letter's colour stays the operator's.
64. **Measures in px:** `.page-header` 660, bsdports header 660/62ch, amber `.item-detail` 700, playlist 720, forms 480/584, splash tagline 28em, errors 30em, print `.prose` 100%. Chrome widths (map HUD 280/320, dressing room 420, `--feed-max`) stay.
78. **Scale and rhythm:** `--line-height: 20px` absolute; `--text-display` is a ninth size and H1 is 1.75× body against a 2.0 law — decide which token is H1; `font-size` 1.17/0.92/0.6em; two paragraph rhythms; 500/700 weights unused; legal 1.62 and mailer 1.55 leading; `.post_body` 1.6 against `.prose` 1.5.
86. **Tracking:** `--tracking-tightest` −0.03 on heavy headings and marketplace −0.045em; primer h1 lowercase `.01em`; face `.04em` and `.32em`; legal eyebrow `.12em` at `.72rem`; mailer kickers; uppercase labels in maps and marketplace cards without tracking.
95. **Families per surface:** marketplace hero three families; face primer names Inter beside system-ui and mono; splash chips mono on a system-ui splash.
99. **OpenType and quotes on `.prose`:** `onum pnum liga clig`, `hyphenate-limit-lines: 2`, `quotes` for nb, `smcp` on `abbr`, tabular numerals on mailer price, legal dates and wiki history; face `font-feature-settings` lacks the defaults.
109. **`_fonts.scss` falls back to jsDelivr for JetBrains Mono** though `/fonts/` is self-hosted, and Libre Baskerville files may have no `@font-face`. Dropping the CDN is a first-paint change on a missing file.
111. **Flat UI residue:** `_search_yep.scss` shadow (PEN_ALLOW), `#ccc` and `white` on search, dating button gradient, splash `scale(1.02)` at rest, `chat_upload.css` `.42s`, vote `duration-value="900"`, `_tab_bar.scss:99` max-width band unmarked, marketplace masthead clamp 5.5rem.
B16. **Modulor:** if H1 stays 1.75×, lower the ratio in law or raise the title token.

### Needs vm23

C24. **Checkpoint WAL before `dr-pull`** (`PRAGMA wal_checkpoint(TRUNCATE)` or `.backup`), so the off-host copy is consistent.
C26. **If `/var/log` shows `database is locked`, raise `busy_timeout`;** confirm one writer per primary with `FALCON_WORKERS` at 1.

---

## Bughunt, restructure and harness gaps — what survived 2026-09-14

The 2026-09-11 bughunt, the "one job, one door" restructure list and the two
agent-harness comparisons were worked on 2026-09-13 and 2026-09-14. Refusals
sit in comments beside the code they concern, in the Refused lists in `MASTER/AGENTS.md` and `OPENBSD/CLAUDE.md`, and in
`RAILS/shared/WIRING_NOTES.md` ("Write races on SQLite"). One trap from the pass:
SQLite transactions here are `BEGIN IMMEDIATE`, so a finding about a uniqueness
race or a rolled-back callback is false until it names a second database.

### Blocked on `STUDIO/dilla/dilla.rb` (another session holds it)

- **Album master and encode trust a failed ffmpeg.** Album master reads `I=0`
  from a failed run and applies ~19 dB of make-up; album encode ignores status,
  deletes the staged file and prints loudness from the missing dest;
  `audio_duration_sec` rescues to 0.0 and `build_harmony_loud` then mixes 8 s.
  First step: route them through `lib/listen.rb`, which MixScore and
  VerifyFx already use.
- **Scratch names collide.** `harmony_loud.wav`, `live_tmp.wav`,
  `dilla_drums.wav` are not pid-scoped, and the fallback dir is per-uid. The
  pid-scoped temp helper exists in dilla.rb; use it everywhere.
- **Loose ends in the same file.** Playlist/learn loaders rescue a corrupt
  catalog to empty and the next save overwrites it; engine `capture` returns
  `[out, err, status]` while `RadioChop.capture` returns a string;
  `STREAM_ITERATE_LOG` is appended without flock; the `council`/`scan` slogans
  still sit in dilla's dispatch.

### Operator decisions

- **`.reading-column` / `.form-measure`** (`shared/_typography.scss`) are
  defined and worn nowhere. Wearing them on legal and compose changes the
  measure; deleting them is the alternative.

### Needs vm23

- **After the next deploy, install and check on the box:** the four app/master
  rc.d scripts (deploy flag now spans the /up wait), `resource_guard.sh` (stale
  flag after 1800 s), `/usr/local/bin/{nsd-resign,drain-jobs.sh,core-reclaim.sh}`
  and `emergency_cpu.sh`, then read `/var/log/drain-jobs.log` and the next
  `nsd-resign` run in the daily mail for a FAIL line. brgen migrates
  `20260913130000_drop_unwritten_tv_video_counters`.
- **`smtpd.conf` listens on `vio0`.** `listen on egress` survives an interface
  rename; read smtpd.conf(5) on the box before changing it.

### STUDIO

- `rake test:dilla` loads every `test_dilla_*.rb` into one `-e` process, so ENV
  pins and `session.json` mtimes leak between files, and `EnvSandbox` restores
  ENV but not constants computed from it at load (acapella `ONLY`/`EXCLUDE`).
  Run each file in its own process, or stop calling it isolation.

## OpenCrabs borrow list — ChatGPT intake 2026-09-13

Worked 2026-09-13 and 2026-09-14: items 2 to 8 landed with a test each, and the
refusals are in `MASTER/AGENTS.md`, Refused. One stays open.

1. **The interactive CLI can never approve a Request.** `CoreBridge.build_fold`
   builds `World.new` without `ask:`, so the push, hard reset and deploy the
   sandbox routes to a person are refused at a terminal as they are in the
   daemon. Needs a TTY surface that does not fight the thinking indicator, and
   the operator's word that approval belongs there at all.

## ChatGPT proposed forward work — intake 2026-09-11

478 items, worked 2026-09-13. About 306 were built, false or already open
elsewhere; 43 were done with a test each; about 110 were refused, with the
arguments in the Refused lists in `MASTER/AGENTS.md` and `OPENBSD/CLAUDE.md` and in comments beside the code; seven product wishes went to `RAILS/apps.horizon.yml`.
The trap worth keeping: the intake asks for a gate over mechanisms the tree has
under other names, so grep for the mechanism, never the proposal's word.

- **Rendered journeys nobody walks.** Turbo-frame navigation, focus after a Turbo
  visit, the `noscript` pager paths, and messenger reconnect keeping scroll
  position and jump-to-newest. Extend `journey_invariant`, `keyboard_flow` or
  `mobile_flow`; rendered gates run on the deploy host, not on a shared Mac.
- **Prove the new box checks on vm23 after the next deploy.** Run
  `health_check.rb --all-ready-apps`: the permission audit (`/etc/*.env`,
  `/home/*/app/storage`, tts-worker log owner) and the `df -ik` disk check must
  pass, and `/health` `deploy.git_sha` must name the booted commit. No reboot of
  vm23 has been verified end to end; do one in a window the operator picks.
- **dilla may orphan its children on Ctrl-C (unverified).**
  `system_with_timeout` spawns with `pgroup: true`, so the terminal's SIGINT
  never reaches the child, and it kills the group only on timeout; the looping
  play path traps INT with a bare `exit 0`. Check with `ps` after interrupting a
  render and a looped play; the fix lives in `STUDIO/dilla/dilla.rb`, which
  another session holds uncommitted.

## STUDIO/dilla mix and reference research — ChatGPT intake 2026-09-11

Closed 2026-09-13. The measuring half was built or refused, and the refusal is in
`MASTER/AGENTS.md`, Refused.
One decision stays with the operator.

- **Sound changes the intake proposed.** A `ROUGH_HEWN` or `DENSE_EXPERIMENTAL`
  profile, a mastering stage split from the mix bus, stem-group routing,
  deliberate mono-source widening, per-channel strip variance, MPC-style shift
  timing, and sample-start offsets independent of drum timing each change how a
  take sounds. Decide which, if any, to try. Seams: `lib/sound.rb`,
  `lib/sound.rb`, `lib/groove.rb`, `DILLA_STYLE_DEFAULTS`.

## MASTER web UI — future-human face — ChatGPT intake 2026-09-11

Closed 2026-09-13 except the operator's look and voice and one check that needs
a browser on vm23. The refusal is in `MASTER/AGENTS.md`, Refused: the face's design is the
operator's.

- **Morphology.** Whether the face moves toward a far-future-human form — larger
  cranium, smaller lower face, wider orbits, seeded developmental asymmetry,
  slow drift, generations 0 to 4 — and how far; and any blind test of
  recognisability or perceived intelligence. Seams: geometry in
  `web/public/face.part1-3.txt`, `VOICE_IDLE_SIGNATURES` in `face.part1.txt`.
- **Expression, motion and layout.** Continuous affect instead of named
  expressions, a motion grammar with per-region time constants, speaking motion
  kept below lip-sync, states that read without colour, and a
  face-conversation-input hierarchy on one spacing, radius and duration scale.
  Seams: `face.part3.txt`, `face.part5.txt`, `face_semantics.js`, `face.css`.
- **How MASTER says technical text.** `Speech#clean_text` drops code blocks and
  links but speaks paths, identifiers and figures nearly as written. Whether to
  respell them, and any rate, pitch or pause policy beyond `voice.yml`
  `default_rate` and `default_pitch`, is a voice decision. Seams:
  `lib/voice/speech.rb`, `lib/voice/lexicon.rb`.
- **A real-browser smoke on ai.brgen.no.** `health_check.rb` proves TTS answers
  and `deploy_smoke_gate.rb` proves `face.runtime.js` exists; nothing proves the
  deployed face paints, speaks one phrase with moving visemes, and falls back to
  2D with WebGL off. Needs a browser on vm23, where rendered gates belong.

## Subtraction and refinement intakes

Three ChatGPT intakes of 2026-09-11 closed on 2026-09-13. Layout
micro-refinement (264 items) is `RAILS/shared/WIRING_NOTES.md` "The layout
micro-refinement intake"; the CLI dmesg model (160) is the comment on `Trace::Dmesg`;
subtraction and entropy (254) is "No audit without a path" in `MASTER/AGENTS.md`,
Refused. What stays open:

- **`shared/_toast.html.erb` is rendered by no view.** `stimulus_boot.js`
  registers the controller, so the component is wired at one end only. Where a
  toast appears is the operator's call.
- **`swarm.html` and `codebase.js` are built and unreached.** `swarm.html` is the
  May face renderer, still public at ai.brgen.no/swarm.html and linked from
  nothing. `codebase.js` is the Repository Body renderer that
  `topologies.yml:95` names, but `face_assets.yml` does not load it, so the
  topology is never drawn. Delete, gate or load each; both are product calls.
  `diag.html` reads only the visitor's own WebGL and stays.
- **`ListeningLoop.converge` targets -14.5..-10.5 LUFS** (`harmony.rb`)
  while the critique scores against the house -20..-16. Aligning it changes when
  a render stops raising `HARM_VOL`, so it waits for the operator's ear.
- **`core-reclaim.sh` parses `swapctl -l` and `vm.loadavg` with head, tail and
  awk** in five places. Four are field splits `set --` can do; the fifth is a
  float comparison OpenBSD ksh cannot make, and a careless replacement moves
  when the box sheds memory. Check each form on vm23 before changing it.

## performance

Both 2026-09-11 performance intakes (980 items) closed on 2026-09-13: six
measured costs fixed, the rest declined as unmeasured. The rule for the next
proposal is "No performance machinery ahead of a measured slowness" in
the Refused lists in `MASTER/AGENTS.md` and `OPENBSD/CLAUDE.md`.

- **dilla_live is not real-time.** Last measured: synthesis 1.58x real-time,
  the effects chain drags it to 0.34x. Re-measure first; any speedup must leave
  the rendered sound identical, and `dilla.rb` is under another session’s edit.

## Brgen monetization

The 289-item intake of 2026-09-11 is twelve rows under `horizon.brgen.monetization`
in `RAILS/apps.horizon.yml`, fences included. One decision is the operator's and
blocks all of it: which model comes first — the intake ranked verified business →
subscriptions → promoted listings → analytics → credits, with 0% commission — and
whether the shared Commerce/Entitlements domain is worth building before liquidity.

## Tree grammar

The grammar itself is written in `TREE.md`; the Rakefile split and a MASTER
`docs/` move are refused in `MASTER/AGENTS.md`, Refused. The `MASTER/bin/` fold lives in
the MASTER sections above. One item survives.

- **The OPENBSD root holds ~60 loose files in three layouts.** Gates at the root
  (`integrity_gate.rb`, `health_check.rb`, `config_drift_gate.rb`, …) beside
  `OPENBSD/gates/`; operator shell (`deploy_all.sh`, `vps_*.sh`,
  `start_all_apps.sh`, `resource_guard.sh`) beside `bin/` and `usr/local/bin/`.
  vm23 procedures and the resource_guard cron call several by path, so the move
  needs the box:
  grep `/home/dev/pub4/OPENBSD/` on vm23 first, then move gates under `gates/` and
  verbs under `bin/` in one commit with `PATH_OWNERSHIP.yml`.

## dilla — measured defects, blocked on `dilla.rb`

Measured 2026-09-13 against the committed engine. Each fix is an edit to
`STUDIO/dilla/dilla.rb`, which another session holds dirty; none changes a sound
default unless marked.

- **Hocket voices all play one patch.** `render_hocket_lead!` calls
  `voice_stack_lead!` first, which always returns a path, so the per-voice
  `EP_GM_PROGRAMS[i]` fallback never runs; under VoiceStack every hocket voice
  picks patches from the same `seed_for("vsmodel#{voice.index}")`. The album
  signature's `HOCKET=3` is a note census, not an ensemble. Fix: pass the hocket
  index into the stack's patch seed or program. Sound change — operator hears the
  A/B.
- **`VoiceStack` plans `cutoff_scale` and nothing applies it** (`lib/sound.rb`
  plans it; the only other reader is `describe`). Wire it into
  `render_lead_voice!`'s filter or delete the field.
- **`data/modes.yml` has no reader.** The engine still walks the hardcoded
  heptatonic `SCALE_SEMITONES`/`DEGREE_TRANSITIONS` in `dilla.rb`, so the four
  qenit modes are inert and adding hicaz or hüseyni there would be too. Load the
  file into those tables first.
- **`insert_secondary_dominants` and `insert_backdoor` write one-note chords**
  (`lib/harmony.rb:351,368`). `apply_voicing` returns any chord without a
  third unchanged, and both pass it a single pitch, so `V7/ii` and `bVII7` land
  on soul profiles as a lone note unless `validate_and_fix` repairs them —
  measure that, then voice them fully or delete them. Sound change — operator.
- **The demo run lies about success.** `acquire_demo_lock!` exits 0 when another
  run holds the lock and checks-then-writes (use `File::EXCL` or flock); an
  unknown command prints help and exits 0; the loop exits 0 with parts missing
  (exit non-zero unless `parts == order`); the next run wipes a killed run's
  finished parts unless `DEMO_KEEP_PARTS=1`;
  `demo_all` sets `DILLA_STREAMING=1`; `DEMO_TRACK_TIMEOUT` defaults to 420 s; help
  still says bare `ruby dilla.rb` runs `readme_loop!` when it runs `demo_all`.
- **Logs and provenance print load-time device ENV.** `ringtone_layer_describe`
  and the sidecar can report `COPY_MACHINE=6` on a slot `apply_album_slot!`
  forced to 0. Snapshot after the last `force_env!`.
- **Names.** `demo-all` is the catalogue, `demo` is `generate_demo`'s crate matrix,
  `showcase` is a third medley. Rename to `demo` / `demo-crate`, alias `demo-all`
  one release. No MASTER or RAILS caller.
- **No smoke test for the no-arg path.** `DEMO_TRACKS=<one verified>,<one improv>
  BARS=4` into a tmpdir, assert files, LUFS range and exit 0 — needs a render, so
  it runs on a quiet machine.

## dilla — operator decisions

Each changes how a default render sounds. The first is the operator's own
direction of 2026-09-12 and waits only on `dilla.rb`; the rest wait for the
operator's ear.

- **One DNA, devices on.** Fold `ALBUM=1`'s table, `RINGTONE_LAYER` and `DILLA_FULL` into
  `DILLA_STYLE_DEFAULTS` so a single `dilla` render and a demo slot share one
  table: `HOCKET=3`, `LPG`, `COPY_MACHINE`, `VOICE_STACK`, `MIDI_BAG` (predicate
  to `!= "0"`) on; subtractive flags stay; `RENDER_MODE=album` and the other mode
  keys go. Blast radius: `Shared::DillaProcessor` renders in RAILS and its 900 s
  timeout. Gate on a 16-bar MixScore inside the keepers.
- **Demo evenness.** `DEMO_STEADY` default for the catalogue, a fixed rap
  cadence instead of `DEMO_RAP_EVERY=2`, `DEMO_TECHNO_SHARE=0.34` (a second
  renderer in one wav), one tonic family across parts, a BPM band or pulse-aligned
  joins, device rotation on coprime periods, real images for `WAV_MAP` instead of
  the generated mandelbrot.
- **Engineer colour, sourced.** Tempo-relative bus-compressor release that keeps
  LRA (Cooley/STC-8), cassette on some album grades with air at 0, a 40 Hz
  kick-gated oscillator and SPX900-style Symphonic on the dug loop (Fairall),
  independent 2nd/3rd/tape harmonic amounts on the master (HEDD), EQ before
  compression and a slow, gentle start (Daddy Kev).
- **Harmony languages.** An `esen_parallel_dorian` language (parallel m11 cells,
  common-scale-tone lead, same-function half-step resolution, fast harmonic
  rhythm) with its own HarmonyScore profile; one `delay_tension!` operator for
  Bach 4–3 and the Dilla hang; `THEORY_BACH` and the Dilla pedal gated by
  language tag instead of track-name regex and `VOICING=drop2`; Picardy and
  Neapolitan on Bach languages only; cap borrowed-chord surprises at one per cell.

## dilla — unbuilt opt-in devices

None exists as code, so none can be wired; each wants `dilla.rb` to read its knob,
the CopyMachine shape (`plan` → `describe` → `build!`, tests on the plan), and a
16-bar probe. Refused proposals are recorded at the end of "A hundred livesets" below,
and connecting existing devices to livesets is that section's list. In order of
leverage:

- promote `radio_chop`'s drum stem, which survives only in `scratch/chop_work/`,
  beside its rack in `samples/` (crate policy strips drums, so the operator says
  whether);
- `MIDI_BAG_TIMING=hats|kick|lead|chops` and a velocity morph;
- `GRANULAR=file` scan of a dug loop (scan position, grain size, spray; pitch held);
- a spectral resonator snapping partials to the sounding chord;
- a modal (Rings-lite) resonator on a chop;
- a named warp family on the crate (beats, tones, texture, re-pitch, complex);
- then wavefolder and 2-op FM on AnalogSynth, PitchLoop-style delay-line
  pitch, crate-sourced IR, wav_Map path morph and mip-mapped tables, MIDI
  transforms (strum, ornament, recombine, chop, note chance), weighted-next-section
  follow actions.
## dilla — a hundred livesets

Written after the three sets in `lib/livesets.rb` landed, and after the
operator said what the lost Ableton sets were made of: Goldbaby drums, a master
chain of many Sonitex instances and several Nasty VCS on *summing phasy*, one
sweet sample, and Dilla's rule — make old things sound new and new things sound
old. The sets exist to replace a life's work that a robbery took. Three is not a
catalogue, and this is the list of what would make it one.

One fact shapes most of what follows. `dilla.rb` already carries the sound
design: devices (`COPY_MACHINE`, `HOCKET`, `VOICE_STACK`, `LPG`, `BUS_PATCH`,
`WAV_MAP`, `MIDI_BAG`), section maps, four mix buses, a modulation matrix,
hundreds of chord progressions, dozens of track presets, and the support
modules under `lib/`. The three sets reach for about six of its knobs and re-synthesise from
scratch what the engine would have handed them. So a large share of this list is
not *build* — it is *connect*, which is this repo's dominant defect written down
in `MEMORY` as inert config and dead wiring.

**[cheap]** is an afternoon. **[deep]** is a project. **[yours]** is a decision
rather than work. **[risk]** changes a rendered sound and so is not mine to
choose. Numbers are for citation, not for order.

### A · The catalogue: sets to build (1–20)

1. **`vocal_chop_beats.als.rb`** [cheap] — `lib/sampling.rb` already separates
   a vocal stem and refuses any rack that cannot name its source. Thirteen racks
   can. A set built on the voice rather than the instrumental is one new file
   against work already done.
2. **`drum_break_beats.als.rb`** [deep] — `radio_chop` runs `htdemucs_6s` and
   throws the drum stem away. Keeping it gives every record in the crate its own
   break, which is the other half of the sampling tradition and currently
   discarded at the moment it is most expensive to compute.
3. **`two_deck.als.rb`** [deep] — two beds at once. `Rack.grid` already derives a
   tempo from a loop's own duration, so beat-matching two racks is arithmetic
   that exists. A DJ shape rather than a beat: one record under another, one
   leaving as the other arrives.
4. **`interlude.als.rb`** [cheap] — twenty to forty seconds, one idea, no
   arrangement. *Donuts* is thirty-one pieces in forty-three minutes. The sets
   are all ninety-six or a hundred and eighty seconds because that was the first
   number typed, not because anything measured it.
5. **`beat_tape.als.rb`** [deep] — one render containing six linked pieces with
   transitions between them: a side of a tape rather than a track. The unit the
   lost sets probably were.
6. **`remix.als.rb`** [cheap] — `samples/own/` holds nine finished recordings by
   the operator and named collaborators. Every set so far plays other people's
   records. One that plays ours is a different thing to own.
7. **`spoken_word.als.rb`** [deep] — `lib/sampling.rb` exists. A bed under speech
   is the oldest form in the tradition and the one the crate is best suited to.
8. **`jazz_trio.als.rb`** [deep] — `chord_based_beats` voices its chords as
   detuned sines because that was the cheapest honest thing. `lib/harmony.rb`
   and `lib/sound.rb` and the four cached soundfonts exist. The same
   progressions through a real instrument is a second set, not a change to the
   first.
9. **`tape_loop.als.rb`** [deep] — a physical loop degrading each pass:
   `lib/sound.rb` is already written and the set would be the first
   caller that makes its behaviour audible over time rather than statically.
10. **`long_form.als.rb`** [cheap] — twenty minutes rather than three. The pad
    set is already the shape; only `TOTAL` and the swell period stand in the way,
    and a set you can leave running is a different use than a set you audition.
11. **`playlist.als.rb`** [deep] — never ends. ``dilla_live.rb broadcast`` rotates four
    processes with hard cuts between them; a set that crossfades its own
    successor is the thing that was actually wanted.
12. **`field.als.rb`** [yours] — a bed that is a place rather than a record.
    Needs recordings that do not exist yet, and making them is a day out with a
    recorder, which is the cheapest new material this project could get.
13. **`minimal.als.rb`** [cheap] — one voice, no kit, no bed, no console stack.
    Useful mostly as a control: everything else in the room is additive and
    nothing measures what each addition is worth.
14. **`flip.als.rb`** [cheap] — `lib/sampling.rb` chops against chords and is
    one of the engine's better ideas. No set reaches it.
15. **`dfam.als.rb`** [cheap] — `lib/sound.rb` models a semi-modular drum
    voice and is likewise unreached from the livesets.
16. **`gospel.als.rb`** [cheap] — the eight-bar climb specialised: slower harmonic
    rhythm, the climb as the whole arrangement rather than a row sampled out of a
    table of four hundred.
17. **`techno.als.rb`** [yours] [risk] — the crate rules exclude industrial
    techno and the standing goal is a genre-agnostic engine where techno, soul
    and jazz are parameters rather than forks. Those two are in tension and only
    the operator can resolve it.
18. **B-side sets** [cheap] — the same seed through a deliberately different
    room. Costs one environment variable if the console parameters become data;
    see 31.
19. **Tempo families** [cheap] — the beat sets both sit at 82–104 because that
    is where the crate lands after drag. A set at 60 and a set at 140 would say
    whether the room survives outside its comfortable octave.
20. **A set per crate region** [deep] — `project/sample_worth.json` scores every
    rack on seven terms. The sets use only the aggregate. Sets keyed to *voicing
    density* or *chord-register presence* would each sound like a different
    record collection, which is what a shelf of Ableton sets actually was.

### B · The room is sitting on an engine it does not call (21–36)

21. **`COPY_MACHINE`** [cheap] — the bed played six times at once at different
    speeds, with `_FAMILY=harmonic|chromatic|spray`. This is precisely what
    `sampled_based_beats` hand-rolls with `asetrate` and three voices, done
    better, already tested, and reachable.
22. **`VOICE_STACK`** [cheap] — four voices each playing all of it, differing in
    register, tuning and timbre, with a macro that picks a model and a patch from
    212. The pad set's four-interval voicings are a poor cousin of this.
23. **`HOCKET`** [cheap] — one line split across voices with `round_robin`,
    `pendulum`, `shift_register` modes. Nothing in the livesets splits anything.
24. **`LPG`** [cheap] — a Buchla low-pass gate, measured at 17.5 dB more high-band
    fall than body over a decay. It is what makes a note read as *struck*, and the
    chord set's whole problem is that its notes read as *triggered*.
25. **`BUS_PATCH`** [cheap] — a whole modulation patch on a bus: one source per
    destination, depths biased low, at least one inverted, `BUS_PATCH_SEED` to
    pin it. Movement over ninety-six seconds is the sets' weakest dimension and
    this is the built answer.
26. **`WAV_MAP`** [cheap] — a picture read as an oscillator in the track's key.
    Not a gimmick if the picture is a photograph of the thing the piece is about.
27. **`SECTION_LAYERS=full`** [cheap] — the harmony bus leaves in the intro and in
    any breakdown over eight seconds. The sets each hand-roll one volume
    automation across a fixed bar range and call it an arrangement.
28. **`FORM_FIT`** [cheap] — stretch a form across the track rather than cycling
    it, on by default past 64 bars. The pad set at 180 seconds is four intros
    cycling and does not know it.
29. **`DILLA_MIX_BUSES` and `CONSOLE_STACK`** [cheap] — four buses and a summing
    stack measured at 23 dB less third harmonic at three stages than one. The
    sets do their own flat `amix` with hand-tuned weights that had to be
    re-measured by hand this session when the kit changed.
30. **`FROZEN_STATE` / `DILLA_FROZEN`** [cheap] — the engine's own A/B pin. The
    sets grew a parallel seed mechanism because nobody checked whether one
    existed.
31. **Make the console parameters data, not call sites** [cheap] — `Rack.sonitex`
    and `Rack.vcs` are invoked eleven times across three files with literal
    numbers. A named table (`warm`, `dry`, `blown`, `phasy`) turns "which room"
    into a knob, which is what 18 and most of section G need.
32. **`lib/sound.rb`** [cheap] — eight emulations, four of which measuring
    proved dead. The live rack re-implements two of the four that work.
33. **`lib/groove.rb` and `GROOVE_DNA=donuts`** [deep] — `drunk_kit`'s
    jitter figures are hand-chosen constants. A DNA table already describes this
    and would let a set be *in the manner of* rather than *approximately drunk*.
34. **`lib/ledger.rb`** [cheap] — nineteen documented knobs the sets do not read,
    so a set cannot be steered without editing it.
35. **`lib/listen.rb` and the scoring modules** [deep] — `mix_score`,
    `groove_score`, `harmony_score` and `spectral_audit` can each judge a render.
    Nothing judges a pass. A set that scored itself and refused to journal a bad
    take would make the catalogue self-curating.
36. **`RINGTONE_LAYER` and `PAD_LAYERS`** [cheap] [risk] — known-good layers with
    known switches, unreached from the livesets.

### C · Drums (37–46)

37. **Run `lib/sampling.rb`** [cheap] — it cuts a kit from `samples/own/` by
    running demucs and keeping only the drum stem. It has never been run: there is
    no `provenance.json`, and `samples/drums/custom/` is the downloaded
    `03-soulful-vintage`. Our own drums are one command away and beat re-buying
    anything.
38. **Re-acquire Goldbaby** [yours] — nothing on this machine is named it. The
    licences presumably survive the robbery even though the sets did not; the free
    packs would do to start. This is the single named ingredient of the lost
    chain that is simply absent.
39. **More than one sample per role** [cheap] — `LIVE_KIT` plays one `kick.wav`
    for every kick in the piece. Real machines and real drummers do not repeat a
    waveform, and round-robin over a folder is the difference between a kit and a
    trigger.
40. **Velocity, not just position** [cheap] — `drunk_kit` jitters *when* a hit
    lands and never *how hard*. Dilla time is both, and the level dimension is the
    one that reads as a human.
41. **Ghost notes from the snare recording** [cheap] — a ghost is a quiet short
    snare, not a separate file. Deriving it would remove a role from `KIT_ROLES`
    and make more kit directories qualify.
42. **The two-kick habit** [cheap] — the engine already alternates a second kick
    body (`kit[:ind_kick]`). The live rack does not.
43. **Kit-aware mix weights** [cheap] — the sampled bus gain was matched by
    rendering and measuring, by hand, once. A calibration step that measures each
    kit on install and stores its trim is the version that survives a new kit.
44. **Swing that is not jitter** [cheap] — the hat pattern adds a flat 34 ms to
    odd steps. That is a swing setting, the exact thing the comment above it says
    this is not.
45. **Name a `DRUM_LOOP` replacement** [yours] [risk] — it currently falls back to
    `~/Downloads/techno_drums.mp3`, outside the repo and against the crate rules.
46. **A kit from the crate itself** [deep] — every rack has a discarded drum stem
    (see 2). A kit cut from the same record as the bed would glue in a way no
    imported kit can.

### D · The crate, and not losing it twice (47–58)

47. **Record the source URL at fetch time** [cheap] — forty-one of forty-two
    sources are gone with no URL anywhere. This is the same failure that took the
    Ableton sets: irreplaceable material with no way back. It is a one-line change
    and it is the most important item on this page.
48. **Write provenance before the audio** [cheap] — a sidecar written first
    cannot be outlived by what it describes, which is how `henrik_debich` alone
    survived.
49. **Checksum the racks and deduplicate** [cheap] — 161 rows, 123 unique wavs, 38
    phantoms in 28 collision groups. Dropping duplicates is measurement, not
    judgement.
50. **A silence floor on the downbeat measure** [cheap] — the rotation fix for the
    153 mis-cut racks is blocked on this, because a quiet tail currently scores as
    a bar line and one rack starts at −57 dB.
51. **Then rotate the 153** [deep] — content-preserving, since a rack is one whole
    period.
52. **Back the crate up off this machine** [yours] — `samples/` is gitignored by
    path, the renders are gitignored, and the one copy of both is a laptop. The
    robbery is the argument.
53. **A crate manifest that is not the audio** [cheap] — titles, seams, keys,
    worth scores and URLs in one committed file, so a lost crate can be re-cut
    rather than merely mourned.
54. **Dig more** [cheap] — `samples/dug/` holds one file. `dig`, `dig-seams` and
    `dig-cc` exist and work.
55. **Attribution as a build artifact** [cheap] — `credits` exists. A set that
    plays CC-BY material should be able to print what it owes without being asked.
56. **Key-aware bed selection** [cheap] — all 161 racks now carry `key`; nothing
    reads it. Two decks (3) and any harmony over a bed need it.
57. **Retire `sample_worth`'s single number** [deep] — it is seven terms collapsed
    to one, and the collapse is where a set loses the ability to ask for a
    *kind* of record rather than a *good* one.
58. **A rack the operator marked** [cheap] — no way exists to say *this one*. A
    starred flag in the worth table would outrank every automatic score, which is
    the correct hierarchy.

### E · Playing them, not running them (59–70)

59. **A set should not exit** [cheap] — every set renders a fixed block and stops.
    A performance does not.
60. **Change something while it plays** [deep] — the engine already has
    `asendcmd` modulation and a `modulate` command; `MOD_RATE_HZ` names its
    resolution. The live rack builds one static graph.
61. **MIDI in** [deep] — the difference between a generator and an instrument.
62. **A pass you can nudge** [cheap] — drag, kit, weights and drop points are
    all decided before the first sample and cannot be touched after.
63. **Cue the next bed** [cheap] — `pick_bed` chooses once, silently. Being able
    to see and reject the next choice is most of what a DJ does.
64. **Mute groups** [cheap] — kit, bed, phrase, crackle. Four switches would make
    the sets performable with nothing else on this list done.
65. **Tap tempo** [cheap] — the grid is derived from the record. Sometimes the
    record is wrong.
66. **A set that listens** [deep] — `LISTEN_PASSES` exists in the engine.
67. **Two sets at once** [deep] — `broadcast.sh` runs one at a time by design; the
    interesting case is a pad set under a beat set.
68. **Stop cleanly** [cheap] — killing audio this session meant killing processes.
    A set should end on a bar.
69. **A visible transport** [cheap] — bar number, section, next change. The banner
    prints once and then ninety-six seconds pass in silence.
70. **The rig on the box** [yours] — `radio.brgen.no` is the label. A set
    rendering nightly on vm23 into the catalogue is a different project than a set
    played on a laptop, and the capacity ceiling there is real.

### F · Keeping, naming, releasing (71–82)

71. **Every take, not the kept ones** [yours] — `--keep` is opt-in and a good pass
    is recognised after it has gone. Ring-buffering the last ten renders costs
    disk and no decisions.
72. **A take is not a wav** [cheap] — `renders/live_<seed>/` holds an ignored wav
    and a tracked json. That asymmetry is right and should be stated somewhere a
    reader finds it.
73. **Replay verification in the suite** [cheap] — three determinism defects were
    found this session by rendering one seed twice and comparing hashes. Nothing
    stops a fourth.
74. **Name the takes** [cheap] — a seed is not a title. `dilla` already generates
    track names.
75. **Stems** [cheap] — `VOICE_STACK_STEMS` exists for the engine. A kept take
    that cannot be remixed later is a photograph, not a session.
76. **Export the set, not the audio** [deep] — the thing that was lost was
    editable. A take that reopens as parameters is the only real answer to the
    robbery, and the `.als.rb` naming already claims it.
77. **A catalogue file** [cheap] — `project/liveset.jsonl` is a log. A catalogue
    is the subset worth keeping, in order, with titles.
78. **Mark the three that must not be shared** [cheap] — the existing label rules
    already distinguish them and the live rig knows nothing about it.
79. **Loudness for the destination** [cheap] — every set ends in `dynaudnorm` and
    a limiter at a hand-picked `volume=`. Integrated LUFS is a solved measurement
    and lies about speech over music, which matters for 7.
80. **A sleeve** [yours] — `STUDIO/postpro` grades images and `repligen` generates
    them. A catalogue with covers is a release.
81. **Publish the tracklist** [yours] — `radio.brgen.no` exists and is empty of
    this.
82. **Delete nothing automatically** [cheap] — the scratchpad sweeps audio, and a
    long render that lands there is gone. Renders must be written outside it and
    be resumable.

### G · The master chain, against the one that was lost (83–92)

83. **Verify `vcs` against the plugin** [yours] — `Rack.vcs` is `aphaser` into
    `aecho` and was written toward *summing phasy* from description alone. Nobody
    has A/B'd it against the real thing, and the operator is the only person who
    can say whether it is close.
84. **Count the instances honestly** [cheap] — the sets run five or six Sonitex
    stages and five or six VCS stages. *Tons* was the word used about the lost
    chain. Whether more is more here is measurable and unmeasured.
85. **Order matters and is unrecorded** [yours] — where in the chain each instance
    sat is not something the sets can guess.
86. **Per-channel versus master** [cheap] — the current placement is at every
    summing point, which is defensible and is not what a plugin chain on a master
    bus does.
87. **Gain staging as a measurement, not a constant** [cheap] — `vcs` carries a
    `volume=1.9` makeup that exists because three instances were throwing away
    22 dB. That is the right fix and the wrong form: it should be derived.
88. **`sonitex` runs its crusher at half strength** [cheap] — `acrusher` defaults
    `mix=0.5` and `Rack.sonitex` never sets it, so all eleven stages are fifty per
    cent dry. Whether full strength is better is an ear question; that the knob
    was never turned is a fact.
89. **The 1260 is a sample rate as much as a bit depth** [deep] — `acrusher` also
    carries `samples` (1 to 250, currently 1, meaning off) and an `lfo`. Bit
    reduction alone is the cheapest third of what a 12-bit sampler does.
90. **Tape before the console** [cheap] — `lib/sound.rb` is written and
    unused in the livesets, and tape is where the lost chain's *old* came from.
91. **A dry control** [cheap] — no set can be heard without the room. Nothing
    proves the room is an improvement.
92. **Measure THD, not taste** [cheap] — `CONSOLE_STACK`'s documentation cites a
    measured 23 dB figure. The live rack cites nothing.

### H · Instruments before findings (93–100)

93. **Nothing in the suite covers `lib/livesets.rb`** [cheap] — three sets, a shared rack and
    a recall tool, and `grep` over `STUDIO/test` finds no reference to any of it.
94. **A graph that builds is not a graph that sounds** [cheap] — two defects this
    session were empty filter strings from Ruby comments inside line continuations,
    which ffmpeg reported as `No such filter: ''`. A lint over the built graph
    would have caught both before the render.
95. **`aloop` is not reproducible at scale** [deep] — proven at 1.5 million
    samples, fine at 120 000, bisected to the filter. The workaround is in
    `ambient_pads`; the boundary is unknown and the other sets sit on the wrong
    side of not knowing.
96. **Every generator needs a seed** [cheap] — `anoisesrc` seeds from the clock.
    One audit over the tree for unseeded sources would close the class rather than
    the instance.
97. **PRNG draw order is an interface** [cheap] — adding a `rand` above an
    existing one silently invalidates every journalled seed. Nothing states this
    and nothing tests it.
98. **A/B by rendering, always** [cheap] — the kit change was verified by
    rendering seed 777 against `HEAD` and comparing SHA256. That is the standard
    and should be a script rather than a habit.
99. **Level-match before judging** [cheap] — the louder arm wins every informal
    comparison, and three of this session's comparisons needed a measured trim
    before they meant anything.
100. **Ask what the lost sets sounded like, in more detail** [yours] — tempos,
    lengths, whether any were performance sets rather than beat sketches, what a
    typical one had on its channels. Four sentences from the operator are worth
    more than any twenty items above them.

### What the engine refuses

These were proposed by the Ableton, ringtone.tools, KVR and harmony intakes of
2026-09-12 and are settled. dilla does not port Plaits: sixteen engines beside
AnalogSynth, DFAM and WavMap would be a second synthesiser, so VoiceStack models
resolve to the patch catalogue instead. It does not become a Max for Live device,
host a plugin, vendor a C++ Rings, or extend the note-event contract for MPE,
because every renderer reads that contract and the musical need is met by
ornament, LPG and VoiceStack drift. Neural synthesis is out while a take must
reproduce from its provenance. A second tape model, a second SP-1200, a third
thickener, a Generate panel, a hanging-note stopper for an engine with no
note-off, particle sequencers, attractor oscillators and monitor-controller
emulation all duplicate something here or solve a problem this engine does not
have. MixScore keeps its keeper range of −18 to −15 LUFS against the beat-scene
−8.5 target, negative harmony stays blocked, Coltrane changes stay a language
rather than a beautifier, a supersaw lives only behind warp, and wav_Map never
becomes the default pad. The deleted industrial `afftfilt` chain comes back only
with a caller and a test.


## Reasoning OS Implementation - Remaining Debt
- [ ] Resolve  violation (+1502)
- [ ] Resolve  violation (+6)
- [ ] Resolve  violation (+8)
- [ ] Resolve  violation (+6)
- [ ] Resolve  violation (+1)
- [ ] Resolve  violation (+1)
- [ ] Fix  slack (-1)

## Reasoning OS Implementation - Remaining Debt
- [ ] Resolve `spine.lib_body_ceiling` violation (+1502)
- [ ] Resolve `self_findings.law` violation (+6)
- [ ] Resolve `code_reach` violation (+8)
- [ ] Resolve `sprawl.lone_dirs` violation (+6)
- [ ] Resolve `sprawl.vague_names` violation (+1)
- [ ] Resolve `entrypoints.master` violation (+1)
- [ ] Fix `data_reach` slack (-1)
