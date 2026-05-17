#!/usr/bin/env ruby
# frozen_string_literal: true

# Postpro.rb - Professional Cinematic Post-Processing
# Version: 16.0.0 - Full Analog Science

require "logger"
require "json"
require "time"
require "fileutils"

module PostproBootstrap
  def self.dmesg(msg)
    puts "[postpro] #{msg}"
  end

  def self.startup_banner
    ruby_version = RUBY_VERSION
    os = RbConfig::CONFIG["host_os"]
    dmesg "boot ruby=#{ruby_version} os=#{os}"
  end

  def self.ensure_gems
    vips_available = ensure_vips
    tty_available = ensure_tty_prompt
    
    dmesg "vipsgem=#{vips_available} tty=#{tty_available}"
    { vips: vips_available, tty: tty_available }
  end

  def self.ensure_vips
    require "vips"
    true
  rescue LoadError
    dmesg "WARN ruby-vips gem missing, attempting install..."
    begin
      if system("gem install ruby-vips --no-document")
        require "vips"
        dmesg "OK ruby-vips gem installed"
        true
      else
        dmesg "WARN ruby-vips install failed"
        probe_and_install_libvips
        false
      end
    rescue => e
      dmesg "WARN ruby-vips unavailable: #{e.message}"
      false
    end
  end

  def self.ensure_tty_prompt
    require "tty-prompt"
    true
  rescue LoadError
    dmesg "WARN tty-prompt gem missing, attempting install..."
    begin
      if system("gem install tty-prompt --no-document")
        require "tty-prompt"
        dmesg "OK tty-prompt gem installed"
        true
      else
        dmesg "WARN tty-prompt install failed, degraded prompt experience"
        false
      end
    rescue => e
      dmesg "WARN tty-prompt unavailable: #{e.message}"
      false
    end
  end

  def self.probe_and_install_libvips
    dmesg "probing libvips installation..."
    
    if system("pkg-config --exists vips") 
      dmesg "OK libvips already installed"
      return true
    end

    # Detect package manager and attempt install
    os = RbConfig::CONFIG["host_os"]
    case os
    when /darwin/
      if system("which brew > /dev/null 2>&1")
        dmesg "attempting: brew install vips"
        system("brew install vips")
      else
        dmesg "ERROR homebrew not found, install manually: brew install vips"
      end
    when /linux/
      if system("which apt > /dev/null 2>&1")
        dmesg "attempting: apt install libvips-dev"
        system("sudo apt update && sudo apt install -y libvips-dev")
      elsif system("which dnf > /dev/null 2>&1")
        dmesg "attempting: dnf install vips-devel"
        system("sudo dnf install -y vips-devel")
      elsif system("which yum > /dev/null 2>&1")
        dmesg "attempting: yum install vips-devel"
        system("sudo yum install -y vips-devel")
      elsif system("which apk > /dev/null 2>&1")
        dmesg "attempting: apk add vips-dev"
        system("sudo apk add vips-dev")
      elsif system("which pacman > /dev/null 2>&1")
        dmesg "attempting: pacman -S libvips"
        system("sudo pacman -S --noconfirm libvips")
      else
        dmesg "ERROR no supported package manager found"
      end
    when /openbsd/
      if system("which pkg_add > /dev/null 2>&1")
        dmesg "attempting: pkg_add vips"
        system("doas pkg_add vips")
      else
        dmesg "ERROR pkg_add not found"
      end
    else
      dmesg "ERROR unsupported OS: #{os}"
    end

    # Verify installation
    if system("pkg-config --exists vips")
      dmesg "OK libvips installation successful"
      true
    else
      dmesg "ERROR libvips installation failed"
      false
    end
  end

  def self.load_camera_profiles(profiles_path)
    profiles = {}
    
    unless Dir.exist?(profiles_path)
      dmesg "WARN camera profiles directory not found: #{profiles_path}"
      return profiles
    end

    Dir.glob(File.join(profiles_path, "*.json")).each do |file|
      begin
        data = JSON.parse(File.read(file))
        vendor = data["vendor"]
        if vendor && data["profiles"]
          profiles[vendor] = data["profiles"]
        end
      rescue => e
        dmesg "WARN failed to load profile #{File.basename(file)}: #{e.message}"
      end
    end

    brands = profiles.keys.join(",")
    dmesg "camera_profiles=#{brands.empty? ? 'none' : brands}"
    profiles
  end

  def self.load_master_config
    return {} unless File.exist?("master.json")
    
    begin
      master = JSON.parse(File.read("master.json").gsub(/^.*\/\/.*$/, ""))
      config = master.dig("config", "multimedia", "postpro") || {}
      dmesg "OK loaded defaults from master.json"
      config
    rescue => e
      dmesg "WARN failed to parse master.json: #{e.message}"
      {}
    end
  end

  def self.run
    startup_banner
    gems = ensure_gems
    
    unless gems[:vips]
      dmesg "FATAL libvips unavailable - image processing impossible"
      puts "\nPostpro.rb requires libvips for image processing."
      puts "Installation failed. Please install manually:"
      puts "  macOS: brew install vips"
      puts "  Ubuntu/Debian: sudo apt install libvips-dev"
      puts "  OpenBSD: doas pkg_add vips"
      exit 1
    end

    profiles_path = "multimedia/camera_profiles"
    camera_profiles = load_camera_profiles(profiles_path)
    config = load_master_config
    
    {
      gems: gems,
      camera_profiles: camera_profiles,
      config: config
    }
  end
end

# Initialize postpro
BOOTSTRAP = PostproBootstrap.run
$logger = Logger.new("postpro.log", "daily", level: Logger::DEBUG)
$cli_logger = Logger.new(STDOUT, level: Logger::INFO)

if BOOTSTRAP[:gems][:tty]
  require "tty-prompt"
  PROMPT = TTY::Prompt.new
else
  PROMPT = nil
end

if BOOTSTRAP[:gems][:vips]
  require "vips"
end

REPLIGEN_PRESENT = File.exist?("repligen.rb")
CAMERA_PROFILES = BOOTSTRAP[:camera_profiles]
CONFIG = BOOTSTRAP[:config]

