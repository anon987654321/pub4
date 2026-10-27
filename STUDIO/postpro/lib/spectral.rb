# frozen_string_literal: true

# Spectral chromatic adaptation. Black-body physics, not ad-hoc R/G/B
# multipliers. Each pixel's RGB is upsampled to a 31-sample spectrum via a
# Gaussian basis calibrated so that under D65 the round-trip is identity;
# then reweighted by I_target/I_source (Planck's law); then re-integrated
# against CIE 1931 2° CMFs and projected to sRGB. All steps are linear, so
# they collapse to a single 3×3 matrix at runtime — applied via recomb in
# linear scrgb space.
module Spectral
  WAVELENGTHS = (400..700).step(10).to_a.freeze
  DELTA = 10.0

  CMF_X = [0.0143, 0.0435, 0.1344, 0.2839, 0.3483, 0.3362, 0.2908, 0.1954,
           0.0956, 0.0320, 0.0049, 0.0093, 0.0633, 0.1655, 0.2904, 0.4334,
           0.5945, 0.7621, 0.9163, 1.0263, 1.0622, 1.0026, 0.8544, 0.6424,
           0.4479, 0.2835, 0.1649, 0.0874, 0.0468, 0.0227, 0.0114].freeze
  CMF_Y = [0.0004, 0.0012, 0.0040, 0.0116, 0.0230, 0.0380, 0.0600, 0.0910,
           0.1390, 0.2080, 0.3230, 0.5030, 0.7100, 0.8620, 0.9540, 0.9950,
           0.9950, 0.9520, 0.8700, 0.7570, 0.6310, 0.5030, 0.3810, 0.2650,
           0.1750, 0.1070, 0.0610, 0.0320, 0.0170, 0.0082, 0.0041].freeze
  CMF_Z = [0.0679, 0.2074, 0.6456, 1.3856, 1.7471, 1.7721, 1.6692, 1.2876,
           0.8130, 0.4652, 0.2720, 0.1582, 0.0782, 0.0422, 0.0203, 0.0087,
           0.0039, 0.0021, 0.0017, 0.0011, 0.0008, 0.0003, 0.0002, 0.0000,
           0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000].freeze

  XYZ_TO_SRGB = [[ 3.2406, -1.5372, -0.4986],
                 [-0.9689,  1.8758,  0.0415],
                 [ 0.0557, -0.2040,  1.0570]].freeze

  PLANCK_C1 = 2 * 6.62607015e-34 * (2.99792458e8)**2
  PLANCK_C2 = 6.62607015e-34 * 2.99792458e8 / 1.380649e-23
  D65_KELVIN = 6504.0
  PRIMARY_CENTERS = [611.0, 549.0, 464.0].freeze
  PRIMARY_SIGMA = 30.0
  # A module ivar rather than a constant, for the reason spelled out over
  # HD.cache above: calibrated_basis memoises into it, and an autofix that
  # freezes every constant took this file out twice.
  def self.cache = (@cache ||= {})

  module_function

  def planckian(kelvin)
    WAVELENGTHS.map do |nm|
      l = nm * 1e-9
      PLANCK_C1 / (l**5 * (Math.exp(PLANCK_C2 / (l * kelvin)) - 1))
    end
  end

  def normalize_to_y1(spd)
    y = spd.zip(CMF_Y).sum { |s, c| s * c } * DELTA
    spd.map { |v| v / y }
  end

  def gaussian_basis
    PRIMARY_CENTERS.map do |c|
      WAVELENGTHS.map { |λ| Math.exp(-(λ - c)**2 / (2 * PRIMARY_SIGMA**2)) }
    end
  end

  def spd_to_xyz(spd, illuminant)
    weighted = spd.each_with_index.map { |s, i| s * illuminant[i] }
    [CMF_X, CMF_Y, CMF_Z].map { |cmf| weighted.zip(cmf).sum { |w, c| w * c } * DELTA }
  end

  def matvec3(m, v)
    (0..2).map { |i| (0..2).sum { |j| m[i][j] * v[j] } }
  end

  def inv3(m)
    a, b, c = m[0]; d, e, f = m[1]; g, h, i = m[2]
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    raise "singular" if det.abs < 1e-12
    inv = 1.0 / det
    [[(e * i - f * h) * inv, (c * h - b * i) * inv, (b * f - c * e) * inv],
     [(f * g - d * i) * inv, (a * i - c * g) * inv, (c * d - a * f) * inv],
     [(d * h - e * g) * inv, (b * g - a * h) * inv, (a * e - b * d) * inv]]
  end

  def calibrated_basis
    cache[:basis] ||= begin
      raw = gaussian_basis
      d65 = normalize_to_y1(planckian(D65_KELVIN))
      cols = raw.map { |b| matvec3(XYZ_TO_SRGB, spd_to_xyz(b, d65)) }
      m = [[cols[0][0], cols[1][0], cols[2][0]],
           [cols[0][1], cols[1][1], cols[2][1]],
           [cols[0][2], cols[1][2], cols[2][2]]]
      m_inv = inv3(m)
      (0..2).map do |j|
        WAVELENGTHS.each_index.map do |λi|
          (0..2).sum { |k| m_inv[j][k] * raw[k][λi] }
        end
      end
    end
  end

  def integration_matrix(illuminant)
    basis = calibrated_basis
    (0..2).map do |i|
      (0..2).map do |j|
        WAVELENGTHS.each_index.sum do |λi|
          xyz_dot = XYZ_TO_SRGB[i][0] * CMF_X[λi] +
                    XYZ_TO_SRGB[i][1] * CMF_Y[λi] +
                    XYZ_TO_SRGB[i][2] * CMF_Z[λi]
          basis[j][λi] * illuminant[λi] * xyz_dot * DELTA
        end
      end
    end
  end

  def matmul3(a, b)
    (0..2).map { |i| (0..2).map { |j| (0..2).sum { |k| a[i][k] * b[k][j] } } }
  end

  def adaptation_matrix(source_kelvin, target_kelvin)
    src = normalize_to_y1(planckian(source_kelvin))
    tgt = normalize_to_y1(planckian(target_kelvin))
    matmul3(integration_matrix(tgt), inv3(integration_matrix(src)))
  end
