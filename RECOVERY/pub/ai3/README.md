# AI³ recovery note

Legacy source:

```text
pub/ai3/
```

`MASTER/` absorbed the AI³ idea, but this old subsystem was not restored as a
standalone CLI. That is a restore gap.

## Legacy identity

AI³ was a modular Ruby CLI:

- launched with `ruby ai3.rb`
- used LangChain.rb
- supported multi-LLM routing
- used Weaviate for RAG
- had role-specific assistants
- used Ferrum for web scraping and screenshots
- used Replicate for multimedia/TV/news generation
- exposed file and system tools
- targeted OpenBSD with pledge/unveil
- used encrypted sessions

## Legacy commands

```text
chat <query>
task <name> [args]
rag <query>
list
help
exit
```

## Legacy assistant inventory from `pub/ai3/README.md`

- General
- OffensiveOps
- Influencer
- Lawyer
- Trader
- Architect
- Hacker
- ChatbotSnapchat
- ChatbotOnlyfans
- Personal
- Music
- MaterialRepurposing
- SEO
- Medical
- PropulsionEngineer
- LinuxOpenbsdDriverTranslator

## Legacy structure

```text
ai3/
├── ai3.rb
├── assistants/
├── config/
│   ├── config.yml
│   └── locales/en.yml
├── lib/
│   ├── cognitive.rb
│   ├── multimedia.rb
│   ├── scraper.rb
│   ├── mock_classes.rb
│   └── utils/
│       ├── config.rb
│       ├── file.rb
│       └── llm.rb
├── data/
├── logs/
├── tmp/
├── install.sh
├── install_ass.sh
├── Gemfile
└── README.md
```

## Port plan into `MASTER`

Do not paste the old CLI wholesale into production. Port it in layers:

1. Create an inventory importer:

```text
MASTER/tools/ai3_import.rb
```

2. Map old assistants to `MASTER` roles/council members:

```text
ai3/assistants/lawyer      → MASTER/data/roles.yml
ai3/assistants/architect   → MASTER/data/roles.yml
ai3/assistants/medical     → MASTER/data/roles.yml
ai3/assistants/music       → MASTER/data/roles.yml
```

3. Map tools:

```text
UniversalScraper           → MASTER/lib/reach/
Weaviate RAG               → MASTER/lib/reach/weaviate.rb
FileUtils/system access    → MASTER/lib/ground/
LLM routing                → MASTER/lib/judge/llm_dispatcher.rb
Multimedia                 → MASTER/lib/voice/ or STUDIO/postpro/
```

4. Preserve the old README and installers under:

```text
RECOVERY/pub/ai3/legacy/
```

5. Add tests that prove each old assistant has one canonical successor.

## Completion definition

AI³ is restored only when one of these is true:

- the old `ai3/` tree is archived under `RECOVERY/pub/ai3/legacy`, or
- each old assistant/tool/config file has a manifest entry mapping it to a
  working `MASTER` replacement, with tests.

The current state is only `absorbed`.
