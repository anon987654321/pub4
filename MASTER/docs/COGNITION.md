# MASTER cognition

MASTER now has a persistent, inspectable cognitive layer inspired by research on
Global Workspace Theory, predictive processing, active inference, affective
computing, autobiographical memory, and recurrent cognitive architectures.

This implementation is deliberately modest. It does **not** claim that MASTER is
conscious. Its consciousness-related measurements are engineering proxies that
make internal state observable and testable.

## Loop

```text
world/event
    ↓
perception
    ↓
prediction error
    ↓
salience / attention
    ↓
global workspace
    ↓
affect / homeostasis
    ↓
self model
    ↓
metrics + persistent state
    ↓
reflection
    ↓
long-term memory
```

## Persistent state

The runtime stores cognitive state in `.master/cognition/state.yml`, which is
workspace-local state and should not be committed. The state contains:

- identity and continuity
- affect: valence, arousal, novelty, uncertainty
- drives: safety, coherence, curiosity, agency, affiliation
- global workspace entries
- event predictions
- self-model beliefs
- reflective thoughts
- integration, attention, and prediction-error proxies

Existing `Master::Ground::Memory` remains the long-term memory system. Cognitive
reflections are written into that memory store rather than replacing it.

## Important distinction

A recurrent loop, memory, self-description, affect model, or integration score
is not by itself evidence of subjective experience. MASTER should therefore
report these as **proxies** and preserve the uncertainty in its own self-model.
