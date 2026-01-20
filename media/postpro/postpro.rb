#!/usr/bin/env ruby
# frozen_string_literal: true

# postpro.rb - The Cinematic Emotion Engine v15.1.0

require "logger"
require "json"
require "time"
require "fileutils"

# ──────────────────────────────────────────────────────────────────────────────
# Bootstrap & Configuration
# ──────────────────────────────────────────────────────────────────────────────
BOOTSTRAP = PostproBootstrap.run
$logger = Logger.new("postpro.log", "daily", level: Logger::DEBUG)
$cli_logger = Logger.new($stdout, level: Logger::INFO)

PROMPT = TTY::Prompt.new if BOOTSTRAP[:gems][:tty]
require "vips" if BOOTSTRAP[:gems][:vips]

REPLIGEN_PRESENT = File.exist?("repligen.rb")
CAMERA_PROFILES = BOOTSTRAP[:camera_profiles]
CONFIG = BOOTSTRAP[:config]

# ──────────────────────────────────────────────────────────────────────────────
# Film Stock Database: Emotional Parameters
# ──────────────────────────────────────────────────────────────────────────────
STOCKS = {
  kodak_portra:       { grain: 15, gamma: 0.65, toe: 0.10, shoulder: 0.88, lift: 0.05 },
  kodak_vision3_50d:  { grain: 8,  gamma: 0.63, toe: 0.08, shoulder: 0.92, lift: 0.02 },
  kodak_vision3_500t: { grain: 20, gamma: 0.65, toe: 0.12, shoulder: 0.88, lift: 0.08, blue_shift: 0.15 },
  fuji_velvia:        { grain: 8,  gamma: 0.75, toe: 0.05, shoulder: 0.95, lift: 0.03 },
  tri_x:              { grain: 25, gamma: 0.70, toe: 0.15, shoulder: 0.80, lift: 0.12 },
  print_2383:         { contrast: 1.1, saturation: 1.15 },
  print_3510:         { contrast: 1.05, saturation: 1.0 }
}.freeze

# ──────────────────────────────────────────────────────────────────────────────
# Core Math & Physics Models
# ──────────────────────────────────────────────────────────────────────────────
def to_linear(img) = img.gamma(gamma: 2.2)
def to_gamma(img)  = img.gamma(gamma: 1/2.2)
def lum(img)       = img.colourspace("grey16").cast("float") / 65535.0

def curve(img, stock=:kodak_portra, i=1.0)
  s = STOCKS[stock]
  x = ((to_linear(img).log + 3 - s[:toe]) / (s[:shoulder] - s[:toe])).clamp(0, 1)
  d = x*x*(3-2*x) ** (1/s[:gamma])
  to_gamma(img * (1-i) + d.linear(1, s[:lift] * 255 * i))
end

def ar_grain(img, i=0.4, stock=:kodak_portra)
  s = STOCKS[stock]
  n = Vips::Image.gaussnoise(img.width, img.height, sigma: s[:grain] * i * 15)
  c = n.gaussblur(1.5).linear(0.6, 0) + n.linear(0.4, 0)
  strength = (2 - lum(img)).clamp(0.8, 2)
  g = c * strength.bandjoin([strength, strength])
  to_gamma(img.composite2(g.cast("uchar") * 0.3, "soft_light"))
end

def halation(img, i=0.4)
  l = to_linear(img)
  h = l > 220
  glow = h.gaussblur(15) * 0.5 + h.gaussblur(35) * 0.3 + h.gaussblur(70) * 0.2
  c = [255 * i, 90 * i, 40 * i]
  to_gamma(l.composite2(glow.ifthenelse(c, [0, 0, 0]), "screen"))
end

def super8_weave(img, i=0.3)
  t = Time.now.to_f * 10
  ox = simplex2d(t * 0.8, 0) * 18 * i
  oy = simplex2d(0, t * 0.8) * 14 * i
  rot = simplex2d(t * 0.3, t * 0.4) * 0.8 * i
  c = Math.cos(rot * Math::PI / 180)
  s = Math.sin(rot * Math::PI / 180)
  m = [c, s, -s, c]
  img.affine(m, odx: ox, ody: oy, interpolate: Vips::Interpolate.new("bicubic"))
end

def neg_print(img, neg=:kodak_vision3_500t, prt=:print_2383, i=1.0)
  l = to_linear(img)
  n = curve(l, neg, i)
  n = n.linear(STOCKS[prt][:contrast] || 1.0, 0)
  to_gamma(n)