end

def spectral_temp(image, source_kelvin: 5500, target_kelvin: 6504, intensity: 1.0)
  matrix = Spectral.adaptation_matrix(source_kelvin, target_kelvin)
  linear = image.colourspace("scrgb")
  graded = linear.recomb(matrix)
  blended = linear * (1.0 - intensity) + graded * intensity
  safe_cast(blended.colourspace("srgb"))
end

def color_temp(image, kelvin, intensity = 1.0)
  factor = kelvin / 5500.0
  r_mult, g_mult, b_mult = if factor < 1.0
                             [1.0, factor**0.5, factor**2]
                           else
                             [factor**-0.3, 1.0, 1.0 + (factor - 1.0) * 0.5]
                           end
  safe_cast(image.linear([
    1.0 + (r_mult - 1.0) * intensity,
    1.0 + (g_mult - 1.0) * intensity,
    1.0 + (b_mult - 1.0) * intensity,
  ], [0, 0, 0]))
end

# Keep skin inside the saturation range skin actually occupies.
#
# The previous body ended `image * inv_protection + image * protection_rgb`,
# where inv_protection is 1 - protection. That is image * (1 - p) + image * p,
# which is image, for every pixel and every intensity -- an algebraic identity
# dressed as a blend. It computed a hue mask, a saturation mask, a protection
# weight and a complement, and then returned its own argument. Everything
# downstream that leans on it inherited the nothing: the portrait preset lists
# skin_protect as a step, and teal_orange opens by calling it before pushing
# oranges into exactly the pixels it was meant to hold back.
#
# A "protect" pass that has one image to work with can only do one useful
# thing: stop skin from going anywhere the grade after it would take it. Real
# skin sits under roughly half saturation in HSV regardless of tone; capping it
# there, and only inside the skin hue band, leaves everything else free while
# taking the headroom out of the faces.
SKIN_SAT_CEILING = 128.0

# Where skin is, 0 to 1: the CIELAB hue band skin occupies (20 to 75 degrees;
# most skin sits under 55), at the chroma and lightness skin has. The HSV band
# this file used before, 36 to 90 degrees, was yellow and missed most faces.
# Shared by skin_protect, teal_orange and the take check's skin budget.
def skin_key(image)
  lightness, chroma, hue = rgb_bands(image).cast("float").copy(interpretation: :srgb).colourspace(:lch).bandsplit
  skin_tones(lightness, chroma, hue).cast("float") / 255.0
end

def skin_protect(image, intensity = 1.0)
  h, s, v = image.colourspace("hsv").bandsplit
  skin = skin_key(image) * intensity.clamp(0.0, 1.0)

  s_f = s.cast("float")
  capped = (s_f > SKIN_SAT_CEILING).ifthenelse(SKIN_SAT_CEILING, s_f)
  s_out = (s_f * skin.linear([-1.0], [1.0])) + (capped * skin)

  toned = h.bandjoin([s_out.cast("uchar"), v]).copy(interpretation: :hsv)
  safe_cast(toned.colourspace("srgb"))
rescue StandardError => e
  $logger.error "skin_protect: #{e.message}"
  image
end

def film_curve(image, stock = :kodak_portra, intensity = 1.0)
  data = STOCKS[stock] || STOCKS[:kodak_portra]
  developed = HD.apply(image, data)
  safe_cast(image * (1 - intensity) + developed * intensity)
end

