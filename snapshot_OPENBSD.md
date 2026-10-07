# OPENBSD — source snapshot

Generated 2026-10-07 19:53:07 UTC — git da3c3e6 — 234 files inlined.

Share this file with another LLM as the full readable OPENBSD codebase pack.

## Agent analysis protocol

This document is a **share-size-bounded source mirror** for `OPENBSD`. Treat every fenced
block as source of truth — not a summary. The `Omitted text files` section, when present,
is authoritative: those tracked text files were excluded only to satisfy the hard size ceiling. Work through it in this order:

### 1. Orient
- Read the header (generation metadata, file count, policy) and **Tree** before opening any file block.
- Note topology: where boot, routing, data, UI, deploy, and tests live relative to each other.

### 2. Word-for-word read + cross-reference
- Read each `## \\`path\\`` section **line by line**; do not skim or paraphrase from headings alone.
- **Cross-reference** symbols across files: follow requires/imports, route → controller → service
  chains, YAML keys → Ruby readers, JS event names → subscribers, CLI commands → dispatchers.
- When the same name recurs in multiple places, reconcile definitions — flag drift immediately.

### 3. Deep execution traces (start → finish)
- Pick critical paths (boot, request/response, scan/fix loop, deploy, TTS/chat SSE, face render)
  and trace **one complete path** from entrypoint through every hop to side effects/output.
- For each hop record: caller, callee, inputs, branching conditions, failure modes���q�^