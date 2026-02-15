# RG69 - Mobile-First Beat Machine

A comprehensive, self-contained beat machine and sequencer in a single HTML file (45KB).

## Quick Start
1. Open `rg69.html` in any modern browser
2. Press **Space** to play
3. Click sequencer grid to add/remove steps
4. Select **mood presets** for instant genre styles
5. Press **E** to export WAV, **R** to randomize

## Features

### Audio Engine
- **Synthesizers:** Kick (MembraneSynth), Snare/Clap (NoiseSynth), Hats (MetalSynth), Bass (MonoSynth + Sub), Keys & Pads (PolySynth)
- **Effects:** 17 types including AutoWah, Chorus, Distortion, Reverb, Delay, BitCrusher, Phaser, etc.
- **FX Chains:** Per-track (2-5 FX) + Master (3-8 FX) with randomization
- **Lo-Fi Processing:** Tape saturation, crackle, hiss, flutter, rumble

### Pattern Library (60+ patterns total)
- **28 Drum Patterns:** Ethio-Jazz, Reggae/Dub, Industrial, Afrobeat, Bossa Nova, Trap, Ambient, Broken Beat
- **14 Mood Presets:** Instant genre setups with BPM/swing ranges
- **Bass/Keys/Pads:** 40+ melodic patterns with transposition

### Mobile-First Design
- Touch-friendly controls (48x48px minimum)
- Horizontal-scroll sequencer with snap
- Collapsible panels
- Fixed transport bar on mobile
- iOS audio context fix
- Notch/safe-area support

### Workflow Features
- **Sequencer:** 5 tracks × 16 steps × 4 banks (A/B/C/D)
- **Export:** WAV (offline render) + WebM (live recording)
- **State:** Undo/redo (50 steps), autosave, URL sharing
- **Controls:** Per-track mute/solo, swing, volume
- **Themes:** Dark/light toggle

### Keyboard Shortcuts
- `Space` - Play/Pause
- `R` - Randomize
- `E` - Export WAV
- `T` - Tap tempo
- `L` - Toggle theme
- `Ctrl+Z` / `Ctrl+Shift+Z` - Undo/Redo
- `?` - Help

## Technical Specs
- **Size:** 45KB (self-contained)
- **Dependencies:** Tone.js 14.8.49 CDN only
- **Browser:** Chrome 90+, Safari 14+, Firefox 88+
- **Mobile:** iOS 14+, Android 10+
- **Performance:** CPU monitoring with auto-optimization

## Architecture
- Mobile-first CSS with breakpoints (768px, 1200px)
- Vanilla JavaScript (no frameworks)
- localStorage autosave every 10s
- OfflineAudioContext for WAV export
- MediaRecorder API for live recording
- Base64 URL state encoding

## Genre Packs

### Ethio-Jazz (Mulatu Astatke style)
- 6/8 polyrhythmic grooves
- Qenet modal scales (Tizita, Bati, Ambassel)
- BPM: 85-110, Swing: 15-35%

### Roots Reggae / Dub
- One Drop (kick+snare on 3 only)
- Steppers (4-on-floor)
- Deep sub bass
- BPM: 62-85, Swing: 5-25%

### Industrial / HATE
- Relentless 16th hats
- Displaced kicks
- Dark tritones
- BPM: 140-165, Swing: 0-5%

### Afrobeat (Tony Allen / Fela)
- Polyrhythmic interlocking patterns
- Highlife ghost notes
- BPM: 105-125, Swing: 10-25%

### Bossa Nova
- Son clave patterns
- Samba variations
- BPM: 120-140, Swing: 5-15%

### Trap / Drill
- 808 sub bass rolls
- Triplet hats
- BPM: 130-150, Swing: 0-5%

### Ambient / Drone
- Minimal clicks
- Slow-evolving pads
- BPM: 60-80, Swing: 0-10%

### Broken Beat
- Syncopated between Dilla and house
- West London bounce
- BPM: 115-135, Swing: 15-35%

## Credits
- Combines features from PR #249 (Tone.js engine) and PR #250 (genre patterns)
- Adds 5 new genre packs + comprehensive mobile-first redesign
- Built with Tone.js 14.8.49

## License
See repository license
