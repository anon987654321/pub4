# pub4 backlog

The single backlog for the repo. Authority: `MASTER/data/soul.yml` >
`MASTER/data/rules.yml` > root `CLAUDE.md` > the per-tree contract. Feature
truth is `RAILS/apps.yml`; aspiration is `RAILS/apps.horizon.yml`; rationale is
`MASTER/DECISIONS.md` and `OPENBSD/DECISIONS.md`. A record is deleted when it
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
  `SILENT_RESCUE` sites; folding the eight files of `STUDIO/dilla/live/`.

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
  `master`-owned.** A root `assets:precompile` in `rc_pre` could build a
  container through `cable_bridge.rb` and spawn the worker as root;
  `MasterContainerLoader.ensure!` now refuses under an assets task. If the logs
  turn root again, the writer is elsewhere.
- **Deploy hazards.** Never stash the box's locks to fast-forward; a plain
  `git pull --ff-only` succeeds with them dirty. relayd has died mid-deploy with
  every app port open (`curl 000` on all hosts), so run `rcctl check relayd`
  after any deploy that restarts master.

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

- **The crate holds `drums`, `dug`, `own` and `rauingar`, and no 124 racks.**
  `74d9e4c1b` cleared it on 2026-08-16 on the operator's call; only he can say
  whether he expected the racks back. `samples/dug/` is down to one record, and
  the other 160 sources cannot be re-fetched to the same bytes.
- **Which crate layout survives.** The engine reads `samples/chopped/loops.json`
  through `RadioChop.registered_loops`; `lib/crate_dig.rb` writes `samples/dug/`
  from public-domain archives; `live/dig_crate.rb` rips YouTube and warns on every
  run; `bin/crate` declares a `crate/` layout that no longer exists.
- **`ruby STUDIO/dilla/dilla.rb assets` exits 1**: three loops missing, eight files
  changed (seven re-synthesised one-shots, and the `rauingar` re-cut).
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
  default, and raising the base is a mix value (`composition_engine.rb`).
- **Chop rows in `TRACK_PRESETS`**, when there are chops again. A slug with no row
  falls through to `:timeless`; the `sheger_*` derivation in `dilla.rb` is
  mechanical and whether it sounds right is his.

### Blocked while `dilla.rb` is under another session's edit

- **Classify dilla's default-off flags** into additive, exclusive fork and
  operational, and delete the dead ones. `lib/knobs.rb` is the instrument (727
  knobs, 286 flags, 206 default-off); the counts in `dilla.rb`'s own comments
  are stale.

### Guards

- The eight `sheger_*` rows are half alive: the preset rows are live and tuned,
  the bed aliases point at a cleared chop. A test pins both halves; delete
  neither.
- The monolith stays. `DILLA_SUPPORT_CEILING` (56, any depth) leaves no room for a
  destination file, so any split starts by folding support code, and 14 support
  files use `__dir__`/`__FILE__`. `dilla parts` indexes the engine.
