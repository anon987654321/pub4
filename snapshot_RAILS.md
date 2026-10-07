# RAILS â€” source snapshot

Generated 2026-10-07 19:53:07 UTC â€” git da3c3e6 â€” 2478 files inlined, 87 binary listed only.

Share this file with another LLM as the full readable RAILS codebase pack.

## Agent analysis protocol

This document is a **share-size-bounded source mirror** for `RAILS`. Treat every fenced
block as source of truth â€” not a summary. The `Omitted text files` section, when present,
is authoritative: those tracked text files were excluded only to satisfy the hard size ceiling. Work through it in this order:

### 1. Orient
- Read the header (generation metadata, file count, policy) and **Tree** before opening any file block.
- Note topology: where boot, routing, data, UI, deploy, and tests live relative to each other.

### 2. Word-for-word read + cross-reference
- Read each `## \\`path\\`` section **line by line**; do not skim or paraphrase from headings alone.
- **Cross-reference** symbols across files: follow requires/imports, route â†’ controller â†’ service
  chains, YAML keys â†’ Ruby readers, JS event names â†’ subscribers, CLI commands â†’ dispatchers.
- When the same name recurs in multiple places, reconcile definitions â€” flag drift immediately.

### 3. Deep execution traces (start â†’ finish)
- Pick critical paths (boot, request/response, scan/fix loop, deploy, TTS/chat SSE, face render)
  and trace **one complete path** from entrypoint through every hop to side effects/output.
