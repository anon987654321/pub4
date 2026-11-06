# frozen_string_literal: true

# Filmic shoulder + toe: raised shadow floor + soft highlight rolloff.
# Models the analog curve endpoints without stock-specific emulsion data.
def film_shoulder(image, intensity = 0.75)
  toe = intensity * 0.04 * 255.0
  lifted = image.linear([1.0 - intensity * 0.04], [toe])
  highlight_roll(lifted, (220 - (intensity * 20).to_i), intensity * 0.50)
    .then { |rolled| safe_cast(rolled) }
rescue StandardError => e
  $logger.error "film_shoulder: #{e.message}"; image
end

# Clarity: medium-radius unsharp on Lab L channel only — local contrast "3D pop"
# without hue shift or color fringing.
def clarity(image, radius = 15, intensity = 0.65)
  lab = image.colourspace("lab")
  l = lab.extract_band(0)
  a_ch = lab.extract_band(1)
  b_ch = lab.extract_band(2)
  detail = l - l.gaussblur(radius)
  l_new = l + detail.linear([intensity * 0.40], [0.0])
  safe_cast(Vips::Image.bandjoin([l_new, a_ch, b_ch]).colourspace("srgb"))
rescue StandardError => e
  $logger.error "clarity: #{e.message}"; image
end

# Edge-aware noise reduction: smooth flat areas, preserve edges.
# Approximated as luminance-masked Gaussian — clean base before film grain is added.
def edge_aware_nr(image, strength = 0.60)
  blurred = image.gaussblur(1.5 + strength * 2.0)
  quick = image.gaussblur(1.5)
  # `(image - quick) + (quick - image)` is a value plus its own negation:
  # identically zero at every pixel, so the mask was always 0 and this returned
  # a plain full-frame blur — measured bit-identical to gaussblur alone. The
  # edge term wants the magnitude of the detail, which is what selective_sharpen
  # sixteen lines below was already corrected to use.
  detail = image.cast("float") - quick.cast("float")
  edge_luma = ((detail.extract_band(0) * 0.299) +
               (detail.extract_band(1) * 0.587) +
               (detail.extract_band(2) * 0.114)).abs
  mask = (edge_luma > (12.0 * (1.0 - strength * 0.5))).ifthenelse(1, 0)
  mask3 = mask.bandjoin([mask, mask])
  safe_cast(image * mask3 + blurred * mask3.linear([-1.0], [1.0]))
rescue StandardError => e
  $logger.error "edge_aware_nr: #{e.message}"; image
end

# Selective sharpening: high-pass at σ=1.2, applied only at high-edge regions.
# Lifts perceived acuity at detail without amplifying noise in smooth areas.
def selective_sharpen(image, intensity = 0.70)
  blurred = image.cast("float").gaussblur(1.2)
  detail = image.cast("float") - blurred
  # edge_diff was `detail + (blurred - image)`, which is (image - blurred) plus
  # its own negation: identically zero, at every pixel, for every image. The
  # mask was therefore always 0, mask3 always 0, and the return value always
  # `image + detail * 0`. Selective sharpening has never sharpened anything --
  # including in quality_uplift, the preset that exists to sharpen.
  #
  # What the mask wants is where detail is LARGE, which is its magnitude.
  edge_luma = ((detail.extract_band(0) * 0.299) +
               (detail.extract_band(1) * 0.587) +
               (detail.extract_band(2) * 0.114)).abs
  mask = (edge_luma > 8).ifthenelse(1, 0)
  mask3 = mask.bandjoin([mask, mask])
  safe_cast(image + detail * mask3 * (intensity * 0.55))
rescue StandardError => e
  $logger.error "selective_sharpen: #{e.message}"; image
end

# Complementary grading as a colourist does it: shadows toward teal, highlights
# toward warm, each by a luminance key, with skin held back by a hue key so
# faces stay faces. It used to apply flat gains to every pixel (red x1.25 + 8,
# blue x1.35), which is a colour cast rather than a grade, and it was the effect
# most associated with destroyed takes (96% against 58% without it, 2026-10-27).
TEAL_SHIFT = [-0.05, 0.015, 0.06].freeze
ORANGE_SHIFT = [0.06, 0.02, -0.05].freeze
TEAL_ORANGE_SKIN_HOLD = 0.85

def teal_orange(image, intensity = 1.0)
  colour = image.cast("float") / 255.0
  luma = clamp01(image.colourspace("b-w").cast("float") / 255.0)
  free = skin_key(image).gaussblur(2).linear(-TEAL_ORANGE_SKIN_HOLD, 1.0) * intensity
  shadows = (luma.linear(-1, 1)**2) * free
  highlights = (luma**2) * free
  shifted = colour.bandsplit.each_with_index.map do |channel, i|
    channel + shadows * TEAL_SHIFT[i] + highlights * ORANGE_SHIFT[i]
  end
  safe_cast(clamp01(Vips::Image.bandjoin(shifted)) * 255.0)
rescue StandardError => e
  $logger.error "teal_orange: #{e.message}"; image
end

