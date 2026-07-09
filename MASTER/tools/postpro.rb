#!/usr/bin/env ruby
# frozen_string_literal: true

# Postpro.rb - Professional Cinematic Post-Processing
# Version: 20.0.0 - Photo quality research: adaptive contrast, filmic shoulder/toe,
#   clarity (local contrast), edge-aware NR, selective sharpening; quality_uplift preset

require "logger"
require "json"
require "time"
require "fileutils"

BOOT_TIME = Time.now.freeze

module PostproBootstrap
  def self.dmesg(msg)
    elapsed = defined?(BOOT_TIME) ? " +%.3fs" % (Time.now - BOOT_TIME) : ""
    tag = if msg.start_with?("ERROR", "error")
            "fix:"
          elsif msg.start_with?("WARN", "warn")
            "warn:"
          else
            "ok:"
          end
    text = msg.sub(/\A(?:OK|WARN|ERROR|ok|warn|error)\s+/i, "")
    $stdout.puts "postpro#{elapsed}: #{tag} #{text}"
    $stdout.flush
  end

  def self.startup_banner
    dmesg "ruby#{RUBY_VERSION} os=#{RbConfig::CONFIG["host_os"]} pid=#{Process.pid}"
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
    rescue StandardError => e
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
    rescue StandardError => e
      dmesg "WARN tty-prompt unavailable: #{e.message}"
      false
    end
  end

  def self.probe_and_install_libvips
    dmesg "probing libvips installation..."

    if system("pkg-config", "--exists", "vips", out: File::NULL, err: File::NULL)
      dmesg "OK libvips already installed"
      return true
    end

    # Detect package manager and attempt install
    os = RbConfig::CONFIG["host_os"]
    case os
    when /darwin/
      if system("which", "brew", out: File::NULL, err: File::NULL)
        dmesg "attempting: brew install vips"
        system("brew", "install", "vips")
      else
        dmesg "ERROR homebrew not found, install manually: brew install vips"
      end
    when /linux/
      if system("which", "apt", out: File::NULL, err: File::NULL)
        dmesg "attempting: apt install libvips-dev"
        system("apt", "update") && system("apt", "install", "-y", "libvips-dev")
      elsif system("which", "dnf", out: File::NULL, err: File::NULL)
        dmesg "attempting: dnf install vips-devel"
        system("dnf", "install", "-y", "vips-devel")
      elsif system("which", "yum", out: File::NULL, err: File::NULL)
        dmesg "attempting: yum install vips-devel"
        system("yum", "install", "-y", "vips-devel")
      elsif system("which", "apk", out: File::NULL, err: File::NULL)
        dmesg "attempting: apk add vips-dev"
        system("apk", "add", "vips-dev")
      elsif system("which", "pacman", out: File::NULL, err: File::NULL)
        dmesg "attempting: pacman -S libvips"
        system("pacman", "-S", "--noconfirm", "libvips")
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
    if system("pkg-config", "--exists", "vips", out: File::NULL, err: File::NULL)
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
      rescue StandardError => e
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
    rescue StandardError => e
      dmesg "WARN failed to parse master.json: #{e.message}"
      {}
    end
  end

  def self.run
    startup_banner
    gems = ensure_gems

    unless gems[:vips]
      dmesg "FATAL libvips unavailable; macOS: brew install vips; Ubuntu: apt install libvips-dev; OpenBSD: doas pkg_add vips"
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

BOOTSTRAP = PostproBootstrap.run
$logger = Logger.new("postpro.log", "daily", level: Logger::DEBUG)
$cli_logger = Object.new.tap do |obj|
  def obj.info(msg) = PostproBootstrap.dmesg(msg)
  def obj.error(msg) = PostproBootstrap.dmesg("error #{msg}")
end

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
  kodak_portra: { grain: 15,
                  sublayers: [{ sensitivity_shift: 0.0, grain_scale: 1.4, weight: 0.45 },
                               { sensitivity_shift: -0.5, grain_scale: 1.0, weight: 0.55 }],
                  matrix: [1.05, -0.02, -0.03, 0.02, 0.98, 0.00, 0.01, -0.05, 1.04],
                  hd: { r: [0.06, 0.93, 0.18, 1.10], g: [0.05, 0.94, 0.18, 1.10], b: [0.04, 0.92, 0.20, 1.05] } },
  kodak_vision3: { grain: 20,
                   sublayers: [{ sensitivity_shift: 0.3, grain_scale: 1.5, weight: 0.40 },
                                { sensitivity_shift: 0.0, grain_scale: 1.1, weight: 0.35 },
                                { sensitivity_shift: -0.6, grain_scale: 0.85, weight: 0.25 }],
                   matrix: [1.08, -0.05, -0.03, 0.03, 0.95, 0.02, 0.02, -0.08, 1.06],
                   hd: { r: [0.07, 0.95, 0.17, 1.15], g: [0.06, 0.95, 0.18, 1.20], b: [0.08, 0.90, 0.20, 1.10] } },
  kodak_vision3_50d: { grain: 8, matrix: [1.06, -0.03, -0.02, 0.02, 0.96, 0.01, 0.01, -0.05, 1.04],
                       hd: { r: [0.05, 0.95, 0.18, 1.08], g: [0.04, 0.95, 0.18, 1.12], b: [0.03, 0.93, 0.20, 1.05] } },
  kodak_vision3_500t: { grain: 20, matrix: [1.10, -0.06, -0.04, 0.04, 0.94, 0.03, 0.04, -0.10, 1.09],
                        hd: { r: [0.08, 0.95, 0.17, 1.18], g: [0.06, 0.95, 0.18, 1.22], b: [0.10, 0.90, 0.20, 1.15] },
                        focal_plane_offset: 1.1 },
  cinestill_800t: { grain: 22,
                    sublayers: [{ sensitivity_shift: 0.4, grain_scale: 1.6, weight: 0.35 },
                                 { sensitivity_shift: 0.0, grain_scale: 1.2, weight: 0.40 },
                                 { sensitivity_shift: -0.5, grain_scale: 0.9, weight: 0.25 }],
                    matrix: [1.12, -0.07, -0.05, 0.04, 0.93, 0.03, 0.05, -0.12, 1.10],
                    hd: { r: [0.09, 0.96, 0.17, 1.20], g: [0.07, 0.95, 0.18, 1.25], b: [0.12, 0.88, 0.20, 1.18] },
                    halation: 0.8, focal_plane_offset: 1.2 },
  ektachrome_100: { grain: 10, matrix: [1.08, -0.04, -0.04, 0.02, 1.02, -0.02, 0.01, -0.08, 1.07],
                    hd: { r: [0.02, 0.97, 0.18, 1.30], g: [0.02, 0.97, 0.18, 1.35], b: [0.03, 0.96, 0.20, 1.25] } },
  fuji_velvia: { grain: 8, matrix: [1.12, -0.08, -0.04, 0.05, 1.05, -0.02, 0.01, -0.12, 1.11],
                 hd: { r: [0.02, 0.97, 0.18, 1.45], g: [0.02, 0.98, 0.18, 1.50], b: [0.03, 0.95, 0.20, 1.40] } },
  tri_x: { grain: 25, matrix: [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
            hd: { r: [0.05, 0.95, 0.18, 1.30], g: [0.05, 0.95, 0.18, 1.30], b: [0.05, 0.95, 0.18, 1.30] } },
  # Kodachrome: steep gamma, no in-film couplers, external development process.
  # Punchy reds, heavy yellow separation, minimal shadow fog.
  kodachrome: { grain: 12, matrix: [1.15, -0.10, -0.05, 0.03, 1.00, -0.03, 0.00, -0.10, 1.10],
                hd: { r: [0.02, 0.97, 0.18, 1.42], g: [0.03, 0.97, 0.18, 1.36], b: [0.04, 0.95, 0.20, 1.20] } },
}.freeze

# Lens character: data-driven table drives vintage_lens().
# vignette/glow/micro_contrast/chroma are intensity multipliers [0,1].
LENSES = {
  zeiss: { micro_contrast: 0.40, flare: 0.08 },
  leica: { micro_contrast: 0.45, glow: 0.25 },
  helios: { micro_contrast: 0.30, chroma: 0.05 },
  cooke: { micro_contrast: 0.20, warmth: 0.10 },
  anamorphic: { micro_contrast: 0.25, chroma: 0.08, flare: 0.50 },
}.freeze

