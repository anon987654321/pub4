# frozen_string_literal: true

# Per-stock dye fading. Each emulsion has a characteristic failure mode over decades:
# Kodachrome: greens hold, reds drift to orange, shadows warm. Ektachrome: cyan fades,
# image shifts magenta-red. Velvia: magenta dye weakens. C-41: yellow cast + desaturation.
def dye_fade(image, stock = :kodak_portra, age = 0.50)
  img_f = image.cast("float") / 255.0
  r, g, b = img_f.bandsplit
  faded = case stock
          when :kodachrome
            Vips::Image.bandjoin([r.linear([1.0], [age * 0.08]), g,
                                  b.linear([1.0 - age * 0.16], [age * 0.05])])
          when :ektachrome_100
            Vips::Image.bandjoin([r.linear([1.0 + age * 0.13], [0]),
                                  g.linear([1.0 + age * 0.04], [0]), b])
          when :fuji_velvia
            Vips::Image.bandjoin([r, g.linear([1.0], [age * 0.05]),
                                  b.linear([1.0 - age * 0.08], [age * 0.03])])
          else
            Vips::Image.bandjoin([r.linear([1.0], [age * 0.06]),
                                  g.linear([1.0], [age * 0.04]),
                                  b.linear([1.0 - age * 0.10], [age * 0.02])])
          end
  gray = img_f.colourspace("b-w").colourspace("srgb").cast("float")
  result = clamp01(faded) * (1.0 - age * 0.18) + gray * (age * 0.18)
  safe_cast(clamp01(result) * 255.0)
rescue StandardError => e
  $logger.error "dye_fade: #{e.message}"; image
end

# Darkroom print tone compression. Optical enlarger prints cannot reproduce the full
# DR of a negative. Highlights block at paper Dmax; shadows print lighter than film.
# Slight gamma lift + shadow floor raise compress the tonal scale to print-medium range.
def darkroom_print(image, intensity = 0.50)
  img_f = image.cast("float") / 255.0
  lifted = img_f**(1.0 + (intensity * 0.28))
  floored = clamp01(lifted.linear([1.0], [intensity * 0.018]))
  safe_cast(floored * 255.0)
rescue StandardError => e
  $logger.error "darkroom_print: #{e.message}"; image
end

# Per-stock film base density tint. Applies the FILM_BASE color at low opacity
# so shadow areas pick up more tint than highlights — physically correct since
# tint is always present and highlights burn through it.
def film_base_density(image, stock = :kodak_portra, opacity = 0.06)
  tint = FILM_BASE[stock] || [255, 255, 255]
  dual_base_density(image, tint, opacity)
rescue StandardError => e
  $logger.error "film_base_density: #{e.message}"; image
end

# C-41 integral orange mask. Colored couplers in the negative create a
# characteristic orange base density that raises shadows toward orange-amber.
# Reversal and B&W stocks have no mask — only applied to C41_STOCKS.
def orange_mask(image, stock = :kodak_portra, intensity = 1.0)
  return image unless C41_STOCKS.include?(stock)
  mask = case stock
         when :cinestill_800t, :kodak_vision3_500t then 0.09
         when :kodak_vision3, :kodak_vision3_50d   then 0.08
         else 0.07
         end * intensity
  img_f = image.cast("float") / 255.0
  shadow_w = image.colourspace("b-w").cast("float") / 255.0
  shadow_w = shadow_w.linear(-1, 1)
  r, g, b = img_f.bandsplit
  result = Vips::Image.bandjoin([
    clamp01(r + shadow_w * mask * 0.55),
    clamp01(g + shadow_w * mask * 0.18),
    clamp01(b - shadow_w * mask * 0.35),
  ])
  safe_cast(result * 255.0)
rescue StandardError => e
  $logger.error "orange_mask: #{e.message}"; image
end

