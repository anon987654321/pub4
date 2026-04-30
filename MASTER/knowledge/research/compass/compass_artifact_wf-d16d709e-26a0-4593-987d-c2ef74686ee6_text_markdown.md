# Optimizing constitutional AI governance configs for human and machine readers

**For a 250+ principle YAML governance framework consumed by multiple LLMs, the optimal architecture is a shallow-nested YAML structure (2-3 levels maximum) with a flat index overlay, JSON Schema validation, and brutalist formatting that exposes structure honestly.** This hybrid approach captures YAML's **17-25% token efficiency** and superior LLM comprehension for nested data while mitigating its indentation-related failure modes through defensive parsing. Critical principles must appear in the first and last 20% of the document to counter the "lost in the middle" phenomenon that affects all transformer architectures.

The research reveals a fundamental tension: LLMs perform better with looser format constraints on reasoning tasks (up to 40% performance variation), yet multi-LLM systems require strict schema guarantees. The solution is a two-layer architecture—human-readable YAML as the source of truth, with JSON Schema enforcement at the parsing boundary.

## YAML wins comprehension tests but demands defensive architecture

Academic research testing GPT-3.5-turbo, Claude-3-Haiku, Gemini-1.5-Flash, LLaMA-3-8B, and Gemma-2-9B found YAML outperforms JSON and XML for nested data comprehension. GPT-5 Nano showed **17.7% better accuracy** with YAML than XML; Gemini 2.5 Flash Lite exhibited similar preferences. Only Llama models proved format-agnostic.

However, YAML's whitespace sensitivity creates significant failure modes. LinkedIn's production systems experienced **~10% reliability issues** with LLM-generated YAML, requiring a custom "defensive parser" to patch common mistakes. The primary failure patterns include indentation drift (**30-70% of YAML parsing failures**), unquoted special characters (`:`, `#`, `@`), and boolean auto-conversion from `yes/no` to `true/false`. These risks multiply when six different LLMs consume the same configuration.

Token efficiency claims require scrutiny. While YAML saves **25-50% tokens** versus pretty-printed JSON, this comparison is misleading—minified JSON actually uses **15-25% fewer tokens** than YAML. For a governance framework prioritizing human readability, this tradeoff favors YAML. But for pure machine consumption, minified JSON wins.

The strategic recommendation: maintain YAML as the canonical human-editable format while implementing strict JSON Schema validation. All major providers (OpenAI, Anthropic, Google, xAI) have invested in JSON Schema enforcement, with constrained decoding guaranteeing **zero parsing errors** when schemas are applied. Export YAML to validated JSON at the parsing boundary.

## Transformer attention mechanisms punish deep nesting

Research on transformer architectures reveals a critical limitation for deeply nested configurations: scaled dot-product attention lacks native mechanisms for handling hierarchical patterns of arbitrary depth. Transformers struggle with recursive structures because they lack stack-like behavior—the ability to push, pop, and backtrack through nested contexts.

The "lost in the middle" phenomenon, documented by Liu et al. (2024), shows a **U-shaped performance curve** where LLMs best recall information at the beginning or end of context. Claude 2.1's accuracy on middle-positioned information dropped to **27%** in controlled tests. For a 250+ principle configuration, this means principles buried in deep hierarchies effectively become invisible to detection engines.

Two mechanisms drive this position bias. Causal attention causes preceding tokens to accumulate disproportionately higher attention scores, favoring initial content. Rotary Position Embedding (RoPE) introduces long-term decay that diminishes attention to semantically meaningful but distantly-positioned tokens. The effect is strongest when inputs occupy less than **50% of the context window**.

Structural mitigation strategies emerge from the research. Minimize nesting to **2-3 levels maximum**—each additional level increases positional distance from attention-favored positions. Place the most critical principles in the first 20% and last 20% of the configuration. Consider explicit repetition of essential rules at both beginning and end. Use numbered flat indexes rather than relying solely on hierarchical position for principle discovery.

## Information architecture for 250+ principles requires layered access patterns

Google's SRE Workbook articulates the core philosophy: "ideal configuration is no configuration at all." For unavoidable complexity, user-centric design minimizes mandatory inputs while providing smart defaults. The cognitive load research supports **70-character line lengths**, chunked information segments, and F-pattern scanning optimization with critical information top-left.

For 250+ principles, a tiered profile system proves most effective. TypeScript-ESLint's model offers a template: a `base` tier of ~20 essential rules, `recommended` expanding to ~100 common rules, and `comprehensive` covering the full set. This allows governance to scale with team sophistication while keeping core configs scannable. Each tier inherits from simpler configurations, with later definitions overriding earlier ones.

The indexing strategy should provide **multiple entry points**: by category, by severity, by tag, and alphabetically. A master index at the configuration head creates a flat lookup table mapping principle IDs to their locations, enabling both human navigation and programmatic access. Cross-references use explicit principle IDs (`SEC-001`, `PERF-042`) rather than implicit hierarchical paths.

Effective organization combines categorical grouping (security, performance, accessibility) with a consistent rule definition schema:

- **Identification block**: ID, name, category, severity, tier
- **Content block**: description, rationale using literal block scalars (`|`)
- **Discovery block**: tags, keywords, aliases for search optimization  
- **Relationship block**: related rules, see-also references, supersedes links
- **Example block**: good and bad code samples