end

def simplex2d(x, y)
  n = Math.sin(x * 12.9898 + y * 78.233) * 43758.5453
  n - n.floor
end

# ──────────────────────────────────────────────────────────────────────────────
# Emotional Preset System: Curated Psychological Profiles
# ──────────────────────────────────────────────────────────────────────────────
EMOTIONAL_PRESETS = {
  portrait: {
    steps: [
      { method: :apply_vintage_lens, params: { lens_type: "zeiss", intensity: 0.8 } },
      { method: :neg_print, params: { neg_stock: :kodak_portra, print_stock: :print_2383, intensity: 1.0 } },
      { method: :base_tint, params: { tint: [255, 250, 245], intensity: 0.08 } }
    ],
    feeling: "Intimacy, warmth, human connection. The 'honest' lens."
  },
  blockbuster: {
    steps: [
      { method: :neg_print, params: { neg_stock: :kodak_vision3_500t, print_stock: :print_2383, intensity: 1.0 } },
      { method: :halation, params: { intensity: 0.7 } },
      { method: :teal_orange, params: { intensity: 1.1 } }
    ],
    feeling: "Awe, spectacle, romantic scale. The 'larger than life' canvas."
  },
  street: {
    steps: [
      { method: :apply_vintage_lens, params: { lens_type: "helios", intensity: 0.6 } },
      { method: :neg_print, params: { neg_stock: :tri_x, print_stock: :print_2383, intensity: 1.2 } },
      { method: :ar_grain, params: { intensity: 0.9, stock: :tri_x } }
    ],
    feeling: "Immediacy, tension, documentary truth. The 'unflinching' eye."
  },
  dream: {
    steps: [
      { method: :apply_vintage_lens, params: { lens_type: "leica", intensity: 0.9 } },
      { method: :color_bleed, params: { intensity: 0.5 } },
      { method: :shadow_lift, params: { amount: 0.25, preserve_blacks: false } }
    ],
    feeling: "Memory, reverie, soft focus. The 'subjective inner world'."
  }
}.freeze

def apply_emotional_preset(image, preset_name: :portrait)
  preset = EMOTIONAL_PRESETS[preset_name]
  return image unless preset

  $cli_logger.info "Applying '#{preset_name}' preset: #{preset[:feeling]}"
  result = image

  preset[:steps].each do |step|
    if respond_to?(step[:method])
      result = send(step[:method], result, **step[:params])
    else
      $logger.warn "Method #{step[:method]} not found. Skipping."
    end
  end
  result
end

# ──────────────────────────────────────────────────────────────────────────────
# Original FX Library (Formatted for consistency)
# ──────────────────────────────────────────────────────────────────────────────
def apply_vintage_lens(image, lens_type: "zeiss", intensity: 0.7)
  case lens_type
  when "zeiss"
    micro_contrast(image, radius: 3, intensity: 0.4 * intensity)
  when "helios"
    sharp = image.sharpen(mask: [[0, -1, 0], [-1, 5, -1], [0, -1, 0]])
    image * (1 - intensity * 0.3) + sharp * (intensity * 0.3)
  when "leica"
    glow = image.gaussblur(20).linear([0.3 * intensity], [0])
    image + glow
  else
    image
  end
end

def base_tint(image, tint_color, intensity=0.1)
  tint_rgb = tint_color.is_a?(Array) ? tint_color : [tint_color, tint_color, tint_color]
  tint_layer = Vips::Image.black(image.width, image.height, bands: 3) + tint_rgb
  image * (1.0 - intensity * 0.5) + tint_layer * (intensity * 0.5 / 255.0)
end

def color_bleed(image, intensity=0.3)
  r, g, b = image.bandsplit
  r_bleed = r.gaussblur(0.8 * intensity)
  g_bleed = g.gaussblur(0.6 * intensity)
  b_bleed = b.gaussblur(1.0 * intensity)
  result = Vips::Image.bandjoin([r_bleed, g_bleed, b_bleed])
  image * (1 - intensity) + result * intensity
end

def micro_contrast(image, radius=5, intensity=0.3)
  blurred = image.gaussblur(radius)
  high_pass = image - blurred
  image + high_pass * intensity
end

