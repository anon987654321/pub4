# Evidence Base for LLM Coding Assistant Framework (master.yml v24.0.0)

This technical reference compiles academic and production evidence supporting configuration decisions for an LLM coding assistant framework. Each section provides validated citations, benchmark data, and specific thresholds from peer-reviewed research and production systems.

---

## 1. Interpretation: loose vs strict principle detection

The framework's interpretation layer determines whether to apply literal pattern matching or semantic analysis when detecting principle violations. Research on code clone detection provides the foundational evidence for threshold selection.

### Code clone taxonomy and detection thresholds

The seminal taxonomy from **Roy, Cordy & Koschke (2009)** in *Science of Computer Programming* defines four clone types: Type-1 (identical except whitespace), Type-2 (syntactically identical with renamed identifiers), Type-3 (copied with modifications), and Type-4 (semantically equivalent but syntactically different). The **BigCloneBench** benchmark by Svajlenko & Roy (ICSME 2015), containing 8+ million validated clone pairs across 25,000 Java systems, further subdivides Type-3 clones by syntactical similarity: **70-90%** for strongly similar and **50-70%** for moderately similar clones.

Production tools converge on remarkably consistent thresholds. **SourcererCC** (Sajnani et al., ICSE 2016) achieves optimal precision-recall at **70% token overlap**, delivering 86% precision with 86-100% recall for Type-1 through Type-3 clones. PMD CPD defaults to **100 minimum tokens**, jscpd uses **50 minimum tokens**, and SonarQube triggers warnings at **5% duplication** and errors at **10%**. CodeClimate's duplication engine uses **25 AST mass** for identical code and **50 AST mass** for similar code, applying the "Rule of Three" (report only when duplicated 3+ times).

### Semantic similarity for "spirit vs letter" interpretation

For loose/semantic detection, embedding-based approaches using **CodeBERT** (Feng et al., EMNLP 2020) and **GraphCodeBERT** (Guo et al., ICLR 2021) achieve F1 scores of **0.90-0.93** on BigCloneBench. GraphCodeBERT's integration of data flow graphs significantly improves Type-4 semantic clone detection. However, a 2022 ACM study found **86% of weak Type-3/Type-4 pairs in BigCloneBench are mislabeled**, cautioning against over-reliance on these benchmarks.

### DRY principle application guidance

Hunt & Thomas's original definition emphasizes eliminating *knowledge* duplication, not code duplication. The **WET principle** ("Write Everything Twice") and Sandi Metz's **AHA** ("Avoid Hasty Abstractions") programming philosophy recommend allowing duplication up to 2 occurrences—only abstracting on the 3rd occurrence. Empirical guidance confirms: "duplication is cheaper than the wrong abstraction." Over-abstraction produces rigid code with if/else explosion, forced coupling, and abstraction overload.

**Recommended configuration**: Use **70% similarity threshold** for balanced detection, **100+ minimum tokens** for conservative precision. Apply literal detection for Type-1/2 clones, AST-based for Type-3, and ML-based embedding similarity for Type-4 semantic clones.

---

## 2. Streaming resilience: API reliability patterns

### Timeout configurations from SDK defaults

Both **Anthropic SDK** and **OpenAI SDK** default to **10-minute (600 seconds)** request timeouts with **5-second** connection timeouts. Anthropic SDK performs **2 auto-retries** by default with exponential backoff, retrying on 408, 409, 429, and 5xx errors. AWS Bedrock Claude allows **60-minute** inference timeouts for Claude 3.7 Sonnet and Claude 4 models.

### Exponential backoff with jitter (AWS formula)

The AWS SDK implements truncated binary exponential backoff with jitter:
```
sleep = random_between(0, min(cap, base * 2^attempt))
```

Default values include **MAX_BACKOFF of 20 seconds**, **3 max attempts** (standard/adaptive retry modes), and **100ms initial delay**. Three jitter algorithms are documented in the AWS Architecture Blog: **Full Jitter** (random between 0 and exponential max), **Equal Jitter** (half exponential plus random half), and **Decorrelated Jitter** (random between base and 3× previous sleep). Full and Equal Jitter reduce API calls by approximately **50%** compared to no-jitter backoff.

