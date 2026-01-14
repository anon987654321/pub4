# GitHub Copilot CLI fails on remote SSH operations by design

**Copilot CLI is architecturally built for local terminal operations only**, and the "missing finish_reason" error indicates the API call is failing mid-stream—likely because Copilot cannot properly handle SSH session contexts. This is a documented limitation (GitHub Issue #268528), not a permissions issue with your OpenBSD server. OpenBSD is also not an officially supported platform, compounding compatibility challenges.

## The core problem: Copilot CLI assumes local execution

GitHub Copilot CLI operates exclusively within the **local shell environment** where it's installed. All official documentation describes operations on "your computer" and "local environment," with zero mention of SSH or remote server management. The trust model is directory-based on the local filesystem, and the agent executes commands in your local shell context.

**Issue #268528** on the VS Code repository explicitly documents this: "Copilot agent fails to execute commands in ssh - impossible to work with remotely accessed shells." Users report that commands either execute locally instead of remotely, terminal output isn't read correctly, or shell integration fails entirely. Your scenario—where Copilot successfully establishes an SSH connection and detects OpenBSD 7.8 but then fails to execute work—matches this documented pattern perfectly.

When Copilot CLI spawns an SSH session, it can successfully run the connection command (that's local execution), but it loses the ability to interact properly with the resulting remote shell. The terminal integration that allows Copilot to read output, parse results, and iterate breaks down in the SSH context.

## What "missing finish_reason for choice 0" actually means

This error originates from the OpenAI SDK's strict validation of streaming API responses. The `finish_reason` field indicates why the model stopped generating tokens (e.g., "stop" for normal completion, "content_filter" for blocked content, "length" for truncation). When this field is missing, the SDK throws an error.

**This is NOT a content policy refusal.** Policy-based blocks return `finish_reason: "content_filter"` with an explicit explanation. A *missing* finish_reason indicates:

- The stream terminated before the final response chunk arrived
- The API call failed or timed out without proper error handling
- A connection dropped mid-stream

In your case, the error suggests Copilot's backend is failing to complete the API call—likely because the context it receives from your SSH terminal session is malformed or unparseable. The model may be receiving gibberish when Copilot tries to read your remote terminal's output, causing the completion to fail entirely rather than refuse explicitly.

## OpenBSD compatibility creates additional barriers

GitHub Copilot CLI officially supports **only Linux, macOS, and Windows**. OpenBSD is not a supported platform, and multiple technical barriers exist:

- **Platform detection failures**: The CLI likely checks `process.platform` and may not recognize or properly handle "openbsd"
- **pledge(2) and unveil(2) restrictions**: OpenBSD's security model can terminate processes that attempt unauthorized syscalls or file access. If Copilot tries operations not covered by OpenBSD's security promises, the process is killed with SIGABRT—silently
- **doas vs. sudo differences**: OpenBSD's `doas` scrubs environment variables more aggressively than `sudo`, which can break tools expecting certain environment state
- **Node.js ecosystem gaps**: Many npm packages lack OpenBSD binaries, causing installation or runtime failures

If you're running Copilot CLI *on* the OpenBSD server (rather than from a local machine SSHing into it), you'll face these compatibility issues directly. Even if you're running Copilot locally and SSHing to OpenBSD, the remote terminal context still presents the fundamental SSH integration problem.

## Safety restrictions are not the primary blocker

While Copilot CLI does have safety mechanisms—command approval prompts, deny lists for destructive commands (`rm`, `curl`, `chmod`), and content filtering—these don't specifically target remote operations. There's no documented policy saying "don't execute commands on remote servers."

The restrictions focus on **what** you're doing rather than **where**. Destructive commands require approval regardless of whether they're local or remote. Content filters target harmful patterns (malware, exploits) rather than legitimate server administration. If safety restrictions were the issue, you'd see explicit refusal messages or `finish_reason: "content_filter"`, not a cryptic missing-field error.

## Viable workarounds for remote server work

Given the architectural limitations, consider these alternatives:

- **Install Copilot CLI directly on the server**: Run it natively where the commands need to execute. This avoids SSH terminal integration issues but still requires a supported OS (Linux). On OpenBSD, you'd need to run it in a Linux VM or container via `vmm(4)`
- **Use VS Code with Remote-SSH extension**: Unlike the standalone CLI, VS Code's Copilot integration can work over Remote-SSH because the agent operates within the remote context, with proper terminal integration
- **Generate commands locally, execute manually**: Use Copilot CLI to generate deployment scripts or commands locally, then copy/paste or transfer them to your OpenBSD server for execution
- **GitHub Copilot Coding Agent**: For repository-based tasks, the cloud-hosted coding agent runs in GitHub's infrastructure and can push code changes, though it operates in a sandboxed environment with restricted internet access
- **MCP server approach**: Configure a Model Context Protocol (MCP) server with SSH capabilities—this is an experimental path that might enable remote operations, though documentation is sparse

## The underlying architectural limitation persists

The fundamental issue is that Copilot CLI's agentic loop—where it reads terminal output, reasons about next steps, and executes commands—depends on tight integration with the local shell. SSH sessions create an abstraction layer that breaks this integration. The agent can run `ssh user@host` locally, but once you're in that remote shell, Copilot can't properly read outputs, parse errors, or iterate on its approach.

Until GitHub explicitly builds remote shell support into Copilot CLI—handling SSH sessions as first-class contexts rather than opaque subprocess outputs—this limitation will persist. The "missing finish_reason" error you're seeing is the symptom of this architectural mismatch, not a fixable configuration issue on your end.