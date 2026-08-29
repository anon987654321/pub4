# MASTER

<!-- HERO: GitHub embeds video only from a user-attachments URL, never a relative
     path. Drag MASTER/loop.mp4 into any issue/PR comment, then paste the resulting
     https://github.com/user-attachments/assets/… URL into the src below. -->
<video src="https://github.com/user-attachments/assets/REPLACE-WITH-UPLOADED-loop.mp4" autoplay loop muted playsinline width="360"></video>

**MASTER is the first artificial intelligence written in pure Ruby that governs
itself by law, not by hope — grown in Norway, to run its own mind on power drawn
from inside a fjord mountain.** Most systems let a model act first and inspect
the wreckage after. MASTER inverts it: the model only proposes, and nothing
touches disk until a written constitution approves it.

This is both the project and its business plan — the case for building it here,
with [Innovasjon Norge](https://en.innovasjonnorge.no/article/startups).

⚖️ &nbsp; 🤖 &nbsp; 🌍 &nbsp; ⚡ &nbsp; 🛡️

### 💎 The idea

Ninety-nine percent of AI is written in Python, chosen for its libraries, not its
clarity. MASTER is written in pure Ruby — and that is the whole point. You cannot
govern a system by law if no human can read the law or the code it judges. Ruby
reads like intention, so the constitution is legible: an unbreakable law, working
rules, and executable laws that carry their own examples and recheck themselves
at every boot. Break it and you get a refusal with a reason, never a quiet patch.

It runs offline, deploys to OpenBSD, and needs no cloud to judge a codebase — so
it can run on hardware we own.

### 🏔️ The business

The world spends more on machine intelligence than on almost anything else, and
nearly all of it burns electricity in large buildings. Global data-centre spend
runs past 250 billion dollars a year, and the binding constraint is no longer
chips — it is clean power. That is the opening: a sovereign AI on cheap green
electricity is the better product *and* the cheaper one.

The heart of it sits inside a mountain on a Norwegian fjord — the model
[Lefdal Mine](https://www.lefdalmine.com) and Green Mountain already prove.
Norway's grid is ~98% renewable hydropower, among the cheapest in Europe, and
fjord water near 8 °C cools the hall for free — power-usage effectiveness toward
1.1 against a global 1.5, a third less energy and carbon. Edge nodes in
California and Malaysia reach the American and South-East Asian markets. Green by
geography, not by offset — and six to ten Norwegian jobs, IP, and export revenue
that stay here.

### 💰 The ask

Roughly **six million kroner from Innovasjon Norge** — Commercialisation Phase 1
near one million, a path to Phase 2 up to four, the startup loan up to two. About
three million covers the software and three to four engineers over two years; two
million funds the fjord feasibility study and a first pilot compute pod, a few
hundred kilowatts proving the economics on real Norwegian power; one million
stands up a 3D-printing and robotics bench where the embryo takes its first body.
The full mountain datacentre is later-stage project finance in the tens of
millions of euros — the roadmap the pilot unlocks.

🚀 &nbsp; ⚡ &nbsp; 🌟 &nbsp; 🏔️

### 🧬 The horizon

MASTER is built like an embryo — one small core of identity, memory, and safety
that takes on whatever body a mission needs. Today that body is software on green
power; the same design reaches, with enormous engineering between, toward
machines that clear orbital debris or microplastic from the sea. The saucer was
never the goal, only a distant phenotype. What we ask Norway to fund is the first
rung: the mind, and the clean ground it stands on.

#### 🔬 Under the hood

Wake it with one line and it comes up like an old Unix machine, telling you what
it is and what it runs on.

```console
$ ssh dev@brgen.no
$ cd MASTER && MASTER_BOOT_STATUS=1 bundle exec ruby bin/master
master: boot safe=1 web=0
master: background=0 watch=0
master: loop= owner=none
master: budget valid=true slot=unknown
master: aesthetic=brutalist
master: motd scan: 228 rules, self-test on boot
master: ready dmesg=preserved
```

Every change a model wants runs through one loop: it proposes an effect, the
constitution admits it, and only an allowed effect touches a file.

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

Three verdicts, only three. Block refuses with a reason; Request stops to ask a
person; Allow applies the effect against a checkpoint it can undo the moment it
errs. Everything past that is detail.

Read [START_HERE](START_HERE.md), then [AGENTS](AGENTS.md); [DECISIONS](DECISIONS.md)
explains anything strange on purpose, and the open work lives in
[one backlog](../TODO.md). Licensed MIT.
