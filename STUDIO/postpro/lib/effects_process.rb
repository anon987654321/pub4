# frozen_string_literal: true

# Reciprocity failure: past about a second, film needs more exposure than the
# reciprocity law says, and each layer a different amount more, so a long
# exposure comes out underexposed and with a cast. Lost exposure is a gain
# below one on linear light, per channel, growing with the decades past a
# second; RECIPROCITY_SHIFT is each stock's per-layer shift in stops a decade,
# on top of RECIPROCITY_LOSS for the whole emulsion. Adding those figures to
# linear light as offsets, the obvious shortcut, lays a flat veil over every
# pixel, shadows most, rather than a cast.
RECIPROCITY_LOSS = 0.5

def reciprocity_failure(image, exposure_seconds = 10.0, stock = :cinestill_800t)
  decades = Math.log10([exposure_seconds, 1.0].max)
  shift = RECIPROCITY_SHIFT[stock] || RECIPROCITY_SHIFT[:cinestill_800t]
  gains = %i[r g b].map { |layer| 2.0**((shift[layer] - RECIPROCITY_LOSS) * decades) }
  safe_cast(clamp01(image.colourspace("scrgb").linear(gains, [0, 0, 0])).colourspace("srgb"))
rescue StandardError => e
  $logger.error "reciprocity_failure: #{e.message}"; image
end

# The light branch is 1 - 2(1-a)(1-b), which meets the dark branch 2ab exactly
# where the blur crosses mid grey. A plain screen there jumps by up to half the
# scale at that crossing, and every place the blurred copy passed 0.5 printed
# as a hard-edged blotch.
def soft_light(base, blend)
  lighter = (base.linear(-1, 1) * blend.linear(-1, 1)).linear(-2, 1)
  (blend < 0.5).ifthenelse(base * blend * 2.0, lighter)
end

# Dreamy soft cross-fade: soft-light blend of a blurred copy over the image.
def cross_fade(image, intensity = 0.4)
  img_f = clamp01(image.cast("float") / 255.0)
  soft = soft_light(img_f, clamp01(image.gaussblur(12.0).cast("float") / 255.0))
  result = img_f * (1.0 - intensity) + soft * intensity
  safe_cast(clamp01(result) * 255.0)
rescue StandardError => e
  $logger.error "cross_fade: #{e.message}"; image
end

# Infrared simulation: green channel → bright (foliage), blue → dark (sky).
# Heavy green mix approximates IR film's extended-red/near-IR sensitivity.
def infrared(image, intensity = 0.8)
  r, g, b = image.cast("float").bandsplit
  ir = r * 0.20 + g * 0.80 + (b > 0).ifthenelse(b, 0).linear(-1, 0) * 0.15
  ir = (ir > 0).ifthenelse(ir, 0)
  glow = ir.gaussblur(8.0) * 0.25
  ir3 = Vips::Image.bandjoin([ir + glow, ir + glow, ir + glow])
  result = image.cast("float") * (1.0 - intensity) + ir3 * intensity
  safe_cast(result.cast("uchar"))
rescue StandardError => e
  $logger.error "infrared: #{e.message}"; image
end

# Cyanotype alt-process: Prussian blue shadows [0,52,102] to white highlights.
def cyanotype(image, intensity = 0.90)
  shadow = [0, 52, 102]
  luma = image.colourspace("b-w").cast("float") / 255.0
  r = luma * (255 - shadow[0]) + shadow[0]
  g = luma * (255 - shadow[1]) + shadow[1]
  b = luma * (255 - shadow[2]) + shadow[2]
  cyan = Vips::Image.bandjoin([r, g, b])
  result = image.cast("float") * (1.0 - intensity) + cyan * intensity
  safe_cast(result.cast("uchar"))
rescue StandardError => e
  $logger.error "cyanotype: #{e.message}"; image
end

# Lith printing: aggressive contrast, warm sepia shadows, near-white highlights.
def lith_print(image, intensity = 0.80)
  gray = image.colourspace("b-w").cast("float") / 255.0
  hi = clamp01(gray ** 0.55 * 1.1)
  s_w = (gray.linear(-1, 1) ** 2.0) * 255.0
  r = hi * 255.0 + s_w * 0.12
  g = hi * 255.0 - s_w * 0.04
  b = hi * 255.0 - s_w * 0.16
  lith = Vips::Image.bandjoin([r, g, b])
  result = image.cast("float") * (1.0 - intensity) + lith * intensity
  safe_cast(result.cast("uchar"))
rescue StandardError => e
  $logger.error "lith_print: #{e.message}"; image
end

