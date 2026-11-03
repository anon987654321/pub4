# frozen_string_literal: true

# Relighting, which is the one thing a grade can do to light and the one thing
# this file could not do.
#
# A photograph fails on four layers — geometry, light, expression and optics —
# and light is PARTLY fixable: gradeable as tonality, and a grade
# cannot move a shadow to the other side of a nose. Both halves are true, and
# the gradeable half has a standard method nobody here had written.
#
# Split the picture into illumination and reflectance — a heavy blur of the
# luminance is the light, and what is left over is the surface — then put the
# light back differently and leave the surface alone. Because the correction
# rides as a RATIO on all three channels, texture, grain and hue survive it
# exactly; only the modelling moves. That is a power window, done by arithmetic
# rather than by hand, and it is why relighting belongs in a grade at all.
#
# `shape` above 1 deepens the modelling the light already made, which is depth
# without a single new pixel of contrast. `azimuth` swings the key around the
# frame. The ratio is bounded because an unbounded division by a blurred
# luminance will find a black background and multiply it by four hundred.
RELIGHT_SCALE = 12.0
# A blur whose sigma is a fraction of the frame is a blur nobody can afford at
# full resolution: sigma 227 on a 2720 px contact sheet took 65 seconds and
# killed a batch part way through. The field it produces is low-frequency by
# definition, so it is built on a small copy and resized back, which costs
# nothing the field had — this is the one place in the file where working at a
# lower resolution is not an approximation.
LOW_FREQUENCY_TILE = 256.0
RELIGHT_FLOOR = 0.004
RELIGHT_RATIO_CEILING = 3.0
RELIGHT_KEY_MIX = 0.65

def relight(image, intensity = 0.5, azimuth: 135.0, shape: 1.25, throw: 0.8, depth: nil)
  linear = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  light = low_frequency_field(r * 0.2126 + g * 0.7152 + b * 0.0722,
                             [image.width / RELIGHT_SCALE, 4.0].max)
  held = (light > RELIGHT_FLOOR).ifthenelse(light, RELIGHT_FLOOR)
  mean = [held.avg, RELIGHT_FLOOR].max
  # The light it already had, with its own falloff deepened.
  deepened = (held.linear([1.0 / mean], [0])**shape).linear([mean], [0])
  # And that light swung toward a new key, renormalised so the exposure holds.
  # With a measured depth map, the key also lands the way a real key does:
  # nearer the viewer collects more of it, far loses its share — the geometric
  # ramp alone would throw light across a wall the map knows is metres back.
  ramp = relight_key(held, azimuth, throw)
  ramp = ramp * proximity_bias(depth) if depth
  keyed = deepened * ramp
  keyed = keyed.linear([mean / [keyed.avg, RELIGHT_FLOOR].max], [0])
  mix = intensity * RELIGHT_KEY_MIX
  ratio = ((held.linear([1.0 - mix], [0]) + keyed.linear([mix], [0])) / held)
  bounded = (ratio < RELIGHT_RATIO_CEILING).ifthenelse(ratio, RELIGHT_RATIO_CEILING)
  safe_cast((linear * bounded.bandjoin([bounded, bounded])).colourspace("srgb"))
rescue StandardError => e
  $logger.error "relight: #{e.message}"
  image
end

# The near map rides as a multiplier on the key: a 1.0 keeps the full throw,
# the far wall holds 0.4 of it, and the curve is a straight blend because the
# physical falloff it stands in for is already in `throw`.
def proximity_bias(near)
  (near * 0.6).clamp01.linear(1.0, 0.4)
end

# A heavy blur, done where it is cheap.
def low_frequency_field(luma, sigma)
  shrink = luma.width / LOW_FREQUENCY_TILE
  return luma.gaussblur(sigma) if shrink <= 1.5

  small = luma.resize(1.0 / shrink)
  blurred = small.gaussblur([sigma / shrink, 0.6].max)
  grown = blurred.resize(luma.width.to_f / blurred.width,
                         vscale: luma.height.to_f / blurred.height)
  grown.embed(0, 0, luma.width, luma.height, extend: :copy)
end

# A normalised ramp across the frame, so the key falls off away from where it
# is thrown from. It multiplies the existing light rather than replacing it: a
# dark background stays dark, which is the difference between relighting a
# photograph and painting over one.
def relight_key(light, azimuth, throw)
  radians = azimuth * Math::PI / 180.0
  grid = Vips::Image.xyz(light.width, light.height)
  across = grid.extract_band(0).linear([1.0 / light.width], [-0.5]) * Math.cos(radians)
  down = grid.extract_band(1).linear([1.0 / light.height], [-0.5]) * Math.sin(radians)
  ramp = (across + down).linear([throw], [1.0])
  (ramp > 0.05).ifthenelse(ramp, 0.05)
end

