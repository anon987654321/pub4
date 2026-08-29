# MASTER ⚡

**MASTER is the first artificial intelligence built in pure Ruby that governs
itself by law — not by hope, not by vibes, not by a prayer that the model
behaves.** Most systems let an AI act first and inspect the wreckage after.
MASTER flips the whole thing on its head: the model only ever *proposes*, and
nothing touches disk until a written constitution signs off. It thinks out loud,
shows every move, and answers to a rulebook it can read but can't rewrite on a
whim.

It's built like an embryo — one small, self-checking core that grows into
whatever body a mission needs. Today that body is a Rails process and a terminal
you talk to in plain sentences. The aim is bigger: an operating system for
intelligence itself.

<!-- HERO: drop the GitHub user-attachments URL for loop.mp4 in here after uploading it -->
<video src="loop.mp4" autoplay loop muted playsinline width="360"></video>

⚖️ &nbsp; 🤖 &nbsp; 🛰️ &nbsp; 🌍 &nbsp; 🛡️

### ⚖️ Law before every write

MASTER keeps thinking and deciding apart. A model — Claude, or one of several it
swaps between — proposes a change. Before that change becomes a file it has to
clear the constitution: one unbreakable law, a set of working rules, and
executable laws that carry their own right-and-wrong examples and re-check
themselves every time the thing boots. Break the constitution and you get a
refusal with a reason. Never a quiet little patch behind your back.

##### 🔁 The loop

You hand MASTER a sentence. It scans, fixes, criticizes, and reviews, circling
until nothing new turns up. The scan isn't a model guessing — it's exact checks
that read a file's shape and measure it against named principles: an idea written
twice, a class that only forwards, a name that says nothing, a step too long to
hold in your head. No model required, so it judges a whole codebase offline, and
holds every other AI assistant to the same law.

🌙 &nbsp; 💭 &nbsp; ✨ &nbsp; 🔮

### 🏛️ The council

When a change deserves more than a checklist, MASTER pulls up a panel: an
architect, a caretaker, a performance head, an ethicist, a designer. Each one
reasons through its own lens, each can run on a different model, and each argues
*against* the change before a judge weighs what's left standing. It's a debate,
not a vote — and the best idea usually shows up long after the eighth.

#### 🔊 Voice, out loud

MASTER talks warm but short, the flattery and throat-clearing stripped before you
hear a word. It shows its work like an old Unix box booting — every file, every
step, every reason scrolling past in plain view. And it's never left without a
way to think: an account if it has one, a signed-in browser if it doesn't, a
model running on the machine itself when the network's gone dark.

###### 🌙 It dreams, and it makes things

When the tree goes quiet, MASTER dreams. It reads one of its own rules, searches
the world for how that rule is best understood, ties it back to the code that
should follow it, and — down a sealed, gated path — fixes one thing. And it
*makes*. Ask in plain words for a photograph of Bergen in the rain, a [J Dilla
beat](../STUDIO/dilla), or a graded film look, and it routes you to [the studio
tools](../STUDIO) sitting right beside it. The beats in this repo are real: a
flipped record under fresh FM drums, an arpeggio locked to the chord scale,
played from a library of a hundred and ninety real
[progressions](https://github.com/ldrolez/free-midi-chords).

### 🧬 The bigger picture — an embryo, not an app

Here's the part that sounds like science fiction until you read the code. MASTER
isn't trying to be a better coding agent. It's a **persistent intelligence whose
body is replaceable.** Its identity, memory, world model, mission, and safety
policy live in the core. A *body* is an interchangeable way to act in some
environment — a browser, a Rails app, a GitHub account today; a rover, a drone,
an underwater vehicle tomorrow; an orbital tug clearing debris the day after
that.

It reasons in capabilities, not gadgets — observe, navigate, move, grasp,
communicate, inspect, repair — and every body implements those in its own way.
So the same order — move — nudges a cursor in one body and fires a thruster in
another, and the mind above never has to care which. Nothing gets manufactured on a whim: physical bodies sit
behind hard authorization, resource, and safety walls, simulated and validated
long before anything is ever built.

The ladder runs from digital embryo, to software agent, to simulated agent, to a
first physical prototype, to a specialized worker, to orbital systems, to
coordinated fleets — and the early rungs are all software you can write today.
The flying saucer was never the goal. It's just one possible phenotype of the
embryo. Today a Rails process. Tomorrow a robot. Eventually, with an enormous
amount of engineering and validation in between, maybe a spacecraft.

🚀 &nbsp; ⚡ &nbsp; 🌟 &nbsp; 💫 &nbsp; 🛸

#### 🧭 Running it

Install the dependencies and start [the master command](bin/master). The
operator commands sit beside it, and the deploy notes are in [the OpenBSD
folder](../OPENBSD). Read [START_HERE](START_HERE.md), then [AGENTS](AGENTS.md),
to work inside it; [DECISIONS](DECISIONS.md) explains anything that looks strange
on purpose; and everything still on the table lives in [one backlog](../TODO.md)
at the top of the repo. Licensed MIT.

###### 🔬 Under the hood

You reach the box and wake it with one line, and it comes up the way an old Unix
machine does — telling you what it is, what it runs on, and how much of itself it
can see.

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
runs through one loop — it proposes an effect, the constitution admits it, and
only an allowed effect ever touches a file:

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

Three verdicts, only three. A Block is a refusal with a reason, never a quiet
patch. A Request stops the loop to ask a person. An Allow applies the effect
against a checkpoint it can undo the second the effect errs. Propose, judge,
allow or refuse — everything past that is detail.
