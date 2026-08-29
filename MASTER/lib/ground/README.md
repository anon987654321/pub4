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