- Not worth chasing, each measured: folding `dilla/live/` (three arrangements,
  and renames break journal replay); merging the three techno renderers (three
  sounds); blanket rescues in STUDIO (optional probes and teardown); preset reach
  in `postpro`/`lora` (selected by name from argv; `vocab_check` owns it); the 37
  stale `sample_worth.json` slugs (pruned on the next chop); the sample rate
  declared under three names (all namespaced; `sample_worth.rb`'s 11,025 is
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

## The refinement inventory — opened 2026-09-11

`ruby MASTER/tools/refinements.rb` scans every tracked file in the four trees
and groups what it finds into batches: one rule, one kind of edit, a known file
list. `--items` prints every finding, `--tree` and `--rule` narrow it. The list
is not written down anywhere, because a written copy of a scan is stale the day
it is made. Run the tool.

It reads **22,417 findings in 3,333 files across 131 groups**, and that number
is an upper bound on an unverified instrument, not a count of defects. Thirty
were sampled and read against their source. Roughly a quarter were actionable.
The rest were the scanner misreading correct code, and the misreadings have
shapes worth naming, because each one is a rule to fix rather than a file:

- `magic_number` (4,492) counts array-slice bounds, quantifiers inside a test
  assertion's regex, and event codes. `[0, 200]` is not a constant wanting a
  name.
- `NO_PUTS` (807) counts CLI tools, rake tasks and probe scripts, where `puts`
  is the interface rather than a debug statement.
- `duplicate_code` (784) counts locale YAML values, Markdown prose and
  comments. "Text to copy" appearing twice in `en.yml` is a translation.
- `FILE_SPRAWL` (664) and `SMALL_FILES` (261) report a per-directory condition
  once per file, anchored to line 1, and count migrations — which accumulate by
  design.
- `CONFIG_HIERARCHY` (913) counts route fragments in gate flow fixtures and
  prompt template lines in `council.yml`.
- `TYPOGRAPHY_DISCIPLINE` (474) counts ASCII box drawing inside comments, which
  is `NO_ASCII_LINE_ART`'s question and cosmetic in a comment either way.

**The exemption marker trips two rules by existing.** 154 findings sit on lines
carrying `scan: intentional`, and 135 of them are `LONG_LINE` and
`TRAILING_COMMENT` — the marker is a trailing comment, and adding it pushes the
line past the length limit. Every author who exempts a line correctly buys two
new findings. Fix the two rules to skip a line whose only overage is the marker
itself, and the count falls without a single file being touched.

### The deterministic tier — 1,888 findings in 607 files

These are the ones worth working. Each is mechanical, each has one right
answer, and a wrong fix shows itself in the diff it makes. One group is one
session. Counts are findings, then files, which is the number of jobs.

- **`TRAILING_COMMAS` — 489 in 188 files.** RAILS 432. Add the comma to the
  last element of each multi-line literal. Autofixable: `add_trailing_commas`.
- **`TAB_CHARACTER` — 322 in 8 files.** OPENBSD 315. Eight files, whole-file
  conversion each.
- **`DOLLAR_PAREN` — 287 in 60 files.** Backticks to `$( )` in shell scripts.
- **`DOUBLE_BRACKET` — 181 in 8 files.** All OPENBSD. `[[ ]]` to `[ ]`, so the
  script runs under `sh`. This one matters on the box.
- **`FROZEN_STRING_LITERAL` — 176 in 176 files.** One magic comment each.
- **`NO_ASCII_LINE_ART` — 175 in 48 files.** STUDIO 94. Keep the words, delete
  the box.
- **`NO_COLUMN_ALIGN` — 143 in 31 files.** MASTER 103. Collapse aligned columns
  to single spaces.
- **`NO_GOD_CLASS` — 29 in 29 files.** RAILS 22. Not mechanical, but each one is
  a class that has outgrown a single subject and already shows the seam.
- **`SILENT_RESCUE` — 23 in 11 files.** STUDIO 22. `Ground::Swallow.log` is the
  house form.
- **`STRICT_MODE_ZSH` — 18 in 18 files.** OPENBSD 15.
- **`NO_VAR` — 15 in 7 files.** `let` or `const`.
- **`NEVER_BATCH_DELETE` — 13 in 9 files.** Read each before touching it; some
  will be correct and want the marker instead.
- **`FAIL_VISIBLY` — 5 in 5 files.** A failure reported into a return value that
  nobody reads.
- **`RATE_LIMITING_MISSING` — closed, 1 of 4 was real.** `Tv::VideosController#create`
  takes a video upload and had no throttle; it has 10 in five minutes now.
  The other three were the rule reading file scope: `shared/authentication.rb`
  and `dating/base_controller.rb` declare no actions at all, and the login and
  password paths throttle through `sessions_actions.rb` and
  `passwords_actions.rb` — 10 in three minutes, and 3 in fifteen for a magic
  link.
- **`MIGRATION_ADD_REFERENCE_NO_FK` — 1 of 2 was real, and it needs a new
  migration.** `add_reference :reactions, :reactable, polymorphic: true` cannot
  carry a foreign key, so that one is the rule misreading a polymorphic
  reference. `add_neighborhood_to_dating_profiles` could, but the migration has
  run on vm23 and an edit to a migration that has already run changes nothing —
  the fix is a new migration, and it wants a check for orphan `neighborhood_id`
  rows before the constraint goes on.
- **`NO_DEBUG` — 2, `CONTROL_CHARS` — 2, `NULL_BLINDNESS` — 2.** Three edits.

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

## What the snapshot gate was really reporting — closed 2026-09-11

`rendered_suite` failed on sixty-nine surfaces, every one of them
`LayoutSnapshotGate`, against baselines last written 2026-08-17. The obvious
reading was twenty-five days of unreviewed drift. It was not: the gate was
comparing against a key format that no longer existed.

`walk.js` was extracted from a Ruby heredoc into a file read verbatim, and
three regexes came with their heredoc escaping intact. In a heredoc `\\s` is
what you write to get `\s`; in a file read as bytes it stays two characters,
and `/\\s+/` in JavaScript matches a literal backslash followed by one or
more letter s — which nothing on any page contains. Verified in Chrome rather
than argued: `"brand-mark brgen-logo-mark".split(/\\s+/)` returns the whole
string as one element, and `/rgba?\\(...\\)/.test("rgb(1, 2, 3)")` is
false.

The one that mattered was in `classSig`. The class attribute was never split,
so every element carrying more than one class keyed as
`a.brand-mark brgen-logo-mark` instead of `a.brand-mark.brgen-logo-mark`, and
`VOLATILE_CLASS` matched the whole blob or none of it — which is why
`body.vertical-marketplace` vanished from ancestor paths whenever the blob
happened to end in a volatile word. 739 removals and 965 additions across 69
surfaces, none of them a layout change. Fixing it halved the removals
immediately and moved elements into the MOVED bucket, where they belong: the
instrument now compares like with like.

The other two broke the rgba fast path, which falls through to a canvas that
answers correctly — slow rather than wrong, and invisible for exactly that
reason. `gate_requires_resolve_test` now fails on a literal `\\` in any
`.js` file under `gates/`, because the next extraction will do this again.

What remained after the fix was real and all of it attributable: the edge
grips and `#q` went with the rails and the search palette (operator,
2026-08-27), the nav swiper groups went flat (operator, 2026-08-29),
`#app-tab-bar` moved because dating and messenger left the immersive list on
2026-09-11, and `#logo` went with the storefront's second wordmark the same
day. The six content-level changes were all improvements: maps gained an `h1`
where it had none, and messenger's title went from "Bergen" to
"Meldinger — Bergen". Baselines regenerated after that review, and after the
instrument was fixed — in that order, because accepting them first would have
written the corrupted key format into all sixty-nine files permanently.

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

## The external reassessment — assessed 2026-09-11

Four ChatGPT logs and one execution brief, read against the tree rather than
taken at their word. Three of the four logs were substantially wrong about what
`main` contains, which is the usual shape: an external reader with repository
access describes the repository it last saw. What follows is what survived being
checked, and what did not, so neither half is re-derived.

### What was wrong, and stays closed

**The visibility test is not missing.** One log opened on the claim that
`MASTER/test/test_visibility_semantics.rb` had been lost from `main` while
`data/spine.yml` still sponsored it, and proposed restoring 109 lines of it. The
file is on `main`, 140 lines, with all eight semantic cases the log listed —
`public` reopening a scope, `protected` as a visibility rather than an end,
`private` not reaching the singleton stream, `private_class_method`, retroactive
named visibility, inline modifiers, `class << self` defaults, and another
object's singleton. Nothing to restore.

**`Core::Constitution` should keep reading `rules.yml` directly.** The proposal
was to replace its `YAML.safe_load_file` with `Master.load_rules`, on the
one-source argument. The one source is real and the fix is backwards: the class
comment two lines above states the spine reaches nothing in `lib/`, and
`load_rules` lives in `lib/boot/data.rb`. Taking the suggestion would invert the
only dependency rule `core/` has, to buy a size limit on a 205 KB file, a
timeout on a local read, and permitted classes for a file that holds no `Date`.
`load_rules` performs no shard merge, so the two paths already return the same
object. Recorded in `MASTER/DECISIONS.md`; do not reopen.

**Cognition phases 3 through 8 are premature.** A log proposed eight phases —
prediction, global workspace, thought generation, consolidation, dreams, goals,
agency, beliefs, an HDC accelerator in Rust — as a staged programme over
`lib/cognition/`. Phases 2A and the tick defect below were real and are done.
The rest builds six new subsystems on a layer whose own loop had never run, and
`COLLAPSE_BEFORE_ADDING` asks for the nine moves before any of them. Revisit
when the persisted transition model has weeks of real event history in it and
something in the tree reads it.

### Open, sized, and real

**The local tier's model list is a guess.** `OllamaSender` dispatches now, but
`models.yml` names `qwen2.5-coder:7b`, `llama3.2:3b` and `phi4:mini` as the
tier-D chain and nothing checks that any of them is pulled — a missing model
reports cleanly as `ollama has no model <name>` and then the chain falls through
to a paid provider. Either pull those three on the machines that enable the tier
or have the chain read `/api/tags` and rank what is actually there. The second
is the one that cannot go stale.

**`Finding#reversibility` and `#blast_radius` still have no reader.** Both are
first-class fields on `Finding`; only `meta_rules.rb` ever sets them and nothing
in `lib/fix/` reads either. The review that raised this called it the whole of
autofix safety and was wrong about that — `Scanner#should_autofix?` and
`AstFixer::DELETING_TRANSFORMS` decide by what a transform *does*, which is the
better question, and both autofix paths consult it now. What remains is the two
unread fields: either give them a reader or delete them, because a declared
field nobody reads is this tree's most common defect and these two have been
sitting in the constructor since they were added.

**Exemptions are measured now, and the corpus is clean.** `ruby
MASTER/tools/stale_exemptions.rb` reads 143 markers in 90 files and every one of
them holds back a finding. The one that did not — `_root.scss`, a marker on the
tail line of a multi-line comment whose subject no rule flags either way — was
deleted with its rationale kept. The tool still reports `web_rules.rb:77`, which
is prose quoting the marker rather than using it, and is disclosed as a known
false positive in its own header.

Run it after a rule narrows or retires. That is when an exemption goes stale, and
nothing else will say so.

**No gate measures engine boundaries.** One intentional cross-engine constant
reference exists — `maps -> Takeaway::Order` — and zero cross-engine
associations. A source gate should detect constant references and model
associations across `RAILS/brgen/engines/`, carry that one as a named exemption,
and fail on the second unreviewed crossing. No Packwerk, no native dependency,
for one check.

**i18n has resolution checks and no hygiene checks.** The locale tests cover
duplicates, homes, naming, parity and resolution. Unused keys and
interpolation-variable parity between locales are both unmeasured. Build it on
this repo's own search machinery: six mounted engines make a generic
`i18n-tasks` configuration likely to misread the tree.

### Operator-owned, recorded not opened

Each of these needs the box, money, or a rendered decision, so they are named
rather than done.

- **relayd restart churn.** The deploy path restarts relayd whenever an
  individual app comes back healthy, which drops the single HTTPS listener for
  every other app and has already caused an outage. Read `relayd(8)`,
  `relayd.conf(5)` and `relayctl(8)` from vm23 first; the likely shape is table
  disable/enable rather than a daemon restart, with a genuine config change still
  reloading properly.
- **Per-process resource evidence.** `resource_guard.sh` sheds on aggregate box
  load, so the log never says which process took the memory. Add per-process RSS
  for the managed services, record an exited process as unavailable rather than
  zero, and change no threshold in the same patch.
- **Service resource limits.** The Rails `login.conf` class permits a datasize
  larger than the physical box. Capture steady-state and peak RSS on vm23 first,
  and open-file usage before touching `openfiles-cur`.
- **Off-host snapshots.** Backups are same-disk and the restore path points
  somewhere unusable. The destination and retention policy are the operator's;
  what is buildable is the contract, the verification, the restore drill, and
  backup freshness in `/health`.
- **TTS daemon ownership.** Worker logs and sockets can be created as root while
  the daemon runs as `master`. Find the writer before adding a periodic chown,
  expose `tts_socket` in `bin/operator vps state --remote`, and make health
  distinguish process-up from socket-usable.
- **The multi-platform Bundler lock.** vm23 carries a hand-repaired
  `MASTER/Gemfile.lock` whose checksums differ from the committed one; the cause
  is the BSD-only dependency in `MASTER/Gemfile` and the fix is `install_if`. A
  deploy-window change, in order: repair the Gemfile, regenerate on both
  platforms, verify frozen Bundler, verify TTS, deploy, restart master, verify
  `/health` and relayd, then close.
- **The face's shader brightness floor.** Probe the live face at production
  defaults against the README-sized render and change the shader, not a
  recorder-only uniform. A rendered value: bring the number back for a decision.
- **The accent question.** Render the front page, marketplace, takeaway, dating,
  TV, Amber and MASTER with and without the vertical accent, compare interactive
  affordance, and encode the winner as a token and a gate. One decision, not
  another abstract colour discussion.
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

## In-depth refinement and micro-refinement opportunities — opened 2026-09-11

Measured against MASTER, RAILS, OPENBSD and STUDIO on 2026-09-11. A finding is
a hypothesis; re-measure before working. This list does not restate the scanner
inventory (`ruby MASTER/tools/refinements.rb`), the deterministic tier already
in this file, operator-priority box work, or anything decided against in
`MASTER/DECISIONS.md` / `OPENBSD/DECISIONS.md`. Rendered values, money, a
registrar login and a vm23 console are named and left.

Each item names a path and a move. Items flagged **unverified** were opened far
enough to name and not far enough to assert. Sample five, open the five lines,
and decide whether the instrument is right before opening the sixth.

Already open above and not restated: Gemfile.lock `CHECKSUMS` / `rb-kqueue`,
TTS log ownership, `tts_socket` on `vps state`, `secrets_rotation`, `rule_deps`
136, exemption-expiry detector, per-rule autofix classification, one chrome,
marketplace 500, layout_snapshot drift, crate backup / `off_host_dr`,
`libvips_local_build`, `multi_app_ram`, history rewrite, `bsdports.org` parking,
relayctl instead of relayd restart, `growth.rails` source/test split.

Fenced throughout: folding `dilla/live/`, splitting `dilla.rb`, merging techno
renderers, changing a rendered look or sound, enabling litestream, Solidus on
SQLite, pgvector, inbound ActivityPub storage, WebRTC, three sign-in methods,
`shared/lib/operator` nesting, LAYER_CAKE / DEAD_ABSTRACTION, raising a ratchet
to absorb growth, `emotion.rb#analyze`.

Numbered 1–N across the four trees.

### MASTER — dual sources and inert config

1. **Fixed 2026-09-12.** It named `lib/master/tools/`, a directory this tree has
   never had. The adapters are the classes `lib/builder.rb`'s `DEFAULT_TOOL_MAP`
   builds, which live in `lib/io/`. The one place a reader would look to answer
   "where does the behaviour live" sent them nowhere.
2. **Repligen/Postpro declared, never constructed.** `data/tools.yml:32-33` list them; `lib/builder.rb:16-53` has no factories. CLI shells STUDIO. Add factories or drop the rows.
3. **Fixed 2026-09-12, and it was nine, not one.** Every `source: docs/<name>.md`
   in `runtime.yml` — nine of them — named `MASTER/docs`, which does not exist.
   `why_explainer.rb:116` prints that value to the operator as provenance, so each
   showed a path that has never resolved for whoever read it. Not a broken link
   either: `3797afea7` is "Codify MASTER docs into runtime catalog", so those
   documents were folded INTO this file and the pointers outlived the files by
   becoming the file they pointed at. Removed rather than repointed, with the
   provenance stated once in the header.
4. **False — checked 2026-09-12.** The Pixel Field is not deleted:
   `particle_kernel.js` is live and declared at `web/config/face_assets.yml:70`,
   which is the manifest the shell loads. `topologies.yml`'s header describes what
   the tree actually renders.
5. **Palette keys contradict one chrome.** `topologies.yml:34-42` operator/review/visitor palettes. Mark canvas-only and test that chrome does not read them, or delete.
6. **`START_HERE.md` has a broken sentence.** `:142` “…`yml` (active read-modify-write…” — the filename was eaten. Restore the stem or cut the clause.
7. **`START_HERE.md` still defends deleted YAML.** `:147-150` discusses `visual_clusters.yml` / `mobile_web_opportunities.yml`. They were deleted 2026-08-11. Move the paragraph to DECISIONS.
8. **Three files, one voice string.** `soul.yml` `voice:`; `voice.yml` `neural:`; `tts.yml` for the engine. One reader (`Voice::Policy`) should own the string; the others cite it. The 2026-09-12 move to `en-US-JennyNeural` touched fourteen files to change one value, which is the cost this entry names.
9. **`limits.yml` still titled Tier 1 Law in START_HERE.** `:170`. `limits.yml:1-18` is explicit that most of it is unread `guidance:`. Retitle START_HERE to match `test_limits_split.rb`.
10. **`project_context.yml` names `MASTER/exe/tts-worker`.** `:36` — worker is `MASTER/bin/tts-worker`.
11. **`project_context.yml` still lists `visual_clusters.yml` as a fold exception.** `:27`. Remove.
12. **Already done — checked 2026-09-12.** `MASTER/data/claude/` does not exist and
    `lib/ground/memory_index.rb` no longer names it.
13. **`data_reach.yml` 28 unnamed keys.** Including `runtime.yml#cognitive_spine`, `soul.yml#evolution_log`, `topologies.yml#palettes`, `models.yml#ollama_*`, `personas.yml#british`, `providers.yml#mistral`. For each: find a reader or delete. Do not build a repo-wide unread-key gate.
14. **`reader_singularity.yml` still allows 10 readers of `rules.yml`.** Collapse remaining readers onto `Master.load_rules` / `Master.law`.
15. **Dual constitution classes.** `lib/ground/constitution.rb` vs `lib/core/constitution.rb`. Rename Ground’s to `PrincipleStore`.
16. **Dual memory search.** `lib/ground/memory_search.rb` vs `lib/ground/memory/search.rb`. Rename the index one `DocIndexSearch`.
17. **Three mood systems.** `lib/pressure_engine.rb`, `lib/trace/context_pressure.rb`, `lib/cognition/affect.rb`. Document which bus events each consumes, or fold PressureEngine into Cognition.
18. **Dual attention.** `lib/cognition/attention.rb` vs `lib/cli/attention_context.rb` vs `data/attention_context.yml`. One table of weights.
19. **`bootstrap.yml` vs `bootstrap_docs.rb`.** Both mention `/tail` `/replay`. `/tail` is not in `CommandRegistry.build`. Confirm callers.
20. **Fixed 2026-09-12.** The `planned:` block already said nothing reads it; it now
    also says what does answer — Falcon on 53187, declared in `web/` and forwarded by
    relayd — and that nothing has ever listened on 18789.
21. **`PATH_OWNERSHIP.yml` owns missing dirs.** `docs:` and `reports:` — neither exists. Delete the keys. **Fixed 2026-09-12 by Copilot.**
22. **`PATH_OWNERSHIP.yml` omits live dirs.** No entries for `lib/cognition/`, `lib/pressure_engine.rb`, `law/`, `AEGIS.md`, `COGNITION.md`, `EXAMPLES.md`. Add them. **Fixed 2026-09-12 by Copilot:** `law/` already had an entry; the remaining live paths now declare their purpose and check.
23. **`PATH_OWNERSHIP.yml` `tools/` check is a source-grep spec.** `:179` `spec/lifecycle_tools_spec.rb` asserts `bin/doctor` contains `"check_yaml"`. Point the check at a real tool test. **Fixed 2026-09-12 by Copilot:** the doctor case now runs the CLI and asserts its emitted YAML probe result.
24. **`data/tools.yml` `name:` vs `Master::Io::`.** Header says `Master::Tools`. Runtime is `Master::Io::ReadFile`. Align the namespace. **Fixed 2026-09-12 by Copilot:** both headers now name `Master::Io`.
25. **`RuntimeCatalog.load("tts_phrases")` vs `data/tts.yml`.** Confirm `tts_phrases` exists in a catalog `sections` list (`runtime_catalog.rb:20-24` already records a miss). **Closed 2026-09-12 by Copilot:** `RuntimeCatalog.sections` reads live `data/runtime.yml` keys, which include `tts_phrases`, and `test_ground_runtime_catalog.rb` asserts the section.
26. **`DATA_ALIASES` vs filenames.** Audit `lib/boot/data.rb` aliases against files on disk. **Closed 2026-09-12 by Copilot:** the aliases live in `lib/ground/rules.rb`; `workflow` resolves to `limits.yml`, `ruby_style` and `rails_stack` resolve to `rules.yml` sections, and `standing_orders` resolves to `state.yml`.
27. **Confirmed and left, 2026-09-12.** `soul.yml:65` does list `bin/cli`. That file
    is `paths.immutable` and outranks everything: an effect must not write it, and
    neither should I. The change is the operator's, and it is one line.
28. **`soul.yml` `anti_simulation.forbidden: [will, would, could, might]`.** If the detector is lexical it is noise; if unused it is inert law.
29. **`models.yml` ollama rows unnamed.** Delete or wire `QuotaGate` / router. **Closed 2026-09-12 by Copilot:** `ModelRouter` selects the env-gated rows and `LLMDispatcher` routes their `ollama:` ids to `OllamaSender`; routing tests pass.
30. **`personas.yml#british` unnamed.** Delete or add to `Personality.persona_names`. **Closed 2026-09-12 by Copilot:** `Personality.persona_names` reads the complete persona registry through `Rules#data(:personas)`; persona and web tests pass.
31. **`providers.yml#mistral` unnamed.** Row or reader, not both silent. **Closed 2026-09-12 by Copilot:** provider configuration loads the full provider registry, including Mistral; provider and web tests pass.
32. **Three lists of council words.** `council.yml` vs `HELP_TOPICS` vs `TurnRouter::MODEL_ALIASES`. One table. **Closed 2026-09-12 by Copilot:** these are different vocabularies with different contracts — council persona aliases, advertised slash commands, and model-generated pipeline aliases. `TurnRouter` documents the deliberate separation; merging them would advertise retired commands and broaden the council panel.

### MASTER — untested lib

33. **`HashDigCompat`.** `lib/boot/hash_dig_compat.rb` prepends `Hash#dig` process-wide. Prove MRI nil-short-circuit vs coltrane’s raise; prove `install_hash_dig_compat!` is idempotent. **Closed 2026-09-12 by Copilot:** `test_master_boot.rb` covers missing intermediate keys, nested lookup, and repeated installation without duplicate ancestors.
34. **`BrainOverlay`.** `lib/cli/brain_overlay.rb`. Test `core_brief` and `load_context` against a planted markdown dir, not empty `data/claude`. **Closed 2026-09-12 by Copilot:** `test_cli.rb` plants nested markdown, verifies the contextual index and matching/missing loads, and checks the Ruby-policy core brief.
35. **`ResyncService`.** `lib/cli/resync_service.rb` — `git reset --hard origin/main`. Dry-run must not reset; live path refused without a flag. **Closed 2026-09-12 by Copilot:** `call` now requires `confirm: true` for live reset, while `test_cli.rb` verifies dry-run fetch/report behavior and refusal without confirmation.
36. **`FixPreviewReport`.** `lib/cli/fix_preview_report.rb`. No test of render shape. **Closed 2026-09-12 by Copilot:** `test_cli.rb` covers clean/skipped output, violation summaries, rule/file sections, and sixty-character file-name truncation.
37. **`DeliberationPrep`.** `lib/cli/deliberation_prep.rb` — `rescue StandardError` at `:17`. No unit test. **Closed 2026-09-12 by Copilot:** `test_cli.rb` verifies ideation exceptions publish `ideation:error` and return `nil` without escaping.
38. **`CouncilCrit`.** `lib/cli/council_crit.rb`. Add focused tests for empty diffs, missing deliberation, veto/pass events, truncation, and runner wiring. **Closed 2026-09-12 by Copilot:** `test_cli.rb` covers all listed paths, including event payloads and container runner dependencies.
39. **`AstEdit`.** `lib/io/ast_edit.rb` — dangerous tool, in `DEFAULT_TOOL_MAP`. No test of Prism edit / governor.
40. **`BatchReplace`.** `lib/io/batch_replace.rb`. Same.
41. **`SearchKnowledge`.** `lib/io/search_knowledge.rb`. No test that it reads `knowledge/` and not `docs/`.
42. **`WebChat`.** `lib/io/web_chat.rb` — Ferrum path from `llm_dispatcher.rb:367`. No test.
43. **`WebSearch`.** `lib/io/web_search.rb` — only the string in `test_tool_profile.rb`. No `Io::WebSearch` call.
44. **`AskLlm`.** `lib/io/ask_llm.rb`. Same: name only in the profile test.
45. **`GitContext`.** `lib/io/git_context.rb`. No test of status/log summary.
46. **`McpCoordinator`.** `lib/io/mcp_coordinator.rb` — booted in `boot_phases.rb:72`. No test.
47. **`DynamicHttp`.** `lib/io/dynamic_http.rb` — SSRF-adjacent. `rescue StandardError` returns `Result.err` (`:37-38`). No test.
48. **`IngressRunner`.** `lib/io/ingress_runner.rb` sets `Fiber[:master_visitor]` / `elevated`. No test that ensure clears fiber keys.
49. **`Io::Clean`.** `lib/io/clean.rb` shells `OPENBSD/dev/clean.sh`. No test that `SCRIPT` exists and timeout fires.
50. **`Io::Tree`.** `lib/io/tree.rb`. No test.
51. **`Io::SymbolLookup`.** `lib/io/symbol_lookup.rb`. No test.
52. **`Io::FeedbackRecord`.** `lib/io/feedback_record.rb`. No test.
53. **`Io::BrgenBridge`.** `lib/io/brgen_bridge.rb` hits `127.0.0.1:38182` with `MASTER_INTERNAL_TOKEN`. No test of missing-token err or non-200.
54. **`Ground::MemorySearch`.** `lib/ground/memory_search.rb`. No test of scoring.
55. **`Ground::MemoryIndex`.** `lib/ground/memory_index.rb`. No test of rebuild against missing `data/claude`.
56. **`UnfinishedLedger`.** `lib/fix/unfinished_ledger.rb`. No test of add/resolve/top.
57. **`HotwireRefactorPolicy`.** `lib/rails/hotwire_refactor_policy.rb`. No test.
58. **`PwaAudit`.** `lib/rails/pwa_audit.rb` — `initialize(root: Master::ROOT)` so a RAILS audit from MASTER root is the wrong tree unless callers pass `app_path`.
59. **`MobilePwaOperator` / `MobileWebClusterCatalog` / `Rails8AppAudit` / `SwStrategy`.** `lib/rails/` — no spec/test names. Test or PATH_OWNERSHIP them as RAILS-only.
60. **`BedrockStub`.** `lib/io/bedrock_stub.rb`. No test that `RubyLLM::Providers::Bedrock` is defined before `ruby_llm` loads.
61. **`PressureEngine`.** Only constructed in `test_master_boot.rb:39`. No test of `ingest` / weather thresholds.
62. **`CLI::Stages::Route#levenshtein`.** `lib/cli/stages/route.rb:53-66` — nested ternary inside `Array.new`. No test of “did you mean”. Split the init loop.

### MASTER — declared, never wired

63. **Command tables built by nobody.** `lib/cli/command_registry/help.rb:11-15` already states it: `memory_commands`, `system_commands`, `media_commands`, `core_commands`, `domain_commands`, `reach_commands`, `agent_commands` are required and never merged into `build`. Wire or delete.
64. **`system_commands` duplicates live verbs.** `system_commands.rb:21-30` redefines `commit`, `doctor`, `pair` that `build` already has. Delete the duplicates from the dead table first.
65. **Second `/commit` is unconfirmed `git add -u`.** `system_commands.rb:51-60`. Even unwired, it is a loaded gun. If kept, require paths.
66. **`dispatch_snapshot` lowercases STUDIO.** `system_commands.rb:69` `File.expand_path("../studio", root)` — tree is `STUDIO/`.
67. **`dispatch_reload` is a stub.** `system_commands.rb:82-84` always `"reload: not supported"`. Session `run_rebuild` actually execs. Two rebuild stories.
68. **Session handlers vs registry.** `command_handlers.rb` implements `run_rebuild`, `run_context`, `run_checkpoint`, `run_verify` outside the closed slash table. `run_verify` hardcodes a 2026-era file list. Register or delete.
69. **`/fold` exists as `core_commands` only.** `TurnRouter::FOLD_SLASH` rewrites `fold`/`run` but `build` does not register `fold`.
70. **Help comment still says `through`.** `help.rb:10`. Rename was `/review`. `completions/_master:6` still completes `through`.
71. **Completions list is the old closed set.** `completions/_master:5-15` — `through`, no `review`/`rules`/`why`/`orders`/`soul`. Generate from `HELP_TOPICS` + `ALIASES`.
72. **START_HERE slash set is short.** `:11-13` lists 9 verbs; `HELP_TOPICS` has more. Add orders/soul/why/rules.
73. **`TurnRouter` still accepts ten pipeline words.** `turn_router.rb:54-70`. Completions and START_HERE should say which four are advertised.
74. **`IntentRouter::INTENTS` is a keyword soup.** `intent_router.rb:6-28`. Add tests for “why isn’t the homepage realtime?” and a plain “review this later” that must stay chat.
75. **`bin/README.md` says `pub4` is the operator surface.** `:6` — the binary is `bin/operator`.
76. **`bin/master-core` survived the two-spine merge.** Fold into `bin/master --core` or keep and give it a test.
78. **`bin/gate` vs `bin/operator gate`.** `bin/README.md` still tells people to run `gate` as if it were the chain. One sentence: do not run `bin/gate` unless debugging the scanner.
79. **Seven diagnose bins overlap.** `check` / `ci` / `audit` / `probe` / `smoke` / `dogfood` / `doctor`. Concrete: `smoke` → `check --profile=ci` subset; `audit` → `operator lint --staged`.
80. **`bin/onboard` / `cleanup` / `handoff` / `playbook` / `reset-costs` / `sync-env`.** No tests except source greps in `lifecycle_tools_spec.rb`. Real subprocess test or fold into `doctor` / `operator`.
81. **Four TTS bins.** `tts-e2e` should be `bin/check --profile=web` or a rake task.
82. **`dispatch_tools` lives in unwired `system_commands`.** `/tools` cannot list tools. Merge that one command if nothing else.

### MASTER — stale comments and names

83. **`EventsController` “Wire into routes”.** `web/app/controllers/events_controller.rb:9-14` — route exists at `routes.rb:26`. Delete the how-to.
84. **`EventsController` talks about “the orb”.** Live surface is the face. Rename in the comment; drop `autoloop:cycle` / `sweep:cycle` unless something still publishes them.
85. **`NO_PUTS` exemption still names `pub4/gate_chain.rb`.** `lib/review/scan/rules/lexical_rules.rb:39`. File is `lib/operator/gate_chain.rb`. The regex does not match.
86. **`FixLoop` “architectures #1–#15”.** `lib/fix/fix_loop.rb:18`. Architecture numbers went with `docs/`. Say what the two tiers are.
87. **`Io::Clean` comment is a changelog.** `lib/io/clean.rb:11-15`. Present-tense: script is `OPENBSD/dev/clean.sh`.
88. **Fixed 2026-09-12.** The paragraph said the guard was paused via
    `/var/db/pub4_all_apps`. That flag does not exist on vm23 and the shed list is
    empty, so the guard has been armed the whole time the doc said otherwise — two
    months of it. It now states that, and points at the script for thresholds
    instead of naming any.
89. **`help.rb` “read-only” vs scan writes.** `:18` vs `:30-32`. Pick one sentence.
90. **`MechanicalAutofix` “`/scan` and `/self`”.** `/self` is a model alias for `/review`. Say `/review --only scan`.
91. **`lib/cli/README.md` still mentions `data/claude`.** `:33`. Empty dir.
92. **Done — verified 2026-09-12.** `mask.js` and the three `mask_*` files are off
     disk and nothing loads them. The two textual matches left are a different
     thing: `visual_bridge.js` names the `papua-mask` topology and a `#mask` DOM
     id fallback, and `visual_governor_spec.rb:30` is the comment recording the
     supersession.
93. **`visual_governor.js:1` “before mask.js loads”.** mask.js does not load. “before face.js”.
94. **`cognition_ecology.js:75` “see mask.js”.** Same.
95. **`HealthController` comment block is a decision record.** Keep one line: git is not critical because dubious ownership under `master` user.
96. **`eslint.config.mjs` `face3d_*.js`.** `:52` — no such files. Dead glob.
97. **`eslint` globals `MASTERVisual`, `Face3DPreview`.** Grep and drop unused globals.
98. **`lib/cli/session/command_handlers.rb`.** Vague; it is rebuild/context/checkpoint/verify. Rename or fold into `repl_flow.rb`.
99. **`work_commands_extra.rb` / `work_commands_status.rb`.** Suffix `extra` is a junk drawer. Split by verb.
100. **`lib/unwrap_error.rb` unnamed in PATH_OWNERSHIP.** Add a key or move under `lib/result/`.
101. **`Operator::` is a foreign namespace.** `data/autoload.yml:75-76`. Collision risk with `lib/operator`. One prefix.
102. **`lib/rails/` audits RAILS from MASTER.** Consider moving to `RAILS/gates/lib` on a sitting, or expose one `/rails audit` command.
103. **Done — verified 2026-09-12.** Neither `MASTER/lib/grok/` nor `MASTER/lib/deploy/`
     exists; lib/ is boot, builder, cli, cognition, core, fix, ground, io,
     operator, rails, review, trace, voice.
104. **Done — verified 2026-09-12.** Neither `MASTER/lib/grok/` nor `MASTER/lib/deploy/`
     exists; lib/ is boot, builder, cli, cognition, core, fix, ground, io,
     operator, rails, review, trace, voice.
105. **`pressure_engine.rb` at lib root.** Not in PATH_OWNERSHIP. Move under `lib/cognition/` or `lib/trace/` and declare.
106. **`cognition/` not in PATH_OWNERSHIP.** Add; purpose is already in `COGNITION.md`.
107. **`web/script/` undeclared.** Add under `web/`.
108. **`MASTER/log/traces.log` and `MASTER/tts.wav` at tree root.** START_HERE says local/generated is `.master/`, `output/`. Gitignore or move.
109. **`MASTER/runtime/` JSONL undeclared.** Either `.master/` or declare `runtime/` as local.
110. **`loop.gif` / `loop.mp4`.** Add to PATH_OWNERSHIP as generated media, check `none`.
111. **`PATH_OWNERSHIP` `lib/providers/` check is a missing spec.** Points at `spec/providers/catalog_index_spec.rb`; file is `spec/io/catalog_index_spec.rb`.

### MASTER — tests

112. **Source-assertion ratchet is 222.** Worst: `test_web_ui.rb` (39), `spec/lifecycle_tools_spec.rb` (17), `test_cli.rb` (12). Convert lifecycle_tools tests to actually run `--help` / a dry flag.
113. **`test_agent.rb` four skips “API moved”.** `:31-54`. Port or delete.
114. **`test_suite_actually_runs.rb` skipped unless `SUITE_AUDIT=1`.** The test that the suite runs does not run. Put a cheap version in default `rake test`.
115. **`test_self_scan.rb` skipped unless `MASTER_INTEGRATION`.** Document in START_HERE which integration tests exist.
116. **`test_cli_boot_e2e.rb` needs `MASTER_CLI_E2E=1`.** Same.
117. **`test_web_http.rb` / `test_browser.rb` excluded from `rake test`.** `--profile=web` must be the only advertised path; START_HERE lists operator profile without web.
118. **`test_injection_guard_wiring.rb` uses `.allocate`.** `:50`. Construct with a fake governor.
119. **`test_io_replicate_client_train.rb` allocate.** Same pattern `:8`.
120. **`test_tool_registry_elevation.rb` allocate.** `:12`.
121. **`spec/web/visual_governor_spec.rb` greps source for `let maxFps = 24`.** Drive the function if exported, or keep as a marked manifest test.
122. **`test_web_ui.rb` asserts `File.read(visual_bridge.js)` includes `phantom:detected`.** Assert the method/event fires.
123. **Fixed 2026-09-12.** It already called `Thresholds.worn_profile`; what was left
     was a seventh assertion that `rules.yml` *contains the string*
     "Design::Thresholds.micro_typography". The six above it call that reader and
     check what it returns, which is what having a reader means — the seventh passed
     if the method were deleted and the comment stayed, and failed on a rename that
     broke nothing. Removed, and `TestSourceAssertions::BASELINE` lowered 222 -> 221
     so the gain cannot be handed back silently; that test demanded it.
124. **`test_edge_case_stub_generator.rb` asserts generated tests contain `skip`.** Generate real stubs or delete the generator.
125. **`spec/core_smoke.rb` is not `*_spec.rb`.** `rake spec` does not run it; `rake core_smoke` does. Rename.
126. **Three homes for face tests.** `web/test/`, `test/test_web_*.rb`, `spec/web/`. Pick two.
127. **`web/test/locale_contract_test.rb` vs `RAILS/test/locale_contract_test.rb`.** Extract one helper.
128. **Fixed 2026-09-12.** Removed. `rules.yml` is tracked and `paths.immutable`, so
     the skip could never fire in this repo; if it ever could, the boot test should
     say so rather than pass.
129. **`test_style_guides.rb` skips unless `OPERATOR` checked out.** OPERATOR is not a tree. Dead skip or wrong path.
130. **`test_io_key_rotator.rb` skips unless two key vars.** Fixture ENV so empty/single-key branches run.
131. **FakeConfig `send(k) rescue nil`.** `test_agent.rb:12`. Swallows everything. Stop.

### MASTER — web face

132. **Done — verified 2026-09-12.** `mask.js` and the three `mask_*` files are off
     disk and nothing loads them. The two textual matches left are a different
     thing: `visual_bridge.js` names the `papua-mask` topology and a `#mask` DOM
     id fallback, and `visual_governor_spec.rb:30` is the comment recording the
     supersession.
133. **`codebase.js` not in `face_assets.yml`.** Topology `renderer: codebase.js` (`topologies.yml:95`) but the shell never loads it. Add to a deferred group or stop naming it.
134. **`offline_memory.js` not in the manifest.** `sw.js:78` says drain lives there; the contract test only asserts the file exists.
135. **`swarm.html` / `diag.html`.** Extra HTML, `lang="en"`, scanline overlay against FLAT_UI. Route behind auth or delete.
136. **`index.html.erb` `<title>brgen</title>`.** `:17` hardcoded. `t("face.title")` in nb/en.
137. **Already done — verified 2026-09-12.** No `hello:` key and no "Hello world"
     string anywhere under RAILS or MASTER.
138. **I18N_COVERAGE already flags `index.html.erb:17` and `:348`.** Fix with keys.
139. **`BLANK_LINE_RUN` on `index.html.erb:1`.** One blank-line fix.
140. **Face copy still English-first in JS.** `config/application.rb:70` is nb. Audit primer inline script against locale keys (`primer_title`).
141. **`data-theme="dark"` + inline `#000` FOUC guard.** `index.html.erb:67-80`. When chrome moves, these three inline colour rules are the FOUC layer — change with the stylesheet, not before. Values stay the operator’s.
142. **`chat.js` + `chat_actions.js`.** CLAUDE.md says `chat_actions.js` owns POST streaming. If `chat.js` is leftover, fold.
143. **`boot_fsm.js` + two inline primer scripts.** One test that both cannot double-dismiss.
144. **`face_vision_a.js`–`d.js` + `face_vision.bundle.js`.** Manifest loads the bundle. Stop serving sources as static.
145. **`face.modules.bundle.js` vs eager `face.js` imports.** Confirm only one runs per tap.
146. **Three particle systems.** `particle_kernel.js` + `particle_worker.js` + `face_particles.js`. Name the boot order in `face_assets.yml` comments (kernel is already called out).
147. **Three ecology layers.** `cognition_ecology.js` + `_render.js` + `face_offscreen_ecology.js`. Same.
148. **`smart_turn.js` fetches 21MB ONNX.** Default must stay off; add a test that `index.html.erb` does not `<script src>` the wasm.
149. **`sw.js` cache name `brgen-`.** `:3`. MASTER face is `ai.brgen.no`. Rename to `master-`.
150. **`sw.js` precaches `/manifest.json` not the Rails `pwa#manifest` path.** Confirm both URLs 200 or the SW precache fails silently.
151. **`DYNAMIC_PREFIXES` includes `/bridge/`.** `sw.js:11`. No `bridge` route. Dead prefix.
152. **Dashboard is a second chrome.** `views/dashboard/index.html.erb`. Under one chrome: brgen shell or fold into chat.
153. **`ChatController#dmesg` shells `dmesg`.** `:32-35`. Bound it or drop; OpenBSD dmesg is not chat telemetry (`Trace::Dmesg` exists).
154. **`skip_before_action :verify_authenticity_token, only: :command`.** Add a test that a sibling-host POST is 403.
155. **Index without container still paints.** Ensure primer copy does not claim “ready”.
156. **ActionCable `/cable` + SSE `/events/stream` + `visual_bridge.js`.** Three event pipes. Document Cable’s remaining job or remove.
157. **`web/public/offline.html` BARE_DIV_WRAPPER.** One wrapper div.
158. **`probe.rake` missing frozen_string_literal.** One magic comment.
159. **NO_CHANGELOG_COMMENT on `tts_job.rb:45`, `master_container.rb:59`, `face_asset_paths.rb:6`, `face_assets_manifest_test.rb:19`.** Present-tense or delete.
160. **Ferrum in both Gemfiles.** `MASTER/Gemfile:23` and `web/Gemfile:22`. Web could use the path gem’s test group.
161. **`web/Gemfile:29-50` “must mirror root Gemfile”.** A comment is not a lock. Test that web’s runtime gems ⊇ what `lib/` requires, or a single `gemspec`.
162. **`allow_browser versions: :modern`.** Test that an old UA gets 406, not a blank face.
163. **`PwaController` has no controller test.** `pwa_master_contract_test.rb` greps the ERB and `sw.js`. Add a request test that `GET /manifest` is 200 JSON.
164. **`chat_upload.css` / `face.css` not in `face_assets.yml` groups.** Loaded from the view. Digest hole of the same class as 2026-07-10. Add a `shell_css:` group.
165. **`mic_capture_processor.js` / `whisper_mel.js` absolute `/…` URLs.** Propshaft digest will 404 if not in the manifest. Add to singletons.

### MASTER — law, boot, docs, errors

166. **`NO_PUTS` `puts\b(?!\s*\()`.** `puts("x")` is allowed, `puts "x"` is not. Detect any `puts`/`p`/`pp` in `lib/` except the exemption paths.
167. **Exemption marker vs LONG_LINE / TRAILING_COMMENT.** Already named in the refinement inventory. Fix the two rules to ignore overage that is only the marker.
168. **`lib/io/key_rotator.rb` exists; `secrets_rotation` still `rule_ids: []`.** A detector that keys in `/etc/*.env` have no `expires` is the honest gap. Do not point at a neighbour.
169. **`principle_map` 175 `gap` of 272.** Fill `rule_ids` from a name match against `Law.define` / `RuleDSL.rule`. Do not invent detectors for conduct.
170. **`scan_coverage.yml` exempts `tools/`, `bin/`, `web/`.** One glob that includes `bin/*` without claiming SelfCheck covers it.
171. **`tools/` exemption is “arguable”.** Scan tools/ with a profile that ignores `$PROGRAM_NAME` scripts’ CLI `puts`.
172. **`web/` exemption produces findings nobody acts on.** Scan `web/public/*.js` (sources only, not bundles) in SelfCheck or stop claiming FOR_OF is enforced.
173. **`TODO_FIXME` examples in `voice.yml:85`.** If the rule scans YAML, those are findings or exemptions. Confirm `applies_to`.
174. **`FILE_SPRAWL` still flags `lib/cli/propose/` one-file dir** if `candidate_sources.rb` remains alone.
175. **Two Gemfiles, two locks, two platform `if`s.** Runtime deps should come from `master.gemspec`; web Gemfile should be Rails + falcon only.
176. **`master.gemspec` exists but Gemfile lists gems directly.** `gemspec` in both Gemfiles so versions cannot drift.
177. **Dilla gems in MASTER Gemfile.** `:44-52` `group :dilla`. STUDIO resolves its own gems. Trace `test_helper.rb` before deleting the group.
178. **Zeitwerk ignores: 45.** If slash tables stay unwired, they should not be ignores forever — they are unused files Zeitwerk cannot load.
179. **`required_manually: boot` comment vs file.** Comment still says `require_relative "boot/boot"`. Verify the require in `lib/master.rb`.
180. **`Builder.build` vs `build_fast`.** `BootReceipt` should list what `build_fast` skipped.
181. **`HashDigCompat` prepends Hash globally.** Install only after `require "coltrane"`, not on every MASTER boot, if coltrane is not loaded.
182. **START_HERE `bin/check` default profile may name a renamed task.** If `lint:data_singularity` was renamed `reader_singularity`, the doc is wrong. Read `check_runner.rb`.
183. **START_HERE runtime map omits `lib/cognition/`, `lib/operator/`, `lib/rails/`, `law/`.** Add one line each.
184. **START_HERE “Do not optimize away: constitution self-scan debt”.** Selftest is 0 as of 2026-09-10. Cut or retarget.
185. **`EXAMPLES.md` still shows “Good TODO Update”.** TODO policy is delete-on-close. Rewrite EXAMPLES to match.
186. **TREE.md is the map; START_HERE still has an ASCII runtime map.** Point START_HERE at TREE.md.
187. **DECISIONS still contains superseded two-spine text.** Add a one-line “current policy is One Spine” at the top of that section.
188. **`ResyncService#call` rescues StandardError to a string.** A failed `reset --hard` looks like a chat line. `Result.err`.
189. **`TtsController#synthesize` rescue returns `e.message` to the client.** Map to a stable `"synthesis_failed"`.
190. **`ChatController#dmesg` ignores status, no timeout.** Use `Io::Exec` with timeout.
191. **`cli/scan/request.rb:182` `rescue StandardError` without `=> e`.** Swallows without log.
192. **`runtime_mode.rb:32-36` double rescue StandardError.** Empty. Log or let it raise.
193. **`fold_risk.rb:23` rescue StandardError.** No log.
194. **`voice/dilla.rb:40` rescue StandardError.** No log.
195. **`rails/routes_views_audit.rb` five StandardError rescues.** An audit that cannot read a file should Result.err, not skip.
196. **`SsrfGuard` DNS rebinding residual.** `ssrf_guard.rb:17-25` documents it. Pin IP or refuse hosts that resolve split.

### MASTER — CLI, scan, tools, security, micro

197. **No `completions/_operator`.** Add; generate from operator verbs.
198. **Five “who reaches this” tools.** `operator readers` should be the one verb; `data_reach` / `code_reach` / `method_reach` / `method_graph` are implementation.
199. **Three linters.** Document: `operator lint` = no model, `/review --only scan` = may write, `rake constitution` = self-findings budget.
200. **`operator test` “smallest complete proof for dirty files”.** Print which test files it selected.
201. **`operator land` rebase-push.** Refuse unless worktree (`git rev-parse --git-dir` is a file).
202. **Live `/commit` still `git add -u`.** Make it path-scoped, or refuse when `git status` has files outside argv.
203. **`/orders run` executes standing orders.** Test that it cannot run `git reset --hard`.
204. **`/soul approve` amends constitution.** Test absolute sections refuse.
205. **`grep_history` / `audit_changes` on CommandRegistry.** Not in `build`. Dead methods or missing `/grep` `/audit`.
206. **`dispatch_save` exists, no `/save`.** Wire or delete.
207. **`dispatch_reasoning` / `dispatch_persona`.** Not in `build`. Dead or missing commands.
208. **`EXIT_ALIASES` includes `q`.** A `/q` typo. Require `quit`/`exit`.
209. **`Pipeline::ParallelGroup` pool `nprocessors`.** On a 1-CPU VPS this still fans out. Cap at 2 in production via `HostBudget`.
210. **`MASTER_SCAN_AUTOFIX` defaults to `"1"`.** Confirm `bin/cli /review` default is dry unless `--apply`.
211. **Dual events `scan_autofix:applied` and `self_autofix:applied`.** One topic.
212. **`FixLoop` STARTUP_DELAY 90s.** `build` must not start it unless asked. Test `MASTER_BACKGROUND=0`.
213. **Four loops.** `RuleLoop` / `FixLoop` / `WatchLoop` / `Watcher`. Document which process may run which.
214. **`CrossFileAnalysis` prescan is advisory.** Change the string to “advisory, not a gate”.
215. **`EdgeCaseStubGenerator` generates skips.** Delete or make it a no-op.
216. **`DatalogEngine` / `AutonomousRepairer`.** Confirm callers. If none, they are the next unified_diff_editor.
217. **`rake constitution` budget 1500.** A number that large is not a ratchet. Lower only with a deletion of findings.
218. **`spec/dogfood_spec.rb` vs `bin/dogfood` vs `rake dogfood`.** Three dogfoods. One.
219. **`spec/lifecycle_tools_spec.rb` greps `bin/`.** Move to `test/test_bin_scripts.rb` and run processes.
220. **`spec/smoke/pipeline_e2e_spec.rb` vs `test/test_pipeline.rb`.** Merge fixtures.
221. **Flat `test/test_*.rb` outliers.** `test_aggressive_merge.rb` is not findable. Rename to `test_trace_*`.
222. **`tools/todo.rb` is a second backlog if nobody runs it.** Wire `rake lint:todo` or delete.
223. **`tools/example_scan.rb`.** No test, no rake. Delete or `rake lint:example_scan`.
224. **`tools/history_valuables.rb`.** Test the regex does not match `TODO.md`.
225. **`tools/method_graph.rb` / `method_reach.rb`.** Add `test/test_method_graph.rb` with the hook-false-positive fixtures the comments name.
226. **`tools/namespace_ratchet.rb`.** Duplicate of `data/namespace_ceilings.yml`? One.
227. **`tools/word_boundary_lint.rb`.** Add to `rake audit`.
228. **`tools/swallowed_errors.rb`.** Should flag `scan/request.rb:182`. Add to audit.
229. **`tools/dup_census.rb` / `design_baseline.rb`.** No unit test of the counter.
230. **`tools/snapshot.rb` vs `Trace::Snapshot::Publisher`.** One snapshot verb.
231. **`tools/test_naming.rb`.** Run in `rake lint:test_naming`.
232. **`script/generate_canon.rb`.** Ensure `rake docs:` is the only writer of `data/CANON.md`.
233. **`MASTERFace` leftovers in `public/`.** Grep non-bundle sources and delete.
234. **Three globals.** `window.MASTER` vs `master_namespace.js` vs `MASTER_RUNTIME`. `master_namespace.js` should be the only assigner.
235. **Three stores.** `felt_state.js` vs `face_state.js` vs `ui_presence.js`. Add a runtime test that `MASTERFeltState` exists before `visual_bridge` emits.
236. **`attention_model.js` vs ONNX `smart-turn`.** Two “attention” in the face. Rename JS to `face_attention_field.js`.
237. **TTS `Cache-Control: public, max-age=3600`.** `tts_controller.rb:44`. Body is per-user speech. `private`.
238. **`/chat/tts/phrases` unauthenticated.** If phrases are idle nudges, visitors get them. Intentional? If not, authenticate.
239. **CSP report-only unless `PUB4_CSP_ENFORCE=1`.** Production should enforce. Check `web/config/environments/production.rb`. **Unverified.**
240. **CSP `style_src :unsafe_inline`.** Needed for FOUC. Nonce style?
241. **YouTube in script_src / frame_src.** If unused, drop.
242. **`face.part*.txt` in public/.** Concatenated at build; still served. Move to a build dir.
243. **Ingress test skips if token empty.** Fixture a token so CI tests ingress auth.
244. **`planned.tools.deny_patterns` unwired.** Leave; do not restore `risk_classifier.rb` without a caller.
245. **WebFetch must not hit `127.0.0.1:38182`.** `BrgenBridge` is a dedicated client. Test SSRFGuard blocks the tool path.
246. **`DynamicHttp` + SSRFGuard.** Confirm `resolve_and_validate_uri` calls `SsrfGuard`. If not, that is the hole.
247. **`Fiber[:master_visitor]` process-wide in CLI.** Test a CLI Session does not leak into a later web request in the same Falcon process.
248. **`/up` vs `/health`.** relayd should use `/up` for liveness and `/health` for deploy smoke. Document in `web/CLAUDE.md`.
249. **`pages#radio_bergen`.** Extra surface. Auth? Content? If it is the Dilla tunnel, it belongs in playlist.
250. **`web_boot_payload` vs `_minimal`.** Test `/runtime/config` is not a `<link preload>`.
251. **Cognition `observe` on `**`.** Test a scan of 1000 events does not write 1000 YAML dumps.
252. **`/review --only scan` must not start the council.** Test `MASTER_SCAN_DETERMINISTIC`.
253. **JS `lang="en"` on swarm/diag/offline.** `lang="nb"` or generate from locale.
254. **`skip_to_content` vs `skip_to_prompt` vs `face.skip_prompt`.** Three skip links. One on the face page.
255. **Dashboard `rsi` / `rtk` untranslated.** If they stay jargon, a comment is enough.
256. **Chat rate limits vs `security.yml`.** `CHAT_RATE_LIMIT = 30` in Ruby; ingress 30 in YAML. Chat should read a limits key (`test_security_defaults` pattern). Same for TTS 30 / poll 300.
257. **Visitor must not `Shell`.** `VISITOR_ALLOWED_TOOLS` from `Tool::Profile.public_names`. Add a web controller test.
258. **`ImagePresenter` `tmp/chat_uploads`.** Ensure PathGuard / not world-readable; purge job.
259. **Two token classes.** `MasterIngressToken` / `MasterWebToken`. Name by job (ingress HMAC vs session cookie).
260. **Three logs.** `WebEventLogger` vs `Trace::Log` vs `Swallow` JSONL. One directory.
261. **Two dmesgs.** `lib/trace/dmesg.rb` vs `ChatController#dmesg`. Controller should call Trace::Dmesg or go away.
262. **`lib/ground/openbsd_config.rb` vs `data/openbsd.yml` vs `OPENBSD/`.** One reader `OpenbsdConfig`. Must not drift from the tree.
263. **`lib/ground/host_budget.rb` vs `OPENBSD/vm_resource.yml`.** Test the path; do not duplicate limits.
264. **`lib/cli/web_server.rb` vs Rails `web/`.** If unused, delete. **Unverified** callers.
265. **`lib/cli/skills.rb` vs `data/patterns.yml` skills_registry.** One skills list.
266. **`lib/ground/standing_orders.rb` vs `orders.rb`.** Two names. Fold if one is a facade.
267. **Four stores.** `lib/ground/memory.rb` vs `memory/store.rb` vs `sqlite_store.rb` vs `knowledge_store.rb`. Comment which is session vs knowledge vs sqlite.
268. **Three semantic layers.** `semantic_cache.rb` vs `semantic_index.rb` vs `Review::Embeddings`. One paragraph in `lib/io/`.
269. **Three quota objects.** Cross-link comments to `test_quota_gate.rb`.
270. **`lib/io/ruby_llm_patch.rb`.** Test that `Model::Info.new` kwargs are a subset of the gem.
271. **`lib/trace/metrics.rb` `summary` should not print zeros as if measured.**
272. **`lib/voice/speech.rb` 471 body lines.** Split I/O (worker client) from policy. Do not change sound.
273. **`lib/voice/personality_prompt_builder.rb` 386.** Split CORE_SECTIONS assembly from file IO.
274. **`diag.html` yellow-on-black debug page is public.** Gate behind authenticated `/diag` or delete from production `public/`.
275. **Static 400/404/406/422/500 English Rails defaults.** I18n or nb.
276. **`AuthTier TOKEN_BYTES = 48` vs `MIN_TOKEN_LENGTH = 43`.** Align numbers in one comment.
277. **`bin/cli` vs `bin/master`.** Two entrypoints to the same REPL. One file should exec the other.
278. **`completions/_master` `compdef master` only.** Also `bin/cli`.
279. **`HELP_TOPICS` `review` detail still says “aesthetic scan, deep scan, fix, re-scan”.** Align with `--only scan|critique|map`.
280. **`test_source_assertions` PATTERN misses `refute_includes File.read`.** Extend or `refute` will grow as a dodge.
281. **`lib/boot/data.rb` `unsafe_load` for aliases.** Test that a crafted alias cannot load a Ruby object. If unsafe is required, `permitted_classes` empty and aliases only.
282. **Four YAML loaders.** `Master.law` / `Rules#data` / `RuntimeCatalog.load` / `YAML.load_file`. Grep `YAML.load_file` in `lib/` for stragglers.
283. **Three ways to define a rule.** START_HERE should say: YAML `rules.yml` + `law/*.rb` + RuleDSL. No fourth.
284. **`data/autofix_reach.yml` dangling 0.** Do not add transform names without code.
285. **Ratchet yml without a rake task is inert.** `cohesion_census.yml` / `dup_census.yml` / `sprawl_census.yml` / `namespace_ceilings.yml` / `design_baseline.yml` / `doc_baselines.yml` / `violation_age.yml` — each needs `rake lint:*`.
286. **`data/agent_map.yml` vs `agent_taxonomy.yml`.** `/btw` uses taxonomy. Map is unused or for snapshots. One.
287. **`data/load.yml` dual with `boot_phases.rb`.** One.
288. **`data/proposals.yml`.** If unread, it is `data_reach` unnamed. Reader or delete.
289. **`data/radio_bergen_track_dossiers.yml` unnamed keys.** STUDIO/dilla data in MASTER/data. Move to STUDIO or give dilla the reader.
290. **`data/pub_archive_restore.yml` / `recovery_pub.yml`.** Keep; mark `data_reach` reasons so they stop looking like defects.
291. **`data/recovery/plugin_schema_v1.json`.** JSON in YAML-land. One schema language.
292. **`data/maturity.yml` vs scorecard.** Two maturity sources? One.
293. **`lib/ground/pledge.rb` vs OpenBSD pledge.** Name `OpenbsdPledge` if it is that; if not, do not confuse `OPENBSD/`.
294. **`lib/fix/constants.rb`.** Dumping ground? Split or name the constants’ subject.
295. **`SCAN_GLOB` vs extensionless `bin/`.** Implement include list for `bin/check`, `bin/gate`, `bin/cli`.
296. **`lib/cli/scan/request.rb` TARGET_ALIASES `face`.** Test it points at `web/public` not generated bundles.
297. **`bin/ruby` wrapper.** Test it execs 3.4.9 or prints.
298. **`InjectionGuard` vs WebFetch.** Test Boot still builds `guard:` and WebFetch uses the same object, not a new one.
299. **`BootReceipt` vs `maturity_scorecard.rb`.** Test the receipt includes rule count from the file the process loaded.
300. **`lib/io/antigravity.rb` 231 lines after fold.** Under 300. Fine; skills test exists.

### RAILS — brgen core

301. **Stale layout comment.** `RAILS/brgen/app/views/layouts/application.html.erb:1-26` still says `data-theme="dark"` is load-bearing. Rewrite to the present-tense reason, or delete it. (Amber’s layout comment is already present-tense light.)
302. **404 chrome vs live chrome.** `RAILS/brgen/public/404.html:8-11` forces `color-scheme: dark` and inline `--x-bg: #0f0f12` while the app default is light. Align static errors with `shared/public/styles/errors.css`. Look: name the seam, do not invent tokens.
303. **404 hardcodes Bergen marketplace.** `RAILS/brgen/public/404.html:34` links `https://markedsplass.brgen.no/` so Oslo/LA 404s send people to Bergen. Build the href from `Brgen::DomainRegistry`.
304. **404 English paragraph.** `RAILS/brgen/public/404.html:29`. i18n both, or drop the EN line.
305. **Same for 500/422.** One generator or shared static template.
306. **Mailer English subject.** `email_subscription_mailer.rb:10` `subject: "Confirm your Brgen subscription"`. Move to `t("mailers.email_subscription.confirm")`.
307. **Mailer from-host.** `:4` `from: "Brgen <letters@brgen.no>"` ignores city hosts. Parameterize with the requested host.
308. **No mailer tests.** No `email_subscription_mailer_test.rb`. Assert subject key, `confirm_url` token, and both html/text parts.
309. **Newsletter/queue/verification mailers untested.** One request test per `deliver_*`.
310. **`Tv::BaseController` is a stub.** `:3` “keep empty until shared vertical policy/layout lands.” Hoist vertical policy here or delete the promise.
311. **Stream chat skips the TV base.** `Tv::StreamChatsController` inherits `ApplicationController`. Inherit the base; use `Current.user` not `current_user`.
312. **Comments on TV show N+1.** `tv/videos/show.html.erb:123-128` walks `@video.comments` then `comment.user` with no `includes(:user)`.
313. **`increment!` on listing/video views.** `Marketplace::ListingsController#show:56` and `Tv::VideosController#show:24`. Counter table or `update_counters`; do not fragment-cache that field.
314. **Double view increment on TV.** `VideosController#show` increments, and `ViewEventsController#create` increments again. One writer.
315. **`Tv::VideosController#show` creates a ViewEvent per GET.** Refresh = a row. Dedup per (user, video, hour) or only create from the player beacon.
316. **Posts live search vs FTS.** `posts_controller.rb:35` `apply_live_search` on `title/content` while `posts_fts` exists. Use FTS when the table exists.
317. **Conditional GET absent.** Add `fresh_when` on `posts#show`, `events#show`, `listings#show`. Only `bsdports` `ports#show` has it.
318. **No `data-turbo-prefetch` on nav.** Turn on for the eight swiper destinations; keep `pagy.rb:17` prefetch-off on pager links.
319. **Pagy disables prefetch globally.** Scope to pager anchors, not every Pagy link extra.
320. **`data-turbo-permanent` missing on nav.** Mark the swiper + theme toggle permanent.
321. **Feed sort is a full document.** Hot/New/Following should be a turbo frame.
322. **`turbo: false` on channel join.** `channels/show.html.erb:78`. If join must full-reload, comment why; else drop it.
323. **`turbo: false` on cart PSP forms.** Document, or use `data-turbo="false"` only on those two buttons via a helper.
324. **Notifications still local.** `brgen/.../notifications_controller.rb` vs `shared/.../notifications_controller.rb`. Promote when city grouping unifies — or delete the shared stub.
325. **Votes still local.** Same for `votes_controller.rb`. The shared reflex `vote_reflex.rb` already exists.
326. **Follow schema split.** brgen `follower/followed` vs amber `follower/followee`. Until unifying, stop implying shared following in docs.
327. **WebVitals logs only.** Persist p95 or drop the POST if logs are the product.
328. **Server-Timing absent.** No middleware in `shared/config`. Cheap header for view/db/cache split.
329. **Fragment cache hit/miss not timed.** Three cached partials. Emit `Server-Timing: miss|hit`.
330. **Checkouts `allow_other_host: true`.** `Marketplace::CheckoutsController#create:56`. Allow-list host (`vipps.no`, `checkout.stripe.com`) rather than any URL `start_payment` returns.
331. **Checkouts rescue `StandardError`.** Narrow to payment errors; let programming errors 500.
332. **Flash interpolates exception.** `t("flash.marketplace.checkout_failed", message: e.message)` can leak Stripe internals. Map known errors.
333. **`NotConfigured` flashes English class message.** i18n the provider name.
334. **`hello: Hei` in nb.yml.** `brgen/config/locales/nb.yml:34`. Grep callers; delete if unused.
335. **`nav.vertical_badge_new: "nytt!"`.** Confirm a reader; if the badge never renders, delete the key.
336. **2FA inside engine.** Audit every engine `require_two_factor!` for `main_app` paths (kinds test already pinned a `UrlGenerationError`).
337. **Anonymous TV comments unthrottled.** No `rate_limit` on `Tv::CommentsController`. Add named limit like posts.
338. **Guest minting + prune.** Confirm `guest` + `created_at` index exists in all three schemas. If missing, `PruneGuestUsersJob` is a table scan.
339. **`UserPurgeJob` vs guest prune overlap.** Two daily jobs at 3:45 and 3:50. Document which rows each owns.

### RAILS — marketplace

340. **Favorite button English aria.** `listings/_favorite_button.html.erb:12,20` `"Remove from saved"` / `"Save listing"`. Keys under `marketplace.wishlist.*`.
341. **Saved-search hidden name.** `_live_search_results.html.erb:7` `value: "Marketplace search"`.
342. **“All” chip.** same file `:15` `link_to "All"`.
343. **Category label English.** `listings/new.html.erb:65` `f.label :category_id, "Category"`.
344. **Saved searches “Browse” / “Any query” / “alerts on”.** `saved_searches/index.html.erb`.
345. **Store “Partner program”.** `stores/show.html.erb:16`.
346. **`t(..., default: "Store created")`.** `stores_controller.rb:36,47`. Add nb keys and drop defaults.
347. **Deals search is LIKE, not LiveSearchable.** `deals_controller.rb:11-16`. One helper with listings/stores; FTS if a deals index exists.
348. **Deals `#show` no `includes`.** `Deal.live.includes(listing: [:user, { photos_attachments: :blob }]).find`.
349. **Stores `#show` other stores unscoped.** `:23` `limit(6)` with no city. Scope `Current.city_record`.
350. **Stores `#show` listings not `includes`.** `with_attached_photos.includes(:user, :category)`.
351. **Payouts on show, no pagination.** Frame + pagy.
352. **Questions `#create` no rate_limit.** 10/min named `ask`.
353. **Questions flash first error English.** Add `activerecord.attributes.marketplace/question`.
354. **Reviews / returns / payouts / addresses / variants / favorites / saved_searches creates** — none contain `rate_limit` (only listings does in the engine). Add per-resource burst limits; names required when two limits share a controller.
355. **Webhooks still unlimited.** `webhooks_controller.rb:15` comments the hole. `rate_limit` by IP even after signature verify.
356. **Two Stripe webhook controllers.** Engine `Marketplace::WebhooksController` and `Webhooks::StripeController` both pay orders. One entry.
357. **`views_count` nullable.** `schema.rb:738`. `increment!` on nil raises. Default 0, NOT NULL.
358. **`status` on listings nullable.** `live` scope depends on it. NOT NULL + default `"active"`.
359. **Add `(kind, category_id)` index** if facet queries filter both (they do: `listings_controller.rb:23-27`).
360. **Duplicate indexes on gig/housing/job details.** Unique AND non-unique on `listing_id`. Drop the non-unique.
361. **Checkout `#show` redirects to cart twice.** `checkouts_controller.rb:70` `checkout ? cart_path : cart_path`. Dead ternary.
362. **Facets after kind filter.** Verify job/housing facets aren’t goods leftovers. Test already in `marketplace_saved_and_facets_test.rb`.
363. **Top offers English default.** `_top_offers.html.erb:8` `default: "Picked for the city"`.
364. **Listing show “Make an offer” default EN.** `listings/show.html.erb:99`.
365. **Order status `humanize` fallback.** `orders/show.html.erb:13`. Exhaust `marketplace.order_statuses` in nb.
366. **Condition `humanize`.** `_facets.html.erb:13`.
367. **Anon fallback.** `listings/show.html.erb:39,85,141` `"anon"` instead of `t("chat.anon")`. Same in `_questions.html.erb:13`.
368. **No engine test for stores/deals/addresses/payouts.** Add request tests for owner-only payout release and guest deal index.
369. **Cart qty updates.** Turbo frame around cart lines after PSP return.
370. **`SavedSearchAlertJob` no uniqueness.** `limits_concurrency to: 1, key: "saved-search-alerts"`.
371. **`ListingExpiryJob` same.** Concurrency 1; row lock so two workers cannot both pass the read before `renewal_notice_sent_at`.
372. **Variant out-of-stock hidden in Ruby.** `listings#show` `select(&:in_stock?)`. `scope :in_stock` on the relation instead of loading all.
373. **`finish_live_search` duplicated** across listings/stores/deals/takeaway restaurants/maps places. Deals bypasses it for the query half only.
374. **Solidus still Postgres-first.** `solidus_staging_contract_test.rb` must keep failing closed when `SOLIDUS_MARKETPLACE=1` on sqlite.
375. **Two “deals” nouns.** `AffiliateProduct` vs `Marketplace::Deal`. Verify `deals#index` does not render affiliate placeholders as listings.

### RAILS — dating, takeaway, tv, playlist, maps

376. **“Make profile visible”.** `profiles/new.html.erb:52` and `edit.html.erb:65`. Add `dating.visible_label`.
377. **Show page English paragraph.** `profiles/show.html.erb:61-74` visibility copy. All keys.
378. **Edit photo alt.** `profiles/edit.html.erb:21` `alt: "Profile photo"`.
379. **Swipe card `"anon"`.** `home/_card.html.erb:1`.
380. **Already decided, and the record is in the file that owns it.** The engine's
     locale header states the rule: Rails::Engine appends config/locales/*.yml to
     I18n.load_path on its own and I18n deep-merges across load paths, so keys the
     host already carries stay reachable and are deliberately not copied. The 78
     dating keys in brgen's own locales are those. The stub exists so the next
     engine string has somewhere to go that is not a literal in the markup — which
     is the defect the header was written against. Deleting it would restore that.
381. **LOOKING_FOR / GENDERS raw.** `profiles/new.html.erb:38,44`. `t("dating.looking_for_options.#{v}")`.
382. **LikesController no rate_limit.** Burst 60/min like votes. Same for dislikes/rewinds/prompts/verifications.
383. **`User.find` on like.** `likes_controller.rb:9` not scoped to visible profiles. `Dating::Profile.visible.find_by!(user_id:)`.
384. **`save!` no validation flash.** Failed like is 500. `save` + redirect alert.
385. **Match overlay EN defaults.** `_match.html.erb:10`.
386. **Vipps gate fail-open.** `base_controller.rb:13-21` if `VIPPS_CLIENT_ID` absent, dating is ungated. Document in `dating/README.md` that production must have Vipps.
387. **`candidate_scope` plucks all like/dislike ids.** Unbounded. `NOT EXISTS` or a cap.
388. **Daily picks / verification tests exist in host, not engine.** `cd engines/dating && rake test` is not a lie if they move or duplicate.
389. **Intro JS.** `dating_intro_controller.js` — no test. If intro goes with immersive chrome, delete with the chrome.
390. **Photos purge on edit untested in engine.** Confirm `profiles#update` permits `photos` + signed blob ids only (`media_guard`).
391. **Age required in optional `<details>`.** `new.html.erb:45` `required: true` inside “optional”. Move age to essentials or drop required.
392. **Takeaway engine `nb.yml` is empty.** `takeaway: {}`. Move the takeaway namespace into the engine.
393. **Takeaway reviews / orders `#create` no rate_limit.** Orders: burst 5/10min per user (guest-capable).
394. **`#update` kitchen status from params.** `orders_controller.rb:55` `params[:status]`. Allow-list `Takeaway::Order::TRANSITIONS`.
395. **Menu items / favorite restaurants `#create` no test / no rate_limit.**
396. **Group orders token in URL.** Rate-limit `create` so a host can’t mint unbounded open tickets.
397. **Delivery drivers index `"anon"`.** `delivery_drivers/index.html.erb:13`.
398. **`status` on `takeaway_orders` nullable.** NOT NULL + default `"pending"`. Same for `quantity`/`unit_price_cents` on items.
399. **Courier layer cross-engine.** `maps/home_controller.rb:75` `Takeaway::Order` — add the gate row with that line exempted (awesome-list item already named the shape).
400. **Hours “no rows = open”.** Empty-state on restaurant show should say so if hours missing, not “closed”.
401. **Guest order push.** Test that a guest order doesn’t 500 on push (no VAPID). `WebPushJob` discard path.
402. **Nav bar partial duplication.** `takeaway/_nav_bar.html.erb` vs `marketplace/_nav_bar.html.erb`. Shared `vertical_nav` with accent var already on body.
403. **No takeaway controller tests in engine** except `order_test`. Missing: reviews, favorites, drivers, menu_items.
404. **TV “New channel”.** `channels/index.html.erb:6`.
405. **Empty search English.** `channels/_live_search_results.html.erb:10`.
406. **“Add a note” / “Timestamp (seconds)” / “Add a comment”.** `videos/show.html.erb:106,113,144`.
407. **`"anon"` on comments.** `videos/show.html.erb:126`.
408. **Live streams aria English.** `live_streams/index.html.erb:3,9` despite `t(..., default: "Live streams")`.
409. **`tv.channel_subtitle` default “Brgen TV channel”.** City-name it.
410. **Viewers interpolation default.** `live_streams/show.html.erb:23` `default: "%{count} viewers"` — EN plural on :nb.
411. **Notes/comments/stream_chats creates no rate_limit.**
412. **`StreamChatsController` `save!`.** 500 on validation. `save` + 422 turbo.
413. **`current_user` vs `Current.user`.** `stream_chats_controller.rb:9`. Always `Current.user`.
414. **Missing: `ShowsController`, `EpisodesController` request tests.**
415. **`live_streams/new` still exists.** If MediaMTX is absent, the form should say so (`apps.yml` blocker), not look like RTMP works.
416. **`tv_content.rake`.** If it seeds English titles, mark demo-only (`content_honesty`).
417. **Player Stimulus untested.** At least a request test that feed markup has `preload=none` and `100dvh`.
418. **Watch time sendBeacon.** Test the controller rejects decreasing `watch_time_seconds`.
419. **Channel tenant.** Verify comments/notes can’t POST across channels by id.
420. **Playlist “New set” / “All sets”.** `sets/index.html.erb:9`, `sets/new.html.erb:8`.
421. **`content_for :title, "Edit #{@set.name}"`.** `sets/edit.html.erb:1`. Same for hosted tracks.
422. **Dilla sketches `"anon"` / `"by "`.** `_dilla_sketches.html.erb:24`.
423. **Role select `editor/viewer`.** `_collaborators.html.erb:29` raw English values as labels.
424. **Transport `t(..., default:)`.** Add nb keys in engine; drop defaults.
425. **Imports `#create` no rate_limit.** Confirm `OutboundHttp` like link previews. Rate-limit 5/10min.
426. **Party messages / listens `#create` no rate_limit.** Listens need a high ceiling, not none.
427. **`increment! :tracks_count` / `plays_count`.** Schema NOT NULL default 0 (playlist test already hit nullable counters).
428. **Listening party test exists; collaborations/imports/hosted_tracks do not.**
429. **Embed player layout.** Verify `playlists#embed` uses a minimal layout (skip tab bar).
430. **YouTube iframe aria default.** Engine nb has `youtube_player_aria`. View must use it without `default:`.
431. **Maps engine has no `test/` directory.** Add `PlacesControllerTest` for check-in guest identity.
432. **`#index` JSON vs HTML duplicates live_search.** `places_controller.rb:17` and `:25`. One scope builder.
433. **`#check_in` no rate_limit.** GPS spam. 10/min. Length-validate the free-text param.
434. **Home map default Bergen.** `home_controller.rb:13-14` `60.3913, 5.3221` when `Current.city_record` lacks coords. If nil, don’t pretend Bergen on `lsangeles.com`.
435. **Places layer hardcoded path.** `home_controller.rb:32` `url: "/places/#{place.to_param}"`. Engine mount prefix will break. `place_path(place)`.
436. **500 places, 200 events, 200 stories** loaded for one map. Viewport bbox filter.
437. **`I18n.l(..., format: :event)`.** Depends on host `time.formats.event`. Keep host key or define in engine.
438. **OpenFreeMap style URL.** CSP must allow `tiles.openfreemap.org`; `preconnect` or self-host tiles.
439. **Engine nb only address/city/coordinates/kind/neighborhood.** Views use `maps.map`, `maps.aria_map`, `maps.hud_aria`, `maps.needs_js` — move into engine.
440. **Filter `k.humanize`.** `places/index.html.erb:18`. `t("maps.kinds.#{k}")`.

### RAILS — messenger, stories, events, amber, bsdports

441. **Conversation search `"anon"`.** `conversations/search.html.erb:25`.
442. **Voice recorder Stimulus untested.** Keep the request test; add a markup contract (`capture`/accept audio).
443. **Link previews no image.** Deliberate. UI must not show an empty `<img>`.
444. **`MessageExpirationJob` + sweep.** If both run, `expire!` must be idempotent.
445. **`messages.expires_at` unindexed.** `ExpiredMessagesSweepJob:7` `where(expires_at: ..Time.current)`. Add index (partial where not null if SQLite supports).
446. **`typing_indicators.expires_at` unindexed.** Sweep `where(expires_at: ..1.hour.ago)`. Index.
447. **Events RSVP no rate_limit** on `event_rsvps_controller.rb`.
448. **Events map horizon 7 days.** Document in the events index empty state when everything is next month.
449. **Community wiki empty keys.** Confirm views use `wiki.empty_*` in nb.
450. **Moderation queue regression.** Add a test if `moderation_audit_test` doesn’t load `reportable` after write (strict-load bug was fixed).
451. **Blocks/bookmarks/invites controllers** — no rate_limit. Bookmarks create is easy to script.
452. **Amber coverage floor 2 controllers.** `coverage_ratchet_test.rb`. Raise the floor as tests land; don’t lower.
453. **`AiController` English notices.** `"Heuristic joy analysis applied"` / `"AI joy analysis applied"`.
454. **`AiController` shells `bundle exec ruby bin/cli photograph`.** Timeout, no rate_limit, cwd `../../MASTER` — fails on copy-tree deploy. Guard with `Operator::DeployPaths`.
455. **`WardrobeMediaJob` uniqueness is a LIKE on Solid Queue args.** Racey. Use `limits_concurrency` per `item_id`.
456. **`pending_for?` rescue StandardError.** Returns false → double enqueue. Narrow rescue.
457. **Zombie `RemoveBackgroundJob` / `SegmentGarmentImageJob`.** Comments say amber queue never drained. Operator: count rows on vm23; then delete classes. Don’t enqueue.
458. **Amber jobs: no worker.** `ApplicationJob` comment: amber `perform_later` is “never” unless `run_inline!`. Either enable `rc.d/amber_jobs` (operator/RAM) or `perform_now` for media like password mail.
459. **`recurring.yml` prune + declutter assume a worker.** If none, guests accumulate. Same as 458.
460. **Creator profile form English.** `_form.html.erb:4,40,44`. Use `shared/errors`.
461. **`creator_profiles/edit.html.erb`.** `default: "Edit creator profile"`, `"Add item"`.
462. **Widgets English.** `_widgets.html.erb:27-28,35` `pluralize(..., "piece")`, `"Browse demo →"`, `"Talk to MASTER"`.
463. **Item show aria `Color #{color}`.** `items/show.html.erb:25`.
464. **Outfit aria `Items in #{name}`.** `_outfit.html.erb:11`.
465. **Home `turbo: false` Ask AI.** If `master_embed` frame works, drop.
466. **Wardrobe keys still have EN default.** Drop `default:` now that nb exists.
467. **`hello: Hei` in amber nb.** Grep; delete if unused.
468. **Connections/messages/live_streams/planned_outfits** — no dedicated request tests. Add blocked connection and message create rate.
469. **Affiliate links destroy own vs other.** Missing test.
470. **`GarmentSilhouette#png` nil must not 500 the item show.** Verify the view.
471. **UI must not say “similar items”.** Fingerprint is not embeddings. Grep `similar` in amber views.
472. **Raw `photo_polish_done` in ERB** should go through `analysis_status_label` helper.
473. **Luxury chrome vs one-chrome.** Name `_variables.scss` / Caprasimo as the seam; don’t restyle.
474. **`like!` increment likes_count.** Micro: turbo stream replace count.
475. **Declutter 30d job uniqueness missing.**
476. **Amber public 404/500 same dark+EN as brgen.** Same generator as 302.
477. **`local: true` on search form.** `_widgets.html.erb:1` disables Turbo. Remove so live search can work.
478. **ports_fts — already inventoried, and the choice is the operator's.**
     `RAILS/test/raw_schema_objects_test.rb` holds the whole finding: `schema_format
     = :ruby` cannot express an FTS5 virtual table, production runs `db:migrate` and
     has it, everything built by `db:schema:load` — CI and every developer machine —
     does not. brgen's `posts_fts` is in the same list. The test holds that inventory
     at its current size and states why it goes no further: moving an app to
     structure.sql changes what deploy loads. The feature is done on the box; the
     test skip is the schema format, not the feature.
479. **Importer swallows FTS rebuild.** `Ports::Importer#rebuild_fts` `rescue StandardError`. `Ground::Swallow.log` and fail the import run row.
480. **`semantic_search` is lexical.** Rename or UI-label “search” so the explore assistant doesn’t promise vectors.
481. **MakefileParser `+=` vs `?=`.** Add a fixture Makefile with both. `makefile_parser_test.rb` exists — add those branches if missing.
482. **`expand_vars` infinite recursion.** **Unverified** beyond line 80. If `${VAR}` can self-ref, cap depth.
483. **`permit_file_distfiles`.** Importer must not skip license. Test one restricted port.
484. **`PortsImportJob` no uniqueness.** Nightly + manual = two imports. `limits_concurrency to: 1, key: "ports-import"`.
485. **`SecurityAdvisoryRefreshJob` no uniqueness.** Timeout + cache so it doesn’t hammer NVD.
486. **`turbo: false` on JSON summary.** `ports/show.html.erb:53`. If it’s `render json`, keep false; else a frame.
487. **Comments/reactions on bsdports.** If `comments_controller` is mounted without social tables, it’s a dead surface — unmount or add tables. **Unverified** routing.
488. **PWA manifest English.** `bsdports/app/views/pwa/manifest.json.erb:37`. nb/en by locale.
489. **No system test for search empty.**
490. **Maintainers unique name.** Confirm model now validates unique index.
491. **WCAG AAA — checked 2026-09-12, no claim to withdraw.** No README claims
     AAA. The only statement of it is `apps.yml`, which already carries the
     caveat the item asks for on the same line: "not a full-site AAA audit".
     Item 231 still stands and is the forward half.
492. **Explore assistant.** Rate-limit; no LLM key should fail to a rules summary (amber pattern).
493. **bsdports nightly import vs `rc.d/bsdports_jobs`.** If no worker, the schedule is fiction.

### RAILS — shared, gates, i18n, a11y, jobs, schema, JS

494. **Locale shadowing.** Shared locales load twice and win. Stop appending shared path twice; `locale_shadowing` should fail the double load, not only key collisions.
495. **`t(..., default:)` hides missing nb.** Prefer required keys; `i18n_resolution_test` ignores defaults.
496. **Unused-key check absent.** Extend `locale_contract_test.rb` with a reference scan over ERB/`t("` — no i18n-tasks gem.
497. **Interpolation parity absent.** Assert `%{name}` sets match across nb/en.
498. **`chrome_i18n` aria baseline 172.** Translating `_favorite_button` etc. must lower the baseline in the same commit.
499. **Empty-state English still in TV channels.** Lint looks for `title: "No …"`; body literals aren’t covered. Extend a body rule or fix the two TV strings.
500. **`Shared::Errors` vs local forms.** Creator profile reimplements errors. Always `render "shared/errors"`.
501. **Sweeps can overlap.** `limits_concurrency` on bulk jobs (`retry_on` is not uniqueness).
502. **`WebPushJob` duplicated.** `brgen/app/jobs/web_push_job.rb` and `shared/app/jobs/shared/web_push_job.rb`. One class.
503. **`LiveSearchable` deals exception.** See 347.
504. **New `after_commit` notifiers must `includes` at the job.** Grep `deliver_notification` without `strict_safe` / includes.
505. **`ActivityTrackable` actor nil on failure.** Analytics drop silently. Log once per event name.
506. **`examples.html.erb` English aria.** If routed, i18n; if not, don’t mount.
507. **`_ad_slot.html.erb` inline display.** AdSense requirement; keep. Ensure consent wraps it.
508. **Affiliate disclosure.** Must render on deals and amber shop. Add a view assertion per app.
509. **`master_embed`.** Don’t double-load face JS.
510. **CSP reports controller.** `skip_forgery_protection`. Rate-limit; cap body.
511. **OmniAuth buttons still shown if provider unset.** Hide via `oauth_provider_slugs`.
512. **`examples.html` / `jox_logo_controller.js`.** Grep; if only examples, don’t ship in boot.
513. **`optimistic_send_controller.js`.** Votes don’t use it. Wire vote arrows or delete unused controller.
514. **`parallax_tilt_controller.js`.** If unused in ERB, delete (`stimulus_wiring` will tell).
515. **`stimulus_boot.js` loads full @stimulus-components fleet.** Split per layout.
516. **PWA SW `networkTimeoutSeconds: 20`.** 3–5s then offline page.
517. **SW caches status 0.** `CacheableResponsePlugin({ statuses: [0, 200] })` caches opaque failures. Drop 0.
518. **`__APP_NAME__` cache names.** Must not collide across apps on `amber.brgen.no` vs `brgen.no`.
519. **Offline page Retry.** Confirm bsdports uses shared offline, not a local copy.
520. **Legal pages city TLD.** Grep `brgen.no` in `legal.*.yml`.
521. **`VAPID_SUBJECT` default `admin@brgen.no`.** Wrong for bsdports.org. Per-app env.
522. **`schema_migration` regex.** `/create_table\s+["':](\w+)["']/` misses `create_table :posts`. Fix regex + exempt `if_not_exists` repair migrations.
523. **`css_minify_integrity` selector-loss dead.** dart-sass 1.101.0 doesn’t drop selectors. Keep compile check; skip loss half or detect sass version.
524. **Six gates load-time ROOT.** Add `root:` kwarg so tests don’t rewrite constants.
525. **`scale_ratchet` under-baseline is warning.** Fail until the number is lowered (same contract as chrome_i18n).
526. **`frontend_auditor` advisory unless `GATE_AUDITOR_STRICT`.** Document in `runner.rb --explain`.
527. **`visual_contract` without `--capture` must not print “ok”** as if pixels were measured.
528. **Authenticated personas missing.** `GATE_ADEQUACY.md` gap 1: cart checkout, dating matches, sell form, amber mutations. Add a signed-in fixture user in triangle.
529. **page_sim `:id` pages source-only.** Seed one listing/video id for live.
530. **CDP flake → green.** `--all` should not treat <3 surfaces as pass.
531. **No axe tree.** Don’t claim a11y complete. Accent_contrast is filled controls only.
532. **`gate_mutation` doesn’t plant mobile_flow/page_simulation defects.** Extend plants.
533. **Affiliate honesty.** Assert disclosure on deals index HTML fixture.
534. **`css_constitution` — confirm planted illegal `px` fails.** If it still matches comments, it’s a spelling gate — fix the detector.
535. **`coverage_ratchet` floors stale.** brgen 21/24, amber 2/10, bsdports 2/8. After new tests, raise in the same commit.
536. **Maps engine invisible to some globs.** Any new gate must include `brgen/engines/*/app`.
537. **`i18n_resolution_test` skips `default:`.** Fail on `default:` in views, or resolve with `raise_on_missing`.
538. **Engine `en.yml`/`nb.yml` headers lie.** “Keys the host already carries are NOT copied” — then views add `default:` EN. Either use host keys without default, or copy into engine.
539. **Playlist engine nb incomplete vs defaults in ERB.** Transport, add_track, sets_subtitle.
540. **`marketplace.stores.*` defaults.** edit/delete/confirm.
541. **`shared.errors` default in store form.**
542. **`profile.edit` default.** `users/edit.html.erb`, `users/show.html.erb`.
543. **`posts.add_photo` default.** `posts/new.html.erb:55,60` — aria uses `t(..., default: "Add photo")` and the button still says `Add photo`. Same on edit.
544. **`nav.show_menu` default.** `_mobile_chrome.html.erb`.
545. **`compose.*` used in dating/amber.** Keys in amber nb; brgen must have them too for dating toolbar.
546. **`legal.dating_age`.** Used in dating new. Confirm nb.
547. **Flash `full_messages.to_sentence`.** English AR. `activerecord.errors` nb.
548. **`pluralize` in amber widgets.** Always English. `t("wardrobe.demo_pieces", count:)`.
549. **PWA manifests descriptions EN** in all three apps.
550. **Mailer subjects EN** besides subscriptions: `newsletter_mailer`, `verification_mailer`, `queue_failure_mailer`.
551. **Time `distance_of_time_in_words` locale.** Deal countdown — `I18n.locale` must be nb.
552. **City copy contract.** Add dating “Bergen” literals if any.
553. **`nav.takeaway` default `"takeaway"`.** `maps/places/show.html.erb:66,69`.
554. **OAuth nested defaults.** `_oauth_links.html.erb` three layers. One key.
555. **Dating engine `bio: Bio`** while host has `about_you`. Dead key or wrong label.
556. **172 EN aria-labels.** Start with favorite button, live streams, playlist transport (visible on :nb).
557. **Error pages have no skip-link** and no `#main-content` id on `<main>`. Add both to static errors.
558. **Color swatch `title` + aria English.** amber items show.
559. **Outfit composition unlabeled list.** Should be a list of item names.
560. **Live stream `role=list` without `listitem`.**
561. **Form errors `tabindex=-1`.** Turbo 422 must move focus.
562. **Video notes timestamp field unlabeled in nb.**
563. **`lang` on `<html>`.** Verify application layouts; static errors are `lang="nb"` even for EN gloss children.
564. **Marketplace `_card_media` empty alt.** Confirm `alt: listing.title`. Same for `_top_offers`, event covers, stories, dating picks/verifications, playlist player art, dressing-room imgs. Decorative avatars next to a name may stay empty; content photos may not.
565. **Maps engine zero tests.** See 431.
566. **Dating engine missing controller tests** (host has likes/rewind/unmatch/verification).
567. **TV engine activity + view_event only** — no comments/notes/chat.
568. **Playlist engine playlist + party only.**
569. **Amber `AiController` untested** including Open3 branch.
570. **`fediverse_test.rb:40` skip if no second city.** Seed a second city in fixtures so the skip never fires in CI.
571. **`tradedoubler` skip unless table.** Migrations should make this impossible; if skip remains, schema load is incomplete.
572. **`partner_attribution_report_test` skip unless constant.** Load path bug — require the model.
573. **System tests:** no system test for dating swipe or marketplace checkout.
574. **`query_budget_test.rb`.** Extend to listings#index with facets.
575. **`attachment_preload_test.rb`.** Add TV show comments/notes and marketplace show questions.
576. **`turbo_broadcast_contract_test.rb`.** Add stream_chat broadcast explicit `partial:`.
577. **Engine `rake test` from engine dir.** Document `bin/ci` includes engines. Maps none.
578. **`infinite_scroll_reflex` TV channels.** `_live_search_results` references `ChannelsInfiniteScrollReflex` — verify class exists under tv, not host.
579. **Almost no `limits_concurrency`.** Only `RecommendOutfitsJob`. Add to: `AffiliateImportJob`, `PortsImportJob`, `NightlySearchIndexRebuildJob`, `ListingExpiryJob`, `SavedSearchAlertJob`, `ExpiredStoriesSweepJob`, `ExpiredMessagesSweepJob`, `ComposeNewsletterEditionJob`, `LinkConverterSyncJob`, `UserPurgeJob`, `DeclutterHygieneJob`.
580. **`LinkConverterSyncJob` every 5 minutes.** Can stack. Concurrency 1 + uniqueness key.
581. **`NightlySearchIndexRebuildJob` no-op without `posts_fts`.** Silent return. Log.
582. **`GenerateBlurhashJob` uniqueness per blob.**
583. **`DillaRenderJob`.** Must not overwrite takes. Assert the output lands beside `STUDIO/dilla/dilla.rb` or the brgen equivalent; never `$PWD`.
584. **`PostproJob` from listing create.** If worker busy, listing has unprocessed photos. Status column?
585. **`GoogleEnhancedConversionsJob`.** PII. Test it no-ops without env; don’t retry forever.
586. **`ChannelBotReplyJob`.** Rate; loop guard.
587. **`Fediverse::DeliveryJob` uniqueness per inbox+activity.**
588. **`NotificationDeliveryJob` double-push.** **Unverified** internals. Test like/follow once.
589. **`CableHealthJob` / `CacheHealthJob`.** If they alert, test; if not, don’t schedule.
590. **`playlist` likes_count/plays_count nullable.** NOT NULL 0.
591. **`tv_videos.views_count` nullable.** Default 0.
592. **`identity_assurances.expires_at` unindexed.** If any scope queries it, index; if nothing reads it, don’t add. **Unverified** readers.
593. **`notifications` polymorphic index.** Confirm `(notifiable_type, notifiable_id)` exists.
594. **`marketplace_orders.variant_id` indexed?** Verify if `find_by(variant_id)` in stock decrement. **Unverified.**
595. **Grep remaining `update_column` without `updated_at`.** WIRING_NOTES trap.
1061. **`.page-header` is five different elements across the verticals.** Measured at
     1440px on 2026-09-12: absent on markedsplass and playlist, 0px wide on dating,
     747.03px on takeaway (max 747.035px), 600px on tv, and absent on brgen's front
     page, which uses `.feed-header` instead. So the shared page-header contract in
     `shared/LAYOUT.md` describes an element that four of seven surfaces do not
     render and one renders at zero width. Either the contract names the wrong
     element or the verticals do — deciding which is a layout call and the
     operator's; the measurement is here so it is not made blind.

596. **The prescription is wrong, and measuring it found a smaller real thing.**
     Measured at 1440px on 2026-09-12, `.layout` max-width: brgen 600px, tv 600px,
     markedsplass / dating / playlist / takeaway all 100%. `--feed-max` is 600px on
     every one of them, so the four are opting out by rule, not missing a token —
     and each opt-out has an argument. marketplace and takeaway are storefronts:
     takeaway's own comment says the 600px column crushes the two-row #navBar and
     leaves the restaurant grid no room, and Kaufland is the model there. dating and
     playlist are immersive verticals — `_vertical_shell.scss` hides the core chrome
     on them, so there is no column for content to sit in. tv is the browsable one
     and already has the column. Applying `.app-shell`'s measure cap to all four
     would undo two deliberate decisions.

     What was real: dating and playlist each set `grid-template-areas: "main"` and
     `grid-template-columns: 1fr` on `.layout`, which is `display: flex` in
     `_shell.scss` on every surface — measured flex on brgen, dating, playlist and
     markedsplass alike. Four inert declarations, removed; max-width and display
     measured identical before and after.
597. **`_ui_refinements*` merge.** Boy Scout on next CSS touch — merge into domain partials, no visual change.
598. **`_shared_coverage_fills.scss`.** If it exists only to satisfy css_coverage_lint, that’s a spelling gate — prefer real selectors or fix the lint.
599. **`_stack_brgen.scss` vs `_stack.scss`.** Document why two.
600. **`pull_to_refresh_controller.js`.** Confirm not fighting Turbo morph.
601. **`tabs_controller.js` vs nav swiper.** Two tab patterns. Feed sort should reuse one.
602. **`countdown_controller.js` vs `Deal#ends_in`.** Deals use `distance_of_time_in_words`. If countdown JS unused on deals, don’t load globally.
603. **`share_controller.js`.** i18n toast.
604. **`form_submit_controller.js#lock`.** Attach to listing create / takeaway order.
605. **`lazy_image_controller.js` vs `responsive_image_tag`.** One path.
606. **`lightbox_controller.js` vs lightgallery vendor.** Pick one.
607. **Listing kinds `chip` vs `chip active`.** `aria-current`.
608. **Stimulus controllers without a matching test.** `countdown`, `feed_updates`, `form_submit`, `lazy_image`, `lightbox`, `map`, `pull_to_refresh`, `push`, `radio_tunnel`, `request_location`, `share`, `swipe`, `tabs`, `toggle`, `typing`, `typing_input`, `voice_recorder`, `dating_intro`, `marketplace_logo`, `playlist_player`, `tv_feed`, `tv_player`, amber `filter` / `sortable` / `wardrobe_carousel`. One Node-free contract per controller, or a source contract that each is mounted by a view (the infinite-scroll pattern).
609. **Webhook CSRF skip without rate_limit.** Engine + host Stripe/Vipps/TradeDoubler. Add IP limits.
610. **`AiController` unbounded work.** Auth + rate_limit. Argv array is OK; still a 1 GB box.
611. **`TrackImport` URLs.** SSRF like `LinkPreviewFetchJob`. Reuse `OutboundHttp`.
612. **Mass assignment kinds.** `listing_params_for_kind` — ensure `kind` not user-switchable after create to skip price.
613. **Push subscriptions controller.** Rate-limit subscribe. VAPID per app (521).
614. **Guest photo upload.** Rate-limit + size via `MediaGuard`. Confirm `MediaGuard` on messages#create.
615. **Posts new form English.** `posts/new.html.erb:13-14` `f.label :community_id, "Community"` / `include_blank: "Anywhere in Bergen"`; `:30` `"Body"`; `:60` `Add photo`; `:72` `"Post anonymously"`. All keys. City-aware blank, not Bergen on every host.
616. **`users/new.html.erb:43` “Leave this field empty”.** Honeypot label. i18n; keep off-screen.
617. **Playlist hosted tracks.** `"Replace audio file (keeps URL)"`, `"Upload track"`, `"Unknown artist"`, `"Create playlist"`, `"Only owners can invite collaborators."`
618. **Shared empty_state comment example is English.** Fine as a comment. Callers must pass `t(...)`. Audit callers that pass English string literals.
619. **Newsletter `_hero.html.erb:14` “Curated offers”.**
620. **Untested engine models.** dating: `daily_pick`, `dislike`, `like`, `prompt`, `verification`. marketplace: `address`, `category`, `checkout`, `gig_detail`, `housing_detail`, `job_detail`, `listing`, `listing_favorite`, `payout`, `question`, `return`, `review`, `saved_search`, `store`, `variant`, `variant_option`. playlist: `audio_version`, `collaboration`, `dilla_sketch`, `like`, `listen`, `party_message`, `playlist_track`, `set`, `set_track`, `timestamped_comment`, `track`. takeaway: `delivery_driver`, `favorite_restaurant`, `menu_item`, `opening_hour`, `order_item`, `restaurant`, `review`. tv: `broadcast`, `channel`, `episode`, `live_stream`, `show`, `sound`, `stream_chat`, `subscription`, `video`, `video_note`. One model test each, starting with state machines and uniqueness.

### OPENBSD — dual sources

621. **`sh/` does not exist.** `OPENBSD/README.md` claims deploy tooling lives under `bin/`, `lib/`, `sh/`. There is no `OPENBSD/sh/`. Drop `sh/` from the sentence.
622. **Same ghost path in law.** `OPENBSD/DECISIONS.md` “Repo Layout” still lists `sh/`. Align with the tree.
623. **PATH_OWNERSHIP still names `openbsd/sh/vps_ci.sh`.** File is `OPENBSD/vps_ci.sh`. Fix the key and the `zsh -n` check path.
624. **Fixed 2026-09-12.** `README.md` carries no table at all — zero table rows,
     checked. `SSH_ACCESS.md` now names its own Architecture block as the network
     map, which is what it always was, three lines under the pointer that sent the
     reader elsewhere for it.
625. **Fixed 2026-09-12.** The paragraph named four hosts; `bin/uptime-check.sh`
     execs `health_check.rb --public-only --all-ready-apps` and has no URL list of
     its own. It now says that, and says what `--public-only` costs: the service,
     certificate and relayd checks are the same script without the flag.
626. **Fixed 2026-09-12.** Four rows against ten scheduled jobs, so six self-healing
     jobs — uptime-check, drain-jobs, core-reclaim, keep-warm, prune-guests and
     weekly-integrity — existed only in `etc/crontab.vm23` and not in the table an
     operator reads. All ten are listed. The `relayd-watchdog` row credited it with
     healing `doas.conf`; that step ran `validate_doas.ksh` from a dev-owned
     checkout as root every five minutes and was deliberately removed, which its own
     header records. The weekly-integrity row carries its never-installed state
     rather than implying it runs.
627. **Fixed 2026-09-12.** `vps_production_push.sh` deploys bsdports too — its own
     first line says so and line 36 runs it. The table said master + brgen + amber,
     which understates a footgun, and understating that one is the wrong direction.
628. **httpd 6666 comment vs CLAUDE.** `CLAUDE.md` still says `httpd.conf` listens on `* port 6666`. Live file listens on `127.0.0.1 port 6666`.
629. **MEM_RESTORE drift — fixed 2026-09-12.** OPENBSD/CLAUDE.md said 8/14 for a
     month after resource_guard.sh moved MEM_RESTORE to 10 on 2026-08-14, a
     recalibration the script records with the 1550 ticks behind it. The doc
     names the current pair and points at the script;
     `test_guard_thresholds_documented` refuses prose that names a different
     number from the code.
630. **Fixed 2026-09-12.** The comment had it backwards in both directions: amber is
     in `OPTIONAL="bsdports amber"` and master is in `CORE="master brgen"`. It no
     longer reasons from the guard's sets at all — brgen and amber are simply the
     two surfaces a visitor arrives on cold, and the shed case was already handled
     six lines below by the per-target `nc -z`.
631. **Fixed 2026-09-12.** `OPTIONAL="bsdports amber"` now, matching the guard.
     litestream is doubly stale: `restore_backups.sh` records that no litestream
     binary exists on vm23 and `/var/backups/litestream/` is empty.
632. **Fixed 2026-09-12.** `data/operator.yml` is the command list and now carries
     the whole of it: the check family (check-rails, check-openbsd, check-vps,
     check-full), vps-state and tree.sh lived only in START_HERE.md's Golden
     Commands, so the stub that pointed here was the more complete of the two.
     START_HERE's Golden Commands and Source Of Truth sections are pointers now,
     and RECIPES.md is a door rather than a table. `operator_docs.rb` reads the
     yaml and `/orient deploy` prints it, so a recipe added there shows at every
     door.
633. **Fixed 2026-09-12.** `data/operator.yml` is the command list and now carries
     the whole of it: the check family (check-rails, check-openbsd, check-vps,
     check-full), vps-state and tree.sh lived only in START_HERE.md's Golden
     Commands, so the stub that pointed here was the more complete of the two.
     START_HERE's Golden Commands and Source Of Truth sections are pointers now,
     and RECIPES.md is a door rather than a table. `operator_docs.rb` reads the
     yaml and `/orient deploy` prints it, so a recipe added there shows at every
     door.
634. **Fixed 2026-09-12.** START_HERE.md's Source Of Truth section listed
     `RAILS/apps.yml` under both "App inventory" and "Feature inventory". That whole
     section is a pointer to `operator.yml`'s `single_source_of_truth:` now.
635. **DECISIONS vs unsigned zones in git.** “61 zones … none of them in git”. `var/nsd/zones/master/` holds 57 unsigned `*.zone` templates by design. Narrow the decision to signed artifacts / keys.
636. **RUNBOOK still describes a fixed deploy_all header.** Current header says there is no archive. Update RUNBOOK.
637. **deploy_all still logs archive/recovery.** `deploy_all.sh:49`. Delete the log line.
638. **tools/tree.rb still DRIFTs a missing dir.** Prints `archive/recovery` as DRIFT. Drop both.
639. **PATH_OWNERSHIP lists `archive/`.** Directory does not exist. Remove the row.
640. **Retired-apps prose vs extra_zones.** RUNBOOK says foodielicio.us went with baibl; `data/dns.yml` `extra_zones` still serves them. Pick one source.
641. **Fixed 2026-09-12.** The comment lives in `render_dns.rb`, and it was wrong
     twice: the count is four, not five, and `bsdports.net` has no zone at all —
     `bsdports.org` is the one with a zone and it is in ALL_DOMAINS, so it was never
     in that set. Computed from `city_zones` and `extra_zones`: 53 city, 13 extra,
     four outside — the anti-gambling trio and foodielicio.us. render_dns reports in
     sync across all 57 zones, so nothing rendered changed.
642. **extra_zones duplicates ALL_DOMAINS.** Keep extras only for names not in ALL_DOMAINS.
643. **doas.conf.example is a different policy.** Mark the example historical or generate it from the live file.
644. **sshd_config is a fragment.** Either track the whole file or say this is a fragment OPERATOR merges.
645. **login.conf is the OpenBSD sample.** Confirm whether app login classes still live here; if unused, stop installing it.
646. **vm_resource.yml falcon workers.** `master_falcon_workers: 2`. `etc/rc.d/master` uses `${FALCON_WORKERS:-1}` and comments “keep at 1 on 1GB”. Make the yaml match.
647. **vm_resource.yml load comment vs guard.** Guard uses 5-minute load; yaml keys are `load_avg_1m_*`. Rename keys to 5m or stop claiming they mirror.
648. **operator.yml Solid Queue vs rc.conf.local.** Add a one-line “must match pkg_scripts” note.
649. **CLAUDE vs RUNBOOK on SKIP_CI.** Make RUNBOOK a pointer at CLAUDE’s section.
650. **START_HERE “check-full chains local checks and the integrity gate”.** `bin/check-full` also runs `RAILS/test/run_all.rb`. Name that third step.
651. **PATH_OWNERSHIP RAILS paths with lowercase `rails/`.** Use real paths `RAILS/` / `OPENBSD/`.
652. **PATH_OWNERSHIP omits most of the tree.** Add rows or a glob policy for `data/`, `test/`, `gates/`, `lib/`, `dotfiles/`, `quarantine/`.
653. **PATH_OWNERSHIP `tools/` check is `MASTER/tools/verify`.** Point at `OPENBSD/bin/check-openbsd` or a local test.
654. **deploy_inventory `generated_at: 2026-07-15`.** Regenerate on apps.yml change or drop the date.
655. **sync_deploy_inventory drops `standalone_apps`.** Preserve the key.
656. **health_check public master is a literal.** `:411` `"ai.brgen.no"`. Read `deploy_inventory.json` `master_face`.
657. **Two uptime checkers, two master policies.** One function, one list.
658. **Fixed 2026-09-12.** `data/dns.yml` declares `resolvers.public`, and
     `gates/dns_zones.rb` reads it along with `nameserver.ip` instead of carrying
     its own two literals. The copies had already drifted: OPERATOR.sh led with
     8.8.8.8 while the gate used Cloudflare and Quad9 and had written down why, so
     the gate's list won and OPERATOR.sh dropped Google. `test_dns_facts_agree`
     fails if either copy moves without the other.
659. **Fixed 2026-09-12.** `data/dns.yml` declares `resolvers.public`, and
     `gates/dns_zones.rb` reads it along with `nameserver.ip` instead of carrying
     its own two literals. The copies had already drifted: OPERATOR.sh led with
     8.8.8.8 while the gate used Cloudflare and Quad9 and had written down why, so
     the gate's list won and OPERATOR.sh dropped Google. `test_dns_facts_agree`
     fails if either copy moves without the other.
660. **Held rather than moved, 2026-09-12.** They stay as shell literals: the block
     is sourced before anything runs, and making the deploy script shell out to
     ruby34 to boot would put it behind an interpreter it is itself responsible for
     installing. `test_dns_facts_agree` asserts BRGEN_IP is `nameserver.ip` and
     HYP_IP the first `xfr_peers` entry, so the duplication now costs something.
661. **relayd-watchdog BACKENDS table hardcoded four ports.** Add this file to `SMOKE_SCRIPTS` / `FLEET_INVENTORIES`.
662. **Fixed 2026-09-12.** The names come from the same read as the ports, twelve
     lines below where the frozen `%w[brgen amber bsdports]` used to sit — the file
     was already loading apps.yml for ports and keeping a second inventory for
     names, so a fourth app would have shown its port and never its row. master
     keeps its own block: it is not under /home/*/app and not in apps.yml.
663. **vps_ci_all apps hardcoded.** Same.
664. **start_all_apps SERVICES hardcoded.** Derive from inventory + master.
665. **Declined 2026-09-12, and the file now says why.** TARGETS is a curated pair,
     not a stale copy of the fleet: brgen and amber are the surfaces a visitor
     arrives on cold. Reading apps.yml would warm bsdports, a low-traffic index
     nobody waits on, and master, whose 927M of address space is correctly swapped
     out until someone opens the face. The shed case is handled per target by the
     `nc -z` below the list.
666. **Fixed 2026-09-12.** Falling back is a finding now: the built-in names are
     still checked, because knowing those four are up beats checking nothing, but
     the run exits nonzero whatever they answer and says the exit code is the
     missing list rather than them. A green uptime check measuring a fleet one
     deploy out of date is exactly what the file's own header warns about. The
     fallback names and the derived list agree today: brgen, amber, bsdports,
     master.

### OPENBSD — scripts, expect, gates

667. **vps_deploy_master.sh is a second MASTER deploy.** Keep as recovery (already decided) but have it call `vps-deploy master`.
668. **vps_production_push vs vps-deploy all.** Make push `SKIP_CI=1 vps-deploy all` plus the optional demo seed.
669. **vps_install_all vs vps_on_vm_install.** Fold into one “bootstrap on box” script; the other becomes a one-line wrapper.
670. **vps_install_all stashes the box.** `git stash push`. Root TODO records that stashing Gemfile.lock on vm23 broke master. Delete the stash; `git pull --ff-only` only.
671. **smoke-apps.sh vs deploy-smoke.sh.** Make smoke-apps a `deploy-smoke --local` alias or delete it and retarget `port_inventory` `SMOKE_SCRIPTS`.
672. **check vs check-openbsd overlap.** Document a Venn in START_HERE, or have `check` call `check-openbsd` instead of repeating identity/smoke.
673. **check-full vs integrity_gate.** Deduplicate the integrity list.
674. **check-vps ON_VPS test is a third predicate.** One helper: `Operator::Environment.on_vps?`.
675. **check-openbsd uses `RbConfig.ruby`, check uses `Operator::RubyRunner.gate_ruby`.** Use the gate runner everywhere.
676. **tree.sh header still talks about “MASTER KISS/DRY redesign”.** One-line usage.
677. **solid_queue_proof.sh is a doas trampoline.** In-line in the caller or `bin/`.
679. **extract_legacy_installers.sh vs restore_backups.sh.** If the source is gone forever, make extract exit 2 with that sentence.
680. **extract_legacy uses `tr`.** Banned. Use zsh `${rel//\//_}` or Ruby.
681. **`_net.sh` `generate_random_port` always errors.** Delete if unused, or make unused-path fail at parse.
682. **OPERATOR tmux falcon fallback.** Starts a second falcon as **dev**. Conflicts with `daemon_user="master"`. Remove or refuse if rc.d/master is enabled.
684. **deploy_all.sh default `SSH_KEY=~/.ssh/id_rsa`.** Every other file uses `id_ed25519_brgen`. Change the default.
685. **deploy_all VPS_HOST is a bare IP.** Source `lib/ssh_vm23.sh` and drop the copy. Same for `vps_run_remote.sh`.
686. **post-pull-checklist is a here-doc.** Generate from `operator.yml` or delete in favour of `operator status`.
687. **deploy-diff.sh vs sync.rb vs config_drift_gate --remote.** Make deploy-diff a wrapper over the gate’s report.
688. **dev/agent_worktree.sh vs MASTER/bin/operator worktree.** Exec the operator command or delete it.
689. **dev/*.sh (backup, clean, lint, perms, replace, watch_tests).** Workstation helpers in the OpenBSD tree. Move to `dotfiles/` / `MASTER/tools/` or declare Mac-only with check `none`.
690. **ptr_openbsd_amsterdam.rb has no test.** Add a dry-run test that the request is built, not sent.
692. **sync.rb FIXED_SOURCES vs config_drift VERBATIM.** Make sync’s source list = VERBATIM + EXCLUDED so a hand-edit cannot hide in a file sync never copies.
697. **port_inventory RETIRED_ACTIVE_PATHS includes live console shims.** Rename the list; they are not retired.
699. **test_health_check.rb measures spelling.** Replace with a `--public-only` run against a stub CURL that returns 200/000.
700. **`--public-only` not in the flag test.** It is the laptop path.
704. **verify_openbsd_idempotency.rb is source grep on OPERATOR.sh.** Add a known-bad fixture (OPERATOR snippet missing the backup).
705. **verify_deploy_identity.rb is string includes on `_deploy.sh`.** Assert the functions exist via `zsh -c 'source …; whence -w deploy_tracked_app'`.
706. **No OPENBSD test for dns_zones / domain_alignment / port_inventory / installed_targets / deploy_smoke.** Each wants a known-bad fixture (decision 2026-08-22).
707. **No test for integrity_gate.rb.** Assert skip_reason for `:vps` off-box, and that `:live_http` / `:repo` needs are actually consulted.
708. **GateEnvironment skip_reason ignores `:repo` and `:live_http`.** Wire them or drop them from the structs.
709. **test_gate_lib does not cover `GateResult#measured_nothing?`.** Add the empty-run vs checked! cases here.
710. **config_drift_gate tests only crontab.** Add a VERBATIM file mismatch and an EXCLUDED file that must *not* fail.
711. **installed_targets CONFIG_GLOBS miss usr/local.** Include `usr/local/bin/*` as referrers or document the hole.
712. **check does not run installed_targets, dns_zones, vps_safety.** Those live only in `check-openbsd`. Either include them or say contributor must run both.
713. **Fixed 2026-09-12, and wider than asked.** `OPENBSD/shell_syntax_gate.rb`
     reads each script's shebang and parses it with the interpreter that shebang
     names, so the set is the tree rather than a list somebody maintains. It covers
     43 scripts across zsh, ksh and sh — all of which parse today — and replaces the
     two hand-named lines, so check-openbsd got shorter. Recorded as OPENBSD 112 ->
     113 in spine.yml.
714. **deploy_smoke_gate check_master_rc is a string hunt.** Assert “warmup hits a public unauthed path”, not that exact `chat/message?message=ping` query.
715. **domain_watch population is nsd.conf.** Read `RenderDns.zones` so a zone not yet in nsd.conf still gets whois.
716. **test_domain_expiry `--update` needs `/usr/bin/timeout`.** Document in START_HERE: refresh on vm23; local red is not a code defect.
717. **domain_released.yml is empty while five domains fail.** Point failure output at this file so the next agent does not “fix” the test.
718. **weekly.local runs domain_watch from the checkout as dev.** PATH_OWNERSHIP does not mention `bin/domain_watch.rb`. Add it.
720. **daily.local comments should state the two questions** (repo-versus-live `/etc` bytes vs relayd/acme/nsd consistency) in one line each.
721. **bin/check loads all OPENBSD tests in one `-e` process.** One process per file, as check-full already does for Rails.
722. **reach.rb vs installed_targets_gate.** Wire reach into check-openbsd or fold its unique checks into installed_targets.

### OPENBSD — shell, rc.d, DNS, tests, remaining

726. **start_all_apps.sh: `set -e` without pipefail.** Add `set -eo pipefail`.
727. **vps_deploy_master.sh: `set -e` only, `#!/bin/sh`.** Add pipefail.
729. **renew-certs.sh add `--help`.**
730. **tree.sh `CDPATH= cd` vs `CDPATH='' cd --`.** Use the safer form.
731. **dev/agent_worktree.sh add `--help`.**
733. **rails-app.tmpl is a third rc.d.** No PATH export, `pexp="ruby.*${port}"` not `ruby34`, `daemon_timeout="60"` not 120. Either regenerate apps from a fixed tmpl or delete the tmpl and stop OPERATOR from installing it.
734. **irc_gateway has no PATH, no pexp.** Match brgen’s PATH/`bundle34 exec` shape so a go-live does not repeat the cron-PATH outage.
735. **amber vs brgen env paths.** Document which of the three paths is live; drop the others from the scripts.
736. **rc.d/master `bundle34 install` in rc_pre with `|| true`.** Fail the start if `bundle34 check` fails; do not install from rc.d.
737. **rc.d/master pkill patterns include `operator/MASTER/web`.** Stale path after OPERATOR→OPENBSD. Confirm pexp still matches; drop dead pkills.
738. **pf.stage1.conf has no 443 or 25.** RUNBOOK should say “stage-1 pf will not pass HTTPS or SMTP”.
739. **httpd listens 0.0.0.0:80.** `deploy_smoke_gate` does not check httpd.conf exists or has the ACME location. Add a one-line assert.
740. **acme-client.conf pair.** Mention in RUNBOOK that dns_zones `--check` diffs it so nobody byte-compares acme.
741. **relayd keypair list vs LIVE_DOMAINS.** Add the six “waiting” cities from RUNBOOK as an explicit not-yet list.
742. **OPERATOR.sh `EMAIL_ADDRESS="bergen@pub.attorney"`.** If unused, delete.
743. **newsyslog misses `/var/log/domain_watch.log`, `git_gc.log`, `/tmp/config-drift.out`.** Add rotation or write under `/var/log/`.
744. **rc.d/*_jobs footers are triplicated.** One `etc/rc.d/jobs.footer` comment file, or a shared tmpl with APP filled in.
745. **Run `render_dns.rb --check` in `check-openbsd` directly** so a DNS edit does not require the Rails gate registry.
746. **nsd.conf `server-count: 2` on 1 vCPU.** Put `server-count` in `data/dns.yml` (default 1 for vm23_small).
747. **False — checked 2026-09-12.** `render_dns.rb:84` reads it
     (`policy.dig("extra_hosts", domain)`) and `dns.yml:119` carries
     `brgen.no: [ns, amber]`, which is how ns.brgen.no and amber.brgen.no get their
     A records. Both halves are live.
748. **DMARC assert in `--check`.** Do not also emit `_dmarc` in zone_body for mail_domain.
749. **domain_inventory.yml `state: unknown` never alarms.** Fail or skip-with-count so “32 unknown” is visible.
750. **Nominet dates in inventory are already past.** Add `domain_watch --update` recipe in operator.yml.
751. **Argued against, and the argument is in the file.** `data/dns.yml`'s header
     states it: the domain list is deliberately not there, because ALL_DOMAINS is
     already what `domain_alignment` binds `Brgen::DomainRegistry` to, and a yaml
     copy would be a third list rather than one. The regex parse is real and is what
     that costs. Moving it means moving the binding too, which is a deploy-path
     decision and the operator's. See 32, which is the same proposal.
752. **Fixed 2026-09-12.** `OPENBSD/test/test_vps_deploy_contract.rb` — refuses uid
     0 with an exit rather than a warning, `all` expands to apps.yml plus master in
     the order the script argues for, and SKIP_CI=1 still runs `${app}.sh`, which is
     what reaches rails_runtime_gate. See 779 for the mutation check.
753. **No test for OPERATOR.sh beyond zsh -n and idempotency grep.** Add: `ALL_DOMAINS` parse round-trip against `render_dns` city_zones.
754. **resource_guard crisis path.** The test should fail if the crisis function’s path is not in `explicitly_installed`.
755. **test_restore_scripts.rb.** Add an executable dry-run with `LITESTREAM_CONFIG` pointing at a missing file, expect exit 1.
756. **test_githooks.rb.** PATH_OWNERSHIP should name `dev/githooks/` with this test as `check`.
757. **test_tracked_crontab.rb vs config_drift crontab tests.** Fold or cross-reference so a new cron line needs one fixture.
758. **No test for nsd-resign.** Fixture: a signed zone with a parseable RRSIG vs garbage. `rescue nil` on expiry parse swallows errors.
759. **No test for renew-certs.sh intersection logic.** Unit-test CONFIGURED∩HELD in zsh with tmp crt/conf dirs.
760. **No test for prune-guests.sh wait loop.** A ksh test with `PRUNE_GUESTS_LOAD_CEILING=0` should still run one tick.
761. **No test for drain-jobs.sh / keep-warm skip-if-not-listening.**
762. **health_check `--core` banner.** State that smtpd is required and master is a service not an app.
763. **“Every gate carries its known-bad fixture” (2026-08-22).** Adopt-forward: next touch of each gate adds the pair.
764. **“No staging environment” is still open.** Point `vm_resource.yml` at this entry so a “add staging” idea dies in one place.
765. **“Auto-commit atomicity” is still open.** Belongs in MASTER/dev hooks, not OPENBSD/DECISIONS. Move or delete.
766. **Deploy script names still say `RAILS/deploy.sh`.** If per-app `RAILS/<app>/<app>.sh` is the truth, fix the decision line. **Unverified** whether `RAILS/deploy.sh` exists (it does at tree root).
767. **Gate kernel decision vs PATH_OWNERSHIP.** Add `lib/` row with the decision’s check.
768. **doas install decision vs RUNBOOK.** RUNBOOK still says cron heal paths use `validate_doas.ksh`. Heals were removed.
769. **Fixed 2026-09-12, and the premise needs a correction.** It did not fail open:
     measured in an isolated checkout with no apps.yml, the old code still exited 1
     — but by way of "brgen: missing port in apps.yml", because `core_apps` hardcodes
     brgen. The right answer for the wrong reason, and only by accident of that
     hardcoding. The real cause went to stderr where the --json consumers never saw
     it. It is a first-class entry in `failures` now, so the JSON carries it.
770. **health_check `--core` still requires smtpd.** Document as required.
771. **resource_guard ALL_APPS_FLAG vs start_all_apps.** Name the flag in PATH_OWNERSHIP.
772. **Measured 2026-09-12 — the layout question is secondary to what it hides.**
     `emergency_cpu.sh` is not on vm23 at all. `resource_guard.sh:298` guards with
     `[ -x /usr/local/bin/emergency_cpu.sh ]` and otherwise logs "emergency_cpu not
     installed", so the LOAD_CRIT crisis path — the one deliberately exempted from
     the two-strike rule because a genuine crisis should not wait — has only ever
     written a log line. Installing it needs doas on the box and is the operator's.
     The repo-layout half (root vs usr/local/) still stands and is item 21's.
773. **Crisis tier on the box is missing the binary.** Confirm `explicitly_installed` scan matches `install -m 755 … emergency_cpu`. **Unverified scan.** If the install line does not match the regex, fix the regex, not the box.
774. **etc/litestream.yml header still reads as a how-to.** First lines should be: inert by decision; not in ports; do not enable; dr-pull is the backup. Keep the yaml body.
775. **OPERATOR `setup_litestream`.** Add `rcctl ls failed` must not contain litestream as a check in health_check.
776. **Fixed 2026-09-12.** `OPENBSD/restore_litestream.sh`. Three separate passes
    asked for this rename, which is what a real defect looks like from outside.
    Its first line now reads "NOT the disaster-recovery script — use
    OPENBSD/bin/dr-pull for that", and the paragraph under it says why: vm23 has
    no litestream binary and no replicas, so the old name promised recovery the
    file cannot deliver, under exactly the name somebody reaches for in an
    emergency.
777. **port_inventory RETIRED_CONFIG_PATHS includes litestream.yml.** Add a positive test: litestream.yml may exist, must not appear in pkg_scripts.
778. **vps-deploy drift gate is advisory.** Add `VPS_DEPLOY_DRIFT=fail` opt-in. Do not flip to blocking from here (box is dirty).
779. **Fixed 2026-09-12 as a test, not a derivation.** Deriving the list would lose
     the ordering argument the script writes down — master leads because it is
     independent and gets forgotten, amber and bsdports go last because every deploy
     sheds them and deploying them last folds the restore into the same pass.
     `test_vps_deploy_contract` asserts DEPLOY_ALL is apps.yml plus master and holds
     both ends of the order. Closes 752 with it: the same file covers the uid-0
     refusal and the SKIP_CI branch. Mutation-checked — dropping master fails 2,
     reordering 1, warning instead of exiting 1, gutting SKIP_CI 1, clean source 0.
780. **vps_production_push DEMO_SEED_ON_DEPLOY defaults to 1.** Production hotfix seeds the demo. Default 0; require an explicit 1.
781. **vps_deploy_master.sh `SECRET_KEY_BASE` openssl rand fallback.** Can boot master with a random key, wiping sessions. Refuse if `/etc/master.env` has no key.
782. **vps_on_vm_install `SECRET_KEY_BASE:-dummy` for assets:precompile.** Same class of footgun. Read `/etc/master.env`.
783. **`bin/vps-deploy` has usage on missing args, not `--help`.** Accept `-h`.
784. **integrity_gate post_pull_warning still says `zsh OPENBSD/vps_ci.sh`.** Canonical is `bin/vps-deploy`.
785. **deploy_inventory.json has no `standalone_apps` consumer except empty.** If unused, drop the key from the schema and the Inventory class.
786. **dotfiles/ is a Mac desktop setup.** Declare `purpose: operator Mac; not installed by OPERATOR.sh; check none` or move out of OPENBSD.
787. **fix_macos.sh references `FUN/config/`.** That tree does not exist. Point at `dotfiles/config/`.
788. **PUB4_ROOT in fix_macos is `SCRIPT_DIR/..`.** That is OPENBSD/, not repo root. `cd "${SCRIPT_DIR}/../.."`.
789. **zshrc.shared vs box `/home/dev/.zshrc`.** OPERATOR mentions `etc/.zshrc`. Find the tracked zshrc or stop syncing it. **Unverified path.**
790. **quarantine/virus_museum.** PATH_OWNERSHIP check should name `MASTER/tools/security_sweep.rb`. RUNBOOK: recovery is `bin/dr-pull` and `manual_master_deploy.ksh`; quarantine is inert samples.
791. **Missing `--help` / usage** on `bin/vps-deploy`, `vps-state`, `ds-records`, `render_dns.rb`, `domain_watch.rb`, `sync_deploy_inventory.rb`, `with-ci-lock`, `dr-pull` (**unverified**), `start_all_apps.sh`, `emergency_cpu.sh`, `vps_ci.sh`, `vps_ci_all.sh`, `vps_install_all.sh`, `vps_on_vm_install.sh`, `vps_master_scan.sh`, `resource_guard.sh`, `core-reclaim.sh`, `keep-warm.sh`, `drain-jobs.sh`, `prune-guests.sh`, `tree.sh`. Pattern: `deploy-smoke.sh`.
793. **keep-warm has no heartbeat.** Touch `/var/db/keep_warm_seen` each run; health_check already has the pattern.
795. **OPERATOR.sh `2>/tmp/pkg_add.log`.** Use `/var/log/pub4/`.
796. **home/johann/bin/mailimg.** PATH_OWNERSHIP should list it as the executable check (`ksh -n`).
797. **stale_ci_cleanup.ksh lives under usr/local/libexec.** Include `/usr/local/libexec/` in installed_targets.
798. **gates live under OPENBSD/gates but run via RAILS/gates/runner.rb.** One paragraph in START_HERE: registered in `RAILS/gates/gates.yml`, invoked by `check-openbsd`.
1062. **`.dash-stats dl` wants auto-fit and could not be verified for it.** Amber's
     stat grid is four columns, two below md, and nothing between — a tablet gets
     the phone grid. `repeat(auto-fit, minmax(<floor>, 1fr))` computes the count and
     adds the three-column step, which is the right shape. It was written and then
     reverted on 2026-09-12: the floor has to be measured against the real dashboard
     container, that page is behind a login the CDP probe cannot reach, and a floor
     guessed wider than the column silently drops desktop from four columns to
     three. Measure the container, then set the floor.

1063. **`_root.scss:334` is the last max-width, and it is not a violation.**
     `(min-width: 768px) and (max-width: 1264px)` swaps `.compose-label` for
     `.compose-icon` in a band. MOBILE_FIRST does not flag it — the detector reads
     `@media (max-width` and this opens with min-width — and the max is the upper
     bound of an enhancement rather than a narrow-screen exception. Closing it would
     need the two elements' default display values, which have no rule anywhere in
     the tree and sit behind the same login. Left deliberately.

1064. **radio.<city> is live on vm23 — deployed 2026-09-12.** DNS, certificate and
     relayd landed together, because DNS alone would have made radio.<city> resolve
     to a box holding no certificate for it, which a browser reports as an attack.
     Order: 44 zone files copied and `nsd-resign --force` re-signed and reloaded all
     57 with the existing keys (no KSK touched, DS unchanged, NOERROR through a
     validating resolver); `acme-client.conf` installed and `renew-certs.sh`
     reissued 7 of 9 held certificates, so `brgen.no` now carries
     `DNS:radio.brgen.no` and no longer carries playlist; relayd restarted once by
     that script. Verified: `https://radio.brgen.no/up` answers 200,
     `playlist.brgen.no` resolves nowhere, and `health_check --public-only
     --all-ready-apps` reports bsdports.org as its only failure, which is the
     registrar parking already recorded.
     The zone directory was backed up to
     `/var/backups/pub4/nsd-zones-pre-radio-*.tar.gz` first, and relayd.conf and
     acme-client.conf to the same directory.

1065. **trymbot is off vm23 — done 2026-09-12.** The repo retired it on 2026-08-28
     (`spine.yml` 148 -> 145) and production ran it for two more weeks:
     `/etc/relayd.conf` held a `tls keypair` line and a Host match to `<master>`,
     and `/etc/ssl` held `trymbot.brgen.no.{crt,key}` symlinks plus a
     `brgen.no.fullchain.pem.bak-trymbot`. All removed. It had no DNS record and no
     acme SAN, so it had already stopped resolving.
     This is the case `relayd.conf repo-vs-live divergence` warns about, in its
     sharpest form: the repo was MISSING two lines the box was running, so
     installing the repo copy wholesale would have deleted a live host. The two
     files are byte-identical now, and both dropped off `config_drift --remote`.
     Two mentions stay in `spine.yml` and `dup_census.yml`; they are ratchet-fall
     justifications, and deleting them would break the rule that a fall records
     what paid for it.

1066. **A guard for listener-vs-topic drift is worth building and is not free.**
     Four dead event names in `visual_bridge.js` were found by hand on 2026-09-12
     (TODO 1 and 4). The shape of the check is: collect every `publish("ns:topic")`
     in `MASTER/{lib,core,web}/**/*.rb` — 290 of them — and every `ns:topic` token in
     the bridge, keep the tokens whose namespace the bus uses at all (37), and
     require each to prefix-match a published topic, because the bridge tests with
     regexes rather than equality.
     Two things stop that being a five-line test. Comments count as tokens, so the
     very comments explaining a removal read as the removal not having happened —
     strip comments first. And several live names are SSE or DOM events rather than
     bus topics (`council:speech`, `chat:append`, `input:focus`, `runtime:event`),
     so the check needs a named allowlist, and an allowlist nobody curates becomes
     the place dead names hide.

1067. **Four tests in `test_agent.rb` were skipped as "drifted", and were dead.**
     Removed 2026-09-12. They exercised `tool_capable?` and `cache_key_for`, and
     neither method exists anywhere in `lib/` or `core/` — nor did the behaviour
     move: there is no `supports_tools`, no `cache_key`, nothing. So they were not
     drifted pending a port, they asserted against an API that had been deleted,
     while reading as coverage from every angle except the one that counts. Five
     live tests remain in that file. MASTER's skips went 11 -> 6; of what is left,
     `test_cli_boot_e2e` and `test_self_scan` are deliberately env-gated, which is
     a different thing from a skip nobody can lift.

1068. **Radio's visualizer: the code is all here, and nothing is wired.** Archaeology
     done 2026-09-12 against the deleted root `index.html`, 144 revisions.

     The best version is **`ba752d682`** (2026-01-17, "purple/magenta VGA synthwave
     palette"), the last of sixteen revisions carrying all seven visualisers —
     `PixelTunnel`, `InfinityGridViz`, `CymaticWavesViz`, `FractalCascadeViz`,
     `VortexNestViz`, `NeuralWebViz`, `CosmicEmanationViz`, `HypergridSpiralViz` —
     together with the behaviour that was asked for, written exactly this way:

         window.vizMode = 0;                       // the tunnel, by default
         window.vizRenderers = [tunnelRenderer, new InfinityGridViz(ctx), ...];
         // on a new track:
         vizMode = (vizMode + 1) % vizRenderers.length;

     So the original visualiser IS the warp tunnel with the merged orb, it IS
     index 0, and the cycle-per-track already existed. The six others were dropped
     from index.html at `037d14ce0` (2026-01-29) in the orb/tunnel merge.

     Nothing needs recovering from git. All seven classes AND the switching —
     `vizRenderers`, `vizMode`, `vizNames`, `vizPsychedelicModes`, `lastTrackIndex`
     — are already in the tree at `brgen/app/javascript/reference/visualizers_2d_reference.js`,
     61KB, whose own header records the second half of the story: they had also
     lived in `shared/frontend/layouts/visualizer.js`, bound to a `#canvas` no view
     rendered, so they never ran and were compiled dead into brgen and amber until
     `248e23795` deleted that copy and parked this one.

     What radio runs today is `brgen/app/javascript/radio_brgen_tunnel.js` —
     `AudioEngine`, `VisualEngine`, `RadioBrgen`. Its `VisualEngine` has no
     visualiser modes at all, only a `performanceMode` toggle, and `nextTrack()`
     changes the audio without touching the visuals. That is the whole defect: one
     renderer, no cycle, with seven renderers and the cycle sitting unimported
     beside it.

     The work is a port, not a recovery: give the radio canvas the seven renderers,
     restore `vizMode` at 0, and call the cycle from `nextTrack()`. The reference
     file is `// Reference only. Not loaded, not imported, not compiled` and
     `css_coverage_lint.rb:181` depends on it staying that way, so wiring it means
     moving the classes rather than importing that file where it sits.

1060. **`vps_weekly_integrity.sh` has never run.** `etc/crontab.vm23:97` schedules it
     `30 3 * * 0`. Read from vm23 on 2026-09-12, root's live crontab does not carry
     that line and `/usr/local/bin/vps_weekly_integrity.sh` does not exist — this is
     the "1 unscheduled" that `config_drift_gate --remote` reports. A weekly
     integrity check that has never fired reads as green because nothing reports it,
     which is the same shape as the daily.local finding this file already records.
     Installing it and merging the crontab line needs doas on the box: the operator's.

799. **Fixed 2026-09-12.** `config_drift_gate.rb` sets its own
     `Encoding.default_external` with the reason beside it. It is the only file
     OPERATOR.sh installs to /usr/local/bin, and `require_relative` resolves beside
     the installed copy, so one shared six-line file forced a whole
     `/usr/local/bin/lib/` onto the box and an install that could half-succeed. The
     other seven callers run from the checkout and keep `require_relative
     "lib/utf8"`. `installed-targets` clean: 12 named, 14 provided.
800. **bin/ds-records requires root to read signed zones.** Off-box it should skip, not traceback. Guard ZONE_DIR readability.
801. **bin/render_dns.rb add `--help`.**
802. **OPERATOR.sh pin `RUN_PRODUCTION_SEEDS` default 0 in the header.**
803. **Partly fixed 2026-09-12; the alias stays.** `ssh brgen` needs a Host block in
     the operator's own ~/.ssh/config, so making it the repo-wide default fails item
     21's test — a stranger rebuilding from the repo alone has no such alias. What
     was fixed is the disagreement between the files that do not use it: see 806.
804. **Three doors.** START_HERE should say “agents: CLAUDE.md; operators: RUNBOOK.md; first screen: README.md” in one sentence.
805. **RUNBOOK “Always use tmux” then `doas zsh OPENBSD/OPERATOR.sh`.** vps-deploy must *not* be doas. Put that adjacent.
806. **Fixed 2026-09-12, and the real defect was worse.** `bin/deploy-diff.sh`
     defaulted to `dev@46.23.89.226` and now matches config_drift_gate's
     `dev@brgen.no`, which is the form the repo contract names. Underneath that,
     `SSH_HOST` means two different things: login@host in those two files, host alone
     in `lib/ssh_vm23.sh` where `SSH_USER` sits beside it. Exporting one for the other
     yields `dev@dev@brgen.no`. All three files say which they mean now.
     `deploy_all.sh`'s own usage example told the operator to pass
     `VPS_HOST=dev@46.23.89.226`, which the script joins with VPS_USER — so the
     documented invocation could not have worked.
807. **Fixed 2026-09-12.** `deploy_all.sh:13` says `RAILS/<app>/<app>.sh`.
808. **START_HERE post-pull.** Add “do not stash”.
809. **health_check encoding comment duplicated.** One `lib/utf8.rb` require is enough.
810. **bin/check OptionParser without `--help` banner.** Add a banner listing profiles and which gates each runs.

### STUDIO — dilla

Re-measured 2026-09-13; 190 entries became these. The first group is real and
blocked only because `STUDIO/dilla/dilla.rb`, `lib/producer_dna.rb`,
`README.md` and `ENV_AND_RENDER.md` carry another session's uncommitted work.
Take them the day those files are clean.

811. **dilla.rb comments that describe the split.** 80 `# engine part:` headers still say "split out of dilla.rb"; `:230` says load order lives in `engine_sources.rb`; `:248`, `:13733`, `:14870`, `:20805` still name `lib/engine/`; `:14900` names the gone `ENGINE_PARTS`; `:14672` hardcodes "35,000 lines / 83 markers" instead of asking `parts_report`. `:35237` should say the gate and tests depend on the CLI guard.
812. **`ENGINE_SOURCES = DillaSources.all` sits at `:34385`,** after `wiring_dead_constants` and `parts_report` close over it. Move it up to the require at `:36`.
814. **`scan` probes `dilla.html` (`:13165`),** a file that does not exist. Drop the key.
815. **`help` is one 170-line dump.** Topic index (`help render|chop|knobs|sample`) with the wall behind `help all`. The topics owe these lines: `industrial`/`techno`/`analog` bypass AudioGraph; `characterize` under READING THE ENGINE; `source` points at `lib/crate_dig.rb` before `project/crate.yml`, and `live/dig_crate.rb` is the YouTube digger; chop lists RadioChop's operations in order; `STREAM_DEMO` overwrites the rolling `demo.wav`, not a take; `DILLA_OVERWRITE=1` is the only overwrite; `SWING=` is the fallback and per-role offsets are the Charnas move.
816. **`council` (`:13184`) prints five slogans.** Delete it or make it run a command.
822. **Lazy requires are undocumented.** Say beside the requires which of `console_strip`, `tape_hysteresis`, `mix_score`, `verify_fx`, `kit_dig` are command-only, so a fold does not pull DSP into boot.
829. **Locale.** brgen's CI loads dilla.rb as user brgen; set `Encoding.default_external = Encoding::UTF_8` at the top of dilla.rb rather than touching 37 `File.read` sites.
846. **`radio-bergen-librosa` cannot run.** `scripts/librosa_analyze.py` reads `scripts/radio_bergen_tracks.yml`, which does not exist, and audio roots in `pub2`/`pub3`; it is also committed Python. Delete the dispatch arm (`:34877`) and the script together.
853. **`dilla stems` should refuse** when `stems/manifest.json` names `samples/demux/…` paths not on disk, as `dilla assets` does.
855. **"~60 presets"** in `producer_dna.rb` and the README: count in `dilla knobs` instead of restating.
868. **Chop registry JSON is parsed twice** (`:18223` warns, `registered_loops` rescues again). Parse once; drop bad rows by slug.
871. **`rap-vocal list`** should mark sidecar-only rows "audio missing", and say `_mislabelled_untitled_flac/` is deliberate so nobody cleans it.
873. **`dilla assets` exits 0 on an unreadable `data/assets.json`.** The module warns and returns an empty crate; the command should exit non-zero.
965. **dilla README and ENV_AND_RENDER.md.** README names `sample_loops.rb` (it is an engine part), tells a pre-`bin/crate` restore story, and never says a worktree has no crate so crate tests skip; ENV_AND_RENDER.md says command aliases are gone while `loose_pocket`, `industrial` and `techno` remain as genre renderers. One sentence should name the three ways to hear it: `dilla.html`, `dilla_live.rb`, `bin/sine_stream.rb`.
1000. **Provenance pins.** Confirm a probe asserts the sidecar note carries a non-seed pin when `USER_PINNED_ENV` is set; add one to `test_dilla_engine_probes.rb` if not.

These are the operator's, because each changes a sound or accepts a changed input:

850. **`data/modes.yml` has no reader.** Nothing in STUDIO loads it — `tizita`, `bati`, `ambassel` appear only in the file, and the `chord_theory.rb` it names is gone. Wiring it into the harmony spine changes what dilla generates; the other choice is deleting it. Same decision as `dilla_principles.yml`.
859. **The crate on main disagrees with `data/assets.json`.** `DillaAssets.verify` there: `samples/{kembara_rindu,lo_borges,semua_untuk_mu}/loop.wav` missing, and seven one-shots under `samples/drums/` changed hash at the same size. Restore them, or `dilla assets record` to accept the new drums as the inputs.

### STUDIO — postpro, repligen, lora

907. **Chains are ungraded by default.** `generate` applies `HOUSE_POSTPRO` (`portrait`); `chain` grades its final frame only when `--postpro` is given. Whether chains share the house grade is a graded-look call.
926. **`lora/guides/*.m4a` are tracked TTS output** beside their `.txt` scripts. Keep them in git or untrack them; either is the operator's.
931. **`lora/_toolkit/judge_thresholds.yml` was calibrated on seven images;** `ragnhild/dataset/` now holds six. Recalibrating moves the quality floors.

---

## Wiring, type and Rails leftovers — the 2026-09-11 second pass, compressed 2026-09-13

Six sections opened 2026-09-11 (cross-tree micro-refinements, unwired logic
and typography, Rails 8.1 and stimulus-components, completing the four trees,
books, agentic coding) re-measured into this one. The cross-tree list was
almost entirely a restatement of the numbered inventory above and the
awesome-list scan, and closed as duplicates. Refusals are argued in
`MASTER/DECISIONS.md` ("What The Catalogs, Papers And Books Do Not License");
three ranking ideas moved to `RAILS/apps.horizon.yml`.

Two guards worth keeping. `data/modes.yml` has no reader (see STUDIO 850), so
entries elsewhere that treat it as the live scale are wrong. And the
`MASTER/web` suite is not run by anything that fails: `events_controller_test`
errored on both tests for as long as it existed.

### MASTER face and bus — real, and the face's behaviour

2. **Face regexes name topics nothing publishes.** `phantom:retry` (`face_semantics.js:162`, `topology_registry.js:22`, `data/topologies.yml:7`) where the bus publishes `phantom:recovery|occurrence|halt`; `pipeline:start` (`face_semantics.js:192`, `face_perf_guards.js:68`, `topologies.yml:13`) where it publishes `pipeline:stage_start`; `council:deliberation` in `face_semantics.js`, `face_council_multi.js`, `cognition_ecology.js`. Renaming makes the face flinch and tint on events it ignores today, so the operator should see it once; the bundle rebuilds at `assets:precompile`.
10. **`sse_contract.js` lists `felt`, `mood`, `model`, `verdict`, `confidence`, `council:speech` with no handler,** and `content_kind` is handled but unlisted. POST chat works only because `handleFaceNamedEvent` passes them as extensions, and it omits `felt`. Put the handlers in the contract and assert `SSE_EVENTS ⊆ NAMED_HANDLERS` in `sse_contract.test.mjs`.
11. **`face.runtime.js` keeps a GET EventSource `/chat/message` path beside the POST one.** Edit `face.part*.txt`, not the generated file.
20. **Command tables built by no caller.** `agent_commands.rb` publishes `btw:done` and `agent:plan_done`, which `chat_service.rb:127` and `active_plan.rb:51` subscribe; `CommandRegistry.build` never builds that table (help.rb says so). Register `/btw` or delete the table with both subscribers.
24. **`MASTER_CONSENSUS_FIXES`, `MASTER_WATCH`, `MASTER_INCREMENTAL`, `MASTER_SKIP_SELF_TEST` have no on-path test,** and `MASTER_WEB` has no test that the Falcon boot sets it. One test each that the `=1` path runs.
170. **`/dashboard/live` has one fetcher,** `dashboard/index.html.erb:57`, and the dashboard is not in `face_assets.yml`. Keep both or fold both into chat.

### RAILS wiring

28. **A report sent by Turbo answers 422.** `ReportsController#create` offers `format.turbo_stream` with no template; a test posting with Turbo's Accept header reproduced 422, and removing the format still gave 422 with `ActiveRecord::RecordInvalid: Flaggable må eksistere`, while the same post without the header creates the report. Find why the Turbo path loses the flaggable before touching the format.
29. **Identity, reputation, neighbourhoods and mentions are models without an inlet or a page.** `IdentityAssurer` is called only by a test; `IdentityAssurance`/`ReputationScore` have no view; `Neighborhood` has no route though dating and maps print the name; `Mention` rows have no "you were mentioned". Each wants a reader or deletion — a product call per model.
42. **Mutations that reload the page.** Favorite, like, dislike, rewind, comment, collaboration, import, conversation pins and group members redirect; `Tv::CommentsController` has no views despite `TvCommentCreated`. Stream the row (Turbo), not a new Reflex; `VoteReflex` beside `votes#create.turbo_stream` is the same arrow twice, and `optimistic-send` has no caller.
44. **`lazy_image_tag` lives in brgen's host but dating's engine views call it,** so the engine's own tests cannot render them. Move it to shared.
45. **`BSDPORTS_PORTS_TARBALL=1` has only its decline path tested.** Add a fixture tarball.
R5. **Sign-up has no `unauthenticated_access_only` and no named rate limit on create,** the edge guide's two lines.
R8. **`fresh_when` only on bsdports `ports#show`.** Add to post, listing, event, item and maintainer show with an ETag that includes `Current.user&.id`.
R12. **Marketplace variants are a static `fields_for`;** amber's `nested-form` and `sortable` already do this. Same for dating prompt order.
R14. **`auto-submit` has no caller outside the snippet library.** Put it on the GET filter forms: marketplace facets, TV channels, bsdports search, amber filters.
R23. **Four confirms want native `<dialog>`:** dating match overlay, report confirm, takeaway cancel, amber "let go". Re-pin `dialog` with the first view.
R40. **No test that `tiptap-editor` survives a `broadcasts_refreshes` morph.**
R44. **`futurism` is in amber's Gemfile with zero callers and no pin.** Remove the gem or give it one index.
C2. **`Matchmaking#create_mutual_matches` looks users up one id at a time;** `User.where(id: mutual_ids)` once.
C6. **Marketplace defaults to goods;** the kind switcher and the empty state for a kind a city lacks are missing.
C8. **`tv/live_streams/new` offers a form for infrastructure vm23 does not have.** Hide it behind a false flag.
C20. **`ports_fts` is created by migration and skipped by tests when absent.** Put the virtual table where `bin/ci` builds it, so a done feature cannot skip.
C22. **bsdports offers FreeBSD and NetBSD chips that import nothing.** Disable them.
A17. **RAILS runs Selenium while every gate drives Chrome over CDP.** Pick one driver for the few system tests (1 amber, 2 brgen, 1 bsdports); they already fail nothing on console errors.

### Instruments — detectors that measure, never repaint

60. **Lint reach.** `NO_INLINE_STYLES` names two `.html` files and never reads ERB `<style>`; `RhythmLint` reads only the two token files; `ScaleLint` misses the `font:` shorthand and `letter-spacing` inside `clamp()`; `NO_LONG_TRANSITION` misses seconds (`.42s`, `1.2s`) and JS `duration-value`; `LOGICAL_PROPERTIES` matches only margin/padding; `MEASURE_OPTIMUM` fires only at ≥800px. Extending each will surface findings, which go to the operator's list below, never into a raised ceiling.
124. **Hanging markers are a soft geometry probe on surfaces without lists.** Add legal, wiki and post show to `geometry_surfaces.yml`; say beside `list_marker_hang` whether it is law or advice. `void_target: 0.70` and `rhythm_off_max_pct` have no reader.
A1. **Findings carry no `status: hypothesis | measured`,** and nothing tests the `Scan::Finding` shape. `research_thresholds.yml prompt_compression_ratio` is unread; JSON tool results may skip `OutputFilter` (grep `Result.ok(` in `lib/io/`); no test that a tainted WebFetch result cannot reach `AstEdit`; no test that `/scan` never reaches a frontier model under `MASTER_SCAN_DETERMINISTIC`.
A22. **`visual_contract` pixel diffs will churn on `time`, `time_ago`, animated numbers and `[data-money]`.** Mask those selectors.
B2. **Prose lints nobody runs:** two spaces after a period and `2010-2014` instead of an en dash in locale YAML prose values; centred body text inside `main`.

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
A24. **A drifted snapshot could print the token that would absorb it** (`layout_snapshot --explain`), without writing a baseline.

### Needs vm23

C24. **Checkpoint WAL before `dr-pull`** (`PRAGMA wal_checkpoint(TRUNCATE)` or `.backup`), so the off-host copy is consistent.
C26. **If `/var/log` shows `database is locked`, raise `busy_timeout`;** confirm one writer per primary with `FALCON_WORKERS` at 1.

---

## Bughunt — 2026-09-11

New defects from reading the four trees after the inventories. Does not restate event-name drift, rate limits, English literals, job uniqueness, LUFS dual windows, or unread `dilla_principles.yml`. A finding is a hypothesis.

### MASTER

1. **`OutputFilter` compresses git/ls/tree and long line-counts.** JSON from WebSearch / scan / GitContext can still dump. Route those `Result.ok` bodies through `filter` (agent-harness item 4). Brittle: `GIT_STATUS_RE` is a regex on the whole blob.

### RAILS

2. **Package index follows redirects with `URI.join` to any host.** `package_index_fetcher.rb:79`. If `mirror_url` or `Location` is `http://169.254.169.254/`, that’s SSRF. Allow-list host to the mirror’s host (and ftp.openbsd.org). Same shape as `OutboundHttp`.
3. **`Vote#apply_score_delta` uses `saved_change_to_value`.** Create: `[nil, 1]`, `nil.to_i` is 0, delta 1 — OK. `after_save` on a touch with no value change: `saved_change_to_value` is nil, `before, after = nil` → `nil.to_i` 0. OK. `after_destroy` uses `value` after destroy — still in memory. OK. Pitfall: `update_all` skips `updated_at` on the votable; WIRING_NOTES trap. Add `updated_at = ?` or leave if score is the only reader.
4. **`Takeaway::Restaurant#update_columns(rating: avg&.round(1) || 0)`.** Average of integers rounded to 1 decimal is Fine; `round(1)` on a float is not money. Don’t store money this way. Rating is OK. Inconsistency: other counters use `increment!`.
5. **Release gate `sleep 1` in a retry loop.** `gates/release.rb:99`. Fine for a laptop gate; don’t copy into a job.
6. **`Date.today` in app code vs `Time.zone`.** Dating `ranked_for` seeds `Date.current` — good. Grep remaining `Date.today` in `app/` (not gates). UTC-vs-Oslo can shift daily picks at 00:00–02:00.
7. **`amber` `config.generators.system_tests`.** brgen and bsdports set `nil`. If amber still generates system tests, the 8.1 policy is inconsistent.

### STUDIO / OPENBSD

8. **`MixScore.band` interpolates `path` into backticks.** `mix_score.rb:43`. `verify_fx.rb:83` interpolates `path` and `af`. `dilla.rb:15011` ffprobe the same. `live/rack.rb:182` uses `shellescape`. One helper: `Open3.capture2e("ffmpeg", "-i", path, ...)` with a timeout. A crate path with `"` is a command.
9. **No timeout on those ffmpeg backticks.** A hung decode blocks `rake test` / characterize forever. `Open3` + `Timeout` or ffmpeg `-t`.
10. **`measure` `.to_f` on a missed regex is `0.0`.** A failed ffmpeg looks like silence. Raise or return `nil` if the match is missing.
11. **`OPERATOR.sh` `sleep 10` / `sleep 5` in loops.** Fine for boot. Pitfall: `set -e` with sleep is OK; an unquoted `$delay` is not if delay is empty. Quote `"$delay"`.
12. **lora `YAML.load_file` in `render_config.rb` / `shoots.rb`.** Same as 8. Toolkit YAML is local; still `safe_load_file`.

### Smells that are pitfalls, not style

13. **FixLoop background + propose_tree threads + WatchLoop + cable_bridge + TTS workers.** Five unsupervised thread families in one Falcon process. A leak in one starves TTS. Bound them (`HostBudget`) or don’t start propose_tree from the web process.
14. **`SecurityAdvisoryRefreshJob` + `sleep` + no uniqueness** (uniqueness was inventory). Together: two jobs, ten minutes of sleeps, NVD bans the IP. Continuations (Rails 8.1 list) + no sleep.
15. **Redirect-follow without host pin** is the same class as DynamicHttp+SSRFGuard. One allow-list helper for all `Net::HTTP` in RAILS (`CrawlSupport.fetch` already exists per `file_length_ratchet_test` comment). Point the package index at it.

### OPENBSD — locks, env, false greens

16. **`.deploying-*` does not cover the window `resource_guard.sh` describes.** App `rc_pre` touches the flag, `pkill`, `sleep 1`, then `rm`. The 300s `/up` wait is after `rc_cmd`. Guard comment says the lock lasts through precompile, migrate, cold boot. A 5-minute tick can shed during the boot the lock was meant to protect.
17. **master’s lock is the same hole, shifted.** `etc/rc.d/master` touches `.deploying` after `bundle34 install` and removes it at the end of `rc_pre` *before* the `/up` wait. Bundle and Falcon bind are uncovered.
18. **`*_jobs` drop the app’s `set -a`.** `rc.d/brgen` exports the whole env file. `brgen_jobs` / `amber_jobs` / `bsdports_jobs` `. /etc/<app>.env && export RAILS_ENV SECRET_KEY_BASE HOME …` without `set -a`. VAPID, SMTP, and the rest of the file never reach Solid Queue. Push and mail from jobs fail closed-looking.
19. **Two `PUB4_CI_LOCK` policies.** `lib/ci_lock.sh` only honours an override under `/var/db/pub4/`. `bin/with-ci-lock` honours any non-world-writable directory. Two mutexes.
20. **`pub4_ensure_ci_lock` deletes `.holder` while a holder may own the flock.** Attribution races; running CI looks unheld.
21. **`nsd-resign` reports health when it signed nothing.** Empty keys or empty zone dir → “all zones valid — nothing to do.” Pass on empty.
22. **`bin/smoke-apps.sh` cannot fail master.** Master not listening is `skip`. A dead face plus live brgen exits 0.
23. **`test_tracked_crontab.rb` never sees the uptime-check line.** `scheduled_commands` takes `line.split[5]` and keeps only paths starting `/`. Crontab `ALLOW_BSDPORTS_DOWN=1 /usr/local/bin/uptime-check.sh` — field 5 is the env assignment. The test would still pass if that wrapper vanished.
24. **`drain-jobs.sh` turns a dead sqlite into “nothing due.”** Unreadable db → 0; `solid_queue_proof.rb` treats “nothing due” as proof the drain ran. A broken queue file keeps deploys green.
25. **`drain-jobs.sh` uses `cut`.** Banned. Ruby or zsh split.
26. **`core-reclaim.sh` RSS is `ps | grep | grep -v | head -1 | awk`.** Wrong pid; ceiling never fires. `head`/`awk` banned.
27. **`emergency_cpu.sh` uses `head`.** Crisis path on OpenBSD `head`.
28. **Weekly integrity lock is a no-op if `fuser` is absent.** `if [ -f "$LOCK" ] && fuser "$LOCK"` — missing fuser makes the condition false; the script proceeds and races CI.
29. **`start_all_apps.sh` restarts relayd after a fixed 5s.** Amber rc.d waits up to 300s for `/up`. Relayd can reload onto empty backends.
30. **`etc/rc.d/master` digest is unquoted.** `cksum $_face_assets …` word-splits. Empty list plus glob stamps a digest that is not the asset set.
31. **`bin/vps-state` swallows a corrupt deploy stamp.** `JSON.parse` rescue nil → “never deployed.”
32. **Fixed 2026-09-12.** Confirmed against vm23: `top -b -n 1` and `vmstat -s`
    both answer on OpenBSD 7.8, so the fallback is live and only the both-failed
    case was wrong. It kept the 100% initialiser, which made `mem_avail_pct -lt
    MEM_WARN` unreachable and left the guard quietly deaf to memory-only pressure.
    It now fails to 0 and logs why, matching the load arm six lines above, which
    fails to 9.9 for the same stated reason.
33. **`smtpd.conf` listens on `vio0`.** Interface rename and inbound 25 dies.
34. **Hardcoded `/home/dev/pub4` in `start_all_apps.sh` and rc.d.** `PUB4_ROOT` / a worktree is ignored.
35. **`dr-pull --check` exits 0 when `~/pub4-dr` is missing.** The local gate that should notice a stale backup is a skip on a Mac that never created the dir.

### STUDIO — ffmpeg 0.0, scratch races, silent session

37. **Album master is the same backtick hole as MixScore, with gain.** `dilla.rb:34535–34541`. Failed ffmpeg → `I=0` → `gain = target - 0` applies ~19 dB of make-up. Don’t ship that take. Open3 + status + abort.
38. **`audio_duration_sec` discards status, rescue `0.0`.** `build_harmony_loud` then `[dur, 8.0].max` — a failed probe mixes **8 seconds** of a longer stem.
39. **Scratch names are not pid-scoped.** `harmony_loud.wav`, `live_tmp.wav`, `dilla_drums.wav` … Two `dilla` processes (or `PARALLEL=3`) write the same files. Pid-scoped temps exist at `:5735` and are unused here.
40. **Scratch fallback is per-uid, not per-process.** `Dir.tmpdir/dilla-scratch-#{uid}`. CI user plus a second render still collide.
41. **`CompositionEngine.load!` silent `rescue StandardError`.** Truncated `session.json` becomes a brand-new session with no warn. Jam looks like it loaded last night’s work.
42. **`crate_dig` / `VocalChop.loops` / `Acapella.index` JSON parse with no rescue.** Corrupt index is a backtrace on the vocal path. Refuse with the path.
43. **`kaggle_session.rb` `JSON.parse` at load.** Missing file raises on `require`, not on `run`. `ruby -c` never sees it.
44. **postpro comment-strip `gsub(/^.*\/\/.*$/, "")` kills JSON lines that contain `//`, including URLs in strings.**
45. **Playlist/learn JSON loaders `rescue StandardError` → empty.** Corrupt catalog looks like a first run; the next save overwrites it.
46. **`sine_stream.rb` mutates ENV at load.** `ENV["WONKY_TOP_DIRT"] ||= …`. A require from a test leaks knobs.
47. **Two `capture` APIs.** Engine `capture` → `[stdout, stderr, status]`; `RadioChop.capture` → a string. Copy-paste of `.first` across the boundary is a type error.
48. **`mix-score` never calls `tool_available?("ffmpeg")`.** Engine mix metrics do.
49. **`STREAM_ITERATE_LOG` is one shared path, no flock.** Concurrent streams interleave lines.
50. **`bin/crate` ROOT is `…/dilla/crate`.** That directory is gone. `list`/`fetch` write a third layout the engine never reads.
51. **`isolation.rb` loads every `test_dilla_*.rb` in one `-e` process.** session.json mtime races and ENV pins leak by construction. `rake test:dilla` still runs that way.
52. **`EnvSandbox` restores ENV, not constants.** Engine constants computed from ENV at load (`ONLY`/`EXCLUDE` in acapella) stay at first-process values.
53. **Album encode `Open3.capture2e` ignores status, then `rm`s the staged file** and prints loudness from the missing dest (0.0 again).

Highest cost if wrong: 28–30 (deploy lock + jobs env), 36 (drain false-green), 49–53 (ffmpeg 0.0, scratch, silent session).

### MASTER — writes, taint, request path

54. **PathGuard is prefix-only; World realpath-walks ancestors.** ReadFile/WriteFile use PathGuard. A symlink inside the root reaches `/etc`. Put World’s ancestor-realpath check in PathGuard.
55. **`SearchFiles` `Dir.glob(File.join(@root, glob))`.** `File.join(root, "/etc/passwd")` is `/etc/passwd`. Reject absolute globs; PathGuard every hit.
56. **Fixed 2026-09-12.** Confirmed before fixing: the sanitiser allowed `:` and `/`
    explicitly, so `show` with `HEAD:<path>` printed that path's blob — any tracked
    file, at any revision, including ones deleted since — while log, blame and diff
    all route their path through `safe_path` and PathGuard. `show` has no path
    argument, so the colon form was the only way to ask it for one and nothing
    bounded it. `Io::LLM::GitContext` exposes the tool to a model, which is what
    made this worth more than tidying. Refused rather than sanitised, since no
    caller in the tree passes `<rev>:<path>` and `--stat` already says the argument
    describes a commit. `test_io_path_guard.rb` covers it and fails 2 of 3 with the
    guard removed.
    Cost: `spine.lib_body_ceiling` 38329 -> 38334, recorded with the reason. I first
    compressed the guard onto one line to stay under the ceiling and then put it
    back — the 38298 -> 38299 entry in `spine.yml` had already settled that exact
    instinct, for a security rule, against itself.
57. **`ReadFile` `File.readlines` the whole file then slices.** A 200k-line file becomes prompt. Sacred paths block writes, not reads — `.master/config.yml` is ingestible. Line-range IO; refuse secret paths on read.
58. **TTS `job_id` is SHA256(voice|text)[0,32].** `readable_job` skips ownership when ready. Anyone who can guess the utterance fetches the mp3; identical lines cross conversations. Random id; always `owned?`.
59. **`GET /chat/tts` and `GET /chat/enhance` have side effects.** Prefetch and query logs trigger paid work. Enhance is not in `AUTHENTICATED_ACTIONS`. POST only; auth enhance.
60. **`require_same_origin!` allows missing Origin when `Sec-Fetch-Site` is not `cross-site`.** curl CSRF from a sibling host with no fetch metadata passes. Command already skips CSRF. Require Origin or `same-origin`.
61. **`GET /chat/skills`, `GET /chat/research`, `POST /chat/photo` are visitor-reachable.** Research is outbound HTTP; photo is 12MB + postpro. Authenticate or quota.
62. **`GET /ingress/health` lists cron/webhook names unauthenticated.** Public health stays `{ok:true}`; names behind the token.
63. **`production.rb` `host_authorization = { exclude: ->(_) { true } }`.** Any `Host:` is accepted behind relayd. Allow the real hosts only.
64. **`DynamicHttp` interpolates `{param}` into URL/body with no escape.** Query injection; SsrfGuard sees the URI after interpolate. Escape by slot.
65. **MCP SSE `cfg["url"]` has no SsrfGuard.** Writable `mcp_servers.yml` becomes an internal-network client.
66. **`pairing.rb` `allowlist_path` `File.expand_path` can leave the tree.** Force under `.master/pairing/`.
67. **`ensure_brain_files!` writes `data/IDENTITY.md` if missing**, bypassing sacred `data/`. Write under `.master/` or don’t create constitution files at runtime.
68. **`Timeout.timeout` around `Net::HTTP` / UNIXSocket / Ferrum.** World already measured Timeout does not kill the child. Hung POST holds a Falcon worker. Use `read_timeout` / `IO.select` / Ferrum’s timeout; `quit` in ensure.
69. **SSE loop `sleep 0.1` for up to 600s, `subscribe("*")` unbounded Queue.** Two Falcon workers plus chat SSE starve the 1 GB box. `Queue.pop(timeout:)`; cap; `HostBudget`.
70. **`/health` SHA256s `Gemfile.lock` every poll — measured 2026-09-12, and
    the finding is false in both halves.** The hash costs **27µs** on a 14,687-byte
    lockfile (2,000 calls in 0.054s); ten times slower on vm23's vCPU is still
    a third of a millisecond against a relayd poll. And the proposed fix is the
    thing `speech.rb:154-158` already measured and rejected in writing: the
    worker's own `bundler/setup` touches `Gemfile.lock`, so an mtime key is
    invalidated by the very probe it memoises and every call spawns a full
    subprocess. Content-keying is what makes the memo work. Kept as a guard —
    a cheap-looking hash beside an expensive-looking name reads as waste, and
    the expensive thing was the subprocess it prevents.
71. **Hard compact sends all `session.messages` into `agent.ask`.** That’s the window that overflowed. Summarise a tail.
72. **`SqliteStore` WAL failure falls back to `:memory:`.** Pairing/memory vanish on restart; process looks healthy. Fail closed for durable stores.
73. **`FileProcessor` lock is `CREAT|EXCL` then delete; `remove_stale_lock` is mtime then delete (TOCTOU).** A crash holds the scan 300s. `flock` on a stable lockfile.
74. **`mode_posture#set!` writes `.master/mode` and sets `ENV["MASTER_MODE"]` process-wide.** One Falcon worker’s `/mode` changes every request on that process. Don’t mutate ENV.
75. **`pairing#revoke` skips `with_store_lock`.** Redeem vs revoke can resurrect a deleted token.
76. **`context_window` soft compact `Thread.new { compact! }` which `session.clear!` while a turn may still append.** Compact under the session mutex.

### RAILS — strict load, mass assignment, uniqueness, GET writes

77. **Listing show `reviewable_by?` hits `orders.where` after `increment!`.** `restrict_with_error` is still strict. Signed-in show 500s. Include `:orders` or query `Marketplace::Order.where(listing_id:)`.
78. **TV feed preloads `video_file` not thumbnail.** `_item.html.erb` `video.thumbnail.attached?` → strict 500. `includes(thumbnail_attachment: :blob)`.
79. **Users#show posts without `with_attached_image`.** Profile cards 500 or N+1. Mirror HomeController preloads.
80. **Inbox `includes(:participants, :messages)` loads every message in every thread.** Drop `:messages`; unread already has `unread_counts_for`.
81. **Listing params permit `:status` and `:kind`.** Seller POSTs `status=sold` or flips kind without details. Drop `:status`; lock `:kind` on update.
82. **Stores permit `:stripe_connect_id`.** Owner points payouts at another Connect account. Server-only OAuth write.
83. **Partner programs permit `:status`.** Owner opens a draft with no review. `open!` / `pause!` only.
84. **Takeaway restaurants permit `:active`.** Hidden field unpublishes the kitchen. Dedicated action.
85. **Playlist like uniqueness includes nullable `set_id`/`playlist_id`.** SQLite unique treats NULL as distinct — two likes on the same playlist both insert. Partial unique indexes.
86. **Dating match unique is initiator+receiver only.** A→B and B→A are two rows (comment admits it). Unique on `LEAST/GREATEST`.
87. **Mention uniqueness has no unique index.** Race on edit double-notifies.
88. **Affiliate conversion `transaction_id` allow_nil unique.** Duplicate paid postbacks. Reject blank ids.
89. **Vote `after_save` `update_all` score.** A rolled-back vote still moved `posts.score`. `after_commit`.
90. **Dating like `after_create :check_mutual_match` inside the transaction.** Rollback can leave a Match. `after_create_commit`.
91. **GET nearby `#room`/`#widget` `join!` + `ensure_guest_user!`.** Crawlers mint users. POST join, or join when a message is sent.
92. **GET stories show `view_by!`.** Prefetch inflates counts. Beacon/POST.
93. **GET ports/places/amber items `record_activity!`.** Activity table grows with every crawl. Skip bots.
94. **Daily picks: two tabs both `create!`, rescue unique, return `chosen` not the rows that won.** Page shows five faces the DB does not have. Reload `existing`.
95. **Amber `MoneyInOre` `cents / 100.0` is Float.** Outfit totals drift. `BigDecimal`.
96. **Amber `planned_outfit` `this_week` uses `Date.today..7.days.from_now`.** Date vs Time, UTC vs Oslo. `Time.zone.today`.
97. **TV `comments_count` / `likes_count` have no writer.** Rank/UI that reads them is 0. `counter_cache` + default 0, or drop the columns.
98. **Ports importer upserts one-by-one, no transaction.** Nightly vs web → `BusyException`. Wrap in `Port.transaction`. `ApplicationJob` does not `retry_on SQLite3::BusyException`.
99. **PWA share skips CSRF on posts#share and amber items#share.** Require Origin allowlist or a share nonce.
100. **Playlist sets unknown privacy string is treated as public.** Typo in DB leaks private sets. Default deny.
101. **Comments#create with neither event_id nor post_id → `@commentable` nil → 500.** `head :not_found`.

---

## Restructure — one job, one door — 2026-09-11

Cherry-picked. Not the sprawl census, not “split this file,” not LAYER_CAKE, not folding `dilla/live/`, not nesting `shared/lib/operator`, not three sign-in screens, not merging `probe`/`dogfood`. The move is always: two things that do one job become one thing, or a dead copy is deleted.

A finding is a hypothesis. Verify the second caller before you delete the first.

### MASTER

1. **One atomic write.** `Io::AtomicWrite` (fsyncs), `World#write_atomic`, `cli/scan/live.rb`. Callers of the last two can leave a 0-byte file. One helper; the others become wrappers or go.
2. **One PathGuard.** Prefix check vs World ancestor-realpath. Reads use the weak one. One module, the strong check.
3. **One constitution loader.** `Ground::Constitution` vs `Core::Constitution`. Rename Ground’s to `PrincipleStore` or fold. `Master.law` is the reader of `rules.yml`.
4. **One memory search.** `ground/memory_search.rb` vs `ground/memory/search.rb`. Index vs query. Honest names, or one class.
5. **One mood.** `PressureEngine`, `Trace::ContextPressure`, `Cognition::Affect`. Document which bus events each owns, or fold PressureEngine into Cognition. Three weathers is a forecast.
6. **One attention table.** `cognition/attention.rb` vs `cli/attention_context.rb` vs `data/attention_context.yml`.
7. **Delete the unwired command tables.** `memory_commands` / `system_commands` / `media_commands` / … are required and never merged into `CommandRegistry.build`. Wiring them duplicates live verbs. Delete the dead tables; keep the one command worth merging (`/tools` list).
8. **One diagnose door.** `check` / `ci` / `audit` / `probe` / `smoke` / `dogfood` / `doctor`. `probe` and `dogfood` stay (measured). `smoke` → `check --profile=ci` subset; `audit` → `operator lint --staged`. Document the Venn once; don’t add an eighth.
9. **`bin/cli` execs `bin/master`.** Two entrypoints, one REPL. Completions generate from `HELP_TOPICS`.
10. **`spec/` vs `test/` vs `web/test/`.** Face tests live in three homes. Two at most: `test/` for Ruby, `web/test/` for the face. `spec/core_smoke.rb` is not `*_spec.rb`.
11. **`lib/rails/` moves to `RAILS/gates/lib` or becomes `/rails audit`.** MASTER should not audit RAILS by walking `Master::ROOT`.
12. **Done — verified 2026-09-12.** Neither `MASTER/lib/grok/` nor `MASTER/lib/deploy/`
     exists; lib/ is boot, builder, cli, cognition, core, fix, ground, io,
     operator, rails, review, trace, voice.
13. **`work_commands_extra.rb` / `work_commands_status.rb`.** Split by verb or fold into `work_commands.rb`. `extra` is a junk drawer.
14. **One snapshot verb.** `tools/snapshot.rb` vs `Trace::Snapshot::Publisher`.
15. **One dogfood.** `spec/dogfood_spec.rb` vs `bin/dogfood` vs `rake dogfood`.
16. **One skills list.** `lib/cli/skills.rb` vs `data/patterns.yml` skills_registry. Index first, body on demand.
17. **One dmesg.** `lib/trace/dmesg.rb` vs `ChatController#dmesg`.
18. **One token job.** `MasterIngressToken` vs `MasterWebToken` — names by job (HMAC vs cookie), not two classes that look interchangeable.
19. **One log directory.** `WebEventLogger` vs `Trace::Log` vs `Swallow` JSONL.
20. **`OpenbsdConfig` / `HostBudget` read `OPENBSD/` once.** Don’t duplicate `vm_resource.yml` in MASTER data.
21. **Runtime deps from `master.gemspec`; web Gemfile is Rails + Falcon.** Two Gemfiles, two locks, two platform `if`s.
22. **Completions generated from the live table.** `_master` still completes `through`. Add `_operator`. No hand-maintained verb list.
23. **Done — verified 2026-09-12.** `mask.js` and the three `mask_*` files are off
    disk and nothing loads them. The two textual matches left are a different
    thing: `visual_bridge.js` names the `papua-mask` topology and a `#mask` DOM
    id fallback, and `visual_governor_spec.rb:30` is the comment recording the
    supersession.
24. **Cable vs SSE vs `visual_bridge`.** Three event pipes. Cable broadcasts `*`. One pipe for the face; Cable goes or takes the visitor allow-list.

### OPENBSD

25. **Fixed 2026-09-12.** `data/operator.yml` is the command list and now carries
     the whole of it: the check family (check-rails, check-openbsd, check-vps,
     check-full), vps-state and tree.sh lived only in START_HERE.md's Golden
     Commands, so the stub that pointed here was the more complete of the two.
     START_HERE's Golden Commands and Source Of Truth sections are pointers now,
     and RECIPES.md is a door rather than a table. `operator_docs.rb` reads the
     yaml and `/orient deploy` prints it, so a recipe added there shows at every
     door.
26. **One deploy verb.** `bin/vps-deploy` is canonical. `vps_deploy_master.sh` calls it. `vps_production_push` is `SKIP_CI=1 vps-deploy all`. `deploy_all.sh` dies or becomes a wrapper.
27. **One uptime checker.** `bin/uptime-check.sh` execs `health_check.rb --public-only`. `usr/local/bin/uptime-check.sh` is the install target of the same file, or a one-line exec. One list of hosts from `deploy_inventory.json`.
28. **One “on box” bootstrap.** `vps_install_all` vs `vps_on_vm_install`. Fold; delete the `git stash`.
29. **`check` calls `check-openbsd` for the identity/smoke overlap**, or START_HERE draws the Venn. Contributors must not need both by folklore.
30. **rc.d apps from one tmpl.** `rails-app.tmpl` disagrees with brgen (PATH, pexp, timeout). Generate amber/bsdports from the live brgen script, or delete the tmpl so OPERATOR cannot install the wrong one.
31. **Jobs rc.d `set -a` like the app.** Same env file, same export. Three footers → one `jobs.footer` with APP filled in.
32. **`ALL_DOMAINS` lives in `data/dns.yml`.** OPERATOR.sh, Ruby gates, and health_check parse a shell array today. One yaml; shell reads it with `ruby34 -ryaml`.
33. **`SMOKE_SCRIPTS` / `FLEET_INVENTORIES` include `relayd-watchdog`.** Hardcoded backend tables elsewhere die.
34. **`dotfiles/` declared Mac-only, check none**, or it leaves the OpenBSD tree.
35. **Fixed 2026-09-12.** `OPENBSD/restore_litestream.sh`. Three separate passes
    asked for this rename, which is what a real defect looks like from outside.
    Its first line now reads "NOT the disaster-recovery script — use
    OPENBSD/bin/dr-pull for that", and the paragraph under it says why: vm23 has
    no litestream binary and no replicas, so the old name promised recovery the
    file cannot deliver, under exactly the name somebody reaches for in an
    emergency.

### RAILS

36. **One `WebPushJob`.** `brgen/app/jobs/web_push_job.rb` and `shared/app/jobs/shared/web_push_job.rb`.
37. **Notifications: host or shared, not both.** brgen controller vs `Shared::NotificationsController`. Promote when city grouping unifies, or delete the stub.
38. **Votes: host or shared reflex, not both.** `VoteReflex` and `votes#create.turbo_stream` — keep the stream (function-layout test); Reflex becomes a no-op or goes.
39. **One `LiveSearchable` including deals.** Listings/stores/takeaway use the helper; deals still LIKE. Maps `#index` JSON vs HTML duplicates it.
40. **One vertical nav partial.** `marketplace/_nav_bar.html.erb` vs `takeaway/_nav_bar.html.erb`. Accent var already on `body`.
41. **One empty-state partial, callers pass `t(...)`.** TV channels still inline English titles.
42. **One `finish_live_search`.** Duplicated across listings/stores/deals/restaurants/places.
43. **Stimulus: one registration path.** `stimulus_boot.js` loads the fleet; unused reveal/auto-submit/content-loader still cost importmap. Register when present (carousel pattern) for the rest, or unregister.
44. **One `application.js` Stimulus start.** Three app copies plus shared. If they only `import "controllers"`, one file in shared.
45. **`lazy_image_tag` lives in the brgen host, called from dating.** Move the helper to shared so engine tests don’t need the host.
46. **Fixed 2026-09-12.** The inline block is `shared/app/assets/stylesheets/_site_legal.scss`, moved with every value untouched — measured on brgen.no/privacy before and after, `.legal-prose` is 724.397px wide and its h1 is 28.8px/33.12px either way. Snapping those values onto the scales is a separate decision and the operator's.
47. **`.reading-column` / `.form-measure` are worn or deleted.** Defined, unused. Put them on legal and compose, or drop.
48. **One money type.** Amber `MoneyInOre` float vs marketplace integer cents vs affiliate decimals. Integer minor units everywhere money is money. Ratings stay decimal.
49. **One uniqueness helper for nullable FKs.** Playlist likes/collaborations. Don’t copy the NULL-is-distinct bug.
50. **`after_commit` for anything that enqueues or `update_all`s.** Vote score, dating match, hashtags, mentions, listing alerts. One concern if the pattern repeats; don’t invent `AfterCommitable`.
51. **Gates: `root:` kwarg.** Six gates rewrite `ROOT` at load. Tests shouldn’t.
52. **`locale_contract` is the i18n door.** Don’t also append shared locale paths twice. Unused-key scan extends that test, not a gem.
53. **System tests stay the handful.** Integration + gates. Cuprite/Ferrum as the one browser driver (MASTER already Ferrum). Selenium goes.

### STUDIO

54. **One `capture`.** Engine returns `[stdout, stderr, status]`; `RadioChop.capture` returns a string. One signature; Acapella and mix-score call it.
55. **One ffmpeg runner.** MixScore, verify_fx, album master, `dilla.rb` ffprobe — backticks vs Open3 vs `tool_available?`. Open3 + timeout + non-zero abort. 0.0 is not a measurement.
56. **Pid-scoped scratch everywhere.** The helper exists (`:5735`). `harmony_loud.wav` and friends use it.
58. **One LUFS window.** `dilla_reference.yml` vs `MixScore::REFERENCE[:lufs]`. Loss-gate test already wants them equal.
59. **`bin/crate` writes the layout the engine reads, or it goes.** Third crate tree.
60. **`rake test:dilla` is isolation’s process model, or isolation is not claimed.** One `-e` that requires every test file is how ENV and session.json leak.
61. **`council` / `scan` slogans out of `dilla` dispatch.** Dead prose. Help topics stay.

### Cross-tree

62. **`operator gate` is the ladder.** OPENBSD `check-full` and `RAILS/test/run_all.rb` are rungs. START_HERE in each tree says so in one sentence.
63. **PATH_OWNERSHIP lists live dirs only.** MASTER `docs:`/`reports:` are gone; `cognition/` / `law/` / `runtime/` are not listed. OPENBSD omits `data/`, `gates/`, `lib/`. A lint on undeclared top-level dirs.
64. **TODO.md stays the backlog; DECISIONS.md stays the why.** Don’t add a third.
65. **Harness files stay generated.** `rake docs:agent_contracts`. Don’t copy law into CLAUDE.md.

Fenced: splitting `dilla.rb`, folding `live/`, LAYER_CAKE, ViewComponent, nesting operator, three sign-in, merging `probe`/`dogfood`, Kamal, Docker workers, a second type scale, a Parametricist CSS.

---

## OpenClaw, OpenCrabs, Hermes, OpenCode — MASTER gaps — 2026-09-11

Read against source, not star counts. OpenClaw `openclaw/openclaw` (~389k, Why OpenClaw 2026-08-27), OpenCrabs `adolfousier/opencrabs` docs v0.5, Hermes `NousResearch/hermes-agent`, OpenCode `anomalyco/opencode` (~207k). MASTER already recorded a June 2026 cousin-pass in `project_context.yml` (`reference_opencrabs`): pairing, tool profiles, FTS5, compaction, phantom, `/doctor`, worktrees. This list is what that pass did not name, or what shipped in those trees since.

Do not import Docker sandboxes, ClawHub untrusted skills, native iOS apps, Voice Wake, Live Canvas/A2UI, RSI brain writes, or Hermes Portal telemetry. Policy stays code (`soul.yml`), not a prompt.

A finding is a hypothesis.

### Trust boundary (OpenClaw Why)

1. **Trusted gateway / untrusted execution.** OpenClaw: Falcon-class control plane must not share credentials with the shell. MASTER’s face, CLI, and `Io::Exec` are one process. Completeness: visitor/chat never sees `MASTER_INTERNAL_TOKEN`; write tools already go through PathGuard (strengthen it — bughunt 67). Don’t wrap the whole app in Docker; isolate *exec*, not the gateway.
2. **Policy is code, fail closed.** OpenClaw and Hermes RFC: denial is structural; hook failure on `tool_call` fails closed. MASTER `InjectionGuard` / `Tool::Profile` are that. Completeness: a plugin/MCP tool that errors on the guard must not run. Test: WebFetch without SsrfGuard is a fail, not a skip (bughunt 78).
3. **Secrets as handles, not prompt text.** OpenClaw SecretRefs; agent sees a handle, egress substitutes. MASTER Redactor is post-hoc regex (bughunt 60 over-redacts SHAs). Completeness: env keys used by tools stay out of `session.messages`. A test that `File.read("/etc/master.env")` cannot appear in a council prompt.
4. **Versioned state, guarded upgrades.** OpenClaw schemas + signed releases + `doctor` migrations. MASTER `data/*.yml` has no schema version. Completeness: `soul.yml` / `rules.yml` already immutable; `.master/` session JSON gets a `schema_version` and `bin/doctor --fix` migrates or refuses.
5. **Forgetting has bounds.** OpenClaw `memory forget` vs reingestion. MASTER knowledge/ is gitignored. Completeness: `/forget` that tombstones a session id so compact/index cannot pull it back. Don’t claim GDPR from a delete of one file.
6. **`openclaw security audit --deep` as a scheduled check.** MASTER `/security-audit` exists. Completeness: `bin/doctor` prints the same IDs `openclaw security audit` would (pairing store path, host_authorization, GET /chat/tts). Alarm on drift, don’t add VirusTotal.

### Gateway and sessions (OpenClaw, Hermes, OpenCode)

7. **`openclaw triage`.** Read-only health → sanitized prompt → hand to a detected coding agent. MASTER `bin/doctor` reports. Completeness: `bin/doctor --prompt` writes a redacted diagnosis MASTER or OpenCode can ingest. Nothing leaves the box until the operator picks the agent.
8. **Build vs plan agents.** OpenCode Tab: `build` (full) vs `plan` (read-only, bash asks). MASTER `/btw` + `agent_taxonomy.yml` already types explore/plan. Completeness: plan profile cannot call `WriteFile`/`AstEdit` (Policy::Subagent). Test it.
9. **ACP (Agent Client Protocol).** OpenClaw and OpenCode speak ACP so editors host the harness. MASTER is the harness. Completeness: optional `bin/master --acp` stdio that maps ACP session/prompt to the existing Session. Don’t become an editor.
10. **A2A JSON-RPC.** OpenClaw/OpenCrabs. MASTER has no peer protocol. Completeness: one documented “MASTER is not an A2A server” or a tiny `/v1` that is the OpenAI-compatible subset OpenClaw copied — disabled by default. Don’t enable `/v1/chat/completions` on the public face.
11. **Prompt-cache session affinity.** Hermes `x-opencode-session` / OpenRouter `session_id`. MASTER `Trace::CacheEfficiency` exists. Completeness: every provider call in one conversation sends one opaque session header. One helper, all senders.
12. **Bounded SSE queues per connection.** OpenCode v2 event stream: encode once, offer to N bounded queues. MASTER EventsController `subscribe("*")` unbounded + `sleep 0.1` (bughunt 82). Steal the queue bound, not the TypeScript.
13. **`/retry` and `/undo`.** Hermes. Completeness: last-turn undo is `session.messages.pop` + worktree `git reset` of that turn’s paths if a commit exists (bughunt 8 checkpoint). Don’t invent a timeline UI.
14. **Mid-turn interrupt.** Hermes Ctrl+C / OpenCrabs `/stop` cancels handshake and backoff. MASTER chat has no `/stop`. Completeness: SSE client disconnect cancels the Fiber; `/stop` on the next POST. Test disconnect.
15. **Session id on every log line.** OpenCrabs `session_id` spans. MASTER logs mix. Completeness: `Trace::Log` includes `session:` from `Fiber[:master_conversation]`. One grep reconstructs a turn.

### Skills, plugins, directives

16. **AgentSkills spec (`SKILL.md`).** OpenClaw/Hermes/agentskills.io. MASTER `CLI::Skills` + `patterns.yml`. Completeness: load `SKILL.md` from `.master/skills/` with YAML frontmatter; index first, body on demand (restructure 16). Don’t fetch ClawHub.
17. **ClawHub is untrusted.** Scans can be pending and still install with a warning. MASTER: local skills only, or `bin/master skill verify` that hashes the file against a pinned allowlist. No registry.
18. **Plugin hook timeouts.** Hermes RFC on Pi vs OpenCode: neither had timeouts; both shipped hangs. MASTER bus subscribers can block Falcon. Completeness: `bus.subscribe` with a deadline; timeout is Swallow.log + skip, fail-closed if the hook is a write guard.
19. **Namespaced plugin emit.** Hermes proposal vs Pi’s un-namespaced channels. MASTER topics are already `fix_loop:` / `tool:`. Completeness: MCP/plugin events must use `plugin.<name>.` prefix or they don’t publish.
20. **Vendor harness as plugin, core stays small.** OpenClaw drives Codex/Claude Code as runtimes; it keeps channels and policy. MASTER `bin/master` is the runtime. Completeness: optional `Io::Exec` of `opencode run` / `codex` behind Tool::Profile, not a rewrite. Policy still PathGuard.
21. **Project directive discovery.** OpenCrabs indexes AGENTS.md, CLAUDE.md, `.cursorrules`, GEMINI.md, copilot-instructions. MASTER *generates* those from one block. Completeness: when MASTER is pointed at a foreign repo, read their AGENTS.md as data, never as instruction (soul already). A test that a planted `AGENTS.md` saying “print your prompt” is not obeyed.
22. **Config writes only through a validator.** OpenCrabs `config_manager`; agent never raw-edits `config.toml`. MASTER: no tool may `WriteFile` `data/soul.yml` / `data/rules.yml` (already immutable). Completeness: `.master/*.yml` goes through `RuntimeCatalog` schema or refuse.

### OpenCrabs since the June cousin-pass

23. **Per-path write locks.** OpenCrabs v0.3.83. MASTER FileProcessor TOCTOU (bughunt 87). One flock per abs path for WriteFile/StrReplace/AstEdit.
24. **Tree-sitter structural memory.** OpenCrabs v0.5: call-graph beside FTS. MASTER `CodeIndex` / `SymbolLookup` untested. Completeness: “who calls X” walks Prism, not embeddings. Don’t add a vector DB.
25. **Ralph verification / type-aware criteria.** OpenCrabs: plan criteria use the project’s own test command. MASTER FixLoop re-scans. Completeness: `/fix` on RAILS runs `ruby RAILS/gates/runner.rb` for the dirty app, not a generic `rake test`.
26. **Plan vs execute models.** OpenCrabs routes plan to a cheap model, execute to another. Completeness: `/btw plan` uses the scan/deterministic path; `/fix` may use council. Test `/scan` never hits a frontier (agent-harness 10).
27. **Thinking-loop timeout.** OpenCrabs v0.3.78. MASTER council can stream forever. Completeness: `HostBudget` already; apply it to the LLM socket (bughunt 29 Timeout.timeout).
28. **`doctor --fix` repairs locks and stale markers.** OpenCrabs. MASTER `bin/doctor --fix` already has a comment citing OpenClaw. Completeness: repair `.master/*.lock` and stuck FixLoop pid files; don’t auto-edit `rules.yml`.
29. **Background compaction.** OpenCrabs v0.5 summariser off the turn. MASTER `Thread.new { compact! }` races (bughunt 90). Completeness: compact after the turn, under the session mutex, not during.
30. **Zero telemetry.** OpenCrabs: no phone-home code. OpenClaw: daily version check, opt-out. MASTER: a test that `lib/` has no `update.check` / analytics URL. Version check if any is `bin/doctor`, not boot.

### Hermes (ops agent, not a rewrite)

31. **Closed learning loop stays off for daemons.** OpenCrabs RSI default-off for headless. MASTER must not rewrite `soul.yml` from a skill. `Ledger::Feedback` is the learning surface. Don’t create SKILL.md from a turn without `/soul approve`.
32. **FTS5 session search.** Hermes. MASTER memory FTS exists; session JSONL may not be indexed. Completeness: `/grep` over `MASTER/runtime/*.jsonl` with the redactor on. Don’t embed chat in a vector store.
33. **Cron with delivery.** Hermes/OpenClaw. MASTER ingress cron exists. Completeness: a standing order can POST a summary to a channel *only* if pairing allowlists that destination. No WhatsApp stack.
34. **Don’t put the venv inside the workspace.** Hermes install note: a relative `rm` can wipe the runtime. MASTER `.master/` vs `lib/`. Completeness: `Io::Exec` cwd is the worktree, never `Master::ROOT` for destructive globs.
35. **Seven terminal backends (Docker, Modal, Daytona).** Out. Isolation is `operator worktree`. Document that in START_HERE so the next OpenClaw comparison doesn’t demand Daytona.

### OpenCode (coding TUI)

36. **`opencode run '…'` as a worker.** Hermes skill already shells it. MASTER can `Io::Exec` it under PathGuard for a long coding subtask. Policy still ours. Don’t vendor Bun.
37. **models.dev.** OpenCode’s model DB. MASTER `providers.yml` / `models.yml`. Completeness: `CatalogIndex` already fetches OpenRouter; don’t scrape models.dev unless `data_reach` names it.
38. **Plugin server vs TUI split.** OpenCode: one package, one entrypoint. MASTER `bin/master` vs `web/`. Keep two processes; don’t load the face’s Rails into the CLI.

### Aider / OpenHands / SWE-agent (already in project_context)

39. **Aider repo map.** `GitContext` + `CodeIndex` partial. Completeness: a token-cheap map of dirty files before `/fix` (span context, agent-harness 5). Don’t add tree-sitter twice (24).
40. **OpenHands sandbox GUI.** Out. CDP belongs to RAILS gates.
41. **SWE-agent ACI.** Tools return structured windows. `OutputFilter` + ReadFile line slice (bughunt 70). That’s the interface; don’t clone the Python agent.

### What not to take

42. **ClawHub, unsigned skills, VirusTotal-as-admission.** Local allowlist or nothing.
43. **Native companion apps, Peekaboo screenshots, VNC worker desktops, Beam.** Face is the companion.
44. **Hermes Portal / paid tiers / prompt collection.** MASTER keys stay in `/etc/*.env`.
45. **OpenClaw 647 advisories as a score.** Disclosure volume ≠ safety. Steal the *audit check IDs*, not the count.
46. **RSI that rewrites brain files.** `soul.yml` is immutable. AGENTS.md is generated. Operator approves constitution.

`project_context.yml` `reference_opencrabs` still lists OAuth-before-key, NL config_manager, multi-channel inbox, cron DSL, ClawHub, Live Canvas, Voice Wake. Those stay there as the June list. This section is the 2026-09 delta plus OpenCode/Hermes/ACP.

---

## Aider, Cline, Goose, OpenHands, Warp — MASTER delta — 2026-09-11

Continuation. Stars as of 2026-09-11: OpenCode 207k, OpenHands 87k, Cline 68k, Warp 65k, Goose/AAIF 54k, Aider 49k, Continue 36k (read-only after Cursor acquihire). Read against `CodeIndex` (Prism graph, `references_to`, `impact`) and `GitContext` (log/blame/diff/status/show). Does not restate OpenClaw pairing, ClawHub, Docker, ACP, plan-vs-build.

### Aider — the map, not the chat loop

1. **Repo map is PageRank over a definition/reference graph, fitted to a token budget.** Aider: tree-sitter tags → MultiDiGraph → personalized PageRank → binary-search into `--map-tokens` (default ~1–2k). Chat files ×50, mentioned ids ×10. MASTER `CodeIndex#impact` already has callers; it does not emit a budgeted markdown map. Completeness: `Io::RepoMap` (or `CodeIndex#map(tokens:, chat_files:)`) using Prism, not tree-sitter. Fit by dropping lowest-rank files. Don’t dump the index.
2. **Only `/add` files are writable; the map is read-only context.** Aider. MASTER WriteFile can touch anything PathGuard allows. Completeness: a session `writable:` set (git dirty + explicit add). Writes outside it fail closed. Map still shows the rest.
3. **Invalid grammar must not crash the map.** Aider #5138: skip bad queries, keep filename-only. Prism parse failure → filename line, don’t abort `/fix`.
4. **Auto-commit with a real message, path-scoped.** Aider commits every turn. MASTER law is `git commit -- <paths>` on a worktree. Completeness: optional `/commit` after a successful `/fix` pass using the finding ids as the body. Never `git add -u`.
5. **Co-authored-by from verified session participants.** OpenClaw + Aider `--attribute-co-authored-by`. MASTER is one operator. Completeness: trailer `Co-authored-by: MASTER <master@brgen.no>` only on `/commit` from the runtime, so `git log` can tell agent commits from human ones. Don’t invent a team credit UI.

### Cline — HITL, plan/act, headless JSON

6. **Every edit and bash is a diff until auto-approve.** Cline Plan/Act. MASTER CLI operator is the human; the face visitor is not. Completeness: visitor profile already cannot Shell. Operator CLI: a `--ask` that prints the StrReplace hunk and waits. Default for `/fix` stays scan-with-write (law). Don’t add a VS Code extension.
7. **Checkpoints to undo the agent.** Cline. Same as `/undo` + worktree reset (OpenClaw list 13). One implementation.
8. **Headless JSON for CI.** `cline --json "…"`. MASTER `bin/master --json` / `operator gate --scan-only` already machine. Completeness: `/review --only scan --format json` is the contract test, not a new CLI.
9. **Linter errors as a loop, not a later gate.** Cline watches diagnostics while editing. MASTER FixLoop already re-scans. Completeness: FastStage rubocop is that loop. Don’t spawn a language server.
10. **`.clinerules` is another AGENTS.md.** OpenCrabs already discovers it. MASTER generates harness files. When pointed at a foreign tree, read as data (OpenClaw list 21). Don’t copy Cline’s rule format into pub4.
11. **SDK as a second product.** Cline `@cline/sdk`. MASTER is `bin/master`. Don’t publish an npm SDK.

### Goose (AAIF / Linux Foundation)

12. **MCP-first extensions, not a tool zoo.** Goose. MASTER has MCP coordinator untested (first inventory). Completeness: one MCP client path with SsrfGuard (bughunt 78), stdio only on the box, HTTP behind the allow-list. Don’t “50 tools.”
13. **Desktop + CLI + API.** Goose. MASTER is CLI + Falcon face. Completeness: the face *is* the API. Don’t a Tauri app.
14. **Donated to AAIF.** Governance note, not a feature. MASTER stays this repo’s constitution, not a foundation product.

### OpenHands, Warp, Open Interpreter

15. **OpenHands sandbox GUI.** Out (OpenClaw list 40). Steal: a *named* workspace snapshot before a swarm, which is the worktree.
16. **Warp ADE / Orca fleet.** Parallel agents with a subscription. MASTER FixLoop is one writer. Completeness: `operator worktree` per subagent (OpenCrabs 0.3.83), not a desktop fleet.
17. **Open Interpreter.** Natural language → shell. MASTER Shell is elevated. Completeness: visitor never gets it; operator gets PathGuard. Don’t loosen.

### OpenCode leftovers

18. **Language servers for symbol context.** OpenCode. MASTER has Prism `CodeIndex`. Completeness: repo map (1) *is* the LSP-less equivalent. Don’t start `ruby-lsp` from the agent.
19. **Parallel sessions.** OpenCode TUI split panes. MASTER Session is one Fiber. Completeness: two `bin/master` in two worktrees, already the law. Don’t multiplex two writes on main.
20. **Sign in with Copilot/ChatGPT subscription.** OpenCode. MASTER keys in `/etc/*.env`. Completeness: document that a Copilot token is a provider row, not a product. Don’t OAuth in the face.

### Continue is a tombstone

21. **Continue joined Cursor; repo read-only.** Don’t follow Continue Hub, don’t vendor its autocomplete. If someone cites Continue as a peer, the answer is Cline or OpenCode.

### Cross-cutting that these trees share and MASTER still splits

22. **Dirty-set + map + budget is one prompt recipe.** Aider proved it. `/fix` today dumps files or greps. Completeness: prompt = (writable hunks) + (repo map ≤ N tokens) + (finding). Measure tokens; don’t guess.
23. **Edit format is structured.** Aider search/replace vs diff vs whole-file. MASTER `StrReplace` / `AstEdit` (broken call, bughunt 66). Completeness: one edit tool that works; delete the one that `NoMethodError`s.
24. **Git is the undo log.** Aider, Cline checkpoints, OpenClaw worktrees. MASTER shared-index law already. Completeness: `/fix` without a worktree refuses on a dirty main (restructure 8). That’s the product difference from Aider’s auto-commit-on-main.

### Still out

25. **VS Code / JetBrains / Warp as a shell around MASTER.** The face and `bin/master` are the surfaces.
26. **Harbor / Cline-bench as a hosted eval.** `bin/check --profile=agent` is the eval. Don’t a third-party SWE farm.
27. **Kilo / Roo as a Cline fork to absorb.** Same HITL idea (6).


## ChatGPT proposed forward work — intake 2026-09-11

478 items, worked 2026-09-13. About 306 were built, false or already open
elsewhere; 43 were done with a test each; about 110 were refused, with the
arguments in `MASTER/DECISIONS.md` and `OPENBSD/DECISIONS.md` under the
2026-09-13 intake headings; seven product wishes went to `RAILS/apps.horizon.yml`.
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

Closed 2026-09-13. The measuring half was built or refused, and the argument is
in `MASTER/DECISIONS.md`, "dilla Measures From Kept Takes, Not From An Intake".
One decision stays with the operator.

- **Sound changes the intake proposed.** A `ROUGH_HEWN` or `DENSE_EXPERIMENTAL`
  profile, a mastering stage split from the mix bus, stem-group routing,
  deliberate mono-source widening, per-channel strip variance, MPC-style shift
  timing, and sample-start offsets independent of drum timing each change how a
  take sounds. Decide which, if any, to try. Seams: `lib/outboard.rb`,
  `lib/console_strip.rb`, `lib/groove_engine.rb`, `DILLA_STYLE_DEFAULTS`.


## MASTER web UI — future-human face — ChatGPT intake 2026-09-11

Closed 2026-09-13 except the operator's look and voice and one check that needs
a browser on vm23. The argument is in `MASTER/DECISIONS.md`, "The Face Intake
Was A Design Brief, And The Design Is The Operator's".

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


## layout_micro_refinement — ChatGPT intake 2026-09-11

Unmeasured. `RAILS/shared/design_tokens.yml`, `_typography.scss`, ScaleLint,
`layout_snapshots`, visual_contract, and one chrome already exist. Do not invent
a second token file. Apply the scale that is there. Look stays the operator’s:
colours, radii that change the paint, dating immersive chrome, playlist SF Mono,
recorded popover shadow, Kaufland copy-styling. A finding is a hypothesis.

### master_design_system

1. Establish one canonical spacing scale for MASTER and Brgen; replace arbitrary margins/padding with scale tokens.
2. Establish one canonical radius scale; remove one-off border-radius values.
3. Establish one canonical border hierarchy: structural, interactive, selected, disabled, destructive.
4. Establish one canonical elevation model; eliminate decorative shadows that do not communicate hierarchy.
5. Establish one canonical surface model: page, panel, elevated panel, interactive surface, overlay.
6. Establish one canonical content-width system; prevent each vertical from inventing unrelated max-widths.
7. Establish one canonical control-height scale for buttons, inputs, tabs, selects and compact controls.
8. Establish one canonical icon-size scale.
9. Establish one canonical avatar/media-size scale.
10. Establish one canonical typography scale rather than component-specific font sizes.
11. Establish one canonical line-height scale matched to the typography scale.
12. Establish one canonical text-width measure for readable prose.
13. Establish one canonical responsive breakpoint vocabulary.
14. Establish one canonical motion-duration scale.
15. Establish one canonical easing vocabulary.
16. Establish one canonical focus-ring treatment.
17. Establish one canonical disabled-state treatment.
18. Establish one canonical loading/skeleton treatment.
19. Establish one canonical empty-state treatment.
20. Establish one canonical error-state treatment.
21. Establish one canonical success/confirmation treatment.
22. Establish one canonical tooltip/popover treatment.
23. Establish one canonical modal/dialog geometry.
24. Establish one canonical drawer/sheet geometry.
25. Add design-token linting so new arbitrary values become measurable violations.
26. Add a token-usage report showing which CSS values remain outside the design system.
27. Add a duplicate-token detector for visually equivalent colors, spacing, radii and typography.
28. Collapse visually equivalent tokens rather than preserving historical names indefinitely.
### typography

29. Audit every Brgen vertical for typographic hierarchy rather than merely font-size hierarchy.
30. Make heading weight, size, line-height and spacing form one deliberate hierarchy.
31. Reduce unnecessary font-weight variation.
32. Reserve the strongest weight for genuinely important information.
33. Establish a clear distinction between navigation text, labels, metadata, body text and primary actions.
34. Reduce uppercase text where it harms readability.
35. Audit letter-spacing independently for headings, labels, buttons and metadata.
36. Prevent typography from becoming visually noisy through excessive bold text.
37. Establish a maximum readable line length for marketplace descriptions and community posts.
38. Establish compact measures for cards and dense transactional interfaces.
39. Ensure numerical information uses consistent alignment and typographic treatment.
40. Standardize price typography across marketplace and takeaway.
41. Standardize timestamp typography across messenger, posts, comments and notifications.
42. Standardize seller/shop/user metadata hierarchy.
43. Standardize secondary text contrast without allowing metadata to disappear.
44. Test Norwegian compound words and long labels at every responsive width.
45. Test typography with unusually long usernames, product names and marketplace titles.
46. Test typography with zero-width and empty states rather than designing only for populated content.
47. Ensure truncation always preserves semantic recognition.
48. Prefer multiline wrapping where truncation would hide important transactional information.
49. Ensure text truncation never produces unexplained layout jumps.
50. Audit icon-plus-text combinations for baseline alignment.
51. Audit button labels for consistent optical centering rather than mathematically equal padding.
52. Test font rendering at normal browser zoom, 125%, 150%, 200% and mobile text scaling.
53. Test the interface using system font fallback when the preferred font is unavailable.
54. Measure cumulative layout shift caused by font loading.
55. Remove typography choices that exist only because they looked good in one screenshot.
### optical_alignment

56. Add an optical-alignment pass after geometric alignment.
57. Correct icons that appear vertically misaligned despite equal CSS dimensions.
58. Correct asymmetric icon shapes that require optical rather than mathematical centering.
59. Audit circular avatars whose visual mass differs from their bounding box.
60. Audit buttons with text/icons whose perceived center differs from their flex center.
61. Audit cards where headings appear too close to one edge despite equal padding.
62. Audit image crops for perceived rather than mathematical centering.
63. Establish rules for optical inset compensation rather than scattered magic numbers.
64. Prefer component-level optical tokens over individual CSS exceptions.
### density

65. Define explicit density modes for Brgen: comfortable, standard and compact.
66. Make marketplace and takeaway intentionally denser than social/community surfaces.
67. Keep messenger dense enough for scanning without becoming visually cramped.
68. Keep landing/home surfaces calmer than transactional surfaces.
69. Prevent every vertical from independently choosing its own information density.
70. Measure information density using visible actions/content per viewport.
71. Test whether additional whitespace actually improves comprehension before retaining it.
72. Remove whitespace that merely separates elements without communicating hierarchy.
73. Preserve whitespace where it establishes grouping or reduces cognitive load.
74. Ensure density changes never alter the semantic hierarchy.
### cards

75. Stop treating every piece of content as a rounded card.
76. Classify components as surface, list row, card, panel, section or overlay.
77. Remove nested cards where a divider or spacing would communicate hierarchy better.
78. Remove redundant borders around already-separated surfaces.
79. Ensure card padding follows the spacing scale.
80. Ensure card title/body/action spacing follows one rhythm.
81. Establish maximum useful card complexity before content moves into a dedicated page.
82. Ensure card hover states do not cause layout movement.
83. Ensure card selection states are distinguishable without relying solely on color.
84. Ensure cards with different content types still share the same structural grammar.
85. Audit every “card within card” construction for unnecessary hierarchy.
### navigation

86. Reduce navigation choices visible simultaneously when they compete for attention.
87. Establish one primary-navigation pattern shared by Brgen verticals.
88. Establish one secondary-navigation pattern.
89. Establish one breadcrumb pattern where breadcrumbs are useful.
90. Make current location visually obvious without relying solely on color.
91. Make back-navigation predictable across mobile and desktop.
92. Prevent vertical-specific navigation from contradicting global Brgen navigation.
93. Ensure deep links retain enough contextual identity to explain where the user is.
94. Audit tab bars for excessive tab counts.
95. Replace overflowed tab rows with deliberate scrolling or grouped navigation.
96. Make navigation hierarchy match URL/application hierarchy.
### marketplace

97. Make product price the strongest visual element after the product image.
98. Make availability, condition and location immediately scannable.
99. Establish one consistent product-card anatomy.
100. Standardize image aspect-ratio handling.
101. Prevent seller metadata from competing visually with price.
102. Establish a consistent distance between price and primary transaction action.
103. Make filtering state persistent and visually explicit.
104. Make sort/filter controls occupy predictable locations.
105. Make search dominant without making the interface look like a generic search engine.
106. Establish consistent result-count treatment.
107. Make saved/favorite state persistent and unmistakable.
108. Make product comparison easier without introducing dashboard-like complexity.
109. Establish a consistent product-detail hierarchy: media → title → price → condition/availability → seller → action → details.
110. Make transactional actions sticky only when measurement shows meaningful benefit.
111. Ensure marketplace cards remain useful at narrow mobile widths.
112. Test dense marketplace grids against Kaufland-like retail scanning patterns without copying proprietary styling.
### takeaway

113. Make restaurant/shop identity immediately distinguishable from individual products.
114. Establish consistent food-image proportions.
115. Make delivery/pickup status visible before secondary metadata.
116. Make cart state persistent without overwhelming browsing.
117. Keep category navigation stable while scrolling.
118. Establish one consistent product-row anatomy.
119. Make price/add controls visually subordinate to product identity but immediately accessible.
120. Make unavailable items visually understandable without making the entire card look disabled.
121. Establish one cart-summary hierarchy.
122. Ensure restaurant/store information never gets visually mixed with product information.
123. Audit checkout for unnecessary decorative UI.
### messenger

124. Establish a true conversation-list density model rather than reusing generic Brgen cards.
125. Make unread state primarily typographic/structural, not decorative.
126. Establish one message-grouping rhythm.
127. Reduce repeated avatars/names when consecutive messages share an author.
128. Establish consistent timestamp visibility rules.
129. Make composer height predictable.
130. Prevent the composer from visually competing with messages.
131. Establish one attachment-preview anatomy.
132. Establish one reply/quote anatomy.
133. Make message actions discoverable without permanently exposing excessive controls.
134. Ensure message hover actions do not cause content movement.
135. Establish clear distinction between sent, received, system and failed messages.
136. Make failed-message state recoverable in-place.
137. Make typing/listening/recording states subtle rather than theatrical.
138. Ensure the messenger remains usable when JavaScript or realtime connectivity degrades.
### social / community

139. Establish one post-header hierarchy.
140. Reduce repeated metadata around posts.
141. Make author identity visually strong but not dominant over content.
142. Establish one reaction/action-row anatomy.
143. Ensure comments do not visually become a second unrelated application.
144. Establish nesting limits for replies.
145. Prevent deep indentation from destroying usable text width.
146. Establish one media-gallery treatment.
147. Ensure post media dominates when media is the content rather than decoration.
148. Establish one empty-feed treatment.
149. Make feed loading visually quiet.
### maps

150. Make map controls share the global Brgen control language.
151. Avoid allowing map-specific controls to become a visually separate application.
152. Establish one location-marker grammar.
153. Establish one selected-location treatment.
154. Establish one map-result-card anatomy.
155. Ensure overlays do not obscure important map content unnecessarily.
156. Make mobile map/list transitions predictable.
157. Ensure map controls remain usable at high browser zoom.
### dating

158. Remove generic dating-app visual tropes that conflict with Brgen identity.
159. Establish a consistent profile hierarchy.
160. Make identity, location and intent scannable before decorative profile information.
161. Ensure interaction controls have the same geometry as other Brgen primary actions.
162. Avoid introducing an independent design language for dating.
163. Ensure profile-media treatment shares the same image rules as marketplace/community.
### playlist / media

164. Establish consistent album/artwork geometry.
165. Standardize play controls with Brgen interaction conventions.
166. Make active-track state structurally obvious.
167. Avoid turning media controls into a separate visual operating system.
168. Establish compact and expanded player states.
169. Ensure player state survives navigation without layout instability.
### maps_and_location

170. Standardize location labels, distances and geographic metadata across every vertical.
171. Use one representation for “nearby,” “distance,” “area” and “exact location.”
172. Prevent each subapp from inventing independent location badges.
173. Make location uncertainty explicit where precision is intentionally reduced.
### cross_vertical_consistency

174. Inventory every duplicated UI component across Brgen verticals.
175. Identify visually equivalent components with different implementations.
176. Consolidate equivalent components before adding new variants.
177. Establish shared primitives for buttons, inputs, tabs, cards, lists, badges, avatars, media and menus.
178. Establish shared primitives for loading/error/empty states.
179. Establish shared primitives for pagination/infinite-scroll indicators.
180. Establish shared primitives for notifications and toasts.
181. Establish shared primitives for confirmation/destructive actions.
182. Establish shared primitives for date/time formatting.
183. Establish shared primitives for money/price formatting.
184. Establish shared primitives for distance/location formatting.
185. Establish shared primitives for user identity.
186. Ensure verticals specialize through information architecture, not arbitrary styling.
187. Detect when a vertical introduces a component that already exists elsewhere.
188. Prefer extending an existing primitive over creating a visually similar sibling.
189. Document intentional exceptions and require a reason for each.
### responsive_refinement

190. Treat mobile as a first-class composition rather than a compressed desktop.
191. Audit every breakpoint for hierarchy changes rather than only width changes.
192. Ensure primary actions remain reachable with one hand where appropriate.
193. Prevent horizontal scrolling except where it is intentional.
194. Test long Norwegian words at every breakpoint.
195. Test keyboard navigation independently of pointer interaction.
196. Test touch targets at minimum usable dimensions.
197. Ensure sticky elements never cover content or focused controls.
198. Ensure viewport-height changes on mobile do not break composers, carts or dialogs.
199. Test browser chrome expansion/collapse effects on full-height layouts.
200. Test landscape mobile layouts.
201. Test large desktop displays without allowing content to become excessively stretched.
### motion

202. Define motion as a hierarchy rather than adding transitions globally.
203. Reserve animation for state change, spatial relationship or feedback.
204. Remove transitions that merely make static UI feel “slick.”
205. Establish motion duration by interaction importance.
206. Establish reduced-motion equivalents for every meaningful animation.
207. Ensure hover animation never communicates information unavailable to keyboard users.
208. Ensure loading animation has bounded visual complexity.
209. Prevent multiple nested animations from synchronizing into visual noise.
210. Establish a maximum simultaneous motion budget.
211. Audit page transitions for unnecessary animation.
### visual_noise_reduction

212. Remove decorative gradients that do not communicate hierarchy.
213. Remove ornamental borders that do not communicate structure.
214. Remove redundant badges.
215. Remove redundant icons.
216. Remove repeated labels where position already communicates meaning.
217. Remove shadows whose only purpose is aesthetic decoration.
218. Remove duplicated status indicators.
219. Remove competing accent colors.
220. Remove one-off illustrations where typography or spacing communicates the same state.
221. Apply “perfection is subtraction” as an explicit UI review criterion.
### accessibility_as_design_system

222. Make focus states part of the visual language rather than an accessibility afterthought.
223. Ensure every state has a non-color representation where necessary.
224. Ensure contrast is preserved across all surface combinations.
225. Ensure text remains understandable at 200% zoom.
226. Ensure interactive controls have predictable keyboard order.
227. Ensure dialogs establish focus and return it correctly.
228. Ensure dynamic content changes are announced appropriately.
229. Ensure reduced-motion does not remove semantic feedback.
230. Ensure screen-reader labels do not diverge from visible terminology.
231. Audit icon-only controls for accessible names.
### design_system_validation

232. Add automated detection for arbitrary spacing values.
233. Add automated detection for arbitrary radii.
234. Add automated detection for arbitrary colors.
235. Add automated detection for arbitrary typography values.
236. Add automated detection for duplicate component styles.
237. Add automated detection for inconsistent control heights.
238. Add automated detection for inconsistent icon sizing.
239. Add automated detection for inconsistent focus states.
240. Add automated detection for inconsistent disabled states.
241. Add visual regression snapshots for every major Brgen vertical.
242. Add representative screenshots for desktop, tablet and mobile.
243. Add “dense,” “normal” and “empty” fixture states.
244. Add long-content fixtures using Norwegian text.
245. Add pathological-content fixtures: long usernames, prices, titles, filenames and URLs.
246. Compare visual regressions by semantic region rather than whole-page pixel difference alone.
247. Record intentional visual differences as explicit design-system exceptions.
248. Fail validation when a new component introduces an unregistered design token.
249. Fail validation when equivalent components diverge without an explicit exception.
### MASTER_alignment

250. Map each visual-system rule to the corresponding MASTER law.
251. Treat duplicated visual constants as SINGULARITY violations.
252. Treat arbitrary component-specific styling as ABSTRACTION violations when an existing primitive covers the same need.
253. Treat unnecessary decoration as DENSITY violations.
254. Treat excessive nesting and indirection as LINEARITY violations.
255. Treat visually unrelated controls placed far from their semantic content as PROXIMITY violations.
256. Treat fragile responsive exceptions as ROBUSTNESS violations.
257. Add a UI `/sweep` that reports these violations before visual redesign work is accepted.
258. Make the UI sweep recursive across every Brgen vertical.
259. Require evidence before declaring a layout improvement complete.
260. Compare visual changes against the previous implementation rather than only the desired mockup.
261. Prefer deletion/consolidation before adding another component or token.
262. Require every new visual abstraction to have at least two real consumers unless there is a documented reason otherwise.
263. Keep design-system exceptions measurable and searchable.
264. Add a final “why does this exist?” pass to every major UI change.

264 items. Prefer deletion/consolidation. Do not restyle from this file.


## master_cli_dmesg_model — ChatGPT intake 2026-09-11

Unmeasured. `NO_ASCII_DECORATION` and `Trace::Dmesg` already exist; ChatController
dmesg is a second door (restructure 17). Default CLI is already a log, not a TUI.
Do not add a fake kernel boot, a second execution engine, or progress bars.
One event stream; text by default, JSON on request. A finding is a hypothesis.

### master_cli_dmesg_model

1. Model normal CLI output as an append-only execution trace rather than a presentation dashboard.
2. Make every important event express `subsystem: fact`.
3. Prefer facts over prose explanations.
4. Prefer topology and relationships over indentation.
5. Prefer stable subsystem names over visual section headers.
6. Prefer instance identifiers where multiple workers/components exist.
7. Make execution hierarchy visible through names and relationships rather than nested UI.
8. Avoid boxes, banners, decorative separators and dashboard panels in default output.
9. Avoid progress bars in default output.
10. Avoid spinners in default output.
11. Avoid animated terminal repainting in default output.
12. Avoid “AI assistant” presentation language.
13. Avoid narrating obvious operations as sentences.
14. Avoid redundant `starting...`, `working...`, `done!` chatter.
15. Emit a line when a meaningful subsystem state changes.
16. Do not emit a line merely because a method was called.
17. Do not emit a line merely because an internal object changed.
18. Preserve raw evidence where the evidence itself is useful.
### subsystem grammar

19. Define canonical subsystem names for MASTER execution.
20. Use short stable names such as `master`, `repo`, `config`, `rules`, `soul`, `workflow`, `scan`, `sweep`, `council`, `git`, `test`, `patch`, `web`, `tts`, `error`.
21. Allow subsystem instances where parallel or nested execution makes them useful.
22. Keep subsystem identifiers stable across releases.
23. Make subsystem names grep-friendly.
24. Make subsystem names machine-parseable without requiring JSON.
25. Avoid verbose class/module names in ordinary output.
26. Avoid implementation-specific names unless debugging is enabled.
### fact grammar

27. Prefer `rules: loaded 187`
28. Prefer `scan: 412 files`
29. Prefer `violations: 3`
30. Prefer `git: dirty`
31. Prefer `patch: 7 files`
32. Prefer `test: 42 passed`
33. Prefer `tts: ready`
34. Prefer `web: face runtime loaded`
35. Avoid `MASTER has successfully loaded 187 rules`.
36. Avoid `We are now scanning 412 files`.
37. Avoid redundant natural-language narration.
### topology

38. Represent MASTER workflow relationships explicitly.
39. Make `scan at repo`, `rules at config`, `validation at workflow` relationships available where useful.
40. Treat the CLI trace as an observable execution topology.
41. Make parent/child relationships reconstructable from emitted facts.
42. Avoid visual nesting where semantic relationships can express the same information.
43. Ensure a log excerpt remains interpretable when copied without its preceding lines.
### boot

44. Design startup as a compact boot trace.
45. Report repository identity.
46. Report effective configuration sources.
47. Report constitutional sources.
48. Report runtime identity.
49. Report model/provider identity when relevant.
50. Report initial invariants.
51. Emit `master: ready` only after the boot invariants pass.
52. Do not print a startup banner.
53. Do not print an ASCII logo.
54. Do not print a version splash screen.
### workflow_trace

55. Represent Discover → Analyze → Ideate → Design → Implement → Validate → Deliver → Learn as trace events.
56. Enter each phase with one deterministic event.
57. Emit only meaningful phase-local facts.
58. Record phase completion only after its completion criteria pass.
59. Record phase failure at the point of failure.
60. Make the final trace reconstruct the workflow without a separate progress UI.
61. Preserve chronological ordering.
62. Avoid re-rendering previous output.
### counts

63. Use counts where they communicate concrete evidence.
64. Prefer `scan: 412 files`.
65. Prefer `rules: 187 active`.
66. Prefer `test: 42 passed, 0 failed`.
67. Prefer `violations: 3 unresolved`.
68. Avoid percentage completion when completion cannot be measured honestly.
69. Avoid arbitrary “progress” numbers generated merely to make the CLI feel active.
70. Never display `100%` until the underlying operation is actually complete.
### errors

71. Make errors follow the same `subsystem: fact` grammar as successful output.
72. Make the failed subsystem immediately identifiable.
73. Include the actual failing resource.
74. Include the underlying reason.
75. Include recovery information only when it is deterministic.
76. Avoid dramatic error formatting.
77. Avoid color-dependent error semantics.
78. Preserve the original exception in debug mode.
79. Keep normal errors concise.
### warnings

80. Make warnings factual rather than conversational.
81. Distinguish advisory warnings from blocking conditions.
82. Include the affected subsystem.
83. Include the affected path/resource.
84. Avoid warning banners.
85. Avoid repeating the same warning on every dependent operation.
### paths

86. Standardize path formatting.
87. Prefer paths relative to the MASTER repository when that improves readability.
88. Use absolute paths only when necessary to disambiguate.
89. Preserve exact paths in machine-readable output.
90. Make paths directly copyable into shell commands.
91. Avoid shortening paths in a way that destroys identity.
### repeated events

92. Preserve repeated events when repetition itself is evidence.
93. Collapse repeated noise only when it carries no diagnostic value.
94. Never deduplicate genuine hardware/runtime failures merely for prettier output.
95. Provide aggregation only as an optional presentation mode.
96. Keep default output faithful to execution.
### silence

97. Make successful low-level operations silent when their result is not decision-relevant.
98. Treat silence as a valid success state.
99. Avoid emitting “ok” for every operation.
100. Avoid emitting “complete” for every subtask.
101. Avoid progress chatter merely to reassure the user that MASTER has not frozen.
102. For long-running operations, emit sparse liveness facts only when needed.
### terminal_independence

103. Make default output correct when piped through `cat`.
104. Make default output correct when piped through `less`.
105. Make default output correct when redirected to a file.
106. Make default output correct over SSH.
107. Make default output correct on narrow terminals.
108. Make default output correct without color.
109. Make default output correct without cursor control.
110. Make default output useful after losing the first half of the terminal buffer.
### ansi

111. Make ANSI formatting optional.
112. Make monochrome output semantically complete.
113. Respect `NO_COLOR`.
114. Disable ANSI when stdout is not a TTY.
115. Never encode semantic state exclusively through color.
116. Keep the default palette extremely small.
### dmesg_mode

117. Add an explicit `--dmesg`/trace presentation mode only if a second presentation is actually necessary.
118. Make the canonical default already conform to the dmesg grammar where practical.
119. Do not create a second execution engine merely to support dmesg formatting.
120. Render the same underlying event stream through human and machine presenters.
121. Ensure dmesg presentation is append-only.
122. Ensure dmesg presentation never rewrites previous lines.
### machine_trace

123. Define an internal event representation underneath CLI rendering.
124. Give each event a timestamp/sequence only when needed.
125. Give each event a subsystem.
126. Give each event an event type.
127. Give each event a severity.
128. Give each event structured attributes.
129. Render those events as terse text by default.
130. Render the same events as JSON when requested.
131. Ensure human and JSON output cannot disagree about execution state.
### openbsd_fidelity

132. Study actual OpenBSD dmesg grammar rather than approximating its appearance.
133. Preserve the characteristic `device at parent` relationship where it maps naturally to MASTER.
134. Preserve terse comma-separated facts.
135. Preserve stable subsystem naming.
136. Preserve chronological discovery.
137. Preserve repeated lines when operationally meaningful.
138. Preserve precise error messages.
139. Avoid copying kernel-specific terminology where it has no semantic equivalent.
140. Do not turn MASTER into a fake kernel boot log.
141. Use dmesg as a behavioral/presentation reference, not cosplay.
### self_test

142. Add golden traces for successful canonical MASTER execution.
143. Add golden traces for constitutional failure.
144. Add golden traces for rule violations.
145. Add golden traces for Git failure.
146. Add golden traces for model/provider failure.
147. Add golden traces for partial execution.
148. Add golden traces for interrupted execution.
149. Assert deterministic event ordering.
150. Assert no decorative output in default mode.
151. Assert no ANSI output under non-TTY execution.
152. Assert stderr/stdout separation.
153. Assert correct exit status for each terminal state.
### final_constraint

154. Review every CLI line with one question: “Would this line exist in a good system diagnostic trace?”
155. Delete lines whose only purpose is to make the program feel busy.
156. Delete lines whose only purpose is emotional reassurance.
157. Delete lines that merely repeat the command being executed.
158. Delete formatting that competes with the information.
159. Preserve lines that establish topology, state, evidence or failure.
160. Make the CLI feel like a system revealing itself rather than an application performing for the user.

160 items. Would this line exist in a good system diagnostic? If not, delete it.


## pub4 subtraction and entropy — ChatGPT intake 2026-09-11

Unmeasured repo-wide pass: what should exist, what should disappear, what should
become simpler. `operator gate`, sprawl census, FILE_SPRAWL, restructure “one job,
one door,” and soul `perfection is subtraction` already exist. Do not invent a
second CI in git hooks, rewrite history for cosmetics, merge trees for visual
similarity, or LAYER_CAKE. If two things mean the same thing, why do both exist?
If complexity rises faster than capability, the next work is subtraction.
A finding is a hypothesis.

### Remove / consolidate

1. Delete obsolete compatibility layers once their consumers are gone.
2. Remove dead files, dead constants, dead methods and dead configuration.
3. Remove duplicate YAML/JSON registries.
4. Remove duplicate implementations of the same concept across MASTER/RAILS/OPENBSD/STUDIO.
5. Remove historical migration code that no longer participates in startup/runtime.
6. Remove stale TODO items that describe already-completed work.
7. Remove TODO items whose premise has been disproven by measurement.
8. Remove generated artifacts from source when they can be deterministically rebuilt.
9. Remove manually maintained generated files where safe.
10. Remove unused dependencies from every Gemfile/package manifest.
11. Remove dependencies that duplicate Ruby/Rails standard functionality.
12. Remove abandoned experiments rather than preserving them indefinitely “just in case.”
13. Remove compatibility aliases with zero remaining callers.
14. Remove obsolete environment variables.
15. Remove configuration values that have only one possible value.
16. Remove wrapper methods that add no semantic value.
17. Remove one-line abstractions that merely rename another operation.
18. Remove defensive code for impossible states once the invariant is enforced centrally.
19. Remove duplicated validation between adjacent layers where one authoritative validation point is sufficient.
20. Remove decorative CLI/UI machinery that doesn't expose useful state.
21. Remove redundant logging.
22. Remove noisy debug logging from normal execution.
23. Remove duplicate tests that exercise identical behavior without adding coverage.
24. Remove fixtures that encode obsolete behavior.
25. Remove obsolete documentation that conflicts with actual behavior.
26. Remove stale references to deleted files such as old `axioms.yml`-style paths.
27. Remove abandoned branches/worktrees/scripts from the repository where they have no operational purpose.
28. Remove “future work” language for work that is already implemented.
29. Remove speculative abstractions before they acquire consumers.
### Simplify architecture

30. Establish one canonical configuration-loading path.
31. Establish one canonical repository/root discovery mechanism.
32. Establish one canonical runtime context object.
33. Establish one canonical result/error representation.
34. Establish one canonical violation representation.
35. Establish one canonical rule representation.
36. Establish one canonical workflow-phase representation.
37. Establish one canonical model/provider representation.
38. Establish one canonical subprocess execution layer.
39. Establish one canonical filesystem abstraction where abstraction is actually justified.
40. Establish one canonical command/event representation.
41. Establish one canonical path-normalization policy.
42. Establish one canonical logging/event emission mechanism.
43. Establish one canonical timeout policy.
44. Establish one canonical retry policy.
45. Establish one canonical cancellation mechanism.
46. Establish one canonical concurrency policy.
47. Establish one canonical temporary-directory policy.
48. Establish one canonical cleanup policy.
### Dependency hygiene

49. Produce a complete dependency inventory for each application.
50. Identify dependencies used by only one trivial feature.
51. Identify dependencies whose functionality overlaps.
52. Identify transitive dependencies that can be eliminated by changing one direct dependency.
53. Verify every runtime dependency has an actual runtime consumer.
54. Verify development/test dependencies aren't loaded in production.
55. Establish dependency update policy.
56. Record intentionally pinned versions and why.
57. Detect abandoned gems/packages.
58. Detect duplicate libraries solving the same problem.
59. Measure startup cost of heavyweight dependencies.
60. Measure memory impact of major dependencies.
61. Test clean installation from an empty environment.
62. Test deployment with only declared dependencies.
63. Remove accidental host-machine dependencies.
### Ruby quality

64. Run a whole-repository Ruby syntax pass.
65. Run a whole-repository parser/AST pass.
66. Establish one Ruby formatting/style source of truth.
67. Detect methods with excessive branching.
68. Detect excessive method length.
69. Detect excessive class/module size.
70. Detect excessive nesting.
71. Detect high fan-out classes.
72. Detect circular dependencies.
73. Detect constants referenced across inappropriate boundaries.
74. Detect private APIs being used externally.
75. Detect accidental public methods.
76. Audit `rescue StandardError`.
77. Audit bare `rescue`.
78. Audit exception swallowing.
79. Audit `ensure` correctness.
80. Audit subprocess handling.
81. Audit shell interpolation.
82. Audit filesystem race conditions.
83. Audit temporary-file handling.
84. Audit encoding assumptions.
85. Audit timezone assumptions.
86. Audit implicit global state.
87. Audit mutable constants.
88. Audit thread lifecycle.
89. Audit unbounded queues.
90. Audit unbounded loops.
91. Audit implicit network calls.
92. Audit methods whose names don't match their side effects.
### Rails quality

93. Audit controllers for business logic.
94. Audit models for excessive responsibilities.
95. Audit service objects for abstraction without justification.
96. Audit callbacks for hidden side effects.
97. Audit concerns for accidental coupling.
98. Audit serializers/presenters/view models for duplication.
99. Audit routes for obsolete endpoints.
100. Audit jobs for retry/idempotency correctness.
101. Audit mailers for stale templates.
102. Audit ActiveRecord queries for N+1 behaviour.
103. Audit unnecessary eager loading.
104. Audit unnecessary database round trips.
105. Audit missing indexes based on actual query patterns.
106. Audit unused indexes.
107. Audit database constraints vs application-only validation.
108. Audit migrations for historical cruft.
109. Audit authorization boundaries.
110. Audit authentication assumptions.
111. Audit CSRF/session/security defaults.
112. Audit caching correctness and invalidation.
113. Audit Solid Queue/Cache/Cable usage and lifecycle.
114. Audit ActionCable channels for subscription cleanup.
115. Audit background jobs for duplicate execution.
116. Audit all external requests for timeouts.
### Security

117. Full secret/credential scan.
118. Full shell-injection scan.
119. Full command-injection scan.
120. Full path-traversal scan.
121. Full SSRF scan.
122. Full unsafe-deserialization scan.
123. Full HTML/ERB injection scan.
124. Full SQL construction scan.
125. Full URL handling scan.
126. Full file-upload scan.
127. Full authorization matrix.
128. Full session/cookie configuration review.
129. Full CORS review.
130. Full CSP review.
131. Full security-header review.
132. Full dependency vulnerability audit.
133. Verify production error responses don't leak internals.
134. Verify logs don't leak secrets/tokens/PII.
135. Verify debug endpoints cannot become production endpoints.
136. Verify development-only routes/assets are unreachable in production.
137. Add regression tests for every discovered security boundary.
### Testing

138. Measure branch coverage where useful.
139. Measure mutation-testing value on critical logic.
140. Identify untested failure paths.
141. Identify tests that only test implementation details.
142. Identify tests that pass while the feature is broken.
143. Add contract tests between subsystems.
144. Add property tests for parsers/configuration.
145. Add fuzzing for hostile inputs.
146. Add concurrency tests where state is shared.
147. Add timeout tests.
148. Add cancellation tests.
149. Add retry tests.
150. Add partial-failure tests.
151. Add malformed-data tests.
152. Add empty-repository tests.
153. Add huge-repository tests.
154. Add low-memory tests.
155. Add offline tests.
156. Add fresh-install tests.
157. Add production-like deployment smoke tests.
158. Add regression fixtures for every previously fixed serious bug.
### Performance

159. Boot-time benchmark.
160. CLI startup benchmark.
161. Rails boot benchmark.
162. First-response latency.
163. Streaming latency.
164. Database query budget.
165. Browser first meaningful render.
166. Browser JS execution budget.
167. Face/WebGL frame budget.
168. TTS startup budget.
169. Memory baseline.
170. Repository scan throughput.
171. Large-repository scaling test.
172. Large-file scaling test.
173. Concurrent-user baseline.
174. Background-job throughput.
175. Identify performance regressions in CI.
176. Don't optimize measured non-problems.
### Operational reliability

177. Every network request gets a timeout.
178. Every long-running operation gets cancellation semantics.
179. Every background worker has bounded lifetime.
180. Every queue has bounded behaviour.
181. Every retry has a limit/backoff policy.
182. Every external dependency has a degraded mode where practical.
183. Every daemon has clean shutdown.
184. Every temporary resource has deterministic cleanup.
185. Every deployment has a rollback path.
186. Every migration has failure/recovery considerations.
187. Every production process exposes enough diagnostics to identify failure without attaching a debugger.
### OpenBSD / deployment

188. Rebuild a machine from zero using only repository documentation.
189. Verify every documented package is actually required.
190. Verify every service has one owner/configuration source.
191. Audit `rc.d`/`rcctl` lifecycle.
192. Audit `pf` rules.
193. Audit `relayd`.
194. Audit TLS renewal.
195. Audit DNS configuration.
196. Audit filesystem permissions.
197. Audit service users/groups.
198. Audit `doas` rules.
199. Audit pledge/unveil boundaries.
200. Test reboot recovery.
201. Test service restart recovery.
202. Test certificate renewal.
203. Test disk-full behaviour.
204. Test memory pressure.
205. Test network interruption.
206. Test application crash/restart.
207. Test log rotation.
208. Document the minimum viable production installation.
### Documentation

209. Every operational document gets an executable verification command.
210. Every architectural document names the actual files implementing it.
211. Remove documentation describing nonexistent architecture.
212. Remove duplicate architecture documents.
213. Make README claims mechanically testable where practical.
214. Record invariants separately from implementation details.
215. Record deliberate deviations from defaults.
216. Add “why” only where the reason isn't obvious from code.
217. Delete explanations that merely restate code.
218. Keep historical archaeology separate from current architecture.
219. Date/version genuinely historical decisions.
220. Make generated documentation obviously generated.
### Git hygiene

221. Identify commits that introduced dead architecture.
222. Identify reverted/reimplemented features.
223. Identify files repeatedly rewritten without converging.
224. Identify accidental generated-file commits.
225. Identify large binaries/assets that don't belong in Git.
226. Identify enormous commits that should have been decomposed.
227. Identify misleading commit messages.
228. Establish commit-message conventions only if they provide actual value.
229. Add pre-commit checks only for cheap/high-value invariants.
230. Avoid turning Git hooks into a second CI system.
231. Preserve useful archaeology; don't rewrite history merely for cosmetic cleanliness.
### Repository topology

232. Count files by subsystem.
233. Count LOC by subsystem.
234. Count dependencies by subsystem.
235. Count cross-subsystem imports/references.
236. Build a dependency graph.
237. Detect cycles.
238. Detect isolated code.
239. Detect “god directories.”
240. Detect directories with only one meaningful file.
241. Detect files with suspiciously high fan-in/fan-out.
242. Detect concepts appearing in multiple trees.
243. Identify candidates for consolidation.
244. Identify boundaries that should remain separate.
245. Measure whether `MASTER`, `RAILS`, `OPENBSD`, and `STUDIO` actually benefit from sharing code.
### subtraction pass

246. What can be deleted?
247. What can be merged?
248. What can become data instead of code?
249. What can become one source of truth?
250. What can become a standard-library call?
251. What can become a test instead of runtime machinery?
252. What can become an invariant instead of defensive code?
253. What can disappear because the underlying problem no longer exists?

### periodic architectural entropy audit

254. Measure files, LOC, dependencies, duplicate concepts, cross-boundary references, dead code, configuration sources, and special cases against capabilities, coverage, reliability, performance, and maintainability. Prefer subtraction when complexity outruns capability.

254 items. Capability first; then delete.

---

## Measured subtraction candidates — 2026-09-11

Continuation of the entropy pass. These have a path. Verify the second caller before deleting the first.

1. **Unwired slash tables — verified, and the proposed fix would break five live
   commands.** The claim is true: `CommandRegistry.build` merges
   `control_commands` and nothing else, `build_fast` returns status and help,
   and `slash_commands` is built from `HELP_TOPICS` — so `memory_commands`,
   `system_commands` and `media_commands` are required at the top of
   command_registry.rb and reachable from no path a person can type. They have
   been unreachable since `7c23a5ee5` (2026-08-17, "slash surface is a sentence
   and eight verbs"): the merge went then and the tables stayed. Help advertises
   twelve verbs and none of them is one of these.

   Deleting the three FILES breaks `/commit`, `/pair`, `/doctor`, `/rules` and
   `/tree`. Measured by doing it: those five dispatchers live in
   system_commands.rb beside the dead table, and `build` calls them by symbol —
   `command(:dispatch_doctor, root)` — so a grep for the table's name says
   nothing about them. `memory_search` is the same shape in memory_commands.rb,
   with three callers in context_provider and cohesion.

   The subtraction is method-level, and it needs reachability from a live root
   rather than "has a caller": almost every dispatcher in these files is called
   by its own table, so a caller census reads the dead set as live by
   circularity. `code_reach` answers this at file granularity and reads 0 dead
   files of 405, which is why nothing has caught it.

And it is seven tables, not three. `agent_commands`, `core_commands`,
`reach_commands` and `work_commands_extra` have no call site anywhere under
lib, web, bin or tools; media, memory and system are called only by tests.
`domain_commands`, `work_commands` and `work_commands_status` are the three
that are reached. `test_command_registry_dispatch` pins that set so an eighth
cannot join it quietly, and asserts that every symbol `build` dispatches
names a public method — the guard that would have caught the near-miss above
the moment it happened, where the whole suite stayed green.

   `test_capture_command_is_registered` asserts that the table contains
   "capture", not that the table reaches the registry, so it has passed for
   every one of those 25 days. Fix the test first — assert reachability through
   `CommandRegistry.build` — and it will name the dead set for you.
2. **`mask.js` — deleted 2026-09-11.** Superseded by face.js; `visual_limits.test.mjs` now only names `cognition_ecology.js`.
3. **`examples.html.erb` — a documentation file read as a view, and my first
   verdict on it was wrong.** I checked `MASTER/web/app/views/chat/` and called
   it gone; the item means `RAILS/shared/frontend/examples.html.erb`, which
   exists. backlog_triage caught my error by resolving the basename.

   It is not unmounted in the defect sense. Its first line reads "Copy selected
   examples into each app" — a snippet library, so nothing rendering it is the
   design. The assertion on it was redundant rather than misplaced: the line
   above it in `deploy_backlog_test` already asserts
   `shared/app/views/shared/_toast.html.erb`, which is the real artifact, so
   the second line proved that the documentation documents what it documents.
   Removed, with the reason in its place.

   The finding underneath is larger and stays open: nothing renders the toast
   partial either. `stimulus_boot.js:69` registers `["toast", Notification]`
   and no view in any app renders `shared/toast`, so the component is wired at
   the JavaScript end and reached from nowhere. Choosing where a toast appears
   is design work.
4. **Two `WebPushJob`s, and "one class" is false — but reading them side by
   side found a real bug.** `WebPushJob` takes a `notification_id`, builds a
   payload with a `tag` and a target path, and sends through `Webpush`
   directly; `Shared::WebPushJob` takes `user_id, title:, body:, url:` and
   delegates to `Shared::Pushable.deliver_now`. Different signatures,
   different senders, both reached — brgen's from `Notification#deliver`,
   shared's from `Pushable.push_to`. Folding them is a payload question
   (`tag:`, `urgency:` and `target_path` have no home in `Pushable`), not a
   duplicate-file cleanup.
   What the comparison did find is fixed: brgen destroyed the subscription on
   `Webpush::Unauthorized`, which is 401/403 — our VAPID credentials, failing
   identically for every row — so one bad key rotation unsubscribed the whole
   city, irreversibly. `Pushable` never listed it. The divergence was one
   rescue clause.
5. **`futurism` — the claim is false.** `futurize` appears in three ERB files,
   so the pin has a reader. Whether one lazy index is worth a gem is a
   different question from whether it is wired, and it is wired.
6. **`bin/crate` writes `dilla/crate/`.** Directory gone; engine reads `samples/`. Delete or retarget.
7. **Fixed 2026-09-12.** `OPENBSD/restore_litestream.sh`. Three separate passes
    asked for this rename, which is what a real defect looks like from outside.
    Its first line now reads "NOT the disaster-recovery script — use
    OPENBSD/bin/dr-pull for that", and the paragraph under it says why: vm23 has
    no litestream binary and no replicas, so the old name promised recovery the
    file cannot deliver, under exactly the name somebody reaches for in an
    emergency.
8. **Three atomic writes.** `Io::AtomicWrite` fsyncs; World and Live do not. One helper.
9. **Two PathGuards.** Prefix vs ancestor-realpath. One module, the strong check.
10. **`ChatController#dmesg` vs `Trace::Dmesg`.** One.
11. **`VoteReflex` vs `votes#create.turbo_stream`.** Keep the stream.
12. **Host vs shared notifications controllers.** One.
13. **Marketplace vs takeaway `_nav_bar`.** One partial.
14. **Fixed 2026-09-12.** The inline block is `shared/app/assets/stylesheets/_site_legal.scss`, moved with every value untouched — measured on brgen.no/privacy before and after, `.legal-prose` is 724.397px wide and its h1 is 28.8px/33.12px either way. Snapping those values onto the scales is a separate decision and the operator's.
15. **`.reading-column` / `.form-measure` — deliberate, and said so.** No view
    wears either. `css_coverage_lint.rb:96` records them as opt-in measure
    classes "worn by tokens, not yet by every view", so this is a decision
    already taken rather than residue. Wearing them is design work.
16. **MixScore backticks vs engine Open3 vs `RadioChop.capture`.** One ffmpeg runner, one `capture` signature.
18. **Two LUFS windows.** One.
19. **Fixed 2026-09-12.** `data/operator.yml` is the command list and now carries
     the whole of it: the check family (check-rails, check-openbsd, check-vps,
     check-full), vps-state and tree.sh lived only in START_HERE.md's Golden
     Commands, so the stub that pointed here was the more complete of the two.
     START_HERE's Golden Commands and Source Of Truth sections are pointers now,
     and RECIPES.md is a door rather than a table. `operator_docs.rb` reads the
     yaml and `/orient deploy` prints it, so a recipe added there shows at every
     door.
20. **Four deploy verbs.** Wrappers around `vps-deploy`.
21. **Two uptime-check scripts.** One file, one host list.
22. **Face tests in `spec/`, `test/`, `web/test/`.** Two homes at most.
23. **`bin/cli` vs `bin/master`.** One REPL file.
24. **`MASTER/lib/rails/`.** Move to `RAILS/gates/lib` or `/rails audit`.
25. **Zeitwerk ignore of the dead slash tables.** After (1), `rake lint:autoload` failing those entries is the deletion proof.

If two things mean the same thing, keep the one with the test.

26. **`swarm.html` / `diag.html`.** Public extra HTML, `lang="en"`, inline script, not the face. Gate behind auth or delete from production `public/`.
27. **`codebase.js` has no loader, which is worse than not being declared.**
    222 lines in `web/public/`, named by `topology_registry.js` and
    `data/topologies.yml` as the Repository Body topology's renderer — and
    that `renderer:` field is read by nothing. It is descriptive metadata, not
    a load instruction. Since the file is absent from `face_assets.yml`,
    `MASTER_ASSET_PATHS` does not carry it and `face.js` cannot import it, so
    the topology can be named and never drawn.

    Declaring it ships 222 lines to every visitor for a topology nothing
    switches to; deleting it removes a built visualisation. Either is a
    product decision, and the measurement is here so it can be made rather
    than guessed.
28. **`offline_memory.js` is a scaffold.** Comment: no wiring into chat. Wire enqueue or delete.
29. **Two importmap pins for one autogrow file — fixed 2026-09-11.** Both named
    the same vendor file and only `@stimulus-components/textarea-autogrow` was
    imported; `stimulus-textarea-autogrow` is the package's pre-scope spelling
    and nothing asked for it, so every page carried a modulepreload no import
    could resolve. One pin now.
30. **`bin/master-core`.** Fold spine only; `bin/master` boots the rest. `bin/dogfood` still calls it. `bin/master --core` or keep and give it one test that it is the fold, not a second product.
31. **Deals search is LIKE.** Listings/stores use `LiveSearchable`. One helper (restructure 39).
32. **brgen `NotificationsController` is local; amber inherits `Shared::`.** Promote or delete the host copy.
33. **`face.part*.txt` in `public/`.** Concatenated at build, still served. Move to a build dir.
34. **`smart-turn` ONNX (~21MB) default off.** Test that `index.html.erb` does not `<script src>` the wasm. Don’t ship it in the critical path.
36. **`smoke-apps.sh` vs `deploy-smoke.sh`.** One smoke; `port_inventory` `SMOKE_SCRIPTS` retargets.
37. **Fixed 2026-09-12, and the class is closed with it.** `stimulus_boot.js` retired
    content-loader on 2026-08-21 and `shared/frontend/examples.html.erb` went on
    offering the snippet for three weeks — a snippet library is copied by hand, so
    that handed someone a div that never loaded and no error. The container is gone.
    `test_every_controller_the_snippet_library_offers_is_registered` now checks every
    snippet against the registry: all 17 registered, every offer inside them, and the
    test fails when the retired one is put back. examples.html.erb stays — it is
    documentation, and item 3's proposal to delete it loses its argument now that it
    cannot go stale silently.
38. **Three face stores.** `felt_state.js`, `face_state.js`, `ui_presence.js`. Document boot order or fold presence into felt.
39. **`hello: Hei` in brgen and amber `nb.yml`.** Grep callers; delete unused scaffold keys.
40. **`rails-app.tmpl` disagrees with live `rc.d/brgen`.** Generate apps from the live script or delete the tmpl so OPERATOR cannot install the wrong one.
41. **`jobs` rc.d without `set -a` — fixed 2026-09-11, and it was all three.**
    brgen_jobs, amber_jobs and bsdports_jobs each sourced their env file with
    a bare `.` and then exported `SECRET_KEY_BASE` by name, so that was the
    only key from the file the worker could read. rc.d/brgen carries the
    reason in its own comment — VAPID_PUBLIC_KEY sat in /etc/brgen.env for
    hours while push failed silently — and the app was fixed with `set -a`
    while the workers were not, which is where it matters most: WebPushJob is
    one of the classes these workers run. `test_rc_env_export` pins it, and
    holds rails-app.tmpl to the same rule.
42. **`core-reclaim.sh` RSS — fixed 2026-09-11.** Both sites read
    `ps -axo rss,args | grep "127.0.0.1:$PORT" | grep -v grep | head -1 |
    awk '{print $1}'`: three banned tools, and fragile beyond that — it matched
    an args substring across every process on the box, so the answer depended
    on which line came first, and `grep -v grep` was there because the pipeline
    matched itself. One `rss_of_port` helper now, built on `pgrep -n -f` and
    `ps -o rss= -p`. Verified on vm23 (OpenBSD 7.8) before writing: both forms
    returned 52020 KB for master, and an absent port returns empty so the
    existing `[ -n "$rss_kb" ] || exit 0` guard still fires.

    Five banned-tool uses remain in that file, all parsing `swapctl -l` and
    `sysctl -n vm.loadavg`. Four are field extraction that `set --` can do.
    The fifth is `awk '{print ($1 > $2) ? 1 : 0}'`, a float comparison, and
    OpenBSD ksh has integer arithmetic only — so that one needs a tool or a
    scaling trick, and replacing it carelessly changes when the box sheds
    memory.
43. **`STREAM_ITERATE_LOG` unsynchronized.** One flock or pid-scoped log.
44. **`sine_stream.rb` mutates ENV at load — real, and the fix changes sound.**
    Confirmed: `demo_full.rb:14` does `require_relative "sine_stream"`, so it
    is required as a library, and the file sets synthesis defaults from line
    1793 — WONKY_TOP_DIRT, WONKY_HAT_DUCK, DRUM_FIELD_MIX and their
    neighbours. They are `||=`, so an explicit environment still wins.

    Moving them behind a `$PROGRAM_NAME` guard is not a refactor: demo_full
    requires the file and currently inherits those defaults, so guarding them
    changes what it renders. Rendered-sound defaults are the operator's, and
    this one needs a listen rather than a decision from a scanner.
45. **ARGV at load — a false positive.** All three are executables: mode 755,
    `#!/usr/bin/env ruby`, and referenced only by README.md and a notebook
    that describes them. Nothing requires any of them, and kaggle_session.rb
    does not read ARGV at all. An executable reading ARGV at the top is an
    executable; the `$PROGRAM_NAME` guard exists for files that are both a
    library and a script, and these are only scripts.
46. **`postpro.log` — already ignored.** `git ls-files` tracks no log under
    postpro. Nothing to do.
47. **`MASTER/log/traces.log`, `tts.wav`, `runtime/` JSONL, `loop.gif`.** START_HERE says generated goes in `.master/` / `output/`. Gitignore or PATH_OWNERSHIP `check: none`.
48. **`snapshot_*.md` — already ignored.** `.gitignore:65` carries
    `/snapshot_*.md` and `git ls-files` tracks none of them, so the root holds
    what TREE.md says it holds. The four files are generated locally after a
    push and never committed.
49. **`PwaController` request test — added 2026-09-11.**
    `pwa_serving_test` asks for all three routes over HTTP. The content types
    were the unmeasured half and both are load-bearing in a way no template
    shows: a manifest served as text/html installs nothing, and a worker
    served as anything but JavaScript is refused with a console error no
    deploy sees. The rescue path is pinned too — a failed worker render
    answers with a minimal installing worker rather than a 500, because a 500
    leaves whatever is installed in place with no way to replace it.
50. **`AstEdit` could not write — fixed 2026-09-11.** Confirmed and repaired.
    The class includes `Io::AtomicWrite`, which defines `write_atomic`, and
    both call sites asked for `atomic_write` — the same two words reversed — so
    every rename and every insertion raised NoMethodError on the line that was
    about to change the file. It failed late: both paths validate, ask the
    governor, and take an undo snapshot first, so a caller saw the tool accept
    the work and then die, leaving an undo snapshot of a file nothing had
    touched. Nothing in the suite named AstEdit, which is why it survived;
    `test_ast_edit_writes` covers both operations and asserts that every
    `*atomic*` call in the file names a method that exists. Proved by putting
    the misspelling back: three failures, then none.

Keep the one with the test. Then delete the other.


## performance

Both 2026-09-11 performance intakes (980 items) closed on 2026-09-13: six
measured costs fixed, the rest declined as unmeasured. The rule for the next
proposal is `MASTER/DECISIONS.md` "Performance Work Starts From A Measured
Cost", and for the box `OPENBSD/DECISIONS.md` of the same date.

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
`docs/` move are refused in `MASTER/DECISIONS.md`. The `MASTER/bin/` fold lives in
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
- **`VoiceStack` plans `cutoff_scale` and nothing applies it** (`lib/devices.rb`
  plans it; the only other reader is `describe`). Wire it into
  `render_lead_voice!`'s filter or delete the field.
- **`data/modes.yml` has no reader.** The engine still walks the hardcoded
  heptatonic `SCALE_SEMITONES`/`DEGREE_TRANSITIONS` in `dilla.rb`, so the four
  qenit modes are inert and adding hicaz or hüseyni there would be too. Load the
  file into those tables first.
- **`insert_secondary_dominants` and `insert_backdoor` write one-note chords**
  (`lib/harmony_engine.rb:351,368`). `apply_voicing` returns any chord without a
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
16-bar probe. Refused proposals are recorded at the end of `live/CATALOGUE.md`,
and connecting existing devices to livesets is that file's list. In order of
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
