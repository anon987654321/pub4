---
name: No unnecessary piping/concat in shell calls
description: Avoid pipe chains and string concat in Bash invocations; prefer pure Ruby or pure zsh
type: feedback
originSessionId: 0c593fb2-cd49-4fd7-9e89-d77dd7e909ae
---
When invoking Bash, do not pipe through `head`/`tail`/`grep`/`wc` etc. or stitch with `&&`/`;` chains where a single Ruby/zsh idiom does the job.

**Why:** matches the banned-shell-commands rule already in `data/rules.yml` (sed/awk/grep/find/head/tail/wc/sudo). Same discipline applies to my own tool calls, not just to scripts I write. User explicitly called this out as noise — it makes prompts hard to read and audit.

**How to apply:**
- File reads → use Read tool, not `cat | head`.
- Searches → use Grep tool, not `grep`.
- Single-step shell ops → run them directly; do not chain when sequential calls would be clearer.
- For Ruby work, prefer a one-liner `ruby -e '...'` over zsh-glue.
- For zsh, use builtin parameter expansion / globs / arrays, not pipes to coreutils.
