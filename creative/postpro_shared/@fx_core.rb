# frozen_string_literal: true

STOCKS = {
  kodak_portra: { grain: 15, gamma: 0.65, rolloff: 0.88, lift: 0.05, matrix: [1.05, -0.02, -0.03, 0.02, 0.98, 0.00, 0.01, -0.05, 1.04] },
  kodak_vision3: { grain: 20, gamma: 0.65, rolloff: 0.85, lift: 0.08, matrix: [1.08, -0.05, -0.03, 0.03, 0.95, 0.02, 0.02, -0.08, 1.06] },
  fuji_velvia: { grain: 8, gamma: 0.75, rolloff: 0.92, lift: 0.03, matrix: [1.12, -0.08, -0.04, 0.05, 1.05, -0.02, 0.01, -0.12, 1.11] },
  tri_x: { grain: 25, gamma: 0.70, rolloff: 0.80, lift: 0.12, matrix: [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0] }
}.freeze

PRESETS = {
  portrait: { fx: %w[skin_protect film_curve highlight_roll micro_contrast grain color_temp base_tint], stock: :kodak_portra, temp: 5200, intensity: 0.8 },
  landscape: { fx: %w[film_curve color_separate highlight_roll micro_contrast grain vintage_lens], stock: :fuji_velvia, temp: 5800, intensity: 0.9 },
  street: { fx: %w[film_curve shadow_lift micro_contrast vintage_lens grain], stock: :tri_x, temp: 5600, intensity: 1.0 },
  blockbuster: { fx: %w[teal_orange grain bloom_pro highlight_roll micro_contrast], stock: :kodak_vision3, temp: 4800, intensity: 1.2 }
}.freeze

def safe_cast(image, format = 'uchar')
  image.cast(format)
rescue StandardError => e
  $logger.error "Cast failed: #{e.message}"
  image
end

def rgb_bands(image, bands = 3)
  return image if image.bands == bands
  image.bands < bands ? image.bandjoin([image] * (bands - image.bands)) : image.extract_band(0, n: bands)
end

def load_image(file)
  return nil unless File.exist?(file) && File.readable?(file)
  image = Vips::Image.new_from_file(file, access: :sequential)
  image = image.colourspace("srgb") if image.bands < 3
  rgb_bands(image)
rescue StandardError => e
  $logger.error "Load failed #{file}: #{e.message}"
  nil
end

def get_camera_profile(image)
  return nil if CAMERA_PROFILES.empty?
  begin
    make = image.get("exif-ifd0-Make")&.strip&.downcase
    model = image.get("exif-ifd0-Model")&.strip&.downcase
    return nil unless make && model

    CAMERA_PROFILES.each do |brand, profiles|
      return profiles[model] if profiles[model]
    end

    CAMERA_PROFILES.each do |brand, profiles|
      return profiles.values.first if make.include?(brand) || brand.include?(make)
    end
    nil
  rescue => e
    $logger.debug "EXIF read failed: #{e.message}"
    nil
  end
end

def apply_camera_profile(image, profile)
  return image unless profile && profile["color_matrix"]
  begin
    matrix = profile["color_matrix"]
    return image unless matrix.length == 9

    result = image.recomb([
      [matrix[0], matrix[1], matrix[2]],
      [matrix[3], matrix[4], matrix[5]],
      [matrix[6], matrix[7], matrix[8]]
    ])

    if profile["saturation"]
      hsv = result.colourspace("hsv")
      h, s, v = hsv.bandsplit
      s = s.linear([profile["saturation"]], [0])
      result = Vips::Image.bandjoin([h, s, v]).colourspace("srgb")
    end

    if profile["vibrance"]
      result = result.linear([1.0 + profile["vibrance"] * 0.1], [0])
    end

    if profile["base_tint"]
      result = base_tint(result, profile["base_tint"], 0.1)
    end

    safe_cast(result)
  rescue => e
    $logger.error "Camera profile failed: #{e.message}"
    image
  end
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
    1.0 + (b_mult - 1.0) * intensity
  ], [0, 0, 0]))
end

def skin_protect(image, intensity = 1.0)
  hsv = image.colourspace('hsv')
  h, s, v = hsv.bandsplit
  hue_mask = (h > 25.5) & (h < 63.75)
  sat_mask = (s > 51) & (s < 153)
  skin_mask = hue_mask & sat_mask
  protection = skin_mask.cast('float') / 255.0 * (1.0 - intensity * 0.7)
  protection_rgb = protection.bandjoin([protection, protection])
  safe_cast(image * (1.0 - protection_rgb) + image * protection_rgb)
end

def film_curve(image, stock = :kodak_portra, intensity = 1.0)
  data = STOCKS[stock] || STOCKS[:kodak_portra]
  shadows = image.linear([1.0], [data[:lift] * 255 * intensity])
  gamma_corrected = shadows.pow(data[:gamma])
  highlights = gamma_corrected.pow(data[:rolloff])
  safe_cast(image * (1 - intensity) + highlights * intensity)
end