# Per-stock R/G/B channel amplitude ratios for grain — mirrors the three
# dye-layer sensitivities. Red layer is reference (1.00), green and blue
# attenuated to match the stock's measured dye-cloud statistics.
GRAIN_CHAN_SCALE = {
  kodak_portra: [1.00, 0.85, 0.70],
  kodak_vision3: [1.00, 0.90, 0.80],
  kodak_vision3_50d: [1.00, 0.88, 0.75],
  kodak_vision3_500t: [1.00, 0.88, 0.72],
  cinestill_800t: [1.05, 0.88, 0.75],
  ektachrome_100: [0.95, 0.95, 1.05],
  fuji_velvia: [1.00, 1.10, 0.90],
  tri_x: [1.00, 1.00, 1.00],
  kodachrome: [1.00, 0.92, 0.82],
}.freeze

# Per-channel spatial frequency ratios for grain — red layer (σ×1.00) is coarsest,
# blue (σ×0.72) finest, matching measured dye-cloud PSF widths per layer depth.
GRAIN_CHANNEL_SPATIAL = [1.00, 0.85, 0.72].freeze

# Lognormal grain amplitude distribution. Silver halide crystals cluster in groups;
# the cluster field drives amplitude modulation on top of the base Perlin layer.
GRAIN_LOGNORM_SIGMA = 0.55
GRAIN_LOGNORM_MEAN = Math.exp(GRAIN_LOGNORM_SIGMA**2 / 2.0)

# Print film stocks: H&D per channel, warmth triplet, grain amplitude.
# Applied as a final projection stage emulating contact or optical printing.
PRINT_STOCKS = {
  kodak_2383: {
    hd: { r: [0.03, 0.98, 0.18, 1.38], g: [0.02, 0.97, 0.18, 1.34], b: [0.04, 0.96, 0.18, 1.28] },
    grain: 3, warmth: 0.055, cool_shadow: 0.042
  },
  kodak_2302: {
    hd: { r: [0.05, 0.95, 0.18, 1.50], g: [0.05, 0.95, 0.18, 1.50], b: [0.05, 0.95, 0.18, 1.50] },
    grain: 5
  },
}.freeze

# Per-stock reciprocity failure color shifts. Blue layer lags most under long
# exposures; green-magenta crossover happens first. Offsets in scRGB units per
# decade of EV (ev = log2(secs) / 10).
RECIPROCITY_SHIFT = {
  cinestill_800t: { r: 0.02, g: -0.04, b: 0.14 },
  kodak_vision3_500t: { r: 0.01, g: -0.03, b: 0.11 },
  kodak_vision3: { r: 0.01, g: -0.03, b: 0.10 },
  tri_x: { r: 0.02, g: -0.05, b: 0.16 },
  kodak_portra: { r: 0.01, g: -0.02, b: 0.09 },
}.freeze

# Per-stock push response ratios. Blue dye layer develops faster under push;
# green is the reference (1.00). Ratios are per-stop multipliers relative to
# the nominal exposure-doubling factor.
PUSH_RESPONSE = {
  kodak_vision3_500t: { g: 1.00, b: 0.92 },
  kodak_vision3: { g: 1.00, b: 0.93 },
  cinestill_800t: { g: 0.97, b: 0.89 },
  kodak_portra: { g: 1.00, b: 0.94 },
  tri_x: { g: 1.00, b: 0.97 },
  fuji_velvia: { g: 1.00, b: 0.88 },
  ektachrome_100: { g: 0.99, b: 0.91 },
  kodachrome: { g: 0.98, b: 0.90 },
}.freeze

# Stocks with integral colored couplers (C-41 process) — get orange mask treatment.
C41_STOCKS = %i[kodak_portra kodak_vision3 kodak_vision3_50d kodak_vision3_500t cinestill_800t].freeze

# Per-stock film base density tints. Each emulsion has a characteristic base fog
# color: C-41 negatives are orange-masked; reversal stocks are nearly neutral;
# B&W silver prints are pure white. Applied at low opacity over the whole frame
# so dark areas pick up the tint more than highlights (density-sensitive).
FILM_BASE = {
  kodak_portra: [255, 245, 228],
  kodak_vision3: [255, 246, 226],
  kodak_vision3_50d: [255, 248, 232],
  kodak_vision3_500t: [255, 247, 225],
  cinestill_800t: [255, 243, 218],
  ektachrome_100: [248, 250, 255],
  fuji_velvia: [250, 251, 255],
  tri_x: [255, 255, 255],
  kodachrome: [255, 246, 222],
}.freeze

