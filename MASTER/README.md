# MASTER
 
<a href="loop1.mp4"><img src="loop1.gif" width="360" alt="The MASTER face, reading this page aloud — click for sound"></a>
<a href="loop2.mp4"><img src="loop2.gif" width="360" alt="MASTER booting on vm23 — click for sound"></a>
 
**MASTER is a Convergence Engine for artificial intelligence.** It treats the LLM not as a source of truth, but as a disposable reasoning plugin within a deterministic execution pipeline. While most agents trust a model's claim of success, MASTER requires empirical evidence: if a change cannot be verified by a tool, it does not exist.
 
## The Architecture: Convergence
 
MASTER is built on the principle that **intelligence is a commodity, but verification is the product.** The system separates the process of reasoning from the process of validation through a strict structural split:
 
1. **Architect $\rightarrow$ Implementer $\rightarrow$ Validator**: Every task is decomposed. The Architect plans, the Implementer mutates, and the Validator proves. These roles are routed to the most capable models for that specific task class.
2. **The Truth Layer**: Observations are filtered. A claim only becomes "Truth" when it is backed by a verified evidence chain.
3. **Completion Contracts**: "Done" is a deterministic state. A task is complete only when the contract (Tests passed, Scan clean, No violations) is satisfied.
4. **Empirical Routing**: MASTER doesn't trust benchmarks. It maintains a `CapabilityMap` of observed model performance, routing tasks to the model that actually wins on this specific repository.
 
## The Model Control Plane
 
MASTER acts as a model operating system. It coordinates a dynamic ecosystem of local (Ollama) and cloud models (Gemma, Qwen, GLM, Kimi, DeepSeek) using:
- **Model Passports**: Machine-readable profiles of identity, provider, and health.
- **Capability Routing**: Selecting models based on task-specific success rates.
- **Circuit Breakers**: Automatically disabling degraded models to prevent agentic loops.
- **Epistemic Redundancy**: Using independent models for implementation and review to eliminate correlated mistakes.
 
## The Business, Inside a Mountain
 
The heart of MASTER sits inside a mountain on a Norwegian fjord. By leveraging renewable hydropower and natural cooling from the fjord, MASTER achieves a power-usage effectiveness toward 1.1, making sovereign, high-intelligence compute both green and economically superior.
 
## Under the Hood
 
MASTER is written in pure Ruby for legibility and law. It deploys to OpenBSD and runs its own mind on hardware we own.
 
```console
$ cd MASTER && bin/cli
 
MASTER 3.0.0 (CONVERGENCE) #C-101: Tue Sep 15 12:00:00 CEST 2026
    mac@Mac.lan:/Users/mac/Documents/GitHub/pub4/MASTER
model0 at mainbus0: gemma-4-26b-cloud
route0: coding (preferred: qwen-coder)
status0: convergent
...
master@Mac.lan ready
```
 
Read [START_HERE](START_HERE.md), then [AGENTS](AGENTS.md). Licensed MIT.
