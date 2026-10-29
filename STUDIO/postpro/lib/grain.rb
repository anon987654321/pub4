# frozen_string_literal: true

# Grain is a Boolean model. Silver halide crystals are disks dropped by a
# Poisson process whose density respects the local gray level, and the picture
# is what you see when you filter that binary field (Newson, Delon & Galerne,
# CGF 36, 2017). Two facts follow from it, and this file had both backwards.
#
# The filtered indicator has VARIANCE u(1-u), so the amplitude, being a standard
# deviation, goes as sqrt(u(1-u)). The envelope here was 4L^0.8(1-L) — the
# variance curve used as an amplitude — which cost a highlight about three times
# the grain it should carry against a midtone, where film costs it 1.7.
#
# And the crystal radius and the blur it is observed through are independent.
# One belongs to the emulsion, the other to the enlarger, the scanner and the
# eye; Newson keeps the filter in OUTPUT pixels for exactly that reason. This
# file derived both from one cell size, so the filter sat at roughly half the
# grain it was filtering at every resolution and no amplitude could survive it.
# Measured before the change: Portra at preset strength laid 0.27 levels of luma
# sigma on flat grey, against the 3 to 8 a 35 mm scan carries.
GRAIN_REFERENCE_WIDTH = 2048.0
# Crystal size in pixels at the reference width. An emulsion property, so it
# scales with the picture and a 600 px hero and a 4K print share a film.
GRAIN_CELL_BASE = 4.0
# The observer, in output pixels, and deliberately not a function of crystal
# size. Enlarger, scanner and eye, which is what Newson's sigma models.
GRAIN_SCAN_SIGMA = 0.62
# STOCKS[:grain] times this is the stock's peak luma sigma in 8-bit levels at
# midtone, and --fit-grain measures that same quantity off a scan. Tri-X at 25
# reads 6.0, Portra at 15 reads 3.6, Delta 3200 at 38 reads 9.1 — the band a
# 35 mm scan carries. It replaces GRAIN_AMP_SCALE = 141, a denominator in scRGB
# whose output no instrument could interpret and no measurement could check.
GRAIN_SIGMA_SCALE = 0.24
# Grain is exposed in linear light and read in 8-bit levels, and the sRGB
# transfer curve between them is steep in the shadows and flat in the
# highlights — at sRGB 16 a level is worth twelve times the linear light it is
# worth at sRGB 240. A constant linear amplitude therefore reads as four times
# the model's grain in the blacks and a fifth of it in the whites, which is the
# shape of a digital noise floor rather than of an emulsion.
#
# So the curve is carried in the domain it was measured in. This is the slope
# at mid-grey, which is the tone GRAIN_SIGMA_SCALE is quoted at, and
# grain_encoding_slope divides out the rest of it per tone.
GRAIN_MIDTONE_SLOPE = 255.0 * (1.055 / 2.4) * (HD.srgb_to_linear(128 / 255.0)**(1.0 / 2.4 - 1.0))

# 255 * d(sRGB)/d(linear) at the tone an 8-bit value encodes.
def grain_encoding_slope(value)
  linear = HD.srgb_to_linear(value / 255.0)
  return 255.0 * 12.92 if linear <= 0.0031308

  255.0 * (1.055 / 2.4) * (linear**(1.0 / 2.4 - 1.0))
