# frozen_string_literal: true

# Finishing grain uses the preset's own stock and box speed, not a second
# Portra-400 emulsion on top of Tri-X. Random/unspecified presets fall back
# to Portra so the four output paths still share one call.
# The last pass of grain, for the chains that carry none of their own.
#
# It used to run on every output, which grained 57 of the 61 presets twice and
# stood as a --vocab-check note for as long as the note has existed. Two passes
# add in quadrature, so a stock quoted at 6.0 levels of granularity arrived at
# 8.5 — which cost nothing while the grain was invisible and costs the whole
# calibration now that it is not.
def apply_finishing_grain(image, preset_name = nil, grained: nil)
  data = PRESETS[preset_name.to_s.to_sym] || {}
  already = grained.nil? ? Array(data[:fx]).include?("grain") : grained
  return image if already

  grain(image, preset_effective_iso(data), data[:stock] || :kodak_portra, 0.70)
end

# Box speed, doubled per stop of push. A preset may override with iso:.
def preset_effective_iso(preset_data)
  return preset_data[:iso].to_f if preset_data[:iso]

  box = (STOCKS[preset_data[:stock]] || STOCKS[:kodak_portra])[:speed] || 400
  stops = Array(preset_data[:fx]).include?("push_pull") ? preset_data.fetch(:stops, 1.0).to_f : 0.0
  box * (2.0**stops.clamp(-3.0, 4.0))
end

def halation_tint_for(stock)
  case stock
  when :kodak_vision3, :kodak_vision3_500t then HALATION_TINT_VISION3
  when :cinestill_800t then HALATION_TINT_VISION3
  when :kodak_portra, :kodak_vision3_50d then HALATION_TINT_PORTRA
  when :tri_x, :ilford_hp5, :ilford_delta3200 then HALATION_TINT_TRI_X
  when :ektachrome_100 then HALATION_TINT_PORTRA
  when :kodachrome then HALATION_TINT_PORTRA
  when :kodak_ektar100, :fuji_pro400h, :polaroid_sx70 then HALATION_TINT_PORTRA
  else HALATION_TINT_VISION3
  end
end

# Per-channel characteristic curve baked into a 256-entry LUT. Each channel
# carries [Dmin, Dmax, pivot, gamma] — pivot is the linear midtone fulcrum
# (≈0.18 for ISO-calibrated film), gamma is contrast, Dmin/Dmax are the
# shadow floor and highlight ceiling in linear output. Operates in
# linearized sRGB so middle gray maps to itself, and per-channel offset
# from neutral creates the colour cast that defines a stock's look.
# One maplut at runtime; CPU spent only on cache miss.
module HD
  # An instance variable, NOT a constant, and that is the whole point.
  #
  # This was `CACHE = {}` with a comment above it saying "NOT frozen -- this is
  # a memo table and freezing it turns every write into a FrozenError". The
  # comment was right and the code under it said `.freeze` anyway, twice, in
  # this module and in Spectral: MASTER's IMMUTABLE rule ("mutable constant —
  # append .freeze") fires on `CACHE = {}` and cannot tell a lookup table from
  # a cache, so every autofix pass over this file put the freeze back.
  #
  # The cost was total. At the time, film_curve appeared in 46 of the 58 chains
  # and called HD.apply; spectral_temp called Spectral.adaptation_matrix. With either
  # frozen, `--preset portrait` dies on "can't modify frozen Hash" before the
  # second effect runs — postpro could not grade a single image. --vocab-check
  # does not catch it, because it reads tables and never touches a pixel: the
  # file reported 0 problems throughout.
  #
  # Arguing with the scanner in a comment lost twice. A module ivar is not a
  # constant, so IMMUTABLE has nothing to fire on and there is no argument.
  def self.cache = (@cache ||= {})

  module_function

  def srgb_to_linear(v)
    v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055)**2.4
  end

  def linear_to_srgb(v)
    v <= 0.0031308 ? v * 12.92 : 1.055 * v**(1.0 / 2.4) - 0.055
  end

  def develop(linear, params)
    d_min, d_max, pivot, gamma = params
    if linear < pivot
      d_min + (pivot - d_min) * (linear / pivot)**(1.0 / gamma)
    else
      pivot + (d_max - pivot) * ((linear - pivot) / (1.0 - pivot))**gamma
    end
  end

  def channel_curve(params)
    (0..255).map do |i|
      out = develop(srgb_to_linear(i / 255.0), params)
      (linear_to_srgb(out.clamp(0, 1)) * 255.0).round.clamp(0, 255)
    end
  end

  def build_lut(stock_data)
    hd = stock_data[:hd] or return
    bands = %i[r g b].map { |c| Vips::Image.new_from_array([channel_curve(hd[c])]) }
    Vips::Image.bandjoin(bands).cast("uchar")
  end

  def lut_for(stock_data)
    cache[stock_data.object_id] ||= build_lut(stock_data)
  end

  def apply(image, stock_data)
    lut = lut_for(stock_data)
    lut ? image.maplut(lut) : image
  end