# Print film projection. Applies a print stock's H&D curve, warmth, cool-shadow
# grading, and fine grain as a final projection stage — analogous to printing
# from a negative onto Kodak 2383 (or 2302 for B&W).
def print_film(image, stock = :kodak_2383, intensity = 0.70)
  pdata = PRINT_STOCKS[stock]
  return image unless pdata
  hd = pdata[:hd]
  bands = %i[r g b].map { |c| Vips::Image.new_from_array([HD.channel_curve(hd[c])]) }
  lut = Vips::Image.bandjoin(bands).cast("uchar")
  # maplut hands back the LUT's interpretation, which is :matrix, so the
  # colourspace("b-w") below was a no-op returning three bands: hi_mask became
  # three bands, the bandjoin made a nine-band image, and `add` raised
  # "not one band or 9 bands" straight into the rescue. cinematic, blockbuster
  # and cinema_scan have therefore never had a print stage at all. Restoring
  # the interpretation is metadata only — the pixels are identical.
  developed = image.maplut(lut).copy(interpretation: image.interpretation)
  img_f = developed.cast("float") / 255.0
  luma = developed.colourspace("b-w").cast("float") / 255.0
  if pdata[:warmth]
    hi_mask = luma ** 2.8
    sh_mask = luma.linear(-1, 1) ** 2.8
    r, g, b = img_f.bandsplit
    img_f = Vips::Image.bandjoin([
      clamp01(r + hi_mask * pdata[:warmth] * 0.8),
      clamp01(g + hi_mask * pdata[:warmth] * 0.15),
      clamp01(b - hi_mask * pdata[:warmth] * 0.35 + sh_mask * (pdata[:cool_shadow] || 0)),
    ])
  end
  if pdata[:grain].to_i > 0
    amp = pdata[:grain] * 0.25 / 255.0
    noise = Vips::Image.gaussnoise(image.width, image.height, sigma: pdata[:grain].to_f * 0.3, mean: 0.0)
    img_f = clamp01(img_f + rgb_bands(noise).cast("float") * amp)
  end
  safe_cast(image * (1.0 - intensity) + safe_cast(img_f * 255.0) * intensity)
rescue StandardError => e
  $logger.error "print_film: #{e.message}"; image
end

def paper_texture(image, intensity = 0.35)
  w, h = image.width, image.height
  base = Vips::Image.perlin(w, h, cell_size: 12).linear([intensity * 0.018], [1.0])
  fiber = Vips::Image.perlin(w, h, cell_size: 3).linear([intensity * 0.008], [0.0])
  texture = (base + fiber).gaussblur(0.4)
  safe_cast(image * texture.bandjoin([texture, texture]))
rescue StandardError => e
  $logger.error "paper_texture: #{e.message}"; image
end

def dodgeburn_artifacts(image, intensity = 0.40)
  w, h = image.width, image.height
  cx, cy = w / 2.0, h / 2.0
  x = Vips::Image.xyz(w, h).extract_band(0).linear([1.0], [-cx])
  y = Vips::Image.xyz(w, h).extract_band(1).linear([1.0], [-cy])
  r = (((x * x) + (y * y))**0.5).linear([1.0 / [w, h].max], [0.0])
  dodge = r.linear([-intensity * 0.18], [1.0 + intensity * 0.06])
  mask = dodge.bandjoin([dodge, dodge])
  safe_cast(image * mask)
rescue StandardError => e
  $logger.error "dodgeburn_artifacts: #{e.message}"; image
end

def fixing_bath_fog(image, intensity = 0.30)
  floor = intensity * 0.04
  cast = [1.0 + intensity * 0.012, 1.0 + intensity * 0.006, 1.0]
  lifted = image.linear([(1.0 - floor)], [floor])
  safe_cast(lifted.linear(cast, [0.0, 0.0, 0.0]))
rescue StandardError => e
  $logger.error "fixing_bath_fog: #{e.message}"; image
end

def reticulation(image, intensity = 0.50)
  w, h = image.width, image.height
  coarse = Vips::Image.perlin(w, h, cell_size: 28).linear([intensity * 0.06], [1.0])
  mid = Vips::Image.perlin(w, h, cell_size: 9).linear([intensity * 0.03], [0.0])
  pattern = (coarse + mid).gaussblur(0.8)
  mask = pattern.bandjoin([pattern, pattern])
  safe_cast(image * mask)
rescue StandardError => e
  $logger.error "reticulation: #{e.message}"; image
end

def expired_film(image, age = 0.60)
  fogged = image.linear([(1.0 - age * 0.12)], [age * 0.06])
  r, g, b = fogged.bandsplit
  r = r.linear([1.0 + age * 0.08], [0.0])
  g = g.linear([1.0 + age * 0.03], [0.0])
  b = b.linear([1.0 - age * 0.05], [0.0])
  combined = r.bandjoin([g, b])
  grain_intensity = 0.20 + age * 0.35
  safe_cast(grain(combined, 800, :tri_x, grain_intensity))
rescue StandardError => e
  $logger.error "expired_film: #{e.message}"; image
end

def gate_weave(image, intensity = 0.40)
  w, h = image.width, image.height
  rng = postpro_rng(53)
  dx = (rng.rand - 0.5) * intensity * w * 0.004
  dy = (rng.rand - 0.5) * intensity * h * 0.002
  x = Vips::Image.xyz(w, h).extract_band(0).linear([1.0], [-dx])
  y = Vips::Image.xyz(w, h).extract_band(1).linear([1.0], [-dy])
  coords = x.bandjoin(y)
  image.mapim(coords, extend: :copy)