# Technicolor three-strip dye transfer printed each colour record with its own
# pure dye, so colours separated and grew dense rather than merely saturated,
# and the three matrices never registered perfectly. Approximated by stronger
# separation (the crosstalk removal color_separate does), a chroma lift in Lab
# that eases off where colour is already strong, and the one-pixel misregister.
# A global HSV saturation boost is the Photoshop slider, not the process: it
# brightens saturated colours and drags neutrals with them.
TECHNICOLOR_CHROMA_LIFT = 0.35
TECHNICOLOR_CHROMA_KNEE = 60.0

def technicolor(image, intensity = 0.60)
  r, g, b = image.bandsplit
  registered = Vips::Image.bandjoin([r.embed(1, 0, image.width, image.height), g,
                                     b.embed(-1, 1, image.width, image.height)])
  separated = color_separate(registered, intensity)
  l, a, bb = clamp01(separated.cast("float") / 255.0).linear(255.0, 0).cast("uchar")
             .copy(interpretation: :srgb).colourspace(:lab).bandsplit
  chroma = ((a * a) + (bb * bb))**0.5
  gain = (chroma.linear(1.0 / TECHNICOLOR_CHROMA_KNEE, 1.0)**-1).linear(TECHNICOLOR_CHROMA_LIFT * intensity, 1.0)
  dyed = l.bandjoin([a * gain, bb * gain]).copy(interpretation: :lab).colourspace(:srgb)
  safe_cast(image.cast("float") * (1.0 - intensity) + dyed.cast("float") * intensity)
rescue StandardError => e
  $logger.error "technicolor: #{e.message}"; image
end

# Kodachrome simulation: steep per-channel H&D curve + external coupler saturation.
def kodachrome_sim(image, intensity = 0.70)
  result = film_curve(image, :kodachrome, intensity * 0.85)
  hsv = result.colourspace("hsv")
  h, s, v = hsv.bandsplit
  s_hi = safe_cast(s.linear([1.0 + intensity * 0.45], [0]))
  v_hi = safe_cast(v.linear([1.0 + intensity * 0.08], [0]))
  saturated = Vips::Image.bandjoin([h, s_hi, v_hi]).colourspace("srgb")
  safe_cast((result.cast("float") * (1.0 - intensity * 0.25) +
             saturated.cast("float") * intensity * 0.25).cast("uchar"))
rescue StandardError => e
  $logger.error "kodachrome_sim: #{e.message}"; image
end

# Aged photographic print with differential dye fading. Cyan is least stable —
# absorbs visible light, degrades fastest → warm shift. Yellow moderate.
# Magenta most stable. Contrast compression + shadow floor models paper base fog.
def faded_print(image, age = 0.5)
  img_f = image.cast("float") / 255.0
  r, g, b = img_f.bandsplit
  cyan_fade = age * 0.65
  yellow_fade = age * 0.28
  r_faded = clamp01(r + cyan_fade * 0.22 + age * 0.06)
  g_faded = clamp01(g + age * 0.04)
  b_faded = clamp01(b * (1.0 - yellow_fade * 0.20) + yellow_fade * 0.05)
  comp = 1.0 - age * 0.28
  r_out = r_faded * comp + age * 0.07
  g_out = g_faded * comp + age * 0.045
  b_out = b_faded * comp + age * 0.02
  result = Vips::Image.bandjoin([r_out, g_out, b_out])
  result = result.gaussblur(age * 0.9) if age > 0.3
  safe_cast(clamp01(result) * 255.0)
rescue StandardError => e
  $logger.error "faded_print: #{e.message}"; image
end

# Adjacency / Eberhard effect: developer exhaustion at bright edges creates a
# dark inhibition band on the bright side and a slight bright band on the dark side.
# Physically: development byproducts diffuse outward and locally suppress nearby
# grains. Subtract a fraction of the high-pass edge signal → local undershoot.
def adjacency_effects(image, intensity = 0.25)
  blurred = image.gaussblur(1.8)
  edge = image.cast("float") - blurred.cast("float")
  result = clamp01((image.cast("float") - edge * (intensity * 0.45)) / 255.0) * 255.0
  safe_cast(result)
rescue StandardError => e
  $logger.error "adjacency_effects: #{e.message}"; image
end