### Circuit breaker specifications

**Netflix Hystrix** (now in maintenance mode) specified: **20 requests** minimum in rolling window before tripping, **50% error threshold**, **5,000ms sleep window** before half-open state, **10,000ms rolling stats window**, and **1,000ms command timeout**. **Resilience4j** (current recommended library) defaults to **50% failure rate threshold**, **100 calls sliding window**, **60,000ms wait in open state**, and **10 permitted calls in half-open state**.

### Rate limiting standards

**RFC 6585** (April 2012) defines HTTP 429 Too Many Requests with optional Retry-After header. **RFC 7231** specifies Retry-After format as either HTTP-date or delay-seconds integer. The **Token Bucket algorithm** allows bursting up to Bmax capacity then throttles to rate r, while **Leaky Bucket** provides constant output rate (smoothing). LangChain defaults to **6 max retries** (JavaScript SDK) or **3 max attempts** (Python), while LiteLLM uses **60-second cooldown** after rate limiting with **3 allowed failures/minute**.

---

## 3. Context window management

### StreamingLLM attention sink mechanism

**Xiao et al. (ICLR 2024)** "Efficient Streaming Language Models with Attention Sinks" (arXiv:2309.17453) discovered that initial tokens receive disproportionately high attention scores regardless of semantic importance, acting as "attention sinks." The solution: retain just **4 initial tokens** as attention sinks plus a sliding window of recent tokens. Performance data shows stable modeling to **4+ million tokens** with **up to 22.2× speedup** versus sliding window recomputation. Perplexity on PG-19 with Llama-2-13B: StreamingLLM 5.40 vs Dense Attention 5.43 vs Window Attention 5158 (fails).

### LLMLingua compression ratios

**LLMLingua** (Jiang et al., EMNLP 2023) and **LLMLingua-2** (Pan et al., ACL 2024 Findings) achieve the claimed **20× compression** with only **1.5 points drop** on GSM8K. At 20× compression, performance is **33.10 points better** than Selective-Context baseline. LLMLingua-2 achieves **3×-6× faster compression** than LLMLingua with compression ratios of 2×-5×. Practical end-to-end acceleration ranges from **1.7×-5.7×**.

### Mem0 accuracy improvements

**Chhikara et al. (arXiv:2504.19413, 2025)** validates the **+26% accuracy improvement** claim on the LOCOMO benchmark: Mem0 achieves **66.9%** LLM-as-a-Judge score versus OpenAI Memory's **52.9%** (26% relative improvement), with **91% latency reduction** (1.44s vs 17.12s p95) and **90% token reduction** (~1.8K vs 26K tokens). Caveat: full-context baseline achieved ~73% J-score (higher than Mem0's 68%); Mem0's advantage emerges primarily with conversations **>150 turns**.

### RAG chunking optimal sizes

Research from arXiv:2505.21700 ("Rethinking Chunk Size for Long-Document Retrieval") shows: **256-512 tokens** optimal for factoid queries (names, dates), **1024+ tokens** for analytical queries, **64-128 tokens** for short fact-based answers (SQuAD: 64 tokens = 64.1% recall@1), and **512-1024 tokens** for technical content. Industry recommendation: **10-20% overlap** between chunks. Critically, arXiv:2410.13070 found **fixed-size chunking often performs equally or better** than semantic chunking on non-synthetic datasets—semantic chunking benefits are highly task-dependent.

### Importance-weighted eviction

**H₂O (Heavy-Hitter Oracle)** by Zhang et al. (NeurIPS 2023, arXiv:2306.14048) demonstrated that retaining **20% heavy hitter tokens** plus recent tokens achieves **up to 29× throughput improvement** versus DeepSpeed Zero-Inference and HuggingFace Accelerate. The approach treats KV cache eviction as a dynamic submodular optimization problem with provable guarantees.

---

## 4. Instruction persistence: lost-in-middle phenomenon

### Original lost-in-middle paper

**Liu et al. (2024)** "Lost in the Middle: How Language Models Use Long Contexts" (*Transactions of the Association for Computational Linguistics*, 12:157-173, DOI:10.1162/tacl_a_00638) established the U-shaped performance curve: accuracy is highest when relevant information appears at the **beginning or end** of input context, degrading significantly for information in the **middle**. This affects even explicitly long-context models including GPT-3.5-Turbo and Claude-1.3.

