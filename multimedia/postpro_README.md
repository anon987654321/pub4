# postpro.rb — film emulation

Photographic post-processing in Ruby + libvips. Treats every operation as
physics: Hurter-Driffield characteristic curves baked into per-channel LUTs,
halation in linear exposure space, Newson-Delon density-space grain. No "make
it look like film" shortcuts — model the chemistry, output the light.

## Install

```
# OpenBSD
doas pkg_add vips

# Ubuntu / Debian
sudo apt install libvips-dev

# macOS
brew install vips

# Ruby
gem install ruby-vips tty-prompt json
ruby -e "require 'vips'; puts Vips::VERSION"
```

## Usage

Interactive menu:
```
ruby postpro.rb
```

Preset on a glob:
```
ruby postpro.rb --preset portrait 'photos/**/*.jpg'
```

JSON recipe:
```json
{
  "film_curve": { "stock": "kodak_portra", "intensity": 0.9 },
  "halation":   { "intensity": 0.6 },
  "grain":      { "iso": 400, "stock": "kodak_portra", "intensity": 0.5 },
  "color_temp": { "kelvin": 5200, "intensity": 0.6 }
}
```

## Pipeline

Every effect that touches light operates in linearized sRGB (`scrgb`, float
[0,1]) and re-encodes only at the end. The reasons:

- Light adds linearly. Bloom, halation, lens flare, grain envelope — all of
  it is photometrically wrong if you blur in display gamma.
- Per-channel film LUTs assume a known midtone fulcrum (≈0.18 linear) for
  the pivot of the toe/shoulder split. sRGB maps that to ~0.46 display, not
  0.5.

libvips note: `colourspace('b-w')` always returns uchar [0,255] regardless
of source. For linear-space luma, compute `0.2126R + 0.7152G + 0.0722B`
manually. `Numeric#coerce` is not defined on `Vips::Image`, so `1 - image`
fails — use `image.linear(-1, 1)` (computes `-1·x + 1`) instead.

## Film stocks

Each stock carries a 256-entry LUT per R/G/B baked from an H&D
characteristic curve `[Dmin, Dmax, pivot, gamma]`. Pivot is the linear
midtone fulcrum (~0.18 for ISO-calibrated film), gamma is contrast (>1
steeper), Dmin lifts shadows (base+fog), Dmax caps highlights (shoulder).
Per-channel offsets create the stock's colour cast.

| Stock         | Grain σ | R γ  | G γ  | B γ  | Character             |
|---------------|---------|------|------|------|-----------------------|
| Kodak Portra  | 15      | 1.10 | 1.10 | 1.05 | Warm skin, neutral    |
| Kodak Vision3 | 20      | 1.15 | 1.20 | 1.10 | Tungsten cinema       |
| Fuji Velvia   |  8      | 1.45 | 1.50 | 1.40 | Punchy, saturated     |
| Tri-X         | 25      | 1.30 | 1.30 | 1.30 | B&W identity matrix   |

Numbers from `STOCKS[…][:hd][…]` in postpro.rb.

## Effects

### Tone

- `film_curve(stock, intensity)` — apply the per-channel H&D LUT. Single
  `maplut` at runtime; CPU spent only on cache miss.
- `highlight_roll(threshold, intensity)` — soft compression above threshold,
  preserves shoulder.
- `shadow_lift(amount, preserve_blacks)` — toe lift, optional black-floor
  clamp.
- `micro_contrast(radius, intensity)` — local contrast via unsharp mask
  with no global brightness shift.

### Colour

- `color_temp(kelvin, intensity)` — CIE-based per-channel multipliers.
  <5500K warms (boosts R, dampens B), >5500K cools.
- `spectral_temp(source_kelvin, target_kelvin, intensity)` — the same idea
  but spectrally exact. Each pixel's RGB is upsampled to a 31-sample
  spectrum via a Gaussian basis calibrated under D65, reweighted by
  Planckian illuminants at source and target Kelvin, then re-integrated
  against CIE 1931 2° CMFs and projected back to sRGB. All operations are
  linear, so the entire pipeline collapses to a single 3×3 `recomb`
  matrix at runtime — applied in linear scrgb. At source = target the
  matrix is exactly identity; at 5500→3200K the R channel rises ~29% while
  B drops to ~47% (correct tungsten signature); at 5500→8000K the inverse.
  Cross-channel coupling reflects black-body physics, not a per-channel
  fudge.
- `teal_orange(intensity)` — skin-protected blockbuster grade. R/B push,
  G dampen, with HSV skin mask exempting faces.
- `color_separate(intensity)` — analog colour-separation characteristic
  (slight per-channel band offset).
- `base_tint(color, intensity)` — film base colour multiply-screen blend
  (default warm cream).

### Light

