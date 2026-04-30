# Empirical foundations of AI code generation best practices

**The thresholds and heuristics commonly cited in software engineering and AI/LLM code generation frameworks rest on foundations of varying solidity.** While some rules—like the 70% clone detection threshold—have strong empirical validation from top venues, others—like McCabe's cyclomatic complexity ≤10 or 97% test coverage targets—lack rigorous support. This report synthesizes peer-reviewed research from ICSE, FSE, IEEE TSE, Nature, ICLR, and related venues (2015-2025) to establish what the evidence actually says.

## Code complexity thresholds show weaker support than assumed

McCabe's 1976 proposal of **cyclomatic complexity ≤10** was explicitly described as "a reasonable, but not magical, upper limit"—a practical suggestion, not an empirically derived threshold. Subsequent research has been remarkably unkind to this metric:

The most damning evidence comes from **Peitek et al.'s fMRI study (ICSE 2021)**, which found that McCabe's complexity "consistently lacked any significant correlation" with observed measures of cognitive load and behavioral performance in programmers. Instead, vocabulary size (Halstead metrics) and data-flow metrics showed the strongest correlations with brain activation during comprehension.

Large-scale statistical analyses paint a similar picture. **Gil & Kemerer's comprehensive study** concluded that cyclomatic complexity "can be said to have absolutely no explanatory power of its own" beyond lines of code, with the linearity between CC and LOC being "severely underestimated." Shepperd's critique demonstrated that CC is "based on poor theoretical foundations" and is often outperformed by simple LOC for defect prediction.

**Nesting depth** shows considerably stronger empirical support. A 2017 EMSE study identified nesting depth as one of only two characteristics that "markedly influence complexity growth." A University of Twente study (2024) found each unit increase in nesting depth **decreases odds of defect detection during code review by ~8%**. The ≤3 levels heuristic, while not precisely validated, aligns with this research direction.

For **function length**, the evidence suggests a U-shaped relationship with defects: very small and very large functions both have higher defect density, with a sweet spot around **5-10 lines**. The commonly cited 20-line or 50-line limits lack specific empirical derivation.

| Metric | Common Threshold | Empirical Support |
|--------|------------------|-------------------|
| Cyclomatic complexity | ≤10 | **Weak** — no better than LOC; no fMRI correlation |
| Function length | 20-50 lines | **Moderate** — sweet spot appears to be 5-10 lines |
| Nesting depth | ≤3 levels | **Moderate** — correlates with defect detection difficulty |
| Cognitive complexity | ≤15 | **Moderate** — correlates with comprehension time |

## Test coverage targets lack rigorous validation

Neither **97% nor 80%** test coverage has peer-reviewed empirical support as an optimal threshold. The landmark **Inozemtseva & Holmes (ICSE 2014)** study—which won the Most Influential Paper Award in 2024—found only "low to moderate correlation" between coverage and test effectiveness when controlling for test suite size.

Their critical insight: stronger coverage types (branch, MC/DC) provide **no greater insight into effectiveness than weaker types** (statement coverage). Coverage is useful for identifying under-tested code but "should not be used as a quality target because it is not a good indicator of test suite effectiveness."

**Mutation testing research** provides a more nuanced picture. **Just et al. (FSE 2014, Distinguished Paper Award)** found that **73% of real faults are coupled to generated mutants**, and correlation between mutation score and fault detection is stronger than between statement coverage and fault detection. However, Papadakis et al. (ICSE 2018) showed that even mutation score correlations become "weak when controlling for test suite size."

Industry evidence from **Google (ICSE-SEIP 2018)** shows mutation testing is feasible at scale (6,000+ engineers, 14,000+ code authors), with statement coverage "predicting mutation kills best." Facebook's study (ICSE-SEIP 2021) found that **more than half of mutants survived their rigorous test suite**, with only ~50% of developers likely to act on surfaced test gaps.

The evidence points to coverage as a **necessary but not sufficient condition**—useful for finding gaps, not as a quality gate.

## Generating multiple alternatives has strong empirical backing

