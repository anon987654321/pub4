# frozen_string_literal: true

# OLPF (optical low-pass filter) simulation. Two-gaussian PSF: sharp core (84%)
# + wide skirt (16%) matches the Lorentzian wings measured on real lens MTFs.
# Below this the lens is sharper than the sampling grid and there is nothing to
# simulate. Needed because of the floors below: they keep gaussblur off zero,
# and in doing so they also meant a sigma scaled down toward nothing still blurred
# at full strength. Asking for a tenth of the defocus produced all of it, so the
# source-aware scaling in preset() had no effect here until this existed.
OPTICAL_BLUR_FLOOR = 0.12

# Light striking the film outside the gate.
#
# Recovered from the first generation of this file, and rebuilt rather than
# restored. The original drew two to eight filled circles at random coordinates,
# which is not what a light leak is: light enters at a cassette seam, a failing
# door hinge or the film gate, so it arrives from a FRAME EDGE and falls off
# inward. A disc in the middle of the picture has no physical account at all.
#
# Built as a distance ramp from one edge, raised to a power for the falloff and
# added rather than blended, because fogging is additive exposure — the emulsion
# receives light it should not have, and the shadows go first. That is also why
# it lifts blacks far more visibly than highlights without any explicit masking.
#
# The warm colour is not a style choice. A leak is usually red-to-orange because
# the film base and the cassette felt pass long wavelengths most readily, and
# because the red-sensitive layer sits deepest and takes the most stray light.
#
# Seeded through postpro_seed, so which edge and how wide are reproducible. The
# original called bare rand() and could not be reproduced twice.
LEAK_TINT = [1.00, 0.62, 0.34].freeze

def light_leaks(image, intensity = 0.5, edge: nil)
  return image if intensity <= 0

  picker = Random.new(postpro_seed(31))
  edge ||= %i[left right top bottom][picker.rand(4)]
  # How far across the frame the fog reaches: a seam leak is narrow, a failing
  # back is wide.
  reach = 0.18 + picker.rand * 0.22

  w = image.width
  h = image.height
  # A 0..1 ramp that is 1 at the chosen edge and 0 by `reach` across the frame.
  ramp =
    case edge
    when :left   then Vips::Image.xyz(w, h)[0].linear(-1.0 / (w * reach), 1.0)
    when :right  then Vips::Image.xyz(w, h)[0].linear(1.0 / (w * reach), 1.0 - (1.0 / reach))
    when :top    then Vips::Image.xyz(w, h)[1].linear(-1.0 / (h * reach), 1.0)
    else              Vips::Image.xyz(w, h)[1].linear(1.0 / (h * reach), 1.0 - (1.0 / reach))
    end
  ramp = clamp01(ramp)
  # Squared falloff: a leak has a soft core and a long tail, not a linear wedge.
  ramp = (ramp**2.2) * (255.0 * intensity * 0.55)

  bands = LEAK_TINT.map { |t| ramp * t }
  safe_cast(image.cast("float") + Vips::Image.bandjoin(bands))
rescue StandardError => e
  $logger.error "light_leaks: #{e.message}"; image
end

# Underexposing and cooling a daylight frame to read as moonlight.
#
# Also recovered, and this one was already close to right, because it models a
# real practice rather than an artefact: shoot in daylight, stop down hard,
# print cold. Kept as it was in substance — darken, then lift blue — with the
# random component removed so the same call gives the same result, and the blue
# lift moved onto the shadows where moonlight actually reads.
#
# Not a physical process, unlike everything around it. It is a convention: an
# audience reads cold-and-dark as night because film has always shown it that
# way, and real moonlight is neither as blue nor as directional as this.
def day_for_night(image, intensity = 0.6)
  return image if intensity <= 0

  darkened = image.cast("float").linear([1.0 - (0.42 * intensity)], [-18.0 * intensity])
  r, g, b = darkened.bandsplit
  # Weight the cast toward the low end. A uniform blue gain tints the highlights
  # too, which reads as a filter over a daylight shot rather than as night.
  luma = darkened.colourspace("b-w").cast("float") / 255.0
  shadow_weight = clamp01(luma.linear(-1, 1))
  b = b + (shadow_weight * 26.0 * intensity)
  g = g + (shadow_weight * 6.0 * intensity)
  safe_cast(Vips::Image.bandjoin([r, g, b]))
rescue StandardError => e
  $logger.error "day_for_night: #{e.message}"; image
end

def optical_blur(image, sigma = 0.6)
  return image if sigma < OPTICAL_BLUR_FLOOR

  core = image.gaussblur([sigma * 0.6, 0.3].max)
  skirt = image.gaussblur([sigma * 2.8, 0.5].max)
  safe_cast(core.cast("float") * 0.84 + skirt.cast("float") * 0.16)
rescue StandardError => e
  $logger.error "optical_blur: #{e.message}"; image
end

