# MASTER Knowledge Base

Local knowledge indexed by `Tools::SearchKnowledge`. Use `search_knowledge` to query.

## Topics

- **ruby_llm/** — ruby_llm source + README + CHANGELOG
- **system_prompts/** — leaked system prompts (Claude, GPT, o3, etc.)
- **gems/** — README files for the gems in the bundle
- **github_repos/** — cloned reference repos (style guides, prompt leaks, OpenRouter)
- **docs/** — fetched framework docs (Rails edge guides, Stimulus/StimulusReflex, Replicate)
- **research/** — numbered research notes
- **openbsd/** — OpenBSD man pages (add via: `man X | col -b > knowledge/openbsd/X.txt`)
- **style_guides/** — vendored prose/code style canon (`ruby.adoc`, `rails.adoc`, `elements-of-style.md`)

## Querying

```
search_knowledge "streaming SSE"            # search all topics
search_knowledge "pledge" topic:openbsd     # search a specific topic
search_knowledge "on_chunk" topic:ruby_llm  # search ruby_llm source
```

## Known issue

This file was repeatedly clobbered with a circuit-breaker error string
(`circuit open: retry in Ns`) by an autoloop sweep pass across several commits
(`969bca18f`, `66235075e`, `5ea120668`). Some sweep/fetch step writes a caught
exception message to disk instead of discarding it on failure. Restored here
from the last known-good content (commit `8d11c6789`); root cause in the
sweep/fetch path is still open — see `MASTER/TODO.md` section CG.