Research strongly supports generating multiple design alternatives before committing—though the specific "**15 alternatives**" rule appears to be a practitioner heuristic rather than an empirically validated number.

**Dow et al.'s parallel prototyping study (ACM TOCHI, 2010)** provides the clearest quantitative evidence. In a controlled experiment with 33 participants:

- Parallel condition (3 prototypes simultaneously) vs. serial condition (one at a time)
- Click-through rate: **445 vs 398 per million impressions** (p<0.05)
- Time on target site: **31.3 vs 12.9 seconds** (p<0.05)  
- Self-efficacy increase: **+2.5 vs +0.4 points** (p<0.05)
- Zero parallel participants reported feedback as "negative" vs. 8/17 serial participants

The mechanism is **comparison-enabled learning**: parallel prototyping helps designers learn key principles by comparing alternatives simultaneously, avoiding "hill-climbing to local rather than global optima."

**Design fixation research** (Jansson & Smith, 1991) established that both novice and expert designers exhibit "blind, sometimes counterproductive adherence to a limited set of ideas"—and crucially, years of experience provide no protection. **Self-generated first ideas create fixation** just as strongly as provided examples (Daly et al., 2020).

Simonton's **equal-odds rule** demonstrates that the probability of producing a masterpiece is proportional to total output—"quantity breeds quality." This is why divergent thinking (generating many solutions) precedes convergent thinking (selecting the best) in creative problem-solving frameworks.

## Cognitive bias mitigation strategies with empirical validation

**Mohanani et al.'s systematic mapping (IEEE TSE 2020)** identified 65 articles investigating 37 cognitive biases in software engineering. The most-studied biases are anchoring, confirmation bias, optimism bias, and overconfidence—but research on mitigation techniques remains surprisingly scarce.

**Anchoring bias** shows the largest documented effect sizes. **Shepperd et al. (SAC 2018)** conducted experiments with 410 software developers and found:
- Anchoring effect on estimates: **Cohen's d = 1.19** (large effect)
- After debiasing workshop: **d = 0.72** (reduced but still present)
- Threefold reduction in estimate variance after intervention

**Confirmation bias** in testing has been extensively studied. Salman et al.'s family of experiments (IEEE TSE 2023) found that time pressure significantly promotes confirmation bias, with testers designing significantly more confirmatory than disconfirmatory test cases regardless of pressure. Their recommendation: center manual testing on disconfirmatory test cases while automating confirmatory testing.

**Chattopadhyay et al. (ICSE 2020, Distinguished Paper Award)** conducted field studies observing developers in situ and found that **~70% of reversed actions were associated with at least one cognitive bias**, with 45.7% of all developer actions showing bias associations.

Validated mitigation strategies with empirical support include:
- **Awareness training workshops** (reduces anchoring effect by ~40%)
- **Planning poker** for estimation (prevents one estimate from anchoring others)
- **Generating multiple options** before deciding
- **"Ideas" vs. "requirements" framing** (reduces requirements fixation, improving design originality)
- **Pair programming** (navigator can identify reasoning errors)

## The 70% clone detection threshold has strong validation

**Sajnani et al.'s SourcererCC (ICSE 2016)** established the **70% similarity threshold** as optimal for general clone detection, achieving **86% precision and 86-100% recall** for Type-1/2/3 clones. This is one of the best-validated thresholds in the literature.

The threshold emerged from convergent evidence across multiple tools and benchmarks:
- SourcererCC uses 70% default
- NiCad uses 70% similarity (achieving 100% recall on Type-1/2, 95% on strongly-similar Type-3)
- BigCloneBench evaluation uses 70% coverage matching

Clone type performance at 70% threshold:
| Clone Type | Similarity Range | Typical Recall |
|------------|------------------|----------------|
| Type-1 (exact) | 100% | 100% |
| Type-2 (normalized) | 100% after normalization | 93-100% |
| VST3 (very similar) | 90-100% | 86-99% |
| ST3 (similar) | 70-90% | 61-95% |
| MT3/Type-4 | <70% | <1% (expected) |

