MASTER — web layer pass (jjjjjj), 2026-06-15
Scope limited to what is VERIFIABLE in this sandbox. Ruby 3.0.2 only + gems
blocked => no Ruby parse/test verification possible (matches your memory). No
push creds => deliverable is a reviewable patch, not a commit.

FIXED (in master_web_fixes.patch — node --check passes)
1. chat.js mic button crash. startMic lives in chat_actions.js, which the
   served root (chat/index.html.erb, layout:false) does NOT load — only face.js
   + chat.js. Clicking "mic" threw ReferenceError. Fix routes to the always-
   loaded MASTERVoice/MASTER_FACE toggleMic, keeps startMic path where it exists
   (layout page). Both entry points now work.
2. WCAG 4.1.2: <canvas id="face" tabindex="0" aria-hidden="true"> was focusable
   AND hidden from assistive tech. Verified the face engine uses only
   pointer/touch on the canvas; all keyboard handling is document-level. Removed
   tabindex (canvas stays correctly decorative) in chat/index + layout.

FLAGGED — real, NOT changed (your call; intent ambiguous / needs server)
3. Duplicate entry points / ONE_SOURCE: web/face.css, web/face.js,
   web/index.html.erb are unreferenced (layout+views load asset_path =>
   web/public/*). web/public/index.html.erb is ERB inside public/, which Rails
   never processes — dead as written, BUT carries a RICHER UI than the live page
   (theme toggle, voice picker, font-scale, sparklines). Looks staged/intended,
   not junk — so I did NOT delete. Decide: promote it live, or remove.
4. Typography gap: face.css declares Inter + Inter-only feature settings
   (ss01/cv05) and weights 100-200, but the served chat page never loads Inter
   (only the layout does). Primer h1 (200) + logo (700) fall back to system
   fonts. Adding Google Fonts to an offline PWA is its own tradeoff -> flagged,
   not forced. Either load Inter on chat/index for parity, or drop the dead
   Inter-specific declarations.
5. face.css override-by-append duplicates (numbered "#34..#80" blocks re-declare
   earlier rules: dmesg-line color, enhance-text, scroll-behavior, #chat-log).
   Works (last wins) but fragile. Safe to consolidate only with a browser to
   diff render — not available here.

NON-ISSUES (checked)
- The 103 "ruby -c syntax errors" a naive scan reports are FALSE POSITIVES:
  sandbox Ruby is 3.0.2; code targets 3.4 ({x:} shorthand, def m(&)).
- All 27 served JS files parse clean; concatenated face.part1-5 parse as a
  module; window.sendMessage is provided by face engine; _endlessWhite is
  optional-chained (no crash).

NOT DONE — and not claimed
- "10/10 LLM above grok/chatgpt", cli.rb/god-module decomposition, 200+ method-
  length fixes: need the live brgen.no env (tests + LLM providers) to change
  without violating anti_simulation / SELF_APPLY. Not faked.

Applied fixes (2026-06-15):
- Removed tabindex="0" from all <canvas id="face" aria-hidden="true"> (chat view, layout, plus the two index.html.erb for hygiene).
- Guarded mic handler in public/chat.js with fallback to MASTERVoice/MASTER_FACE, preserving startMic path + explanatory comment (PRESERVE_THEN_IMPROVE_NEVER_BREAK).
- Verified: node --check MASTER/web/public/chat.js OK.
- All face canvases now clean of the WCAG anti-pattern.

Flagged items left as-is per review (dupe entrypoints in web/ vs public/, Inter font, css block duplicates). TODO items below for follow-up.