# Physics-ordered 6-8 step chains: optical_blur → exposure/temp → film_curve
# → chemistry → optical_effect → print → grain. One contrast mode and one
# color temperature approach per preset — no stacking.
PRESETS = {
  portrait: { fx: %w[optical_blur film_curve dir_coupler orange_mask skin_protect shadow_lift highlight_roll grain],
              stock: :kodak_portra, temp: 5200, intensity: 0.85 },

  indie: { fx: %w[optical_blur film_curve orange_mask shadow_lift split_toning chromatic_aberration grain],
           stock: :kodak_portra, temp: 5400, intensity: 0.85, lens: "helios" },

  polaroid: { fx: %w[optical_blur film_curve faded_print warmth bloom_pro shadow_lift grain],
              stock: :kodak_portra, temp: 5000, intensity: 0.85 },

  landscape: { fx: %w[optical_blur spectral_temp film_curve color_separate halation micro_contrast grain],
               stock: :fuji_velvia, temp: 5800, intensity: 0.90, lens: "zeiss" },

  magic_hour: { fx: %w[optical_blur spectral_temp film_curve halation warmth bloom_pro grain],
                stock: :fuji_velvia, temp: 4800, intensity: 0.90 },

  reversal: { fx: %w[optical_blur film_curve color_separate halation highlight_roll micro_contrast grain],
              stock: :fuji_velvia, temp: 5600, intensity: 0.90 },

  process_e6: { fx: %w[optical_blur push_pull film_curve color_separate halation highlight_roll grain],
                stock: :ektachrome_100, temp: 5600, intensity: 0.90, stops: 2.0 },

  cinematic: { fx: %w[optical_blur spectral_temp tonemap film_curve orange_mask halation shadow_lift print_film grain],
               stock: :kodak_vision3_500t, temp: 4500, intensity: 0.90, print_stock: :kodak_2383 },

  blockbuster: { fx: %w[optical_blur tonemap bleach_bypass film_curve orange_mask teal_orange halation print_film grain],
                 stock: :kodak_vision3, temp: 4800, intensity: 0.90, print_stock: :kodak_2383 },

  golden_age: { fx: %w[optical_blur film_curve orange_mask technicolor warmth dir_coupler bloom_pro grain],
                stock: :kodak_vision3_50d, temp: 5200, intensity: 0.85, lens: "cooke" },

  bleached: { fx: %w[optical_blur tonemap bleach_bypass film_curve split_grade highlight_roll grain],
              stock: :kodak_vision3, temp: 4800, intensity: 0.90 },

  neon_night: { fx: %w[optical_blur push_pull reciprocity_failure film_curve orange_mask halation bloom_pro grain],
                stock: :cinestill_800t, temp: 3200, intensity: 0.90,
                stops: 0.5, exposure_secs: 30.0 },

  tokyo_night: { fx: %w[optical_blur push_pull reciprocity_failure film_curve orange_mask halation teal_orange grain],
                 stock: :cinestill_800t, temp: 3000, intensity: 0.90,
                 stops: 1.0, exposure_secs: 45.0 },

  tungsten: { fx: %w[optical_blur spectral_temp film_curve orange_mask halation push_pull shadow_lift grain],
              stock: :kodak_vision3_500t, temp: 3200, intensity: 0.90,
              stops: 0.3, exposure_secs: 8.0 },

  street: { fx: %w[optical_blur tonemap bleach_bypass film_curve adjacency_effects shadow_lift micro_contrast grain],
            stock: :tri_x, temp: 5600, intensity: 0.90, stops: 1.0 },

  war_doc: { fx: %w[optical_blur tonemap push_pull film_curve bleach_bypass green_push grain],
             stock: :tri_x, temp: 5600, intensity: 0.90, stops: 2.0 },

  silver_gelatin: { fx: %w[optical_blur film_curve push_pull adjacency_effects shadow_lift highlight_roll grain],
                    stock: :tri_x, temp: 5600, intensity: 0.85, stops: 0.5 },

  lith: { fx: %w[optical_blur film_curve push_pull lith_print split_toning grain],
          stock: :tri_x, temp: 5600, intensity: 0.90, stops: 1.5 },

  noir: { fx: %w[optical_blur tonemap film_curve bleach_bypass desaturate shadow_lift grain],
          stock: :tri_x, temp: 5600, intensity: 0.90, stops: 2.0 },

  dream: { fx: %w[optical_blur film_curve halation bloom_pro desaturate split_toning grain],
           stock: :ektachrome_100, temp: 5800, intensity: 0.85, lens: "leica" },

  dreamscape: { fx: %w[optical_blur film_curve halation bloom_pro split_toning grain],
                stock: :ektachrome_100, temp: 5800, intensity: 0.85 },

  lo_fi: { fx: %w[optical_blur film_curve push_pull faded_print warmth chromatic_aberration grain],
           stock: :kodak_portra, temp: 4800, intensity: 0.85, lens: "helios" },

  horror: { fx: %w[optical_blur tonemap film_curve bleach_bypass green_push desaturate grain],
            stock: :tri_x, temp: 5600, intensity: 0.90 },

  arctic: { fx: %w[optical_blur tonemap film_curve desaturate bleach_bypass highlight_roll grain],
            stock: :tri_x, temp: 6500, intensity: 0.90 },

  kodachrome_look: { fx: %w[optical_blur tonemap film_curve kodachrome_sim dir_coupler halation grain],
                     stock: :kodachrome, temp: 5600, intensity: 0.90 },

  technicolor_3strip: { fx: %w[optical_blur spectral_temp film_curve technicolor dir_coupler bloom_pro grain],
                        stock: :kodachrome, temp: 5500, intensity: 0.90 },

  cross_process: { fx: %w[optical_blur push_pull film_curve color_separate teal_orange split_toning grain],
                   stock: :fuji_velvia, temp: 5500, intensity: 0.90, stops: 0.5 },

  vintage_chrome: { fx: %w[optical_blur film_curve dir_coupler spectral_temp color_separate split_toning grain],
                    stock: :ektachrome_100, temp: 5200, intensity: 0.85 },

  infrared_look: { fx: %w[optical_blur push_pull infrared film_curve bleach_bypass highlight_roll grain],
                   stock: :tri_x, temp: 5600, intensity: 0.90, stops: 0.5 },

  cyanotype_look: { fx: %w[optical_blur film_curve desaturate cyanotype shadow_lift grain],
                    stock: :tri_x, temp: 6000, intensity: 0.85 },

  analog_scan: { fx: %w[optical_blur film_curve grain scan_noise dust_and_hair newton_rings],
                 stock: :kodak_portra, temp: 5200, intensity: 0.80 },

  aged_chrome: { fx: %w[optical_blur film_curve dye_fade selenium_tone faded_print grain],
                 stock: :ektachrome_100, temp: 5600, intensity: 0.85, age: 0.60 },

  anamorphic: { fx: %w[optical_blur longitudinal_ca spectral_temp tonemap film_curve anamorphic_flare halation grain],
                stock: :kodak_vision3_500t, temp: 4200, intensity: 0.90 },

  contact_print: { fx: %w[optical_blur adjacency_effects film_curve darkroom_print shadow_lift grain],
                   stock: :tri_x, temp: 5600, intensity: 0.85 },

  aged_kodachrome: { fx: %w[optical_blur film_curve dye_fade kodachrome_sim dir_coupler grain],
                     stock: :kodachrome, temp: 5600, intensity: 0.88, age: 0.50 },

  wide_angle: { fx: %w[optical_blur lens_distortion spectral_temp film_curve halation grain],
                stock: :fuji_velvia, temp: 5800, intensity: 0.90, k1: -0.14 },

  cinema_scan: { fx: %w[optical_blur longitudinal_ca tonemap film_curve orange_mask halation bokeh_rendering print_film grain],
                 stock: :kodak_vision3, temp: 4600, intensity: 0.90, print_stock: :kodak_2383 },

  diffraction: { fx: %w[optical_blur diffraction_blur film_curve micro_contrast grain],
                 stock: :fuji_velvia, temp: 5600, intensity: 0.85, f_number: 22.0 },

  nitrate: { fx: %w[optical_blur film_curve dye_fade faded_print adjacency_effects grain scan_noise],
             stock: :kodachrome, temp: 4800, intensity: 0.85, age: 0.80 },

  fiber_print: { fx: %w[optical_blur adjacency_effects darkroom_print paper_texture dodgeburn_artifacts grain],
                 stock: :tri_x, temp: 5600, intensity: 0.85 },

  expired: { fx: %w[optical_blur film_curve expired_film gate_weave],
             stock: :kodak_portra, temp: 5200, intensity: 0.90, age: 0.65 },

  reticulated: { fx: %w[optical_blur film_curve reticulation fixing_bath_fog grain],
                 stock: :tri_x, temp: 5600, intensity: 0.80 },

  ortho: { fx: %w[optical_blur ortho_film film_curve adjacency_effects grain],
           stock: :tri_x, temp: 5600, intensity: 0.85 },

  tilt_shift_look: { fx: %w[optical_blur film_curve tilt_shift halation grain],
                     stock: :kodak_portra, temp: 5200, intensity: 0.80 },

  haunted: { fx: %w[optical_blur expired_film reticulation fixing_bath_fog lens_ghosting gate_weave grain],
             stock: :kodachrome, temp: 4600, intensity: 0.90, age: 0.80 },

  quality_uplift: { fx: %w[adaptive_contrast film_shoulder clarity edge_aware_nr selective_sharpen film_curve grain],
                    stock: :kodak_portra, temp: 5600, intensity: 0.75 },
}.freeze

def halation_tint_for(stock)
  case stock
  when :kodak_vision3, :kodak_vision3_500t then HALATION_TINT_VISION3
  when :cinestill_800t then HALATION_TINT_VISION3
  when :kodak_portra, :kodak_vision3_50d then HALATION_TINT_PORTRA
  when :tri_x then HALATION_TINT_TRI_X
  when :ektachrome_100 then HALATION_TINT_PORTRA
  when :kodachrome then HALATION_TINT_PORTRA
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
  if format == 'uchar'
    f = image.cast('float')
    f = (f > 0).ifthenelse(f, 0)
    f = (f < 255).ifthenelse(f, 255)
    f.cast('uchar')
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
  rescue StandardError => e
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
  gray = image.colourspace('b-w').cast('float') / 255.0
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

GRAIN_CELL_BASE = 4.0  # base Perlin cell size in px — larger = coarser grain
GRAIN_AMP_SCALE = 400.0 # amplitude denominator, tuned for scRGB [0,1] space
# 3-tap horizontal convolution kernel for grain anisotropy (film transport direction).
# Film grain is slightly elongated along the direction of film travel — this
# kernel applies a subtle horizontal elongation without visible smearing.
GRAIN_ANISO_KERNEL = Vips::Image.new_from_array([[0.18, 0.64, 0.18]]).freeze