end
# One crystal layer shadows the next, so chroma grain is correlated with luma
# grain rather than drawn three times independently — AFGS1 signals the same
# thing as a luma-to-chroma coefficient. Mixed as sqrt(1-p^2) own + p shared,
# which is the mix that leaves the field at unit variance.
GRAIN_CHROMA_CORRELATION = 0.35
# Worley, not Perlin: a Worley field is a random cell tessellation, which is
# what a halide layer is, where Perlin is a smooth gradient field, which is what
# a cloud is. Measured on the same construction, Worley returns kurtosis 3.50
# against Perlin's 3.05, and the heavy tail is the clumping — a scanned grain
# field runs 3.3 to 4, and a Gaussian is exactly 3. That is the difference
# between grain and noise.
#
# It costs: 2.3 s against 0.9 s for one grain pass over a 1024 x 1365 frame,
# because Worley's price is the cell count and the cells are small. Worth it on
# a still. :perlin is the fast path and is still a defensible emulsion.
GRAIN_CRYSTAL_FIELD = :worley
# The tile the normalisation is measured on.
GRAIN_STATISTICS_TILE = 384
# Film grain is slightly elongated along the transport axis.
GRAIN_ANISO_KERNEL = Vips::Image.new_from_array([[0.18, 0.64, 0.18]]).freeze
# AFGS1 carries grain strength as a piecewise-linear function of luma rather
# than as a formula, so that a measured emulsion is allowed to disagree with the
# model. These sixteen knots are the Boolean model's own sqrt(u(1-u)) normalised
# to peak at 1; a stock overrides them with `grain_knots:` when a scan says
# otherwise, and --fit-grain prints a measured set in this shape.
GRAIN_SCALING_KNOTS = [0.000, 0.499, 0.680, 0.800, 0.884, 0.943, 0.980, 0.998,
                       0.998, 0.980, 0.943, 0.884, 0.800, 0.680, 0.499, 0.000].freeze

# The scaling function as a 256-entry LUT: the knots interpolated, then divided
# by the encoding slope so that what comes out the other end follows the knots
# rather than the transfer curve. Normalised to 1 at mid-grey, which is where
# GRAIN_SIGMA_SCALE is calibrated.
def grain_scaling_lut(knots)
  (@grain_scaling_lut ||= {})[knots] ||= begin
    span = knots.length - 1
    table = (0...256).map do |i|
      position = (i / 255.0) * span
      low = position.floor.clamp(0, span)
      knots_at = knots[low] + (knots[[low + 1, span].min] - knots[low]) * (position - low)
      knots_at * GRAIN_MIDTONE_SLOPE / grain_encoding_slope(i)
    end
    midtone = table[128]
    Vips::Image.new_from_array([table.map { |v| v / midtone }]).cast("float")
  end
end

# Where on that curve each pixel sits.
#
# Indexed on the ENCODED gray level, not on linear light. The Boolean model's
# u is the fraction of the frame a crystal covers, which is the developed
# density — what a scan reads and what an 8-bit file stores. Indexing it on
# linear light instead reads midtone as u = 0.18, lands a third of the way up
# a curve that peaks at 0.5, and quietly costs every midtone a quarter of its
# grain. The noise is still ADDED in linear light, where the exposure happened.
def grain_envelope(image, stock_data)
  lut = grain_scaling_lut(stock_data[:grain_knots] || GRAIN_SCALING_KNOTS)
  rgb_bands(image).colourspace("b-w").cast("uchar").maplut(lut)
end

# A unit-variance crystal field at the given radius, seen through the observer.
#
# Normalising by the field's own measured deviation after the clumping and the
# blur is the whole trick: whatever the filter takes out, the measurement puts
# back, so crystal size and grain strength stop fighting each other and a stock
# can be quoted in levels rather than in an amplitude that survives by luck.
def grain_field(width, height, radius, sublayers, seed)
  cluster = Vips::Image.gaussnoise(width, height, sigma: GRAIN_LOGNORM_SIGMA, mean: 0.0, seed:)
                       .gaussblur([radius * 2.5, 0.4].max).exp
                       .linear([1.0 / GRAIN_LOGNORM_MEAN], [0])
  layers = sublayers.each_with_index.map do |sublayer, index|
    cell = [radius * (2.0**sublayer[:sensitivity_shift]) * sublayer[:grain_scale], 1.0].max.round
    crystals = grain_crystals(width, height, cell, seed + index * 7)
    # A second octave four times coarser is the multi-scale detail a single
    # cell size cannot carry; real emulsion clumps at more than one scale.
    coarse = grain_crystals(width, height, [cell * 4, 4].max, seed + index * 7 + 3)
    (crystals * 0.70 + coarse * 0.30).linear([sublayer[:weight]], [0])
  end
  raw = layers.reduce(:+) * cluster
  anisotropic = raw * 0.55 + raw.conv(GRAIN_ANISO_KERNEL, precision: :float) * 0.45
  # Materialised once. vips is lazy, so deviate, avg and the caller's use are
  # three passes over the same construction unless the field is held — and the
  # construction is sixteen noise images, which is most of what grain costs.
  observed = anisotropic.gaussblur(GRAIN_SCAN_SIGMA).copy_memory
  mean, deviation = grain_field_statistics(observed)
  return observed.linear([0], [0]) if deviation < 1e-9

  observed.linear([1.0 / deviation], [-mean / deviation])