### Anthropic dual-placement research

The **30% improvement** claim is validated from official Anthropic documentation: "Queries at the end can improve response quality by up to 30% in tests, especially with complex, multi-document inputs." Anthropic's September 2023 experiments on 70K-95K token documents showed Claude 2's accuracy improvement from 0.939 to 0.961 representing a **36% reduction in errors**. The documented recommendation is placing **long documents at the TOP** and **queries/instructions at the END** (sandwich pattern), though explicit research on dual-placement (start AND end simultaneously) was not found.

### Primacy and recency effects

Research on serial position effects (arXiv:2406.15981) confirms LLMs consistently perform better on first and last tokens compared to middle positions. GPT-4 variants show strong **primacy bias** (100% first-slot preference in some tests); Qwen 3 shows mild recency bias; "thinking" models show reduced bias. As context lengthens, primacy bias diminishes and **recency bias becomes dominant** (arXiv:2310.01427).

### Instruction drift mitigation

Multi-turn performance studies (arXiv:2505.06120) analyzing 200,000+ simulated conversations found **39% average performance drop** in multi-turn versus single-turn settings, decomposing into minor aptitude loss but **significant reliability increase**. The **Snowball technique** (turn-level recapitulation) mitigates **15-20%** of performance deterioration. **XML structure effectiveness** is strongly validated—Anthropic's Zack Witten confirms "Claude was trained with XML tags in the training data," making structured prompts with `<instructions>`, `<example>`, `<document>` tags significantly improve instruction following.

**Note**: The **"every 2000 tokens" reinforcement interval** was not validated in academic literature. Practical recommendations emphasize structured prompts (XML tags), explicit role definitions, and context summaries over periodic token-based repetition.

---

## 5. Path normalization

### POSIX standards (IEEE 1003.1)

**IEEE Std 1003.1-2024** (POSIX.1-2024) specifies `realpath()` SHALL derive an absolute pathname that resolves to the same directory entry **without `.`, `..`, or symbolic links**. Path resolution rules: absolute paths begin with `/`, multiple slashes treated as single (except implementation-defined leading `//`), trailing slashes indicate directory requirement. The PWD environment variable SHALL represent "an absolute pathname of the current working directory... not contain any components that are dot or dot-dot."

### Cross-platform conversion utilities

