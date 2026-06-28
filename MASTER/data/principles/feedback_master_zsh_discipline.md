---
name: MASTER zsh discipline applies to my session shell
description: When working on MASTER (or any project where MASTER's constitution applies), avoid the banned external commands in my own Bash tool calls — not just in scripts I write
type: feedback
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
When MASTER's constitution applies, zsh-banned commands apply to your own Bash tool calls—not only scripts you write. Avoid sed, awk, grep, head, tail, find, wc, sudo, perl, and standalone ruby -e. Read with cat, search with Grep, find with Glob, elevate with doas, parse with Ruby.

Git, gh, bundle, ssh, and scp remain acceptable. Invoke the CLI through bundle exec ruby bin/cli; otherwise use tmp/patch.rb.