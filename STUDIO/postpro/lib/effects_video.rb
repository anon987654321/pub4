# frozen_string_literal: true

# Newton rings: thin-film interference fringes where film lifts off scanner glass.
# Sinusoidal concentric rings centered near a corner with radial intensity falloff.
def newton_rings(image, intensity = 0.12)
  w, h = image.width, image.height
  cx = w * 0.12
  cy = h * 0.10
  idx = Vips::Image.xyz(w, h)
  xd = idx.extract_band(0).cast("float") - cx
  yd = idx.extract_band(1).cast("float") - cy
  rad = ((xd * xd) + (yd * yd))**0.5
  rings = rad.linear([Math::PI * 2.0 / 28.0], [0]).math(:sin).linear([0.5], [0.5])
  fade = clamp01(rad.linear([-1.2 / [w, h].max], [1.2]))
  mod = (rings - 0.5) * fade * intensity * 0.10
  mod3 = mod.bandjoin([mod, mod])
  safe_cast(clamp01(image.cast("float") / 255.0 + mod3) * 255.0)
rescue StandardError => e
  $logger.error "newton_rings: #{e.message}"; image
end

# Dust specks and hair strands on negative or scanner glass. Procedurally drawn
# at random positions; dark specks more common than bright (dust blocks light).
def dust_and_hair(image, intensity = 0.50)
  w, h = image.width, image.height
  rng = postpro_rng(41)
  overlay = Vips::Image.black(w, h, bands: 3).cast("float")
  (intensity * 14).round.times do
    x = rng.rand(w)
    y = rng.rand(h)
    val = rng.rand > 0.65 ? [230.0, 228.0, 225.0] : [8.0, 6.0, 5.0]
    overlay = overlay.draw_circle(val, x, y, 1 + rng.rand(2), fill: true)
  end
  (intensity * 2).round.times do
    x1 = rng.rand(w)
    y1 = rng.rand(h)
    angle = rng.rand * Math::PI * 2
    len = 30 + rng.rand(110)
    x2 = (x1 + len * Math.cos(angle)).to_i.clamp(0, w - 1)
    y2 = (y1 + len * Math.sin(angle)).to_i.clamp(0, h - 1)
    overlay = overlay.draw_line([14.0, 12.0, 10.0], x1, y1, x2, y2)
  end
  blended = image.cast("float") + overlay.gaussblur(0.5) * 0.45
  safe_cast(clamp01(blended / 255.0) * 255.0)
rescue StandardError => e
  $logger.error "dust_and_hair: #{e.message}"; image
end

# Film curl / frame-holder vignette. Steeper radial falloff (power 8) than the
# smooth lens vignette (power 2) — mimics the mechanical shadow of the film gate.
def film_curl_vignette(image, intensity = 0.45)
  w, h = image.width, image.height
  idx = Vips::Image.xyz(w, h)
  xn = (idx.extract_band(0).cast("float") - w * 0.5) / (w * 0.5)
  yn = (idx.extract_band(1).cast("float") - h * 0.5) / (h * 0.5)
  r2 = xn * xn + yn * yn
  vign = clamp01((r2**4.0).linear([intensity * 6.0], [0]))
  v3 = vign.bandjoin([vign, vign])
  # `1.0 - v3` asks Ruby to subtract a Vips::Image from a Float, which raises
  # TypeError -- there is no coercion in that direction. The vips way to write
  # 1 - x is linear(-1, 1), which is what every other inversion in this file
  # uses. Rescued to `image`, so the vignette never darkened a corner.
  safe_cast(clamp01(image.cast("float") / 255.0 * v3.linear([-1.0], [1.0])) * 255.0)
rescue StandardError => e
  $logger.error "film_curl_vignette: #{e.message}"; image
end

# Video/broadcast artifacts — composite tape and CRT display, distinct signal
# path from the film-scan artifacts above (no emulsion, no optics).