end

# While true, safe_cast keeps float and does not clamp. Set only by preset(),
# which clamps once at the end.
$postpro_float_pipeline = false

# Clamp to 0..255 and quantise to 8-bit — EXCEPT inside a preset chain.
#
# Every effect ends by calling this, so a sixteen-step chain used to round to
# 8-bit sixteen times and, worse, clamp sixteen times. The rounding costs
# precision; the clamping costs information that cannot be recovered. A step
# that pushes a highlight to 260 has it cut to 255 permanently, and the next
# step — the shoulder that exists precisely to roll that highlight back down —
# receives a flat white plateau where the negative had detail.
#
# That is the opposite of what the thing being emulated does. The whole point of
# a colour negative is latitude: it holds values far above and below what a
# print shows, and the curve decides afterwards what becomes white. Clamping at
# every stage models a sensor, not a film.
#
# So inside a chain the values stay float and unbounded, and preset() clamps
# once at the end. Outside a chain — a bare effect call, a recipe step, a caller
# that hands the result straight to write_to_file — behaviour is unchanged,
# because those have no later step to hand headroom to.
def safe_cast(image, format = "uchar")
  if format == "uchar"
    return image.cast("float") if $postpro_float_pipeline

    f = image.cast("float")
    f = (f > 0).ifthenelse(f, 0)
    f = (f < 255).ifthenelse(f, 255)
    f.cast("uchar")
  else
    image.cast(format)
  end
rescue StandardError => e
  $logger.error "Cast failed: #{e.message}"
  image
end

def rgb_bands(image, bands = 3)
  return image if image.bands == bands
  image.bands < bands ? image.bandjoin([image] * (bands - image.bands)) : image.extract_band(0, n: bands)
end

def load_image(file)
  return unless File.exist?(file) && File.readable?(file)
  image = Vips::Image.new_from_file(file, access: :random)
  image = image.colourspace("srgb") if image.bands < 3
  rgb_bands(image)
rescue StandardError => e
  $logger.error "Load failed #{file}: #{e.message}"
  nil
end

def get_camera_profile(image)
  return if CAMERA_PROFILES.empty?

  begin
    make = image.get("exif-ifd0-Make")&.strip&.downcase
    model = image.get("exif-ifd0-Model")&.strip&.downcase

    return unless make && model

    # Try exact model match first
    CAMERA_PROFILES.each do |brand, profiles|
      return profiles[model] if profiles[model]
    end

    # Try brand match
    CAMERA_PROFILES.each do |brand, profiles|
      return profiles.values.first if make.include?(brand) || brand.include?(make)
    end

    nil
  rescue StandardError => e
    $logger.debug "EXIF read failed: #{e.message}"
    nil
  end
end

def apply_camera_profile(image, profile)
  return image unless profile && profile["color_matrix"]

  begin
    matrix = profile["color_matrix"]
    return image unless matrix.length == 9

    # Apply 3x3 color matrix
    result = image.recomb([
      [matrix[0], matrix[1], matrix[2]],
      [matrix[3], matrix[4], matrix[5]],
      [matrix[6], matrix[7], matrix[8]],
    ])

    # Apply optional adjustments
    if profile["saturation"]
      hsv = result.colourspace("hsv")
      h, s, v = hsv.bandsplit
      s = s.linear([profile["saturation"]], [0])
      result = Vips::Image.bandjoin([h, s, v]).colourspace("srgb")
    end

    if profile["vibrance"]
      # Simple vibrance simulation
      result = result.linear([1.0 + profile["vibrance"] * 0.1], [0])
    end

    if profile["base_tint"]
      result = base_tint(result, profile["base_tint"], 0.1)
    end

    safe_cast(result)
  rescue StandardError => e
    $logger.error "Camera profile failed: #{e.message}"
    image
  end
end
