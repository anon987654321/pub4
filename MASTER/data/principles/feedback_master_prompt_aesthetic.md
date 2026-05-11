---
name: MASTER prompt aesthetic is approved
description: Keep the oh-my-zsh-style shell prompt (bold-red master, dim metadata, $); don't redesign it
type: feedback
originSessionId: 0c593fb2-cd49-4fd7-9e89-d77dd7e909ae
---
Keep `Master::Renderer#prompt_line` as-is: bold-red `master`, dim parens/braces around branch/phase, dim token bar, `$` terminator. Oh-my-zsh-style is the desired look.

**Why:** user explicitly approved it after I shipped the IRC `<master>` reply tag. The prompt was never the part that needed fixing — only the reply side lacked a speaker marker.

**How to apply:**
- Don't simplify, recolor, or strip metadata from `prompt_line`.
- New ornamentation goes elsewhere (reply tag, status row, dmesg banner) — not the prompt line.
- If asked to "clean up the prompt," confirm scope first; default assumption is the user means surrounding output, not the prompt itself.
