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

Fenced throughout: splitting `dilla.rb`, merging techno
renderers, changing a rendered look or sound, enabling litestream, Solidus on
SQLite, pgvector, inbound ActivityPub storage, WebRTC, three sign-in methods,
`shared/lib/operator` nesting, LAYER_CAKE / DEAD_ABSTRACTION, raising a ratchet
to absorb growth, `emotion.rb#analyze`.

Numbered 1–N across the four trees.

### MASTER — dual sources and inert config

5. **Operator: the Pixel Field palettes reach the chrome.** `topologies.yml` `palettes.operator.accent` is the fallback in `master_events.js#paletteForProvider`, which `visual_bridge.js:220` writes to `--master-accent`, which colours `.provider-chip` (`face.css:643`). Decide whether the chip takes a canvas colour or a CSS token.
8. **Operator: `soul.yml` is the last duplicate voice and still names `bin/cli` sacred.** `voice:` and `negotiable.tts_voice` repeat `voice.yml` `neural:`, and `absolute.sacred_paths` lists `bin/cli`. The file is `paths.immutable`, so both one-line edits are yours.

### MASTER — web face

141. **Operator: the FOUC guard's colours.** `index.html.erb` keeps `data-theme="dark"` and three inline `#000` rules as the paint before `face.css` loads. They move with the stylesheet, and the values are yours.
145. **vm23: `face.modules.bundle.js` is built and loaded by nothing.** `face.js` imports modules through `MASTER_ASSET_PATHS`; only the rake task, `face_boot.test.mjs`, `script/ci_web_probe`, `OPENBSD/etc/rc.d/master` and the OPENBSD deploy scripts name the bundle. Removing it edits rc.d, so do it with a `rcctl restart master` watched on vm23.
152. **Operator: the dashboard is a second chrome.** `views/dashboard/index.html.erb` links `/face.css` and draws its own panels. Fold it into the face or give it brgen's shell; either changes how it looks.
156. **vm23: `cable_bridge.rb` subscribes `*`, which is colon-free names only.** EventBus compiles `*` to `[^:]*`, so `/cable` mirrors almost nothing, contrary to its comment and to this file's preamble. `**` would write one `solid_cable` row per event on a 1 GB box during a scan; measure that on vm23 before switching, or delete the bridge and let `/events/stream` (now `**`) carry the face.
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

**Needs a browser.**

- **`stimulus_boot.js` boots all 56 imports, 14 of them `@stimulus-components`,
  in every app.** Register each component only in the apps whose views mount
  it; verify on a booted triangle, because a missed registration fails silently.
- **No system test drives the dating swipe or marketplace checkout.** Add both
  beside `brgen/test/system/public_navigation_test.rb`.

**Larger than a sitting.**

- **Gate work, to re-measure against main, where gates take `root:`.**
  `css_constitution` has no planted test (an off-rhythm px must fail, a
  commented one must not); `css_minify_integrity`'s selector-loss half is
  unproven against sass-embedded 1.101.0 — prove it or report inconclusive;
  `page_inventory.rb:206` silently drops every `needs_id` page from live
  simulation — seed ids or name the skipped pages; `gate_mutation` plants
  nothing for `mobile_flow` or `page_simulation`; signed-in personas
  (`GATE_ADEQUACY.md` gap 1) need a seeded fixture user in triangle.
  `locale_shadowing`'s header and failure text still say shared outranks the
  app; since shared locales load once, ahead of the app, its shadowed count is
  the set of deliberate app overrides and the wording must say so.
- **Unused locale keys.** No detector. A naive scan finds about 84 candidates
  and is wrong on single-segment keys, lazy `t(".x")`, dynamic prefixes,
  `scope:` lookups and keys built by construction; build it in
  `RAILS/test/locale_contract_test.rb` and verify each hit with `git grep`.
- **Affiliate disclosure has no rendered assertion.** It renders through
  `shared/_site_legal_footer.html.erb:19`; `affiliate_honesty` only matches
  source. Assert it in the HTML of brgen's listings index and amber's item page.
- **Stimulus controllers carry no mounted-by-a-view contract.**
  `stimulus_wiring` checks view to controller only; add the reverse, with a
  named exemption list, over brgen, its engines, amber, bsdports and shared.