# Per-stock data: grain sigma (legacy), 3x3 colour matrix, and characteristic
# curve [Dmin, Dmax, pivot, gamma] per R/G/B. Dmin lifts shadows (base+fog),
# Dmax caps highlights (shoulder), pivot is the linear midtone fulcrum (≈0.18),
# gamma is contrast (>1 = steeper). Per-channel offsets create stock colour cast.
STOCKS = {
  kodak_portra:       { grain: 15, matrix: [1.05, -0.02, -0.03, 0.02, 0.98, 0.00, 0.01, -0.05, 1.04],
                        hd: { r: [0.06, 0.93, 0.18, 1.10], g: [0.05, 0.94, 0.18, 1.10], b: [0.04, 0.92, 0.20, 1.05] } },
  kodak_vision3:      { grain: 20, matrix: [1.08, -0.05, -0.03, 0.03, 0.95, 0.02, 0.02, -0.08, 1.06],
                        hd: { r: [0.07, 0.95, 0.17, 1.15], g: [0.06, 0.95, 0.18, 1.20], b: [0.08, 0.90, 0.20, 1.10] } },
  kodak_vision3_50d:  { grain:  8, matrix: [1.06, -0.03, -0.02, 0.02, 0.96, 0.01, 0.01, -0.05, 1.04],
                        hd: { r: [0.05, 0.95, 0.18, 1.08], g: [0.04, 0.95, 0.18, 1.12], b: [0.03, 0.93, 0.20, 1.05] } },
  kodak_vision3_500t: { grain: 20, matrix: [1.10, -0.06, -0.04, 0.04, 0.94, 0.03, 0.04, -0.10, 1.09],
                        hd: { r: [0.08, 0.95, 0.17, 1.18], g: [0.06, 0.95, 0.18, 1.22], b: [0.10, 0.90, 0.20, 1.15] } },
  cinestill_800t:     { grain: 22, matrix: [1.12, -0.07, -0.05, 0.04, 0.93, 0.03, 0.05, -0.12, 1.10],
                        hd: { r: [0.09, 0.96, 0.17, 1.20], g: [0.07, 0.95, 0.18, 1.25], b: [0.12, 0.88, 0.20, 1.18] },
                        halation: 0.8 },
  ektachrome_100:     { grain: 10, matrix: [1.08, -0.04, -0.04, 0.02, 1.02, -0.02, 0.01, -0.08, 1.07],
                        hd: { r: [0.02, 0.97, 0.18, 1.30], g: [0.02, 0.97, 0.18, 1.35], b: [0.03, 0.96, 0.20, 1.25] } },
  fuji_velvia:        { grain:  8, matrix: [1.12, -0.08, -0.04, 0.05, 1.05, -0.02, 0.01, -0.12, 1.11],
                        hd: { r: [0.02, 0.97, 0.18, 1.45], g: [0.02, 0.98, 0.18, 1.50], b: [0.03, 0.95, 0.20, 1.40] } },
  tri_x:              { grain: 25, matrix: [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
                        hd: { r: [0.05, 0.95, 0.18, 1.30], g: [0.05, 0.95, 0.18, 1.30], b: [0.05, 0.95, 0.18, 1.30] } },
  # Kodachrome: steep gamma, no in-film couplers, external development process.
  # Punchy reds, heavy yellow separation, minimal shadow fog.
  kodachrome:         { grain: 12, matrix: [1.15, -0.10, -0.05, 0.03, 1.00, -0.03, 0.00, -0.10, 1.10],
                        hd: { r: [0.02, 0.97, 0.18, 1.42], g: [0.03, 0.97, 0.18, 1.36], b: [0.04, 0.95, 0.20, 1.20] } }
}.freeze

# Lens character: data-driven table drives vintage_lens().
# vignette/glow/micro_contrast/chroma are intensity multipliers [0,1].
LENSES = {
  zeiss:      { micro_contrast: 0.40, flare: 0.08 },
  leica:      { micro_contrast: 0.45, glow: 0.25 },
  helios:     { micro_contrast: 0.30, chroma: 0.05 },
  cooke:      { micro_contrast: 0.20, warmth: 0.10 },
  anamorphic: { micro_contrast: 0.25, chroma: 0.08, flare: 0.50 },
}.freeze

# Per-stock R/G/B channel amplitude ratios for grain — mirrors the three
# dye-layer sensitivities. Red layer is reference (1.00), green and blue
# attenuated to match the stock's measured dye-cloud statistics.
GRAIN_CHAN_SCALE = {
  kodak_portra:       [1.00, 0.85, 0.70],
  kodak_vision3:      [1.00, 0.90, 0.80],
  kodak_vision3_50d:  [1.00, 0.88, 0.75],
  kodak_vision3_500t: [1.00, 0.88, 0.72],
  cinestill_800t:     [1.05, 0.88, 0.75],
  ektachrome_100:     [0.95, 0.95, 1.05],
  fuji_velvia:        [1.00, 1.10, 0.90],
  tri_x:              [1.00, 1.00, 1.00],
  kodachrome:         [1.00, 0.92, 0.82],
}.freeze

PRESETS = {
  portrait:       { fx: %w[skin_protect film_curve highlight_roll micro_contrast grain color_temp base_tint],
                    stock: :kodak_portra,       temp: 5200, intensity: 0.8 },
  landscape:      { fx: %w[film_curve color_separate highlight_roll micro_contrast grain vintage_lens],
                    stock: :fuji_velvia,        temp: 5800, intensity: 0.9 },
  street:         { fx: %w[film_curve shadow_lift micro_contrast vintage_lens grain],
                    stock: :tri_x,              temp: 5600, intensity: 1.0 },
  blockbuster:    { fx: %w[tonemap teal_orange halation grain bloom_pro highlight_roll micro_contrast],
                    stock: :kodak_vision3,      temp: 4800, intensity: 1.2 },
  dream:          { fx: %w[film_curve halation shadow_lift desaturate vintage_lens cross_fade],
                    stock: :ektachrome_100,     temp: 5800, intensity: 0.8, lens: "leica" },
  neon_night:     { fx: %w[film_curve halation grain teal_orange micro_contrast chromatic_aberration],
                    stock: :cinestill_800t,     temp: 3200, intensity: 1.0 },
  horror:         { fx: %w[film_curve green_push desaturate micro_contrast grain split_toning],
                    stock: :tri_x,              temp: 5600, intensity: 1.0 },
  golden_age:     { fx: %w[film_curve halation warmth vintage_lens grain micro_contrast dual_base_density],
                    stock: :kodak_vision3_50d,  temp: 5200, intensity: 0.9, lens: "cooke" },
  indie:          { fx: %w[film_curve grain shadow_lift vintage_lens micro_contrast faded_print],
                    stock: :kodak_portra,       temp: 5400, intensity: 0.7 },
  cinematic:      { fx: %w[tonemap bleach_bypass halation grain micro_contrast split_grade],
                    stock: :kodak_vision3_500t, temp: 4500, intensity: 1.0 },
  kodachrome_look:{ fx: %w[kodachrome_sim grain micro_contrast highlight_roll dir_coupler],
                    stock: :kodachrome,         temp: 5600, intensity: 0.9 },
  cross_process:  { fx: %w[film_curve color_separate grain shadow_lift micro_contrast split_toning],
                    stock: :fuji_velvia,        temp: 5500, intensity: 1.2 },
  silver_gelatin: { fx: %w[film_curve grain lith_print micro_contrast],
                    stock: :tri_x,              temp: 5600, intensity: 0.8 },
  vintage_chrome: { fx: %w[film_curve faded_print split_toning grain dual_base_density],
                    stock: :ektachrome_100,     temp: 5200, intensity: 0.7 },
  infrared_look:  { fx: %w[optical_blur infrared grain micro_contrast],
                    stock: :tri_x,              temp: 5600, intensity: 0.9 },
}.freeze

def halation_tint_for(stock)
  case stock
  when :kodak_vision3, :kodak_vision3_500t then HALATION_TINT_VISION3
  when :cinestill_800t                     then HALATION_TINT_VISION3
  when :kodak_portra, :kodak_vision3_50d   then HALATION_TINT_PORTRA
  when :tri_x                              then HALATION_TINT_TRI_X
  when :ektachrome_100                     then HALATION_TINT_PORTRA
  when :kodachrome                         then HALATION_TINT_PORTRA
  else                                          HALATION_TINT_VISION3
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
  CACHE = {}

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
    hd = stock_data[:hd] or return nil
    bands = %i[r g b].map { |c| Vips::Image.new_from_array([channel_curve(hd[c])]) }
    Vips::Image.bandjoin(bands).cast('uchar')
  end

  def lut_for(stock_data)
    CACHE[stock_data.object_id] ||= build_lut(stock_data)
  end

  def apply(image, stock_data)
    lut = lut_for(stock_data)
    lut ? image.maplut(lut) : image
  end
end

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
  image = Vips::Image.new_from_file(file, access: :random)
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
    
    # Try exact model match first
    CAMERA_PROFILES.each do |brand, profiles|
      return profiles[model] if profiles[model]
    end
    
    # Try brand match
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
    
    # Apply 3x3 color matrix
    result = image.recomb([
      [matrix[0], matrix[1], matrix[2]],
      [matrix[3], matrix[4], matrix[5]],
      [matrix[6], matrix[7], matrix[8]]
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
  rescue => e
    $logger.error "Camera profile failed: #{e.message}"
    image
  end
end

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
  CACHE = {}

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
    CACHE[:basis] ||= begin
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
  inv_protection = protection_rgb.linear(-1, 1)

  safe_cast(image * inv_protection + image * protection_rgb)
end

def film_curve(image, stock = :kodak_portra, intensity = 1.0)
  data      = STOCKS[stock] || STOCKS[:kodak_portra]
  developed = HD.apply(image, data)
  safe_cast(image * (1 - intensity) + developed * intensity)
end

def highlight_roll(image, threshold = 200, intensity = 1.0)
  mask = image > threshold
  over_exposed = image - threshold
  rolled_off = ((over_exposed * 0.3) ** 0.7) + threshold
  result = mask.ifthenelse(rolled_off, image)
  safe_cast(image * (1 - intensity) + result * intensity)
end

def shadow_lift(image, lift = 0.15, preserve_blacks = true)
  gray = image.colourspace('grey16').cast('float') / 255.0
  inv_gray    = gray.linear(-1, 1)
  shadow_mask = preserve_blacks ? (inv_gray ** 2.0) * 0.8 : inv_gray * lift
  lift_rgb = shadow_mask.bandjoin([shadow_mask, shadow_mask])
  safe_cast(image + lift_rgb * 255 * lift)
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

GRAIN_SPATIAL_DIV  = 8
GRAIN_TARGET_DIV   = 1600.0
GRAIN_BLUR_INVERSE = 1.0 / 0.36

# Newson-Delon density-space grain: three independent per-channel noise images
# blurred to stock-specific spatial σ, modulated by midtone visibility envelope
# 4L(1-L). Per-channel amplitudes from GRAIN_CHAN_SCALE mirror the three dye
# layers — red layer is coarsest, blue finest on most stocks. Operates in
# linearized sRGB so noise stays photometric.
def grain(image, iso = 400, stock = :kodak_portra, intensity = 0.4)
  data    = STOCKS[stock] || STOCKS[:kodak_portra]
  scales  = GRAIN_CHAN_SCALE[stock] || [1.0, 1.0, 1.0]
  spatial = [data[:grain] / GRAIN_SPATIAL_DIV.to_f, 0.5].max
  target  = data[:grain] * Math.sqrt(iso / 100.0) * intensity / GRAIN_TARGET_DIV
  pre     = [target * spatial * GRAIN_BLUR_INVERSE, 0.001].max

  linear = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  luma = r * 0.2126 + g * 0.7152 + b * 0.0722
  envelope = (luma * luma.linear([-1], [1])).linear([4], [0])

  bands = scales.map do |scale|
    Vips::Image.gaussnoise(image.width, image.height, sigma: pre * scale, mean: 0.0).gaussblur(spatial)
  end
  noise = Vips::Image.bandjoin(bands)
  safe_cast((linear + noise * envelope).colourspace("srgb"))
end

def base_tint(image, color = [252, 248, 240], intensity = 0.08)
  overlay = Vips::Image.black(image.width, image.height, bands: 3) + color
  overlay_norm = overlay.cast('float') / 255.0
  image_norm = image.cast('float') / 255.0
  
  inv_image   = image_norm.linear(-1, 1)
  inv_overlay = overlay_norm.linear(-1, 1)
  multiply    = image_norm * overlay_norm * 2
  screen      = (inv_image * inv_overlay).linear(-2, 1)
  result      = (overlay_norm < 0.5).ifthenelse(multiply, screen)

  blended = result * 255
  safe_cast(image * (1 - intensity) + blended * intensity)
end

def vintage_lens(image, type = "zeiss", intensity = 0.7)
  spec = LENSES[type.to_sym] || LENSES[:zeiss]
  result = image
  result = micro_contrast(result, 4, spec[:micro_contrast] * intensity) if spec[:micro_contrast]
  if spec[:glow]
    glow = image.gaussblur(20) * (spec[:glow] * intensity)
    result = safe_cast(result + glow)
  end
  if spec[:chroma]
    shift = [(spec[:chroma] * intensity * 6).round, 1].max
    r, g, b = result.bandsplit
    r = r.embed(shift, 0, result.width, result.height)
    b = b.embed(-shift, 0, result.width, result.height)
    result = safe_cast(Vips::Image.bandjoin([r, g, b]))
  end
  result = warmth(result, spec[:warmth] * intensity) if spec[:warmth]
  result
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
    [0, 0, 0]
  ).then { |r| safe_cast(r) }
rescue StandardError => e
  $logger.error "warmth failed: #{e.message}"
  image
end

# Desaturated green push for horror / cold clinical grades.
def green_push(image, amount = 0.15)
  image.linear(
    [1.0 - amount * 0.50, 1.0 + amount, 1.0 - amount * 0.30],
    [0, 0, 0]
  ).then { |r| safe_cast(r) }
rescue StandardError => e
  $logger.error "green_push failed: #{e.message}"
  image
end

# OLPF (optical low-pass filter) simulation — gentle pre-blur that removes
# aliasing-scale detail before the film grain is laid down.
def optical_blur(image, sigma = 0.6)
  safe_cast(image.gaussblur([sigma, 0.3].max))
rescue StandardError => e
  $logger.error "optical_blur: #{e.message}"; image
end

# Lateral chromatic aberration: R/B fringe separation at sensor edges.
def chromatic_aberration(image, strength = 0.5)
  shift = [(strength * 3.0).round, 1].max
  r, g, b = image.bandsplit
  r2 = r.embed(shift, 0, image.width, image.height)
  b2 = b.embed(-shift, 0, image.width, image.height)
  safe_cast(Vips::Image.bandjoin([r2, g, b2]))
rescue StandardError => e
  $logger.error "chromatic_aberration: #{e.message}"; image
end

# DIR coupler inhibition: development byproducts from one dye layer inhibit
# adjacent layers, slightly desaturating pure hues and sharpening edges.
def dir_coupler(image, strength = 0.15)
  blurred   = image.gaussblur(2.0)
  high_pass = image.cast("float") - blurred.cast("float")
  gray      = image.colourspace("grey16").colourspace("srgb").cast("float")
  img_f     = image.cast("float")
  desatd    = img_f * (1.0 - strength * 0.3) + gray * (strength * 0.3)
  safe_cast((desatd + high_pass * (strength * 0.5)).cast("uchar"))
rescue StandardError => e
  $logger.error "dir_coupler: #{e.message}"; image
end

# Bleach bypass: skip bleach step, retain silver alongside dye. Result is
# high contrast, desaturated, with lifted shadow detail. Screen-blend of a
# B&W layer over the colour image.
def bleach_bypass(image, intensity = 0.5)
  img_f  = image.cast("float") / 255.0
  gray_f = image.colourspace("grey16").colourspace("srgb").cast("float") / 255.0
  screen = (img_f.linear(-1, 1) * gray_f.linear(-1, 1)).linear(-1, 1)
  result = img_f * (1.0 - intensity) + screen * intensity
  safe_cast(clamp01(result) * 255.0)
rescue StandardError => e
  $logger.error "bleach_bypass: #{e.message}"; image
end

# Push/pull processing: change development time equivalent. Positive stops
# push (more exposure time → lifted blacks, boosted grain), negative pull
# (reduced development → compressed shadows, softer contrast).
def push_pull(image, stops = 1.0)
  linear  = image.colourspace("scrgb")
  exposed = clamp01(linear * (2.0**stops))
  if stops > 0
    shadow_add = exposed.linear(-1, 1) ** 2.0 * (stops * 0.04)
    exposed    = clamp01(exposed + shadow_add)
  end
  safe_cast(exposed.colourspace("srgb"))
rescue StandardError => e
  $logger.error "push_pull: #{e.message}"; image
end

# Split toning: shadow and highlight color casts weighted by luminance.
# shadow_rgb / hi_rgb are [R,G,B] triplets in 0-255.
def split_toning(image, shadow_rgb = [45, 35, 60], hi_rgb = [255, 240, 210], intensity = 0.30)
  luma  = image.colourspace("grey16").cast("float") / 255.0
  img_f = image.cast("float") / 255.0
  s_clr = (Vips::Image.black(image.width, image.height, bands: 3) + shadow_rgb).cast("float") / 255.0
  h_clr = (Vips::Image.black(image.width, image.height, bands: 3) + hi_rgb).cast("float") / 255.0
  s_w   = luma.linear(-1, 1) * intensity * 0.55
  h_w   = luma               * intensity * 0.55
  result = img_f + (s_clr - img_f) * s_w + (h_clr - img_f) * h_w
  safe_cast(clamp01(result) * 255.0)
rescue StandardError => e
  $logger.error "split_toning: #{e.message}"; image
end

# Three-way color corrector: independent shadow / midtone / highlight casts.
def split_grade(image, shadow_rgb = [30, 40, 60], mid_rgb = [255, 255, 248], hi_rgb = [255, 245, 220], intensity = 0.25)
  luma  = image.colourspace("grey16").cast("float") / 255.0
  img_f = image.cast("float") / 255.0
  s_clr = (Vips::Image.black(image.width, image.height, bands: 3) + shadow_rgb).cast("float") / 255.0
  m_clr = (Vips::Image.black(image.width, image.height, bands: 3) + mid_rgb).cast("float") / 255.0
  h_clr = (Vips::Image.black(image.width, image.height, bands: 3) + hi_rgb).cast("float") / 255.0
  s_w = (luma.linear(-1, 1) ** 2.0) * intensity * 0.5
  m_w = (luma * luma.linear(-1, 1) * 4.0)  * intensity * 0.5
  h_w = (luma ** 2.0)                       * intensity * 0.5
  result = img_f + (s_clr - img_f) * s_w + (m_clr - img_f) * m_w + (h_clr - img_f) * h_w
  safe_cast(clamp01(result) * 255.0)
rescue StandardError => e
  $logger.error "split_grade: #{e.message}"; image
end

# Film base density: multiplicative dye-density layer that shifts both color
# and overall density — warmer and slightly darker than a simple tint.
def dual_base_density(image, color = [255, 248, 235], opacity = 0.07)
  r_m, g_m, b_m = color.map { |c| c / 255.0 }
  img_f      = image.cast("float") / 255.0
  multiplied = img_f.linear([r_m, g_m, b_m], [0, 0, 0])
  result     = img_f * (1.0 - opacity) + multiplied * opacity
  safe_cast(clamp01(result) * 255.0)
rescue StandardError => e
  $logger.error "dual_base_density: #{e.message}"; image
end

# Reciprocity failure: long exposures exhibit non-linear response — blue
# channel lags most (needs correction exposure), shadows over-develop slightly.
def reciprocity_failure(image, exposure_seconds = 10.0)
  ev = Math.log2([exposure_seconds, 1.0].max) / 10.0
  linear = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  luma    = r * 0.2126 + g * 0.7152 + b * 0.0722
  dark_w  = luma.linear(-1, 1)
  result  = Vips::Image.bandjoin([
    r + dark_w * ev * 0.03,
    g + dark_w * ev * 0.02,
    b + (ev * 0.15) + dark_w * ev * 0.05
  ])
  safe_cast(clamp01(result).colourspace("srgb"))
rescue StandardError => e
  $logger.error "reciprocity_failure: #{e.message}"; image
end

# Dreamy soft cross-fade: soft-light blend of a blurred copy over the image.
def cross_fade(image, intensity = 0.4)
  blur_f = image.gaussblur(12.0).cast("float") / 255.0
  img_f  = image.cast("float") / 255.0
  screen = (img_f.linear(-1, 1) * blur_f.linear(-1, 1)).linear(-1, 1)
  soft   = (blur_f < 0.5).ifthenelse(img_f * blur_f * 2.0, screen)
  result = img_f * (1.0 - intensity) + soft * intensity
  safe_cast(clamp01(result) * 255.0)
rescue StandardError => e
  $logger.error "cross_fade: #{e.message}"; image
end

# Infrared simulation: green channel → bright (foliage), blue → dark (sky).
# Heavy green mix approximates IR film's extended-red/near-IR sensitivity.
def infrared(image, intensity = 0.8)
  r, g, b = image.cast("float").bandsplit
  ir  = r * 0.20 + g * 0.80 + (b > 0).ifthenelse(b, 0).linear(-1, 0) * 0.15
  ir  = (ir > 0).ifthenelse(ir, 0)
  glow = ir.gaussblur(8.0) * 0.25
  ir3 = Vips::Image.bandjoin([ir + glow, ir + glow, ir + glow])
  result = image.cast("float") * (1.0 - intensity) + ir3 * intensity
  safe_cast(result.cast("uchar"))
rescue StandardError => e
  $logger.error "infrared: #{e.message}"; image
end

# Cyanotype alt-process: Prussian blue shadows [0,52,102] to white highlights.
def cyanotype(image, intensity = 0.90)
  shadow = [0, 52, 102]
  luma   = image.colourspace("grey16").cast("float") / 255.0
  r = luma * (255 - shadow[0]) + shadow[0]
  g = luma * (255 - shadow[1]) + shadow[1]
  b = luma * (255 - shadow[2]) + shadow[2]
  cyan   = Vips::Image.bandjoin([r, g, b])
  result = image.cast("float") * (1.0 - intensity) + cyan * intensity
  safe_cast(result.cast("uchar"))
rescue StandardError => e
  $logger.error "cyanotype: #{e.message}"; image
end

# Lith printing: aggressive contrast, warm sepia shadows, near-white highlights.
def lith_print(image, intensity = 0.80)
  gray = image.colourspace("grey16").cast("float") / 255.0
  hi   = clamp01(gray ** 0.55 * 1.1)
  s_w  = (gray.linear(-1, 1) ** 2.0) * 255.0
  r    = hi * 255.0 + s_w * 0.12
  g    = hi * 255.0 - s_w * 0.04
  b    = hi * 255.0 - s_w * 0.16
  lith = Vips::Image.bandjoin([r, g, b])
  result = image.cast("float") * (1.0 - intensity) + lith * intensity
  safe_cast(result.cast("uchar"))
rescue StandardError => e
  $logger.error "lith_print: #{e.message}"; image
end

# Technicolor 3-strip: per-channel strip registration offset + heavy dye saturation.
def technicolor(image, intensity = 0.60)
  r, g, b = image.bandsplit
  r2 = r.embed(1, 0, image.width, image.height)
  b2 = b.embed(-1, 1, image.width, image.height)
  combined = Vips::Image.bandjoin([r2, g, b2])
  hsv = combined.colourspace("hsv")
  h, s, v = hsv.bandsplit
  s_hi = safe_cast(s.linear([1.0 + intensity * 0.7], [0]))
  boosted = Vips::Image.bandjoin([h, s_hi, v]).colourspace("srgb")
  safe_cast((image.cast("float") * (1.0 - intensity) + boosted.cast("float") * intensity).cast("uchar"))
rescue StandardError => e
  $logger.error "technicolor: #{e.message}"; image
end

# Kodachrome simulation: steep per-channel H&D curve + external coupler saturation.
def kodachrome_sim(image, intensity = 0.70)
  result = film_curve(image, :kodachrome, intensity * 0.85)
  hsv    = result.colourspace("hsv")
  h, s, v = hsv.bandsplit
  s_hi = safe_cast(s.linear([1.0 + intensity * 0.45], [0]))
  v_hi = safe_cast(v.linear([1.0 + intensity * 0.08], [0]))
  saturated = Vips::Image.bandjoin([h, s_hi, v_hi]).colourspace("srgb")
  safe_cast((result.cast("float") * (1.0 - intensity * 0.25) +
             saturated.cast("float") * intensity * 0.25).cast("uchar"))
rescue StandardError => e
  $logger.error "kodachrome_sim: #{e.message}"; image
end

# Aged photographic print: contrast compression, warm yellow-brown lift, soft blur.
def faded_print(image, age = 0.5)
  img_f = image.cast("float") / 255.0
  comp  = img_f * (1.0 - age * 0.35) + (age * 0.12)
  shift = comp.linear([1.0, 1.0, 1.0], [age * 0.10, age * 0.06, -(age * 0.12)])
  out   = safe_cast(clamp01(shift) * 255.0)
  age > 0.3 ? safe_cast(out.gaussblur(age * 1.2)) : out
rescue StandardError => e
  $logger.error "faded_print: #{e.message}"; image
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

# Halation in linear (exposure) space. Bright light penetrates the emulsion,
# reflects off the substrate's antihalation backing imperfectly, and re-exposes
# nearby grains. Red wavelengths penetrate deepest, so the rebound glow is
# red-orange — never neutral. Default tint matches Vision3-style stocks; Velvia
# antihalation is near-perfect (drop intensity), Tri-X has none (boost it).
# Pipeline: linearize → soft-threshold highlights at L≈0.7 → wide gaussian on
# the mono source map → tint asymmetrically (R>G>>B) → add back → re-encode.
HALATION_TINT_VISION3 = [1.0,  0.35, 0.08].freeze
HALATION_TINT_PORTRA  = [1.0,  0.30, 0.06].freeze
HALATION_TINT_TRI_X   = [0.55, 0.55, 0.55].freeze
HALATION_THRESHOLD    = 0.7

# Halation: resolution-aware σ ≈ width/45 (≈43px at 2K, calibrated from agx
# emulsion measurements). Luma-based bright mask rather than red-only, so
# over-exposed highlights on any channel trigger the halo. Per-channel blur
# radii R>G>>B model wavelength-dependent penetration depth in the emulsion
# stack. Output clamp prevents HDR overshoot from adding solarization.
def halation(image, intensity = 1.0, tint: HALATION_TINT_VISION3)
  sigma_r = [image.width / 45.0, 6.0].max.clamp(6.0, 120.0)
  sigma_g = sigma_r * 0.55
  sigma_b = sigma_r * 0.25
  linear  = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  luma    = r * 0.2126 + g * 0.7152 + b * 0.0722
  excess  = luma.linear([1], [-HALATION_THRESHOLD])
  bright  = (excess > 0).ifthenelse(excess, 0) ** 2
  halo_r  = bright.gaussblur(sigma_r) * (tint[0] * intensity)
  halo_g  = bright.gaussblur(sigma_g) * (tint[1] * intensity)
  halo_b  = bright.gaussblur(sigma_b) * (tint[2] * intensity)
  halo    = Vips::Image.bandjoin([halo_r, halo_g, halo_b])
  safe_cast(clamp01(linear + halo).colourspace("srgb"))
end

# Filmic tonemap in linear (exposure) space. ACES is the Narkowicz fit to the
# Academy RRT+ODT — fast, photometric, the canonical "filmic" curve. Hable is
# Uncharted-2's S-curve, slightly more controllable shoulder, used in many
# cinematic productions. Both per-channel; chroma drift in the shoulder is the
# expected filmic behaviour. Exposure is applied in stops (2^EV) before the
# curve, so a +1.0 stop doubles linear light pre-tonemap.
TONEMAP_ACES  = { a: 2.51, b: 0.03, c: 2.43, d: 0.59, e: 0.14 }.freeze
TONEMAP_HABLE = { a: 0.15, b: 0.50, c: 0.10, d: 0.20, e: 0.02, f: 0.30, w: 1.0 }.freeze
# Hejl-Burgess-Dawson: no division path in shadows, slight toe lift.
# Good for scenes where ACES reads too contrasty in the blacks.
TONEMAP_HBD   = { a: 6.2, b: 0.5, c: 1.7, d: 0.06 }.freeze

def tonemap(image, type: :aces, exposure: 0.0, intensity: 1.0)
  linear  = image.colourspace("scrgb")
  exposed = linear.linear([2.0**exposure] * 3, [0, 0, 0])
  curved  = case type.to_sym
            when :hable then tonemap_hable(exposed)
            when :hbd   then tonemap_hbd(exposed)
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

def tonemap_hbd(linear)
  a, b, c, d = TONEMAP_HBD.values_at(:a, :b, :c, :d)
  curved = linear.bandsplit.map do |x|
    num = (x * x).linear([a], [0]) + x.linear([b], [0])
    den = (x * x).linear([a], [0]) + x.linear([c], [d])
    num / den
  end
  Vips::Image.bandjoin(curved)
end

# Preset Application
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
             when "teal_orange"          then teal_orange(result, p[:intensity])
             when "bloom_pro"            then bloom_pro(result, p[:intensity])
             when "halation"             then halation(result, p[:intensity], tint: halation_tint_for(p[:stock]))
             when "tonemap"              then tonemap(result, type: :aces, exposure: 0.0, intensity: p[:intensity] * 0.7)
             when "spectral_temp"        then spectral_temp(result, source_kelvin: 5500, target_kelvin: p[:temp], intensity: p[:intensity] * 0.6)
             when "desaturate"           then desaturate(result, p[:intensity] * 0.6)
             when "warmth"               then warmth(result, p[:intensity] * 0.3)
             when "green_push"           then green_push(result, p[:intensity] * 0.15)
             when "vintage_lens"         then vintage_lens(result, p.fetch(:lens, "zeiss"), p[:intensity] * 0.8)
             when "optical_blur"         then optical_blur(result)
             when "chromatic_aberration" then chromatic_aberration(result, p[:intensity] * 0.35)
             when "dir_coupler"          then dir_coupler(result, p[:intensity] * 0.15)
             when "bleach_bypass"        then bleach_bypass(result, p[:intensity] * 0.5)
             when "push_pull"            then push_pull(result, p.fetch(:stops, 1.0))
             when "split_toning"         then split_toning(result)
             when "split_grade"          then split_grade(result)
             when "dual_base_density"    then dual_base_density(result)
             when "reciprocity_failure"  then reciprocity_failure(result, p.fetch(:exposure_secs, 10.0))
             when "cross_fade"           then cross_fade(result, p[:intensity] * 0.4)
             when "infrared"             then infrared(result, p[:intensity] * 0.8)
             when "cyanotype"            then cyanotype(result, p[:intensity])
             when "lith_print"           then lith_print(result, p[:intensity] * 0.8)
             when "technicolor"          then technicolor(result, p[:intensity] * 0.6)
             when "kodachrome_sim"       then kodachrome_sim(result, p[:intensity] * 0.7)
             when "faded_print"          then faded_print(result, 0.5)
             else result
             end
  end
  
  result
end

# Random Effects
def random_fx(image, effects, mode)
  result = image
  effects.each do |fx|
    intensity = mode == 'experimental' ? rand(0.5..1.5) : rand(0.3..0.8)
    result = case fx
             when 'grain' then grain_basic(result, intensity)
             when 'leaks' then leaks_basic(result, intensity)
             when 'sepia' then sepia_basic(result, intensity)
             when 'bloom' then bloom_basic(result, intensity)
             when 'teal_orange' then teal_orange(result, intensity)
             when 'cross' then cross_basic(result, intensity)
             when 'vhs' then vhs_basic(result, intensity)
             when 'chroma' then chroma_basic(result, intensity)
             when 'glitch' then glitch_basic(result, intensity)
             when 'flare' then flare_basic(result, intensity)
             else result
             end
  end
  result
end

def grain_basic(image, intensity)
  noise = Vips::Image.gaussnoise(image.width, image.height, sigma: 25 * intensity)
  safe_cast(image + rgb_bands(noise) * 0.2)
end

def leaks_basic(image, intensity)
  overlay = Vips::Image.black(image.width, image.height, bands: 3)
  rand(2..5).times do
    x, y = rand(image.width), rand(image.height)
    radius = image.width / rand(2..4)
    color = [255 * intensity, 180 * intensity, 80 * intensity]
    overlay = overlay.draw_circle(color, x, y, radius, fill: true)
  end
  safe_cast(image + overlay.gaussblur(15 * intensity) * 0.3)
end

def sepia_basic(image, intensity)
  matrix = [0.9, 0.7, 0.2, 0.3, 0.8, 0.1, 0.2, 0.6, 0.1]
  safe_cast(image.recomb(matrix))
end

def bloom_basic(image, intensity)
  bright = image.linear([1.8 * intensity], [0]).gaussblur(12 * intensity)
  safe_cast(image + bright * 0.3)
end

def cross_basic(image, intensity)
  r, g, b = image.bandsplit
  r = r.linear([1 + 0.2 * intensity], [10 * intensity])
  g = g.linear([1 - 0.1 * intensity], [0])
  b = b.linear([1 + 0.3 * intensity], [-5 * intensity])
  safe_cast(Vips::Image.bandjoin([r, g, b]))
end

def vhs_basic(image, intensity)
  noise = rgb_bands(Vips::Image.gaussnoise(image.width, image.height, sigma: 40 * intensity))
  lines = rgb_bands(Vips::Image.sines(image.width, image.height).linear(0.3 * intensity, 150))
  safe_cast(image + noise * 0.4 + lines * 0.3)
end

def chroma_basic(image, intensity)
  shift = 3 * intensity
  r, g, b = image.bandsplit
  r = r.embed(shift, 0, image.width, image.height)
  b = b.embed(-shift, 0, image.width, image.height)
  safe_cast(Vips::Image.bandjoin([r, g, b]))
end

def glitch_basic(image, intensity)
  r, g, b = image.bandsplit
  shift = 15 * intensity
  r = r.embed(rand(-shift..shift), rand(-shift..shift), image.width, image.height)
  g = g.embed(rand(-shift..shift), rand(-shift..shift), image.width, image.height)
  b = b.embed(rand(-shift..shift), rand(-shift..shift), image.width, image.height)
  noise = rgb_bands(Vips::Image.gaussnoise(image.width, image.height, sigma: 20 * intensity))
  safe_cast(Vips::Image.bandjoin([r, g, b]) + noise * 0.4)
end

def flare_basic(image, intensity)
  flare = Vips::Image.black(image.width, image.height, bands: 3)
  rand(3..6).times do
    x, y = rand(image.width), rand(image.height)
    length = 200 * intensity
    flare = flare.draw_line([255, 220, 180], x, y, x + length, y)
  end
  safe_cast(image + flare.gaussblur(8 * intensity) * 0.3)
end

def recipe(image, recipe_data)
  result = image
  recipe_data.each do |fx, params|
    intensity = params.is_a?(Hash) ? params['intensity'].to_f : params.to_f
    method = fx.gsub('_professional', '')
    result = respond_to?(method) ? send(method, result, intensity) : result
  end
  result
end

# Export a 3D LUT (.cube) for a preset. size³ lattice points; 17 is standard
# for color-grading workflows, 33 for higher precision.
def export_lut(preset_name, path, size = 17)
  step = 1.0 / (size - 1)
  lines = ["LUT_3D_SIZE #{size}", "DOMAIN_MIN 0.0 0.0 0.0", "DOMAIN_MAX 1.0 1.0 1.0", ""]
  size.times do |bi|
    size.times do |gi|
      size.times do |ri|
        pix = Vips::Image.black(1, 1, bands: 3) + [ri * step * 255, gi * step * 255, bi * step * 255]
        out = preset(pix.cast("uchar"), preset_name)
        ro = out.extract_band(0).avg / 255.0
        go = out.extract_band(1).avg / 255.0
        bo = out.extract_band(2).avg / 255.0
        lines << "%.6f %.6f %.6f" % [ro.clamp(0, 1), go.clamp(0, 1), bo.clamp(0, 1)]
      end
    end
  end
  File.write(path, lines.join("\n") + "\n")
  $cli_logger.info "LUT exported: #{path} (#{size}^3)"
rescue StandardError => e
  $cli_logger.error "export_lut failed: #{e.message}"
end

# Introspection
def describe_preset(name)
  p = PRESETS[name.to_sym] or return "unknown preset: #{name}"
  stock = STOCKS[p[:stock]]
  [
    "#{name}: #{p[:stock]} / #{p.fetch(:temp, "?")}K / intensity #{p[:intensity]}",
    "fx: #{p[:fx].join(" → ")}",
    stock ? "grain σ=#{stock[:grain]}" : nil
  ].compact.join("\n")
end

def list_presets = PRESETS.keys.map { |k| describe_preset(k) }.join("\n\n")
def list_stocks  = STOCKS.keys.join(", ")
def list_lenses  = LENSES.keys.join(", ")

# CSS filter string approximating a preset — for lightweight web previews.
def css_filter(preset_name = :portrait)
  p = PRESETS[preset_name.to_sym] || PRESETS[:portrait]
  stock = STOCKS[p[:stock]] || {}
  hd = stock[:hd] || {}
  contrast = (1 + ((hd[:r]&.last || 1.0) - 1.0) * 0.25).round(2)
  saturate  = p[:fx].include?("teal_orange") ? 1.20 :
              p[:fx].include?("desaturate")  ? 0.65 : 1.0
  parts = ["contrast(#{contrast})", "saturate(#{saturate})"]
  parts << "sepia(0.12)"    if %i[kodak_portra kodak_vision3_50d].include?(p[:stock])
  parts << "grayscale(0.9)" if p[:stock] == :tri_x
  parts.join(" ")
end

# Repligen Integration
def check_repligen
  return unless REPLIGEN_PRESENT
  
  $cli_logger.info 'Repligen detected! Auto-processing generated images...'
  
  recent_files = Dir.glob('*_generated_*.{jpg,jpeg,png,webp}')
                    .select { |f| File.mtime(f) > (Time.now - 300) }
  
  if recent_files.any?
    $cli_logger.info "Found #{recent_files.count} recent Repligen outputs"
    preset_name = PROMPT.select('Choose preset for Repligen outputs:', PRESETS.keys)
    recent_files.each { |file| process_file(file, 2, preset_name) }
  end
end

def process_file(file, variations, preset_name = nil, recipe_data = nil, random_effects = nil, mode = "professional")
  image = load_image(file)
  return 0 unless image
  
  # Apply camera profile first if enabled
  if CONFIG["apply_camera_profile_first"]
    profile = get_camera_profile(image)
    if profile
      image = apply_camera_profile(image, profile)
      PostproBootstrap.dmesg "applied camera profile for #{file}"
    end
  end
  
  processed_count = 0
  variations.times do |i|
    begin
      processed = if preset_name
                     preset(image, preset_name)
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
      if ARGV.include?("--tiff16") || output.end_with?(".tif", ".tiff")
        processed.cast("ushort").write_to_file(output.sub(/\.(jpg|jpeg|png)$/i, ".tif"))
      else
        processed.write_to_file(output, Q: quality)
      end
      $cli_logger.info "Saved masterpiece #{i + 1}: #{File.basename(output)}"
      processed_count += 1
      
    rescue StandardError => e
      $logger.error "Variation #{i + 1} failed: #{e.message}"
    end
  end
  
  processed_count
end

# Main Workflow
def get_input
  $cli_logger.info "Postpro.rb v16.0.0 Full Analog Science"
  $cli_logger.info "Physics-based film emulation" + (REPLIGEN_PRESENT ? " | Repligen Active" : "")
  
  check_repligen if REPLIGEN_PRESENT
  
  if PROMPT
    workflow = PROMPT.select("Choose workflow:", [
      "Masterpiece Presets (Recommended)",
      "Random Effects (Experimental)", 
      "Custom JSON Recipe"
    ])
    
    patterns = PROMPT.ask("File patterns:", default: "**/*.{jpg,jpeg,png,webp}").strip.split(",").map(&:strip)
    variations = PROMPT.ask("Variations per image:", convert: :int, default: CONFIG["variations"] || 2) { |q| q.in("1-5") }
    
    case workflow
    when "Masterpiece Presets (Recommended)"
      preset_name = PROMPT.select("Choose preset:", PRESETS.keys)
      [patterns, variations, { type: :preset, preset: preset_name }]
      
    when "Random Effects (Experimental)"
      mode = PROMPT.select("Mode:", ["Professional", "Experimental"])
      fx_count = PROMPT.ask("Effects per variation:", convert: :int, default: 4) { |q| q.in("2-8") }
      [patterns, variations, { type: :random, mode: mode.downcase, fx: fx_count }]
      
    when "Custom JSON Recipe"
      file = PROMPT.ask("Recipe file path:").strip
      recipe_data = File.exist?(file) ? JSON.parse(File.read(file)) : {}
      [patterns, variations, { type: :recipe, recipe: recipe_data }]
    end
  else
    # Fallback mode without tty-prompt
    patterns = ["**/*.{jpg,jpeg,png,webp}"]
    variations = CONFIG["variations"] || 2
    preset_name = CONFIG["default_preset"] || "portrait"
    [patterns, variations, { type: :preset, preset: preset_name }]
  end
end

def auto_mode
  PostproBootstrap.dmesg "auto mode enabled"
  patterns = ["**/*.{jpg,jpeg,png,webp}"]
  variations = CONFIG["variations"] || 2
  preset_name = CONFIG["default_preset"] || "portrait"
  
  [patterns, variations, { type: :preset, preset: preset_name }]
end

def argv_flag(flag)
  idx = ARGV.index(flag)
  idx && ARGV[idx + 1]
end

# One-shot mode for programmatic use:
#   ruby postpro.rb --input in.jpg --output out.jpg --preset portrait
def one_shot_mode?
  argv_flag("--input") && argv_flag("--output") && argv_flag("--preset")
end

def introspect_mode?
  (ARGV & %w[--list-presets --list-stocks --list-lenses --describe-preset --css-filter --export-lut]).any?
end

def run_introspect
  if ARGV.include?("--list-presets")
    puts list_presets
  elsif ARGV.include?("--list-stocks")
    puts list_stocks
  elsif ARGV.include?("--list-lenses")
    puts list_lenses
  elsif (name = argv_flag("--describe-preset"))
    puts describe_preset(name)
  elsif (name = argv_flag("--css-filter"))
    puts css_filter(name.to_sym)
  elsif (name = argv_flag("--export-lut"))
    out  = argv_flag("--output") || "#{name}.cube"
    size = (argv_flag("--size") || "17").to_i
    export_lut(name.to_sym, out, size)
  end
end

def run_one_shot
  input_path  = argv_flag("--input")
  output_path = argv_flag("--output")
  preset_name = argv_flag("--preset").to_sym

  unless File.exist?(input_path)
    $cli_logger.error "Input not found: #{input_path}"
    exit 1
  end
  unless PRESETS.key?(preset_name)
    $cli_logger.error "Unknown preset: #{preset_name}. Valid: #{PRESETS.keys.join(", ")}"
    exit 1
  end

  image = load_image(input_path)
  unless image
    $cli_logger.error "Failed to load: #{input_path}"
    exit 1
  end

  processed = preset(image, preset_name)
  processed  = rgb_bands(processed)
  quality    = CONFIG["jpeg_quality"] || 95
  processed.write_to_file(output_path, Q: quality)
  $cli_logger.info "ok preset=#{preset_name} out=#{output_path}"
end

def auto_launch
  return run_introspect if introspect_mode?
  return run_one_shot if one_shot_mode?
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
  
  files = patterns.flat_map { |pattern| Dir.glob(pattern) }
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
              else
                0
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

auto_launch if __FILE__ == $0