rescue StandardError => e
  $logger.error "gate_weave: #{e.message}"; image
end

def lens_ghosting(image, intensity = 0.35)
  w, h = image.width, image.height
  luma = image.colourspace(:b_w)
  threshold = 1.0 - intensity * 0.25
  highlights = (luma > threshold).gaussblur(12 * intensity)
  ghost = highlights.gaussblur(6).linear([intensity * 0.12], [0.0])
  offset_x = (w * 0.08).to_i
  offset_y = (h * 0.06).to_i
  ghost_rgb = ghost.bandjoin([ghost, ghost])
  flipped = ghost_rgb.flip(:horizontal).flip(:vertical)
  canvas = Vips::Image.black(w, h, bands: 3).linear([1.0], [0.0])
  x0 = [[w - offset_x - flipped.width, 0].max, w - 1].min
  y0 = [[h - offset_y - flipped.height, 0].max, h - 1].min
  blended = canvas.draw_image(flipped, x0, y0)
  safe_cast(image + blended)
rescue StandardError => e
  $logger.error "lens_ghosting: #{e.message}"; image
end

def ortho_film(image, intensity = 0.80)
  r, g, b = image.bandsplit
  grey = (b.linear([0.72], [0.0]) + g.linear([0.21], [0.0]) + r.linear([0.07], [0.0]))
  grey_rgb = grey.bandjoin([grey, grey])
  blended = image.linear([(1.0 - intensity)], [0.0]) + grey_rgb.linear([intensity], [0.0])
  safe_cast(blended)
rescue StandardError => e
  $logger.error "ortho_film: #{e.message}"; image
end

def tilt_shift(image, intensity = 0.70, focus_y = 0.5)
  w, h = image.width, image.height
  y_img = Vips::Image.xyz(w, h).extract_band(1).linear([1.0 / h], [0.0])
  dist = (y_img - focus_y).abs.linear([2.0], [0.0])**1.6
  blur_radius = (intensity * 8).clamp(1, 20).to_f
  blurred = image.gaussblur(blur_radius)
  # Vips::Image#clamp takes one argument, not two; `.clamp(0, 1)` raised
  # ArgumentError and the rescue returned the untouched image. clamp01 is the
  # helper this file already has for exactly this.
  mask = clamp01(dist.linear([intensity], [0.0]))
  mask3 = mask.bandjoin([mask, mask])
  safe_cast(image * (mask3.linear([-1.0], [1.0])) + blurred * mask3)
rescue StandardError => e
  $logger.error "tilt_shift: #{e.message}"; image
end

# Adaptive contrast: histogram normalization blended at partial opacity.
# Strongest single predictor of perceived photo quality in NIMA/AVA research.
def adaptive_contrast(image, intensity = 0.70)
  normalized = image.hist_norm
  safe_cast(image * (1.0 - intensity * 0.55) + normalized * (intensity * 0.55))
rescue StandardError => e
  $logger.error "adaptive_contrast: #{e.message}"; image
end

# Every graded picture needs a black and a white. Stacked lifts (shadow_lift,
# film_base_density, faded curves) leave the darkest pixel at 15% grey and the
# frame reads as milk, whatever the stock. The anchor stretches the picture's own
# 0.5th and 99.5th luma percentiles to a printed black and white with one gain on
# all three bands, so hue holds, then bends the midtones with a gentle S-curve.
# POSTPRO_ANCHOR=0 returns the unanchored grade.
ANCHOR_BLACK = 0.03
ANCHOR_WHITE = 0.975
ANCHOR_S_CURVE = 0.30
ANCHOR_MAX_GAIN = 2.4

def anchor_tones(image)
  return image if ENV["POSTPRO_ANCHOR"] == "0"

  luma = image.bandmean.cast("uchar")
  low = luma.percent(0.5)
  high = luma.percent(99.5)
  return image if high - low < 24

  gain = [(ANCHOR_WHITE - ANCHOR_BLACK) / ((high - low) / 255.0), ANCHOR_MAX_GAIN].min
  offset = ANCHOR_BLACK - (low / 255.0 * gain)
  bands = image.bands
  stretched = (image.cast("float") / 255.0).linear([gain] * bands, [offset] * bands)
  stretched = clamp01(stretched)
  smooth = stretched * stretched * stretched.linear([-2.0] * bands, [3.0] * bands)
  bent = stretched + ((smooth - stretched) * ANCHOR_S_CURVE)
  safe_cast(bent * 255.0)
rescue StandardError => e
  $logger.error "anchor_tones: #{e.message}"
  image
end
