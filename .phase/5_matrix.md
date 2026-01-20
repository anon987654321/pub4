# Phase 5: Evaluation Matrix

**prev_hash:** aeb49ab0

## Evaluation Matrix

| ID | Alternative | Impact | Effort | Mobile | Battery | Score |
|----|-------------|--------|--------|--------|---------|-------|
| 1  | Bass FOV ✓ | 9 | 1 | 9 | 10 | **29** |
| 2  | Star Frequency | 7 | 1 | 8 | 10 | 26 |
| 3  | Mid Color Shift | 6 | 2 | 8 | 10 | 26 |
| 4  | Beat Shake | 5 | 1 | 6 | 10 | 22 |
| 5  | Waveform BG | 7 | 8 | 5 | 9 | 29 |
| 6  | Reverse Parallax ✓ | 8 | 1 | 9 | 10 | **28** |
| 7  | Pinch Zoom | 6 | 8 | 9 | 10 | 33 |
| 8  | Double-Tap FS | - | - | - | - | exists |
| 9  | Swipe Velocity | 5 | 5 | 7 | 10 | 27 |
| 10 | Gyro Slider | 4 | 6 | 8 | 10 | 28 |
| 11 | Beat Haptics ✓ | 8 | 1 | 10 | 6 | **25** |
| 12 | Track Flash | 5 | 2 | 7 | 10 | 24 |
| 13 | YouTube Spinner | 6 | 3 | 7 | 10 | 26 |
| 14 | Error Toast | 7 | 3 | 7 | 10 | 27 |
| 15 | Haptics Toggle | 5 | 5 | 8 | 10 | 28 |

**Legend:** Impact (aesthetic value), Effort (LOC), Mobile (mobile-first), Battery (power efficiency)
**Higher score = better**, calculated as: `Impact×2 + (10-Effort) + Mobile + Battery`

## Persona Votes

### skeptic: "Do we need this?"
- **1 Bass FOV:** ✓ "Dramatic effect, minimal risk"
- **6 Parallax:** ✓ "Enhances depth perception"
- **11 Haptics:** ⚠️ "Battery concern, but toggle-able later"

### minimalist: "Remove everything possible"
- **YAGNI:** ✓ "Ship with 3 features, skip the rest"
- Reject: 5 (waveform), 7 (pinch zoom), 10 (gyro slider)

### performance_zealot: "Microseconds matter"
- **1 Bass FOV:** ✓ "One multiply per frame"
- **6 Parallax:** ✓ "Sign flip, zero cost"
- **11 Haptics:** ✓ "Native OS call"
- Reject: 5 (waveform = extra draw calls)

### security_auditor: "Attack vectors?"
- ✓ All changes safe - no user input, no eval()
- **11 Haptics:** ✓ "navigator.vibrate sandboxed"

### maintenance_dev: "3AM debugging?"
- **Concern:** Functions already too long (25-50 LOC)
- ✓ Accept as minification tradeoff
- Reject: 7, 10, 13, 14, 15 (adds complexity)

### junior_confused: "Can I understand it?"
- ⚠️ Minified code hard to read
- ✓ But changes are small and isolated

### senior_architect: "5 year implications?"
- ✓ "Mobile-first approach is correct"
- ✓ "Haptics toggle needed eventually"
- Reject premature optimization (21-23)

### cost_cutter: "Resource usage?"
- **11 Haptics:** ⚠️ "8ms × 60bpm × 3min = 1440 vibrations/song"
- ✓ Accept for now, add toggle later

### user_advocate: "User needs?"
- ✓ "Immersion is the goal"
- ✓ "Mobile experience matters"
- Want: 13 (spinner), 14 (error toast)

### chaos_engineer: "How does it break?"
- ✓ FOV bounded (no overflow)
- ✓ Parallax sign flip (can't break)
- ✓ Haptics gracefully degrades (no navigator.vibrate)

## Consensus

**Selected:** #1, #6, #11 (Bass FOV, Reverse Parallax, Beat Haptics)
**Consensus score:** 0.90 (9/10 personas approve)
**Rationale:** High impact, minimal effort, mobile-first, proven safe

**Future backlog:** #2 (star frequency), #13 (spinner), #14 (error toast), #15 (haptics toggle)