# Longitudinal (axial) chromatic aberration: wavelengths focus at different depths.
# Blue focuses short of the plane; green slightly soft; red sharpest at the focal plane.
# Axial chromatic aberration: a lens focuses blue in front of the sensor and
# red behind it, so at any one focus setting the channels are not equally sharp.
#
# The sigmas were 0.4*strength and 0.9*strength, which at the strength presets
# actually pass (0.5) come to 0.2px and 0.45px -- both below the 0.3px floor for
# green, and both far below what survives being quantised back to 8-bit. The
# effect ran, raised nothing, and changed not a single pixel value. Widened to
# where the defocus is visible while still reading as a lens rather than a blur.
def longitudinal_ca(image, strength = 0.50)
  r, g, b = image.bandsplit
  g2 = g.gaussblur([0.9 * strength, 0.3].max)
  b2 = b.gaussblur([2.2 * strength, 0.3].max)
  safe_cast(Vips::Image.bandjoin([r, g2, b2]))
rescue StandardError => e
  $logger.error "longitudinal_ca: #{e.message}"; image
end

# Radial lens distortion via mapim. k1 < 0 = barrel (wide-angle); k1 > 0 = pincushion.
# First-order Brown-Conrady model — single coefficient, adequate for cinematic emulation.
def lens_distortion(image, k1 = -0.12)
  w, h = image.width, image.height
  cx, cy = w / 2.0, h / 2.0
  idx = Vips::Image.xyz(w, h)
  xn = (idx.extract_band(0).cast("float") - cx) / cx
  yn = (idx.extract_band(1).cast("float") - cy) / cy
  r2 = xn * xn + yn * yn
  factor = r2.linear([k1], [1.0])
  xs = (xn * factor * cx + cx).cast("float")
  ys = (yn * factor * cy + cy).cast("float")
  image.mapim(Vips::Image.bandjoin([xs, ys]))
rescue StandardError => e
  $logger.error "lens_distortion: #{e.message}"; image
end

# Bokeh highlight ring structure: out-of-focus highlights from lens element edges
# produce an onion-ring artifact. Detected by finding the bright-disk edge and
# adding a warm ring there. Red dominant — lens coatings transmit red more at edges.
def bokeh_rendering(image, intensity = 0.35)
  linear = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  luma = r * 0.2126 + g * 0.7152 + b * 0.0722
  bright = (luma > 0.65).ifthenelse(luma - 0.65, 0)
  ring = (bright.gaussblur(4.0) - bright.gaussblur(2.0)).linear([1], [0])
  ring = (ring > 0).ifthenelse(ring, 0).linear([intensity * 2.5], [0])
  result = Vips::Image.bandjoin([r + ring * 0.90, g + ring * 0.55, b + ring * 0.15])
  safe_cast(clamp01(result).colourspace("srgb"))
rescue StandardError => e
  $logger.error "bokeh_rendering: #{e.message}"; image
end

# Anamorphic lens flare: horizontal blue-cyan streak through brightest highlights.
# Real anamorphic streaks are produced by cylindrical front element edge diffraction.
# Approximated with a wide 1-D horizontal convolution over the highlight mask.
def anamorphic_flare(image, intensity = 0.50)
  w = image.width
  linear = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  luma = r * 0.2126 + g * 0.7152 + b * 0.0722
  bright = (luma > 0.78).ifthenelse(luma - 0.78, 0)
  kw = [w / 10, 31].min
  kw = kw.even? ? kw + 1 : kw
  kernel = Vips::Image.new_from_array([Array.new(kw, 1.0 / kw)])
  streak = bright.conv(kernel, precision: :float)
  streakc = Vips::Image.bandjoin([streak * 0.10, streak * 0.45, streak * 1.00]) * (intensity * 0.55)
  safe_cast(clamp01(linear + streakc).colourspace("srgb"))
rescue StandardError => e
  $logger.error "anamorphic_flare: #{e.message}"; image
end

# Diffraction softening at small apertures. The Airy disc diameter grows with f-number;
# at f/16+ the disc exceeds the Nyquist limit and detail visibly softens.
def diffraction_blur(image, f_number = 16.0, intensity = 1.0)
  sigma = ([((f_number - 8.0) / 5.0) * intensity, 0.3].max).clamp(0.3, 6.0)
  safe_cast(image.gaussblur(sigma))
rescue StandardError => e
  $logger.error "diffraction_blur: #{e.message}"; image
end

# Flatbed scanner CCD noise floor. Electronic in origin — independent of film grain,
# lower amplitude, no spatial correlation. Adds a second fine incoherent texture.
def scan_noise(image, intensity = 0.40)
  noise = Vips::Image.gaussnoise(image.width, image.height, sigma: 5.0 * intensity, mean: 0.0)
  safe_cast(image.cast("float") + rgb_bands(noise) * 0.06 * intensity)
rescue StandardError => e
  $logger.error "scan_noise: #{e.message}"; image
end
