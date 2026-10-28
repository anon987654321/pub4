# frozen_string_literal: true

# Per-stock data: grain sigma (legacy), 3x3 colour matrix, and characteristic
# curve [Dmin, Dmax, pivot, gamma] per R/G/B. Dmin lifts shadows (base+fog),
# Dmax caps highlights (shoulder), pivot is the linear midtone fulcrum (≈0.18),
# gamma is contrast (>1 = steeper). Per-channel offsets create stock colour cast.
STOCKS = {
  kodak_portra: { grain: 15, speed: 400,
                  sublayers: [{ sensitivity_shift: 0.0, grain_scale: 1.4, weight: 0.45 },
                               { sensitivity_shift: -0.5, grain_scale: 1.0, weight: 0.55 }],
                  matrix: [1.05, -0.02, -0.03, 0.02, 0.98, 0.00, 0.01, -0.05, 1.04],
                  hd: { r: [0.06, 0.93, 0.18, 1.10], g: [0.05, 0.94, 0.18, 1.10], b: [0.04, 0.92, 0.20, 1.05] } },
  kodak_vision3: { grain: 20, speed: 500,
                   sublayers: [{ sensitivity_shift: 0.3, grain_scale: 1.5, weight: 0.40 },
                                { sensitivity_shift: 0.0, grain_scale: 1.1, weight: 0.35 },
                                { sensitivity_shift: -0.6, grain_scale: 0.85, weight: 0.25 }],
                   matrix: [1.08, -0.05, -0.03, 0.03, 0.95, 0.02, 0.02, -0.08, 1.06],
                   hd: { r: [0.07, 0.95, 0.17, 1.15], g: [0.06, 0.95, 0.18, 1.20], b: [0.08, 0.90, 0.20, 1.10] } },
  kodak_vision3_50d: { grain: 8, speed: 50, matrix: [1.06, -0.03, -0.02, 0.02, 0.96, 0.01, 0.01, -0.05, 1.04],
                       hd: { r: [0.05, 0.95, 0.18, 1.08], g: [0.04, 0.95, 0.18, 1.12], b: [0.03, 0.93, 0.20, 1.05] } },
  kodak_vision3_500t: { grain: 20, speed: 500, matrix: [1.10, -0.06, -0.04, 0.04, 0.94, 0.03, 0.04, -0.10, 1.09],
                        hd: { r: [0.07, 0.95, 0.18, 1.18], g: [0.06, 0.95, 0.18, 1.18], b: [0.08, 0.93, 0.19, 1.16] },
                        focal_plane_offset: 1.1 },
  cinestill_800t: { grain: 22, speed: 800,
                    sublayers: [{ sensitivity_shift: 0.4, grain_scale: 1.6, weight: 0.35 },
                                 { sensitivity_shift: 0.0, grain_scale: 1.2, weight: 0.40 },
                                 { sensitivity_shift: -0.5, grain_scale: 0.9, weight: 0.25 }],
                    matrix: [1.12, -0.07, -0.05, 0.04, 0.93, 0.03, 0.05, -0.12, 1.10],
                    hd: { r: [0.08, 0.96, 0.18, 1.20], g: [0.07, 0.95, 0.18, 1.20], b: [0.09, 0.92, 0.19, 1.18] },
                    halation: 0.8, focal_plane_offset: 1.2 },
  ektachrome_100: { grain: 10, speed: 100, matrix: [1.08, -0.04, -0.04, 0.02, 1.02, -0.02, 0.01, -0.08, 1.07],
                    hd: { r: [0.02, 0.97, 0.18, 1.30], g: [0.02, 0.97, 0.18, 1.35], b: [0.03, 0.96, 0.20, 1.25] } },
  fuji_velvia: { grain: 8, speed: 50, matrix: [1.12, -0.08, -0.04, 0.05, 1.05, -0.02, 0.01, -0.12, 1.11],
                 hd: { r: [0.02, 0.97, 0.18, 1.45], g: [0.02, 0.98, 0.18, 1.50], b: [0.03, 0.95, 0.20, 1.40] } },
  tri_x: { grain: 25, speed: 400, matrix: [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
            hd: { r: [0.05, 0.95, 0.18, 1.30], g: [0.05, 0.95, 0.18, 1.30], b: [0.05, 0.95, 0.18, 1.30] } },
  # Kodachrome: steep gamma, no in-film couplers, external development process.
  # Punchy reds, heavy yellow separation, minimal shadow fog.
  kodachrome: { grain: 12, speed: 64, matrix: [1.15, -0.10, -0.05, 0.03, 1.00, -0.03, 0.00, -0.10, 1.10],
                hd: { r: [0.02, 0.97, 0.18, 1.42], g: [0.03, 0.97, 0.18, 1.36], b: [0.04, 0.95, 0.20, 1.20] } },

  # --- 2026-07-30 ------------------------------------------------------------
  # Nine stocks, and seven of them Kodak. The table could do warm-and-forgiving
  # (Portra), cine (Vision3), saturated reversal (Velvia) and one black and
  # white — and nothing else at all: no fast grainy B&W, no cool palette, no
  # instant film, no saturated NEGATIVE as opposed to slide.
  #
  # Each new entry carries a row in all five per-stock tables below it, because
  # a stock missing from GRAIN_CHAN_SCALE silently grains like Portra, one
  # missing from PUSH_RESPONSE pushes like Portra, and one missing from
  # FILM_BASE has no base fog. vocab-check now refuses a stock with a gap.

  # Reportage black and white. Enormous latitude, forgiving of being wrong by
  # two stops in either direction, and grainier than Tri-X at the same speed.
  ilford_hp5: { grain: 22, speed: 400,
                sublayers: [{ sensitivity_shift: 0.2, grain_scale: 1.35, weight: 0.5 },
                            { sensitivity_shift: -0.4, grain_scale: 1.0, weight: 0.5 }],
                matrix: [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
                hd: { r: [0.06, 0.94, 0.18, 1.22], g: [0.06, 0.94, 0.18, 1.22], b: [0.06, 0.94, 0.18, 1.22] } },

  # Available darkness. Nominally 3200 and actually closer to 1000 pushed hard,
  # which is why the grain is enormous and the highlights never reach full
  # density -- the low Dmax here is the stock, not an error.
  ilford_delta3200: { grain: 38, speed: 3200,
                      sublayers: [{ sensitivity_shift: 0.6, grain_scale: 1.9, weight: 0.45 },
                                  { sensitivity_shift: 0.0, grain_scale: 1.3, weight: 0.35 },
                                  { sensitivity_shift: -0.5, grain_scale: 1.0, weight: 0.20 }],
                      matrix: [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
                      hd: { r: [0.11, 0.88, 0.18, 1.08], g: [0.11, 0.88, 0.18, 1.08], b: [0.11, 0.88, 0.18, 1.08] } },

  # The saturated NEGATIVE, which is a different animal from a saturated slide:
  # Velvia's colour comes with Velvia's two-stop latitude, Ektar's does not.
  # Reds are the point.
  kodak_ektar100: { grain: 6, speed: 100,
                    matrix: [1.14, -0.09, -0.05, 0.02, 1.03, -0.05, 0.00, -0.09, 1.09],
                    hd: { r: [0.03, 0.96, 0.18, 1.34], g: [0.03, 0.96, 0.18, 1.32], b: [0.04, 0.94, 0.20, 1.28] } },

  # The cool one. Everything else in this table warms; Pro 400H leans green and
  # cyan and holds pastel skin, which is the whole reason it was worth having.
  fuji_pro400h: { grain: 16, speed: 400,
                  sublayers: [{ sensitivity_shift: 0.1, grain_scale: 1.25, weight: 0.45 },
                              { sensitivity_shift: -0.45, grain_scale: 0.95, weight: 0.55 }],
                  matrix: [0.97, 0.02, 0.01, -0.02, 1.02, 0.00, 0.00, 0.04, 1.02],
                  hd: { r: [0.05, 0.92, 0.18, 1.05], g: [0.05, 0.93, 0.18, 1.06], b: [0.06, 0.93, 0.20, 1.04] } },

  # Instant film. High base fog, a Dmax that never gets near black, and a gamma
  # under 1 -- an integral print developing in daylight in ninety seconds cannot
  # do contrast, and that softness is the look.
  polaroid_sx70: { grain: 14, speed: 150,
                   matrix: [1.06, 0.02, -0.04, 0.01, 0.98, 0.03, 0.03, 0.02, 0.99],
                   hd: { r: [0.15, 0.86, 0.20, 0.95], g: [0.14, 0.85, 0.20, 0.93], b: [0.13, 0.84, 0.22, 0.90] } },
}.freeze

# Black-and-white stocks record one silver image of the scene's luminance. Their
# equal per-channel curves only discard a colour cast, so a chain on one of them
# kept the photograph's colour (a "silver gelatin" take came out in colour).
# film_curve develops these from a panchromatic luminance image instead.
MONOCHROME_STOCKS = %i[tri_x ilford_hp5 ilford_delta3200].freeze

def panchromatic(image)
  r, g, b = rgb_bands(image).cast("float").bandsplit
  luma = r * 0.2126 + g * 0.7152 + b * 0.0722
  luma.bandjoin([luma, luma]).copy(interpretation: :srgb)
end

# Lens character: data-driven table drives vintage_lens().
# vignette/glow/micro_contrast/chroma are intensity multipliers [0,1].
LENSES = {
  zeiss: { micro_contrast: 0.40, flare: 0.08 },
  leica: { micro_contrast: 0.45, glow: 0.25 },
  helios: { micro_contrast: 0.30, chroma: 0.05 },
  cooke: { micro_contrast: 0.20, warmth: 0.10 },
  anamorphic: { micro_contrast: 0.25, chroma: 0.08, flare: 0.50 },
  # A lens is defined as much by how it fails as by how it resolves, and the
  # five above are all variations on "sharp, with a little something". These
  # are the failures: a Petzval that only holds the centre, uncoated glass that
  # veils, a plastic Lomo meniscus, a soft-focus portrait lens that halates on
  # purpose. Only the modern Summicron entry is another sharp one, and it is
  # there so there is something at the top of the range to compare against.
  petzval: { micro_contrast: 0.35, glow: 0.18, chroma: 0.06 },
  takumar: { micro_contrast: 0.28, warmth: 0.16, glow: 0.10 },
  lomo: { micro_contrast: 0.12, chroma: 0.10, glow: 0.16, flare: 0.18 },
  soft_focus: { micro_contrast: 0.08, glow: 0.45 },
  uncoated: { micro_contrast: 0.18, glow: 0.20, flare: 0.35, warmth: 0.08 },
  summicron: { micro_contrast: 0.50, flare: 0.04 },
}.freeze

# Per-stock R/G/B channel amplitude ratios for grain — mirrors the three
# dye-layer sensitivities. Red layer is reference (1.00), green and blue
# attenuated to match the stock's measured dye-cloud statistics.
GRAIN_CHAN_SCALE = {
  kodak_portra: [1.00, 0.85, 0.70],
  kodak_vision3: [1.00, 0.90, 0.80],
  kodak_vision3_50d: [1.00, 0.88, 0.75],
  kodak_vision3_500t: [1.00, 0.88, 0.72],
  cinestill_800t: [1.05, 0.88, 0.75],
  ektachrome_100: [0.95, 0.95, 1.05],
  fuji_velvia: [1.00, 1.10, 0.90],
  tri_x: [1.00, 1.00, 1.00],
  kodachrome: [1.00, 0.92, 0.82],
  ilford_hp5: [1.00, 1.00, 1.00],
  ilford_delta3200: [1.00, 1.00, 1.00],
  kodak_ektar100: [1.00, 0.86, 0.72],
  fuji_pro400h: [0.96, 0.92, 0.86],
  polaroid_sx70: [1.00, 0.94, 0.88],
}.freeze

# Per-channel spatial frequency ratios for grain — red layer (σ×1.00) is coarsest,
# blue (σ×0.72) finest, matching measured dye-cloud PSF widths per layer depth.
GRAIN_CHANNEL_SPATIAL = [1.00, 0.85, 0.72].freeze

# Lognormal grain amplitude distribution. Silver halide crystals cluster in groups;
# the cluster field drives amplitude modulation on top of the base Perlin layer.
GRAIN_LOGNORM_SIGMA = 0.55
GRAIN_LOGNORM_MEAN = Math.exp(GRAIN_LOGNORM_SIGMA**2 / 2.0)

# Print film stocks: H&D per channel, warmth triplet, grain amplitude.
# Applied as a final projection stage emulating contact or optical printing.
PRINT_STOCKS = {
  kodak_2383: {
    hd: { r: [0.03, 0.98, 0.18, 1.38], g: [0.02, 0.97, 0.18, 1.34], b: [0.04, 0.96, 0.18, 1.28] },
    grain: 3, warmth: 0.055, cool_shadow: 0.042
  },
  kodak_2302: {
    hd: { r: [0.05, 0.95, 0.18, 1.50], g: [0.05, 0.95, 0.18, 1.50], b: [0.05, 0.95, 0.18, 1.50] },
    grain: 5,
  },
}.freeze

# Per-stock reciprocity failure color shifts. Blue layer lags most under long
# exposures; green-magenta crossover happens first. Offsets in scRGB units per
# decade of EV (ev = log2(secs) / 10).
RECIPROCITY_SHIFT = {
  cinestill_800t: { r: 0.02, g: -0.04, b: 0.14 },
  kodak_vision3_500t: { r: 0.01, g: -0.03, b: 0.11 },
  kodak_vision3: { r: 0.01, g: -0.03, b: 0.10 },
  tri_x: { r: 0.02, g: -0.05, b: 0.16 },
  kodak_portra: { r: 0.01, g: -0.02, b: 0.09 },
  # Four of the nine stocks had no row here and one had none in PUSH_RESPONSE,
  # so reciprocity_failure and push_pull fell through to a hard-coded default
  # and every one of those stocks failed reciprocity like Portra. Reversal
  # stocks in fact fail hardest and fastest -- Velvia is notorious for going
  # green past a few seconds -- which is the opposite of the default they got.
  kodak_vision3_50d: { r: 0.01, g: -0.02, b: 0.08 },
  ektachrome_100: { r: 0.03, g: -0.06, b: 0.13 },
  fuji_velvia: { r: 0.04, g: -0.08, b: 0.15 },
  kodachrome: { r: 0.03, g: -0.05, b: 0.12 },
  ilford_hp5: { r: 0.02, g: -0.05, b: 0.15 },
  ilford_delta3200: { r: 0.03, g: -0.06, b: 0.18 },
  kodak_ektar100: { r: 0.02, g: -0.04, b: 0.11 },
  fuji_pro400h: { r: 0.01, g: -0.03, b: 0.10 },
  polaroid_sx70: { r: 0.04, g: -0.03, b: 0.09 },
}.freeze

# Per-stock push response ratios. Blue dye layer develops faster under push;
# green is the reference (1.00). Ratios are per-stop multipliers relative to
# the nominal exposure-doubling factor.
PUSH_RESPONSE = {
  kodak_vision3_500t: { g: 1.00, b: 0.92 },
  kodak_vision3: { g: 1.00, b: 0.93 },
  cinestill_800t: { g: 0.97, b: 0.89 },
  kodak_portra: { g: 1.00, b: 0.94 },
  tri_x: { g: 1.00, b: 0.97 },
  fuji_velvia: { g: 1.00, b: 0.88 },
  ektachrome_100: { g: 0.99, b: 0.91 },
  kodachrome: { g: 0.98, b: 0.90 },
  kodak_vision3_50d: { g: 1.00, b: 0.95 },
  # HP5 and Delta are the two stocks people actually push, and they take it
  # better than anything else here.
  ilford_hp5: { g: 1.00, b: 0.98 },
  ilford_delta3200: { g: 1.00, b: 0.99 },
  kodak_ektar100: { g: 0.99, b: 0.90 },
  fuji_pro400h: { g: 1.00, b: 0.96 },
  # An instant print cannot be pushed at all; development is fixed by the pod.
  polaroid_sx70: { g: 1.00, b: 1.00 },
}.freeze

# Stocks with integral colored couplers (C-41 process) — get orange mask treatment.
C41_STOCKS = %i[
  kodak_portra kodak_vision3 kodak_vision3_50d kodak_vision3_500t cinestill_800t
  kodak_ektar100 fuji_pro400h
].freeze

# Per-stock film base density tints. Each emulsion has a characteristic base fog
# color: C-41 negatives are orange-masked; reversal stocks are nearly neutral;
# B&W silver prints are pure white. Applied at low opacity over the whole frame
# so dark areas pick up the tint more than highlights (density-sensitive).
FILM_BASE = {
  kodak_portra: [255, 245, 228],
  kodak_vision3: [255, 246, 226],
  kodak_vision3_50d: [255, 248, 232],
  kodak_vision3_500t: [255, 247, 225],
  cinestill_800t: [255, 243, 218],
  ektachrome_100: [248, 250, 255],
  fuji_velvia: [250, 251, 255],
  tri_x: [255, 255, 255],
  kodachrome: [255, 246, 222],
  ilford_hp5: [255, 255, 255],
  ilford_delta3200: [255, 255, 255],
  kodak_ektar100: [255, 244, 224],
  fuji_pro400h: [255, 247, 233],
  # An instant print has no film base at all — the "base" is the white receiving
  # sheet, and what tints it is the reagent, which reads warm.
  polaroid_sx70: [255, 250, 240],
}.freeze