# VHS luma bleed: composite video's luma channel has far narrower bandwidth
# than a digital signal, so bright edges smear into the pixels to their right.
def vhs_luma_bleed(image, intensity = 0.40)
  luma = image.colourspace("b-w")
  taps = (3 + intensity * 6).round
  weights = (0...taps).map { |i| Math.exp(-i / (taps * 0.5)) }
  total = weights.sum
  trail = (0...taps).zip(weights).reduce(luma * 0) do |acc, (i, wt)|
    acc + luma.embed(i, 0, image.width, image.height) * (wt / total)
  end
  bleed = rgb_bands(trail) - rgb_bands(luma)
  safe_cast(image.cast("float") + bleed * intensity)
rescue StandardError => e
  $logger.error "vhs_luma_bleed: #{e.message}"; image
end

# VHS chroma delay: the chroma subcarrier lags the luma signal through the tape
# path. Decompose to luma + chroma residual (not a naive per-channel shift —
# that would also drag brightness), delay chroma only, recombine.
def vhs_chroma_delay(image, intensity = 0.40)
  r, g, b = image.cast("float").bandsplit
  luma = r * 0.2126 + g * 0.7152 + b * 0.0722
  shift = (2 + intensity * 10).round
  [r, g, b].map { |c| c - luma }.then do |cr, cg, cb|
    cr_s = cr.embed(shift, 0, image.width, image.height)
    cg_s = cg.embed(shift, 0, image.width, image.height)
    cb_s = cb.embed(shift, 0, image.width, image.height)
    safe_cast(Vips::Image.bandjoin([luma + cr_s, luma + cg_s, luma + cb_s]))
  end
rescue StandardError => e
  $logger.error "vhs_chroma_delay: #{e.message}"; image
end

# VHS head-switching band: the bottom strip of an NTSC/PAL frame is where the
# spinning tape head crosses over — a jittered, noisy band a few scanlines tall.
def vhs_head_switch_band(image, intensity = 0.40)
  w, h = image.width, image.height
  band_h = [(h * 0.02 * (0.5 + intensity)).round, 2].max
  top = image.crop(0, 0, w, h - band_h)
  band = image.crop(0, h - band_h, w, band_h)
  shift = (6 + intensity * 18).round
  jittered = band.embed(postpro_rng(43).rand(-shift..shift), 0, w, band_h)
  noisy = jittered.cast("float") + rgb_bands(Vips::Image.gaussnoise(w, band_h, sigma: 30 * intensity, seed: postpro_seed(43)))
  safe_cast(top.join(clamp01(noisy / 255.0) * 255.0, :vertical))
rescue StandardError => e
  $logger.error "vhs_head_switch_band: #{e.message}"; image
end

# VHS mistracking: worn tape/misaligned heads read each horizontal strip with
# a different lateral offset, worst near the bottom edge of the frame.
def vhs_tracking_noise(image, intensity = 0.40)
  w, h = image.width, image.height
  strips = 24
  strip_h = (h.to_f / strips).ceil
  rows = (0...strips).filter_map do |i|
    y0 = i * strip_h
    sh = [y0 + strip_h, h].min - y0
    next nil if sh <= 0
    strip = image.crop(0, y0, w, sh)
    phase = i.to_f / strips
    shift = (Math.sin(phase * Math::PI * 10) * intensity * 14 * (phase**3)).round
    shift.zero? ? strip : strip.embed(shift, 0, w, sh)
  end
  safe_cast(rows.reduce { |acc, r| acc.join(r, :vertical) })
rescue StandardError => e
  $logger.error "vhs_tracking_noise: #{e.message}"; image
end

# Interlace combing: odd and even fields captured 1/60s apart under motion,
# displaced horizontally from each other when deinterlaced naively.
def vhs_interlace_comb(image, intensity = 0.40)
  w, h = image.width, image.height
  shift = (1 + intensity * 4).round
  shifted = image.embed(shift, 0, w, h)
  odd_row = (Vips::Image.xyz(w, h).extract_band(1).cast("int") & 1).cast("uchar") * 255
  safe_cast((rgb_bands(odd_row) > 0).ifthenelse(shifted, image))
