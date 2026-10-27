# frozen_string_literal: true

# Filmic tonemap in linear (exposure) space. ACES is the Narkowicz fit to the
# Academy RRT+ODT — fast, photometric, the canonical "filmic" curve. Hable is
# Uncharted-2's S-curve, slightly more controllable shoulder, used in many
# cinematic productions. Both per-channel; chroma drift in the shoulder is the
# expected filmic behaviour. Exposure is applied in stops (2^EV) before the
# curve, so a +1.0 stop doubles linear light pre-tonemap.
TONEMAP_ACES = { a: 2.51, b: 0.03, c: 2.43, d: 0.59, e: 0.14 }.freeze
TONEMAP_HABLE = { a: 0.15, b: 0.50, c: 0.10, d: 0.20, e: 0.02, f: 0.30, w: 1.0 }.freeze
# Hejl-Burgess-Dawson: no division path in shadows, slight toe lift.
# Good for scenes where ACES reads too contrasty in the blacks.
TONEMAP_HBD = { a: 6.2, b: 0.5, c: 1.7, d: 0.06 }.freeze
# AgX (Troy Sobotka): rotate into a narrower set of primaries, log-encode,
# run a sigmoid there, rotate back. The rotation is the point — it is what
# stops a channel reaching clip from dragging hue with it, which is exactly
# what the 2016 per-channel fit above does to a saturated light source.
AGX_INSET = [[0.842401070950469, 0.042401070950469, 0.042401070950469],
             [0.078436501561803, 0.878436501561803, 0.078436501561803],
             [0.079162427487729, 0.079162427487729, 0.879162427487729]].freeze
AGX_OUTSET = [[1.196998661311914, -0.053001338688086, -0.053001338688086],
              [-0.098045626952253, 1.151954373047747, -0.098045626952253],
              [-0.098953034359661, -0.098953034359661, 1.151046965640339]].freeze
AGX_MIN_EV = -12.473931188332413
AGX_MAX_EV = 4.026068811667588
# The published sixth-order fit to AgX's default contrast curve.
AGX_SIGMOID = [-0.00232, 0.1191, 0.4298, -6.868, 31.96, -40.14, 15.5].freeze
# The ACES 2 tone scale — Daniele Evo, a Michaelis-Menten curve with a flare
# term — at SDR peak luminance. ACES 1's RRT is the fit in TONEMAP_ACES, and
# its highlight desaturation is the "ACES look" ACES 2 was built to remove.
#
# The tone scale only. ACES 2 also carries chroma compression and gamut
# mapping in a JMh appearance model, which is a colour pipeline rather than a
# curve and does not belong inside a per-channel tonemap; AgX above is the
# hue-preserving option here.
ACES2_PEAK_LUMINANCE = 100.0

def tonemap(image, type: :aces, exposure: 0.0, intensity: 1.0)
  linear = image.colourspace("scrgb")
  exposed = linear.linear([2.0**exposure] * 3, [0, 0, 0])
  curved = case type.to_sym
            when :hable then tonemap_hable(exposed)
            when :hbd   then tonemap_hbd(exposed)
            when :agx   then tonemap_agx(exposed)
            when :aces2 then tonemap_aces2(exposed)
            else             tonemap_aces(exposed)
            end
  blended = linear * (1 - intensity) + clamp01(curved) * intensity
  safe_cast(blended.colourspace("srgb"))
end

def clamp01(image)
  lifted = (image > 0).ifthenelse(image, 0)
  (lifted < 1).ifthenelse(lifted, 1)
end

def tonemap_aces(linear)
  a, b, c, d, e = TONEMAP_ACES.values_at(:a, :b, :c, :d, :e)
  sq = linear * linear
  num = sq.linear([a] * 3, [0, 0, 0]) + linear.linear([b] * 3, [0, 0, 0])
  den = sq.linear([c] * 3, [0, 0, 0]) + linear.linear([d] * 3, [e] * 3)
  num / den
end

def tonemap_hable(linear)
  a, b, c, d, e, f, w = TONEMAP_HABLE.values_at(:a, :b, :c, :d, :e, :f, :w)
  white = ((w * (a * w + c * b) + d * e) / (w * (a * w + b) + d * f)) - e / f
  curved = linear.bandsplit.map do |x|
    num = (x * x).linear([a], [0]) + x.linear([c * b], [d * e])
    den = (x * x).linear([a], [0]) + x.linear([b], [d * f])
    num / den - e / f
  end
  Vips::Image.bandjoin(curved).linear([1.0 / white] * 3, [0, 0, 0])
end