# A diffusion filter (a Pro-Mist): glass in front of the lens scatters a share
# of every point's light into a wide kernel. It conserves energy, so it is a mix
# in linear light, (1 - p) * E + p * (K * E), with no threshold: highlights glow
# because they have the most light to spread, shadows lift a little from their
# neighbours, and the frame's total light is unchanged. K is a core, a halo and a
# long bloom, after spektrafilm's Pro-Mist family (weights 0.28, 0.42, 0.30), and
# p rises with strength as theirs does, about 0.35 at full. It used to double the
# whole frame and add its blur back, adding light that was never there, so every
# pixel glowed and the picture went milky.
BLOOM_KERNEL = [[1.0 / 400, 0.28], [1.0 / 60, 0.42], [1.0 / 15, 0.30]].freeze
BLOOM_MIX = 0.35

def bloom_pro(image, intensity = 1.0)
  linear = image.colourspace("scrgb")
  spread = BLOOM_KERNEL.map { |reach, weight| linear.gaussblur([image.width * reach, 0.5].max) * weight }.reduce(:+)
  mix = (BLOOM_MIX * intensity).clamp(0.0, 0.9)
  safe_cast(clamp01(linear * (1.0 - mix) + spread * mix).colourspace("srgb"))
rescue StandardError => e
  $logger.error "bloom_pro: #{e.message}"; image
end

# Halation in linear (exposure) space. Bright light penetrates the emulsion,
# reflects off the substrate's antihalation backing imperfectly, and re-exposes
# nearby grains. Red wavelengths penetrate deepest, so the rebound glow is
# red-orange — never neutral. Default tint matches Vision3-style stocks; Velvia
# antihalation is near-perfect (drop intensity), Tri-X has none (boost it).
# Pipeline: linearize → soft-threshold highlights at L≈0.7 → wide gaussian on
# the mono source map → tint asymmetrically (R>G>>B) → add back → re-encode.
# Physics-calibrated: fraction of incident energy reflected per dye layer depth.
# Red penetrates deepest (0.92), green mid-layer (0.15), blue nearest surface (0.04).
HALATION_TINT_VISION3 = [0.92, 0.15, 0.04].freeze
HALATION_TINT_PORTRA = [0.88, 0.12, 0.04].freeze
HALATION_TINT_TRI_X = [0.45, 0.45, 0.45].freeze
HALATION_THRESHOLD = 0.7
# Halation is an annulus. Light that gets through the emulsion reflects off the
# rear face of the base by total internal reflection and re-enters the emulsion
# a base-thickness away, so it re-exposes a ring around the highlight — not a
# halo centred on it. This summed a narrow and a wide Gaussian, which puts the
# most returned light exactly where the highlight already is, the one place it
# cannot land. A difference of Gaussians is the ring; the narrow lobe stays on
# as the scatter that never left the emulsion.
HALATION_SCATTER = 0.25
# A difference of Gaussians keeps a fraction of the energy the sum carried, so
# the strength has to come back somewhere. Measured on a probe carrying a blown
# specular, the summed form peaked at 5 levels on the highlight's own edge and
# this peaks at 7 a little outside it, which is the move that was wanted.
HALATION_GAIN = 2.6

# Halation: resolution-aware σ ≈ width/45 (≈43px at 2K, calibrated from agx
# emulsion measurements). Luma-based bright mask rather than red-only, so
# over-exposed highlights on any channel trigger the halo. Per-channel blur
# radii R>G>>B model wavelength-dependent penetration depth in the emulsion
# stack. Output clamp prevents HDR overshoot from adding solarization.
# This gates on luma > HALATION_THRESHOLD (0.7) in LINEAR scRGB, where 8-bit
# white is 1.0, so it fires on any real highlight. It belongs before
# film_curve, because it is exposure: light returning into the emulsion before
# anything is developed. Run after the curve, which compresses hard, nothing is
# left above the threshold and the step changes nothing while the log reports
# it ran (found with POSTPRO_EXPLAIN=1). Every preset now orders it first.
# The returned light, as a ring of radius sigma plus the scatter that stayed.
def halation_ring(bright, sigma)
  core = bright.gaussblur([sigma * 0.55, 0.3].max)
  ring = bright.gaussblur(sigma * 1.6) - core
  (ring > 0).ifthenelse(ring, 0) + core * HALATION_SCATTER
end

def halation(image, intensity = 1.0, tint: HALATION_TINT_VISION3)
  sigma_r = [image.width / 45.0, 6.0].max.clamp(6.0, 120.0)
  sigma_g = sigma_r * 0.55
  sigma_b = sigma_r * 0.25
  linear = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  luma = r * 0.2126 + g * 0.7152 + b * 0.0722
  excess = luma.linear([1], [-HALATION_THRESHOLD])
  bright = (excess > 0).ifthenelse(excess, 0) ** 2
  halo = Vips::Image.bandjoin([sigma_r, sigma_g, sigma_b].each_with_index.map do |sigma, band|
    halation_ring(bright, sigma) * (tint[band] * intensity * HALATION_GAIN)
  end)
  safe_cast(clamp01(linear + halo).colourspace("srgb"))
end