- For each hop record: caller, callee, inputs, branching conditi¶»§q«^t€‘…Ñ¥¹œè‘…Ñ¥¹œ¹‰É•¸¹¹¼(€€€Ñ…­•…İ…äèÑ…­•…İ…ä¹‰É•¸¹¹¼(€€€ÑØèÑØ¹‰É•¸¹¹¼(€€€µ…ÁÌèµ…ÁÌ¹‰É•¸¹¹¼(€€€Á±…å±¥ÍĞèÉ…‘¥¼¹‰É•¸¹¹¼(€€€µ•ÍÍ•¹•Èèµ•ÍÍ•¹•È¹‰É•¸¹¹¼)€((ŒŒI%1L½‰É•¸½•¹¥¹•Ì½‘…Ñ¥¹œ½I5¹µ‘€()µ…É­‘½İ¸(Œ‰É•¸‘…Ñ¥¹œ((¨©5…Ñ¡µ…­¥¹œ™½È„¥Ñäå½Ô…±É•…‘ä±¥Ù”¥¸¸¨¨‘…Ñ¥¹œ¥Ì„µ½Õ¹Ñ…‰±”I…¥±Ì•¹¥¹”)Í•ÉÙ•…Ğ‘…Ñ¥¹œ¸ñ¥Ñäù€ƒŠP‘…Ñ¥¹œ¹‰É•¸¹¹½€°‘…Ñ¥¹œ¹±Í…¹•±•Ì¹½µ€ƒŠP¹½Ğ„)Í•Á…É…Ñ”…ÁÀ¸€¸¸¼¸¸½I5¹µ‘€¥ÌÑ¡”É•¥Á”ì€¸¸¼¸¸½9QL¹µ‘€¥ÌÑ¡”Ñ½Á½±½ä¸()… ÕÍ•È‰Õ¥±‘Ì„AÉ½™¥±•€°Ñ¡•¸±¥­•Ì½È‘¥Í±¥­•Ì½Ñ¡•ÉÌ½¹”…Ğ„Ñ¥µ”°İ¥Ñ )¡½µ”¹•áÑ€Í•ÉÙ¥¹œÑ¡”¹•áĞ…¹‘¥‘…Ñ”¸µÕÑÕ…°±¥­”É•…Ñ•Ì„5…Ñ¡€¸Q¡½Í”)™½ÕÈµ½‘•±ÌƒŠPAÉ½™¥±•€°1¥­•€°¥Í±¥­•€°5…Ñ¡€ƒŠPÑ…­”Ñ¡”‘…Ñ¥¹}€Ñ…‰±”)ÁÉ•™¥à™É½´¥Í½±…Ñ•}¹…µ•ÍÁ…”…Ñ¥¹€¸()I½ÕÑ•Ì…É”‘É…İ¸½¸…Ñ¥¹œèé¹¥¹•€…¹µ½Õ¹Ñ•Õ¹‘•È½¹ÍÑÉ…¥¹ÑÌ¡ÍÕ‰‘½µ…¥¸è)Q%9}MU	=5%9L¥€¸I½½Ğ¥ÌÑ¡”…¹‘¥‘…Ñ”™••…¹P¹•áÑ€…‘Ù…¹•Ì¥Ğì)É•Í½ÕÉ”€éÁÉ½™¥±•€¥ÌÑ¡”ÕÍ•ÈÌ½İ¸…É°±¥­•Í€…¹‘¥Í±¥­•Í€É•½ÉÍİ¥Á•Ì°)…¹µ…Ñ¡•Ì¥¹‘•á€±¥ÍÑÌÑ¡”µÕÑÕ…±Ì¸()5…­¥¹œ½È•‘¥Ñ¥¹œ„ÁÉ½™¥±”…Í­Ì™½ÈY¥ÁÁÌ1½¥¸™¥ÉÍĞ°‰•…ÕÍ”„Ù•É¥™¥•Á¡½¹”)¹Õµ‰•È¥Ìİ¡…ĞÁÕÑÌ„É•…°Á•ÉÍ½¸‰•¡¥¹„™…”Í¡½İ¸Ñ¼ÍÑÉ…¹•ÉÌ¸Q¡”…Ñ”)™…¥±Ì½Á•¸¸]¡•¸Y%AAM}1%9Q}%€¥Ì…‰Í•¹ĞÑ¡”Y¥ÁÁÌÁÉ½Ù¥‘•È¹•Ù•ÈÉ•¥ÍÑ•ÉÌ°)Ñ¡”¡•¬¥ÌÍ­¥ÁÁ•°…¹…¹å½¹”Í¥¹•¥¸…¸ÁÕĞ„ÁÉ½™¥±”¥¸Ñ¡”‘•¬ì„)µ¥ÍÍ¥¹œÙ…É¥…‰±”Í¡½Õ±¹½Ğ±½¬„İ¡½±”¥Ñä½ÕĞ½˜Ñ¡”Ù•ÉÑ¥…°¸AÉ½‘ÕÑ¥½¸)µÕÍĞÑ¡•É•™½É”…ÉÉäÑ¡”Y¥ÁÁÌ­•åÌ¥¸€½•ÑŒ½‰É•¸¹•¹Ù€°¾ÚîÆ­yÒĞ¢VÇ6–bWfVçBçG'’ƒ§&–6Uö6VçG2’çFõö’ç÷6—F—fSğ¢°¢$G—R"Óâ$öffW""À¢'&–6R"ÓâWfVçBç&–6Uö6VçG2çFõö’òãÀ¢'&–6T7W'&Væ7’"ÓâWfVçBçG'’ƒ¦7W'&Væ7’’ç&W6Væ6RÇÂ$äô²"À¢&f–Æ&–Æ—G’"ÓâWfVçBæ6æ6VÆÆVCòòæ–Â¢&‡GG3¢ò÷66†VÖæ÷&rô–å7Fö6²"À¢'W&Â"Óâ66†VÖ÷W&Åöf÷"†WfVçB’À¢Òæ6ö×7@¢Væ@ ¢°¢$6öçFW‡B"Óâ&‡GG3¢ò÷66†VÖæ÷&r"À¢$G—R"Óâ$WfVçB"À¢&æÖR"ÓâWfVçBçG'’ƒ§F—FÆR’À¢&FW67&—F–öâ"ÓâÖWFöFW67&—F–öåöf÷"†WfVçB’À¢'7F'DFFR"Óâ7F'G5öBæ–å÷F–ÖU÷¦öæR‚$WW&÷Rô÷6Æò"’æ—6óƒcÀ¢&VæDFFR"Óâ†VæG5öBæ–å÷F–ÖU÷¦öæR‚$WW&÷Rô÷6Æò"’æ—6óƒc–bVæG5öBç&W6VçCò’À¢&WfVçE7FGW2"Óâ€¢WfVçBæ6æ6VÆÆVCòò&‡GG3¢ò÷66†VÖæ÷&rôWfVçD6æ6VÆÆVB"¢&‡GG3¢ò÷66†VÖæ÷&rôWfVçE66†VGVÆVB ¢’À¢&WfVçDGFVæFæ6TÖöFR"Óâ&‡GG3¢ò÷66†VÖæ÷&rôöffÆ–æTWfVçDGFVæFæ6TÖöFR"À¢&Æö6F–öâ"ÓâÆö6F–öâæ6ö×7BÀ¢&–ÖvR"Óâ6Võö–ÖvU÷W&Â†WfVçBçG'’ƒ¦6÷fW"’’À¢&öffW'2"ÓâöffW"À¢&÷&væ—¦W""ÓâW'6öå÷6æ—WB†WfVçBçG'’ƒ§W6W"’’À¢'W&Â"Óâ66†VÖ÷W&Åöf÷"†WfVçB’À¢Òæ6ö×7@¢Væ@ ¢FVbf–FVõ÷66†VÖ‡f–FVò¢°¢$6öçFW‡B"Óâ&‡GG3¢ò÷66†VÖæ÷&r"À¢$G—R"Óâ%f–FVôö&¦V7B"À¢&æÖR"Óâf–FVòçG'’ƒ§F—FÆR’À¢&FW67&—F–öâ"Óâf–FVòçG'’ƒ¦FW67&—F–öâ’bçG'Væ6FRƒ#’À¢'WÆöDFFR"Óâf–FVòæ7&VFVEöBbæ—6óƒcÀ¢'W&Â"Óâ66†VÖ÷W&Åöf÷"‡f–FVò’À¢'F‡VÖ&æ–ÅW&Â"Óâ6[kºwµç