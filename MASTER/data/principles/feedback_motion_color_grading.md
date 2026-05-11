---
name: Smooth motion graphics, professional color grading
description: All transitions/animations use easing curves; palettes follow cinema-grade color science (complementary tones, lift/gamma/gain), not raw primaries
type: feedback
originSessionId: 285acce4-505e-4b41-82ff-f88e72ee1535
---
Motion: every state change interpolates with an easing curve (ease-out-cubic for arrivals, ease-in-out for cross-fades), never snaps. Pulse rings, scatter decay, mode transitions, message appear/fade — all eased. Frame-independent (use dt, not fixed step counts).

Color: think DP/colorist. Pick complementary anchors (teal/orange, cyan/amber, magenta/cyan), control saturation per mood, define shadow/midtone/highlight triplets rather than single hex. Mode palette changes cross-fade RGB over ~600ms.

**Why:** User reads as architect/designer. The current dmesg sepia (#cdc5b6 / #0a0c0a / #1f221d) is the floor — every additional surface should feel like a graded short film, not default canvas demos.

**How to apply:**
- Animations: `easeOutCubic(t) = 1 - Math.pow(1-t, 3)`, `easeInOutCubic(t) = t<.5 ? 4*t*t*t : 1-Math.pow(-2*t+2,3)/2`
- Palette per mood = `{shadow, midtone, highlight, accent}` triple, never one color
- Pulse rings: ease radius growth + ease alpha decay
- Mode cross-fade: lerp palette RGB over 600ms before snapping
- Mood color grade examples — focused: cool teal/cyan; curious: amber/cream; tense: red shadow + sodium highlight; weary: muted slate; idle: dmesg sepia
- Avoid: linear timing, snap palette swaps, single-hex moods, fully saturated primaries