def teal_orange(image, intensity=1.0)
  protected = skin_protect(image, 0.8)
  r, g, b = protected.bandsplit
  r_enhanced = r.linear([1 + 0.25 * intensity], [8 * intensity])
  g_balanced = g.linear([1 - 0.08 * intensity], [0])
  b_enhanced = b.linear([1 + 0.35 * intensity], [0])
  Vips::Image.bandjoin([r_enhanced, g_balanced, b_enhanced])
end

def shadow_lift(image, lift=0.15, preserve_blacks=true)
  gray = image.colourspace("grey16").cast("float") / 255.0
  shadow_mask = preserve_blacks ? ((1.0 - gray).pow(2.0)) * 0.8 : (1.0 - gray) * lift
  lift_rgb = shadow_mask.bandjoin([shadow_mask, shadow_mask])
  image.linear([1.0, 1.0, 1.0], [lift_rgb * 255 * lift])
end

# ──────────────────────────────────────────────────────────────────────────────
# Main Application Flow
# ──────────────────────────────────────────────────────────────────────────────
def process_file(file, variations, preset_name=nil, recipe_data=nil, random_effects=nil, mode="professional")
  image = load_image(file)
  return 0 unless image

  if CONFIG["apply_camera_profile_first"]
    profile = get_camera_profile(image)
    if profile
      image = apply_camera_profile(image, profile)
      PostproBootstrap.log_message "Applied camera profile for #{file}"
    end
  end

  processed_count = 0
  variations.times do |i|
    begin
      processed = if preset_name
        apply_emotional_preset(image, preset_name: preset_name.to_sym)
      elsif recipe_data
        recipe(image, recipe_data)
      elsif random_effects
        random_fx(image, random_effects, mode)
      else
        next
      end

      next unless processed
      processed = rgb_bands(processed)
      timestamp = Time.now.strftime("%Y%m%d%H%M%S")
      suffix = preset_name || "processed"
      output = file.sub(File.extname(file), "_#{suffix}_v#{i + 1}_#{timestamp}#{File.extname(file)}")
      quality = CONFIG["jpeg_quality"] || 95
      processed.write_to_file(output, Q: quality)
      $cli_logger.info "Saved masterpiece #{i + 1}: #{File.basename(output)}"
      processed_count += 1
    rescue StandardError => e
      $logger.error "Variation #{i + 1} failed: #{e.message}"
    end
  end
  processed_count
end

# ──────────────────────────────────────────────────────────────────────────────
# CLI & Execution
# ──────────────────────────────────────────────────────────────────────────────
def auto_launch
  if ARGV.include?("--auto") || (!$stdin.tty? && ARGV.include?("--from-repligen"))
    input = auto_mode
  elsif ARGV.include?("--from-repligen") && REPLIGEN_PRESENT
    check_repligen
    return
  else
    input = get_input
  end
  return unless input

  patterns, variations, config = input
  files = patterns.flat_map { |p| Dir.glob(p) }
                  .reject { |f| File.basename(f).match?(/processed|masterpiece/) }

  if files.empty?
    $cli_logger.error "No files matched patterns!"
    return
  end

  $cli_logger.info "Processing #{files.count} files..."
  total_processed = 0
  total_variations = 0
  start_time = Time.now

  files.each_with_index do |file, i|
    begin
      $cli_logger.info "#{i + 1}/#{files.count}: #{File.basename(file)}"
      count = case config[:type]
              when :preset
                process_file(file, variations, config[:preset])
              when :random
                fx = %w[grain leaks sepia bloom teal_orange cross vhs chroma glitch flare]
                selected = config[:mode] == "experimental" ? fx : fx.first(6)
                random_effects = selected.shuffle.take(config[:fx])
                process_file(file, variations, nil, nil, random_effects, config[:mode])
              when :recipe
                process_file(file, variations, nil, config[:recipe])
              else 0
              end
      total_processed += 1 if count > 0
      total_variations += count
      GC.start if (i % 10).zero?
    rescue StandardError => e
      $logger.error "Failed #{file}: #{e.message}"
      $cli_logger.error "Error: #{File.basename(file)}"
    end
  end

  duration = (Time.now - start_time).round(2)
  $cli_logger.info "Complete! #{total_processed} files → #{total_variations} masterpieces (#{duration}s)"
  if REPLIGEN_PRESENT && total_variations > 0
    $cli_logger.info "Tip: Run 'ruby repligen.rb' to generate more content!"
  end
end

auto_launch if __FILE__ == $PROGRAM_NAME