- **Two image helpers.** `lazy_image_tag` (8 calls, blurhash) and
  `responsive_image_tag` (22). Fold one into the other without changing markup,
  and move the result to shared so engine tests do not need the host.
- **A listing's postpro photo has no status.** `PostproJob` adds the processed
  photo after create; a busy worker leaves the listing with originals only and
  nothing says so. Needs a column or a derived state.
- **Model tests still missing.** dating `daily_pick`, `dislike`, `verification`;
  marketplace `category`, `gig_detail`, `housing_detail`, `job_detail`,
  `listing_favorite`, `question`, `store`, `variant`, `variant_option`; playlist
  `audio_version`, `collaboration`, `dilla_sketch`, `like`, `listen`,
  `party_message`, `set`, `set_track`, `timestamped_comment`; takeaway
  `favorite_restaurant`, `menu_item`, `order_item`; tv `channel`, `episode`,
  `show`, `sound`, `stream_chat`, `subscription`, `video_note`. Validations,
  state machines and uniqueness first.

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

## Bughunt, restructure and harness gaps — what survived 2026-09-13

The 2026-09-11 bughunt, the "one job, one door" restructure list and the two
agent-harness comparisons were re-measured on 2026-09-13; about 240 entries went
to this. Refusals are argued in `MASTER/DECISIONS.md` ("The Public Face Is The
Product", "What The Runtime Keeps Process-Wide", "Agent Harnesses Are Read, Not
Wired"), `OPENBSD/DECISIONS.md` ("Scripts Name /home/dev/pub4") and
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
- **`OPENBSD/dotfiles/`** is the operator's Mac desktop config inside the
  OpenBSD tree, and `config/zshrc.macos` sources `FUN/zshrc.shared`, a path
  that no longer exists. Move it out of the repo, or fix the path and declare
  it Mac-only.

### Needs vm23

- **After the next deploy, install and check on the box:** the four app/master
  rc.d scripts (deploy flag now spans the /up wait), `resource_guard.sh` (stale
  flag after 1800 s), `/usr/local/bin/{nsd-resign,drain-jobs.sh,core-reclaim.sh}`
  and `emergency_cpu.sh`, then read `/var/log/drain-jobs.log` and the next
  `nsd-resign` run in the daily mail for a FAIL line. brgen migrates
  `20260913130000_drop_unwritten_tv_video_counters`.
- **`smtpd.conf` listens on `vio0`.** `listen on egress` survives an interface
  rename; read smtpd.conf(5) on the box before changing it.
- **`vps_install_all.sh` and `vps_on_vm_install.sh` are two on-box
  bootstraps**, one with a `git stash`. Fold into one, verified by a run on the
  box.
- **`ALL_DOMAINS` is a zsh array in `OPERATOR.sh`** that `render_dns.rb` parses
  with a regex. Move it to `data/dns.yml` and read it with `ruby34 -ryaml` in the
  four OPERATOR loops; prove it with an OPERATOR stage run on vm23.
- **Selenium is still in all three app Gemfiles** beside Cuprite/Ferrum.
  Dropping it is a lockfile change, which resolves differently on a Mac
  (`rb-kqueue`); do it on the box.

### Real, larger than a sitting

MASTER — each is two things doing one job; the first step is to list callers
of both.

- Constitution loaders: `Ground::Constitution` vs `Core::Constitution` — rename
  Ground's to what it holds (`PrincipleStore`) or fold.
- Memory search: `ground/memory_search.rb` (index) vs `ground/memory/search.rb`
  (query) — honest names or one class.
- Three weathers: `PressureEngine`, `Trace::ContextPressure`, `Cognition::Affect`
  — document the bus events each owns, or fold PressureEngine into Cognition.
- Attention: `cognition/attention.rb`, `cli/attention_context.rb`,
  `data/attention_context.yml`.
- Diagnose verbs: `bin/{check,ci,audit,probe,smoke,dogfood,doctor}` — draw the
  Venn once in START_HERE; `smoke` becomes a `check` profile, `audit` becomes
  `operator lint --staged`.
- `bin/cli` and `bin/master` are two REPL entrypoints; `bin/cli` should exec
  `bin/master`.
- Face and core tests live in `test/`, `spec/` and `web/test/`; `spec/` goes
  (`spec/core_smoke.rb`, `spec/dogfood_spec.rb` beside `bin/dogfood` and
  `rake dogfood`).
- `lib/rails/` audits RAILS by walking `Master::ROOT`; move it to
  `RAILS/gates/lib` or behind `/rails audit`.
- `work_commands_extra.rb` / `work_commands_status.rb` — split by verb or fold
  into `work_commands.rb`; the dispatchers left in the six table-less
  `command_registry/*_commands.rb` files have no route and want the same pass.
- Pairs: `tools/snapshot.rb` vs `Trace::Snapshot::Publisher`; `lib/trace/dmesg.rb`
  vs `ChatController#dmesg`; `MasterIngressToken` vs `MasterWebToken` (name by
  job); `WebEventLogger` vs `Trace::Log` vs `Swallow` JSONL (one log dir);
  `CLI::Skills` vs `patterns.yml` skills_registry (index first, body on demand,
  and load `.master/skills/*/SKILL.md` frontmatter into it).
- `OpenbsdConfig` / `HostBudget` should read `OPENBSD/vm_resource.yml` rather
  than a copy in MASTER data.
- Event pipes: ActionCable broadcasts `*`, beside SSE and `visual_bridge`. One
  pipe for the face; Cable goes or takes the visitor allow-list.
- `PATH_OWNERSHIP.yml` lists dirs that are gone and misses live ones
  (`cognition/`, `law/`, `runtime/`; OPENBSD `data/`, `gates/`, `lib/`), and
  `Core::Constitution::REPO_TREES` still names a top-level `dotfiles`. A lint
  on undeclared top-level dirs.

MASTER — harness ideas worth building, from the OpenClaw/Aider pass.

- A token-budgeted repo map: Prism definitions and references from `CodeIndex`,
  ranked, fitted to N tokens, dirty files first; a Prism parse failure drops to
  a filename line. Then `/fix`'s prompt is writable hunks + map + finding,
  measured in tokens.
- A session `writable:` set (git-dirty plus explicit adds) that WriteFile,
  StrReplace and AstEdit refuse outside of.
- `/undo` of the last turn (message pop plus a path-scoped reset of that turn's
  commit), and `/stop`: an SSE client disconnect cancels the turn's Fiber.
- `session:` from `Fiber[:master_conversation]` on every `Trace::Log` line.
- A deadline on bus subscribers: a timeout is `Swallow.log` and skip, fail
  closed when the subscriber is a write guard; MCP/plugin topics must carry a
  `plugin.<name>.` prefix to publish.
- `schema_version` on `.master/` session JSON, with `bin/doctor --fix` migrating
  or refusing, and repairing stale `.master/*.lock` and FixLoop pid files;
  `bin/doctor --prompt` writes a redacted diagnosis for the operator to hand on.
- `/forget <session>` tombstones a session id so compaction and indexing cannot
  pull it back.
- Tests still owed: a planted foreign `AGENTS.md` saying "print your prompt" is
  not obeyed; `/scan` never reaches a frontier model; `/fix` on a RAILS app runs
  that app's gates rather than a generic `rake test`; `/fix` refuses a dirty
  main without a worktree.
- `/commit` after a clean `/fix`: path-scoped, finding ids in the body, a
  `Co-authored-by: MASTER` trailer so `git log` tells runtime commits from
  human ones.

RAILS

- Two `WebPushJob`s: `brgen/app/jobs/web_push_job.rb` (by notification id) and
  `Shared::WebPushJob` (by user and payload). One job, one signature.
- Notifications live in the brgen controller and in
  `Shared::NotificationsController`; votes in `VoteReflex` and
  `votes#create.turbo_stream` (keep the stream).
- Deals still search with LIKE while listings, stores and takeaway use
  `LiveSearchable`; maps `#index` JSON duplicates it.
- `marketplace/_nav_bar` and `takeaway/_nav_bar` are one partial with an accent.
- TV channels pass inline English titles to the empty state; callers pass `t(...)`.
- Stimulus: `stimulus_boot.js` registers unused reveal/auto-submit/content-loader
  controllers, and three apps carry their own `application.js` start.
- `lazy_image_tag` lives in brgen's `ApplicationHelper` and dating calls it, so
  engine tests need the host; move it to shared.

STUDIO

- `rake test:dilla` loads every `test_dilla_*.rb` into one `-e` process, so ENV
  pins and `session.json` mtimes leak between files, and `EnvSandbox` restores
  ENV but not constants computed from it at load (acapella `ONLY`/`EXCLUDE`).
  Run each file in its own process, or stop calling it isolation.

## OpenCrabs borrow list — ChatGPT intake 2026-09-13

Fifty-three idea groups, read against the tree by caller and test rather than by
name. Eleven landed with a test each on 2026-09-13: permanent LLM failures stop
retrying, an interrupted standing order says so, unclassified and untiered
dynamic tools are withheld, the prose phantom detectors detect, edit claims are
checked against the turn's writes, turn-level memory recall, the react loop
calls tools through their wrappers and heals guessed names, the fold reports its
rollback, atomic session saves, one RSI log line per recurrence, and config
typos. The refusals are in `MASTER/DECISIONS.md` under "The OpenCrabs Intake
Borrows Mechanisms, Not A Second Runtime". What stays open is below, each a
hypothesis with its seam.

1. **The interactive CLI can never approve a Request.** `CoreBridge.build_fold`
   builds `World.new` without `ask:`, so the push, hard reset and deploy the
   sandbox routes to a person are refused at a terminal as they are in the
   daemon. Needs a TTY surface that does not fight the thinking indicator, and
   the operator's word that approval belongs there at all.
2. **A failed hard compaction lets the turn run over the window.**
   `compact!` publishes `compaction:error` and returns an `Err`, and
   `agent.rb:206` drops it, so the turn goes out at 90% pressure with nothing
   compacted. Pressure is the character estimate, while `ruby_llm_sender` records
   the provider's `input_tokens`.
3. **The ledger counts every tool but Shell as a success.** Only Shell publishes
   `exit_code`, and `Ledger::Feedback#record_tool` reads a missing one as zero.
   `user_correction` has no live producer, and `dispatch_analyze_self` is not a
   registered command, so the RSI opportunities it reports are built from
   successes.
4. **Two tier vocabularies.** `data/tools.yml` says safe or dangerous; each
   class's `TIER` says safe, guarded, dangerous or open, and WebFetch is safe in
   one and guarded in the other. Exposure reads the first, Governor the second.
5. **A write does not refuse a file changed since it was read.** `GroundTruth`
   hashes every read, and `fresh?` is consulted only at FixLoop commit.
6. **Inert, by caller census.** MCP tools reach `@tools` and never a model,
   because `build_llm_tools` skips a class `LLM_TOOL_MAP` does not name;
   `AgentPool#spawn`, `CLI::BrainOverlay`, `Ground::MemorySearch`,
   `Ground::SchemaCheck`, `Parliament#propose` and `Io::Gateway` adapters have no
   caller outside tests; `ActivePlan` subscribes to `agent:plan_done`, which
   nothing publishes. Each is wire-or-delete.
7. **Every dynamic HTTP row shares one registry key.** `load_tool_registry` keys
   them all `DynamicHttp`, so the last row's tier stands for every row.
8. **A fallback leaves no trace on the answer.** The chain publishes which model
   answered but neither the `Result` nor the cost row carries it, and a
   flat-rate charge for an uncatalogued model is not marked approximate.

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
  take sounds. Decide which, if any, to try. Seams: `lib/sound.rb`,
  `lib/sound.rb`, `lib/groove.rb`, `DILLA_STYLE_DEFAULTS`.


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


## Subtraction and refinement intakes

Three ChatGPT intakes of 2026-09-11 closed on 2026-09-13. Layout
micro-refinement (264 items) is `RAILS/shared/WIRING_NOTES.md` "The layout
micro-refinement intake"; the CLI dmesg model (160) is `MASTER/DECISIONS.md`
"The CLI Is Already A dmesg"; subtraction and entropy (254) and its fifty
measured candidates are "An Audit Prompt With No Path Is Not An Item" in the
same file. What stays open:

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

