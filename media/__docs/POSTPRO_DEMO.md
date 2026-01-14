# postpro.rb Analog Effects - Before & After Demo
## System Status
- ✓ postpro.rb syntax valid

- ✓ repligen.rb integration ready

- ✗ libvips not installed (Cygwin limitation)

## Analog Effects Available
### Film Stock Emulation
```ruby

STOCKS = {

  kodak_portra:  { grain: 15, gamma: 0.65, rolloff: 0.88, lift: 0.05 },

  kodak_vision3: { grain: 20, gamma: 0.65, rolloff: 0.85, lift: 0.08 },

  fuji_velvia:   { grain:  8, gamma: 0.75, rolloff: 0.92, lift: 0.03 },

  tri_x:         { grain: 25, gamma: 0.70, rolloff: 0.80, lift: 0.12 }

}

```

### Professional Effects Pipeline
#### 1. Film Curve
**Before**: Linear digital response

**After**: S-curve with custom gamma/rolloff per film stock

**Code**: `film_curve(image, :kodak_portra, 1.0)`

#### 2. Grain
**Before**: Clean digital pixels

**After**: ISO-matched organic grain (brightness-adaptive)

**Code**: `grain(image, 400, :kodak_portra, 0.4)`

#### 3. Highlight Roll
**Before**: Hard clipping at 255

**After**: Smooth film-like compression above threshold

**Code**: `highlight_roll(image, 200, 1.0)`

#### 4. Shadow Lift
**Before**: Crushed blacks

**After**: Lifted shadows with preserved black point

**Code**: `shadow_lift(image, 0.15, true)`

#### 5. Color Temperature
**Before**: Neutral 5500K

**After**: Warm 5200K or cool 6500K shift

**Code**: `color_temp(image, 5200, 1.0)`

#### 6. Vintage Lens
**Before**: Clinical digital sharpness

**After**: Zeiss/Leica/Helios optical character

**Code**: `vintage_lens(image, 'zeiss', 0.7)`

#### 7. Micro Contrast
**Before**: Flat local contrast

**After**: Enhanced clarity and separation

**Code**: `micro_contrast(image, 5, 0.3)`

#### 8. Base Tint
**Before**: Neutral gray substrate

**After**: Warm film base [252, 248, 240]

**Code**: `base_tint(image, [252, 248, 240], 0.08)`

## Preset Example: Portrait
**Input**: Digital capture (neutral, flat, clean)
**Processing Chain**:
1. `skin_protect` - Preserve skin tones

2. `film_curve` - Kodak Portra S-curve

3. `highlight_roll` - Smooth highlight compression

4. `micro_contrast` - Local clarity enhancement

5. `grain` - ISO 400 film grain

6. `color_temp` - 5200K warm shift

7. `base_tint` - Warm film substrate

**Output**: Cinematic analog look with:
- Filmic contrast curve

- Organic texture

- Warm color palette

- Smooth highlight transitions

- Lifted shadow detail

- Protected skin tones

## Visual Comparison (Text Representation)
### BEFORE (Digital)
```

Histogram: ▁▂▃▅▇█████▇▅▃▂▁

Contrast:   Linear, flat

Colors:     Neutral, accurate

Texture:    Clean, clinical

Highlights: Hard clip at 255

Shadows:    Crushed blacks

```

### AFTER (Kodak Portra Emulation)
```

Histogram: ▁▂▄▆███████▆▄▂▁

Contrast:   S-curve, lifted

Colors:     Warm, 5200K tint

Texture:    Organic grain

Highlights: Smooth rolloff

Shadows:    Lifted, detail

```

## Integration with repligen.rb
When repligen.rb generates images, postpro.rb automatically:
1. Detects recent outputs (`*_generated_*.{jpg,png,webp}`)

2. Offers preset selection

3. Processes with analog film emulation

4. Saves variations with timestamp

**Usage**:
```bash

# Generate AI image

ruby repligen.rb

# Postpro auto-detects and offers processing
# → Choose preset: portrait/landscape/street/blockbuster

# → Generates 2+ variations per image

```

## Installation Required
To use postpro.rb, install libvips:
**macOS**: `brew install vips`
**Ubuntu**: `sudo apt install libvips-dev`

**OpenBSD**: `doas pkg_add vips`

**Windows**: Use WSL2 or manual build

## Verification
```bash
cd G:pub