def highlight_roll(image, threshold = 200, intensity = 1.0)
  mask = image > threshold
  over_exposed = image - threshold
  rolled_off = threshold + (over_exposed * 0.3).pow(0.7)
  result = mask.ifthenelse(rolled_off, image)
  safe_cast(image * (1 - intensity) + result * intensity)
end

def shadow_lift(image, lift = 0.15, preserve_blacks = true)
  gray = image.colourspace('grey16').cast('float') / 255.0
  shadow_mask = preserve_blacks ? ((1.0 - gray).pow(2.0)) * 0.8 : (1.0 - gray) * lift
  lift_rgb = shadow_mask.bandjoin([shadow_mask, shadow_mask])
  safe_cast(image.linear([1.0, 1.0, 1.0], [lift_rgb * 255 * lift]))
end

def micro_contrast(image, radius = 5, intensity = 0.3)
  blurred = image.gaussblur(radius)
  high_pass = image - blurred
  safe_cast(image + high_pass * intensity)
end

def color_separate(image, intensity = 0.6)
  r, g, b = image.bandsplit
  r_clean = (r - (g * 0.08 * intensity) - (b * 0.05 * intensity)).max(0)
  g_clean = (g - (r * 0.06 * intensity) - (b * 0.10 * intensity)).max(0)
  b_clean = (b - (r * 0.04 * intensity) - (g * 0.07 * intensity)).max(0)
  separated = Vips::Image.bandjoin([r_clean, g_clean, b_clean])
  safe_cast(image * (1 - intensity) + separated * intensity)
end

def grain(image, iso = 400, stock = :kodak_portra, intensity = 0.4)
  data = STOCKS[stock]
  sigma = data[:grain] * Math.sqrt(iso / 100.0) * intensity
  noise = Vips::Image.gaussnoise(image.width, image.height, sigma: sigma)
  brightness = image.colourspace('grey16').cast('float') / 255.0
  strength = (1.2 - brightness).max(0.3) * intensity
  grain_rgb = rgb_bands(noise * strength.bandjoin([strength, strength]))
  safe_cast(image + grain_rgb * 0.25)
end

def base_tint(image, color = [252, 248, 240], intensity = 0.08)
  overlay = Vips::Image.black(image.width, image.height, bands: 3) + color
  overlay_norm = overlay.cast('float') / 255.0
  image_norm = image.cast('float') / 255.0

  result = image_norm.ifthenelse(
    overlay_norm < 0.5,
    2 * image_norm * overlay_norm,
    1 - 2 * (1 - image_norm) * (1 - overlay_norm)
  )

  blended = result * 255
  safe_cast(image * (1 - intensity) + blended * intensity)
end

def vintage_lens(image, type = 'zeiss', intensity = 0.7)
  case type
  when 'zeiss' then micro_contrast(image, 3, 0.4 * intensity)
  when 'leica'
    glow = image.gaussblur(20).linear([0.3 * intensity], [0])
    safe_cast(image + glow)
  when 'helios'
    sharp = image.sharpen(mask: [[0, -1, 0], [-1, 5, -1], [0, -1, 0]])
    safe_cast(image * (1 - intensity * 0.3) + sharp * (intensity * 0.3))
  else
    image
  end
end

def teal_orange(image, intensity = 1.0)
  protected = skin_protect(image, 0.8)
  r, g, b = protected.bandsplit
  r_enhanced = r.linear([1 + 0.25 * intensity], [8 * intensity])
  g_balanced = g.linear([1 - 0.08 * intensity], [0])
  b_enhanced = b.linear([1 + 0.35 * intensity], [0])
  safe_cast(Vips::Image.bandjoin([r_enhanced, g_balanced, b_enhanced]))
end

def bloom_pro(image, intensity = 1.0)
  bright = image.linear([2.0 * intensity], [0])
  bloom_1 = bright.gaussblur(8 * intensity)
  bloom_2 = bright.gaussblur(16 * intensity)
  combined = (bloom_1 + bloom_2 * 0.5) * 0.2
  safe_cast(image + combined)
end

def preset(image, name)
  p = PRESETS[name.to_sym]
  return image unless p

  result = image
  p[:fx].each do |fx|
    result = case fx
             when 'skin_protect' then skin_protect(result, p[:intensity])
             when 'film_curve' then film_curve(result, p[:stock], p[:intensity])
             when 'highlight_roll' then highlight_roll(result, 200, p[:intensity] * 0.7)
             when 'shadow_lift' then shadow_lift(result, 0.2, false)
             when 'micro_contrast' then micro_contrast(result, 6, p[:intensity] * 0.4)
             when 'grain' then grain(result, 400, p[:stock], p[:intensity] * 0.4)
             when 'color_temp' then color_temp(result, p[:temp], p[:intensity] * 0.6)
             when 'base_tint' then base_tint(result, [255, 250, 245], 0.08)
             when 'color_separate' then color_separate(result, p[:intensity] * 0.6)
             when 'vintage_lens' then vintage_lens(result, 'zeiss', p[:intensity] * 0.8)
             when 'teal_orange' then teal_orange(result, p[:intensity])
             when 'bloom_pro' then bloom_pro(result, p[:intensity])
             else result
             end
  end
  result
end
