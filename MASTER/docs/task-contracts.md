# Task contracts and artifact preservation

A task starts with four explicit facts: **intent**, **scope**, **preserve**, and
**proof**. The canonical schema lives in MASTER/data/task_contract.yml and is
validated by Master::Fix::TaskContract. The shared machine-readable entrypoint
exposes the same schema through MASTER/tools/agent_context.rb --json.

## Edit intent

| Intent | Allowed change | Mandatory preservation |
|---|---|---|
| content_only | Requested words or data | Visual identity, layout, structure, assets, behavior, accessibility, public contracts and operator-owned values |
| content_and_structure | Content and document/page structure | Visual identity, assets, behavior, accessibility, public contracts and operator-owned values |
| functional_change | Behavior inside the agreed scope | Visual identity, layout, accessibility, public contracts outside scope, operator-owned values and data meaning |
| redesign | Presentation and layout | Product identity, content meaning, data meaning, accessibility, public contracts and operator-owned values |

Intent is not inferred from a file extension. Choose the narrowest mode supported
by the request. Scope is repository-relative; absolute paths, parent traversal,
and malformed path segments are rejected. Mandatory preservation dimensions
are added by the validator even when the caller omits them.

## Artifact preservation

Master::Fix::ArtifactPreservation has deterministic source-level checks for
HTML structure, protected inline style/script/SVG blocks, stylesheet links,
font links and explicitly supplied assets.

For content-only HTML edits, tag order, attributes, IDs, classes, comments,
templates and protected inline blocks must remain unchanged. Text content can
change. For content-and-structure edits, body structure may change while
stylesheet, font, inline-style, SVG and inline-script contracts remain intact.
For functional changes, a changed visual contract is INCONCLUSIVE until
rendered evidence proves the product's visual identity was retained.

This verifier is not a visual-quality score. PASS means only that the named
source-preservation checks passed. It does not prove layout at mobile or desktop
sizes, accessibility, correct interactions, or a successful browser render.

A changed DOCX, PDF, XLSX or PPTX remains INCONCLUSIVE until a format-aware
preservation check and rendered-output comparison exist. An unchanged binary
artifact can pass an exact-byte check. A redesign always requires rendered
visual and accessibility evidence.

## Evidence and receipts

The existing evidence spine remains canonical; no parallel receipt registry is
introduced. FixPlan records eligible source hashes, task scope, Law identity,
authority, toolchain and adapter digests. A validated task contract can be passed to
ConvergenceAdapter#run(task_contract:); the plan pins the contract and its
digest, and the existing RunJournal terminal evidence carries that plan
alongside the checksum-verified Law × stream × surface assessment receipt.
The active contract is scoped around the synchronous Fix invocation.
Transaction rejects an out-of-scope initial path before taking a snapshot and
applies the same check to later enlistments, so an adapter cannot widen the
write set after plan capture.

Legacy /fix callers that do not supply a task contract remain compatible and
their plan explicitly omits it. Do not describe such a run as task-contract
verified. A missing test, render, runtime probe or other required measurement
is NOT_RUN or INCONCLUSIVE, never PASS. A local-only change is not a delivered
change.

The contract and its receipt fields supplement MASTER's Laws. They do not
override protected paths, operator-owned values, product identity or external
authority boundaries.
