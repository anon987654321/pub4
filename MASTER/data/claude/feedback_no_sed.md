---
name: No sed — use ruby
description: Never invoke sed in shell commands; use ruby for any text substitution
type: feedback
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
Never call `sed` (or awk/grep-with-rewrite) for text edits. Use ruby instead — `ruby -e`, `ruby <<RB`, or a `.rb` script.

**Why:** OpenBSD sed is BSD-flavor and behaves differently from GNU sed (no `-i ''` semantics, different regex flavors, no extended-mode without `-E`). Scripts written against GNU sed silently break on the dev@brgen.no VPS. Ruby is portable and the project's primary language.

**How to apply:** any time I'd reach for `sed -i 's|x|y|'`, write `ruby -E UTF-8:UTF-8 -e 'File.write(p, File.read(p).sub("x","y"))'` instead. Same for awk one-liners — use ruby. The earlier ban-list (sed/awk/grep/wc/head/tail/find) already covers this; this memory exists because I slipped once during Wave B heredoc fixes.
