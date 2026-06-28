---
name: No unnecessary piping/concat in shell calls
description: Avoid pipe chains and string concat in Bash invocations; prefer pure Ruby or pure zsh
type: feedback
originSessionId: 0c593fb2-cd49-4fd7-9e89-d77dd7e909ae
---
Do not pipe through head, tail, grep, or wc or chain shell calls with logical-and and semicolons when Ruby or zsh handles the job. Use the Read tool for file reads, Grep for searches, and Glob for file finds; run single-step shell operations directly.

In Ruby, prefer ruby -e. In Zsh, use builtins, globs, and arrays—not coreutils pipes. This matches banned commands in data/rules.yml.