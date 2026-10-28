# Efficient repair workflow

Use a measured, tree-scoped loop. The short path is **focused checks → one-tree /fix → read-only proof**; the full check ladder is broader, not cheaper.

Authority remains MASTER/data/soul.yml → MASTER/data/laws.yml → executable Law/check gates → tree contracts → prose. A declared Law, registered detector, or passing source scan does not by itself prove every declared modality or runtime surface was assessed.

## 1. Focused read-only preflight

From MASTER/, first confirm that the active Ruby matches the tree's .ruby-version. Then run the actual leaf/composite checks directly through the check registry:

~~~zsh
bundle exec ruby checks/runner.rb --scan-only architecture layout_suite
~~~

- architecture is the inexpensive Phoenix boundary check.
- layout_suite is the composite for the CSS constitution, scale, typography, source design contracts, and rendered suite. Do not repeat its leaves manually.
- --scan-only disables check autofix. It does not mean that every rendered surface was measured: browser absence, skipped routes, zero rendered cells, soft findings, or inconclusive results must remain visible and are not a rendered PASS.

This direct runner selects registry check names. It is different from MASTER/bin/operator check --only=..., which selects CheckChain stage names.

## 2. Repair only the tree that owns the findings

From MASTER/, when the RAILS product surface is red:

~~~zsh
bin/master /fix RAILS
~~~

This is the model-backed repair pass. It performs the target's Law-driven scan and repair loop; it is not replaced by a green design check. The protocol/architecture tournament belongs to a /fix target run, not to the small Phoenix architecture check. Keep one tree per run unless cross-tree evidence shows a dependency.

For MASTER-owned runtime, CLI, Law tooling, or scan failures, use bin/master /fix MASTER instead. Do not add OPENBSD or STUDIO to a RAILS repair just to make the command look more comprehensive.

## 3. Prove the repaired RAILS tree

The CheckChain's --only accepts its eight stages (lexical, source, openbsd, rehearse, suites, ratchets, sprawl, council), not names such as layout_suite or constitutional_scan.

For broad, deterministic, read-only RAILS proof without repeating the provider-backed council review:

~~~zsh
bin/operator check --scan-only --tree=RAILS --only=lexical,source,rehearse,suites,ratchets,sprawl
~~~

This is intentionally more than a fast preflight: it includes the Law scanner, the RAILS check/premerge proof, rehearsal, full selected-tree test suites, ratchets, and the structural census. It may take substantial time. Leaving out council is explicit; it is not a claim that the council ran.

To run the whole configured CheckChain, including the council stage, use:

~~~zsh
bin/operator check --scan-only --tree=RAILS
~~~

The full command can invoke model-backed critique even though it is scan-only. Choose it when that additional evidence is wanted and model cost/availability is acceptable.

## 4. Understand the separate Law-corpus check

Run the registered constitutional_scan explicitly when the recorded scan-debt ceilings matter:

~~~zsh
bundle exec ruby checks/runner.rb --scan-only constitutional_scan
~~~

This check's default population is **six targets**: the four RAILS targets (brgen, amber, bsdports, __shared), OPENBSD, and MASTER. It is not a RAILS-only scan merely because it was launched from MASTER/, and its recorded finding counts are not proof that every Law has a deterministic detector. For that identity/source/modality question, retain LawRegistryAudit and the agent/self-test gates; a Law without a deterministic detector remains coverage debt, not clean.

CHECK_SCAN_CHANGED=1 narrows this particular check to targets touched in the Git diff. That is a changed-target adjunct, never a substitute for the full corpus when making a full-corpus claim.

## 5. Widen only for evidence

- Include browser/runtime evidence when the rendered surfaces are part of the acceptance criterion; a code-only run cannot certify geometry or interaction.
- Include OPENBSD when configuration/deployment source is the debt, and run native pfctl -nf /etc/pf.conf on the real OpenBSD host for native PF syntax.
- Include STUDIO when its media/toolchain paths are touched; its real ffmpeg/Vips/runtime proof is separate from source checks.
- Run the full four-tree tournament when the task actually requires cross-tree architectural choices. It is the marathon mode, not the cheapest daily loop.

Keep the distinction visible in every report: checks that ran, skipped/inconclusive checks, source findings, runtime/deployment evidence, and provider-backed advice are separate kinds of proof.