Lowering the threshold increases false positives dramatically; raising it misses meaningful Type-3 clones. The 70% figure represents a validated precision-recall tradeoff.

## LLM attention patterns reveal critical context management principles

Three key papers establish the empirical foundation for understanding how LLMs handle context:

**"Lost in the Middle" (Liu et al., TACL 2024)** discovered the **U-shaped attention curve**: performance is highest when relevant information occurs at the **beginning or end** of input context, and significantly degrades when information is in the middle. This holds across GPT-3.5-Turbo, Claude, and long-context models. The pattern mirrors the human serial position effect (primacy and recency).

**"Attention Sinks" (Xiao et al., ICLR 2024)** explains why: initial tokens receive disproportionately high attention even when semantically unimportant. The Softmax mechanism requires attention scores to sum to 1, causing models to "dump" excess attention on early tokens. **StreamingLLM** demonstrated that keeping just 4 "sink tokens" plus a sliding window allows stable processing of **up to 4 million tokens** with **22.2x speedup**.

**"Detecting Hallucinations with Semantic Entropy" (Farquhar et al., Nature 2024)** provides a principled method for identifying unreliable generations. The approach measures uncertainty over *meanings* rather than token sequences, achieving **0.790 AUROC** averaged across 30 task/model combinations (vs. 0.691 for naive entropy). Using 10 generations reliably estimates semantic entropy for confabulation detection.

Practical implications for code generation:
- Place critical code (function signatures, imports) at **prompt beginning and end**
- Use ~4 initial tokens as attention anchors
- Sample multiple completions and check semantic consistency
- Use retrieval reordering to place relevant code at optimal positions

## Working memory research supports the 4±1 rule for code design

Miller's famous "7±2" (1956) has been **revised downward to 4±1 chunks** by modern research. Cowan's comprehensive reassessment (Behavioral and Brain Sciences, 2001) showed that when rehearsal and grouping strategies are prevented, true central capacity is **3-5 chunks (average ~4)**.

This directly applies to code comprehension. Burkhardt et al. (2002) demonstrated that programmers construct two representations: the program model (what code says) and the situation model (the domain problem). Both compete for working memory resources.

Evidence-based recommendations for code design:

| Aspect | Cognitive Basis | Recommendation |
|--------|----------------|----------------|
| Function parameters | 4±1 chunk limit | ≤4-5 parameters |
| Variables in active scope | Working memory capacity | Limit to ~4 simultaneous |
| Nesting depth | Each level adds load | ≤3-4 levels |
| Identifier names | Full words chunk better | Use complete words, not abbreviations |

**Chunking** is the key mechanism for expanding effective capacity. Experienced developers read `for (i = 0; i < N; i++)` as a single chunk ("loop over N items"), while novices parse each element separately. This is why idiomatic patterns, consistent conventions, and meaningful groupings reduce cognitive load.

## Security principles from Saltzer & Schroeder remain foundational

**Saltzer & Schroeder (IEEE 1975)** established eight design principles that remain the foundation of security engineering, with 2,777+ citations:

1. **Least privilege**: "Every program and every user should operate using the least set of privileges necessary to complete the job"
2. **Fail-safe defaults**: "Base access decisions on permission rather than exclusion"
3. **Complete mediation**: "Every access to every object must be checked for authority"
4. **Economy of mechanism**: "Keep the design as simple and small as possible"
5. **Open design**: "The mechanisms should not depend on ignorance of potential attackers"
6. **Separation of privilege**: "A protection mechanism requiring two keys is more robust than one"
7. **Least common mechanism**: "Minimize shared mechanisms between users"
8. **Psychological acceptability**: "The human interface must be designed for ease of use"

Empirical validation varies by principle. **Least privilege** has strong support: Motiee et al. (SOUPS 2010) found 69% of participants failed to apply it correctly; enforcement algorithms achieve 96-98% accuracy. **Input validation** effectiveness is well-documented: Scholte et al. (2012) showed "most SQL injection and significant XSS vulnerabilities can be prevented using straightforward validation mechanisms."

