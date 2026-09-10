# Ground

**Ground is where MASTER's law stops being a document and becomes something the
runtime can ask a question of.** Axioms, law resolution, the memory and evidence
store, and the sandbox policy all live here, and `lib/master.rb` loads them
before anything else can run.

`rules.rb` and `law_resolver.rb` hold the rule concepts themselves. `axioms.rb`
carries the Rails doctrine and the platform pillars.

Almost nothing here is a rule written in Ruby. The rules are data, in
`data/rules.yml`, and this directory is the machinery that resolves them.

Ground's charter is five clauses — constitution, config, policy, memory, schema —
and `MASTER/PATH_OWNERSHIP.yml`, at the root of this tree rather than beside this
file, is where every directory writes its own down. A file belongs where its
purpose lives, which is a question the file answers and the directory it was
written in does not. Seventy-one files had gathered here against a charter that
covers about forty-five, so which provider answers and what a call costs went to
`io/`, how a turn is framed went to `cli/`, and checkpointing and patch
verification went to `fix/`. Read the clause before you add a file, and read it
again before you defend one.

The clause that took longest to settle is schema, because a typed reader over a
declarative table reads as at home almost anywhere. It lives here, and the test
is the table rather than the reader: when what the table declares is MASTER's own
constitution, configuration, policy or memory, the reader is that schema and
belongs to ground, whether the table sits in `data/` or in a frozen constant in
the file itself. `map.rb`, `runtime_catalog.rb`, `maturity_scorecard.rb`,
`research_thresholds.rb`, `bootstrap_docs.rb` and `operator_playbook.rb` are all
that, and all stay. When the table's subject is another directory's declared
purpose, the subject wins over the shape: a catalogue of reference Rails repositories
read only by the PWA audit is a Rails audit, so `mobile_web_cluster_catalog.rb`
went to `rails/`. And a file that writes the table rather than reading it is not a
schema at all — `principle_map_repair.rb` repairs `principle_map.yml` for
`bin/doctor --fix` and went to `fix/`, where repair is the declared purpose.

A move is a constant rename, and it has two traps that bite in this order. Before
moving a file, look for callers that write the bare constant inside `module Ground`,
because a bare name resolves by lexical scope and breaks the moment its neighbour
leaves — `PressureEngine` reads as dead to any census that greps the qualified name
and is built on every boot, and `DoneChecker` defaulted an argument to a bare
`PatchVerifier.new`. After moving it, read the moved file for its own bare
references to constants that stayed behind, `Swallow` and `FailureTaxonomy` and
`Frontmatter` among them, and write them out as `Master::Ground::` in full. The
first trap breaks the caller and the second breaks the file you just moved; the
second is the one that has reached a test.
