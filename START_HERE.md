# pub4 — start here

One screen. Everything else is reference, reached from this page.

## The four trees

| | what it is | entry point |
|---|---|---|
| `MASTER/` | A constitutional AI runtime in pure Ruby. The primary product. | `bin/master "<instruction>"` |
| `RAILS/` | Three Rails 8 apps: **brgen** (a city social network; its verticals are mounted engines), **amber** (wardrobe), **bsdports**. | `RAILS/bin/triangle up` |
| `OPENBSD/` | The deploy pipeline and the VPS runbook. Production is one box, `vm23`. | `bin/pub4 vps state` |
| `STUDIO/` | Media tools. **dilla** makes beats, **postpro** grades images, **repligen**/**lora** generate. | `ruby STUDIO/dilla/dilla.rb` |

## The commands you actually need

```zsh
bin/pub4 status                 # what is dirty, per tree
bin/pub4 test                   # the suites
bin/pub4 measure                # every ratchet, current vs ceiling
bin/pub4 snapshot               # regenerate the codebase packs
bin/pub4 worktree <name>        # your own checkout — see the first trap
bin/pub4 vps state | deploy     # the box

cd MASTER && bin/check          # ordinary MASTER work
ruby RAILS/gates/runner.rb --all   # every RAILS gate
```

Run the smallest check that proves the work, and do not report done without
its output.

## Five traps, in the order they will bite you

1. **The checkout is shared.** Several agents edit this tree at once. `git commit -a`
   sweeps up someone else's half-finished work, and `git push` publishes every
   commit beneath yours, not just your own. Take `bin/pub4 worktree <name>`, or at
   minimum commit path-scoped: `git commit -- <paths>` with no prior `git add`.
2. **Strict loading is on in every environment.** Reading a lazy association off a
   record fetched by id raises — in test and production both. Associations carrying
   a `:destroy` cascade are exempt (see `Shared::CascadingAssociationsLoad`), which
   is easy to get backwards in either direction. Check before you claim a 500.
3. **A deploy sheds amber and bsdports**, and relayd keeps answering TLS with their
   ports closed — so the outage looks like a hang, not a 5xx. `vps-deploy` restores
   them now; if you are deploying by hand, check ports 61352 and 47312.
4. **The apps default to Norwegian.** Tests assert through I18n keys, never English
   literals, and a hardcoded English string is a defect rather than a placeholder.
5. **Renders are irreplaceable.** dilla and postpro write real output with rotating
   seeds. Never render over a take that matters, and never change a
   rendered-sound or graded-look default on your own judgement.

## Two habits this repo learned the hard way

**Verify the instrument before the finding.** Naive pattern-matching over this
tree produces mostly false positives — five candidate findings died on
verification in a single week, and one report had to be retracted after the test
written to prove it passed with the fix reverted. Before calling config inert,
find the reader. Before calling code wrong, check what your scan actually
measured.

**A comment states the present-tense reason.** Not what the code used to do —
that is what `git log`, `DECISIONS.md` and `DEBT.md` are for.

## Where the rest lives

| Working on | Read |
|---|---|
| Anything in MASTER | `MASTER/START_HERE.md`, then `MASTER/AGENTS.md` |
| The web face, WebGL, TTS | `MASTER/web/CLAUDE.md` |
| Deploy, the VPS, rc.d, relayd | `OPENBSD/CLAUDE.md`, then `OPENBSD/RUNBOOK.md` |
| RAILS CSS or visual work | `RAILS/shared/WIRING_NOTES.md`, then `RAILS/shared/LAYOUT.md` |
| brgen's city hosts and verticals | `RAILS/brgen/AGENTS.md` |
| Why something odd is deliberate | `MASTER/DECISIONS.md`, `OPENBSD/DECISIONS.md` |
| Known debt, and what not to chase | `MASTER/DEBT.md`, `OPENBSD/data/debt.yml` |
| What changed recently | `CHANGELOG.md` |

Authority order is `MASTER/data/soul.yml` > `MASTER/data/rules.yml` > `CLAUDE.md`
> the per-tree `CLAUDE.md`. Feature truth is `RAILS/apps.yml`.