Schneider's 2012 retrospective found that separation of privilege and least privilege have "become staples of practice," while simplicity and complete mediation have "failed to thrive."

## Quality metrics that actually predict defects

**Process metrics consistently outperform static code metrics** for defect prediction. The most surprising finding comes from Microsoft Research (**Nagappan, Murphy, & Basili, ICSE 2008**): organizational metrics (team structure, communication patterns) predicted failures **8% better** than code-based metrics.

| Predictor Type | Precision | Recall |
|---------------|-----------|--------|
| Organizational structure | **86.2%** | **84.0%** |
| Code churn (relative) | 78.6% | 79.9% |
| Test coverage | 83.8% | 54.4% |
| Code complexity | 79.3% | 66.0% |

**Code churn** (Nagappan & Ball, ICSE 2005) discriminates between fault/non-fault-prone components with **89% accuracy** when using relative (not absolute) measures.

**DORA metrics** research (Forsgren, Humble, Kim) demonstrates that speed and stability are not tradeoffs—elite performers excel at both. Teams excelling at deployment frequency, lead time, change failure rate, and mean time to recovery show **1.8x better customer satisfaction**. However, the methodology relies heavily on self-reported survey data.

Code review effectiveness research from **Google (Sadowski et al., ICSE 2018)** analyzing 9 million reviewed changes found that **97% of developers** express satisfaction with code review, though the primary benefit may be knowledge transfer rather than bug detection—up to 75% of comments affect evolvability/maintainability rather than addressing bugs directly.

## LLM prompting research provides quantitative guidance

**Self-consistency (Wang et al., ICLR 2023)** achieves significant improvements by sampling diverse reasoning paths and selecting via majority voting:
- GSM8K: **+17.9%** improvement
- SVAMP: **+11.0%** improvement
- Optimal sampling temperature: **0.5-0.7**

**Chain-of-Verification (Dhuliawala et al., ACL 2024)** reduces hallucinations through a four-step process (draft → plan verification questions → answer independently → generate verified response), achieving **+23% F1** improvement on closed-book QA.

**Structured Chain-of-Thought for code (Li et al., ACM TOSEM 2023)** outperforms standard CoT by up to **13.79% Pass@1** on code generation benchmarks by using programming structures (sequence, branch, loop) as intermediate reasoning steps.

Temperature optimization research shows:
- **Low temperature (0.0-0.2)**: Best for deterministic code completion
- **Adaptive temperature**: Higher for "challenging tokens" (function headers, block beginnings); lower for predictable tokens
- **No statistically significant impact** in 0.0-1.0 range for many tasks

For few-shot prompting, **selection matters more than quantity**: carefully chosen demonstrations improve bug fixing exact match by **175.96%**, while more examples can actually degrade performance if prompts become too complex. **2-3 high-quality, diverse examples** typically suffice.

## Conclusions and evidence quality assessment

The evidence quality varies substantially across commonly cited thresholds:

**Strong empirical support:**
- 70% clone detection threshold (multiple tools, BigCloneBench validation)
- 4±1 working memory chunks (decades of cognitive science)
- Parallel prototyping benefits (controlled experiments with effect sizes)
- Anchoring bias magnitude (d=1.19) and debiasing effectiveness
- LLM attention patterns (U-curve, attention sinks, semantic entropy)

**Moderate support with caveats:**
- Nesting depth ≤3 (correlational studies, not causal validation)
- Process metrics > product metrics for defect prediction
- Self-consistency and CoT prompting improvements

**Weak or contested support:**
- Cyclomatic complexity ≤10 (no better than LOC; no neural correlation)
- Specific test coverage percentages (80%, 97%)
- Function length limits (20 lines, 50 lines)

Practitioners should treat strongly-supported thresholds as empirically grounded defaults while recognizing that context-dependent calibration may be necessary. Weakly-supported heuristics remain useful as rules of thumb but should not be treated as evidence-based requirements.