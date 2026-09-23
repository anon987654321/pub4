# MASTER

<!-- Two films, both rebuilt by MASTER/bin/loops.

     loop1 is the face reading this file aloud, in the voice data/voice.yml
     names, with the ai.brgen.no wordmark in the corner — recorded by
     RAILS/gates/probes/face_loop_record.rb. loop2 is a shell booting bin/cli,
     cropped to the boot message and the prompt, recorded by
     RAILS/gates/probes/shell_loop_record.rb. Its banner is read from
     Master::CLI::BootBanner at record time rather than pasted, so changing the
     banner changes the film.

     Each mp4 carries the sound and each gif is the same take without it: GIF
     has no audio track at all, which is why the pair exists rather than one
     file. The frame is the gif because GitHub's sanitizer strips <video> —
     measured 2026-08-30 — so the mp4 is what the frame links to rather than
     what it embeds: clicking either opens the take with its audio.

     An inline player with sound needs the mp4 uploaded through GitHub's web UI
     and its user-attachments URL pasted here. That upload is the operator's; a
     repo-relative <video src="loop1.mp4"> renders as nothing. -->
<a href="loop1.mp4"><img src="loop1.gif" width="360" alt="The MASTER face, reading this page aloud — click for sound"></a>
<a href="loop2.mp4"><img src="loop2.gif" width="360" alt="MASTER booting on vm23 — click for sound"></a>

**MASTER is the first artificial intelligence written in pure Ruby that governs
itself by law, not by hope — grown in Norway, to run its own mind on power drawn
from inside a fjord mountain.** Most systems let a model act first and inspect the
wreckage after. MASTER inverts it: the model only proposes, and nothing touches
disk until a written constitution approves it.

