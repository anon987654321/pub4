# Ground

**Ground is where MASTER's law stops being a document and becomes something the
runtime can ask a question of.** Axioms, law resolution, the memory and evidence
store, and the sandbox policy all live here, and `lib/master.rb` loads them
before anything else can run.

`rules.rb` and `law_resolver.rb` hold the rule concepts themselves. `axioms/`
carries the Rails doctrine and the platform pillars. `repo_mining/` keeps the
reference cluster catalogs an audit compares against.

Almost nothing here is a rule written in Ruby. The rules are data, in
`data/rules.yml`, and this directory is the machinery that resolves them.

Ground's charter is five clauses — constitution, config, policy, memory, schema —
and `PATH_OWNERSHIP.yml` is where every directory in this tree writes its own down.
A file belongs where its purpose lives, which is a question the file answers and
the directory it was written in does not. Seventy-one files had gathered here
against a charter that covers about forty-five, so which provider answers and what
a call costs went to `io/`, how a turn is framed went to `cli/`, and checkpointing
and patch verification went to `fix/`. Read the clause before you add a file, and
read it again before you defend one.

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
