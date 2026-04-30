# Why GitHub Copilot CLI connects via SSH but fails to execute remote commands

GitHub Copilot CLI's ability to establish SSH connections while failing to execute commands within those sessions stems from a **fundamental architectural limitation**: the tool relies on shell integration signals that don't propagate to remote shells. This isn't a bug but a recognized feature gap—VS Code issue #268528 documents exactly this behavior and sits in Microsoft's backlog, labeled `terminal-shell-integration`.

## Shell integration architecture explains the core failure

Copilot CLI depends on a shell integration system that instruments your local terminal to detect command boundaries and capture output. This works through **escape sequences and prompt pattern matching** that your local shell (bash, zsh, PowerShell) emits after each command completes. When you SSH into a remote server, you enter a nested shell context that:

- Does not have VS Code's shell integration scripts installed
- Uses different prompt formats (PS1/PROMPT) than your local shell
- Cannot emit the escape sequences Copilot needs to detect command completion
- Operates outside the instrumented environment Copilot was designed for

The result is predictable: Copilot can generate and execute the `ssh user@server` command because that runs in your local, instrumented shell. But once you're inside the SSH session, Copilot literally **cannot see what's happening**. Research confirms that when asked to run commands in an SSH session, Copilot often opens a new local PowerShell tab instead of using the active connection—it doesn't recognize the SSH terminal as a valid execution target.

## The "missing finish_reason" error reveals streaming disruption

The `finish_reason` field is how the OpenAI-compatible API signals why generation stopped (natural stop, length limit, content filter, tool call). During streaming responses, every intermediate chunk has `finish_reason: null`, with only the final chunk containing the actual reason. The error "missing finish_reason for choice 0" means **the stream was interrupted before that final chunk arrived**.

In SSH contexts, several mechanisms can cause this:

- **PTY environment changes**: When terminal context switches to SSH, the pseudo-terminal configuration changes, potentially disrupting the streaming read operation
- **Network route changes**: SSH typically routes traffic through the remote host; if the Copilot API connection was established before SSH, route changes could terminate existing sockets
- **Signal handling**: SSH session establishment involves complex signal propagation (SIGINT, SIGHUP, SIGWINCH for window resize) that can interrupt streaming operations
- **Environment variable differences**: SSH sessions may lack proper `HTTP_PROXY`, `HTTPS_PROXY`, or certificate configurations that the local session had

The Copilot CLI repository (issues #510, #421, #431) shows this error pattern appearing during model changes and long-running tool executions—contexts where streaming continuity matters most.

## No explicit SSH policy exists, but model training creates implicit limits

GitHub's official documentation reveals **no hardcoded restrictions on SSH or remote command execution**. The safety model relies on user-controlled approvals rather than command category blocks. Users can approve individual commands, approve for session duration, or deny and request alternatives. The `--allow-all-tools` and `--deny-tool` flags give granular control.

The "not allowed" → "IS allowed" inconsistency you observed likely emerges from **multi-layer policy evaluation**:

1. The underlying LLM (Claude Sonnet by default) may refuse based on its training around commands with broad potential impact
2. GitHub's Responsible AI content filters run on inputs/outputs and can flag certain patterns
3. The CLI's approval system independently determines execution permissions

These layers aren't perfectly coordinated. The model might say "I can't do that" based on safety training, while the CLI tool would technically permit it with user approval. Rephrasing requests often bypasses initial refusals because different prompts trigger different model responses.

## Command detection relies on prompt patterns that break remotely

Copilot's output capture mechanism uses a **polling-based approach with timing parameters**: `MinPollingDuration` of 500ms and `MinPollingEvents` of 2. If terminal output hasn't changed in roughly one second, Copilot assumes the command completed. This works locally because shell integration provides explicit command boundary signals.

Remote shells break this in multiple ways. OpenBSD 7.8 (as you noted Copilot detected) has different default prompts than local shells. The remote shell doesn't emit VS Code integration escape sequences. Long-running remote commands without output may be falsely marked complete. Community discussions document cases where Copilot hangs indefinitely waiting for completion signals that never arrive.

## This is an acknowledged architectural gap, not a prioritized bug

VS Code issue #268528, titled "Copilot agent fails to execute commands in ssh - impossible to work with remotely accessed shells," was filed in September 2025 and remains in the Backlog milestone. The same limitation affects Docker containers in interactive mode—any context that changes the shell environment. The issue is labeled as a `feature-request` rather than a bug, indicating Microsoft considers this a missing capability rather than broken functionality.

The practical reality: Copilot CLI was architected for **single, instrumented local shell contexts**. Nested shells, whether from SSH, docker exec, or subprocess spawning, operate outside the architectural assumptions. No timeline exists for addressing this limitation.

## Practical workarounds exist but require changing workflow

For remote server work with Copilot CLI, the most reliable approaches are:

- **Generate commands, execute manually**: Ask Copilot for the commands you need, then copy and run them yourself in the SSH session
- **Run Copilot directly on the remote machine**: Install the CLI on your server and run it there rather than from a local session
- **Use VS Code Remote-SSH extension**: This connects the full VS Code environment to the remote machine, giving Copilot proper integration context
- **Redirect output to files**: Execute commands manually, redirect output to files, then use Copilot's `read_file` tool to analyze results

## Conclusion

The disconnection between connection capability and execution capability is structural. Copilot CLI can run SSH commands because those execute in your local instrumented shell. It cannot execute within SSH sessions because remote shells exist outside its detection architecture—no shell integration signals, different prompt patterns, no escape sequences to mark command boundaries. The "missing finish_reason" errors compound this by indicating streaming disruption during context transitions. This isn't a safety restriction or intentional block but an architectural limitation that GitHub has acknowledged without committing to resolve.