def tonemap_agx(linear)
  positive = (linear > 1e-10).ifthenelse(linear, 1e-10)
  log2 = positive.log10.linear([1.0 / Math.log10(2.0)] * 3, [0, 0, 0])
  span = AGX_MAX_EV - AGX_MIN_EV
  x = clamp01(log2.linear([1.0 / span] * 3, [-AGX_MIN_EV / span] * 3))
  shaped = AGX_SIGMOID.each_with_index.reduce(nil) do |sum, (coefficient, power)|
    term = (power.zero? ? x.linear([0] * 3, [coefficient] * 3) : (x**power) * coefficient)
    sum ? sum + term : term
  end
  # AgX hands back a display-encoded picture; tonemap's callers expect display
  # LINEAR, so decode before returning rather than gamma-encoding twice.
  srgb_decode(clamp01(shaped)).recomb(AGX_OUTSET)
end

# The sRGB transfer function, backwards, on an image rather than a scalar.
def srgb_decode(image)
  bands = image.bands
  low = image.linear([1.0 / 12.92] * bands, [0] * bands)
  high = image.linear([1.0 / 1.055] * bands, [0.055 / 1.055] * bands)**2.4
  (image <= 0.04045).ifthenelse(low, high)
end

# Michaelis-Menten with a flare term, per the ACES 2 tone scale library.
def aces2_tonescale_params(peak = ACES2_PEAK_LUMINANCE)
  @aces2_tonescale_params ||= {}
  @aces2_tonescale_params[peak] ||= begin
    n_r = 100.0
    g = 1.15
    t_1 = 0.04
    r_hit = 128.0 + (896.0 - 128.0) * (Math.log(peak / n_r) / Math.log(100.0))
    m_1 = 0.5 * ((peak / n_r) + Math.sqrt((peak / n_r) * ((peak / n_r) + 4.0 * t_1)))
    m = m_1 / (((r_hit / m_1) / ((r_hit / m_1) + 1.0))**g)
    c_t = 10.013 / n_r * (1.0 + (Math.log(peak / 100.0) / Math.log(2.0)) * 0.14)
    g_ip = 0.5 * (c_t + Math.sqrt(c_t * (c_t + 4.0 * t_1)))
    w_2 = 0.18 / (-(m_1 * ((g_ip / m)**(1.0 / g))) / (((g_ip / m)**(1.0 / g)) - 1.0))
    { g:, t_1:, s_2: w_2 * m_1, m_2: m_1 / (((r_hit / m_1) / ((r_hit / m_1) + w_2))**g) }
  end
end

def tonemap_aces2(linear)
  p = aces2_tonescale_params
  positive = (linear > 0).ifthenelse(linear, 0)
  curved = positive.bandsplit.map do |x|
    f = ((x / x.linear([1], [p[:s_2]]))**p[:g]) * p[:m_2]
    (f * f) / f.linear([1], [p[:t_1]])
  end
  Vips::Image.bandjoin(curved)
end

def tonemap_hbd(linear)
  a, b, c, d = TONEMAP_HBD.values_at(:a, :b, :c, :d)
  curved = linear.bandsplit.map do |x|
    num = (x * x).linear([a], [0]) + x.linear([b], [0])
    den = (x * x).linear([a], [0]) + x.linear([c], [d])
    num / den
  end
  Vips::Image.bandjoin(curved)
end

