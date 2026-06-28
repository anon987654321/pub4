---
name: MASTER zsh discipline applies to my session shell
description: When working on MASTER (or any project where MASTER's constitution applies), avoid the banned external commands in my own Bash tool calls — not just in scripts I write
type: feedback
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
MASTER zsh-banned commands (`sed`, `awk`, `grep`, `head`, `tail`, `find`, `wc`, `sudo`, `perl`, standalone `ruby -e`) apply to Bash calls. Read: `cat`. Search: Grep. Find: Glob. Privilege: `doas`. Parse: Ruby script. OK: git, gh, bundle, ssh, scp. CLI via `bundle exec ruby bin/cli`; else `tmp/patch.rb`.