# Emulsion depth defocus: each dye layer sits at a different depth in the
# multilayer emulsion stack. Blue layer (top, nearest lens) is sharpest;
# red (deepest) sees the most focus spread from incident + substrate-reflected
# light. focal_plane_offset is stock-specific — cinestill_800t (remjet removed)
# has the most scatter; slow daylight stocks have little.
def emulsion_defocus(image, stock = :kodak_portra)
  data = STOCKS[stock] || STOCKS[:kodak_portra]
  offset = data.fetch(:focal_plane_offset, 1.0)
  r, g, b = image.bandsplit
  r2 = offset > 0 ? safe_cast(r.gaussblur(0.6 * offset)) : r
  g2 = offset > 0 ? safe_cast(g.gaussblur(0.3 * offset)) : g
  safe_cast(Vips::Image.bandjoin([r2, g2, b]))
rescue StandardError => e
  $logger.error "emulsion_defocus: #{e.message}"; image
end

# Lateral + longitudinal chromatic aberration. Lateral: R/B registration shift
# at sensor edges. Longitudinal: wavelength-dependent focus depth — blue blurs
# before the focal plane, red sharpest (as in `longitudinal_ca`).
def chromatic_aberration(image, strength = 0.5)
  shift = [(strength * 3.0).round, 1].max
  r, g, b = image.bandsplit
  r2 = r.embed(shift, 0, image.width, image.height)
  b2 = b.embed(-shift, 0, image.width, image.height)
  long_sigma = [strength * 0.9, 0.3].max
  r3 = r2.gaussblur([long_sigma * 0.35, 0.3].max)
  b3 = b2.gaussblur([long_sigma, 0.3].max)
  safe_cast(Vips::Image.bandjoin([r3, g, b3]))
rescue StandardError => e
  $logger.error "chromatic_aberration: #{e.message}"; image
end

# DIR coupler inhibition: development byproducts from one dye layer inhibit
# adjacent layers, slightly desaturating pure hues and sharpening edges.
def dir_coupler(image, strength = 0.15)
  blurred = image.gaussblur(2.0)
  high_pass = image.cast("float") - blurred.cast("float")
  gray = image.colourspace("grey16").colourspace("srgb").cast("float")
  img_f = image.cast("float") / 255.0
  # Lateral inhibition: each dye layer's development byproducts diffuse σ≈0.8px
  # and suppress adjacent layers — desaturates pure hues, sharpens colour edges.
  #
  # The diffusion is on the INHIBITOR, not on the picture. It used to be on
  # both: every band of the output was built from `r_d, g_d, b_d`, the blurred
  # channels, so the whole frame was replaced by a σ=0.8 gaussian of itself and
  # only `strength * 0.5` of the high-pass came back — about 5% at the strength
  # `portrait` calls it with. On a photograph that cost 52% of the picture's
  # texture in one step, which is more than every other effect in the chain
  # combined, while the log reported spread-2.38 and looked unremarkable.
  #
  # It also inverted what the line above claims. A layer's own density is sharp;
  # what reaches it from its neighbours has diffused. Subtracting a blurred
  # neighbour from a sharp channel IS an unsharp mask, so written this way the
  # edge effect falls out of the physics instead of being bolted on after it —
  # which is what "sharpens colour edges" meant.
  r_s, g_s, b_s = img_f.bandsplit
  r_d, g_d, b_d = [r_s, g_s, b_s].map { |ch| ch.gaussblur(0.8) }
  inhibition = Vips::Image.bandjoin([
    r_s - g_d * (0.08 * strength) - b_d * (0.04 * strength),
    g_s - r_d * (0.12 * strength) - b_d * (0.07 * strength),
    b_s - r_d * (0.06 * strength) - g_d * (0.10 * strength),
  ])
  inhibited = clamp01(inhibition) * 255.0
  desatd = inhibited * (1.0 - strength * 0.3) + gray * (strength * 0.3)
  safe_cast((desatd + high_pass * (strength * 0.5)).cast("uchar"))
rescue StandardError => e
  $logger.error "dir_coupler: #{e.message}"; image
end

# Bleach bypass leaves the silver in, and silver is neutral density. On the
# print, Kodak's description: shadows darker and richer, contrast up, colour
# muted. Density adds in log space, so in transmittance every channel is
# multiplied by the scene's own luminance to a power: out = in * Y^k. Shadows,
# where Y is small, crush most; highlights, where Y is near 1, hold. The dyes
# keep their differences while the silver greys them, so saturation falls, and
# a little more is taken to match the muted colour. A screen blend with a lifted
# shadow floor, the tempting shortcut, makes the picture lighter and milkier,
# the opposite of the look, and costs more structure than any other step.
BLEACH_SILVER_POWER = 0.8
BLEACH_DESATURATION = 0.3

def bleach_bypass(image, intensity = 0.5)
  linear = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  luma = clamp01(r * 0.2126 + g * 0.7152 + b * 0.0722)
  silver = ((luma > 1e-4).ifthenelse(luma, 1e-4)**(BLEACH_SILVER_POWER * intensity))
  dense = linear * silver.bandjoin([silver, silver])
  grey = (dense.extract_band(0) * 0.2126 + dense.extract_band(1) * 0.7152 + dense.extract_band(2) * 0.0722)
  share = BLEACH_DESATURATION * intensity
  muted = dense * (1.0 - share) + grey.bandjoin([grey, grey]) * share
  safe_cast(clamp01(muted).colourspace("srgb"))