`halation(intensity, tint:, sigma_div:)` — light penetrates the emulsion,
reflects off an imperfect antihalation backing, re-exposes nearby grains.
Red wavelengths reach deepest, so the rebound glow is red-orange, not
neutral. Pipeline: linearize → soft-threshold red above L=0.7 (squared) →
gaussian blur σ=width/60 → asymmetric R>G>>B re-add → sRGB on output.

| Stock   | R    | G    | B    | Notes                              |
|---------|------|------|------|------------------------------------|
| Vision3 | 1.0  | 0.35 | 0.08 | Imperfect antihalation backing     |
| Portra  | 1.0  | 0.30 | 0.06 | Slightly warmer rebound            |
| Tri-X   | 0.55 | 0.55 | 0.55 | No antihalation: broadband rebound |

`bloom_pro(intensity)` — two-stage gaussian bloom (σ=8, σ=16) summed at
0.2 weight. Cheaper than halation; works in display gamma. Use for stylised
highlight glow when physical accuracy is not the goal.

### Tonemap

`tonemap(type:, exposure:, intensity:)` — filmic S-curve in linear space
ahead of the film LUT. Exposure is in stops (`+1.0` doubles linear light
pre-curve, `-1.0` halves it). Two curves:

| Type   | Source                                | Notes                                |
|--------|---------------------------------------|--------------------------------------|
| `:aces`| Narkowicz fit to Academy RRT+ODT       | Default. Soft shoulder, slight toe lift, no blowouts |
| `:hable`| Uncharted-2 filmic, W=1.0 for LDR     | More aggressive midtone lift, white pinned to 255    |

Per-channel; chroma drift in the shoulder is the expected filmic look.
Both curves are monotone, photometric, applied before any film LUT so the
H&D curve sees compressed scene-referred light, not display-clipped sRGB.
Pre-multiply HDR sources by exposure stops if needed.

### Grain

`grain(iso, stock, intensity)` — Newson-Delon stochastic grain in linear
sRGB. Three independent per-channel gaussnoise images blurred to
stock-specific spatial σ (Velvia ≈1px, Portra ≈2px, Tri-X ≈3px), modulated
by a midtone visibility envelope `4L(1-L)` so highlights stay clean (no
silver halide density to develop) and shadows soften (max dye-cloud
density). Independence across R/G/B mirrors the three dye layers.

Calibration: target output stddev = `grain · √(iso/100) · intensity / 1600`,
gaussblur attenuation ≈ `0.36 / spatial_sigma` inverted into pre-blur
amplitude. At iso 1600 Tri-X intensity 1.0 the output stddev is ~14 in
red, ~9 in green/blue (8-bit) — clearly visible texture without
destruction. At iso 100 Velvia intensity 1.0 the output stddev is ~1.7
in red, ~0.9 in green/blue — barely perceptible.

### Lens character

`vintage_lens(type, intensity)`:
- `zeiss` — micro-contrast push, fine detail.
- `leica` — diffuse highlight glow.
- `helios` — high-pass sharpen approximating swirly bokeh.

### Skin

`skin_protect(intensity)` — HSV mask on hue 25.5°-63.75°, saturation
20-60%. Returns a per-pixel exemption mask consumed by `teal_orange` and
similar grades so faces don't shift.

### Experimental

`vhs_basic`, `chroma_basic`, `glitch_basic`, `flare_basic` — degraded
analog effects. Random mode pulls from these for variety.

## Presets

```ruby
PRESETS = {
  portrait:    { fx: %w[skin_protect film_curve highlight_roll micro_contrast grain color_temp base_tint],
                 stock: :kodak_portra,  temp: 5200, intensity: 0.8 },
  landscape:   { fx: %w[film_curve color_separate highlight_roll micro_contrast grain vintage_lens],
                 stock: :fuji_velvia,   temp: 5800, intensity: 0.9 },
  street:      { fx: %w[film_curve shadow_lift micro_contrast vintage_lens grain],
                 stock: :tri_x,         temp: 5600, intensity: 1.0 },
  blockbuster: { fx: %w[tonemap teal_orange halation grain bloom_pro highlight_roll micro_contrast],
                 stock: :kodak_vision3, temp: 4800, intensity: 1.2 }
}
```

## Performance

- Float-pipeline effects (halation, grain) round-trip through
  `colourspace('scrgb')` once each. Two such effects back-to-back cost less
  than one because vips fuses the conversion.
- Single LUT apply (`film_curve`) is ~100× cheaper than per-pixel Ruby math.
- 8K images: 2-4 s per variation on a modern CPU. vips uses SIMD where
  available; OpenBSD vmm guests get scalar fallbacks.
- Memory footprint stays under 500 MB for 8K images. vips streams; do not
  load with `access: :sequential` if you intend to read the source twice.

## Output

```
photo.jpg → photo_<preset>_v<n>_<timestamp>.jpg
```

JPEG Q=95 default. EXIF and ICC profile preserved.
