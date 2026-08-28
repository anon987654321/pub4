# frozen_string_literal: true

module Master
  module Trace
    module Snapshot
      # Preamble embedded at the top of MASTER/OPERATOR snapshot markdown artifacts.
      # Instructs downstream AI agents how to consume the digest before the tree/codebase.
      module AgentGuide
        module_function

        # full_inline: true describes a pack with no per-file size cap; false
        # describes Snapshot::Publisher's boot-context digest, which still lists
        # oversized files rather than pasting them (kept small on purpose). Only
        # the false branch has a caller: the uncapped pack is `pub4 snapshot`,
        # which collects and renders its own.
        def lines(label: "MASTER", full_inline: false)
          header_lines(label) + orient_lines + cross_reference_lines +
            execution_trace_lines + architecture_assessment_lines + rehydrate_lines(full_inline:)
        end

        def header_lines(label)
          [
            "## Agent analysis protocol",
            "",
            "This document is a **verbatim codebase mirror** for `#{label}`. Treat every fenced",
            "block as source of truth — not a summary. Work through it in this order:",
            "",
          ]
        end

        def orient_lines
          [
            "### 1. Orient",
            "- Read the header (generation metadata, file count, policy) and **Tree** before opening any file block.",
            "- Note topology: where boot, routing, data, UI, deploy, and tests live relative to each other.",
            "",
          ]
        end

        def cross_reference_lines
          [
            "### 2. Word-for-word read + cross-reference",
            "- Read each `## \\`path\\`` section **line by line**; do not skim or paraphrase from headings alone.",
            "- **Cross-reference** symbols across files: follow requires/imports, route → controller → service",
            "  chains, YAML keys → Ruby readers, JS event names → subscribers, CLI commands → dispatchers.",
            "- When the same name recurs in multiple places, reconcile definitions — flag drift immediately.",
            "",
          ]
        end

        def execution_trace_lines
          [
            "### 3. Deep execution traces (start → finish)",
            "- Pick critical paths (boot, request/response, scan/fix loop, deploy, TTS/chat SSE, face render)",
            "  and trace **one complete path** from entrypoint through every hop to side effects/output.",
            "- For each hop record: caller, callee, inputs, branching conditions, failure modes, and what",
            "  state mutates (files, DB, env, in-memory singletons, event bus).",
            "- Prefer evidence from this snapshot over assumptions from training data.",
            "",
          ]
        end

        def architecture_assessment_lines
          [
            "### 4. Architecture & design assessment",
            "- **Structure**: layering, boundaries, coupling, duplication, god objects, require cycles.",
            "- **Semantics**: naming honesty, invariants, tenancy/auth, error taxonomy, idempotency.",
            "- **Design**: UI philosophy, data flow, extension points, config vs code, deploy topology.",
            "- **Smells & oddities**: dead code, parallel implementations, magic numbers, commented-out paths,",
            "  inconsistent conventions, docs that disagree with code.",
            "- **Gaps & friction**: missing tests, unwired features, slow/hidden boot steps, operator pain,",
            "  places where a human or agent gets stuck without tribal knowledge.",
            "",
          ]
        end

        # Which step-4 note applies depends on which kind of pack this is; the
        # surrounding template does not otherwise vary. Split out so this method is
        # the template and that one is the choice.
        def binary_inlining_note(full_inline:)
          unless full_inline
            return "4. This is the small boot-context digest: binaries and files over the size cap " \
                   "are **listed only** (not inlined) — do not expect base64 blocks. For a full, " \
                   "uncapped pack use `pub4 snapshot` (writes `snapshot_<TREE>.md` at the repo root)."
          end

          "4. Every git-tracked **text** file is inlined in full — no size cap, no " \
          "\"large file, not inlined\" placeholders. Binaries (images, fonts, archives) " \
          "are still not base64-inlined (that once produced multi-GB snapshots); their " \
          "path just doesn't appear as a fenced block — read them from the real repo if needed."
        end

        def rehydrate_lines(full_inline: false)
          binary_note = binary_inlining_note(full_inline:)
          [
            "### 5. Rehydrate files locally (mirror extraction)",
            "To turn this `.md` back into a working tree:",
            "",
            "1. Create a temp workspace, e.g. `mktemp -d` → `$SNAP/work`.",
            "2. For each `## \\`relative/path\\`` heading, recreate directory structure under `$SNAP/work`.",
            "3. Copy the fenced block body **exactly** (preserve newlines; strip only the outer ```lang fences).",
            binary_note,
            # Names the files Snapshot::Publisher actually writes (see its `paths`:
            # MASTER_snapshot.md / OPERATOR_snapshot.md). This line used to say
            # "e.g. MASTER + RAILS + OPENBSD", which implied an OPENBSD_snapshot.md
            # that is never produced — the OpenBSD material ships as
            # OPERATOR_snapshot.md. An agent following the old wording would look
            # for a file that does not exist.
            "5. Repeat for every sibling snapshot file present — typically `MASTER_snapshot.md` and",
            "   `OPERATOR_snapshot.md` — each extracting to its own subtree under `$SNAP/work`.",
            "6. Verify: file count vs Tree, spot-check hashes, run targeted tests from the mirrored tree.",
            "",
            "Do not edit the mirrored tree until you have a written assessment and a trace for the path",
            "you intend to change.",
            "",
          ]
        end

        def render(label: "MASTER", full_inline: false)
          lines(label:, full_inline:).join("\n")
        end
      end
    end
  end
end
