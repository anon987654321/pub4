# MASTER cognition

MASTER carries a persistent, inspectable cognitive layer: recurrent perception,
a salience model, a bounded working set, homeostatic affect, an explicit
self-model, prediction error, and reflection written back into long-term memory.
The ingredients are borrowed from global workspace theory, predictive processing,
active inference and affective computing.

It does not claim MASTER is conscious. The consciousness-adjacent numbers are
engineering proxies whose only purpose is to make internal state observable and
testable, and the self-model records `phenomenal_consciousness: unknown` as a
belief rather than as a comment, because `soul.yml` forbids claiming what has
not been shown and no amount of running this code can show that one.

## The loop

An event arrives on the bus. Perception scores how surprising it is against when
that event last fired, attention turns surprise and arousal into salience, the
working set keeps the twelve most salient entries, affect moves within bounds,
the self-model records what was seen, and the metrics are recomputed. Every
sixteenth tick the layer writes a reflection into `Ground::Memory`, which remains
the long-term store — cognition adds to it and replaces nothing.

## What runs where

Perception runs inside the bus handler and never touches disk. `tick!` is the
only writer and the only publisher. Both of those are deliberate: a bus handler
runs inside every publish, a scan publishes thousands of events, and a layer that
serialised its state per event would spend a scan writing a mood to YAML. It also
subscribes with `**` rather than `*`, because the bus compiles `*` to `[^:]*` and
a single star would have missed every colon-namespaced event — which is nearly
all of them.

The cost of persisting on tick rather than on perception is that a crash loses
the observations since the last tick. Those live in the working set and nowhere
else, which is the point of a working set.

## State

`.master/cognition/state.yml`, which `.gitignore` already excludes. It holds
identity and continuity, affect, drives, the working set, self-model beliefs,
reflections, and the integration, attention and prediction-error proxies.

## The distinction worth keeping

A recurrent loop, a memory, a self-description, an affect model and an
integration score are not evidence of subjective experience, individually or
together. MASTER reports them as proxies and keeps the uncertainty in its own
self-model, which is the only honest place for it.
