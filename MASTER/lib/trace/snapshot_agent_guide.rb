# frozen_string_literal: true

module Master
  module Trace
    # Preamble embedded at the top of MASTER/DEPLOY snapshot markdown artifacts.
    # Instructs downstream AI agents how to consume the digest before the tree/codebase.
    module SnapshotAgentGuide
      module_function

      def lines(label: "MASTER")
        [
          "## Agent analysis protocol",
          "",
          "This document is a **verbatim codebase mirror** for `#{label}`. Treat every fenced",
          "block as source of truth — not a summary. Work through it in this order:",
          "",
          "### 1. Orient",
          "- Read **Summary**, **Recent changes**, and **Tree** before opening any file block.",
          "- Note topology: where boot, routing, data, UI, deploy, and tests live relative to each other.",
          "",
          "### 2. Word-for-word read + cross-reference",
          "- Read each `## \\`path\\`` section **line by line**; do not skim or paraphrase from headings alone.",
          "- **Cross-reference** symbols across files: follow requires/imports, route → controller → service",
          "  chains, YAML keys → Ruby readers, JS event names → subscribers, CLI commands → dispatchers.",
          "- When the same name appears in multiple places, reconcile definitions — flag drift immediately.",
          "",
          "### 3. Deep execution traces (start → finish)",
          "- Pick critical paths (boot, request/response, scan/fix loop, deploy, TTS/chat SSE, face render)",
          "  and trace **one complete path** from entrypoint through every hop to side effects/output.",
          "- For each hop record: caller, callee, inputs, branching conditions, failure modes, and what",
          "  state mutates (files, DB, env, in-memory singletons, event bus).",
          "- Prefer evidence from this snapshot over assumptions from training data.",
          "",
          "### 4. Architecture & design assessment",
          "- **Structure**: layering, boundaries, coupling, duplication, god objects, require cycles.",
          "- **Semantics**: naming honesty, invariants, tenancy/auth, error taxonomy, idempotency.",
          "- **Design**: UI philosophy, data flow, extension points, config vs code, deploy topology.",
          "- **Smells & oddities**: dead code, parallel implementations, magic numbers, commented-out paths,",
          "  inconsistent conventions, docs that disagree with code.",
          "- **Gaps & friction**: missing tests, unwired features, slow/hidden boot steps, operator pain,",
          "  places where a human or agent would get stuck without tribal knowledge.",
          "",
          "### 5. Rehydrate files locally (mirror extraction)",
          "To turn this `.md` back into a working tree:",
          "",
          "1. Create a temp workspace, e.g. `mktemp -d` → `$SNAP/work`.",
          "2. For each `## \\`relative/path\\`` heading, recreate directory structure under `$SNAP/work`.",
          "3. Copy the fenced block body **exactly** (preserve newlines; strip only the outer ```lang fences).",
          "4. Binary sections use `\\`\\`\\`base64` — decode to bytes, write with the same relative path.",
          "5. Repeat for **both** `MASTER_snapshot.md` and `DEPLOY_snapshot.md` when present:",
          "   - `$SNAP/work/MASTER/...` from MASTER sections",
          "   - `$SNAP/work/DEPLOY/...` from DEPLOY sections",
          "6. Verify: file count vs Tree, spot-check hashes, run targeted tests from the mirrored tree.",
          "",
          "Do not edit the mirrored tree until you have a written assessment and a trace for the path",
          "you intend to change.",
          ""
        ]
      end

      def render(label: "MASTER")
        lines(label:).join("\n")
      end
    end
  end
end