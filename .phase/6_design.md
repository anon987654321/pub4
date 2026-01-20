# Phase 6: Design

**prev_hash:** d29a59c8

## TDD Plan

### Test 1: Bass FOV Changes
**Given:** Audio with bass frequency data
**When:** Bass level increases from 0.0 to 1.0
**Then:** FOV increases from 250 to 300 (250 + 50)
**Verify:** `const fovDynamic=this.fov+(a?.bass||0)*50`

### Test 2: Reversed Parallax
**Given:** Mouse at (100, 100)
**When:** Previously subtracted from center
**Then:** Now added to center
**Verify:** `center.x=(this.w/2+this.mouse.x/this.s)*...` (was `-this.mouse.x`)

### Test 3: Beat Haptics
**Given:** Beat detected (a.beat = true)
**When:** navigator.vibrate available
**Then:** Vibrate for 8ms
**Verify:** `if(a?.beat&&navigator.vibrate){navigator.vibrate(8)}`

### Test 4: New Tracks Playable
**Given:** YouTube tracks array
**When:** Index 20 and 21 accessed
**Then:** kemt and J Dilla tracks load
**Verify:** Lines 150-151 in YOUTUBE_TRACKS

## Implementation Steps

### Step 1: Bass FOV (Line 384-385)
```javascript
// BEFORE:
const sc=this.fov/(this.fov+row[0].z);

// AFTER:
const fovDynamic=this.fov+(a?.bass||0)*50;
const sc=fovDynamic/(fovDynamic+row[0].z);
```
**Status:** ✅ IMPLEMENTED

### Step 2: Reversed Parallax (Lines 372-377)
```javascript
// BEFORE:
center.x=(this.w/2-this.mouse.x/this.s)*...
center.y=(this.w/2-this.mouse.y/this.s)*...
const mx=-this.ori.gamma*(this.w/180)

// AFTER:
center.x=(this.w/2+this.mouse.x/this.s)*...
center.y=(this.w/2+this.mouse.y/this.s)*...
const mx=this.ori.gamma*(this.w/180)
```
**Status:** ✅ IMPLEMENTED

### Step 3: Beat Haptics (Line 590-593)
```javascript
// AFTER viz.frame(a):
if(a?.beat&&navigator.vibrate){
  navigator.vibrate(8);
}
```
**Status:** ✅ IMPLEMENTED

### Step 4: New Tracks (Lines 150-151)
```javascript
{artist:"kemt",title:"close to you",id:"8SQZtBRdSbE"},
{artist:"J Dilla",title:"Motor City 17",id:"OSg9Fwd8QSs"}
```
**Status:** ✅ IMPLEMENTED

## Rollback Plan

### Git Rollback
```bash
# If breaks:
git diff index.html  # Review changes
git checkout -- index.html  # Revert
```

### Manual Rollback (if uncommitted work lost)
**Line 384-385:** Remove `fovDynamic`, restore `const sc=this.fov/(this.fov+row[0].z);`
**Lines 372-377:** Flip signs back (+ → -, remove negation on gamma/beta)
**Lines 590-593:** Delete haptics block
**Lines 150-151:** Delete two track entries

### Verification After Rollback
1. Open in browser (requires GitHub Pages)
2. Verify tunnel renders
3. Verify no console errors
4. Verify tracks play

## Risk Mitigation

**Risk 1:** FOV overflow
- **Mitigation:** Bass clamped 0-1 by analyser, max FOV = 250+50 = 300
- **Fallback:** Reduce multiplier from 50 to 30

**Risk 2:** Parallax too sensitive
- **Mitigation:** Division factor `/500` dampens movement
- **Fallback:** Increase divisor to `/750`

**Risk 3:** Haptics drain battery
- **Mitigation:** 8ms is minimal (navigator.vibrate spec)
- **Fallback:** Add toggle in future release (Phase 4, Alternative #15)

**Risk 4:** Browser test impossible locally
- **Mitigation:** Deploy to GitHub Pages first
- **Fallback:** User tests after deployment
