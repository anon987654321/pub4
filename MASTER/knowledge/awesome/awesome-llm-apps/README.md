# Awesome LLM Apps

A curated list of inspiring applications, demos, and tools built with large language models (LLMs).  
The list is community‑maintained; feel free to submit pull requests for additions, corrections, or enhancements.

---

## Table of Contents

- [Chatbots & Assistants](#chatbots--assistants)
- [Coding & Development](#coding--development)
- [Content Generation](#content-generation)
- [Data & Analytics](#data--analytics)
- [Education & Research](#education--research)
- [Entertainment & Art](#entertainment--art)
- [Productivity & Automation](#productivity--automation)
- [Privacy‑Focused & Self‑Hosted](#privacy‑focused--self‑hosted)
- [Resources & Tools](#resources--tools)
- [Contributing](#contributing)

---

## Chatbots & Assistants

| Project | Model | Description | Repo / Source |
|---|---|---|---|
| **ChatGPT‑like UI** | OpenAI **GPT‑4o** | Full‑stack web UI with streaming, authentication, and session persistence. | [GitHub](https://github.com/Shubhamsaboo/awesome-llm-apps/tree/main/chatgpt-ui) |
| **Voice‑Enabled Agent** | DeepSeek **V3** | Speech‑to‑text + text‑to‑speech pipeline for hands‑free interaction. | [GitHub](https://github.com/Shubhamsaboo/awesome-llm-apps/tree/main/voice-agent) |
| **Ferrum Web‑Chat Bridge** | Custom | Browser‑automation bridge (Ferrum) that lets an LLM control a remote web UI. | [`lib/master/bridges/ferrum_web_chat.rb`](lib/master/bridges/ferrum_web_chat.rb) |

---

## Coding & Development

| Project | Model | Highlights | Repo / Source |
|---|---|---|---|
| **Auto‑Coder** | DeepSeek **V3** | Generates, edits, and applies diffs to a Rails codebase using `Master::Tools::ApplyDiff`. | [GitHub](https://github.com/Shubhamsaboo/awesome-llm-apps/tree/main/auto-coder) |
| **Static Analyzer** | OpenAI **GPT‑4o** | Runs RuboCop, Reek and custom heuristics via `Master::Scan`. | [`lib/master/scan`](lib/master/scan) |
| **Code Indexer** | — | Parses the entire repository with Prism, exposing a symbol‑lookup tool. | [`lib/master/code_index.rb`](lib/master/code_index.rb) |
| **Repo‑Browser** | OpenAI **GPT‑4o** | Interactive exploration of the codebase through a Ferrum‑based web UI. | [`lib/master/bridges/replicate.rb`](lib/master/bridges/replicate.rb) |

---

## Content Generation

| Project | Model | Output | Repo |
|---|---|---|---|
| **Blog Post Generator** | OpenAI **GPT‑4o** | Markdown articles from prompts. | [GitHub](https://github.com/Shubhamsaboo/awesome-llm-apps/tree/main/blog-generator) |
| **Slide Deck Builder** | DeepSeek **V3** | LaTeX Beamer decks from outlines. | [GitHub](https://github.com/Shubhamsaboo/awesome-llm-apps/tree/main/slide-deck) |
| **Newsletter Composer** | OpenAI **GPT‑4o** | RSS aggregation + human‑tone rewrite. | [GitHub](https://github.com/Shubhamsaboo/awesome-llm-apps/tree/main/newsletter) |

All use the unified `Master::Tools::LLM` wrapper for consistent provider handling.

---

## Data & Analytics

| Project | Model | Use‑case |
|---|---|---|
| **Semantic Search** | OpenAI embeddings | Indexes project files and enables natural‑language queries via `Master::SemanticCache`. |
| **Log Summarizer** | DeepSeek **V3** | Summarizes large log files, extracts anomalies, and surfaces actionable insights. |
| **Metrics Dashboard** | OpenAI **GPT‑4o** | Real‑time pipeline telemetry visualized with Chart.js. |

---

## Education & Research

| Project | Model | Feature |
|---|---|---|
| **LLM Tutor** | DeepSeek **V3** | Interactive Q&A for programming topics, powered by `Master::Council` personas (*Mentor*, *Skeptic*). |
| **Paper Reviewer** | OpenAI **GPT‑4o** | Parses PDFs, extracts key points, and generates critique reports. |
| **Conceptual Explorer** | DeepSeek **V3** | Runs `Master::Scan::Rules::ConceptualRule` to surface hidden design patterns. |

---

## Entertainment & Art

| Project | Model | Media |
|---|---|---|
| **Story Generator** | Gemini | Branching narratives with optional image generation. |
| **Music Lyric Composer** | DeepSeek **V3** | Generates lyrics; uses `Master::Tools::StrReplace` for rhyme tweaking. |
| **AI‑Paint** | Stable Diffusion (via `Master::Tools::WebSearch`) | Text‑to‑image generation with style prompts. |

---

## Productivity & Automation

| Project | Model | Integration |
|---|---|---|
| **Task Manager Bot** | DeepSeek **V3** | Syncs with Todoist API, creates & updates tasks from natural language. |
| **Email Draft Assistant** | OpenAI **GPT‑4o** | Drafts, revises, and sends emails via SMTP; respects `Master::Security::Permissions`. |
| **Meeting Scheduler** | OpenAI **GPT‑4o** | Parses calendar invites and proposes optimal times. |

---

## Privacy‑Focused & Self‑Hosted

| Project | Stack | Notes |
|---|---|---|
| **Self‑Hosted LLM Stack** | Docker Compose (DeepSeek, OpenRouter, Ollama) | Zero external API calls; optional GPU support. |
| **Secure Execution Sandbox** | `Master::CircuitBreaker` + `Master::Security::InjectionGuard` | Isolates LLM calls, caps resource usage, and prevents code injection. |
| **Local Knowledge Base** | `Master::SemanticCache` | Stores embeddings on‑disk; no network traffic. |

---

## Resources & Tools

- **`Master::Tools`** – File I/O, AST editing, shell execution, web search, and more.  
- **`Master::Pipeline`** – 10‑stage processing (Intake → Infer → Route → Guard → Execute → Council → Lint → Memo → Render).  
- **`Master::Result`** – Monadic `Ok`/`Err` wrapper for robust error handling.  
- **`Master::RingBuffer`** – Fixed‑size circular buffer for context windows.  
- **`Master::CodeIndex`** – Prism‑based symbol map, searchable via `Master::Tools::SymbolLookup`.  

---

## Contributing

1. Fork the repository.  
2. Add your project under the appropriate section, following the table format.  
3. Include:  
   - **Name** (linked to source or repo)  
   - **Model** (or “self‑hosted”)  
   - **Brief description** (≤ 120 characters)  
   - **Link** to code or demo.  
4. Run `rake test` to ensure the suite passes.  
5. Open a PR with a concise description.

For major restructurings, open an issue first.

---

*Maintained with ❤️ by the LLM‑apps community.*