# Perlin + fractsurf grain with horizontal anisotropy and shadow-weighted envelope.
# Perlin (70%) gives crystalline cluster structure; fractsurf (30%) adds multi-scale
# fBm detail. The midtone envelope 4L^0.8(1-L) peaks slightly toward the shadow
# side of mid-gray, matching real halide clump statistics. A mild horizontal
# directional kernel elongates grain clusters along the film-transport axis.
def grain(image, iso = 400, stock = :kodak_portra, intensity = 0.4)
  data      = STOCKS[stock] || STOCKS[:kodak_portra]
  scales    = GRAIN_CHAN_SCALE[stock] || [1.0, 1.0, 1.0]
  sublayers = data[:sublayers] || [{ sensitivity_shift: 0.0, grain_scale: 1.0, weight: 1.0 }]
  iso_factor     = Math.sqrt(iso / 100.0)
  base_amplitude = data[:grain] * iso_factor * intensity / GRAIN_AMP_SCALE

  linear = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  luma = r * 0.2126 + g * 0.7152 + b * 0.0722
  # Shadow-biased envelope: luma^0.8 shifts peak toward shadows vs symmetric 4L(1-L)
  envelope = (luma.linear([1], [0]).pow(0.80) * luma.linear([-1], [1])).linear([4], [0])

  # Lognormal cluster field: silver halide crystals cluster in groups whose
  # amplitude follows a lognormal distribution. exp(gaussian_noise) produces
  # the characteristic long-tail clumping seen in real emulsion grain scans.
  cluster_sigma = [GRAIN_CELL_BASE * 2.5, 1.0].max
  cluster_field = Vips::Image.gaussnoise(image.width, image.height, sigma: GRAIN_LOGNORM_SIGMA, mean: 0.0)
                             .gaussblur(cluster_sigma).exp
                             .linear([1.0 / GRAIN_LOGNORM_MEAN], [0])

  bands = scales.each_with_index.map do |chan_scale, ci|
    sp = [GRAIN_CELL_BASE * GRAIN_CHANNEL_SPATIAL[ci] * 0.7, 0.3].max
    sublayers.map do |sl|
      cell      = [GRAIN_CELL_BASE * (2.0**sl[:sensitivity_shift]) * sl[:grain_scale], 1.5].max.round
      amplitude = base_amplitude * chan_scale * sl[:grain_scale] * sl[:weight]
      perlin    = Vips::Image.perlin(image.width, image.height, cell_size: cell)
      fractal   = Vips::Image.fractsurf(image.width, image.height, 2.5)
      raw       = (perlin * 0.70 + fractal * 0.30)
      # Anisotropy: slight horizontal elongation along film-transport axis
      aniso     = raw.conv(GRAIN_ANISO_KERNEL, precision: :float)
      clustered = (raw * 0.55 + aniso * 0.45) * cluster_field
      clustered.gaussblur(sp).linear([amplitude], [0.0])
    end.reduce(:+)
  end

  noise = Vips::Image.bandjoin(bands)
  safe_cast((linear + noise * envelope).colourspace("srgb"))
rescue StandardError => e
  $logger.error "grain failed: #{e.message}"; image
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

# OLPF (optical low-pass filter) simulation. Two-gaussian PSF: sharp core (84%)
# + wide skirt (16%) matches the Lorentzian wings measured on real lens MTFs.
def optical_blur(image, sigma = 0.6)
  core = image.gaussblur([sigma * 0.6, 0.3].max)
  skirt = image.gaussblur([sigma * 2.8, 0.5].max)
  safe_cast(core.cast("float") * 0.84 + skirt.cast("float") * 0.16)
rescue StandardError => e
  $logger.error "optical_blur: #{e.message}"; image
end

# Emulsion depth defocus: each dye layer sits at a different depth in the
# multilayer emulsion stack. Blue layer (top, nearest lens) is sharpest;
# red (deepest) sees the most focus spread from incident + substrate-reflected
# light. focal_plane_offset is stock-specific — cinestill_800t (remjet removed)
# has the most scatter; slow daylight stocks have little.
def emulsion_defocus(image, stock = :kodak_portra)
  data   = STOCKS[stock] || STOCKS[:kodak_portra]
  offset = data.fetch(:focal_plane_offset, 1.0)
  r, g, b = image.bandsplit
  r2 = offset > 0 ? safe_cast(r.gaussblur(0.6 * offset)) : r
  g2 = offset > 0 ? safe_cast(g.gaussblur(0.3 * offset)) : g
  safe_cast(Vips::Image.bandjoin([r2, g2, b]))
rescue StandardError => e
  $logger.error "emulsion_defocus: #{e.message}"; image
end

# Lateral + longitudinal chromatic aberration. Lateral: R/B registration shift
# at sensor edges. Longitudinal: wavelength-dependent focus depth — blue blurs
# before the focal plane, red sharpest (as in `longitudinal_ca`).
def chromatic_aberration(image, strength = 0.5)
  shift = [(strength * 3.0).round, 1].max
  r, g, b = image.bandsplit
  r2 = r.embed(shift, 0, image.width, image.height)
  b2 = b.embed(-shift, 0, image.width, image.height)
  long_sigma = [strength * 0.9, 0.3].max
  r3 = r2.gaussblur([long_sigma * 0.35, 0.3].max)
  b3 = b2.gaussblur([long_sigma, 0.3].max)
  safe_cast(Vips::Image.bandjoin([r3, g, b3]))
rescue StandardError => e
  $logger.error "chromatic_aberration: #{e.message}"; image
end

# DIR coupler inhibition: development byproducts from one dye layer inhibit
# adjacent layers, slightly desaturating pure hues and sharpening edges.
def dir_coupler(image, strength = 0.15)
  blurred   = image.gaussblur(2.0)
  high_pass = image.cast("float") - blurred.cast("float")
  gray      = image.colourspace("grey16").colourspace("srgb").cast("float")
  img_f     = image.cast("float") / 255.0
  # Lateral inhibition: each dye layer's development byproducts diffuse σ≈0.8px
  # and suppress adjacent layers — desaturates pure hues, sharpens colour edges.
  r_d, g_d, b_d = img_f.bandsplit.map { |ch| ch.gaussblur(0.8) }
  inhibition = Vips::Image.bandjoin([
    r_d - g_d * (0.08 * strength) - b_d * (0.04 * strength),
    g_d - r_d * (0.12 * strength) - b_d * (0.07 * strength),
    b_d - r_d * (0.06 * strength) - g_d * (0.10 * strength)
  ])
  inhibited = clamp01(inhibition) * 255.0
  desatd = inhibited * (1.0 - strength * 0.3) + gray * (strength * 0.3)
  safe_cast((desatd + high_pass * (strength * 0.5)).cast("uchar"))
rescue StandardError => e
  $logger.error "dir_coupler: #{e.message}"; image
end

# Bleach bypass: skip bleach step, retain silver alongside dye. Screen-blend of
# a B&W layer over the colour image. Shadow neutral lift models the base silver
# density — retained metallic silver adds a grey floor to the darkest zones.
def bleach_bypass(image, intensity = 0.5)
  img_f  = image.cast("float") / 255.0
  gray_f = image.colourspace("grey16").colourspace("srgb").cast("float") / 255.0
  screen = (img_f.linear(-1, 1) * gray_f.linear(-1, 1)).linear(-1, 1)
  shadow_base = gray_f.linear(-1, 1) ** 2.0 * intensity * 0.18
  base_rgb = shadow_base.bandjoin([shadow_base, shadow_base])
  result = img_f * (1.0 - intensity) + screen * intensity + base_rgb * intensity
  safe_cast(clamp01(result) * 255.0)
rescue StandardError => e
  $logger.error "bleach_bypass: #{e.message}"; image
end

# Push/pull processing. Per-stock per-channel response: blue dye layer develops
# faster under push (reaches Dmax sooner), so PUSH_RESPONSE attenuates it to
# match measured sensitometry curves for each stock.
def push_pull(image, stops = 1.0, stock = :kodak_portra)
  resp   = PUSH_RESPONSE[stock] || { g: 1.00, b: 0.94 }
  linear = image.colourspace("scrgb")
  factor = 2.0**stops
  r, g, b = linear.bandsplit
  adj = Vips::Image.bandjoin([
    clamp01(r * factor),
    clamp01(g * factor * resp[:g]),
    clamp01(b * factor * resp[:b])
  ])
  if stops > 0
    shadow_add = adj.linear(-1, 1) ** 2.0 * (stops * 0.04)
    adj = clamp01(adj + shadow_add)
  end
  safe_cast(adj.colourspace("srgb"))
rescue StandardError => e
  $logger.error "push_pull: #{e.message}"; image
end