This structure ensures each principle is self-documenting and independently comprehensible—embodying the "every page is page one" principle from technical documentation research.

## Multi-LLM compatibility demands explicit schemas and defensive patterns

Provider-specific parsing behaviors vary substantially. OpenAI's GPT-4o supports strict JSON Schema enforcement through constrained decoding. Anthropic's Claude handles XML tags exceptionally well (specifically trained on them) but shows **14-20% JSON failure rates** without workarounds like response pre-filling. Google's Gemini requires the cumbersome `genai.protos.Schema` class for reliable JSON. DeepSeek returns empty content occasionally and requires the literal word "json" in prompts. Grok supports structured outputs only on grok-2-1212+. GLM shows less reliable schema adherence in structured output scenarios.

The defensive architecture pattern for cross-LLM consumption:

Schema-as-contract enforcement means all fields marked required, `additionalProperties: false`, enum constraints for categorical values, and explicit data types. For governance principles, this includes enumerating valid severity levels (`error|warn|info`), valid categories, and valid tiers rather than accepting arbitrary strings.

Two-step reasoning preserves accuracy. Research shows format constraints hurt reasoning task performance. For governance detection, have LLMs reason freely first, then structure their output in a second pass. This improved accuracy from **48% to 61%** in comparative studies.

Provider abstraction via libraries like Instructor handles mode switching: `Mode.TOOLS` for OpenAI, `Mode.ANTHROPIC_TOOLS` for Claude, `Mode.GENAI_STRUCTURED_OUTPUTS` for Gemini, `Mode.MD_JSON` for DeepSeek. Build retry logic with exponential backoff and maintain a fallback chain across providers.

Token budget planning must account for **10%+ variance** in token counts across different tokenizers (tiktoken, SentencePiece). Budget 15-20% additional headroom for multi-LLM deployments. System instructions with strict rules get truncated when context windows fill, causing format drift—keep governance configs well under context limits.

## Brutalist design philosophy creates honest, minimal configurations

Dieter Rams' tenth principle—"good design is as little design as possible" (*Weniger, aber besser*)—translates directly to configuration architecture. Every option costs cognitive load; every key must earn its place. Default everything that can be defaulted. Configuration should reveal its function through organization, not require documentation to explain structure.

Tadao Ando's architectural philosophy offers three structural metaphors. **Raw materials**: use plain text formats with disciplined structure, exposing the raw configuration intent without abstraction layers. **Light and geometry**: create clear geometric organization through consistent indentation, sections as squares, whitespace as "Ma" (間)—the Japanese concept of meaningful emptiness. **The haiku effect**: emphasize simplicity through what is absent, leaving room for user extension rather than anticipating every case.

Brutalist web design's principle of "truth to materials" demands that configuration structure reveal purpose. The config's material isn't YAML syntax—it's configuration intent. Structure should mirror system architecture: a `connection:` block that contains connection parameters, not a `database_configuration_settings.primary_connection_parameters.hostname_address` that obscures meaning through hierarchy.

The anti-patterns to eliminate: feature-itis (options for edge cases that bloat the config), comment bloat (explaining the obvious), nested abstraction (configs requiring other configs to understand), magic values (options meaningful only with external documentation), and ceremony over content (XML-like verbosity where key-value suffices).

## Practical implementation for master.yml v115.3

The recommended architecture synthesizes these findings into a concrete structure. The master configuration maintains a **flat header section** containing version metadata, a master index of all 250+ principles keyed by ID, and profile definitions (minimal, standard, comprehensive). This header occupies the attention-favored initial position.

The principle definitions follow in **shallow hierarchies grouped by domain** (security, performance, accessibility, formatting). Each principle uses the standardized schema ensuring self-documentation and search optimization. Critical governance rules—those that must never be missed by detection engines—appear both in their categorical location AND in an explicit `critical_principles` list at the document's end, exploiting the recency bias in attention mechanisms.

Section separators use brutalist visual markers that parse as comments:

```yaml
# ═══════════════════════════════════════════
# SECURITY PRINCIPLES
# ═══════════════════════════════════════════
```

This creates scannable structure for human readers while remaining invisible to YAML parsers.

For LLM consumption, the system exports the YAML to minified JSON with full schema validation at runtime. The JSON Schema includes all principle ID enums, valid severity levels, required cross-reference validations, and structural constraints. Parsing failures trigger defensive recovery: attempt YAML parse, attempt JSON extraction from partial response, log failure patterns by model for continuous improvement.

## Conclusion

The optimal governance configuration is neither purely flat nor deeply nested—it's a **structured shallow hierarchy with flat index overlays**, brutalist formatting that exposes rather than obscures, and a defensive parsing layer that accommodates multi-LLM variance. YAML serves human authors; JSON Schema enforcement serves machine reliability. Critical principles exploit attention bias through strategic positioning. Every element earns its place through necessity, not convention.

The deeper insight: configuration design is information architecture. The same attention mechanisms that lose middle content in prose lose middle principles in nested configs. The same cognitive load that overwhelms readers with verbose documentation overwhelms them with over-engineered configuration. Rams was right—less, but better. The governance framework that protects through 250+ principles must itself embody the discipline of knowing which principles matter most, where they appear, and how to ensure every system that consumes them can find what it needs.