end

# Off a centre tile, not the whole frame. The field is stationary by
# construction, so a tile is the same measurement for a fraction of the work,
# and on a 24 MP scan that difference is most of a second.
def grain_field_statistics(field)
  side = [GRAIN_STATISTICS_TILE, field.width, field.height].min
  tile = field.extract_area((field.width - side) / 2, (field.height - side) / 2, side, side)
  [tile.avg, tile.deviate]
end

# Three unit-variance channel fields, correlated by GRAIN_CHROMA_CORRELATION, do
# not sum to a unit-variance luma: the Rec.709 weights and the per-stock channel
# scales decide that, and they differ per stock. Dividing the factor out is what
# lets GRAIN_SIGMA_SCALE mean the same number of levels for Ektar and for Delta.
def grain_luma_factor(scales)
  weighted = [0.2126, 0.7152, 0.0722].each_with_index.map { |weight, i| weight * scales[i] }
  cross = weighted.combination(2).sum { |a, b| a * b }
  Math.sqrt(weighted.sum { |v| v * v } + 2 * GRAIN_CHROMA_CORRELATION**2 * cross)
end

# Both fields are zero-mean and roughly unit-scale before normalisation; the
# caller normalises, so only the correlation structure matters here.
def grain_crystals(width, height, cell, seed)
  if GRAIN_CRYSTAL_FIELD == :worley
    Vips::Image.worley(width, height, cell_size: cell, seed: seed % 2_147_483_647).cast("float")
  else
    Vips::Image.perlin(width, height, cell_size: cell, seed: seed % 2_147_483_647)
  end
end

def grain(image, iso = 400, stock = :kodak_portra, intensity = 0.4)
  data = STOCKS[stock] || STOCKS[:kodak_portra]
  scales = GRAIN_CHAN_SCALE[stock] || [1.0, 1.0, 1.0]
  sublayers = data[:sublayers] || [{ sensitivity_shift: 0.0, grain_scale: 1.0, weight: 1.0 }]
  radius = [GRAIN_CELL_BASE * (image.width / GRAIN_REFERENCE_WIDTH), 0.5].max
  # Rated against the stock's OWN box speed: at box speed a film comes out at
  # its own granularity, and every stop of push costs sqrt(2) more.
  box_speed = (data[:speed] || 400).to_f
  levels = data[:grain].to_f * GRAIN_SIGMA_SCALE * Math.sqrt(iso.to_f / box_speed) * intensity
  peak = levels / (GRAIN_MIDTONE_SLOPE * grain_luma_factor(scales))

  linear = image.colourspace("scrgb")
  envelope = grain_envelope(image, data)
  shared = grain_field(image.width, image.height, radius, sublayers, postpro_seed(11))
  mix = Math.sqrt(1.0 - GRAIN_CHROMA_CORRELATION**2)

  bands = scales.each_with_index.map do |chan_scale, ci|
    own = grain_field(image.width, image.height, radius * GRAIN_CHANNEL_SPATIAL[ci], sublayers,
                      postpro_seed(100 + ci))
    (own * mix + shared * GRAIN_CHROMA_CORRELATION).linear([peak * chan_scale], [0])
  end

  safe_cast((linear + Vips::Image.bandjoin(bands) * envelope).colourspace("srgb"))
rescue StandardError => e
  $logger.error "grain failed: #{e.message}"
  image
end
