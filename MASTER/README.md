# MASTER ⚡

**MASTER is the first artificial intelligence built in pure Ruby that governs
itself by law, not by hope.** Most systems let an AI act first and
inspect the damage after. MASTER inverts it: the model may only propose, and
nothing is saved until a written constitution has approved it.

It is built like an embryo — a small, self-checking core, grown over time into
machines that build their own parts, clear the debris orbiting the Earth, and
keep the people it serves safe. For now it is a program you talk
to in plain sentences; its aim is the operating system for intelligence itself.

⚖️ 🤖 🛰️ 🌍 🛡️ ✨ 🔥

## ⚖️ Law before every write

MASTER keeps thinking and deciding apart. A model — Claude, or one of several it
swaps between — proposes a change. Before it becomes a file, it must pass the
constitution: an unbreakable law, a set of working rules, and executable laws
that carry their own right and wrong examples and re-check themselves at every
boot. What breaks the constitution is refused with a reason, never quietly
patched.

## 🔁 The loop

You give MASTER a sentence, and it scans, fixes, criticizes, and reviews,
circling until nothing new turns up. The scan is not a model guessing; it is
exact checks that read a file's shape and measure it against named principles —
an idea written twice, a class that only forwards, a name that says nothing, a
step too long to hold in the head. They need no model, so MASTER judges a whole
codebase offline, and holds any other AI assistant to the same law.

## 🏛️ The council

When a change deserves more than a checklist, MASTER convenes a panel: an
architect, a caretaker, a performance mind, an ethicist, a designer. Each
reasons through its own lens, each can run on a different model, and each argues
against the change before a judge weighs what survives. It is a debate, not a
vote, and the best idea usually arrives long after the eighth.

🌙 💭 ✨ 🔮 🎨 🎵 📷 🎬

## 🔊 Voice and transparency

MASTER speaks warmly but briefly, the flattery and throat-clearing stripped
before you hear a word. It shows its work like an old Unix machine's boot log:
every file, every step, every reason scrolls past in plain view. And it is never
left without a way to think — an account if it has one, a signed-in browser if
not, a model on the machine itself when the network is gone.

## 🌙 Dreaming and making

When the tree falls quiet, MASTER dreams — it reads one of its rules,
searches the world for how that rule is best understood, connects it to the code
that should follow it, and along a sealed, gated path, fixes one. And it makes things. Ask
in plain words for a photograph of Bergen in the rain, a
J Dilla beat, or a graded film look, and it routes the request to the studio
tools beside it.

## 🧭 Running it

Install the dependencies and start `bin/master`; the operator commands live
under `bin/pub4`; the deploy notes are in the OpenBSD folder. Read START_HERE,
then AGENTS, to work inside it; DECISIONS explains anything surprising; and
everything still to do lives in one backlog at the top of the repository.
Licensed MIT.

🚀 ⚡ 🌟 💫

## 🔬 Under the hood

You reach the box and wake it with one line, and it comes up the way an old Unix
machine does — announcing what it is, what it runs on, and how much of itself it
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

The heart behind that prompt is smaller than it looks. Every change a model
wants runs through one loop — it proposes an effect, the constitution admits it,
and only an allowed effect ever touches a file:

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

Three verdicts, and only three. A Block is a refusal with a reason, never a
quiet patch. A Request stops the loop to ask a person. An Allow applies the
effect against a checkpoint it can undo the moment the effect errs. Propose,
judge, allow or refuse — everything past that is detail.
