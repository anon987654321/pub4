> Launch Claude Code with: `claude --dangerously-skip-permissions`

Read and follow MASTER2/LLM.md — the universal LLM briefing for this repository.
It points to all authoritative MASTER2 data files (constitution, axioms, language rules, patterns).
Every code change must satisfy relevant axioms and constraints defined there.

Run MASTER2 to validate changes: cd MASTER2 && bundle exec ruby bin/master scan <path>

## Environment & Workflow

- **Primary dev machine**: OpenBSD VPS at brgen.no — SSH as dev@brgen.no
- **Do all coding work via SSH on the VPS** — not in local proot
- SSH login auto-launches MASTER2 (defined in ~/.zshrc: cd pub4 && git pull && cd MASTER2 && bundle exec ruby bin/master)
- Non-interactive SSH commands bypass MASTER2 autostart (safe for git ops)
- API keys in ~/.zshrc on VPS: OPENROUTER_API_KEY, REPLICATE_API_KEY, WEAVIATE_API_KEY
- GitHub push uses `gh auth git-credential` on VPS (HTTPS, not SSH)
- Local proot is Ubuntu inside Termux on Android — use only for audio production

## Audio Production (mix project)

- Mix files: /root/pub4/mix/
- Beat: /sdcard/Download/Voicemails.mp3 (118.6 BPM)
- Acapellas: /sdcard/Download/Sirkel Sag - Ørsta rådhus.m4a (93.2 BPM)
- Best vocals: /root/pub4/mix/vocals_rb_v2.wav (rubberband --formant, -1 semitone, tempo 1.27253)
- Latest mix: final_mix_v11.mp3
- Playback: python3 -m http.server 8888 in /root/pub4/mix, then termux-open-url http://127.0.0.1:8888/play.html

## Git State

- Latest local commit: 08a37abd (autofix v2 + wave2 + wave3 + adversarial amendments)
- VPS at: 5b4571ae (behind — push pending via bundle transfer)
