---
name: No unnecessary piping/concat in shell calls
description: Avoid pipe chains and string concat in Bash invocations; prefer pure Ruby or pure zsh
type: feedback
originSessionId: 0c593fb2-cd49-4fd7-9e89-d77dd7e909ae
---
Don't pipe through `head`/`tail`/`grep`/`wc` or chain with `&&`/`;` when Ruby/zsh does the job. File reads → Read tool; searches → Grep; file finds → Glob. Single-step shell ops run directly. Ruby: prefer `ruby -e`. Zsh: builtins, globs, arrays — not coreutils pipes. Matches banned commands in `data/rules.yml`.