This is both the project and its business plan — the case for building it here,
with [Innovasjon Norge](https://en.innovasjonnorge.no/article/startups).

## The idea

Ninety-nine percent of AI is written in Python, chosen for its libraries rather
than its clarity. MASTER is written in pure Ruby, and that is the whole point. A
law governs a system only when a human can read both the law and the code it
judges. Ruby reads like intention, so the constitution stays legible: one
unbreakable law, the working rules under it, and executable laws that carry their
own examples and recheck themselves at every boot. Break one and you get a refusal
with a reason, never a quiet patch.

The law is not the only thing written down. Every measure that matters carries a
number recorded in the tree — the files each tree holds, the lines the runtime is
allowed, the findings its own rules produce against its own source. A number may
fall and never rise. An improvement locks the moment someone makes it, and a
regression fails the build instead of waiting to be noticed. This is the
unglamorous half of governing by law, and it is the half that makes the claim
checkable: one command prints every measure beside the number it must respect.

It runs offline, deploys to OpenBSD, and judges a codebase with no cloud behind
it, so it runs on hardware we own.

## The business, inside a mountain

The world spends more on machine intelligence than on almost anything else, and
nearly all of it burns electricity in large buildings. Global data-centre spend
runs past 250 billion dollars a year, and the binding constraint has moved from
chips to clean power. That is the opening. A sovereign AI on cheap green
electricity is the better product and the cheaper one.

The heart of it sits inside a mountain on a Norwegian fjord, the model
[Lefdal Mine](https://www.lefdalmine.com) and Green Mountain already prove.
Norway's grid is ~98% renewable hydropower, among the cheapest in Europe, and
fjord water near 8 °C cools the hall for free — power-usage effectiveness toward
1.1 against a global 1.5, a third less energy and carbon. Edge nodes in
California and Malaysia reach the American and South-East Asian markets. This is
green by geography rather than by offset, and it keeps six to ten Norwegian jobs,
the IP, and the export revenue here.

## The ask

Roughly **six million kroner from Innovasjon Norge** — Commercialisation Phase 1
near one million, a path to Phase 2 up to four, the startup loan up to two. Three
million covers the software and three to four engineers over two years. Two
million funds the fjord feasibility study and a first pilot compute pod, a few
hundred kilowatts proving the economics on real Norwegian power. One million
stands up a 3D-printing and robotics bench where the embryo takes its first body.
The full mountain datacentre is later-stage project finance in the tens of
millions of euros, the roadmap this pilot unlocks.

## The horizon

MASTER is built like an embryo: one small core of identity, memory, and safety
that takes on whatever body a mission needs. Today that body is software on green
power. The same design reaches, with enormous engineering between, toward machines
that clear orbital debris or microplastic from the sea. The saucer was never the
goal, only a distant phenotype. What we ask Norway to fund is the first rung —
the mind, and the clean ground it stands on.

## Executable constitution

`data/rules.yml` is the declarative catalogue: names, provenance, scope, severity, and compatibility metadata. `law/` is the executable constitutional layer: detectors, semantic questions, practice guidance, remedies, and worked examples that can be proved offline.

Migration is being done in batches so each rule remains reversible and auditable. Batches 1–7 have migrated the catalogue’s semantic layer into executable Law definitions covering foundational architecture, design, security, refactoring, user experience, LLM operations, and prose. Domain-specific lexical and structural detectors remain in their existing `law/ruby.rb`, `law/javascript.rb`, `law/shell.rb`, `law/css.rb`, and `law/html.rb` homes until those consumers are migrated without losing deterministic coverage.

The executable Law layer now contains 140 universal definitions plus four Rails-specific semantic definitions in `law/rails.rb`, with no duplicate `Law.define` IDs across the current law sources. The semantic implementation has been retired from YAML; the remaining catalogue fields describe rules but no longer contain their executable semantic prompts or remedies. The next stage is consolidation of the remaining deterministic and structural registry detectors under Law without losing coverage.

## Reliability kernel

MASTER treats completion and survivability as separate claims.

The constitutional core is designed to keep a truthful runtime alive when optional
services fail. `/fix` journals its run before the first pass, records each pass
durably, marks crashes explicitly, and replays an interrupted pass on the next
invocation instead of silently skipping work. Concurrent fix runs for different
targets are refused rather than sharing recovery state.

Long-running budgets use a monotonic clock, so an NTP step or manual wall-clock
change cannot extend a fix beyond its elapsed-time budget. File content still uses
the existing atomic-write and checkpoint mechanisms; the journal records
lifecycle state, not a second copy of repository contents.

The intended invariant is simple: MASTER may be **healthy**, **degraded**, or
**failed**, but an unavailable model, TTS worker, network path, or other optional
capability must never be reported as successful execution.

A `/fix` pass is transactional across its owned files: either its validated changes
are delivered as one unit, or the transaction restores the exact observed pre-pass
state. A concurrent edit is detected rather than overwritten. Successful delivery
promotes the resulting Git commit to a durable known-good runtime; `/runtime rollback`
only operates on a clean checkout and returns to that recorded commit.

Optional services are supervised with a bounded restart budget, and expensive model
work is shed when measured CPU load, RSS, file-descriptor, thread, or disk pressure
reaches critical limits. Deterministic work can therefore continue under pressure
without turning a resource emergency into a restart storm.

## Rendered convergence

Source-clean is not improvement-clean. Every `/fix` pass starts with deterministic
observation and, for `RAILS/` or `MASTER/web`, a real rendered observation. or `MASTER/web`, MASTER captures real browser surfaces through the existing
GeometryProbe/CDP gates, gives the screenshot and measured geometry to the UI
council, turns the council's selected repairs into ordinary fix-loop findings,
and renders again on the next pass. Typography, hierarchy, spacing,
alignment, density, composition and responsive behavior are therefore part of
convergence, not a final human-afterthought.

A source-clean non-web target is treated the same way conceptually: MASTER makes
one anchored Council improvement pass looking for real simplification, naming,
duplication, complexity, prose, accessibility and layout-adjacent micro-smells,
then feeds selected repairs through the ordinary RuleLoop. Unanchored taste,
speculative redesign and hallucinated defects never become automatic fixes.


The browser is evidence, not decoration: when the capture or visual council
cannot run, the pass says INCONCLUSIVE rather than claiming DONE.

## Under the hood

Wake it with one line and it comes up like an old Unix machine, telling you what
it is and what it runs on.

```console
$ cd MASTER && bin/cli

MASTER 2.8.0 (CONSTITUTIONAL) #8021: Fri Sep  4 17:39:16 CEST 2026
    mac@Mac.lan:/Users/mac/Documents/GitHub/pub4/MASTER
real mem = 8589934592 (8192MB)
avail mem = 1813561344 (1729MB)
mainbus0 at root: Mac14,2
cpu0 at mainbus0: Apple M2
kern0 at mainbus0: Darwin 25.5.0 arm64
ruby0 at mainbus0: ruby 4.0.5 arm64-darwin25
shell0 at mainbus0: zsh, user mac
soul0 at mainbus0: constitution rev 2.8.0
soul0: imports soul rules limits state patterns openbsd
soul0: 3 orders active
model0 at mainbus0: nemotron-3-super-120b-a12b
model0: openrouter, 128.0k context
mode0 at mainbus0: safe, visitor, cli
mode0: no-autofix, loop none, owner none, posture balanced
aesthetic0 at mode0: brutalist
module0 at mainbus0: boot builder cli core design fix ground io ops pub4 rails review trace voice
web0 at mainbus0: https://ai.brgen.no
pledge0 at mainbus0: unavailable
root on master0 (169570c86) boot 2652ms

master@Mac.lan ready
boot0: constitution ok, agent ok, scan active
model nemotron-3-super-120b-a12b, ctx 0/128.0k
~/Documents/GitHub/pub4/MASTER main (discover) %
```

Every change a model wants runs through one loop. It proposes an effect, the
constitution admits it, and only an admitted effect touches a file.

```ruby
def run(goal)
  @memory.note(:goal, goal)

  @max_turns.times do |turn|
    effect = @model.propose(@memory.context, verbs: @world.verbs)

    case @law.admit(effect, @memory)
    in Verdict::Block(reason:, by:)       then emit(turn, effect, refused(reason, by))
    in Verdict::Request(effect:, prompt:) then return done if (done = approve(turn, effect, prompt:))
    in Verdict::Allow(effect: admitted)   then return done if (done = apply(turn, admitted))
    end
  end
end
```

Three verdicts, only three. Block refuses with a reason. Request stops to ask a
person. Allow applies the effect against a checkpoint it undoes the moment the
effect errs. Everything past that is detail.

Read [START_HERE](START_HERE.md), then [AGENTS](AGENTS.md), which closes on what
MASTER refuses and why. Anything strange on purpose says so in a comment beside
it, and the open work lives in [one backlog](../TODO.md). Licensed MIT.
