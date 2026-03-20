# MASTER Knowledge Base

Local knowledge indexed by `Tools::SearchKnowledge`. Use `search_knowledge` tool to query.

## Topics

- **ruby_llm/** — ruby_llm 1.13.2 full source + README + CHANGELOG
- **system_prompts/** — asgeirtj/system_prompts: leaked Claude, GPT-4o, o3 system prompts
- **gems/** — README files for all 192 gems in the bundle
- **openbsd/** — OpenBSD man pages (add via: `man X | col -b > knowledge/openbsd/X.txt`)
- **awesome/** — Curated lists (populate via git clone)

## Querying

```
# In MASTER:
search_knowledge "streaming SSE"            # search all topics
search_knowledge "pledge" topic:openbsd     # search specific topic
search_knowledge "on_chunk" topic:ruby_llm  # search ruby_llm source
```