**cygpath** (Cygwin) converts between Unix (`/cygdrive/c/`), Windows (`C:\`), mixed (`C:/`), and DOS 8.3 forms. Key options: `-u` for Unix output (default), `-w` for Windows, `-m` for mixed (forward slashes). Edge cases include 8.3 names not always available on modern Windows, MAX_PATH handling (root-local prefix `\\?\` auto-prepended for paths >260 bytes), and codepage considerations.

**wslpath** (WSL) provides similar conversion with drives mounted under `/mnt/c`, `/mnt/d` (versus Cygwin's `/cygdrive/c`).

### Windows path handling

Microsoft documentation defines path categories: DOS paths (`C:\folder\file`), UNC paths (`\\server\share\path`), and extended device paths (`\\?\C:\path` which skip normalization and support >MAX_PATH). Normalization via `GetFullPathName()` converts forward slashes to backslashes (except with `\\?\` prefix), removes `.` and `..` segments, and strips trailing periods and spaces. **Critical**: Forward slashes NOT supported with `\\?\` prefix, and MAX_PATH (260 characters) requires explicit opt-in on Windows 10 1607+ or `\\?\` prefix bypass.

### VS Code Remote architecture

VS Code Remote Development uses a client-server model where the VS Code Server installs on the remote OS independently. Path abstraction ensures most extensions work without modification, but "absolute path settings" may need local/remote variations. For SSH config files, "You can use `/` for Windows paths as well."

---

## 6. Anti-hallucination and verification

### Semantic entropy (Nature 2024)

**Farquhar, Kossen, Kuhn & Gal** "Detecting hallucinations in large language models using semantic entropy" (*Nature*, 630(8017):625-630, 2024, DOI:10.1038/s41586-024-07421-0) introduces entropy computed at the *meaning* level rather than token sequences. The method samples **~5 answers**, clusters by semantic meaning using NLI or bidirectional entailment checking, then computes entropy over clustered groups. High semantic entropy indicates likely confabulation. Computational cost: **~10× compute** versus raw Q&A (comparable to chain-of-thought). Works across datasets without task-specific data and supports black-box models via the "discrete variant."

### Chain-of-Verification (CoVe)

**Dhuliawala et al. (Meta AI/FAIR, arXiv:2309.11495, ACL Findings 2024)** "Chain-of-Verification Reduces Hallucination in Large Language Models" uses a 4-step process: (1) generate baseline response, (2) plan verification questions, (3) execute verification independently (avoiding bias from original response), (4) generate final verified response. The **Factor+Revise variant** is most effective, achieving on Wikidata list-based tasks F1/Precision improvement from 0.17 to 0.36 (2× improvement) and negative hallucinations from 2.95 to 0.68 (**76% reduction**).

### Self-consistency sampling

**Wang et al. (ICLR 2023)** "Self-Consistency Improves Chain of Thought Reasoning in Language Models" (arXiv:2203.11171) shows majority voting across multiple reasoning paths improves GSM8K by **+17.9%**, SVAMP by **+11.0%**, and AQuA by **+12.2%** over greedy CoT. **Optimal sample count**: **5-10 samples** capture most improvement with diminishing returns clearly evident by 40 samples. AWS analysis confirms "5-10 paths are typically enough." The **RASC framework** (2025) achieves **70-80% sample reduction** through dynamic early stopping while maintaining accuracy.

### SWE-bench verification methodology

SWE-bench validates solutions via unit tests (FAIL_TO_PASS tests that fail before fix and pass after, plus PASS_TO_PASS regression tests). **SWE-bench Verified** uses 500 human-validated samples from 93 Python developers. Critical findings: **38.3%** underspecified problem statements, **61.1%** unit tests may reject valid solutions, **7.2-8.4%** plausible but incorrect patches (PatchDiff study), and **~31%** weak test oracles. Resolution rate overestimation reaches **3.8-5.2% absolute drop** in empirical studies.

---

## 7. Command enforcement and permissions

### Claude Code permission model

Claude Code implements an **allow/ask/deny permission triad** with processing order: PreToolUse Hook → Deny Rules → Allow Rules → Ask Rules → Permission Mode Check. **Deny rules take highest precedence** and override all others. Permission categories: read-only operations (no approval required), bash commands (permanent per project+command approval), and file modifications (session-end approval). Permission modes include `default`, `acceptEdits`, `plan` (read-only), and `bypassPermissions` (requires safe environment). Enterprise deployments use `managed-settings.json` which **cannot be overridden** by user/project settings.

### NVIDIA NeMo Guardrails

**Rebedea et al. (EMNLP 2023)** "NeMo Guardrails: A Toolkit for Controllable and Safe LLM Applications with Programmable Rails" (arXiv:2310.10501) supports five rail types: input rails (reject/alter user input), dialog rails (control canonical messages), retrieval rails (filter RAG chunks), execution rails (validate action I/O), and output rails (final safety checks). **Colang 2.0** provides a Pythonic modeling language with event-driven interaction, pattern matching, and asynchronous action execution. Benchmarks show hallucination detection at **70%** (davinci-003) to **95%** (GPT-3.5-turbo) with orchestrating up to 5 GPU-accelerated guardrails adding only **~0.5s latency**.

### AWS Bedrock guardrails

Seven policy types: content filters (hate, insults, sexual, violence, misconduct, prompt attack), prompt attack detection, denied topics, word filters, sensitive information (PII), contextual grounding, and automated reasoning. Filter strength levels: None, Low (HIGH confidence only), Medium (HIGH+MEDIUM), High (all confidence levels). AWS claims guardrails block **up to 88% of harmful content** with **99% accuracy** for Automated Reasoning validation.

### Principle of least privilege

**Saltzer & Schroeder (1975)** "The Protection of Information in Computer Systems" (*Proceedings of the IEEE*, Vol. 63, No. 9) established: "Every program and every user should operate using the least set of privileges necessary to complete the job." The eight design principles include least privilege, economy of mechanism, **fail-safe defaults** (base access on permission, not exclusion), **complete mediation** (every access must be checked), and separation of privilege.

### Pre-execution validation

**Transactional sandboxing** (arXiv:2512.12806) treats every LLM tool-call as an **atomic ACID transaction**, achieving **100% interception rate** for high-risk commands, **100% rollback success**, with only **14.5% performance overhead**. Implementation methods include containers (namespace isolation, low overhead), WebAssembly/Pyodide (browser sandbox, fast instantiation), user-mode kernels (system call interception), and VMs (maximum isolation).

---

## 8. Output management

### Aider edit format effectiveness

The **3× improvement claim is validated**: unified diffs reduce GPT-4 Turbo's "lazy coding" from 12/89 tasks to 4/89 tasks on the 89-task Python refactoring benchmark. Benchmark scores improved from **20% to 61%** (3×+) with unified diff format on GPT-4-1106. Key design principles: use **familiar** formats GPT has seen in training (unified diffs are common via `git diff`), avoid line numbers (GPT is "terrible" at working with them), and encourage **function/method-level** edits over line-by-line changes. Aider's flexible patching strategies reduce editing errors by **9×**.

### Architect/Editor split pattern

The **85% SOTA claim is validated** from Aider's September 2024 benchmark: o1-preview + o1-mini (Editor) achieved **85.0%**, matching o1-preview + DeepSeek. Practical configurations include Claude 3.5 Sonnet as both Architect and Editor at 80.5% (versus 77.4% solo baseline). The pattern separates reasoning (Architect) from formatting (Editor), enabling use of strong reasoning models (o1, R1) paired with cost-effective editors (DeepSeek, Sonnet).

### Search/replace vs unified diff

Unified diffs are more familiar from training data (`git diff` default) and reduce lazy coding by 3×. Search/replace has lower parsing errors but is more prone to lazy output. Both require robust flexible parsing—Aider interprets each diff hunk as a search/replace operation with fuzzy matching using Levenshtein distance.

### AST-based code chunking

**Tree-sitter** achieves **36× speedup** over traditional parsers. The **cAST** algorithm (arXiv:2506.15655v1) applies recursive split-then-merge on ASTs, yielding **average 5.5 point gains** on RepoEval for StarCoder2-7B. Optimal chunk boundaries: function/method level for semantic coherence, **100-250 AST nodes** for refactoring tasks. AST-based chunking preserves semantic boundaries and produces syntactically valid chunks, unlike line-based or token-based approaches.

### Response continuation protocols

Aider implements infinite output via **prefilling**—when output hits token limits, it initiates another request with the partial response prefilled, prompting continuation. Detection uses `finish_reason`: `"stop"` indicates natural completion, `"length"` indicates truncation requiring continuation. State preservation best practices: maintain conversation history with system message always preserved, track partial code blocks to avoid mid-function cuts, and keep state minimal (title, section outline, summary of last snippet).

---

## 9. Adversarial personas and red team methodology

### Academic red teaming research

**Perez et al. (2022)** "Red Teaming Language Models with Language Models" (arXiv:2202.03286) demonstrated using LLMs to automatically generate adversarial test cases, uncovering "tens of thousands of offensive replies" in 280B parameter chatbots. **Hong et al. (2024)** "Curiosity-driven Red-teaming for Large Language Models" (arXiv:2402.19464) addresses limited test case diversity through curiosity-driven exploration. A 2024 framework study (arXiv:2512.20677) identified **47 distinct vulnerabilities** including 21 high-severity findings across six threat categories: reward hacking, deceptive alignment, data exfiltration, sandbagging, inappropriate tool use, and chain-of-thought manipulation.

### Anthropic's red team methodology

Anthropic's Frontier Red Team (~15 researchers under policy division) uses **Policy Vulnerability Testing (PVT)** with external subject matter experts, **frontier threats red teaming** (150+ hours with biosecurity experts using bespoke secure interfaces), and **automated evaluations** scaling from qualitative to benchmark testing. Key metrics: **200-attempt attack campaigns** (versus single-attempt metrics), degradation curves, and **96% prompt injection prevention** in tool use scenarios (99.4% with shields).

### Guardrail bypass research

**Hackett et al. (2025)** "Bypassing LLM Guardrails: An Empirical Analysis" (arXiv:2504.11168) tested Microsoft Azure Prompt Shield, Meta Prompt Guard, NVIDIA NeMo Guard, and others. Attack vectors achieving up to **100% evasion**: emoji smuggling, zero-width characters, Unicode tags, homoglyphs, and AML perturbations. **"No single guardrail consistently outperformed across all attack types."** **DualBreach** (arXiv:2504.18564) achieved **93.67% dual-jailbreak success rate** against GPT-4 with Llama-Guard-3 in average 1.77 queries.

### Security persona effectiveness

OWASP integration reduces vulnerabilities by **up to 36%** during development. Mean Time to Remediate (MTTR) industry average: 57.5 days; teams with real-time feedback cut MTTR by **up to 92%**. 2024 Veracode study: ~45% of AI-generated code contains OWASP Top-10 flaws. Manual review catches business logic flaws; SAST tools catch common pattern flaws (SQL injection, XSS).

---

## 10. Principle application order

### Security-first tiered enforcement

Evidence supports **security principles taking highest precedence** based on Saltzer & Schroeder's fail-safe defaults: base access on permission rather than exclusion, where "errors in permission-granting tend to fail by refusing (detectable), while errors in exclusion-granting fail by allowing (may go unnoticed)." Claude Code's processing order (Deny → Allow → Ask) implements this principle with deny rules taking absolute precedence.

### Veto principle effectiveness

Veto mechanisms allow any single safety check to halt operations regardless of other permissive signals. Implementation patterns include **fail-secure** (on error, deny all further progress) and **separation of privilege** (require multiple conditions for access—"a protection mechanism that requires two keys to unlock it is more robust"). Anthropic's Constitutional Classifiers implement multiple layers each with veto power; safety scores degrade from 0.87 to 0.41 under optimized attack, demonstrating need for layered defenses.

### Quality gate optimization

Research on multi-phase testing validates the pattern: internal qualitative red teaming → crowdsourced testing → automated evaluations, with each phase catching different vulnerability types. The 2025 automated framework study demonstrates value of structured threat categorization with tiered severity assessment. **Complete mediation** (every access must be checked) supports checking all principles rather than sampling, while **economy of mechanism** (keep design simple) argues for limiting principle count to essential checks.

**Recommended order**: (1) Security/safety veto checks, (2) Permission/authorization validation, (3) Input validation and normalization, (4) Quality/style principles, (5) Output verification. Any security veto immediately halts processing; other principles apply in order with accumulated findings.

---

## Summary of key validated thresholds

| Configuration Area | Recommended Value | Source |
|--------------------|-------------------|--------|
| Code similarity threshold | 70% | SourcererCC (ICSE 2016) |
| Minimum duplicate tokens | 100 | PMD CPD default |
| API timeout | 600 seconds (10 min) | Anthropic/OpenAI SDK |
| Max retry attempts | 2-3 | SDK defaults |
| Max backoff | 20 seconds | AWS SDK |
| Circuit breaker error threshold | 50% | Hystrix/resilience4j |
| Attention sink tokens | 4 | StreamingLLM (ICLR 2024) |
| Compression ratio achievable | 20× | LLMLingua (EMNLP 2023) |
| Self-consistency samples | 5-10 | Wang et al. (ICLR 2023) |
| RAG chunk size (balanced) | 512 tokens | Multiple studies |
| Chunk overlap | 10-20% | Industry consensus |
| Query placement improvement | 30% | Anthropic documentation |
| AST chunk size | 100-250 nodes | Aider benchmark |
| Semantic entropy samples | ~5 | Nature 2024 |
| CoVe hallucination reduction | 76% | Meta/FAIR (ACL 2024) |

All major claims in the framework configuration have been validated against peer-reviewed research from top venues (Nature, ICLR, NeurIPS, EMNLP, ACL, TACL, ICSE) and production system documentation (Anthropic SDK, OpenAI SDK, AWS, NVIDIA). The "every 2000 tokens" instruction reinforcement interval was **not validated** in academic literature and should be treated as a heuristic requiring empirical tuning per use case.