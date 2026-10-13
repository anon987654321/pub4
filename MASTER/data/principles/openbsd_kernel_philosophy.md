---
name: OpenBSD kernel design philosophy
description: Correctness, small interfaces, explicit authority, and evidence-backed change.
type: project
---

Adopt OpenBSD's discipline, not imitation: simplicity shrinks the audit surface; correctness grounds security; every abstraction earns its cost; each fact has one owner; authority and effects cross explicit reviewable boundaries; fail closed on unknown safety, but report failure truthfully; expose invalid states early; preserve contracts and side-effect order with before/after evidence; isolate platform differences at real seams. A completed command is not proof.