# How much of the grade this picture actually needs.
#
# Every preset here was tuned against generated images, and against those it is
# purely additive: a render arrives with no micro-texture and no toe, so
# optical_blur costs nothing (there is no detail to lose), film_curve has the
# whole tonal range to play with, and grain is the point of the exercise.
#
# Point the same chain at a photograph and each of those becomes a subtraction.
# Measured on a phone photograph through `portrait`: film_curve took 14.7 levels
# of contrast out and added 11.4 of brightness, shadow_lift another 4.3, and
# optical_blur removed roughly four times more texture than grain put back. The
# result is milky, flat and pink, and it is worse than the input by every number
# uncanny.rb reports.
#
# So the subtractive steps are scaled by what the source arrived with. A flat
# render measures near zero on both axes and gets the full grade unchanged —
# which the golden-grade suite pins, since `portrait` must still put texture
# into a flat field. A photograph measures high and gets the smoothing and the
# curve backed off, while grain, the stock's colour and the toe still apply.
#
# On by default and not reachable by a flag, deliberately: a grade that damages
# real photographs unless you know to disable it is a grade that damages real
# photographs.
#
# The knees are calibrated, not guessed. Below TEXTURE_FLOOR is rescue.rb's
# definition of "no micro-detail" — phone noise reduction, a beauty filter, or
# a diffusion model. TEXTURE_NATIVE is the low end of the nine phone photographs
# measured here, which ran 0.015 to 0.092. The tonal pair is the same idea on
# the contrast axis: those photographs ran 0.15 to 0.28.
TEXTURE_FLOOR = 0.004
TEXTURE_NATIVE = 0.015
TONAL_FLOOR = 0.10
TONAL_NATIVE = 0.22
# The curve never scales to nothing: the stock has a look, and a photograph
# that needs none of the repair should still come out graded rather than
# untouched. Defocus does scale to nothing, because simulated lens softness is
# not a look anyone asked for on a frame that is already sharp — it is only
# ever there to give grain something to sit on.
#
# 0.70, raised from 0.25, because 0.25 was protecting the picture from the
# grade rather than from damage. On a set of ordinary phone photographs the
# taper measured them as already-good and cut the curve to a quarter, which
# moved the mean about four levels and was invisible — the operator's report
# was that postpro had never run, and the files had in fact been graded twice.
#
# The confusion was mine: I conflated subtractive with damaging. A film curve
# compresses contrast, and that compression IS the look — the shoulder, the toe,
# the way a highlight rolls instead of clipping. Measured on a real photograph,
# the difference between 0.25 and 0.70 is eight points of texture (99% kept
# against 91%, both comfortably inside the golden suite's 75% floor) and a
# tonal shift from -0.05 to -0.07. Cheap, and the difference between a grade
# you can see and one you cannot.
#
# What actually damaged photographs was never the curve. It was dir_coupler
# rebuilding every band from a blurred copy, and defocus whose sigma floors
# ignored any request to soften less. Both are fixed at the mechanism. The
# taper should hold back the effects that destroy information and let the ones
# that shape tone do their work.
GRADE_FLOOR = 0.70

def source_headroom(image)
  reading = Postpro::Uncanny.read_image(image)
  { blur: taper(reading.texture, TEXTURE_FLOOR, TEXTURE_NATIVE, 0.0),
    curve: curve_strength(reading.tonal_range),
    # Two more effects that destroy what the source arrived with, and were
    # measured doing it before being taken out of `house`:
    # chromatic_aberration cost 0.0265 of texture and film_curl_vignette 0.0428
    # on one frame, together two thirds of its micro-detail.
    #
    # They were left unscaled with a note saying so, which made the note the
    # only thing standing between a photograph and the damage — and a note is
    # not a mechanism. Both are still available to the two presets each that
    # want them; those presets now get them at a strength the source can afford.
    #
    # Both taper on TEXTURE, not tonal range. Lateral CA blurs the red and blue
    # channels against green, and a vignette's falloff destroys detail in the
    # corners; neither is a tone curve, and neither has contrast to spend.
    fringe: taper(reading.texture, TEXTURE_FLOOR, TEXTURE_NATIVE, 0.30),
    vignette: taper(reading.texture, TEXTURE_FLOOR, TEXTURE_NATIVE, 0.35),
    reading: reading }
rescue StandardError => e
  # A measurement failure must not cost the grade. Full strength is what every
  # preset did before this existed.
  $logger.error "source_headroom: #{e.message}"
  { blur: 1.0, curve: 1.0, fringe: 1.0, vignette: 1.0, reading: nil }
end

# 1.0 at or below `floor`, `minimum` at or above `native`, linear between.
#
# Correct for a step that DESTROYS what the source already has: the more the
# picture arrived with, the less of that step it should get. Defocus is the
# case — a sharp frame wants none of it.
def taper(value, floor, native, minimum)
  return 1.0 if value <= floor
  return minimum if value >= native

  1.0 - ((value - floor) / (native - floor)) * (1.0 - minimum)
end

# How much film curve this picture can afford, which runs the OTHER way.
#
# The curve used to go through taper() with everything else, and that was a
# polarity error hiding behind a shared helper. taper() reduces a step as the
# source gets richer, which is right for defocus and exactly wrong here: an H&D
# curve does not add contrast, it compresses it — the toe and the shoulder are
# both reductions. So tapering it upward for flat images handed the most
# compression to the pictures with the least to spare.
#
# Measured across seven photographs: the most contrasty lost 26% of its tonal
# range and the flattest lost 46%. Backwards, and visible as muddiness in
# exactly the frames that were already soft.
#
# A film curve is a way of SPENDING contrast. A frame with plenty can afford the
# full shoulder and looks like film for it; a flat one has nothing to give and
# gets a light touch, because compressing an already-flat picture is not a look,
# it is a loss.
CURVE_FLOOR = 0.35

def curve_strength(tonal_range)
  return CURVE_FLOOR if tonal_range <= TONAL_FLOOR
  return 1.0 if tonal_range >= TONAL_NATIVE

  CURVE_FLOOR + ((tonal_range - TONAL_FLOOR) / (TONAL_NATIVE - TONAL_FLOOR)) * (1.0 - CURVE_FLOOR)
end
