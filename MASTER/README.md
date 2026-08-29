# MASTER

<!-- HERO: drop the GitHub user-attachments URL for loop.mp4 in here after uploading it -->
<video src="loop.mp4" autoplay loop muted playsinline width="360"></video>

**MASTER is the first artificial intelligence written in pure Ruby that governs
itself by law, not by hope — and the seed of a Norwegian company that runs its
own intelligence on its own green power.** Most systems let a model act first and
inspect the wreckage after. MASTER inverts that: the model only proposes, and
nothing touches disk until a written constitution approves it. It thinks out
loud, shows every move, and answers to a rulebook it can read but never rewrite.

This document is both the project and its business plan — the technology below,
and the case for building it in Norway with support from
[Innovasjon Norge](https://en.innovasjonnorge.no/article/startups).

⚖️ &nbsp; 🤖 &nbsp; 🌍 &nbsp; ⚡ &nbsp; 🛡️

### 💡 The innovation

Every other AI assistant asks you to trust it. MASTER is built so you do not have
to. Thinking and deciding are kept apart: a model proposes a change, and before
that change becomes a file it must clear a constitution — an unbreakable law,
working rules, and executable laws that carry their own right-and-wrong examples
and recheck themselves at every boot. Break the constitution and you get a
refusal with a reason, never a quiet patch behind your back. It is written in
pure Ruby, deploys to OpenBSD, and needs no cloud to judge a codebase — which
means it can run anywhere, including on hardware we own.

### 🔁 What it does

You hand MASTER a sentence and it scans, fixes, criticizes, and reviews, circling
until nothing new turns up. The scan is not a model guessing; it is exact checks
that read a file's shape against named principles. When a change deserves more
than a checklist, MASTER convenes a panel — an architect, a caretaker, a
performance mind, an ethicist, a designer — each on its own model, each arguing
before a judge. And it makes things: ask in plain words for a photograph of
Bergen in the rain, a [J Dilla beat](../STUDIO/dilla), or a graded film look, and
it routes you to [the studio tools](../STUDIO) beside it.

### 🌍 The market, and why now

The world is spending more on machine intelligence than on almost anything else,
and nearly all of it runs on electricity in large buildings. Global data-centre
investment now runs past 250 billion US dollars a year, most of it driven by AI,
and the binding constraint is no longer chips — it is power, and clean power most
of all. That is the opening. A sovereign, self-governing AI that runs on cheap
green electricity is both a better product and a cheaper one.

### 🏔️ Three homes for the compute

MASTER's intelligence needs somewhere to live, and where it lives is the whole
advantage.

A datacentre in **California** puts MASTER next to the American market and the
frontier labs. A second in **Malaysia** reaches South-East Asia on tropical-grid
economics and a fast-growing customer base. But the heart of it sits **inside a
mountain on a Norwegian fjord** — the same model Norway already proves at scale
with [Lefdal Mine](https://www.lefdalmine.com) and Green Mountain. Norway's grid
is about 98 percent renewable hydropower, among the cheapest in Europe, and fjord
water holds near 8 °C all year, so a mountain hall cools itself for free. That
pushes power-usage effectiveness toward 1.1, against a global average near 1.5 —
roughly a third less energy for the same compute, at a third less carbon. Green
by geography, not by offset.

### 🇳🇴 What Norway gets

A Norwegian company owning both the intelligence and the infrastructure it runs
on. Realistically that is six to ten skilled jobs within three years — engineers,
operators, studio staff — and export revenue from selling governed AI and green
compute abroad, into exactly the California and South-East Asia markets the
datacentres reach. The intellectual property, the carbon savings, and the value
stay in Norway.

### 💰 The ask

We are seeking **Commercialisation funding from Innovasjon Norge** — Phase 1 on
the order of one million kroner, with a path to Phase 2 up to roughly five
million, and the startup loan (up to two million kroner) alongside it. Honestly
scoped: that grant does not build a mountain datacentre — a full facility is
later-stage project finance in the tens of millions of euros. What it funds is
the fundable near-term: finishing MASTER as a product, a feasibility study for
the fjord site, and a first pilot compute pod proving the green economics on real
Norwegian power. The datacentres are the growth roadmap the pilot unlocks.

Year one, commercialise the software and complete the fjord feasibility. Year
two, stand up the pilot pod inside a Norwegian mine site and win first export
customers. Year three, scale the fjord hall and add the California and Malaysia
edge nodes.

🚀 &nbsp; ⚡ &nbsp; 🌟 &nbsp; 🏔️

### 🧬 The horizon

The near-term is a company. The long-term is stranger, and it is why the
architecture is shaped the way it is. MASTER is built like an embryo — one small
core of identity, memory, and safety that takes on whatever body a mission needs.
Today that body is software on green Norwegian power. The same design reaches, in
time and with enormous engineering between, toward machines that clear orbital
debris or microplastic from the sea. The flying saucer was never the goal; it is
one distant phenotype of the embryo. What we are asking Norway to fund is the
first rung: the intelligence, and the clean ground it stands on.

#### 🔬 Under the hood

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
    in Verdict::Block(reason:, by:)      then emit(turn, effect, refused(reason, by))
    in Verdict::Request(effect:, prompt:) then return done if (done = approve(turn, effect, prompt:))
    in Verdict::Allow(effect: admitted)   then return done if (done = apply(turn, admitted))
    end
  end
end
```

Three verdicts, only three. A Block refuses with a reason. A Request stops to ask
a person. An Allow applies the effect against a checkpoint it can undo the moment
it errs. Propose, judge, allow or refuse — everything past that is detail.

To work inside it, read [START_HERE](START_HERE.md), then [AGENTS](AGENTS.md);
[DECISIONS](DECISIONS.md) explains anything that looks strange on purpose, and the
open work lives in [one backlog](../TODO.md). Licensed MIT.
