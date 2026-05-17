---
name: MASTER zsh discipline applies to my session shell
description: When working on MASTER (or any project where MASTER's constitution applies), avoid the banned external commands in my own Bash tool calls — not just in scripts I write
type: feedback
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
The zsh-banned-commands list in MASTER (`sed`, `awk`, `tr`, `grep`, `cut`, `head`, `tail`, `find`, `wc`, `sudo`, `perl`, `ruby` invoked from zsh, `dd`, `xargs`) applies to commands I run via the Bash tool too, not only to scripts I write into the repo.

**Why:** MASTER is a constitutional agent and the operator expects me to live by the same constitution while editing it. Reaching for `wc -l` or `sort | tail` to inspect repo files signals that I do not actually use what I preach. Caught 2026-05-05.

**How to apply:** When inspecting MASTER (or any sibling pub4 project) over Bash:
- Read a file → `cat file` (prefer over grep/head/tail fragments — user reinforced 2026-05-06: "instead of grep and head just cat"). Read the whole file once instead of stitching snippets together.
- File line counts → zsh array: `lines=("${(@f)$(<file)}"); print ${#lines}` — or `print -l file*(.oL[1,N])` for size-sorted listing
- Largest N files → glob qualifier with size sort: `print -l **/*.yml(.oL[1,20])`
- Search content (when actually searching, not reading) → use the Grep **tool**, never shell `grep`/`rg`
- Find files → use the Glob **tool**, never shell `find`
- Privilege → `doas`, never `sudo`
- Complex parsing → write a Ruby script and run it, never inline `sed`/`awk`

The exception that already holds: `git`, `gh`, `bundle`, `ssh`, `scp`, `sshpass`, plain `ls`, `mkdir`, `cd`, `print`, `echo`, parameter expansion. Those stay fine.

**Narrow exceptions:**
- `eval` — only for loading exports from `.zshrc` (`eval "$(grep '^export' ~/.zshrc)"`). Banned for arbitrary code execution.
- `bundle exec ruby bin/cli` — permitted because it boots the project executable. Standalone `ruby -e` from zsh stays banned; use `tmp/patch.rb` + `ruby tmp/patch.rb` for transient scripts.
