---
name: MASTER prompt aesthetic is approved
description: Keep the oh-my-zsh-style shell prompt (bold-red master, dim metadata, $); don't redesign it
type: feedback
originSessionId: 0c593fb2-cd49-4fd7-9e89-d77dd7e909ae
---
Keep `Master::Renderer#prompt_line` as-is: bold-red `master`, dim branch/phase parens, dim token bar, `$` terminator — oh-my-zsh style. Don't simplify, recolor, or strip metadata. New ornamentation goes to reply tag/status row/dmesg banner, not the prompt. "Clean up the prompt" usually means surrounding output — confirm scope first.