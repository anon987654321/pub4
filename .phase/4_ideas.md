# Phase 4: Ideate

**prev_hash:** 4ec27846

## Alternatives (15 minimum)

### Audio Enhancements
- 1. **Bass-Reactive FOV** ✓ SELECTED - FOV pulses ±50px with bass
- 2. **Frequency-Reactive Star Field** - Stars pulse with high frequencies
- 3. **Mid-Range Ring Color Shift** - Ring hue shifts with mid frequencies
- 4. **Beat-Synced Camera Shake** - Subtle screen shake on beat
- 5. **Audio Waveform Background** - Draw waveform behind tunnel

### Interaction Enhancements
- 6. **Reversed Parallax** ✓ SELECTED - Tunnel moves opposite to mouse/tilt
- 7. **Pinch Zoom for FOV** - Mobile gesture controls FOV
- 8. **Double-Tap Fullscreen** - Already exists (line 511)
- 9. **Swipe Velocity Affects Speed** - Faster swipe = faster tunnel
- 10. **Gyro Intensity Slider** - User controls tilt sensitivity

### Mobile UX
- 11. **Beat Haptics** ✓ SELECTED - Vibrate on beat detection
- 12. **Track Change Flash** - Brief white flash on transition
- 13. **Loading Spinner for YouTube** - Show loading state
- 14. **Error Recovery Toast** - Notify on track load failure
- 15. **Haptics Toggle Button** - Disable vibration for battery

### Visual Polish
- 16. **Depth-Based Alpha Fade** - Distant rings fade transparency
- 17. **Star Field Trails** - Stars leave fading trails
- 18. **Beat Glow Rings** - Extra ring glow on beat
- 19. **Track Transition Crossfade Visual** - Fade tunnel color on track change
- 20. **Performance Stats Overlay** - Optional FPS/quality display

### Code Quality (YAGNI)
- 21. **Extract Magic Numbers** - Move to constants
- 22. **Split Long Functions** - Break _loadYT into smaller pieces
- 23. **Add JSDoc Comments** - Document complex functions
- 24. **Do Nothing** - Ship as-is, accept violations

**Selected:** 1, 6, 11 (already implemented)
**Future Candidates:** 2, 13, 14, 15 (low-hanging fruit)
