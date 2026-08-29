# MASTER

<!-- HERO: drop the GitHub user-attachments URL for loop.mp4 in here after uploading it -->
<video src="loop.mp4" autoplay loop muted playsinline width="360"></video>

**MASTER is the first artificial intelligence written in pure Ruby that governs
itself by law, not by hope.** Most systems let a model act first and inspect the
wreckage after. MASTER inverts that: the model only proposes, and nothing touches
disk until a written constitution approves it. It thinks out loud, shows every
move, and answers to a rulebook it can read but never rewrite.

It grows like an embryo — one small, self-checking core that takes on whatever
body a mission needs. Today that body is a Rails process and a terminal you talk
to in plain sentences. The aim is larger: an operating system for intelligence
itself.

⚖️ &nbsp; 🤖 &nbsp; 🛰️ &nbsp; 🌍 &nbsp; 🛡️

### ⚖️ Law before every write

MASTER keeps thinking and deciding apart. A model — Claude, or one of several it
swaps between — proposes a change. Before that change becomes a file, it must
clear the constitution: one unbreakable law, a set of working rules, and
executable laws that carry their own right-and-wrong examples and recheck
themselves at every boot. Break the constitution and you get a refusal with a
reason, never a quiet patch behind your back.

##### 🔁 The loop

You hand MASTER a sentence. It scans, fixes, criticizes, and reviews, circling
until nothing new turns up. The scan is not a model guessing; it is exact checks
that read a file's shape against named principles — an idea written twice, a
class that only forwards, a name that says nothing, a step too long to hold in
the head. No model required, so it judges a whole codebase offline, and holds
every other assistant to the same law.

🌙 &nbsp; 💭 &nbsp; ✨ &nbsp; 🔮

### 🏛️ The council

When a change deserves more than a checklist, MASTER convenes a panel: an
architect, a caretaker, a performance mind, an ethicist, a designer. Each reasons
through its own lens, each can run on a different model, and each argues *against*
the change before a judge weighs what survives. It is a debate, not a vote, and
the best idea usually arrives long after the eighth.

#### 🔊 Voice, out loud

MASTER speaks warm but short, the flattery and throat-clearing stripped before
you hear a word. It shows its work like an old Unix machine booting — every file,
every step, every reason in plain view. And it is never without a way to think:
an account if it has one, a signed-in browser if not, a model on the machine
itself when the network goes dark.

###### 🌙 It dreams, and it makes things

When the tree goes quiet, MASTER dreams. It reads one of its rules, searches the
world for how that rule is best understood, ties it to the code that should
follow it, and — down a sealed, gated path — fixes one. And it *makes*. Ask in
plain words for a photograph of Bergen in the rain, a [J Dilla
beat](../STUDIO/dilla), or a graded film look, and it routes you to [the studio
tools](../STUDIO) beside it. The beats here are real: a flipped record under
fresh FM drums, an arpeggio locked to the chord scale, drawn from a hundred and
ninety real [progressions](https://github.com/ldrolez/free-midi-chords).

### 🧬 The bigger picture — an embryo, not an app

This part sounds like science fiction until you read the code. MASTER is not
trying to be a better coding agent. It is a **persistent intelligence whose body
is replaceable.** Its identity, memory, world model, mission, and safety policy
live in the core. A *body* is an interchangeable way to act in an environment — a
browser, a Rails app, a GitHub account today; a rover, a drone, an underwater
vehicle tomorrow; an orbital tug clearing debris after that.

It reasons in capabilities, not gadgets — observe, navigate, move, grasp,
communicate, inspect, repair — and every body implements them differently. The
same order, move, nudges a cursor in one body and fires a thruster in another,
and the mind above never cares which. Nothing is built on a whim: physical bodies
sit behind hard authorization, resource, and safety walls, simulated and
validated long before anything is made.

The ladder runs from digital embryo, to software agent, to simulated agent, to a
first physical prototype, to a specialized worker, to orbital systems, to
coordinated fleets — and the early rungs are all software you can write today.
The flying saucer was never the goal; it is one phenotype of the embryo among
many. Today a Rails process. Tomorrow a robot. Eventually, with vast engineering
and validation in between, a spacecraft.

🚀 &nbsp; ⚡ &nbsp; 🌟 &nbsp; 💫 &nbsp; 🛸

#### 🧭 Running it

Install the dependencies and start [MASTER](bin/master). The operator commands
sit beside it; the deploy notes are in [the OpenBSD folder](../OPENBSD). Read
[START_HERE](START_HERE.md), then [AGENTS](AGENTS.md), to work inside it;
[DECISIONS](DECISIONS.md) explains anything that looks strange on purpose; and
everything left to do lives in [one backlog](../TODO.md). Licensed MIT.

###### 🔬 Under the hood

You reach the box and wake it with one line, and it comes up like an old Unix
machine — telling you what it is, what it runs on, and how much of itself it
sees.

```console
$ ssh dev@brgen.no
$ cd MASTER && bundle exec ruby bin/master
<master> /status
mode      safe · full · cli · no-autofix   owner=none   posture=balanced
service   master/ok   master(ok)
git       main   clean
fix       bg=stopped   autofix=off
bundle    ok (MASTER+web satisfied)
code      index built · 872 files · 8239 symbols
```

The heart behind that prompt is smaller than it looks. Every change a model wants
runs through one loop: it proposes an effect, the constitution admits it, and
only an allowed effect touches a file.

```ruby
def run(goal)
  @memory.note(:goal, goal)

  @max_turns.times do |turn|
    effect = @model.propose(@memory.context, verbs: @world.verbs)

    case @law.admit(effect, @memory)
    in Verdict::Block(reason:, by:)
      emit(turn, effect, Observation.no("refused by #{by}: #{reason}"))
    in Verdict::Request(effect:, prompt:, reason:, by:)
      return done if (done = approve(turn, effect, prompt:, reason:, by:))
    in Verdict::Allow(effect: admitted)
      return done if (done = apply(turn, admitted))
    end
  end
end
```

Three verdicts, only three. A Block refuses with a reason, never a quiet patch. A
Request stops the loop to ask a person. An Allow applies the effect against a
checkpoint it can undo the moment the effect errs. Propose, judge, allow or
refuse — everything past that is detail.