rescue StandardError => e
  $logger.error "bleach_bypass: #{e.message}"; image
end

# Push and pull are development, not exposure. A push rates the film faster,
# underexposing it by `stops`, and develops longer to make up for it: midtones
# come back to about where they belong, the curve steepens so contrast rises,
# thin shadows stay thin, and the densest highlights block up toward a shoulder
# instead of clipping. A pull is the reverse, a softer curve. Per channel the
# steepening follows PUSH_RESPONSE, since the layers develop at different rates.
# This used to multiply linear light by 2^stops and clip, which on noir's
# two-stop push was four times the exposure and burnt highlights: a gain, which
# no lab ever applied.
PUSH_GAMMA_PER_STOP = 0.15
PUSH_PIVOT = 0.18
PUSH_SHOULDER = 0.80

def push_pull(image, stops = 1.0, stock = :kodak_portra)
  resp = PUSH_RESPONSE[stock] || { g: 1.00, b: 0.94 }
  linear = image.colourspace("scrgb")
  developed = linear.bandsplit.zip([1.0, resp[:g], resp[:b]]).map do |channel, response|
    gamma = (1.0 + PUSH_GAMMA_PER_STOP * stops * response).clamp(0.4, 2.0)
    positive = (channel > 1e-6).ifthenelse(channel, 1e-6)
    push_shoulder(((positive / PUSH_PIVOT)**gamma) * PUSH_PIVOT)
  end
  safe_cast(Vips::Image.bandjoin(developed).colourspace("srgb"))
rescue StandardError => e
  $logger.error "push_pull: #{e.message}"; image
end

# Above the shoulder density builds ever more slowly, an exponential approach
# to white, so a pushed highlight blocks up rather than clipping.
def push_shoulder(value)
  head = 1.0 - PUSH_SHOULDER
  over = value - PUSH_SHOULDER
  rolled = over.linear(-1.0 / head, 0).exp.linear(-head, PUSH_SHOULDER + head)
  (over > 0).ifthenelse(rolled, value)
end

# Split toning: shadow and highlight color casts weighted by luminance.
# shadow_rgb / hi_rgb are [R,G,B] triplets in 0-255.
def split_toning(image, shadow_rgb = [45, 35, 60], hi_rgb = [255, 240, 210], intensity = 0.30)
  luma = image.colourspace("b-w").cast("float") / 255.0
  img_f = image.cast("float") / 255.0
  s_clr = (Vips::Image.black(image.width, image.height, bands: 3) + shadow_rgb).cast("float") / 255.0
  h_clr = (Vips::Image.black(image.width, image.height, bands: 3) + hi_rgb).cast("float") / 255.0
  s_w = luma.linear(-1, 1) * intensity * 0.55
  h_w = luma               * intensity * 0.55
  result = img_f + (s_clr - img_f) * s_w + (h_clr - img_f) * h_w
  safe_cast(clamp01(result) * 255.0)
rescue StandardError => e
  $logger.error "split_toning: #{e.message}"; image
end

# Three-way color corrector: independent shadow / midtone / highlight casts.
def split_grade(image, shadow_rgb = [30, 40, 60], mid_rgb = [255, 255, 248], hi_rgb = [255, 245, 220], intensity: 0.25)
  luma = image.colourspace("b-w").cast("float") / 255.0
  img_f = image.cast("float") / 255.0
  s_clr = (Vips::Image.black(image.width, image.height, bands: 3) + shadow_rgb).cast("float") / 255.0
  m_clr = (Vips::Image.black(image.width, image.height, bands: 3) + mid_rgb).cast("float") / 255.0
  h_clr = (Vips::Image.black(image.width, image.height, bands: 3) + hi_rgb).cast("float") / 255.0
  s_w = (luma.linear(-1, 1) ** 2.0) * intensity * 0.5
  m_w = (luma * luma.linear(-1, 1) * 4.0)  * intensity * 0.5
  h_w = (luma ** 2.0)                       * intensity * 0.5
  result = img_f + (s_clr - img_f) * s_w + (m_clr - img_f) * m_w + (h_clr - img_f) * h_w
  safe_cast(clamp01(result) * 255.0)
rescue StandardError => e
  $logger.error "split_grade: #{e.message}"; image
end

# Film base density: multiplicative dye-density layer that shifts both color
# and overall density — warmer and slightly darker than a simple tint.
def dual_base_density(image, color = [255, 248, 235], opacity = 0.07)
  r_m, g_m, b_m = color.map { |c| c / 255.0 }
  img_f = image.cast("float") / 255.0
  multiplied = img_f.linear([r_m, g_m, b_m], [0, 0, 0])
  result = img_f * (1.0 - opacity) + multiplied * opacity
  safe_cast(clamp01(result) * 255.0)
rescue StandardError => e
  $logger.error "dual_base_density: #{e.message}"; image
end