# Depth, by the oldest cue in painting.
#
# Distance costs contrast, costs saturation and cools, because what is between
# you and the far thing is air full of scattered skylight. Every other depth
# cue in this file is optical — defocus, vignette, tilt — and optics is where
# the amateur version lives, because a blurred background reads as a filter
# while haze reads as a room.
#
# What is near is what is sharp, so local high-frequency energy stands in for
# proximity. It is a proxy and it is named as one: it will read a sharp cloud
# as near. On a portrait, which is what this is for, it reads the face.
AERIAL_HAZE = [0.74, 0.83, 1.00].freeze
AERIAL_DEPTH_CAP = 0.45
# The mask has to be selective or the effect is global haze wearing a depth
# cue as a name. Straight off the acutance it covers half the frame at a mean
# of 0.57; cubed it sits at 0.32 and lives where the detail is not. Measured
# over the sharpest fifth of a portrait it reads 0.00 either way, so the face
# was never at risk — what the curve buys is the middle distance.
AERIAL_FALLOFF = 3.0

# Aerial depth, and with a depth map, the same without the proxy.
#
# The acutance stand-in is only used when the neural map is absent: Postpro::Depth
# returns a measured `near` map for the frame, 1.0 at the viewer's side of the
# plane, and far is simply the rest of its span.
def aerial_depth(image, intensity = 0.5, depth: nil)
  linear = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  if depth
    far = clamp01(depth.linear([-1.0], [1.0]))**AERIAL_FALLOFF
  else
    luma = r * 0.2126 + g * 0.7152 + b * 0.0722
    acutance = low_frequency_field((luma - luma.gaussblur(2.0)).abs, [image.width / 40.0, 3.0].max)
    scale = [acutance.avg * 2.0, 1e-5].max
    far = clamp01(acutance.linear([-1.0 / scale], [1.0]))**AERIAL_FALLOFF
  end
  fade = far.linear([intensity * AERIAL_DEPTH_CAP], [0])
  level = [luma.avg, 0.02].max
  haze = Vips::Image.bandjoin(AERIAL_HAZE.map { |channel| fade.linear([0], [channel * level]) })
  keep = fade.linear([-1], [1])
  safe_cast((linear * keep.bandjoin([keep, keep]) + haze * fade.bandjoin([fade, fade]))
              .colourspace("srgb"))
rescue StandardError => e
  $logger.error "aerial_depth: #{e.message}"
  image
end

def base_tint(image, color = [252, 248, 240], intensity = 0.08)
  overlay = Vips::Image.black(image.width, image.height, bands: 3) + color
  overlay_norm = overlay.cast("float") / 255.0
  image_norm = image.cast("float") / 255.0

  inv_image = image_norm.linear(-1, 1)
  inv_overlay = overlay_norm.linear(-1, 1)
  multiply = image_norm * overlay_norm * 2
  screen = (inv_image * inv_overlay).linear(-2, 1)
  result = (overlay_norm < 0.5).ifthenelse(multiply, screen)

  blended = result * 255
  safe_cast(image * (1 - intensity) + blended * intensity)
end

def vintage_lens(image, type = "zeiss", intensity = 0.7)
  spec = LENSES[type.to_sym] || LENSES[:zeiss]
  processed = image
  processed = micro_contrast(processed, 4, spec[:micro_contrast] * intensity) if spec[:micro_contrast]
  if spec[:glow]
    glow = image.gaussblur(20) * (spec[:glow] * intensity)
    processed = safe_cast(processed + glow)
  end
  if spec[:chroma]
    shift = [(spec[:chroma] * intensity * 6).round, 1].max
    r, g, b = processed.bandsplit
    r = r.embed(shift, 0, processed.width, processed.height)
    b = b.embed(-shift, 0, processed.width, processed.height)
    processed = safe_cast(Vips::Image.bandjoin([r, g, b]))
  end
  processed = warmth(processed, spec[:warmth] * intensity) if spec[:warmth]
  # LENSES has carried a flare: figure on zeiss and anamorphic since it was
  # written and nothing read it, so a "flare" number described a veiling glare
  # that no render contained. Uncoated and early-coated glass scatters light
  # into the shadows; bloom_pro is the veiling this file already has.
  processed = bloom_pro(processed, spec[:flare] * intensity) if spec[:flare]
  processed
rescue StandardError => e
  $logger.error "vintage_lens failed: #{e.message}"
  image
end

def desaturate(image, amount = 0.5)
  gray = image.colourspace("grey16").colourspace("srgb")
  safe_cast(image * (1.0 - amount) + gray * amount)
rescue StandardError => e
  $logger.error "desaturate failed: #{e.message}"
  image
end

# Gentle warm color push: R+, G mild+, B-. Stays subtle — use amount ≤ 0.3.
def warmth(image, amount = 0.2)
  image.linear(
    [1.0 + 0.30 * amount, 1.0 + 0.08 * amount, 1.0 - 0.18 * amount],
    [0, 0, 0],
  ).then { |r| safe_cast(r) }
rescue StandardError => e
  $logger.error "warmth failed: #{e.message}"
  image
end

# Desaturated green push for horror / cold clinical grades.
def green_push(image, amount = 0.15)
  image.linear(
    [1.0 - amount * 0.50, 1.0 + amount, 1.0 - amount * 0.30],
    [0, 0, 0],
  ).then { |r| safe_cast(r) }
rescue StandardError => e
  $logger.error "green_push failed: #{e.message}"
  image
end