# Split toning: shadow and highlight color casts weighted by luminance.
# shadow_rgb / hi_rgb are [R,G,B] triplets in 0-255.
def split_toning(image, shadow_rgb = [45, 35, 60], hi_rgb = [255, 240, 210], intensity = 0.30)
  luma  = image.colourspace("b-w").cast("float") / 255.0
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
def split_grade(image, shadow_rgb = [30, 40, 60], mid_rgb = [255, 255, 248], hi_rgb = [255, 245, 220], intensity: 0.25)
  luma  = image.colourspace("b-w").cast("float") / 255.0
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
# channel lags most. Per-stock shifts from RECIPROCITY_SHIFT calibrate the
# green-magenta crossover and blue lag to measured sensitometry data.
def reciprocity_failure(image, exposure_seconds = 10.0, stock = :cinestill_800t)
  ev   = Math.log2([exposure_seconds, 1.0].max) / 10.0
  cs   = RECIPROCITY_SHIFT[stock] || RECIPROCITY_SHIFT[:cinestill_800t]
  linear = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  luma    = r * 0.2126 + g * 0.7152 + b * 0.0722
  dark_w  = luma.linear(-1, 1)
  result  = Vips::Image.bandjoin([
    r + dark_w * ev * 0.03 + (ev * cs[:r]),
    g + dark_w * ev * 0.02 + (ev * cs[:g]),
    b + (ev * 0.15) + dark_w * ev * 0.05 + (ev * cs[:b])
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
  luma   = image.colourspace("b-w").cast("float") / 255.0
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
  gray = image.colourspace("b-w").cast("float") / 255.0
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

# Aged photographic print with differential dye fading. Cyan is least stable —
# absorbs visible light, degrades fastest → warm shift. Yellow moderate.
# Magenta most stable. Contrast compression + shadow floor models paper base fog.
def faded_print(image, age = 0.5)
  img_f = image.cast("float") / 255.0
  r, g, b = img_f.bandsplit
  cyan_fade   = age * 0.65
  yellow_fade = age * 0.28
  r_faded = clamp01(r + cyan_fade * 0.22 + age * 0.06)
  g_faded = clamp01(g + age * 0.04)
  b_faded = clamp01(b * (1.0 - yellow_fade * 0.20) + yellow_fade * 0.05)
  comp = 1.0 - age * 0.28
  r_out = r_faded * comp + age * 0.07
  g_out = g_faded * comp + age * 0.045
  b_out = b_faded * comp + age * 0.02
  result = Vips::Image.bandjoin([r_out, g_out, b_out])
  result = result.gaussblur(age * 0.9) if age > 0.3
  safe_cast(clamp01(result) * 255.0)
rescue StandardError => e
  $logger.error "faded_print: #{e.message}"; image
end

# Adjacency / Eberhard effect: developer exhaustion at bright edges creates a
# dark inhibition band on the bright side and a slight bright band on the dark side.
# Physically: development byproducts diffuse outward and locally suppress nearby
# grains. Subtract a fraction of the high-pass edge signal → local undershoot.
def adjacency_effects(image, intensity = 0.25)
  blurred = image.gaussblur(1.8)
  edge    = image.cast("float") - blurred.cast("float")
  result  = clamp01((image.cast("float") - edge * (intensity * 0.45)) / 255.0) * 255.0
  safe_cast(result)
rescue StandardError => e
  $logger.error "adjacency_effects: #{e.message}"; image
end

# Longitudinal (axial) chromatic aberration: wavelengths focus at different depths.
# Blue focuses short of the plane; green slightly soft; red sharpest at the focal plane.
def longitudinal_ca(image, strength = 0.50)
  r, g, b = image.bandsplit
  g2 = g.gaussblur([0.4 * strength, 0.3].max)
  b2 = b.gaussblur([0.9 * strength, 0.3].max)
  safe_cast(Vips::Image.bandjoin([r, g2, b2]))
rescue StandardError => e
  $logger.error "longitudinal_ca: #{e.message}"; image
end

# Radial lens distortion via mapim. k1 < 0 = barrel (wide-angle); k1 > 0 = pincushion.
# First-order Brown-Conrady model — single coefficient, adequate for cinematic emulation.
def lens_distortion(image, k1 = -0.12)
  w, h   = image.width, image.height
  cx, cy = w / 2.0, h / 2.0
  idx    = Vips::Image.xyz(w, h)
  xn     = (idx.extract_band(0).cast("float") - cx) / cx
  yn     = (idx.extract_band(1).cast("float") - cy) / cy
  r2     = xn * xn + yn * yn
  factor = r2.linear([k1], [1.0])
  xs     = (xn * factor * cx + cx).cast("float")
  ys     = (yn * factor * cy + cy).cast("float")
  image.mapim(Vips::Image.bandjoin([xs, ys]))
rescue StandardError => e
  $logger.error "lens_distortion: #{e.message}"; image
end

# Bokeh highlight ring structure: out-of-focus highlights from lens element edges
# produce an onion-ring artifact. Detected by finding the bright-disk edge and
# adding a warm ring there. Red dominant — lens coatings transmit red more at edges.
def bokeh_rendering(image, intensity = 0.35)
  linear  = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  luma    = r * 0.2126 + g * 0.7152 + b * 0.0722
  bright  = (luma > 0.65).ifthenelse(luma - 0.65, 0)
  ring    = (bright.gaussblur(4.0) - bright.gaussblur(2.0)).linear([1], [0])
  ring    = (ring > 0).ifthenelse(ring, 0).linear([intensity * 2.5], [0])
  result  = Vips::Image.bandjoin([r + ring * 0.90, g + ring * 0.55, b + ring * 0.15])
  safe_cast(clamp01(result).colourspace("srgb"))
rescue StandardError => e
  $logger.error "bokeh_rendering: #{e.message}"; image
end

# Anamorphic lens flare: horizontal blue-cyan streak through brightest highlights.
# Real anamorphic streaks are produced by cylindrical front element edge diffraction.
# Approximated with a wide 1-D horizontal convolution over the highlight mask.
def anamorphic_flare(image, intensity = 0.50)
  w       = image.width
  linear  = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  luma    = r * 0.2126 + g * 0.7152 + b * 0.0722
  bright  = (luma > 0.78).ifthenelse(luma - 0.78, 0)
  kw      = [w / 10, 31].min
  kw      = kw.even? ? kw + 1 : kw
  kernel  = Vips::Image.new_from_array([Array.new(kw, 1.0 / kw)])
  streak  = bright.conv(kernel, precision: :float)
  streakc = Vips::Image.bandjoin([streak * 0.10, streak * 0.45, streak * 1.00]) * (intensity * 0.55)
  safe_cast(clamp01(linear + streakc).colourspace("srgb"))
rescue StandardError => e
  $logger.error "anamorphic_flare: #{e.message}"; image
end

# Diffraction softening at small apertures. The Airy disc diameter grows with f-number;
# at f/16+ the disc exceeds the Nyquist limit and detail visibly softens.
def diffraction_blur(image, f_number = 16.0, intensity = 1.0)
  sigma = ([((f_number - 8.0) / 5.0) * intensity, 0.3].max).clamp(0.3, 6.0)
  safe_cast(image.gaussblur(sigma))
rescue StandardError => e
  $logger.error "diffraction_blur: #{e.message}"; image
end

# Flatbed scanner CCD noise floor. Electronic in origin — independent of film grain,
# lower amplitude, no spatial correlation. Adds a second fine incoherent texture.
def scan_noise(image, intensity = 0.40)
  noise = Vips::Image.gaussnoise(image.width, image.height, sigma: 5.0 * intensity, mean: 0.0)
  safe_cast(image.cast("float") + rgb_bands(noise) * 0.06 * intensity)
rescue StandardError => e
  $logger.error "scan_noise: #{e.message}"; image
end

# Newton rings: thin-film interference fringes where film lifts off scanner glass.
# Sinusoidal concentric rings centered near a corner with radial intensity falloff.
def newton_rings(image, intensity = 0.12)
  w, h  = image.width, image.height
  cx    = w * 0.12
  cy    = h * 0.10
  idx   = Vips::Image.xyz(w, h)
  xd    = idx.extract_band(0).cast("float") - cx
  yd    = idx.extract_band(1).cast("float") - cy
  rad   = (xd * xd + yd * yd).pow(0.5)
  rings = rad.linear([Math::PI * 2.0 / 28.0], [0]).math(:sin).linear([0.5], [0.5])
  fade  = clamp01(rad.linear([-1.2 / [w, h].max], [1.2]))
  mod   = (rings - 0.5) * fade * intensity * 0.10
  mod3  = mod.bandjoin([mod, mod])
  safe_cast(clamp01(image.cast("float") / 255.0 + mod3) * 255.0)
rescue StandardError => e
  $logger.error "newton_rings: #{e.message}"; image
end

# Dust specks and hair strands on negative or scanner glass. Procedurally drawn
# at random positions; dark specks more common than bright (dust blocks light).
def dust_and_hair(image, intensity = 0.50)
  w, h    = image.width, image.height
  overlay = Vips::Image.black(w, h, bands: 3).cast("float")
  (intensity * 14).round.times do
    x   = rand(w)
    y   = rand(h)
    val = rand > 0.65 ? [230.0, 228.0, 225.0] : [8.0, 6.0, 5.0]
    overlay = overlay.draw_circle(val, x, y, 1 + rand(2), fill: true)
  end
  (intensity * 2).round.times do
    x1    = rand(w)
    y1    = rand(h)
    angle = rand * Math::PI * 2
    len   = 30 + rand(110)
    x2    = (x1 + len * Math.cos(angle)).to_i.clamp(0, w - 1)
    y2    = (y1 + len * Math.sin(angle)).to_i.clamp(0, h - 1)
    overlay = overlay.draw_line([14.0, 12.0, 10.0], x1, y1, x2, y2)
  end
  blended = image.cast("float") + overlay.gaussblur(0.5) * 0.45
  safe_cast(clamp01(blended / 255.0) * 255.0)
rescue StandardError => e
  $logger.error "dust_and_hair: #{e.message}"; image
end

# Film curl / frame-holder vignette. Steeper radial falloff (power 8) than the
# smooth lens vignette (power 2) — mimics the mechanical shadow of the film gate.
def film_curl_vignette(image, intensity = 0.45)
  w, h = image.width, image.height
  idx  = Vips::Image.xyz(w, h)
  xn   = (idx.extract_band(0).cast("float") - w * 0.5) / (w * 0.5)
  yn   = (idx.extract_band(1).cast("float") - h * 0.5) / (h * 0.5)
  r2   = xn * xn + yn * yn
  vign = clamp01(r2.pow(4.0).linear([intensity * 6.0], [0]))
  v3   = vign.bandjoin([vign, vign])
  safe_cast(clamp01(image.cast("float") / 255.0 * (1.0 - v3)) * 255.0)
rescue StandardError => e
  $logger.error "film_curl_vignette: #{e.message}"; image
end

# Selenium toning: silver areas in shadow zones chemically convert to selenium
# compounds — blue-violet shift in the deepest densities, neutral in highlights.
def selenium_tone(image, intensity = 0.45)
  img_f  = image.cast("float") / 255.0
  luma   = img_f.colourspace("b-w").cast("float") / 255.0
  shad_w = clamp01(luma.linear([-1], [1]).pow(1.5)) * (intensity * 0.65)
  r, g, b = img_f.bandsplit
  result  = Vips::Image.bandjoin([clamp01(r + shad_w * 0.12), g, clamp01(b + shad_w * 0.28)])
  safe_cast(result * 255.0)
rescue StandardError => e
  $logger.error "selenium_tone: #{e.message}"; image
end

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
  gray   = img_f.colourspace("b-w").colourspace("srgb").cast("float")
  result = clamp01(faded) * (1.0 - age * 0.18) + gray * (age * 0.18)
  safe_cast(clamp01(result) * 255.0)
rescue StandardError => e
  $logger.error "dye_fade: #{e.message}"; image
end

# Darkroom print tone compression. Optical enlarger prints cannot reproduce the full
# DR of a negative. Highlights block at paper Dmax; shadows print lighter than film.
# Slight gamma lift + shadow floor raise compress the tonal scale to print-medium range.
def darkroom_print(image, intensity = 0.50)
  img_f   = image.cast("float") / 255.0
  lifted  = img_f.pow(1.0 + intensity * 0.28)
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
  img_f    = image.cast("float") / 255.0
  shadow_w = image.colourspace("b-w").cast("float") / 255.0
  shadow_w = shadow_w.linear(-1, 1)
  r, g, b  = img_f.bandsplit
  result   = Vips::Image.bandjoin([
    clamp01(r + shadow_w * mask * 0.55),
    clamp01(g + shadow_w * mask * 0.18),
    clamp01(b - shadow_w * mask * 0.35)
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
  developed = image.maplut(lut)
  img_f = developed.cast("float") / 255.0
  luma  = developed.colourspace("b-w").cast("float") / 255.0
  if pdata[:warmth]
    hi_mask = luma ** 2.8
    sh_mask = luma.linear(-1, 1) ** 2.8
    r, g, b = img_f.bandsplit
    img_f = Vips::Image.bandjoin([
      clamp01(r + hi_mask * pdata[:warmth] * 0.8),
      clamp01(g + hi_mask * pdata[:warmth] * 0.15),
      clamp01(b - hi_mask * pdata[:warmth] * 0.35 + sh_mask * (pdata[:cool_shadow] || 0))
    ])
  end
  if pdata[:grain].to_i > 0
    amp   = pdata[:grain] * 0.25 / 255.0
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
  r = (x * x + y * y).pow(0.5).linear([1.0 / [w, h].max], [0.0])
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
  dx = (rand - 0.5) * intensity * w * 0.004
  dy = (rand - 0.5) * intensity * h * 0.002
  x = Vips::Image.xyz(w, h).extract_band(0).linear([1.0], [-dx])
  y = Vips::Image.xyz(w, h).extract_band(1).linear([1.0], [-dy])
  coords = x.bandjoin(y)
  image.mapim(coords)
rescue StandardError => e
  $logger.error "gate_weave: #{e.message}"; image
end

def lens_ghosting(image, intensity = 0.35)
  w, h = image.width, image.height
  luma = image.colourspace(:b_w)
  threshold = 1.0 - intensity * 0.25
  highlights = luma.more(threshold).gaussblur(12 * intensity)
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
  dist = (y_img - focus_y).abs.linear([2.0], [0.0]).pow(1.6)
  blur_radius = (intensity * 8).clamp(1, 20).to_f
  blurred = image.gaussblur(blur_radius)
  mask = dist.linear([intensity], [0.0]).clamp(0, 1)
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

# Filmic shoulder + toe: raised shadow floor + soft highlight rolloff.
# Models the analog curve endpoints without stock-specific emulsion data.
def film_shoulder(image, intensity = 0.75)
  toe = intensity * 0.04 * 255.0
  lifted = image.linear([1.0 - intensity * 0.04], [toe])
  rolled = highlight_roll(lifted, (220 - (intensity * 20).to_i), intensity * 0.50)
  safe_cast(rolled)
rescue StandardError => e
  $logger.error "film_shoulder: #{e.message}"; image
end

# Clarity: medium-radius unsharp on Lab L channel only — local contrast "3D pop"
# without hue shift or color fringing.
def clarity(image, radius = 15, intensity = 0.65)
  lab = image.colourspace("lab")
  l = lab.extract_band(0)
  a_ch = lab.extract_band(1)
  b_ch = lab.extract_band(2)
  detail = l - l.gaussblur(radius)
  l_new = l + detail.linear([intensity * 0.40], [0.0])
  safe_cast(Vips::Image.bandjoin([l_new, a_ch, b_ch]).colourspace("srgb"))
rescue StandardError => e
  $logger.error "clarity: #{e.message}"; image
end

# Edge-aware noise reduction: smooth flat areas, preserve edges.
# Approximated as luminance-masked Gaussian — clean base before film grain is added.
def edge_aware_nr(image, strength = 0.60)
  blurred = image.gaussblur(1.5 + strength * 2.0)
  quick = image.gaussblur(1.5)
  edge_diff = (image - quick) + (quick - image)
  edge_luma = edge_diff.extract_band(0) * 0.299 +
              edge_diff.extract_band(1) * 0.587 +
              edge_diff.extract_band(2) * 0.114
  mask = (edge_luma > (12.0 * (1.0 - strength * 0.5))).ifthenelse(1, 0)
  mask3 = mask.bandjoin([mask, mask])
  safe_cast(image * mask3 + blurred * mask3.linear([-1.0], [1.0]))
rescue StandardError => e
  $logger.error "edge_aware_nr: #{e.message}"; image
end

# Selective sharpening: high-pass at σ=1.2, applied only at high-edge regions.
# Lifts perceived acuity at detail without amplifying noise in smooth areas.
def selective_sharpen(image, intensity = 0.70)
  blurred = image.gaussblur(1.2)
  detail = image - blurred
  edge_diff = detail + (blurred - image)
  edge_luma = edge_diff.extract_band(0) * 0.299 +
              edge_diff.extract_band(1) * 0.587 +
              edge_diff.extract_band(2) * 0.114
  mask = (edge_luma > 8).ifthenelse(1, 0)
  mask3 = mask.bandjoin([mask, mask])
  safe_cast(image + detail * mask3 * (intensity * 0.55))
rescue StandardError => e
  $logger.error "selective_sharpen: #{e.message}"; image
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
# Physics-calibrated: fraction of incident energy reflected per dye layer depth.
# Red penetrates deepest (0.92), green mid-layer (0.15), blue nearest surface (0.04).
HALATION_TINT_VISION3 = [0.92, 0.15, 0.04].freeze
HALATION_TINT_PORTRA  = [0.88, 0.12, 0.04].freeze
HALATION_TINT_TRI_X   = [0.45, 0.45, 0.45].freeze
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
  # Lorentzian-approx PSF: sharp core (30%) + wide wings (70%) per wavelength band.
  halo_r = (bright.gaussblur(sigma_r * 0.7) * 0.30 + bright.gaussblur(sigma_r * 1.6) * 0.70) * (tint[0] * intensity)
  halo_g = (bright.gaussblur(sigma_g * 0.7) * 0.30 + bright.gaussblur(sigma_g * 1.6) * 0.70) * (tint[1] * intensity)
  halo_b = (bright.gaussblur(sigma_b * 0.7) * 0.30 + bright.gaussblur(sigma_b * 1.6) * 0.70) * (tint[2] * intensity)
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

def preset(image, name)
  p = PRESETS[name.to_sym]
  return image unless p
  result  = image
  t_start = Time.now
  n_steps = p[:fx].length
  PostproBootstrap.dmesg "preset=#{name} stock=#{p[:stock]} steps=#{n_steps} intensity=#{p[:intensity]}"

  p[:fx].each_with_index do |fx, i|
    t0 = Time.now
    result = case fx
             when "optical_blur"        then optical_blur(result, 0.5)
             when "tonemap"             then tonemap(result, type: :aces, exposure: p.fetch(:tonemap_ev, 0.0), intensity: p[:intensity] * 0.85)
             when "halation"            then halation(result, p[:intensity] * 0.60, tint: halation_tint_for(p[:stock]))
             when "film_curve"          then film_curve(result, p[:stock], p[:intensity])
             when "spectral_temp"       then spectral_temp(result, source_kelvin: 6504, target_kelvin: p[:temp], intensity: p[:intensity] * 0.50)
             when "color_temp"          then color_temp(result, p[:temp], p[:intensity] * 0.50)
             when "dir_coupler"         then dir_coupler(result, p[:intensity] * 0.12)
             when "push_pull"           then push_pull(result, p.fetch(:stops, 1.0), p[:stock])
             when "bleach_bypass"       then bleach_bypass(result, p[:intensity] * 0.40)
             when "reciprocity_failure" then reciprocity_failure(result, p.fetch(:exposure_secs, 10.0), p[:stock])
             when "orange_mask"         then orange_mask(result, p[:stock], p[:intensity] * 0.90)
             when "print_film"          then print_film(result, p.fetch(:print_stock, :kodak_2383), p[:intensity] * 0.70)
             when "split_grade"         then split_grade(result, intensity: p[:intensity] * 0.25)
             when "split_toning"        then split_toning(result)
             when "skin_protect"        then skin_protect(result, p[:intensity])
             when "shadow_lift"         then shadow_lift(result, 0.12, true)
             when "highlight_roll"      then highlight_roll(result, 200, p[:intensity] * 0.50)
             when "micro_contrast"      then micro_contrast(result, 5, p[:intensity] * 0.20)
             when "grain"               then grain(result, 800, p[:stock], p[:intensity] * 0.30)
             when "color_separate"      then color_separate(result, p[:intensity] * 0.55)
             when "chromatic_aberration" then chromatic_aberration(result, p[:intensity] * 0.25)
             when "vintage_lens"        then vintage_lens(result, p.fetch(:lens, "zeiss"), p[:intensity] * 0.70)
             when "teal_orange"         then teal_orange(result, p[:intensity] * 0.80)
             when "bloom_pro"           then bloom_pro(result, p[:intensity] * 0.25)
             when "desaturate"          then desaturate(result, p[:intensity] * 0.45)
             when "warmth"              then warmth(result, p[:intensity] * 0.25)
             when "green_push"          then green_push(result, p[:intensity] * 0.15)
             when "cross_fade"          then cross_fade(result, p[:intensity] * 0.40)
             when "infrared"            then infrared(result, p[:intensity] * 0.85)
             when "lith_print"          then lith_print(result, p[:intensity] * 0.75)
             when "kodachrome_sim"      then kodachrome_sim(result, p[:intensity] * 0.75)
             when "technicolor"         then technicolor(result, p[:intensity] * 0.55)
             when "cyanotype"           then cyanotype(result, p[:intensity])
             when "faded_print"         then faded_print(result, p.fetch(:age, 0.40))
             when "base_tint"           then base_tint(result, [255, 250, 242], 0.07)
             when "dual_base_density"   then dual_base_density(result, [255, 248, 236], 0.06)
             when "emulsion_defocus"    then emulsion_defocus(result, p[:stock])
             when "adjacency_effects"   then adjacency_effects(result, p[:intensity] * 0.25)
             when "longitudinal_ca"     then longitudinal_ca(result, p[:intensity] * 0.50)
             when "lens_distortion"     then lens_distortion(result, p.fetch(:k1, -0.12))
             when "bokeh_rendering"     then bokeh_rendering(result, p[:intensity] * 0.35)
             when "anamorphic_flare"    then anamorphic_flare(result, p[:intensity] * 0.50)
             when "diffraction_blur"    then diffraction_blur(result, p.fetch(:f_number, 16.0))
             when "scan_noise"          then scan_noise(result, p[:intensity] * 0.40)
             when "newton_rings"        then newton_rings(result, p[:intensity] * 0.12)
             when "dust_and_hair"       then dust_and_hair(result, p[:intensity] * 0.50)
             when "film_curl_vignette"  then film_curl_vignette(result, p[:intensity] * 0.45)
             when "selenium_tone"       then selenium_tone(result, p[:intensity] * 0.45)
             when "dye_fade"            then dye_fade(result, p[:stock], p.fetch(:age, 0.50))
             when "darkroom_print"      then darkroom_print(result, p[:intensity] * 0.50)
             when "film_base_density"   then film_base_density(result, p[:stock], 0.06)
             when "paper_texture"       then paper_texture(result, p[:intensity] * 0.35)
             when "dodgeburn_artifacts" then dodgeburn_artifacts(result, p[:intensity] * 0.40)
             when "fixing_bath_fog"     then fixing_bath_fog(result, p[:intensity] * 0.30)
             when "reticulation"        then reticulation(result, p[:intensity] * 0.50)
             when "expired_film"        then expired_film(result, p.fetch(:age, 0.60))
             when "gate_weave"          then gate_weave(result, p[:intensity] * 0.40)
             when "lens_ghosting"       then lens_ghosting(result, p[:intensity] * 0.35)
             when "ortho_film"          then ortho_film(result, p[:intensity] * 0.80)
             when "tilt_shift"          then tilt_shift(result, p[:intensity] * 0.70)
             when "adaptive_contrast"   then adaptive_contrast(result, p[:intensity] * 0.70)
             when "film_shoulder"       then film_shoulder(result, p[:intensity] * 0.75)
             when "clarity"             then clarity(result, 15, p[:intensity] * 0.65)
             when "edge_aware_nr"       then edge_aware_nr(result, p[:intensity] * 0.55)
             when "selective_sharpen"   then selective_sharpen(result, p[:intensity] * 0.65)
             else result
             end
    result = result.copy_memory
    GC.start(full_mark: false) if (i % 4).zero?
    PostproBootstrap.dmesg "fx=#{fx} step=#{i + 1}/#{n_steps} time=%.3fs" % (Time.now - t0)
  end

  PostproBootstrap.dmesg "preset=#{name} done total=%.2fs" % (Time.now - t_start)
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
  sepia = image.recomb(matrix)
  safe_cast(image.cast("float") * (1.0 - intensity) + sepia.cast("float") * intensity)
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
  shift = (15 * intensity).round
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

RECIPE_ALLOWED = %w[
  grain film_curve highlight_roll shadow_lift micro_contrast color_separate
  chromatic_aberration vintage_lens split_toning split_grade bleach_bypass
  push_pull halation optical_blur tonemap dir_coupler spectral_temp color_temp
  skin_protect desaturate warmth green_push cross_fade infrared cyanotype
  lith_print technicolor kodachrome_sim faded_print base_tint dual_base_density
  reciprocity_failure bloom_pro teal_orange grain_basic leaks_basic sepia_basic
  bloom_basic cross_basic vhs_basic chroma_basic glitch_basic flare_basic
  emulsion_defocus adjacency_effects longitudinal_ca lens_distortion bokeh_rendering
  anamorphic_flare diffraction_blur scan_noise newton_rings dust_and_hair
  film_curl_vignette selenium_tone dye_fade darkroom_print film_base_density
  paper_texture dodgeburn_artifacts fixing_bath_fog reticulation expired_film
  gate_weave lens_ghosting ortho_film tilt_shift
  adaptive_contrast film_shoulder clarity edge_aware_nr selective_sharpen
].freeze

def recipe(image, recipe_data)
  result = image
  recipe_data.each do |fx, params|
    intensity = params.is_a?(Hash) ? params["intensity"].to_f : params.to_f
    method = fx.gsub("_professional", "")
    result = (RECIPE_ALLOWED.include?(method) && respond_to?(method)) ? send(method, result, intensity) : result
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
    preset_name = PROMPT ? PROMPT.select("Choose preset for Repligen outputs:", PRESETS.keys) : (CONFIG["default_preset"] || "portrait")
    recent_files.each { |file| process_file(file, 2, preset_name) }
  end
end

def preset_chain(image, names)
  names.reduce(image) { |img, name| preset(img, name) }
end

def process_file(file, variations, preset_name = nil, recipe_data = nil, random_effects = nil, mode = "professional")
  image = load_image(file)
  return 0 unless image

  # Apply camera profile first if enabled
  if CONFIG["apply_camera_profile_first"]
    profile = get_camera_profile(image)
    if profile
      image = apply_camera_profile(image, profile)
      PostproBootstrap.dmesg "camera_profile src=#{File.basename(file)}"
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

      processed = grain(processed, 400, :kodak_portra, 0.35)
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
      PostproBootstrap.dmesg "write out=#{File.basename(output)} q=#{quality}"
      processed_count += 1

    rescue StandardError => e
      $logger.error "Variation #{i + 1} failed: #{e.message}"
    end
  end

  processed_count
end

# Main Workflow
def get_input
  $cli_logger.info "postpro.rb v18.0.0 full-analog#{REPLIGEN_PRESENT ? " repligen=active" : ""}"

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
    out = argv_flag("--output") || "#{name}.cube"
    size = (argv_flag("--size") || "17").to_i
    export_lut(name.to_sym, out, size)
  end
end

def run_one_shot
  input_path = argv_flag("--input")
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
  processed = rgb_bands(processed)
  quality = CONFIG["jpeg_quality"] || 95
  processed.write_to_file(output_path, Q: quality)
  $cli_logger.info "ok preset=#{preset_name} out=#{output_path}"
end

def watch_mode?
  ARGV.include?("--watch")
end

def random_mode?
  ARGV.include?("--random")
end

# Resolve the best available downloads directory on Android/Termux or desktop.
def downloads_dir
  candidates = [
    argv_flag("--random"),
    File.expand_path("~/storage/downloads"),
    "/sdcard/Download",
    File.expand_path("~/Downloads"),
    Dir.pwd
  ]
  candidates.compact.find { |d| File.directory?(d) }
end

# --random [DIR] [experimental]
# Without "experimental": random preset per file (uplift — maximally cinematic).
# With "experimental": chaotic short random chains (happy accidents).
def run_random
  experimental = ARGV.include?("experimental")
  dir = downloads_dir
  files = Dir.glob(File.join(dir, "**", "*.{jpg,jpeg,JPG,JPEG,png,PNG,webp,WEBP}"))
             .reject { |f| File.basename(f).match?(/processed|masterpiece|postpro|_v\d+_/) }

  if files.empty?
    $cli_logger.error "No images in #{dir}"
    return
  end

  PostproBootstrap.dmesg "random dir=#{dir} files=#{files.count} mode=#{experimental ? 'experimental' : 'uplift'}"
  count = (argv_flag("--count") || argv_flag("-n") || 4).to_i.clamp(1, 6)
  uplift_presets = %i[portrait cinematic magic_hour blockbuster golden_age reversal
                      warmth noir masterpiece anamorphic aged_kodachrome analog_scan
                      cinema_scan nitrate fiber_print expired reticulated ortho
                      tilt_shift_look haunted quality_uplift]

  files.each_with_index do |file, index|
    $cli_logger.info "#{index + 1}/#{files.count}: #{File.basename(file)}"
    begin
      if experimental
        fx_pool = %w[grain leaks sepia bloom teal_orange cross vhs chroma glitch flare]
        count.times do
          effects = fx_pool.shuffle.take(rand(4..7))
          process_file(file, 1, nil, nil, effects, "experimental")
        end
      else
        pool = uplift_presets.shuffle
        count.times do |i|
          base = pool[i % pool.size]
          layer = (pool - [base]).sample
          image = load_image(file)
          next unless image
          processed = preset_chain(image, [base, layer])
          processed = grain(processed, 400, :kodak_portra, 0.35)
          processed = rgb_bands(processed)
          timestamp = Time.now.strftime("%Y%m%d%H%M%S")
          output = file.sub(File.extname(file), "_#{base}+#{layer}_v#{i + 1}_#{timestamp}#{File.extname(file)}")
          quality = CONFIG["jpeg_quality"] || 95
          processed.write_to_file(output, Q: quality)
          PostproBootstrap.dmesg "write chain=#{base}+#{layer} out=#{File.basename(output)}"
        end
      end
      GC.start if (index % 5).zero?
    rescue StandardError => e
      $cli_logger.error "Error #{File.basename(file)}: #{e.message}"
    end
  end
end

def run_watch
  dir     = argv_flag("--watch") || "/sdcard/DCIM/Camera"
  preset_name = (argv_flag("--preset") || "cinematic").to_sym
  unless PRESETS.key?(preset_name)
    $cli_logger.error "Unknown preset: #{preset_name}"
    exit 1
  end
  seen    = Dir.glob(File.join(dir, "IMG_*.{jpg,jpeg,JPG,JPEG}")).map { |f| [f, File.mtime(f)] }.to_h
  PostproBootstrap.dmesg "watch dir=#{dir} preset=#{preset_name} known=#{seen.size}"
  loop do
    sleep 2
    Dir.glob(File.join(dir, "IMG_*.{jpg,jpeg,JPG,JPEG}")).each do |path|
      mtime = File.mtime(path)
      next if seen[path] == mtime
      seen[path] = mtime
      next if File.size(path) < 50_000
      ext  = File.extname(path)
      base = File.basename(path, ext)
      out  = File.join(dir, "#{base}_#{preset_name}#{ext}")
      PostproBootstrap.dmesg "new path=#{File.basename(path)} -> #{File.basename(out)}"
      begin
        image     = load_image(path)
        processed = preset(image, preset_name)
        processed = rgb_bands(processed)
        processed.write_to_file(out, Q: CONFIG["jpeg_quality"] || 95)
        $cli_logger.info "ok preset=#{preset_name} out=#{out}"
      rescue StandardError => e
        $cli_logger.error "watch error: #{e.message}"
      end
    end
  end
end

def auto_launch
  return run_introspect if introspect_mode?
  return run_watch       if watch_mode?
  return run_one_shot    if one_shot_mode?
  return run_random      if random_mode?
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
