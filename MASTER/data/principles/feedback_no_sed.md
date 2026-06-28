---
name: No sed — use ruby
description: Never invoke sed in shell commands; use ruby for any text substitution
type: feedback
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
Never call sed, awk, or grep-with-rewrite for text edits—use Ruby through ruby -e, heredoc, or a .rb script. BSD sed on the OpenBSD VPS breaks GNU-style scripts.

Replace sed -i substitution with ruby -E UTF-8:UTF-8 -e and File.write. The ban also covers awk one-liners.