# The other half of a film stock, and until now the half nobody used.
#
# Every STOCKS entry carries a 3x3 matrix -- the table's own header calls it
# "3x3 colour matrix" in its first line. Before this effect existed, nine then-
# defined stock matrices had no readers, so film_curve applied the H&D curves
# alone: stocks differed in contrast and density and barely in hue.
#
# Deliberately NOT folded into film_curve: that would repaint all 73 presets
# that call it in one move. It is its own step, added to the presets
# whose entire point is colour separation, and available to any recipe.
def stock_matrix(image, stock = :kodak_portra, intensity = 1.0)
  flat = (STOCKS[stock] || STOCKS[:kodak_portra])[:matrix]
  return image unless flat.is_a?(Array) && flat.length == 9

  # Rows normalised to sum to 1 so the matrix maps white to white.
  #
  # A 3x3 whose rows do not sum to 1 moves neutrals, and seven of the fourteen
  # here do: Velvia's green row sums to 1.08, an eight percent green lift on
  # every grey in the frame. That is a white-balance shift wearing a saturation
  # matrix's clothes, and it would be applied on top of the cast the H&D curves
  # already carry -- the STOCKS header says in as many words that the per-channel
  # curve offsets are what "create stock colour cast". Two jobs, two mechanisms;
  # the matrix's job is dye crosstalk, which is what is left once the row sums
  # are taken out of it.
  #
  # Normalised here rather than in the table so the authored numbers stay as
  # written and no future entry can reintroduce the shift by being typed.
  rows = flat.each_slice(3).map do |row|
    sum = row.sum
    sum.abs < 1e-6 ? row : row.map { |v| v / sum }
  end
  linear = image.colourspace("scrgb")
  graded = linear.recomb(rows)
  safe_cast((linear * (1.0 - intensity) + graded * intensity).colourspace("srgb"))
rescue StandardError => e
  $logger.error "stock_matrix: #{e.message}"
  image
end

def highlight_roll(image, threshold = 200, intensity = 1.0)
  mask = image > threshold
  over_exposed = image - threshold
  rolled_off = ((over_exposed * 0.3) ** 0.7) + threshold
  result = mask.ifthenelse(rolled_off, image)
  safe_cast(image * (1 - intensity) + result * intensity)
end

# A film toe: the blacks sit slightly off zero rather than crushed to it.
#
# Expressed as a TARGET rather than an amount, which is the whole fix. An
# amount cannot know what it is being added to, so the same call that puts a
# gentle toe under a crushed render turns a photograph milky — the photograph
# already had its toe and got a second one on top. A target is self-limiting:
# reach it from below, and do nothing at all when the picture is already there.
#
# 0.045 of full scale, about 11/255. Chosen as a film toe rather than measured
# from a stock, and worth saying so — STOCKS carries H&D curves but no toe
# density, so there is nothing in the table to derive this from.
SHADOW_TOE_TARGET = 0.045

def shadow_lift(image, lift = SHADOW_TOE_TARGET, preserve_blacks = true)
  gray = image.colourspace("b-w").cast("float") / 255.0
  inv_gray = gray.linear(-1, 1)

  # `lift` is the fraction of full scale added at the darkest point, applied
  # ONCE. It used to be applied twice on the false branch (`inv_gray * lift`
  # and again in `* 255 * lift`, so 0.12 meant 0.0144) and replaced by a
  # constant 0.8 on the true branch — which made `preserve_blacks: true` lift
  # pure black by 30.6 levels against the other branch's 5.7. The flag named
  # for preserving blacks raised them 5.4x harder than the flag that does not.
  shadow_mask = preserve_blacks ? inv_gray**2.0 : inv_gray

  # Only the distance still to travel. A frame whose blacks already sit at or
  # above the toe gets nothing, so this can no longer stack onto a photograph
  # that had already been graded, scanned, or simply exposed properly.
  headroom = [lift - Postpro::Uncanny.black_point(image), 0.0].max
  return image if headroom <= 0.0

  lift_rgb = shadow_mask.bandjoin([shadow_mask, shadow_mask])
  safe_cast(image + lift_rgb * 255 * headroom)
end

def micro_contrast(image, radius = 5, intensity = 0.3)
  blurred = image.gaussblur(radius)
  high_pass = image - blurred
  safe_cast(image + high_pass * intensity)
end

def color_separate(image, intensity = 0.6)
  r, g, b = image.bandsplit

  r_diff = r - (g * 0.08 * intensity) - (b * 0.05 * intensity)
  g_diff = g - (r * 0.06 * intensity) - (b * 0.10 * intensity)
  b_diff = b - (r * 0.04 * intensity) - (g * 0.07 * intensity)
  r_clean = (r_diff > 0).ifthenelse(r_diff, 0)
  g_clean = (g_diff > 0).ifthenelse(g_diff, 0)
  b_clean = (b_diff > 0).ifthenelse(b_diff, 0)

  separated = Vips::Image.bandjoin([r_clean, g_clean, b_clean])
  safe_cast(image * (1 - intensity) + separated * intensity)
end
