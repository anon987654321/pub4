# Runbooks

Runbooks describe how to gather evidence for the one root backlog, TODO.md.
They do not change application code, execute themselves, or close TODO items.

For each run:

1. Choose the exact intended source commit. Record git rev-parse HEAD and
   inspect the starting source/worktree state.
2. Run the real command through ruby OPENBSD/bin/evidence LABEL -- COMMAND ...
   The default timeout is 1,800 seconds; set a shorter or longer explicit
   --timeout where appropriate.
3. Inspect the JSON and captured text output. Resolve every FAIL, BLOCKED,
   TIMEOUT, SKIPPED or INCONCLUSIVE state honestly.
4. Attach relevant screenshots, geometry dumps, output manifests, device logs
   or host evidence with --attach PATH where the files are in the checkout.
5. Review the attachments and log for secrets or personal data. Commit only
   the reviewed evidence that is appropriate for the repository.
6. Close the corresponding TODO.md item in a separate commit whose message
   cites the evidence path and verdict.

The helper captures the command's actual status. It does not silently convert
a failed command into a pass, and it terminates the command's process group on
timeout. A --verdict override requires a non-empty --note when it changes the
detected classification; PASS is refused for a non-zero command. Overrides
are classifications, not new test results, and the process still exits with
the reported command status.

JSON uses .json and the output log uses .txt. The repository-wide ignore rule
covers *.log, so .txt keeps evidence logs visible to Git without an ignore
override. Capture artifacts are not automatically staged or committed.

| Runbook | Root TODO scope |
|---|---|
| release-pass.md | Release pass, check runner, campaign, command/surface parity |
| rendered-layout.md | Rendered layout, geometry, accessibility and asset budgets |
| pwa.md | Install, offline behavior, service-worker update and recovery |
| voice-path.md | Actual STT/TTS playback, interruptions and latency |
| openbsd-deploy-restore.md | Deploy/canary/rollback, restore drills and host-only proofs |
| provider-integration.md | Live external providers, advice review and Brgen revenue readiness |
| cli-web-ux.md | Cancellation, connection/message status, state and terminal/DOM restoration |
| studio-render.md | Dilla render, postpro/live output and objective audio measurements |

Never raise a budget, skip a failing check or mark a test green to make the
runbook look complete. If the browser, provider, device, host or required data
is unavailable, record BLOCKED or INCONCLUSIVE with a specific reason.
