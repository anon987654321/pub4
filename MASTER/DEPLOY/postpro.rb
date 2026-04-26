#!/usr/bin/env ruby
# frozen_string_literal: true

require "logger"
require "json"
require "time"
require "fileutils"
require "rbconfig"

module PostproBootstrap
  LOG_PREFIX = "[postpro]".freeze

  def self.dmesg(msg)
    puts "#{LOG_PREFIX} #{msg}"
  end

  def self.startup_banner
    dmesg "boot ruby=#{RUBY_VERSION} os=#{RbConfig::CONFIG['host_os']}"
  end

  def self.ensure_gems
    { vips: ensure_vips, tty: ensure_tty_prompt }
  end

  def self.ensure_vips
    require "vips"
    true
  rescue LoadError
    dmesg "WARN ruby-vips missing, installing..."
    if system("gem install ruby-vips --no-document")
      require "vips"
      dmesg "OK ruby-vips installed"
      true
    else
      dmesg "WARN ruby-vips install failed, probing libvips"
      probe_and_install_libvips
      false
    end
  rescue StandardError => e
    dmesg "WARN ruby-vips unavailable: #{e.message}"
    false
  end

  def self.ensure_tty_prompt
    require "tty-prompt"
    true
  rescue LoadError
    dmesg "WARN tty-prompt missing, installing..."
    if system("gem install tty-prompt --no-document")
      require "tty-prompt"
      dmesg "OK tty-prompt installed"
      true
    else
      dmesg "WARN tty-prompt install failed"
      false
    end
  rescue StandardError => e
    dmesg "WARN tty-prompt unavailable: #{e.message}"
    false
  end

  def self.probe_and_install_libvips
    dmesg "probing libvips..."
    return true if system("pkg-config --exists vips")

    os = RbConfig::CONFIG["host_os"]
    case os
    when /darwin/
      if system("which brew > /dev/null 2>&1")
        dmesg "brew install vips"
        system("brew install vips")
      else
        dmesg "ERROR brew not found"
      end
    when /linux/
      install_cmd = if system("which apt > /dev/null 2>&1")
                      "sudo apt update && sudo apt install -y libvips-dev"
                    elsif system("which dnf > /dev/null 2>&1")
                      "sudo dnf install -y vips-devel"
                    elsif system("which yum > /dev/null 2>&1")
                      "sudo yum install -y vips-devel"
                    elsif system("which apk > /dev/null 2>&1")
                      "sudo apk add vips-dev"
                    elsif system("which pacman > /dev/null 2>&1")
                      "sudo pacman -S --noconfirm libvips"
                    end
      if install_cmd
        dmesg install_cmd
        system(install_cmd)
      else
        dmesg "ERROR unsupported package manager"
      end
    when /openbsd/
      if system("which pkg_add > /dev/null 2>&1")
        dmesg "pkg_add vips"
        system("doas pkg_add vips")
      else
        dmesg "ERROR pkg_add missing"
      end
    else
      dmesg "ERROR unsupported OS: #{os}"
    end

    if system("pkg-config --exists vips")
      dmesg "OK libvips installed"
      true
    else
      dmesg "ERROR libvips installation failed"
      false
    end
  end

  def self.load_camera_profiles(dir)
    return {} unless Dir.exist?(dir)

    profiles = {}
    Dir.glob(File.join(dir, "*.json")).each do |f|
      begin
        data = JSON.parse(File.read(f))
        vendor = data["vendor"]
        profiles[vendor] = data["profiles"] if vendor && data["profiles"]
      rescue StandardError => e
        dmesg "WARN profile #{File.basename(f)}: #{e.message}"
      end
    end
    dmesg "camera_profiles=#{profiles.keys.join(',')}"
    profiles
  end

  def self.load_master_config
    return {} unless File.exist?("master.json")

    begin
      raw = File.read("master.json")
      json = JSON.parse(raw.gsub(%r{^.*//.*$}, ""))
      json.dig("config", "multimedia", "postpro") || {}
    rescue StandardError => e
      dmesg "WARN master.json: #{e.message}"
      {}
    end
  end

  def self.run
    startup_banner
    gems = ensure_gems
    unless gems[:vips]
      dmesg "FATAL libvips missing"
      abort <<~MSG
        Postpro.rb requires libvips.
        Install manually:
          macOS: brew install vips
          Debian/Ubuntu: sudo apt install libvips-dev
          OpenBSD: doas pkg_add vips
      MSG
    end

    {
      gems: gems,
      camera_profiles: load_camera_profiles("multimedia/camera_profiles"),
      config: load_master_config
    }
  end
end

BOOTSTRAP = PostproBootstrap.run
LOGGER = Logger.new("postpro.log", "daily")
LOGGER.level = Logger::DEBUG
CLI_LOGGER = Logger.new($stdout)
CLI_LOGGER.level = Logger::INFO

PROMPT = if BOOTSTRAP[:gems][:tty]
           require "tty-prompt"
           TTY::Prompt.new
         end

require "vips" if BOOTSTRAP[:gems][:vips]

REPLIGEN_PRESENT = File.exist?("repligen.rb")
CAMERA_PROFILES = BOOTSTRAP[:camera_profiles]
CONFIG = BOOTSTRAP[:config]

STOCKS = {
  kodak_portra: { grain: 15, gamma: 0.65, rolloff: 0.88, lift: 0.05, matrix: [1.05, -0.02, -0.03, 0.02, 0.98, 0.00, 0.01, -0.05, 1.04] },
  kodak_vision3: { grain: 20, gamma: 0.65, rolloff: 0.85, lift: 0.08, matrix: [1.08, -0.05, -0.03, 0.03, 0.95, 0.02, 0.02, -0.08, 1.06] },
  fuji_velvia: { grain: 8, gamma: 0.75, rolloff: 0.92, lift: 0.03, matrix: [1.12, -0.08, -0.04, 0.05, 1.05, -0.02, 0.01, -0.12, 1.11] },
  tri_x: { grain: 25, gamma: 0.70, rolloff: 0.80, lift: 0.12, matrix: [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0] }
}.freeze

PRESETS = {
  portrait:   { fx: %w[skin_protect film_curve highlight_roll micro_contrast grain color_temp base_tint], stock: :kodak_portra, temp: 5200, intensity: 0.8 },
  landscape:  { fx: %w[film_curve color_separate highlight_roll micro_contrast grain vintage_lens], stock: :fuji_velvia, temp: 5800, intensity: 0.9 },
  street:     { fx: %w[film_curve shadow_lift micro_contrast vintage_lens grain], stock: :tri_x, temp: 5600, intensity: 1.0 },
  blockbuster:{ fx: %w[teal_orange grain bloom_pro highlight_roll micro_contrast], stock: :kodak_vision3, temp: 4800, intensity: 1.2 }
}.freeze

def safe_cast(img, fmt = "uchar")
  img.cast(fmt)
rescue StandardError => e
  LOGGER.error "Cast failed: #{e.message}"
  img
end

def rgb_bands(img, bands = 3)
  return img if img.bands == bands
  img.bands < bands ? img.bandjoin([img] * (bands - img.bands)) : img.extract_band(0, n: bands)
end

def load_image(path)
  return nil unless File.file?(path) && File.readable?(path)

  img = Vips::Image.new_from_file(path, access: :sequential)
  img = img.colourspace("srgb") if img.bands < 3
  rgb_bands(img)
rescue StandardError => e
  LOGGER.error "Load #{path}: #{e.message}"
  nil
end

def get_camera_profile(img)
  return nil if CAMERA_PROFILES.empty?
  make  = img.get("exif-ifd0-Make")&.strip&.downcase
  model = img.get("exif-ifd0-Model")&.strip&.downcase
  return nil unless make && model

  CAMERA_PROFILES.each { |_, p| return p[model] if p[model] }
  CAMERA_PROFILES.each { |brand, p| return p.values.first if make.include?(brand) || brand.include?(make) }
  nil
rescue StandardError => e
  LOGGER.debug "EXIF error: #{e.message}"
  nil
end

def apply_camera_profile(img, profile)
  return img unless profile && profile["color_matrix"]
  matrix = profile["color_matrix"]
  return img unless matrix.size == 9

  result = img.recomb([
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

  result = result.linear([1.0 + profile["vibrance"].to_f * 0.1], [0]) if profile["vibrance"]
  result = base_tint(result, profile["base_tint"], 0.1) if profile["base_tint"]
  safe_cast(result)
rescue StandardError => e
  LOGGER.error "Camera profile: #{e.message}"
  img
end

def color_temp(img, kelvin, intensity = 1.0)
  factor = kelvin / 5500.0
  r, g, b = if factor < 1.0
              [1.0, factor**0.5, factor**2]
            else
              [factor**-0.3, 1.0, 1.0 + (factor - 1.0) * 0.5]
            end
  safe_cast img.linear([
    1.0 + (r - 1.0) * intensity,
    1.0 + (g - 1.0) * intensity,
    1.0 + (b - 1.0) * intensity
  ], [0, 0, 0])
end

def skin_protect(img, intensity = 1.0)
  hsv = img.colourspace("hsv")
  h, s, _ = hsv.bandsplit
  mask = (h > 25.5) & (h < 63.75) & (s > 51) & (s < 153)
  protection = mask.cast("float") / 255.0 * (1.0 - intensity * 0.7)
  safe_cast img * (1.0 - protection) + img * protection
end

def film_curve(img, stock = :kodak_portra, intensity = 1.0)
  data = STOCKS[stock] || STOCKS[:kodak_portra]
  shadows = img.linear([1.0], [data[:lift] * 255 * intensity])
  highlights = shadows.pow(data[:gamma]).pow(data[:rolloff])
  safe_cast img * (1 - intensity) + highlights * intensity
end

def highlight_roll(img, threshold = 200, intensity = 1.0)
  mask = img > threshold
  rolled = threshold + (img - threshold) * 0.3 ** 0.7
  safe_cast img * (1 - intensity) + (mask.ifthenelse(rolled, img)) * intensity
end

def shadow_lift(img, lift = 0.15, preserve = true)
  gray = img.colourspace("grey16").cast("float") / 255.0
  mask = preserve ? ((1.0 - gray).pow(2.0)) * 0.8 : (1.0 - gray) * lift
  safe_cast img.linear([1.0, 1.0, 1.0], [mask * 255 * lift])
end

def micro_contrast(img, radius = 5, intensity = 0.3)
  blurred = img.gaussblur(radius)
  high_pass = img - blurred
  safe_cast img + high_pass * intensity
end

def color_separate(img, intensity = 0.6)
  r, g, b = img.bandssplit
  r = (r - g * 0.08 * intensity - b * 0.05 * intensity).max(0)
  g = (g - r * 0.06 * intensity - b * 0.10 * intensity).max(0)
  b = (b - r * 0.04 * intensity - g * 0.07 * intensity).max(0)
  safe_cast img * (1 - intensity) + Vips::Image.bandjoin([r, g, b]) * intensity
end

def grain(img, iso = 400, stock = :kodak_portra, intensity = 0.4)
  data = STOCKS[stock]
  sigma = data[:grain] * Math.sqrt(iso / 100.0) * intensity
  noise = Vips::Image.gaussnoise(img.width, img.height, sigma: sigma)
  bright = img.colourspace("grey16").cast("float") / 255.0
  strength = (1.2 - bright).max(0.3) * intensity
  safe_cast img + rgb_bands(noise * strength) * 0.25
end

def base_tint(img, color = [252, 248, 240], intensity = 0.08)
  overlay = Vips::Image.black(img.width, img.height, bands: 3) + color
  ov = overlay.cast("float") / 255.0
  im = img.cast("float") / 255.0
  blended = im.ifthenelse(ov < 0.5, 2 * im * ov, 1 - 2 * (1 - im) * (1 - ov)) * 255
  safe_cast img * (1 - intensity) + blended * intensity
end

def vintage_lens(img, type = "zeiss", intensity = 0.7)
  case type
  when "zeiss"
    micro_contrast(img, 3, 0.4 * intensity)
  when "leica"
    glow = img.gaussblur(20).linear([0.3 * intensity], [0])
    safe_cast img + glow
  when "helios"
    sharp = img.sharpen(mask: [[0, -1, 0], [-1, 5, -1], [0, -1, 0]])
    safe_cast img * (1 - intensity * 0.3) + sharp * (intensity * 0.3)
  else
    img
  end
end

def teal_orange(img, intensity = 1.0)
  r, g, b = skin_protect(img, 0.8).bandsplit
  r = r.linear([1 + 0.25 * intensity], [8 * intensity])
  g = g.linear([1 - 0.08 * intensity], [0])
  b = b.linear([1 + 0.35 * intensity], [0])
  safe_cast Vips::Image.bandjoin([r, g, b])
end

def bloom_pro(img, intensity = 1.0)
  bright = img.linear([2.0 * intensity], [0])
  combined = (bright.gaussblur(8 * intensity) + bright.gaussblur(16 * intensity) * 0.5) * 0.2
  safe_cast img + combined
end

def preset(img, name)
  cfg = PRESETS[name.to_sym]
  return img unless cfg

  result = img
  cfg[:fx].each do |fx|
    result = case fx
             when "skin_protect"   then skin_protect(result, cfg[:intensity])
             when "film_curve"     then film_curve(result, cfg[:stock], cfg[:intensity])
             when "highlight_roll" then highlight_roll(result, 200, cfg[:intensity] * 0.7)
             when "shadow_lift"    then shadow_lift(result, 0.2, false)
             when "micro_contrast" then micro_contrast(result, 6, cfg[:intensity] * 0.4)
             when "grain"          then grain(result, 400, cfg[:stock], cfg[:intensity] * 0.4)
             when "color_temp"     then color_temp(result, cfg[:temp], cfg[:intensity] * 0.6)
             when "base_tint"      then base_tint(result, [255, 250, 245], 0.08)
             when "color_separate" then color_separate(result, cfg[:intensity] * 0.6)
             when "vintage_lens"   then vintage_lens(result, "zeiss", cfg[:intensity] * 0.8)
             when "teal_orange"    then teal_orange(result, cfg[:intensity])
             when "bloom_pro"      then bloom_pro(result, cfg[:intensity])
             else result
             end
  end
  result
end

def grain_basic(img, intensity)
  noise = Vips::Image.gaussnoise(img.width, img.height, sigma: 25 * intensity)
  safe_cast img + rgb_bands(noise) * 0.2
end

def leaks_basic(img, intensity)
  overlay = Vips::Image.black(img.width, img.height, bands: 3)
  rand(2..5).times do
    x = rand(img.width)
    y = rand(img.height)
    radius = img.width / rand(2..4)
    color = [255 * intensity, 180 * intensity, 80 * intensity]
    overlay = overlay.draw_circle(color, x, y, radius, fill: true)
  end
  safe_cast img + overlay.gaussblur(15 * intensity) * 0.3
end

def sepia_basic(img, intensity)
  matrix = [0.9, 0.7, 0.2, 0.3, 0.8, 0.1, 0.2, 0.6, 0.1]
  safe_cast img.recomb(matrix)
end

def bloom_basic(img, intensity)
  bright = img.linear([1.8 * intensity], [0]).gaussblur(12 * intensity)
  safe_cast img + bright * 0.3
end

def cross_basic(img, intensity)
  r, g, b = img.bandssplit
  r = r.linear([1 + 0.2 * intensity], [10 * intensity])
  g = g.linear([1 - 0.1 * intensity], [0])
  b = b.linear([1 + 0.3 * intensity], [-5 * intensity])
  safe_cast Vips::Image.bandjoin([r, g, b])
end

def vhs_basic(img, intensity)
  noise = rgb_bands(Vips::Image.gaussnoise(img.width, img.height, sigma: 40 * intensity))
  lines = rgb_bands(Vips::Image.sines(img.width, img.height).linear(0.3 * intensity, 150))
  safe_cast img + noise * 0.4 + lines * 0.3
end

def chroma_basic(img, intensity)
  shift = 3 * intensity
  r, g, b = img.bandssplit
  r = r.embed(shift, 0, img.width, img.height)
  b = b.embed(-shift, 0, img.width, img.height)
  safe_cast Vips::Image.bandjoin([r, g, b])
end

def glitch_basic(img, intensity)
  r, g, b = img.bandssplit
  shift = 15 * intensity
  r = r.embed(rand(-shift..shift), rand(-shift..shift), img.width, img.height)
  g = g.embed(rand(-shift..shift), rand(-shift..shift), img.width, img.height)
  b = b.embed(rand(-shift..shift), rand(-shift..shift), img.width, img.height)
  noise = rgb_bands(Vips::Image.gaussnoise(img.width, img.height, sigma: 20 * intensity))
  safe_cast Vips::Image.bandjoin([r, g, b]) + noise * 0.4
end

def flare_basic(img, intensity)
  flare = Vips::Image.black(img.width, img.height, bands: 3)
  rand(3..6).each do
    x = rand(img.width)
    y = rand(img.height)
    flare = flare.draw_line([255, 220, 180], x, y, x + 200 * intensity, y)
  end
  safe_cast img + flare.gaussblur(8 * intensity) * 0.3
end

def random_fx(img, effects, mode)
  result = img
  effects.each do |fx|
    intensity = mode == "experimental" ? rand(0.5..1.5) : rand(0.3..0.8)
    result = case fx
             when "grain"          then grain_basic(result, intensity)
             when "leaks"          then leaks_basic(result, intensity)
             when "sepia"          then sepia_basic(result, intensity)
             when "bloom"          then bloom_basic(result, intensity)
             when "teal_orange"    then teal_orange(result, intensity)
             when "cross"          then cross_basic(result, intensity)
             when "vhs"            then vhs_basic(result, intensity)
             when "chroma"         then chroma_basic(result, intensity)
             when "glitch"         then glitch_basic(result, intensity)
             when "flare"          then flare_basic(result, intensity)
             else result
             end
  end
  result
end

def recipe(img, data)
  result = img
  data.each do |fx, params|
    intensity = params.is_a?(Hash) ? params["intensity"].to_f : params.to_f
    method = fx.to_s.sub("_professional", "")
    result = send(method, result, intensity) if respond_to?(method)
  end
  result
end

def check_repligen
  return unless REPLIGEN_PRESENT
  CLI_LOGGER.info "Repligen detected – auto‑processing..."

  recent = Dir.glob("*_generated_*.{jpg,jpeg,png,webp}")
              .select { |f| File.mtime(f) > (Time.now - 300) }
  return if recent.empty?

  CLI_LOGGER.info "Found #{recent.size} generated images"
  preset = PROMPT.select("Preset for Repligen:", PRESETS.keys)
  recent.each { |f| process_file(f, 2, preset) }
end

def process_file(path, variations, preset_name = nil, recipe_data = nil, random_fx = nil, mode = "professional")
  img = load_image(path)
  return 0 unless img

  if CONFIG["apply_camera_profile_first"]
    profile = get_camera_profile(img)
    img = apply_camera_profile(img, profile) if profile
    PostproBootstrap.dmesg "camera profile applied to #{path}"
  end

  count = 0
  variations.times do |i|
    processed =
      if preset_name
        preset(img, preset_name)
      elsif recipe_data
        recipe(img, recipe_data)
      elsif random_fx
        random_fx(img, random_fx, mode)
      else
        next
      end

    next unless processed

    out = path.sub(File.extname(path), "_#{preset_name || 'processed'}_v#{i + 1}_#{Time.now.strftime('%Y%m%d%H%M%S')}#{File.extname(path)}")
    processed.write_to_file(out, Q: CONFIG["jpeg_quality"] || 95)
    CLI_LOGGER.info "Saved #{File.basename(out)}"
    count += 1
  rescue StandardError => e
    LOGGER.error "Variation #{i + 1} failed: #{e.message}"
  end
  count
end

def get_input
  CLI_LOGGER.info "Postpro.rb v14.2.0 – Professional Edition"
  CLI_LOGGER.info "Repligen: #{REPLIGEN_PRESENT ? 'active' : 'inactive'}"
  check_repligen if REPLIGEN_PRESENT

  unless PROMPT
    return [["**/*.{jpg,jpeg,png,webp}"], CONFIG["variations"] || 2,
            { type: :preset, preset: CONFIG["default_preset"] || "portrait" }]
  end

  workflow = PROMPT.select("Workflow:", %w[Presets Random JSON])
  patterns = PROMPT.ask("File patterns:", default: "**/*.{jpg,jpeg,png,webp}").split(",").map(&:strip)
  variations = PROMPT.ask("Variations per image:", convert: :int, default: CONFIG["variations"] || 2) { |q| q.in("1-5") }

  case workflow
  when "Presets"
    preset = PROMPT.select("Preset:", PRESETS.keys)
    [patterns, variations, { type: :preset, preset: preset }]
  when "Random"
    mode = PROMPT.select("Mode:", %w[Professional Experimental]).downcase
    fx_cnt = PROMPT.ask("Effects per variation:", convert: :int, default: 4) { |q| q.in("2-8") }
    [patterns, variations, { type: :random, mode: mode, fx: fx_cnt }]
  else
    file = PROMPT.ask("Recipe file:")
    data = File.exist?(file) ? JSON.parse(File.read(file)) : {}
    [patterns, variations, { type: :recipe, recipe: data }]
  end
end

def auto_mode
  [["**/*.{jpg,jpeg,png,webp}"], CONFIG["variations"] || 2,
   { type: :preset, preset: CONFIG["default_preset"] || "portrait" }]
end

def auto_launch
  input =
    if ARGV.include?("--auto") || (!$stdin.tty? && ARGV.include?("--from-repligen"))
      auto_mode
    elsif ARGV.include?("--from-repligen") && REPLIGEN_PRESENT
      check_repligen
      return
    else
      get_input
    end
  return unless input

  patterns, variations, cfg = input
  files = patterns.flat_map { |p| Dir.glob(p) }
                 .reject { |f| f.match?(/processed|masterpiece/) }

  if files.empty?
    CLI_LOGGER.error "No matching files"
    return
  end

  CLI_LOGGER.info "Processing #{files.size} files"
  total_files = total_variations = 0
  start = Time.now

  files.each_with_index do |file, idx|
    CLI_LOGGER.info "#{idx + 1}/#{files.size}: #{File.basename(file)}"
    count =
      case cfg[:type]
      when :preset
        process_file(file, variations, cfg[:preset])
      when :random
        fx_pool = %w[grain leaks sepia bloom teal_orange cross vhs chroma glitch flare]
        selected = cfg[:mode] == "experimental" ? fx_pool : fx_pool.first(6)
        random_fx = selected.shuffle.take(cfg[:fx])
        process_file(file, variations, nil, nil, random_fx, cfg[:mode])
      when :recipe
        process_file(file, variations, nil, cfg[:recipe])
      else
        0
      end
    total_files += 1 if count.positive?
    total_variations += count
    GC.start if (idx % 10).zero?
  rescue StandardError => e
    LOGGER.error "File #{file}: #{e.message}"
    CLI_LOGGER.error "Error processing #{File.basename(file)}"
  end

  duration = (Time.now - start).round(2)
  CLI_LOGGER.info "Done – #{total_files} files → #{total_variations} outputs (#{duration}s)"
  CLI_LOGGER.info "Run 'ruby repligen.rb' for more content!" if REPLIGEN_PRESENT && total_variations.positive?
end

auto_launch if __FILE__ == $0