rescue StandardError => e
  $logger.error "vhs_interlace_comb: #{e.message}"; image
end

# CRT phosphor bloom: P22 phosphor persistence glows green-dominant (human eye
# is most sensitive there, and it decays slowest) — distinct from bloom_pro's
# neutral highlight glow.
def crt_phosphor_bloom(image, intensity = 0.5)
  linear = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  excess = (g * 0.9 + r * 0.4 + b * 0.3).linear([1], [-0.55])
  bright = (excess > 0).ifthenelse(excess, 0)
  sigma = [image.width / 60.0, 4.0].max
  glow_r = bright.gaussblur(sigma) * (0.35 * intensity)
  glow_g = bright.gaussblur(sigma * 1.3) * (0.85 * intensity)
  glow_b = bright.gaussblur(sigma * 0.8) * (0.30 * intensity)
  glow = Vips::Image.bandjoin([glow_r, glow_g, glow_b])
  safe_cast(clamp01(linear + glow).colourspace("srgb"))
rescue StandardError => e
  $logger.error "crt_phosphor_bloom: #{e.message}"; image
end

# CRT scanline response: the raster gap between phosphor lines darkens every
# other row — a hard row-parity mask, not a continuous wave (which aliases to
# zero at integer pixel rows for a 2px period).
def crt_scanlines(image, intensity = 0.35)
  w, h = image.width, image.height
  odd_row = (Vips::Image.xyz(w, h).extract_band(1).cast("int") & 1).cast("uchar") * 255
  dark = image.cast("float") * (1.0 - intensity)
  safe_cast((rgb_bands(odd_row) > 0).ifthenelse(image, dark))
rescue StandardError => e
  $logger.error "crt_scanlines: #{e.message}"; image
end

# MiniDV block dropout: a digital tape read error corrupts one DCT macroblock
# at a time — a small solid-fill rectangle, not noise.
def minidv_block_dropout(image, intensity = 0.35)
  w, h = image.width, image.height
  processed = image
  rng = postpro_rng(47)
  (intensity * 6).round.times do
    bw = 8 + rng.rand(w / 12)
    bh = 8 + rng.rand(h / 20)
    x = rng.rand([w - bw, 1].max)
    y = rng.rand([h - bh, 1].max)
    shade = rng.rand < 0.5 ? [20, 20, 24] : [180, 180, 190]
    processed = processed.draw_rect(shade, x, y, bw, bh, fill: true)
  end
  processed
rescue StandardError => e
  $logger.error "minidv_block_dropout: #{e.message}"; image
end

# Hi8 chroma noise: analog Hi8's chroma subcarrier has a much worse SNR than
# its luma — noise piled onto the chroma residual only, luma stays clean.
def hi8_chroma_noise(image, intensity = 0.40)
  r, g, b = image.cast("float").bandsplit
  luma = r * 0.2126 + g * 0.7152 + b * 0.0722
  noise = Vips::Image.gaussnoise(image.width, image.height, sigma: 18 * intensity)
  cr_n = (r - luma) + noise
  cg_n = (g - luma) + noise * 0.6
  cb_n = (b - luma) + noise
  safe_cast(Vips::Image.bandjoin([luma + cr_n, luma + cg_n, luma + cb_n]))
rescue StandardError => e
  $logger.error "hi8_chroma_noise: #{e.message}"; image
end

# Selenium toning: silver areas in shadow zones chemically convert to selenium
# compounds — blue-violet shift in the deepest densities, neutral in highlights.
def selenium_tone(image, intensity = 0.45)
  img_f = image.cast("float") / 255.0
  luma = img_f.colourspace("b-w").cast("float") / 255.0
  shad_w = clamp01(luma.linear([-1], [1])**1.5) * (intensity * 0.65)
  r, g, b = img_f.bandsplit
  result = Vips::Image.bandjoin([clamp01(r + shad_w * 0.12), g, clamp01(b + shad_w * 0.28)])
  safe_cast(result * 255.0)
rescue StandardError => e
  $logger.error "selenium_tone: #{e.message}"; image
end
