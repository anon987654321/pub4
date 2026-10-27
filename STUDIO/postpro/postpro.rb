#!/usr/bin/env ruby
# frozen_string_literal: true

# postpro: film emulation and photo grading over libvips. `--help` lists the
# flags; `--capabilities` says what this build can do.

require "logger"
require "json"
require "time"
require "fileutils"
require "digest"
# postpro lives two levels below MASTER/, so ../../lib/io resolves to
# MASTER/lib/io. Keep this anchored path rather than depending on the operator's
# working directory.
require_relative "analog_capabilities"

require "open3"
require "rbconfig"
require_relative "legacy_effects"
require_relative "dilla_analog"
require_relative "constitution"
require_relative "../source_map"
require_relative "depth"
include Postpro::LegacyEffects
include Postpro::DillaAnalog

require_relative "bootstrap"

require_relative "explain"

BOOTSTRAP = PostproBootstrap.run

# Stills only. Every input glob is jpg/jpeg/png/webp and nothing here reads a
# video.
#
# A frame-by-frame video path existed and was removed. It shelled out to a fresh
# interpreter per frame, so a minute of 1080p cost about an hour while its own
# estimate promised six minutes, and two of its eight tests timed out rather
# than passed. Whatever replaces it grades in-process, holds the grain seed
# steady across frames so the grain does not boil, and declares a per-minute
# budget it is held to; a path that cannot do those is not worth having back.
POSTPRO_USAGE = <<~TXT
  usage: postpro.rb [flags]           with no flags, asks what to grade
  usage: postpro.rb IMAGE... | DIR... ten light analog takes per image and a contact
                                      sheet, all written beside the image

    --input FILE --output FILE --preset NAME   grade one image
    --reference FILE                  add a quality report against a reference
    --compare                         side-by-side after a one-shot grade
    --random [--count N] [--rough]    five to ten analog variations per image
    --heavy                           start each take from a named look (noir, neon
                                      night...); lane deal subtle→bleeding edge, at most
                                      ten steps a take; also POSTPRO_HEAVY=1
    --watch [DIR] [--preset NAME]     grade every new photo that lands in DIR
    --auto                            grade the default globs without prompting
    --from-replicate                   grade what replicate just wrote
    --rescue FILE [--output FILE]     diagnose a photograph, then apply the fix
    --measure FILE [--against AFTER]  read texture numbers and palette, or how a grade moved them
    --stock-sheet FILE [--preset NAME] [--output FILE]  one frame through every stock, tiled
    --gallery [DIR]                   an index.html contact page of every render in DIR
    --map                             the table of contents of this file, with line numbers
    --set DIR                         which frames repeat, and how far each sits from the set's exposure
    --vocab-check                     are the tables consistent?
    --capabilities                    what this build can do
    --list-presets | --list-stocks | --list-lenses
    --describe-preset NAME | --css-filter NAME | --fit-grain SCAN
    --export-lut NAME [--output FILE] [--size N]
    CONFIG is the built-in tables unless POSTPRO_CONFIG or master.json beside this file names more.
TXT
if (ARGV & %w[-h --help]).any?
  puts POSTPRO_USAGE
  exit 0
end

# Defined here, above its first caller: a def below a top-level use is not yet
# defined when that line runs.
def argv_flag(flag)
  idx = ARGV.index(flag)
  idx && ARGV[idx + 1]
end

# A lone --preset falls through to the interactive chooser and can look like a
# hung non-interactive job. Named one-shot grades are only valid with input and
# output paths; watch and stock-sheet have their own documented preset routes.
one_shot_flags = %w[--input --output --preset]
one_shot_requested = one_shot_flags.any? { |flag| ARGV.include?(flag) }
complete_one_shot = one_shot_flags.all? do |flag|
  value = argv_flag(flag)
  value && !value.start_with?("--")
end
dedicated_mode = (%w[--watch --stock-sheet --rescue --export-lut] & ARGV).any?
if one_shot_requested && !complete_one_shot && !dedicated_mode
  message = [
    "ERROR one-shot mode requires --input FILE, --output FILE and --preset NAME",
    "(or use --watch/--stock-sheet/--rescue/--export-lut)",
  ].join(" ")
  PostproBootstrap.dmesg(message)
  exit 2
end

# Light is the default; --heavy opts one invocation into the named-look takes,
# even when POSTPRO_HEAVY=0 is inherited from the environment.
ENV["POSTPRO_HEAVY"] = "1" if ARGV.include?("--heavy")

# What is wrong with this photograph, and which half a grade can reach.
#
# --rescue FILE diagnoses and stops. Add --output FILE and it applies the
# preset its findings point at. It names what it cannot fix every time, because
# three of the four layers a photograph fails on are beyond any grade, and a
# tool that quietly tries everything and reports success is lying about them.
if ARGV.include?("--rescue")
  require_relative "rescue"
  subject = ARGV[ARGV.index("--rescue") + 1]
  if subject.nil? || !File.file?(subject)
    PostproBootstrap.dmesg("ERROR --rescue needs a readable file")
    exit 1
  end

  findings = Postpro::Rescue.diagnose(subject)
  Postpro::Rescue.report(findings).each { |line| PostproBootstrap.dmesg(line) }

  target = ARGV.include?("--output") ? ARGV[ARGV.index("--output") + 1] : nil
  preset = Postpro::Rescue.preset_for(findings)
  if target.nil?
    PostproBootstrap.dmesg("rescue: diagnosis only — pass --output FILE to apply " \
                           "#{preset || 'a grade'}")
    exit 0
  end
  if preset.nil?
    PostproBootstrap.dmesg("rescue: nothing to apply; the optical layer is already sound")
    exit 0
  end

  PostproBootstrap.dmesg("rescue: applying preset=#{preset}")
  out, status = Open3.capture2e(RbConfig.ruby, __FILE__, "--input", subject,
                                "--output", target, "--preset", preset)
  unless status.success?
    PostproBootstrap.dmesg("ERROR rescue: the grade failed: #{out.lines.last.to_s.strip}")
    exit 1
  end

  require_relative "uncanny"
  comparison = Postpro::Uncanny.compare(subject, target)
  Postpro::Uncanny.verdict(comparison).each { |line| PostproBootstrap.dmesg("rescue: #{line}") }
  PostproBootstrap.dmesg("rescue: wrote #{target}")
  exit 0
end

# What a set of frames says about itself: which frames are one photograph taken
# twice, and how far each frame's exposure sits from the set's own median. Both
# are readings, and the set is left as it was — moving a frame toward the
# median changes the graded look, which is the operator's decision.
if ARGV.include?("--set")
  require_relative "frame_set"
  dir = ARGV[ARGV.index("--set") + 1]
  unless dir && File.directory?(dir)
    PostproBootstrap.dmesg("ERROR --set needs a directory of frames")
    exit 1
  end

  paths = Postpro::FrameSet.frames(dir)
  if paths.size < 2
    PostproBootstrap.dmesg("set #{dir}: #{paths.size} frame, and a set needs two")
    exit 0
  end

  Postpro::FrameSet.near_duplicates(paths).each do |pair|
    PostproBootstrap.dmesg("set duplicate: #{File.basename(pair.first)} ~ #{File.basename(pair.second)} " \
                           "(#{pair.distance}/64 bits differ)")
  end
  Postpro::FrameSet.exposure_offsets(paths).each do |path, stops|
    PostproBootstrap.dmesg(format("set exposure: %+.2f stops  %s", stops, File.basename(path)))
  end
  exit 0
end

# Four numbers on an image, or the delta across a grade. Handled here, straight
# after boot, because everything below this point can reach the interactive
# prompt — and a measurement that waits for a keypress is a measurement nobody
# puts in a script.
#
# Everything this file claims about putting texture back — the grain, the
# halation, the H&D shoulder — was an assertion until something measured it.
# `--measure FILE` reads one image; adding `--against AFTER` reads the pair and
# says which way each number moved and whether that is the direction film
# emulation should move it.
if ARGV.include?("--measure")
  require_relative "uncanny"
  subject = ARGV[ARGV.index("--measure") + 1]
  if subject.nil? || !File.file?(subject)
    PostproBootstrap.dmesg("ERROR --measure needs a readable file")
    exit 1
  end

  against = ARGV.include?("--against") ? ARGV[ARGV.index("--against") + 1] : nil
  if against.nil?
    PostproBootstrap.dmesg("measure #{File.basename(subject)}: #{Postpro::Uncanny.read(subject)}")
    image = Vips::Image.new_from_file(subject, access: :random)
    PostproBootstrap.dmesg(format("measure %s: finest_octave=%.2f squint=%.2f", File.basename(subject),
                                  Postpro::Uncanny.finest_octave(image), Postpro::Uncanny.squint_image(image)))
    PostproBootstrap.dmesg("measure #{File.basename(subject)}: palette #{Postpro::Uncanny.palette_line(image)}")
  elsif !File.file?(against)
    PostproBootstrap.dmesg("ERROR --against #{against} is not a file")
    exit 1
  else
    comparison = Postpro::Uncanny.compare(subject, against)
    PostproBootstrap.dmesg("measure before: #{comparison[:before]}")
    PostproBootstrap.dmesg("measure after:  #{comparison[:after]}")
    Postpro::Uncanny.verdict(comparison).each { |line| PostproBootstrap.dmesg("measure #{line}") }
    [subject, against].each do |path|
      image = Vips::Image.new_from_file(path, access: :random)
      PostproBootstrap.dmesg("measure #{File.basename(path)}: palette #{Postpro::Uncanny.palette_line(image)}")
    end
  end
  exit 0
end
# Anchored to the tool, not to the shell's working directory — the same CWD
# defect this file already fixes for master.json and replicate.rb. A bare
# relative path meant even a read-only --vocab-check created a log wherever the
# operator happened to be standing.
#
# The Rails apps run this as their own user from dev's checkout on vm23, where
# this directory is not theirs to write, so the log falls back to stderr there
# rather than aborting the grade before it starts.
postpro_log = File.join(__dir__, "postpro.log")
postpro_log = $stderr unless File.writable?(File.exist?(postpro_log) ? postpro_log : __dir__)
$logger = Logger.new(postpro_log, "daily", level: Logger::DEBUG)
$cli_logger = Object.new.tap do |obj|
  def obj.info(msg) = PostproBootstrap.dmesg(msg)
  # warn was missing while two call sites used it, so a bad recipe key hit
  # private Kernel#warn, raised NoMethodError, and process_file's rescue turned
  # it into "Variation 1 failed" — naming neither the recipe nor the key, and
  # producing no output files for one typo.
  def obj.warn(msg) = PostproBootstrap.dmesg("warn #{msg}")
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
  # Here rather than at the top of the file: uncanny.rb opens with `require
  # "vips"`, so requiring it before the bootstrap has decided vips is present
  # would raise during load and take the whole tool down instead of degrading.
  # The grade reads it now — shadow_lift asks where the blacks already sit, and
  # preset() asks how much texture and contrast the source arrived with.
  require_relative "uncanny"
end

# Was File.exist?("replicate.rb") -- relative to the CURRENT WORKING DIRECTORY,
# which is wherever the user happened to be, and never the directory replicate
# lives in. It has been false on every invocation from anywhere, so the
# --from-replicate branch and the closing hand-off tip were both unreachable.
# replicate is a sibling of this file, and that relationship does not depend on
# where the shell was when it started.
REPLICATE_PATH = File.expand_path("../replicate/replicate.rb", __dir__)
REPLICATE_PRESENT = File.exist?(REPLICATE_PATH)
CAMERA_PROFILES = BOOTSTRAP[:camera_profiles]
CONFIG = BOOTSTRAP[:config]
$postpro_seed = Integer(ENV.fetch("POSTPRO_SEED", "0"), exception: false) || 0

def postpro_seed(offset = 0)
  (($postpro_seed || 0) + offset).abs % 2_147_483_647
end

# A generator for one effect, derived from the run seed, so the same seed lays
# the same dust, the same weave and the same dropout twice.
def postpro_rng(offset)
  Random.new(postpro_seed(offset))
end

# Per-stock data: grain sigma (legacy), 3x3 colour matrix, and characteristic
# curve [Dmin, Dmax, pivot, gamma] per R/G/B. Dmin lifts shadows (base+fog),
# Dmax caps highlights (shoulder), pivot is the linear midtone fulcrum (≈0.18),
# gamma is contrast (>1 = steeper). Per-channel offsets create stock colour cast.
STOCKS = {
  kodak_portra: { grain: 15, speed: 400,
                  sublayers: [{ sensitivity_shift: 0.0, grain_scale: 1.4, weight: 0.45 },
                               { sensitivity_shift: -0.5, grain_scale: 1.0, weight: 0.55 }],
                  matrix: [1.05, -0.02, -0.03, 0.02, 0.98, 0.00, 0.01, -0.05, 1.04],
                  hd: { r: [0.06, 0.93, 0.18, 1.10], g: [0.05, 0.94, 0.18, 1.10], b: [0.04, 0.92, 0.20, 1.05] } },
  kodak_vision3: { grain: 20, speed: 500,
                   sublayers: [{ sensitivity_shift: 0.3, grain_scale: 1.5, weight: 0.40 },
                                { sensitivity_shift: 0.0, grain_scale: 1.1, weight: 0.35 },
                                { sensitivity_shift: -0.6, grain_scale: 0.85, weight: 0.25 }],
                   matrix: [1.08, -0.05, -0.03, 0.03, 0.95, 0.02, 0.02, -0.08, 1.06],
                   hd: { r: [0.07, 0.95, 0.17, 1.15], g: [0.06, 0.95, 0.18, 1.20], b: [0.08, 0.90, 0.20, 1.10] } },
  kodak_vision3_50d: { grain: 8, speed: 50, matrix: [1.06, -0.03, -0.02, 0.02, 0.96, 0.01, 0.01, -0.05, 1.04],
                       hd: { r: [0.05, 0.95, 0.18, 1.08], g: [0.04, 0.95, 0.18, 1.12], b: [0.03, 0.93, 0.20, 1.05] } },
  kodak_vision3_500t: { grain: 20, speed: 500, matrix: [1.10, -0.06, -0.04, 0.04, 0.94, 0.03, 0.04, -0.10, 1.09],
                        hd: { r: [0.08, 0.95, 0.17, 1.18], g: [0.06, 0.95, 0.18, 1.22], b: [0.10, 0.90, 0.20, 1.15] },
                        focal_plane_offset: 1.1 },
  cinestill_800t: { grain: 22, speed: 800,
                    sublayers: [{ sensitivity_shift: 0.4, grain_scale: 1.6, weight: 0.35 },
                                 { sensitivity_shift: 0.0, grain_scale: 1.2, weight: 0.40 },
                                 { sensitivity_shift: -0.5, grain_scale: 0.9, weight: 0.25 }],
                    matrix: [1.12, -0.07, -0.05, 0.04, 0.93, 0.03, 0.05, -0.12, 1.10],
                    hd: { r: [0.09, 0.96, 0.17, 1.20], g: [0.07, 0.95, 0.18, 1.25], b: [0.12, 0.88, 0.20, 1.18] },
                    halation: 0.8, focal_plane_offset: 1.2 },
  ektachrome_100: { grain: 10, speed: 100, matrix: [1.08, -0.04, -0.04, 0.02, 1.02, -0.02, 0.01, -0.08, 1.07],
                    hd: { r: [0.02, 0.97, 0.18, 1.30], g: [0.02, 0.97, 0.18, 1.35], b: [0.03, 0.96, 0.20, 1.25] } },
  fuji_velvia: { grain: 8, speed: 50, matrix: [1.12, -0.08, -0.04, 0.05, 1.05, -0.02, 0.01, -0.12, 1.11],
                 hd: { r: [0.02, 0.97, 0.18, 1.45], g: [0.02, 0.98, 0.18, 1.50], b: [0.03, 0.95, 0.20, 1.40] } },
  tri_x: { grain: 25, speed: 400, matrix: [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
            hd: { r: [0.05, 0.95, 0.18, 1.30], g: [0.05, 0.95, 0.18, 1.30], b: [0.05, 0.95, 0.18, 1.30] } },
  # Kodachrome: steep gamma, no in-film couplers, external development process.
  # Punchy reds, heavy yellow separation, minimal shadow fog.
  kodachrome: { grain: 12, speed: 64, matrix: [1.15, -0.10, -0.05, 0.03, 1.00, -0.03, 0.00, -0.10, 1.10],
                hd: { r: [0.02, 0.97, 0.18, 1.42], g: [0.03, 0.97, 0.18, 1.36], b: [0.04, 0.95, 0.20, 1.20] } },

  # --- 2026-07-30 ------------------------------------------------------------
  # Nine stocks, and seven of them Kodak. The table could do warm-and-forgiving
  # (Portra), cine (Vision3), saturated reversal (Velvia) and one black and
  # white — and nothing else at all: no fast grainy B&W, no cool palette, no
  # instant film, no saturated NEGATIVE as opposed to slide.
  #
  # Each new entry carries a row in all five per-stock tables below it, because
  # a stock missing from GRAIN_CHAN_SCALE silently grains like Portra, one
  # missing from PUSH_RESPONSE pushes like Portra, and one missing from
  # FILM_BASE has no base fog. vocab-check now refuses a stock with a gap.

  # Reportage black and white. Enormous latitude, forgiving of being wrong by
  # two stops in either direction, and grainier than Tri-X at the same speed.
  ilford_hp5: { grain: 22, speed: 400,
                sublayers: [{ sensitivity_shift: 0.2, grain_scale: 1.35, weight: 0.5 },
                            { sensitivity_shift: -0.4, grain_scale: 1.0, weight: 0.5 }],
                matrix: [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
                hd: { r: [0.06, 0.94, 0.18, 1.22], g: [0.06, 0.94, 0.18, 1.22], b: [0.06, 0.94, 0.18, 1.22] } },

  # Available darkness. Nominally 3200 and actually closer to 1000 pushed hard,
  # which is why the grain is enormous and the highlights never reach full
  # density -- the low Dmax here is the stock, not an error.
  ilford_delta3200: { grain: 38, speed: 3200,
                      sublayers: [{ sensitivity_shift: 0.6, grain_scale: 1.9, weight: 0.45 },
                                  { sensitivity_shift: 0.0, grain_scale: 1.3, weight: 0.35 },
                                  { sensitivity_shift: -0.5, grain_scale: 1.0, weight: 0.20 }],
                      matrix: [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
                      hd: { r: [0.11, 0.88, 0.18, 1.08], g: [0.11, 0.88, 0.18, 1.08], b: [0.11, 0.88, 0.18, 1.08] } },

  # The saturated NEGATIVE, which is a different animal from a saturated slide:
  # Velvia's colour comes with Velvia's two-stop latitude, Ektar's does not.
  # Reds are the point.
  kodak_ektar100: { grain: 6, speed: 100,
                    matrix: [1.14, -0.09, -0.05, 0.02, 1.03, -0.05, 0.00, -0.09, 1.09],
                    hd: { r: [0.03, 0.96, 0.18, 1.34], g: [0.03, 0.96, 0.18, 1.32], b: [0.04, 0.94, 0.20, 1.28] } },

  # The cool one. Everything else in this table warms; Pro 400H leans green and
  # cyan and holds pastel skin, which is the whole reason it was worth having.
  fuji_pro400h: { grain: 16, speed: 400,
                  sublayers: [{ sensitivity_shift: 0.1, grain_scale: 1.25, weight: 0.45 },
                              { sensitivity_shift: -0.45, grain_scale: 0.95, weight: 0.55 }],
                  matrix: [0.97, 0.02, 0.01, -0.02, 1.02, 0.00, 0.00, 0.04, 1.02],
                  hd: { r: [0.05, 0.92, 0.18, 1.05], g: [0.05, 0.93, 0.18, 1.06], b: [0.06, 0.93, 0.20, 1.04] } },

  # Instant film. High base fog, a Dmax that never gets near black, and a gamma
  # under 1 -- an integral print developing in daylight in ninety seconds cannot
  # do contrast, and that softness is the look.
  polaroid_sx70: { grain: 14, speed: 150,
                   matrix: [1.06, 0.02, -0.04, 0.01, 0.98, 0.03, 0.03, 0.02, 0.99],
                   hd: { r: [0.15, 0.86, 0.20, 0.95], g: [0.14, 0.85, 0.20, 0.93], b: [0.13, 0.84, 0.22, 0.90] } },
}.freeze

# Lens character: data-driven table drives vintage_lens().
# vignette/glow/micro_contrast/chroma are intensity multipliers [0,1].
LENSES = {
  zeiss: { micro_contrast: 0.40, flare: 0.08 },
  leica: { micro_contrast: 0.45, glow: 0.25 },
  helios: { micro_contrast: 0.30, chroma: 0.05 },
  cooke: { micro_contrast: 0.20, warmth: 0.10 },
  anamorphic: { micro_contrast: 0.25, chroma: 0.08, flare: 0.50 },
  # A lens is defined as much by how it fails as by how it resolves, and the
  # five above are all variations on "sharp, with a little something". These
  # are the failures: a Petzval that only holds the centre, uncoated glass that
  # veils, a plastic Lomo meniscus, a soft-focus portrait lens that halates on
  # purpose. Only the modern Summicron entry is another sharp one, and it is
  # there so there is something at the top of the range to compare against.
  petzval: { micro_contrast: 0.35, glow: 0.18, chroma: 0.06 },
  takumar: { micro_contrast: 0.28, warmth: 0.16, glow: 0.10 },
  lomo: { micro_contrast: 0.12, chroma: 0.10, glow: 0.16, flare: 0.18 },
  soft_focus: { micro_contrast: 0.08, glow: 0.45 },
  uncoated: { micro_contrast: 0.18, glow: 0.20, flare: 0.35, warmth: 0.08 },
  summicron: { micro_contrast: 0.50, flare: 0.04 },
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
  ilford_hp5: [1.00, 1.00, 1.00],
  ilford_delta3200: [1.00, 1.00, 1.00],
  kodak_ektar100: [1.00, 0.86, 0.72],
  fuji_pro400h: [0.96, 0.92, 0.86],
  polaroid_sx70: [1.00, 0.94, 0.88],
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
    grain: 5,
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
  # Four of the nine stocks had no row here and one had none in PUSH_RESPONSE,
  # so reciprocity_failure and push_pull fell through to a hard-coded default
  # and every one of those stocks failed reciprocity like Portra. Reversal
  # stocks in fact fail hardest and fastest -- Velvia is notorious for going
  # green past a few seconds -- which is the opposite of the default they got.
  kodak_vision3_50d: { r: 0.01, g: -0.02, b: 0.08 },
  ektachrome_100: { r: 0.03, g: -0.06, b: 0.13 },
  fuji_velvia: { r: 0.04, g: -0.08, b: 0.15 },
  kodachrome: { r: 0.03, g: -0.05, b: 0.12 },
  ilford_hp5: { r: 0.02, g: -0.05, b: 0.15 },
  ilford_delta3200: { r: 0.03, g: -0.06, b: 0.18 },
  kodak_ektar100: { r: 0.02, g: -0.04, b: 0.11 },
  fuji_pro400h: { r: 0.01, g: -0.03, b: 0.10 },
  polaroid_sx70: { r: 0.04, g: -0.03, b: 0.09 },
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
  kodak_vision3_50d: { g: 1.00, b: 0.95 },
  # HP5 and Delta are the two stocks people actually push, and they take it
  # better than anything else here.
  ilford_hp5: { g: 1.00, b: 0.98 },
  ilford_delta3200: { g: 1.00, b: 0.99 },
  kodak_ektar100: { g: 0.99, b: 0.90 },
  fuji_pro400h: { g: 1.00, b: 0.96 },
  # An instant print cannot be pushed at all; development is fixed by the pod.
  polaroid_sx70: { g: 1.00, b: 1.00 },
}.freeze

# Stocks with integral colored couplers (C-41 process) — get orange mask treatment.
C41_STOCKS = %i[
  kodak_portra kodak_vision3 kodak_vision3_50d kodak_vision3_500t cinestill_800t
  kodak_ektar100 fuji_pro400h
].freeze

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
  ilford_hp5: [255, 255, 255],
  ilford_delta3200: [255, 255, 255],
  kodak_ektar100: [255, 244, 224],
  fuji_pro400h: [255, 247, 233],
  # An instant print has no film base at all — the "base" is the white receiving
  # sheet, and what tints it is the reagent, which reads warm.
  polaroid_sx70: [255, 250, 240],
}.freeze

# Physics-ordered 6-8 step chains: optical_blur → exposure/temp → film_curve
# → chemistry → optical_effect → print → grain. One contrast mode and one
# color temperature approach per preset — no stacking.
PRESETS = {
  # The house grade, and the default: the whole analog path rather than a
  # selection from it.
  #
  # Every other preset here is a look — a choice of some effects over others.
  # This one is the answer to "put the full treatment on it", which is what the
  # tool is for when nobody has asked for a particular film. Eighteen steps
  # against the ten of the richest preset before it.
  #
  # Ordered by where each thing physically happens, not by taste, because the
  # order is the difference between emulation and a stack of filters:
  #
  #   lens        optical_blur, vintage_lens, chromatic_aberration
  #   exposure    spectral_temp, halation      (halation is light reflecting off
  #                                            the film base back through the
  #                                            emulsion, so it precedes the curve)
  #   emulsion    emulsion_defocus             (dye layers sit at different depths)
  #   development film_curve, stock_matrix, dir_coupler, adjacency_effects
  #   negative    orange_mask
  #   print       print_film
  #   tone        skin_protect, shadow_lift, highlight_roll, micro_contrast
  #   grain       last, because it is a property of the emulsion the print sees
  #   gate        film_curl_vignette
  #
  # Safe as a default only because the source-aware scaling above exists: on a
  # photograph that already has texture and contrast, the defocus goes to zero
  # and the curve backs off, so eighteen steps do not mean eighteen
  # subtractions. Against a generated image it runs at full strength, which is
  # what a generated image needs.
  # Two effects are deliberately NOT in this chain, having been measured in it
  # and taken out. chromatic_aberration cost 0.0265 of texture and
  # film_curl_vignette 0.0428 — together two thirds of the picture's
  # micro-detail, and a vignette that dropped mean brightness by 53.8 levels.
  # Both are legitimate and both remain available to the presets that want
  # them; neither belongs in the one grade that runs when nobody chose.
  #
  # They are scaled now rather than merely excluded. When this was written the
  # taper reached only the defocus and the curve, and the paragraph above was
  # the only thing standing between a photograph and the damage — a note is not
  # a mechanism. head[:fringe] and head[:vignette] taper on texture, so the two
  # presets that want each still get them at a strength the source can afford.
  # Keeping them out of the default is a separate decision and it stands.
  #
  # NOTHING IN THIS CHAIN SOFTENS THE PICTURE.
  #
  # optical_blur, emulsion_defocus and vintage_lens are all out — the last one
  # took `lens:` with it, since it was that key's only reader and an unread key
  # is a --vocab-check failure. They are lens simulation, and lens simulation on
  # a frame that was already taken through a lens is invention, not emulation.
  # Softness is also the one artefact that cannot be undone downstream, which
  # makes it the wrong thing for a default to add on the operator's behalf.
  #
  # What is left is tone, colour and emulsion: the H&D curve, dye crosstalk,
  # coupler inhibition, adjacency, the negative's mask, the print stock, and
  # grain. Halation stays and is not a blur — it adds light that bounced off the
  # film base back through the emulsion, which is why it glows rather than
  # smears, and it measured at -0.0001 texture.
  #
  # This is the difference between a film emulation and a lo-fi filter. No lomo,
  # no scan lines, no vignette, no defocus.
  house: { fx: %w[spectral_temp halation film_curve stock_matrix dir_coupler
                  adjacency_effects orange_mask print_film skin_protect
                  shadow_lift highlight_roll micro_contrast grain],
           stock: :kodak_portra, print_stock: :kodak_2383,
           temp: 5400, intensity: 0.80 },

  portrait: { fx: %w[optical_blur spectral_temp film_curve dir_coupler orange_mask skin_protect shadow_lift highlight_roll grain],
              stock: :kodak_portra, temp: 5200, intensity: 0.85 },

  # `lens:` is not metadata: vintage_lens is the effect that reads it. Every
  # preset declaring a lens must include this step, or the look silently loses
  # its named optical character and falls back to an unrelated default.
  indie: { fx: %w[optical_blur spectral_temp vintage_lens film_curve orange_mask shadow_lift split_toning chromatic_aberration grain],
           stock: :kodak_portra, temp: 5400, intensity: 0.85, lens: "helios" },

  polaroid: { fx: %w[optical_blur spectral_temp film_curve faded_print warmth bloom_pro shadow_lift grain],
              stock: :kodak_portra, temp: 5000, intensity: 0.85 },

  landscape: { fx: %w[optical_blur vintage_lens spectral_temp halation film_curve stock_matrix color_separate
                      micro_contrast grain],
               stock: :fuji_velvia, temp: 5800, intensity: 0.90, lens: "zeiss" },

  magic_hour: { fx: %w[optical_blur spectral_temp halation film_curve warmth bloom_pro grain],
                stock: :fuji_velvia, temp: 4800, intensity: 0.90 },

  reversal: { fx: %w[optical_blur spectral_temp halation film_curve stock_matrix color_separate highlight_roll
                     micro_contrast grain],
              stock: :fuji_velvia, temp: 5600, intensity: 0.90 },

  process_e6: { fx: %w[optical_blur spectral_temp push_pull halation film_curve color_separate highlight_roll grain],
                stock: :ektachrome_100, temp: 5600, intensity: 0.90, stops: 2.0 },

  cinematic: { fx: %w[optical_blur spectral_temp halation tonemap film_curve orange_mask shadow_lift print_film grain],
               stock: :kodak_vision3_500t, temp: 4500, intensity: 0.90, print_stock: :kodak_2383 },

  blockbuster: { fx: %w[optical_blur spectral_temp halation tonemap bleach_bypass film_curve orange_mask teal_orange print_film grain],
                 stock: :kodak_vision3, temp: 4800, intensity: 0.90, print_stock: :kodak_2383 },

  golden_age: { fx: %w[optical_blur spectral_temp vintage_lens film_curve orange_mask technicolor warmth dir_coupler bloom_pro grain],
                stock: :kodak_vision3_50d, temp: 5200, intensity: 0.85, lens: "cooke" },

  bleached: { fx: %w[optical_blur spectral_temp tonemap bleach_bypass film_curve split_grade highlight_roll grain],
              stock: :kodak_vision3, temp: 4800, intensity: 0.90 },

  neon_night: { fx: %w[optical_blur spectral_temp push_pull reciprocity_failure halation film_curve orange_mask
                       bloom_pro grain],
                stock: :cinestill_800t, temp: 3200, intensity: 0.90,
                stops: 0.5, exposure_secs: 30.0 },

  tokyo_night: { fx: %w[optical_blur spectral_temp push_pull reciprocity_failure halation film_curve orange_mask
                        teal_orange grain],
                 stock: :cinestill_800t, temp: 3000, intensity: 0.90,
                 stops: 1.0, exposure_secs: 45.0 },

  tungsten: { fx: %w[optical_blur spectral_temp reciprocity_failure halation film_curve orange_mask push_pull
                     shadow_lift grain],
              stock: :kodak_vision3_500t, temp: 3200, intensity: 0.90,
              stops: 0.3, exposure_secs: 8.0 },

  street: { fx: %w[optical_blur spectral_temp tonemap bleach_bypass push_pull film_curve adjacency_effects shadow_lift micro_contrast grain],
            stock: :tri_x, temp: 5600, intensity: 0.90, stops: 1.0 },

  war_doc: { fx: %w[optical_blur spectral_temp tonemap push_pull film_curve bleach_bypass green_push grain],
             stock: :tri_x, temp: 5600, intensity: 0.90, stops: 2.0 },

  silver_gelatin: { fx: %w[optical_blur spectral_temp film_curve push_pull adjacency_effects shadow_lift highlight_roll grain],
                    stock: :tri_x, temp: 5600, intensity: 0.85, stops: 0.5 },

  lith: { fx: %w[optical_blur spectral_temp film_curve push_pull lith_print split_toning grain],
          stock: :tri_x, temp: 5600, intensity: 0.90, stops: 1.5 },

  noir: { fx: %w[optical_blur spectral_temp tonemap push_pull film_curve bleach_bypass desaturate shadow_lift grain],
          stock: :tri_x, temp: 5600, intensity: 0.90, stops: 2.0 },

  dream: { fx: %w[optical_blur spectral_temp vintage_lens halation film_curve bloom_pro desaturate split_toning grain],
           stock: :ektachrome_100, temp: 5800, intensity: 0.85, lens: "leica" },

  dreamscape: { fx: %w[optical_blur spectral_temp halation film_curve bloom_pro split_toning grain],
                stock: :ektachrome_100, temp: 5800, intensity: 0.85 },

  lo_fi: { fx: %w[optical_blur spectral_temp vintage_lens film_curve push_pull faded_print warmth chromatic_aberration grain],
           stock: :kodak_portra, temp: 4800, intensity: 0.85, lens: "helios" },

  horror: { fx: %w[optical_blur spectral_temp tonemap film_curve bleach_bypass green_push desaturate grain],
            stock: :tri_x, temp: 5600, intensity: 0.90 },

  arctic: { fx: %w[optical_blur spectral_temp tonemap film_curve desaturate bleach_bypass highlight_roll grain],
            stock: :tri_x, temp: 6500, intensity: 0.90 },

  kodachrome_look: { fx: %w[optical_blur spectral_temp halation tonemap film_curve stock_matrix kodachrome_sim dir_coupler grain],
                     stock: :kodachrome, temp: 5600, intensity: 0.90 },

  technicolor_3strip: { fx: %w[optical_blur spectral_temp film_curve stock_matrix technicolor dir_coupler bloom_pro grain],
                        stock: :kodachrome, temp: 5500, intensity: 0.90 },

  cross_process: { fx: %w[optical_blur spectral_temp push_pull film_curve color_separate teal_orange split_toning grain],
                   stock: :fuji_velvia, temp: 5500, intensity: 0.90, stops: 0.5 },

  vintage_chrome: { fx: %w[optical_blur film_curve stock_matrix dir_coupler spectral_temp color_separate split_toning grain],
                    stock: :ektachrome_100, temp: 5200, intensity: 0.85 },

  infrared_look: { fx: %w[optical_blur spectral_temp push_pull infrared film_curve bleach_bypass highlight_roll grain],
                   stock: :tri_x, temp: 5600, intensity: 0.90, stops: 0.5 },

  cyanotype_look: { fx: %w[optical_blur spectral_temp film_curve desaturate cyanotype shadow_lift grain],
                    stock: :tri_x, temp: 6000, intensity: 0.85 },

  analog_scan: { fx: %w[optical_blur spectral_temp film_curve grain scan_noise dust_and_hair newton_rings],
                 stock: :kodak_portra, temp: 5200, intensity: 0.80 },

  aged_chrome: { fx: %w[optical_blur spectral_temp film_curve dye_fade selenium_tone faded_print grain],
                 stock: :ektachrome_100, temp: 5600, intensity: 0.85, age: 0.60 },

  # LENSES[:anamorphic] was the one entry in that table no preset reached at
  # all. The preset named after it is the obvious home for it.
  anamorphic: { fx: %w[optical_blur vintage_lens longitudinal_ca spectral_temp halation tonemap film_curve anamorphic_flare grain],
                stock: :kodak_vision3_500t, temp: 4200, intensity: 0.90, lens: "anamorphic" },

  contact_print: { fx: %w[optical_blur spectral_temp adjacency_effects film_curve darkroom_print shadow_lift grain],
                   stock: :tri_x, temp: 5600, intensity: 0.85 },

  aged_kodachrome: { fx: %w[optical_blur spectral_temp film_curve dye_fade kodachrome_sim dir_coupler grain],
                     stock: :kodachrome, temp: 5600, intensity: 0.88, age: 0.50 },

  wide_angle: { fx: %w[optical_blur lens_distortion spectral_temp halation film_curve grain],
                stock: :fuji_velvia, temp: 5800, intensity: 0.90, k1: -0.14 },

  cinema_scan: { fx: %w[optical_blur spectral_temp longitudinal_ca halation tonemap film_curve orange_mask bokeh_rendering print_film grain],
                 stock: :kodak_vision3, temp: 4600, intensity: 0.90, print_stock: :kodak_2383 },

  diffraction: { fx: %w[optical_blur spectral_temp diffraction_blur film_curve micro_contrast grain],
                 stock: :fuji_velvia, temp: 5600, intensity: 0.85, f_number: 22.0 },

  nitrate: { fx: %w[optical_blur spectral_temp film_curve dye_fade faded_print adjacency_effects grain scan_noise],
             stock: :kodachrome, temp: 4800, intensity: 0.85, age: 0.80 },

  fiber_print: { fx: %w[optical_blur spectral_temp adjacency_effects darkroom_print paper_texture dodgeburn_artifacts grain],
                 stock: :tri_x, temp: 5600, intensity: 0.85 },

  expired: { fx: %w[optical_blur spectral_temp film_curve expired_film gate_weave],
             stock: :kodak_portra, temp: 5200, intensity: 0.90, age: 0.65 },

  # The two presets below carry effects recovered from this file's first
  # generation. Added as NEW presets rather than folded into the fifty-eight
  # that existed at the time, because those were tuned looks and a recovered effect is
  # not a reason to move one.
  #
  # A cassette that has been opened, or a back that no longer seals. The leak
  # arrives from a frame edge and fogs the shadows first, so it belongs after
  # the curve — the fog is light the emulsion received, not a grade applied to
  # what it recorded.
  light_leak: { fx: %w[optical_blur spectral_temp halation film_curve light_leaks grain],
                stock: :kodak_portra, temp: 5600, intensity: 0.85 },

  # Daylight printed as moonlight. A convention rather than a process — real
  # moonlight is neither this blue nor this directional, and an audience reads
  # it as night because film has always shown it this way.
  day_for_night: { fx: %w[optical_blur spectral_temp film_curve day_for_night shadow_lift grain],
                   stock: :kodak_vision3_500t, temp: 4100, intensity: 0.85 },

  reticulated: { fx: %w[optical_blur spectral_temp film_curve reticulation fixing_bath_fog grain],
                 stock: :tri_x, temp: 5600, intensity: 0.80 },

  ortho: { fx: %w[optical_blur spectral_temp ortho_film film_curve adjacency_effects grain],
           stock: :tri_x, temp: 5600, intensity: 0.85 },

  tilt_shift_look: { fx: %w[optical_blur spectral_temp halation film_curve tilt_shift grain],
                     stock: :kodak_portra, temp: 5200, intensity: 0.80 },

  haunted: { fx: %w[optical_blur spectral_temp expired_film reticulation fixing_bath_fog lens_ghosting gate_weave grain],
             stock: :kodachrome, temp: 4600, intensity: 0.90, age: 0.80 },

  quality_uplift: { fx: %w[spectral_temp adaptive_contrast film_shoulder clarity edge_aware_nr selective_sharpen film_curve grain],
                    stock: :kodak_portra, temp: 5600, intensity: 0.75 },

  vhs_tape: { fx: %w[optical_blur spectral_temp vhs_luma_bleed vhs_chroma_delay vhs_tracking_noise vhs_interlace_comb vhs_head_switch_band],
              stock: :kodak_portra, temp: 6500, intensity: 0.80 },

  crt_broadcast: { fx: %w[optical_blur spectral_temp crt_phosphor_bloom crt_scanlines hi8_chroma_noise],
                   stock: :kodak_portra, temp: 6500, intensity: 0.75 },

  camcorder_glitch: { fx: %w[optical_blur spectral_temp vhs_chroma_delay minidv_block_dropout vhs_tracking_noise crt_scanlines],
                      stock: :kodak_portra, temp: 6500, intensity: 0.85 },

  # ==========================================================================
  # 2026-07-30. One preset per new stock and per new lens, so nothing added
  # above is reachable only by hand-editing a recipe.
  # ==========================================================================

  # HP5 in daylight, developed normally, printed straight. The plainest thing
  # this file can do, and there was no preset for it: every black-and-white
  # preset here bleaches, pushes, tones, solarises or otherwise intervenes.
  # print_stock: kodak_2302 is the black-and-white print film in PRINT_STOCKS,
  # and until this preset no chain projected onto it — the table had two entries
  # and one reader.
  reportage: { fx: %w[optical_blur spectral_temp vintage_lens film_curve adjacency_effects micro_contrast print_film grain],
               stock: :ilford_hp5, temp: 5600, intensity: 0.85, lens: "summicron", print_stock: :kodak_2302 },

  # Delta 3200 at night, which is the only place it makes sense. Grain is not a
  # side effect of this preset, it is the subject.
  available_darkness: { fx: %w[optical_blur spectral_temp film_curve push_pull shadow_lift adjacency_effects grain],
                        stock: :ilford_delta3200, temp: 3400, intensity: 0.90, stops: 1.5 },

  # Ektar, with the colour matrix doing the work its data was written for.
  saturated_negative: { fx: %w[optical_blur spectral_temp vintage_lens film_curve stock_matrix orange_mask color_separate micro_contrast grain],
                        stock: :kodak_ektar100, temp: 5500, intensity: 0.90, lens: "zeiss" },

  # Pro 400H: cool, pastel, and the only preset here that does not warm up.
  pastel_portrait: { fx: %w[optical_blur spectral_temp vintage_lens film_curve stock_matrix orange_mask skin_protect highlight_roll grain],
                     stock: :fuji_pro400h, temp: 6200, intensity: 0.80, lens: "soft_focus" },

  # An SX-70 print: milky blacks, a ceiling on the highlights, and the whole
  # thing a little faded before it has finished developing.
  instant_pack: { fx: %w[optical_blur spectral_temp film_curve stock_matrix faded_print film_base_density bloom_pro grain],
                  stock: :polaroid_sx70, temp: 5800, intensity: 0.85, age: 0.35 },

  # The Petzval swirl, as far as a per-pixel pipeline can carry it: centre
  # holding, everything else glowing and coming apart at the edges.
  swirl_portrait: { fx: %w[optical_blur spectral_temp vintage_lens film_curve orange_mask film_curl_vignette skin_protect grain],
                    stock: :kodak_portra, temp: 5200, intensity: 0.85, lens: "petzval" },

  # Uncoated pre-war glass: no anti-reflection coating, so every highlight
  # veils the shadows next to it and contrast is a suggestion.
  uncoated_glass: { fx: %w[optical_blur spectral_temp vintage_lens film_curve shadow_lift adjacency_effects grain],
                    stock: :ilford_hp5, temp: 5400, intensity: 0.85, lens: "uncoated" },

  # A plastic meniscus and expired consumer film, which is most of what the
  # word "lomo" ever meant.
  plastic_lens: { fx: %w[optical_blur spectral_temp vintage_lens film_curve expired_film film_curl_vignette grain],
                  stock: :fuji_pro400h, temp: 5000, intensity: 0.85, lens: "lomo", age: 0.5 },

  # Radioactive thorium glass yellows with age; a Takumar shot today is warmer
  # than the one that left the factory.
  takumar_sun: { fx: %w[optical_blur spectral_temp vintage_lens film_curve stock_matrix orange_mask warmth grain],
                 stock: :kodak_ektar100, temp: 5000, intensity: 0.85, lens: "takumar" },

  legacy_polaroid: { fx: %w[spectral_temp film_curve faded_print polaroid_frame], stock: :polaroid_sx70,
                     temp: 5800, intensity: 0.82 },

  legacy_super8: { fx: %w[spectral_temp film_curve super8_flicker film_scratches], stock: :kodak_vision3_50d,
                   temp: 5600, intensity: 0.78 },

  legacy_cinemascope: { fx: %w[spectral_temp halation film_curve print_film cinemascope_bars], stock: :kodak_vision3_500t,
                        temp: 4500, intensity: 0.78, print_stock: :kodak_2383 },

  legacy_halftone: { fx: %w[spectral_temp film_curve halftone_print], stock: :kodak_portra,
                     temp: 5400, intensity: 0.72 },

  legacy_vhs: { fx: %w[spectral_temp vhs_degrade], stock: :kodak_portra,
                temp: 6500, intensity: 0.72 },

  legacy_anamorphic: { fx: %w[spectral_temp halation film_curve print_film anamorphic_simulation], stock: :kodak_vision3_500t,
                       temp: 4200, intensity: 0.80, print_stock: :kodak_2383 },

  legacy_tape: { fx: %w[spectral_temp film_curve tape_degradation color_fade], stock: :kodak_portra,
                 temp: 5200, intensity: 0.70 },

  legacy_frame: { fx: %w[spectral_temp film_curve frame_distortion film_scratches], stock: :ilford_hp5,
                  temp: 5600, intensity: 0.70 },

  legacy_sprocket: { fx: %w[spectral_temp film_curve sprocket_holes], stock: :kodak_portra,
                     temp: 5400, intensity: 0.80 },

  legacy_flare: { fx: %w[spectral_temp film_curve lens_flare], stock: :kodak_vision3,
                  temp: 5400, intensity: 0.70 },

  legacy_soft_focus: { fx: %w[spectral_temp film_curve soft_focus grain], stock: :kodak_portra,
                       temp: 5200, intensity: 0.72 },

  legacy_scratch_print: { fx: %w[spectral_temp film_curve film_scratches color_fade], stock: :kodachrome,
                          temp: 5400, intensity: 0.68 },

  legacy_cross_process: { fx: %w[spectral_temp film_curve cross_process film_halation grain], stock: :fuji_velvia,
                          temp: 5500, intensity: 0.72 },

  legacy_golden_hour: { fx: %w[spectral_temp film_curve golden_hour_glow], stock: :kodak_portra,
                        temp: 4800, intensity: 0.72 },

  legacy_lomo: { fx: %w[spectral_temp vintage_lens film_curve lomo grain], stock: :fuji_pro400h,
                 temp: 5000, intensity: 0.70, lens: "lomo" },

  legacy_sepia: { fx: %w[spectral_temp film_curve sepia grain], stock: :ilford_hp5,
                  temp: 5400, intensity: 0.68 },

  legacy_glitch: { fx: %w[spectral_temp glitch], stock: :kodak_portra,
                   temp: 6500, intensity: 0.68 },

  dilla_vinyl_hot: { fx: %w[spectral_temp dilla_head_bump dilla_vinyl_bandlimit dilla_phasy grain],
                     stock: :kodak_portra, temp: 5000, intensity: 0.72 },

  dilla_summing_phasy: { fx: %w[spectral_temp dilla_head_bump dilla_phasy film_curve grain],
                         stock: :kodak_ektar100, temp: 5200, intensity: 0.70 },

  dilla_tape: { fx: %w[spectral_temp dilla_head_bump dilla_tape_saturation dilla_vinyl_bandlimit grain],
                stock: :kodak_vision3_500t, temp: 4700, intensity: 0.74 },

  dilla_acetate: { fx: %w[spectral_temp dilla_head_bump dilla_tape_saturation dilla_vinyl_bandlimit film_curve],
                   stock: :fuji_pro400h, temp: 4900, intensity: 0.68 },
}.freeze

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
  cluster = Vips::Image.gaussnoise(width, height, sigma: GRAIN_LOGNORM_SIGMA, mean: 0.0, seed: seed)
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

# OLPF (optical low-pass filter) simulation. Two-gaussian PSF: sharp core (84%)
# + wide skirt (16%) matches the Lorentzian wings measured on real lens MTFs.
# Below this the lens is sharper than the sampling grid and there is nothing to
# simulate. Needed because of the floors below: they keep gaussblur off zero,
# and in doing so they also meant a sigma scaled down toward nothing still blurred
# at full strength. Asking for a tenth of the defocus produced all of it, so the
# source-aware scaling in preset() had no effect here until this existed.
OPTICAL_BLUR_FLOOR = 0.12

# Light striking the film outside the gate.
#
# Recovered from the first generation of this file, and rebuilt rather than
# restored. The original drew two to eight filled circles at random coordinates,
# which is not what a light leak is: light enters at a cassette seam, a failing
# door hinge or the film gate, so it arrives from a FRAME EDGE and falls off
# inward. A disc in the middle of the picture has no physical account at all.
#
# Built as a distance ramp from one edge, raised to a power for the falloff and
# added rather than blended, because fogging is additive exposure — the emulsion
# receives light it should not have, and the shadows go first. That is also why
# it lifts blacks far more visibly than highlights without any explicit masking.
#
# The warm colour is not a style choice. A leak is usually red-to-orange because
# the film base and the cassette felt pass long wavelengths most readily, and
# because the red-sensitive layer sits deepest and takes the most stray light.
#
# Seeded through postpro_seed, so which edge and how wide are reproducible. The
# original called bare rand() and could not be reproduced twice.
LEAK_TINT = [1.00, 0.62, 0.34].freeze

def light_leaks(image, intensity = 0.5, edge: nil)
  return image if intensity <= 0

  picker = Random.new(postpro_seed(31))
  edge ||= %i[left right top bottom][picker.rand(4)]
  # How far across the frame the fog reaches: a seam leak is narrow, a failing
  # back is wide.
  reach = 0.18 + picker.rand * 0.22

  w = image.width
  h = image.height
  # A 0..1 ramp that is 1 at the chosen edge and 0 by `reach` across the frame.
  ramp =
    case edge
    when :left   then Vips::Image.xyz(w, h)[0].linear(-1.0 / (w * reach), 1.0)
    when :right  then Vips::Image.xyz(w, h)[0].linear(1.0 / (w * reach), 1.0 - (1.0 / reach))
    when :top    then Vips::Image.xyz(w, h)[1].linear(-1.0 / (h * reach), 1.0)
    else              Vips::Image.xyz(w, h)[1].linear(1.0 / (h * reach), 1.0 - (1.0 / reach))
    end
  ramp = clamp01(ramp)
  # Squared falloff: a leak has a soft core and a long tail, not a linear wedge.
  ramp = (ramp**2.2) * (255.0 * intensity * 0.55)

  bands = LEAK_TINT.map { |t| ramp * t }
  safe_cast(image.cast("float") + Vips::Image.bandjoin(bands))
rescue StandardError => e
  $logger.error "light_leaks: #{e.message}"; image
end

# Underexposing and cooling a daylight frame to read as moonlight.
#
# Also recovered, and this one was already close to right, because it models a
# real practice rather than an artefact: shoot in daylight, stop down hard,
# print cold. Kept as it was in substance — darken, then lift blue — with the
# random component removed so the same call gives the same result, and the blue
# lift moved onto the shadows where moonlight actually reads.
#
# Not a physical process, unlike everything around it. It is a convention: an
# audience reads cold-and-dark as night because film has always shown it that
# way, and real moonlight is neither as blue nor as directional as this.
def day_for_night(image, intensity = 0.6)
  return image if intensity <= 0

  darkened = image.cast("float").linear([1.0 - (0.42 * intensity)], [-18.0 * intensity])
  r, g, b = darkened.bandsplit
  # Weight the cast toward the low end. A uniform blue gain tints the highlights
  # too, which reads as a filter over a daylight shot rather than as night.
  luma = darkened.colourspace("b-w").cast("float") / 255.0
  shadow_weight = clamp01(luma.linear(-1, 1))
  b = b + (shadow_weight * 26.0 * intensity)
  g = g + (shadow_weight * 6.0 * intensity)
  safe_cast(Vips::Image.bandjoin([r, g, b]))
rescue StandardError => e
  $logger.error "day_for_night: #{e.message}"; image
end

def optical_blur(image, sigma = 0.6)
  return image if sigma < OPTICAL_BLUR_FLOOR

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
  data = STOCKS[stock] || STOCKS[:kodak_portra]
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
  blurred = image.gaussblur(2.0)
  high_pass = image.cast("float") - blurred.cast("float")
  gray = image.colourspace("grey16").colourspace("srgb").cast("float")
  img_f = image.cast("float") / 255.0
  # Lateral inhibition: each dye layer's development byproducts diffuse σ≈0.8px
  # and suppress adjacent layers — desaturates pure hues, sharpens colour edges.
  #
  # The diffusion is on the INHIBITOR, not on the picture. It used to be on
  # both: every band of the output was built from `r_d, g_d, b_d`, the blurred
  # channels, so the whole frame was replaced by a σ=0.8 gaussian of itself and
  # only `strength * 0.5` of the high-pass came back — about 5% at the strength
  # `portrait` calls it with. On a photograph that cost 52% of the picture's
  # texture in one step, which is more than every other effect in the chain
  # combined, while the log reported spread-2.38 and looked unremarkable.
  #
  # It also inverted what the line above claims. A layer's own density is sharp;
  # what reaches it from its neighbours has diffused. Subtracting a blurred
  # neighbour from a sharp channel IS an unsharp mask, so written this way the
  # edge effect falls out of the physics instead of being bolted on after it —
  # which is what "sharpens colour edges" meant.
  r_s, g_s, b_s = img_f.bandsplit
  r_d, g_d, b_d = [r_s, g_s, b_s].map { |ch| ch.gaussblur(0.8) }
  inhibition = Vips::Image.bandjoin([
    r_s - g_d * (0.08 * strength) - b_d * (0.04 * strength),
    g_s - r_d * (0.12 * strength) - b_d * (0.07 * strength),
    b_s - r_d * (0.06 * strength) - g_d * (0.10 * strength),
  ])
  inhibited = clamp01(inhibition) * 255.0
  desatd = inhibited * (1.0 - strength * 0.3) + gray * (strength * 0.3)
  safe_cast((desatd + high_pass * (strength * 0.5)).cast("uchar"))
rescue StandardError => e
  $logger.error "dir_coupler: #{e.message}"; image
end

# Bleach bypass leaves the silver in, and silver is neutral density. On the
# print, Kodak's description: shadows darker and richer, contrast up, colour
# muted. Density adds in log space, so in transmittance every channel is
# multiplied by the scene's own luminance to a power: out = in * Y^k. Shadows,
# where Y is small, crush most; highlights, where Y is near 1, hold. The dyes
# keep their differences while the silver greys them, so saturation falls, and
# a little more is taken to match the muted colour. A screen blend with a lifted
# shadow floor, the tempting shortcut, makes the picture lighter and milkier,
# the opposite of the look, and costs more structure than any other step.
BLEACH_SILVER_POWER = 0.8
BLEACH_DESATURATION = 0.3

def bleach_bypass(image, intensity = 0.5)
  linear = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  luma = clamp01(r * 0.2126 + g * 0.7152 + b * 0.0722)
  silver = ((luma > 1e-4).ifthenelse(luma, 1e-4)**(BLEACH_SILVER_POWER * intensity))
  dense = linear * silver.bandjoin([silver, silver])
  grey = (dense.extract_band(0) * 0.2126 + dense.extract_band(1) * 0.7152 + dense.extract_band(2) * 0.0722)
  share = BLEACH_DESATURATION * intensity
  muted = dense * (1.0 - share) + grey.bandjoin([grey, grey]) * share
  safe_cast(clamp01(muted).colourspace("srgb"))
rescue StandardError => e
  $logger.error "bleach_bypass: #{e.message}"; image
end

# Push and pull are development, not exposure. A push rates the film faster,
# underexposing it by `stops`, and develops longer to make up for it: midtones
# come back to about where they belong, the curve steepens so contrast rises,
# thin shadows stay thin, and the densest highlights block up toward a shoulder
# instead of clipping. A pull is the reverse, a softer curve. Per channel the
# steepening follows PUSH_RESPONSE, since the layers develop at different rates.
# This used to multiply linear light by 2^stops and clip, which on noir's
# two-stop push was four times the exposure and burnt highlights: a gain, which
# no lab ever applied.
PUSH_GAMMA_PER_STOP = 0.15
PUSH_PIVOT = 0.18
PUSH_SHOULDER = 0.80

def push_pull(image, stops = 1.0, stock = :kodak_portra)
  resp = PUSH_RESPONSE[stock] || { g: 1.00, b: 0.94 }
  linear = image.colourspace("scrgb")
  developed = linear.bandsplit.zip([1.0, resp[:g], resp[:b]]).map do |channel, response|
    gamma = (1.0 + PUSH_GAMMA_PER_STOP * stops * response).clamp(0.4, 2.0)
    positive = (channel > 1e-6).ifthenelse(channel, 1e-6)
    push_shoulder(((positive / PUSH_PIVOT)**gamma) * PUSH_PIVOT)
  end
  safe_cast(Vips::Image.bandjoin(developed).colourspace("srgb"))
rescue StandardError => e
  $logger.error "push_pull: #{e.message}"; image
end

# Above the shoulder density builds ever more slowly, an exponential approach
# to white, so a pushed highlight blocks up rather than clipping.
def push_shoulder(value)
  head = 1.0 - PUSH_SHOULDER
  over = value - PUSH_SHOULDER
  rolled = over.linear(-1.0 / head, 0).exp.linear(-head, PUSH_SHOULDER + head)
  (over > 0).ifthenelse(rolled, value)
end

# Split toning: shadow and highlight color casts weighted by luminance.
# shadow_rgb / hi_rgb are [R,G,B] triplets in 0-255.
def split_toning(image, shadow_rgb = [45, 35, 60], hi_rgb = [255, 240, 210], intensity = 0.30)
  luma = image.colourspace("b-w").cast("float") / 255.0
  img_f = image.cast("float") / 255.0
  s_clr = (Vips::Image.black(image.width, image.height, bands: 3) + shadow_rgb).cast("float") / 255.0
  h_clr = (Vips::Image.black(image.width, image.height, bands: 3) + hi_rgb).cast("float") / 255.0
  s_w = luma.linear(-1, 1) * intensity * 0.55
  h_w = luma               * intensity * 0.55
  result = img_f + (s_clr - img_f) * s_w + (h_clr - img_f) * h_w
  safe_cast(clamp01(result) * 255.0)
rescue StandardError => e
  $logger.error "split_toning: #{e.message}"; image
end

# Three-way color corrector: independent shadow / midtone / highlight casts.
def split_grade(image, shadow_rgb = [30, 40, 60], mid_rgb = [255, 255, 248], hi_rgb = [255, 245, 220], intensity: 0.25)
  luma = image.colourspace("b-w").cast("float") / 255.0
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
  img_f = image.cast("float") / 255.0
  multiplied = img_f.linear([r_m, g_m, b_m], [0, 0, 0])
  result = img_f * (1.0 - opacity) + multiplied * opacity
  safe_cast(clamp01(result) * 255.0)
rescue StandardError => e
  $logger.error "dual_base_density: #{e.message}"; image
end

# Reciprocity failure: long exposures exhibit non-linear response — blue
# channel lags most. Per-stock shifts from RECIPROCITY_SHIFT calibrate the
# green-magenta crossover and blue lag to measured sensitometry data.
def reciprocity_failure(image, exposure_seconds = 10.0, stock = :cinestill_800t)
  ev = Math.log2([exposure_seconds, 1.0].max) / 10.0
  cs = RECIPROCITY_SHIFT[stock] || RECIPROCITY_SHIFT[:cinestill_800t]
  linear = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  luma = r * 0.2126 + g * 0.7152 + b * 0.0722
  dark_w = luma.linear(-1, 1)
  result = Vips::Image.bandjoin([
    r + dark_w * ev * 0.03 + (ev * cs[:r]),
    g + dark_w * ev * 0.02 + (ev * cs[:g]),
    b + (ev * 0.15) + dark_w * ev * 0.05 + (ev * cs[:b]),
  ])
  safe_cast(clamp01(result).colourspace("srgb"))
rescue StandardError => e
  $logger.error "reciprocity_failure: #{e.message}"; image
end

# Dreamy soft cross-fade: soft-light blend of a blurred copy over the image.
def cross_fade(image, intensity = 0.4)
  blur_f = image.gaussblur(12.0).cast("float") / 255.0
  img_f = image.cast("float") / 255.0
  screen = (img_f.linear(-1, 1) * blur_f.linear(-1, 1)).linear(-1, 1)
  soft = (blur_f < 0.5).ifthenelse(img_f * blur_f * 2.0, screen)
  result = img_f * (1.0 - intensity) + soft * intensity
  safe_cast(clamp01(result) * 255.0)
rescue StandardError => e
  $logger.error "cross_fade: #{e.message}"; image
end

# Infrared simulation: green channel → bright (foliage), blue → dark (sky).
# Heavy green mix approximates IR film's extended-red/near-IR sensitivity.
def infrared(image, intensity = 0.8)
  r, g, b = image.cast("float").bandsplit
  ir = r * 0.20 + g * 0.80 + (b > 0).ifthenelse(b, 0).linear(-1, 0) * 0.15
  ir = (ir > 0).ifthenelse(ir, 0)
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
  luma = image.colourspace("b-w").cast("float") / 255.0
  r = luma * (255 - shadow[0]) + shadow[0]
  g = luma * (255 - shadow[1]) + shadow[1]
  b = luma * (255 - shadow[2]) + shadow[2]
  cyan = Vips::Image.bandjoin([r, g, b])
  result = image.cast("float") * (1.0 - intensity) + cyan * intensity
  safe_cast(result.cast("uchar"))
rescue StandardError => e
  $logger.error "cyanotype: #{e.message}"; image
end

# Lith printing: aggressive contrast, warm sepia shadows, near-white highlights.
def lith_print(image, intensity = 0.80)
  gray = image.colourspace("b-w").cast("float") / 255.0
  hi = clamp01(gray ** 0.55 * 1.1)
  s_w = (gray.linear(-1, 1) ** 2.0) * 255.0
  r = hi * 255.0 + s_w * 0.12
  g = hi * 255.0 - s_w * 0.04
  b = hi * 255.0 - s_w * 0.16
  lith = Vips::Image.bandjoin([r, g, b])
  result = image.cast("float") * (1.0 - intensity) + lith * intensity
  safe_cast(result.cast("uchar"))
rescue StandardError => e
  $logger.error "lith_print: #{e.message}"; image
end

# Technicolor three-strip dye transfer printed each colour record with its own
# pure dye, so colours separated and grew dense rather than merely saturated,
# and the three matrices never registered perfectly. Approximated by stronger
# separation (the crosstalk removal color_separate does), a chroma lift in Lab
# that eases off where colour is already strong, and the one-pixel misregister.
# A global HSV saturation boost is the Photoshop slider, not the process: it
# brightens saturated colours and drags neutrals with them.
TECHNICOLOR_CHROMA_LIFT = 0.35
TECHNICOLOR_CHROMA_KNEE = 60.0

def technicolor(image, intensity = 0.60)
  r, g, b = image.bandsplit
  registered = Vips::Image.bandjoin([r.embed(1, 0, image.width, image.height), g,
                                     b.embed(-1, 1, image.width, image.height)])
  separated = color_separate(registered, intensity)
  l, a, bb = clamp01(separated.cast("float") / 255.0).linear(255.0, 0).cast("uchar")
             .copy(interpretation: :srgb).colourspace(:lab).bandsplit
  chroma = ((a * a) + (bb * bb))**0.5
  gain = (chroma.linear(1.0 / TECHNICOLOR_CHROMA_KNEE, 1.0)**-1).linear(TECHNICOLOR_CHROMA_LIFT * intensity, 1.0)
  dyed = l.bandjoin([a * gain, bb * gain]).copy(interpretation: :lab).colourspace(:srgb)
  safe_cast(image.cast("float") * (1.0 - intensity) + dyed.cast("float") * intensity)
rescue StandardError => e
  $logger.error "technicolor: #{e.message}"; image
end

# Kodachrome simulation: steep per-channel H&D curve + external coupler saturation.
def kodachrome_sim(image, intensity = 0.70)
  result = film_curve(image, :kodachrome, intensity * 0.85)
  hsv = result.colourspace("hsv")
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
  cyan_fade = age * 0.65
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
  edge = image.cast("float") - blurred.cast("float")
  result = clamp01((image.cast("float") - edge * (intensity * 0.45)) / 255.0) * 255.0
  safe_cast(result)
rescue StandardError => e
  $logger.error "adjacency_effects: #{e.message}"; image
end

# Longitudinal (axial) chromatic aberration: wavelengths focus at different depths.
# Blue focuses short of the plane; green slightly soft; red sharpest at the focal plane.
# Axial chromatic aberration: a lens focuses blue in front of the sensor and
# red behind it, so at any one focus setting the channels are not equally sharp.
#
# The sigmas were 0.4*strength and 0.9*strength, which at the strength presets
# actually pass (0.5) come to 0.2px and 0.45px -- both below the 0.3px floor for
# green, and both far below what survives being quantised back to 8-bit. The
# effect ran, raised nothing, and changed not a single pixel value. Widened to
# where the defocus is visible while still reading as a lens rather than a blur.
def longitudinal_ca(image, strength = 0.50)
  r, g, b = image.bandsplit
  g2 = g.gaussblur([0.9 * strength, 0.3].max)
  b2 = b.gaussblur([2.2 * strength, 0.3].max)
  safe_cast(Vips::Image.bandjoin([r, g2, b2]))
rescue StandardError => e
  $logger.error "longitudinal_ca: #{e.message}"; image
end

# Radial lens distortion via mapim. k1 < 0 = barrel (wide-angle); k1 > 0 = pincushion.
# First-order Brown-Conrady model — single coefficient, adequate for cinematic emulation.
def lens_distortion(image, k1 = -0.12)
  w, h = image.width, image.height
  cx, cy = w / 2.0, h / 2.0
  idx = Vips::Image.xyz(w, h)
  xn = (idx.extract_band(0).cast("float") - cx) / cx
  yn = (idx.extract_band(1).cast("float") - cy) / cy
  r2 = xn * xn + yn * yn
  factor = r2.linear([k1], [1.0])
  xs = (xn * factor * cx + cx).cast("float")
  ys = (yn * factor * cy + cy).cast("float")
  image.mapim(Vips::Image.bandjoin([xs, ys]))
rescue StandardError => e
  $logger.error "lens_distortion: #{e.message}"; image
end

# Bokeh highlight ring structure: out-of-focus highlights from lens element edges
# produce an onion-ring artifact. Detected by finding the bright-disk edge and
# adding a warm ring there. Red dominant — lens coatings transmit red more at edges.
def bokeh_rendering(image, intensity = 0.35)
  linear = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  luma = r * 0.2126 + g * 0.7152 + b * 0.0722
  bright = (luma > 0.65).ifthenelse(luma - 0.65, 0)
  ring = (bright.gaussblur(4.0) - bright.gaussblur(2.0)).linear([1], [0])
  ring = (ring > 0).ifthenelse(ring, 0).linear([intensity * 2.5], [0])
  result = Vips::Image.bandjoin([r + ring * 0.90, g + ring * 0.55, b + ring * 0.15])
  safe_cast(clamp01(result).colourspace("srgb"))
rescue StandardError => e
  $logger.error "bokeh_rendering: #{e.message}"; image
end

# Anamorphic lens flare: horizontal blue-cyan streak through brightest highlights.
# Real anamorphic streaks are produced by cylindrical front element edge diffraction.
# Approximated with a wide 1-D horizontal convolution over the highlight mask.
def anamorphic_flare(image, intensity = 0.50)
  w = image.width
  linear = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  luma = r * 0.2126 + g * 0.7152 + b * 0.0722
  bright = (luma > 0.78).ifthenelse(luma - 0.78, 0)
  kw = [w / 10, 31].min
  kw = kw.even? ? kw + 1 : kw
  kernel = Vips::Image.new_from_array([Array.new(kw, 1.0 / kw)])
  streak = bright.conv(kernel, precision: :float)
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
  w, h = image.width, image.height
  cx = w * 0.12
  cy = h * 0.10
  idx = Vips::Image.xyz(w, h)
  xd = idx.extract_band(0).cast("float") - cx
  yd = idx.extract_band(1).cast("float") - cy
  rad = ((xd * xd) + (yd * yd))**0.5
  rings = rad.linear([Math::PI * 2.0 / 28.0], [0]).math(:sin).linear([0.5], [0.5])
  fade = clamp01(rad.linear([-1.2 / [w, h].max], [1.2]))
  mod = (rings - 0.5) * fade * intensity * 0.10
  mod3 = mod.bandjoin([mod, mod])
  safe_cast(clamp01(image.cast("float") / 255.0 + mod3) * 255.0)
rescue StandardError => e
  $logger.error "newton_rings: #{e.message}"; image
end

# Dust specks and hair strands on negative or scanner glass. Procedurally drawn
# at random positions; dark specks more common than bright (dust blocks light).
def dust_and_hair(image, intensity = 0.50)
  w, h = image.width, image.height
  rng = postpro_rng(41)
  overlay = Vips::Image.black(w, h, bands: 3).cast("float")
  (intensity * 14).round.times do
    x = rng.rand(w)
    y = rng.rand(h)
    val = rng.rand > 0.65 ? [230.0, 228.0, 225.0] : [8.0, 6.0, 5.0]
    overlay = overlay.draw_circle(val, x, y, 1 + rng.rand(2), fill: true)
  end
  (intensity * 2).round.times do
    x1 = rng.rand(w)
    y1 = rng.rand(h)
    angle = rng.rand * Math::PI * 2
    len = 30 + rng.rand(110)
    x2 = (x1 + len * Math.cos(angle)).to_i.clamp(0, w - 1)
    y2 = (y1 + len * Math.sin(angle)).to_i.clamp(0, h - 1)
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
  idx = Vips::Image.xyz(w, h)
  xn = (idx.extract_band(0).cast("float") - w * 0.5) / (w * 0.5)
  yn = (idx.extract_band(1).cast("float") - h * 0.5) / (h * 0.5)
  r2 = xn * xn + yn * yn
  vign = clamp01((r2**4.0).linear([intensity * 6.0], [0]))
  v3 = vign.bandjoin([vign, vign])
  # `1.0 - v3` asks Ruby to subtract a Vips::Image from a Float, which raises
  # TypeError -- there is no coercion in that direction. The vips way to write
  # 1 - x is linear(-1, 1), which is what every other inversion in this file
  # uses. Rescued to `image`, so the vignette never darkened a corner.
  safe_cast(clamp01(image.cast("float") / 255.0 * v3.linear([-1.0], [1.0])) * 255.0)
rescue StandardError => e
  $logger.error "film_curl_vignette: #{e.message}"; image
end

# Video/broadcast artifacts — composite tape and CRT display, distinct signal
# path from the film-scan artifacts above (no emulsion, no optics).

# VHS luma bleed: composite video's luma channel has far narrower bandwidth
# than a digital signal, so bright edges smear into the pixels to their right.
def vhs_luma_bleed(image, intensity = 0.40)
  luma = image.colourspace("b-w")
  taps = (3 + intensity * 6).round
  weights = (0...taps).map { |i| Math.exp(-i / (taps * 0.5)) }
  total = weights.sum
  trail = (0...taps).zip(weights).reduce(luma * 0) do |acc, (i, wt)|
    acc + luma.embed(i, 0, image.width, image.height) * (wt / total)
  end
  bleed = rgb_bands(trail) - rgb_bands(luma)
  safe_cast(image.cast("float") + bleed * intensity)
rescue StandardError => e
  $logger.error "vhs_luma_bleed: #{e.message}"; image
end

# VHS chroma delay: the chroma subcarrier lags the luma signal through the tape
# path. Decompose to luma + chroma residual (not a naive per-channel shift —
# that would also drag brightness), delay chroma only, recombine.
def vhs_chroma_delay(image, intensity = 0.40)
  r, g, b = image.cast("float").bandsplit
  luma = r * 0.2126 + g * 0.7152 + b * 0.0722
  shift = (2 + intensity * 10).round
  [r, g, b].map { |c| c - luma }.then do |cr, cg, cb|
    cr_s = cr.embed(shift, 0, image.width, image.height)
    cg_s = cg.embed(shift, 0, image.width, image.height)
    cb_s = cb.embed(shift, 0, image.width, image.height)
    safe_cast(Vips::Image.bandjoin([luma + cr_s, luma + cg_s, luma + cb_s]))
  end
rescue StandardError => e
  $logger.error "vhs_chroma_delay: #{e.message}"; image
end

# VHS head-switching band: the bottom strip of an NTSC/PAL frame is where the
# spinning tape head crosses over — a jittered, noisy band a few scanlines tall.
def vhs_head_switch_band(image, intensity = 0.40)
  w, h = image.width, image.height
  band_h = [(h * 0.02 * (0.5 + intensity)).round, 2].max
  top = image.crop(0, 0, w, h - band_h)
  band = image.crop(0, h - band_h, w, band_h)
  shift = (6 + intensity * 18).round
  jittered = band.embed(postpro_rng(43).rand(-shift..shift), 0, w, band_h)
  noisy = jittered.cast("float") + rgb_bands(Vips::Image.gaussnoise(w, band_h, sigma: 30 * intensity, seed: postpro_seed(43)))
  safe_cast(top.join(clamp01(noisy / 255.0) * 255.0, :vertical))
rescue StandardError => e
  $logger.error "vhs_head_switch_band: #{e.message}"; image
end

# VHS mistracking: worn tape/misaligned heads read each horizontal strip with
# a different lateral offset, worst near the bottom edge of the frame.
def vhs_tracking_noise(image, intensity = 0.40)
  w, h = image.width, image.height
  strips = 24
  strip_h = (h.to_f / strips).ceil
  rows = (0...strips).filter_map do |i|
    y0 = i * strip_h
    sh = [y0 + strip_h, h].min - y0
    next nil if sh <= 0
    strip = image.crop(0, y0, w, sh)
    phase = i.to_f / strips
    shift = (Math.sin(phase * Math::PI * 10) * intensity * 14 * (phase**3)).round
    shift.zero? ? strip : strip.embed(shift, 0, w, sh)
  end
  safe_cast(rows.reduce { |acc, r| acc.join(r, :vertical) })
rescue StandardError => e
  $logger.error "vhs_tracking_noise: #{e.message}"; image
end

# Interlace combing: odd and even fields captured 1/60s apart under motion,
# displaced horizontally from each other when deinterlaced naively.
def vhs_interlace_comb(image, intensity = 0.40)
  w, h = image.width, image.height
  shift = (1 + intensity * 4).round
  shifted = image.embed(shift, 0, w, h)
  odd_row = (Vips::Image.xyz(w, h).extract_band(1).cast("int") & 1).cast("uchar") * 255
  safe_cast((rgb_bands(odd_row) > 0).ifthenelse(shifted, image))
rescue StandardError => e
  $logger.error "vhs_interlace_comb: #{e.message}"; image
end

# CRT phosphor bloom: P22 phosphor persistence glows green-dominant (human eye
# is most sensitive there, and it decays slowest) — distinct from bloom_pro's
# neutral highlight glow.
def crt_phosphor_bloom(image, intensity = 0.5)
  linear = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  excess = (g * 0.9 + r * 0.4 + b * 0.3).linear([1], [-0.55])
  bright = (excess > 0).ifthenelse(excess, 0)
  sigma = [image.width / 60.0, 4.0].max
  glow_r = bright.gaussblur(sigma) * (0.35 * intensity)
  glow_g = bright.gaussblur(sigma * 1.3) * (0.85 * intensity)
  glow_b = bright.gaussblur(sigma * 0.8) * (0.30 * intensity)
  glow = Vips::Image.bandjoin([glow_r, glow_g, glow_b])
  safe_cast(clamp01(linear + glow).colourspace("srgb"))
rescue StandardError => e
  $logger.error "crt_phosphor_bloom: #{e.message}"; image
end

# CRT scanline response: the raster gap between phosphor lines darkens every
# other row — a hard row-parity mask, not a continuous wave (which aliases to
# zero at integer pixel rows for a 2px period).
def crt_scanlines(image, intensity = 0.35)
  w, h = image.width, image.height
  odd_row = (Vips::Image.xyz(w, h).extract_band(1).cast("int") & 1).cast("uchar") * 255
  dark = image.cast("float") * (1.0 - intensity)
  safe_cast((rgb_bands(odd_row) > 0).ifthenelse(image, dark))
rescue StandardError => e
  $logger.error "crt_scanlines: #{e.message}"; image
end

# MiniDV block dropout: a digital tape read error corrupts one DCT macroblock
# at a time — a small solid-fill rectangle, not noise.
def minidv_block_dropout(image, intensity = 0.35)
  w, h = image.width, image.height
  processed = image
  rng = postpro_rng(47)
  (intensity * 6).round.times do
    bw = 8 + rng.rand(w / 12)
    bh = 8 + rng.rand(h / 20)
    x = rng.rand([w - bw, 1].max)
    y = rng.rand([h - bh, 1].max)
    shade = rng.rand < 0.5 ? [20, 20, 24] : [180, 180, 190]
    processed = processed.draw_rect(shade, x, y, bw, bh, fill: true)
  end
  processed
rescue StandardError => e
  $logger.error "minidv_block_dropout: #{e.message}"; image
end

# Hi8 chroma noise: analog Hi8's chroma subcarrier has a much worse SNR than
# its luma — noise piled onto the chroma residual only, luma stays clean.
def hi8_chroma_noise(image, intensity = 0.40)
  r, g, b = image.cast("float").bandsplit
  luma = r * 0.2126 + g * 0.7152 + b * 0.0722
  noise = Vips::Image.gaussnoise(image.width, image.height, sigma: 18 * intensity)
  cr_n = (r - luma) + noise
  cg_n = (g - luma) + noise * 0.6
  cb_n = (b - luma) + noise
  safe_cast(Vips::Image.bandjoin([luma + cr_n, luma + cg_n, luma + cb_n]))
rescue StandardError => e
  $logger.error "hi8_chroma_noise: #{e.message}"; image
end

# Selenium toning: silver areas in shadow zones chemically convert to selenium
# compounds — blue-violet shift in the deepest densities, neutral in highlights.
def selenium_tone(image, intensity = 0.45)
  img_f = image.cast("float") / 255.0
  luma = img_f.colourspace("b-w").cast("float") / 255.0
  shad_w = clamp01(luma.linear([-1], [1])**1.5) * (intensity * 0.65)
  r, g, b = img_f.bandsplit
  result = Vips::Image.bandjoin([clamp01(r + shad_w * 0.12), g, clamp01(b + shad_w * 0.28)])
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
  gray = img_f.colourspace("b-w").colourspace("srgb").cast("float")
  result = clamp01(faded) * (1.0 - age * 0.18) + gray * (age * 0.18)
  safe_cast(clamp01(result) * 255.0)
rescue StandardError => e
  $logger.error "dye_fade: #{e.message}"; image
end

# Darkroom print tone compression. Optical enlarger prints cannot reproduce the full
# DR of a negative. Highlights block at paper Dmax; shadows print lighter than film.
# Slight gamma lift + shadow floor raise compress the tonal scale to print-medium range.
def darkroom_print(image, intensity = 0.50)
  img_f = image.cast("float") / 255.0
  lifted = img_f**(1.0 + (intensity * 0.28))
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
  img_f = image.cast("float") / 255.0
  shadow_w = image.colourspace("b-w").cast("float") / 255.0
  shadow_w = shadow_w.linear(-1, 1)
  r, g, b = img_f.bandsplit
  result = Vips::Image.bandjoin([
    clamp01(r + shadow_w * mask * 0.55),
    clamp01(g + shadow_w * mask * 0.18),
    clamp01(b - shadow_w * mask * 0.35),
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
  # maplut hands back the LUT's interpretation, which is :matrix, so the
  # colourspace("b-w") below was a no-op returning three bands: hi_mask became
  # three bands, the bandjoin made a nine-band image, and `add` raised
  # "not one band or 9 bands" straight into the rescue. cinematic, blockbuster
  # and cinema_scan have therefore never had a print stage at all. Restoring
  # the interpretation is metadata only — the pixels are identical.
  developed = image.maplut(lut).copy(interpretation: image.interpretation)
  img_f = developed.cast("float") / 255.0
  luma = developed.colourspace("b-w").cast("float") / 255.0
  if pdata[:warmth]
    hi_mask = luma ** 2.8
    sh_mask = luma.linear(-1, 1) ** 2.8
    r, g, b = img_f.bandsplit
    img_f = Vips::Image.bandjoin([
      clamp01(r + hi_mask * pdata[:warmth] * 0.8),
      clamp01(g + hi_mask * pdata[:warmth] * 0.15),
      clamp01(b - hi_mask * pdata[:warmth] * 0.35 + sh_mask * (pdata[:cool_shadow] || 0)),
    ])
  end
  if pdata[:grain].to_i > 0
    amp = pdata[:grain] * 0.25 / 255.0
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
  r = (((x * x) + (y * y))**0.5).linear([1.0 / [w, h].max], [0.0])
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
  rng = postpro_rng(53)
  dx = (rng.rand - 0.5) * intensity * w * 0.004
  dy = (rng.rand - 0.5) * intensity * h * 0.002
  x = Vips::Image.xyz(w, h).extract_band(0).linear([1.0], [-dx])
  y = Vips::Image.xyz(w, h).extract_band(1).linear([1.0], [-dy])
  coords = x.bandjoin(y)
  image.mapim(coords, extend: :copy)
rescue StandardError => e
  $logger.error "gate_weave: #{e.message}"; image
end

def lens_ghosting(image, intensity = 0.35)
  w, h = image.width, image.height
  luma = image.colourspace(:b_w)
  threshold = 1.0 - intensity * 0.25
  highlights = (luma > threshold).gaussblur(12 * intensity)
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
  dist = (y_img - focus_y).abs.linear([2.0], [0.0])**1.6
  blur_radius = (intensity * 8).clamp(1, 20).to_f
  blurred = image.gaussblur(blur_radius)
  # Vips::Image#clamp takes one argument, not two; `.clamp(0, 1)` raised
  # ArgumentError and the rescue returned the untouched image. clamp01 is the
  # helper this file already has for exactly this.
  mask = clamp01(dist.linear([intensity], [0.0]))
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

# Every graded picture needs a black and a white. Stacked lifts (shadow_lift,
# film_base_density, faded curves) leave the darkest pixel at 15% grey and the
# frame reads as milk, whatever the stock. The anchor stretches the picture's own
# 0.5th and 99.5th luma percentiles to a printed black and white with one gain on
# all three bands, so hue holds, then bends the midtones with a gentle S-curve.
# POSTPRO_ANCHOR=0 returns the unanchored grade.
ANCHOR_BLACK = 0.03
ANCHOR_WHITE = 0.975
ANCHOR_S_CURVE = 0.30
ANCHOR_MAX_GAIN = 2.4

def anchor_tones(image)
  return image if ENV["POSTPRO_ANCHOR"] == "0"

  luma = image.bandmean.cast("uchar")
  low = luma.percent(0.5)
  high = luma.percent(99.5)
  return image if high - low < 24

  gain = [(ANCHOR_WHITE - ANCHOR_BLACK) / ((high - low) / 255.0), ANCHOR_MAX_GAIN].min
  offset = ANCHOR_BLACK - (low / 255.0 * gain)
  bands = image.bands
  stretched = (image.cast("float") / 255.0).linear([gain] * bands, [offset] * bands)
  stretched = clamp01(stretched)
  smooth = stretched * stretched * stretched.linear([-2.0] * bands, [3.0] * bands)
  bent = stretched + ((smooth - stretched) * ANCHOR_S_CURVE)
  safe_cast(bent * 255.0)
rescue StandardError => e
  $logger.error "anchor_tones: #{e.message}"
  image
end

# A take must stay a grade of its source, judged on what a colourist protects
# rather than on whether the palette moved, since moving it is often the point
# of a look. Measured against the source at TAKE_PROBE_EDGE px, every take must
# keep the source's shapes, keep its black and white points (no more than
# TAKE_MAX_CLIP of the frame newly blown or crushed) and keep at least half its
# tonal spread. Colour may move within the look's own budget: how far overall
# colourfulness may rise, how far neutral greys may be tinted (mean C*), and how
# far skin may turn in hue, which is held tightest, as a colourist holds it on
# the skin-tone line. A take that drains colour on purpose (black and white,
# toned) is judged on shapes and tones alone. Every bound is relative to the
# source, so a low-key photograph is judged against its own darkness; the fixed
# brightness window this replaced refused every faithful grade of one. Default
# budgets sit at the 90th percentile of the light takes of nine photographs
# (2026-10-27): chroma 1.8x, neutral C* 10.4, skin 17.6 degrees, which is how far
# an ordinary film grade moves them. The heavy takes testers called destroyed ran
# 6.7x, 58.6 and 90.8 at the same percentile. Colourfulness is judged only where
# the source has colour to compare against; a grey source is all neutral.
TAKE_PROBE_EDGE = 512.0
TAKE_MIN_STRUCTURE = 0.5
TAKE_MAX_CLIP = 0.05
TAKE_MIN_SPREAD_RATIO = 0.5
TAKE_TONED_CHROMA = 0.6
TAKE_BUDGET = { chroma: 1.8, neutral: 10.0, skin: 18.0 }.freeze
# A named look tints neutrals and lifts colour by design, as its stock and print do.
LOOK_BUDGET = { chroma: 2.2, neutral: 16.0, skin: 22.0 }.freeze
TAKE_MIN_SOURCE_CHROMA = 4.0
# Colourfulness is measured against at least this mean C*, so a frame that is
# mostly grey wall does not turn a modest tint into a tenfold rise.
TAKE_CHROMA_FLOOR = 10.0
# Looks whose point is a new palette get more of it; skin still has a ceiling.
LOOK_BUDGETS = {
  day_for_night: { chroma: 2.6, neutral: 30.0, skin: 30.0 },
  cross_process: { chroma: 2.8, neutral: 18.0, skin: 25.0 },
  tokyo_night: { chroma: 2.8, neutral: 18.0, skin: 20.0 },
  neon_night: { chroma: 2.8, neutral: 18.0, skin: 20.0 },
  infrared_look: { chroma: 2.0, neutral: 16.0, skin: 40.0 },
  technicolor_3strip: { chroma: 2.6, neutral: 12.0, skin: 22.0 },
  golden_age: { chroma: 2.6, neutral: 18.0, skin: 22.0 },
  # A toning process: blue neutrals are its point, and skin goes blue with them.
  cyanotype_look: { chroma: 3.0, neutral: 40.0, skin: 90.0 },
  magic_hour: { chroma: 2.6, neutral: 16.0, skin: 22.0 },
  blockbuster: { chroma: 2.4, neutral: 28.0, skin: 22.0 },
  cinematic: { chroma: 2.2, neutral: 14.0, skin: 22.0 },
}.freeze

# A look's own budget only ever widens the baseline it starts from.
def take_budget(look)
  base = look ? LOOK_BUDGET : TAKE_BUDGET
  base.merge(LOOK_BUDGETS.fetch(look&.to_sym, {})) { |_key, floor, own| [floor, own].max }
end

def check_take_survives!(take, source, look = nil)
  problems = take_problems(take_readings(source, take), take_budget(look))
  return if problems.empty?

  raise ArgumentError, "take refused: #{problems.join(", ")}"
end

def take_problems(readings, budget = TAKE_BUDGET)
  problems = []
  problems << format("structure %.2f", readings[:structure]) if readings[:structure] < TAKE_MIN_STRUCTURE
  problems << format("clipping +%.1f%%", 100 * readings[:clip]) if readings[:clip] > TAKE_MAX_CLIP
  problems << format("spread %.2fx", readings[:spread]) if readings[:spread] < TAKE_MIN_SPREAD_RATIO
  problems.concat(palette_problems(readings, budget))
end

def palette_problems(readings, budget)
  return [] if readings[:chroma] && readings[:chroma] < TAKE_TONED_CHROMA

  problems = []
  problems << format("colour %.1fx", readings[:chroma]) if readings[:chroma].to_f > budget[:chroma]
  problems << format("neutrals tinted C* %.0f", readings[:neutral]) if readings[:neutral].to_f > budget[:neutral]
  problems << format("skin turned %.0f deg", readings[:skin]) if readings[:skin].to_f > budget[:skin]
  problems
end

# Readings of a take against its source: edge-map correlation for structure,
# then palette, clipping and spread. Colour is read on a light blur, so grain
# counts as texture and not as a change of palette.
def take_readings(source, take)
  before = take_probe(source)
  after = take_probe(take)
  after = after.resize(before.width.to_f / after.width, vscale: before.height.to_f / after.height)
  {
    structure: edge_correlation(before, after),
    clip: take_extremes(after) - take_extremes(before),
    spread: take_spread(after) / [take_spread(before), 1.0].max,
  }.merge(take_palette(before.gaussblur(2), after.gaussblur(2)))
end

def take_probe(image)
  rgb = rgb_bands(image).cast(:uchar).copy(interpretation: :srgb)
  rgb.resize(TAKE_PROBE_EDGE / [rgb.width, rgb.height].max).copy_memory
end

def take_luma(image) = image.colourspace(:b_w).extract_band(0).cast(:float)

def edge_correlation(before, after)
  left = take_luma(before).sobel.cast(:float)
  right = take_luma(after).sobel.cast(:float)
  spread = left.deviate * right.deviate
  return 1.0 if spread.zero?

  ((left * right).avg - (left.avg * right.avg)) / spread
end

def take_extremes(image)
  luma = take_luma(image)
  ((luma >= 250).avg + (luma <= 5).avg) / 255.0
end

# A float, because the ratio of two integer spreads divided to zero for every
# take with less spread than its source.
def take_spread(image)
  luma = take_luma(image).cast(:uchar)
  (luma.percent(95) - luma.percent(5)).to_f
end

# Overall chroma ratio; the mean C* a take gives what was neutral grey in the
# source; and the mean hue turn over what was skin. Neutral and skin read nil
# when too little of the frame holds either for the number to mean anything.
SKIN_LAB_HUE = (20.0..75.0)
SKIN_LAB_CHROMA = (8.0..55.0)
SKIN_LAB_LIGHTNESS = (25.0..92.0)
NEUTRAL_CHROMA = 6.0

def take_palette(before, after)
  lightness, chroma_before, hue_before = before.colourspace(:lch).bandsplit
  _, chroma_after, hue_after = after.colourspace(:lch).bandsplit
  {
    chroma: chroma_before.avg < TAKE_MIN_SOURCE_CHROMA ? nil : chroma_after.avg / [chroma_before.avg, TAKE_CHROMA_FLOOR].max,
    neutral: masked_mean(chroma_after, chroma_before < NEUTRAL_CHROMA, 0.02),
    skin: masked_mean(hue_turn(hue_before, hue_after), skin_tones(lightness, chroma_before, hue_before), 0.01),
  }
end

def skin_tones(lightness, chroma, hue)
  [[hue, SKIN_LAB_HUE], [chroma, SKIN_LAB_CHROMA], [lightness, SKIN_LAB_LIGHTNESS]]
    .map { |band, range| (band > range.first) & (band < range.last) }.reduce(:&)
end

def hue_turn(before, after)
  turn = (before - after).abs
  (turn > 180).ifthenelse(turn * -1 + 360, turn)
end

# The mean of `values` over a 0/255 mask, or nil below `min_share` of the frame.
def masked_mean(values, mask, min_share)
  share = mask.avg / 255.0
  return if share < min_share

  (values * (mask / 255)).avg / share
end

# Filmic shoulder + toe: raised shadow floor + soft highlight rolloff.
# Models the analog curve endpoints without stock-specific emulsion data.
def film_shoulder(image, intensity = 0.75)
  toe = intensity * 0.04 * 255.0
  lifted = image.linear([1.0 - intensity * 0.04], [toe])
  highlight_roll(lifted, (220 - (intensity * 20).to_i), intensity * 0.50)
    .then { |rolled| safe_cast(rolled) }
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
  # `(image - quick) + (quick - image)` is a value plus its own negation:
  # identically zero at every pixel, so the mask was always 0 and this returned
  # a plain full-frame blur — measured bit-identical to gaussblur alone. The
  # edge term wants the magnitude of the detail, which is what selective_sharpen
  # sixteen lines below was already corrected to use.
  detail = image.cast("float") - quick.cast("float")
  edge_luma = ((detail.extract_band(0) * 0.299) +
               (detail.extract_band(1) * 0.587) +
               (detail.extract_band(2) * 0.114)).abs
  mask = (edge_luma > (12.0 * (1.0 - strength * 0.5))).ifthenelse(1, 0)
  mask3 = mask.bandjoin([mask, mask])
  safe_cast(image * mask3 + blurred * mask3.linear([-1.0], [1.0]))
rescue StandardError => e
  $logger.error "edge_aware_nr: #{e.message}"; image
end

# Selective sharpening: high-pass at σ=1.2, applied only at high-edge regions.
# Lifts perceived acuity at detail without amplifying noise in smooth areas.
def selective_sharpen(image, intensity = 0.70)
  blurred = image.cast("float").gaussblur(1.2)
  detail = image.cast("float") - blurred
  # edge_diff was `detail + (blurred - image)`, which is (image - blurred) plus
  # its own negation: identically zero, at every pixel, for every image. The
  # mask was therefore always 0, mask3 always 0, and the return value always
  # `image + detail * 0`. Selective sharpening has never sharpened anything --
  # including in quality_uplift, the preset that exists to sharpen.
  #
  # What the mask wants is where detail is LARGE, which is its magnitude.
  edge_luma = ((detail.extract_band(0) * 0.299) +
               (detail.extract_band(1) * 0.587) +
               (detail.extract_band(2) * 0.114)).abs
  mask = (edge_luma > 8).ifthenelse(1, 0)
  mask3 = mask.bandjoin([mask, mask])
  safe_cast(image + detail * mask3 * (intensity * 0.55))
rescue StandardError => e
  $logger.error "selective_sharpen: #{e.message}"; image
end

# Complementary grading as a colourist does it: shadows toward teal, highlights
# toward warm, each by a luminance key, with skin held back by a hue key so
# faces stay faces. It used to apply flat gains to every pixel (red x1.25 + 8,
# blue x1.35), which is a colour cast rather than a grade, and it was the effect
# most associated with destroyed takes (96% against 58% without it, 2026-10-27).
TEAL_SHIFT = [-0.05, 0.015, 0.06].freeze
ORANGE_SHIFT = [0.06, 0.02, -0.05].freeze
TEAL_ORANGE_SKIN_HOLD = 0.85

def teal_orange(image, intensity = 1.0)
  colour = image.cast("float") / 255.0
  luma = clamp01(image.colourspace("b-w").cast("float") / 255.0)
  free = skin_key(image).gaussblur(2).linear(-TEAL_ORANGE_SKIN_HOLD, 1.0) * intensity
  shadows = (luma.linear(-1, 1)**2) * free
  highlights = (luma**2) * free
  shifted = colour.bandsplit.each_with_index.map do |channel, i|
    channel + shadows * TEAL_SHIFT[i] + highlights * ORANGE_SHIFT[i]
  end
  safe_cast(clamp01(Vips::Image.bandjoin(shifted)) * 255.0)
rescue StandardError => e
  $logger.error "teal_orange: #{e.message}"; image
end

# A diffusion filter (a Pro-Mist): glass in front of the lens scatters a share
# of every point's light into a wide kernel. It conserves energy, so it is a mix
# in linear light, (1 - p) * E + p * (K * E), with no threshold: highlights glow
# because they have the most light to spread, shadows lift a little from their
# neighbours, and the frame's total light is unchanged. K is a core, a halo and a
# long bloom, after spektrafilm's Pro-Mist family (weights 0.28, 0.42, 0.30), and
# p rises with strength as theirs does, about 0.35 at full. It used to double the
# whole frame and add its blur back, adding light that was never there, so every
# pixel glowed and the picture went milky.
BLOOM_KERNEL = [[1.0 / 400, 0.28], [1.0 / 60, 0.42], [1.0 / 15, 0.30]].freeze
BLOOM_MIX = 0.35

def bloom_pro(image, intensity = 1.0)
  linear = image.colourspace("scrgb")
  spread = BLOOM_KERNEL.map { |reach, weight| linear.gaussblur([image.width * reach, 0.5].max) * weight }.reduce(:+)
  mix = (BLOOM_MIX * intensity).clamp(0.0, 0.9)
  safe_cast(clamp01(linear * (1.0 - mix) + spread * mix).colourspace("srgb"))
rescue StandardError => e
  $logger.error "bloom_pro: #{e.message}"; image
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
HALATION_TINT_PORTRA = [0.88, 0.12, 0.04].freeze
HALATION_TINT_TRI_X = [0.45, 0.45, 0.45].freeze
HALATION_THRESHOLD = 0.7
# Halation is an annulus. Light that gets through the emulsion reflects off the
# rear face of the base by total internal reflection and re-enters the emulsion
# a base-thickness away, so it re-exposes a ring around the highlight — not a
# halo centred on it. This summed a narrow and a wide Gaussian, which puts the
# most returned light exactly where the highlight already is, the one place it
# cannot land. A difference of Gaussians is the ring; the narrow lobe stays on
# as the scatter that never left the emulsion.
HALATION_SCATTER = 0.25
# A difference of Gaussians keeps a fraction of the energy the sum carried, so
# the strength has to come back somewhere. Measured on a probe carrying a blown
# specular, the summed form peaked at 5 levels on the highlight's own edge and
# this peaks at 7 a little outside it, which is the move that was wanted.
HALATION_GAIN = 2.6

# Halation: resolution-aware σ ≈ width/45 (≈43px at 2K, calibrated from agx
# emulsion measurements). Luma-based bright mask rather than red-only, so
# over-exposed highlights on any channel trigger the halo. Per-channel blur
# radii R>G>>B model wavelength-dependent penetration depth in the emulsion
# stack. Output clamp prevents HDR overshoot from adding solarization.
# This gates on luma > HALATION_THRESHOLD (0.7) in LINEAR scRGB, where 8-bit
# white is 1.0, so it fires on any real highlight. It belongs before
# film_curve, because it is exposure: light returning into the emulsion before
# anything is developed. Run after the curve, which compresses hard, nothing is
# left above the threshold and the step changes nothing while the log reports
# it ran (found with POSTPRO_EXPLAIN=1). Every preset now orders it first.
# The returned light, as a ring of radius sigma plus the scatter that stayed.
def halation_ring(bright, sigma)
  core = bright.gaussblur([sigma * 0.55, 0.3].max)
  ring = bright.gaussblur(sigma * 1.6) - core
  (ring > 0).ifthenelse(ring, 0) + core * HALATION_SCATTER
end

def halation(image, intensity = 1.0, tint: HALATION_TINT_VISION3)
  sigma_r = [image.width / 45.0, 6.0].max.clamp(6.0, 120.0)
  sigma_g = sigma_r * 0.55
  sigma_b = sigma_r * 0.25
  linear = image.colourspace("scrgb")
  r, g, b = linear.bandsplit
  luma = r * 0.2126 + g * 0.7152 + b * 0.0722
  excess = luma.linear([1], [-HALATION_THRESHOLD])
  bright = (excess > 0).ifthenelse(excess, 0) ** 2
  halo = Vips::Image.bandjoin([sigma_r, sigma_g, sigma_b].each_with_index.map do |sigma, band|
    halation_ring(bright, sigma) * (tint[band] * intensity * HALATION_GAIN)
  end)
  safe_cast(clamp01(linear + halo).colourspace("srgb"))
end

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

# How much of a look's intensity each effect gets. A preset or a recipe step
# names one intensity for the whole look; each effect is mixed down from it by
# its own factor here, calibrated per effect, because a colourist runs a look
# below full strength and some effects (a bloom, a bleach) read at a quarter of
# the strength others need. Effects not listed take the intensity as it comes,
# or scale it in their own arm of grade_step where the source also has a say.
EFFECT_MIX = {
  "adaptive_contrast" => 0.70,
  "adjacency_effects" => 0.25,
  "aerial_depth" => 0.45,
  "anamorphic_flare" => 0.50,
  "bleach_bypass" => 0.40,
  "bloom_pro" => 0.25,
  "bokeh_rendering" => 0.35,
  "clarity" => 0.65,
  "color_separate" => 0.55,
  "color_temp" => 0.50,
  "cross_fade" => 0.40,
  "crt_phosphor_bloom" => 0.50,
  "crt_scanlines" => 0.35,
  "darkroom_print" => 0.50,
  "day_for_night" => 0.70,
  "desaturate" => 0.45,
  "dir_coupler" => 0.12,
  "dodgeburn_artifacts" => 0.40,
  "dust_and_hair" => 0.50,
  "edge_aware_nr" => 0.55,
  "film_shoulder" => 0.75,
  "fixing_bath_fog" => 0.30,
  "gate_weave" => 0.40,
  "green_push" => 0.15,
  "halation" => 0.60,
  "hi8_chroma_noise" => 0.40,
  "highlight_roll" => 0.50,
  "infrared" => 0.85,
  "kodachrome_sim" => 0.75,
  "lens_ghosting" => 0.35,
  "light_leaks" => 0.45,
  "lith_print" => 0.75,
  "longitudinal_ca" => 0.50,
  "micro_contrast" => 0.20,
  "minidv_block_dropout" => 0.35,
  "newton_rings" => 0.12,
  "orange_mask" => 0.90,
  "ortho_film" => 0.80,
  "paper_texture" => 0.35,
  "print_film" => 0.70,
  "relight" => 0.55,
  "reticulation" => 0.50,
  "scan_noise" => 0.40,
  "selective_sharpen" => 0.65,
  "selenium_tone" => 0.45,
  "spectral_temp" => 0.50,
  "split_grade" => 0.25,
  "stock_matrix" => 0.85,
  "teal_orange" => 0.80,
  "technicolor" => 0.55,
  "tilt_shift" => 0.70,
  "tonemap" => 0.85,
  "vhs_chroma_delay" => 0.40,
  "vhs_head_switch_band" => 0.40,
  "vhs_interlace_comb" => 0.40,
  "vhs_luma_bleed" => 0.40,
  "vhs_tracking_noise" => 0.40,
  "vintage_lens" => 0.70,
  "warmth" => 0.25,
}.freeze

# One step of a grade, calibrated. Every effect is mixed down from the look's
# intensity by its own factor here, the subtractive ones are scaled by what the
# source arrived with (`head`), and the stock, print stock, stops and the rest
# come from `p`. preset() and recipe() both grade through this, so a random
# take built from a look is that look and not its effects at raw strength:
# measured 2026-10-27, the uncalibrated path ran bloom at four times and bleach
# at two and a half times the strength the presets give them, blurred sharp
# photographs the taper would have spared, and wrecked 69% of its takes.
def grade_step(fx, processed, p, head, owner = "chain")
  level = p[:intensity]
  mix = level * EFFECT_MIX.fetch(fx, 1.0)
  stock = p[:stock]
  case fx
  when "optical_blur"        then optical_blur(processed, 0.5 * head[:blur])
  when "tonemap"             then tonemap(processed, type: p.fetch(:tonemap, :aces2), exposure: p.fetch(:tonemap_ev, 0.0), intensity: mix)
  when "halation"            then halation(processed, mix, tint: halation_tint_for(stock))
  when "film_curve"          then film_curve(processed, stock, level * head[:curve])
  when "stock_matrix"        then stock_matrix(processed, stock, mix)
  when "spectral_temp"       then spectral_temp(processed, source_kelvin: 6504, target_kelvin: p[:temp], intensity: mix)
  when "color_temp"          then color_temp(processed, p[:temp], mix)
  when "dir_coupler"         then dir_coupler(processed, mix)
  when "push_pull"           then push_pull(processed, p.fetch(:stops, 1.0), stock)
  when "bleach_bypass"       then bleach_bypass(processed, mix)
  when "reciprocity_failure" then reciprocity_failure(processed, p.fetch(:exposure_secs, 10.0), stock)
  when "orange_mask"         then orange_mask(processed, stock, mix)
  when "print_film"          then print_film(processed, p.fetch(:print_stock, :kodak_2383), mix)
  when "split_grade"         then split_grade(processed, intensity: mix)
  when "split_toning"        then split_toning(processed)
  when "skin_protect"        then skin_protect(processed, level)
  when "shadow_lift"         then shadow_lift(processed, SHADOW_TOE_TARGET, true)
  when "light_leaks"         then light_leaks(processed, mix)
  when "day_for_night"       then day_for_night(processed, mix)
  when "highlight_roll"      then highlight_roll(processed, 200, mix)
  when "micro_contrast"      then micro_contrast(processed, 5, mix)
  # Was a hard-coded 800 for every preset. grain's whole ISO term is
  # sqrt(iso/100), so a constant made it a constant: Velvia 50 and
  # Delta 3200 were graining at the same speed and differed only by
  # their sigma. Now each stock states its own box speed, and a push
  # raises the effective one, which is what pushing IS -- rating the
  # film faster than it is and paying for it in grain. Safe to change
  # today of all days: grain raised on every call until this session,
  # so no render anywhere has a grain pattern to preserve.
  when "grain"               then grain(processed, preset_effective_iso(p), stock, level)
  when "color_separate"      then color_separate(processed, mix)
  when "chromatic_aberration" then chromatic_aberration(processed, level * 0.25 * head[:fringe])
  when "vintage_lens"        then vintage_lens(processed, p.fetch(:lens, "zeiss"), mix)
  when "teal_orange"         then teal_orange(processed, mix)
  when "bloom_pro"           then bloom_pro(processed, mix)
  # The measured depth map rides along on both shape stages; a cache
  # miss costs about twelve seconds, which the chain spends in
  # glows anyway. nil degrades both to their own cues.
  when "relight"             then relight(processed, mix, azimuth: p.fetch(:azimuth, 135.0), shape: p.fetch(:shape, 1.25), depth: Postpro::Depth.near(processed))
  when "aerial_depth"        then aerial_depth(processed, mix, depth: Postpro::Depth.near(processed))
  when "desaturate"          then desaturate(processed, mix)
  when "warmth"              then warmth(processed, mix)
  when "green_push"          then green_push(processed, mix)
  when "cross_fade"          then cross_fade(processed, mix)
  when "infrared"            then infrared(processed, mix)
  when "lith_print"          then lith_print(processed, mix)
  when "kodachrome_sim"      then kodachrome_sim(processed, mix)
  when "technicolor"         then technicolor(processed, mix)
  when "cyanotype"           then cyanotype(processed, level)
  when "faded_print"         then faded_print(processed, p.fetch(:age, 0.40))
  when "base_tint"           then base_tint(processed, [255, 250, 242], 0.07)
  when "dual_base_density"   then dual_base_density(processed, [255, 248, 236], 0.06)
  when "emulsion_defocus"    then emulsion_defocus(processed, stock)
  when "adjacency_effects"   then adjacency_effects(processed, mix)
  when "longitudinal_ca"     then longitudinal_ca(processed, mix)
  when "lens_distortion"     then lens_distortion(processed, p.fetch(:k1, -0.12))
  when "bokeh_rendering"     then bokeh_rendering(processed, mix)
  when "anamorphic_flare"    then anamorphic_flare(processed, mix)
  when "diffraction_blur"    then diffraction_blur(processed, p.fetch(:f_number, 16.0))
  when "scan_noise"          then scan_noise(processed, mix)
  when "newton_rings"        then newton_rings(processed, mix)
  when "dust_and_hair"       then dust_and_hair(processed, mix)
  when "film_curl_vignette"  then film_curl_vignette(processed, level * 0.45 * head[:vignette])
  when "selenium_tone"       then selenium_tone(processed, mix)
  when "dye_fade"            then dye_fade(processed, stock, p.fetch(:age, 0.50))
  when "darkroom_print"      then darkroom_print(processed, mix)
  when "film_base_density"   then film_base_density(processed, stock, 0.06)
  when "paper_texture"       then paper_texture(processed, mix)
  when "dodgeburn_artifacts" then dodgeburn_artifacts(processed, mix)
  when "fixing_bath_fog"     then fixing_bath_fog(processed, mix)
  when "reticulation"        then reticulation(processed, mix)
  when "expired_film"        then expired_film(processed, p.fetch(:age, 0.60))
  when "gate_weave"          then gate_weave(processed, mix)
  when "lens_ghosting"       then lens_ghosting(processed, mix)
  when "ortho_film"          then ortho_film(processed, mix)
  when "tilt_shift"          then tilt_shift(processed, mix)
  when "adaptive_contrast"   then adaptive_contrast(processed, mix)
  when "film_shoulder"       then film_shoulder(processed, mix)
  when "clarity"             then clarity(processed, 15, mix)
  when "edge_aware_nr"       then edge_aware_nr(processed, mix)
  when "selective_sharpen"   then selective_sharpen(processed, mix)
  when "vhs_luma_bleed"      then vhs_luma_bleed(processed, mix)
  when "vhs_chroma_delay"    then vhs_chroma_delay(processed, mix)
  when "vhs_head_switch_band" then vhs_head_switch_band(processed, mix)
  when "vhs_tracking_noise"  then vhs_tracking_noise(processed, mix)
  when "vhs_interlace_comb"  then vhs_interlace_comb(processed, mix)
  when "crt_phosphor_bloom"  then crt_phosphor_bloom(processed, mix)
  when "crt_scanlines"       then crt_scanlines(processed, mix)
  when "minidv_block_dropout" then minidv_block_dropout(processed, mix)
  when "hi8_chroma_noise"    then hi8_chroma_noise(processed, mix)
  when "double_exposure"     then double_exposure(processed, p[:second_image], p.fetch(:blend_mode, "over"))
  when "polaroid_frame"      then polaroid_frame(processed, level, p.fetch(:border_style, "classic"))
  when "tape_degradation"    then tape_degradation(processed, level)
  when "frame_distortion"    then frame_distortion(processed, level)
  when "super8_flicker"      then super8_flicker(processed, level)
  when "cinemascope_bars"    then cinemascope_bars(processed, level, p.fetch(:aspect_ratio, "2.35:1"))
  when "halftone_print"      then halftone_print(processed, level)
  when "film_scratches"      then film_scratches(processed, level)
  when "film_stock_emulation" then film_stock_emulation(processed, level, p.fetch(:stock, "kodak_portra"))
  when "sprocket_holes"      then sprocket_holes(processed, level)
  when "lens_flare"          then lens_flare(processed, level)
  when "vhs_degrade"         then vhs_degrade(processed, level)
  when "color_fade"          then color_fade(processed, level)
  when "anamorphic_simulation" then anamorphic_simulation(processed, level)
  when "soft_focus"          then soft_focus(processed, level)
  when "film_grain"          then film_grain(processed, level)
  when "film_halation"       then film_halation(processed, level)
  when "bloom_effect"        then bloom_effect(processed, level)
  when "cross_process"       then cross_process(processed, level)
  when "golden_hour_glow"    then golden_hour_glow(processed, level)
  when "lomo"                then lomo(processed, level)
  when "sepia"               then sepia(processed, level)
  when "teal_and_orange"     then teal_and_orange(processed, level)
  when "glitch"              then glitch(processed, level)
  when "dilla_head_bump"      then dilla_head_bump(processed, level)
  when "dilla_tape_saturation" then dilla_tape_saturation(processed, level)
  when "dilla_vinyl_bandlimit" then dilla_vinyl_bandlimit(processed, level)
  when "dilla_phasy"          then dilla_phasy(processed, level)
  when "dilla_console_sum"    then dilla_console_sum(processed, level)
  else
    # Was a bare `else processed` — an fx name with no arm here returned
    # the image untouched, and the dmesg line below then reported the
    # step as having run. A preset could be four steps short of what
    # it says it is and the log would agree with the preset.
    message = "fx=#{fx} has no implementation; #{owner} is short a step"
    PostproBootstrap.dmesg "ERROR #{message}"
    raise ArgumentError, message
  end
end

# `stock:` swaps the film under an otherwise unchanged chain, which is how the
# stock sheet shows one grade on every emulsion.
def preset(image, name, stock: nil)
  p = PRESETS[name.to_sym] or
    raise ArgumentError, "unknown preset #{name.inspect}; have #{PRESETS.keys.join(', ')}"

  p = p.merge(stock: stock) if stock
  processed = image
  t_start = Time.now
  n_steps = p[:fx].length
  head = source_headroom(image)
  # Headroom on, for the whole chain. Values may exceed 0..255 between steps and
  # only the final clamp decides what becomes white.
  $postpro_float_pipeline = true
  PostproBootstrap.dmesg "preset=#{name} stock=#{p[:stock]} steps=#{n_steps} intensity=#{p[:intensity]}"
  if head[:reading]
    PostproBootstrap.dmesg format("source %s -> blur x%.2f curve x%.2f",
                                  head[:reading], head[:blur], head[:curve])
  end

  p[:fx].each_with_index do |fx, i|
    t0 = Time.now
    # What the picture looked like before this step, when asked. POSTPRO_EXPLAIN=1
    # turns the dmesg line below into a report of what each effect actually did,
    # rather than only that it ran.
    #
    # This file already carries the reason: an fx name with no arm in the case
    # returned the image untouched while the log reported the step as having run,
    # so a preset could be four steps short of what it says it is and the log
    # would agree with the preset. That was fixed for the missing-arm case. It
    # does not cover the arm that exists, runs, and changes nothing — which looks
    # identical from outside.
    before_stats = PostproExplain.snapshot(processed)
    processed = grade_step(fx, processed, p, head, "preset #{name}")
    processed = processed.copy_memory
    GC.start(full_mark: false) if (i % 4).zero?
    PostproBootstrap.dmesg "fx=#{fx} step=#{i + 1}/#{n_steps} time=%.3fs%s" %
                           [(Time.now - t0), PostproExplain.delta(before_stats, processed)]
  end

  PostproBootstrap.dmesg "preset=#{name} done total=%.2fs" % (Time.now - t_start)
  # The single clamp. Everything above ran in unbounded float; this is where
  # the negative becomes a print.
  $postpro_float_pipeline = false
  safe_cast(processed)
ensure
  # One clamp, at the end, whatever happened in between — including a raise,
  # which is why this is an ensure rather than a line before the return. Leaving
  # the flag set would make every later bare effect call return unbounded float
  # to a caller expecting 8-bit.
  $postpro_float_pipeline = false
end

# Random Effects
# A random chain, grown rather than sampled.
#
# A random subset without a shared process is the Photoshop filter menu, and it
# looks like one: tilt-shift and selenium toning and teal-orange on the same
# frame, each at half strength, none of them agreeing about what the picture is.
# What makes a chain read as a grade instead is that its steps belong to one
# process — a stock, a development, a print, one way of having been damaged.
#
# Nobody declares those families here. They are read off the eighty-two presets,
# each a colourist's answer to the same question: a candidate may
# join the chain only where some preset already puts it beside everything
# already picked. The graph is dense enough to carry it — greedy walks run five
# to thirteen effects, median eight — so the constraint buys coherence without
# costing variety.
RANDOM_CHAIN_LENGTH = (4..8)
# Grain is not optional, ever. The argument of this whole file is that an
# emulsion is a physical process, and a chain with no crystals in it is a colour
# filter with opinions.
RANDOM_ALWAYS = "grain"
RANDOM_VARIATIONS = (5..10)
RANDOM_VARIATION_RANGE = RANDOM_VARIATIONS.freeze

RANDOM_ANALOG_CORE = %w[
  film_curve halation stock_matrix dir_coupler adjacency_effects film_base_density
  orange_mask print_film paper_texture dilla_head_bump dilla_tape_saturation
  dilla_vinyl_bandlimit dilla_phasy dilla_console_sum
].freeze

# Grain is removed from every lane pool: `random_finish` appends the
# always-grain once at the end, and a lane draw putting another grain earlier
# in the chain made "grainx2" — two passes of what compositors forbid stacking
# ("don't mix grain on top of grain in the plate"). One grain pass, last.

RANDOM_LANES = {
  subtle_analog: {
    effects: %w[
      spectral_temp film_curve stock_matrix dir_coupler adjacency_effects halation
      film_base_density orange_mask print_film shadow_lift highlight_roll micro_contrast
      warmth
    ].freeze,
    strength: (0.16..0.42)
  },
  cinematic_color: {
    effects: %w[
      spectral_temp color_temp film_curve stock_matrix halation orange_mask print_film
      tonemap split_toning teal_orange warmth shadow_lift highlight_roll micro_contrast
    ].freeze,
    strength: (0.24..0.58)
  },
  artistic_analog: {
    effects: %w[
      film_curve halation stock_matrix dir_coupler adjacency_effects bloom_pro
      double_exposure lith_print cyanotype technicolor faded_print polaroid_frame
      soft_focus golden_hour_glow cross_process lens_flare film_scratches
      dilla_head_bump dilla_tape_saturation dilla_vinyl_bandlimit dilla_phasy
    ].freeze,
    strength: (0.34..0.72)
  },
  bleeding_edge_analog: {
    effects: %w[
      film_curve halation stock_matrix dilla_head_bump dilla_tape_saturation
      dilla_vinyl_bandlimit dilla_phasy dilla_console_sum vhs_luma_bleed
      vhs_chroma_delay vhs_head_switch_band vhs_tracking_noise vhs_interlace_comb
      crt_phosphor_bloom crt_scanlines minidv_block_dropout hi8_chroma_noise
      scan_noise newton_rings reticulation gate_weave lens_ghosting anamorphic_flare
    ].freeze,
    strength: (0.48..0.88)
  }
}.freeze

RANDOM_LANE_NAMES = RANDOM_LANES.keys.freeze

def random_lane(rng) = RANDOM_LANE_NAMES.sample(random: rng)

# One or two steps carry the look and the rest are barely there.
#
# Nine effects at half strength each is mud, and it is the clearest tell of an
# amateur stack: everything turned up, nothing decided. A grade has a subject.
RANDOM_LEADS = (1..2)
# Every chain shapes the light, because a chain that leaves the light alone is
# a chain about texture, and texture is the shallow half of a photograph. One
# of these runs in every picture, and it leads.
RANDOM_SHAPES = %w[relight aerial_depth].freeze

# The wear shelf: dust, scanner noise, tape dropouts, fogged fixer, gate weave.
#
# Off by default, and that is the change. These may not lead — dust and hair at
# 0.94 is the amateur move in a single line, the artefact becoming the picture
# — but the deeper problem is that they are loud by construction. They read as
# an effect where the rest of this file is trying to read as a photograph.
# `--rough` brings them back for the runs that want a handled print, still
# capped and still never leading. A preset is free to disagree; a preset was
# written by somebody.
RANDOM_WEAR = %w[dust_and_hair newton_rings scan_noise gate_weave
                        dodgeburn_artifacts fixing_bath_fog reticulation
                        film_curl_vignette lens_ghosting anamorphic_flare
                        vhs_luma_bleed vhs_chroma_delay vhs_head_switch_band
                        vhs_tracking_noise vhs_interlace_comb
                        crt_phosphor_bloom crt_scanlines minidv_block_dropout
                        hi8_chroma_noise].freeze

# A lead has to read. At 0.38 to 0.66 with supports at 0.05 to 0.16 the stack summed
# to almost nothing and five takes of one frame looked like one take (operator
# review, 2026-10-20), so the leads sit high and the supports are audible.
RANDOM_LEAD_STRENGTH = (0.55..0.9)
RANDOM_SUPPORT_STRENGTH = (0.12..0.28)
# And one step is allowed to disagree with the family, quietly. A chain that is
# only coherent is a template; the interest is in the one thing that should not
# be there, at a strength that makes it a suggestion rather than a joke.
RANDOM_WILDCARD_CHANCE = 0.5

RANDOM_WILDCARD_STRENGTH = (0.1..0.25)
# Heavy mode (--heavy) starts each take from a named look and deals the lanes
# round-robin so one run spans subtle analog to bleeding edge. It is opt-in:
# measured on nine photographs (2026-10-27), 69% of its takes lost the
# source's colour or shapes against 10% of light takes, and its damage rose
# with chain length (53% at 9-11 steps, 100% past 15) and with the strength
# lift it used to apply. A look keeps all its own steps; the random steps grown
# around it stop at HEAVY_MAX_STEPS, and every strength sits in the same band
# as a light take's, since professional practice mixes a look below full
# strength rather than above it.
HEAVY_MAX_STEPS = 10

# Ten takes per photograph in either mode, the top of the constitution's
# five-to-ten range: heavy's lane deal goes round twice and HEAVY_LOOKS has
# eighteen looks, so no two of ten share one. --count sets any other number.
RANDOM_TAKES = 10
HEAVY_LANE_DEAL = %i[
  subtle_analog cinematic_color artistic_analog bleeding_edge_analog bleeding_edge_analog
].freeze

def heavy_mode? = ENV.fetch("POSTPRO_HEAVY", "0") == "1"
# Two marks of wear is a print that has been handled. Five is a prop.
RANDOM_WEAR_CEILING = 2
# A repeat is a second pass, not a second effect: halation twice at different
# radii is what a bright window through a thick base does, and it only means
# anything when the first pass was one of the leads.
RANDOM_DUPLICATE_CHANCE = 0.3
# No two pictures out of one run may be near neighbours. Jaccard over the effect
# sets, with a fresh stock each time.
RANDOM_SIMILARITY_CEILING = 0.34
RANDOM_DRAW_ATTEMPTS = 40

# Effects that can start a chain: not damage, not the backbone, and known to
# some preset, so that the walk has somewhere to go.
# What a chain may draw from. The wear shelf is not in it unless --rough says
# so, and the shape step is appended rather than drawn, so it never has to
# argue with the co-occurrence graph it appears in no preset of.
def random_seeds(lane = nil)
  (random_pool(lane) - random_common_spine) & random_affinity.keys.flatten.uniq
end

def random_pool(lane = nil)
  rough = ARGV.include?("--rough")
  allowed = lane ? RANDOM_LANES.fetch(lane).fetch(:effects) : RECIPE_ALLOWED - [RANDOM_ALWAYS] - RANDOM_SHAPES
  allowed &= RECIPE_ALLOWED
  allowed -= RANDOM_SHAPES
  allowed -= RANDOM_WEAR unless rough || lane == :bleeding_edge_analog || heavy_mode?
  allowed
end

# Which effects a colourist actually puts together, counted off the presets.
def random_affinity
  @random_affinity ||= begin
    pairs = Hash.new(0)
    PRESETS.each_value { |p| Array(p[:fx]).uniq.combination(2) { |a, b| pairs[[a, b].sort] += 1 } }
    pairs
  end
end

# Where each effect belongs in a chain, measured across all eighty-two presets.
#
# A chain in a random order is mush: a print stock before the film curve, a
# vignette before the lens. Rather than declare a stage table that would drift
# from the presets, read the presets — each one is a colourist's ordering, and
# the mean normalised position of an effect across all of them is the order it
# wants to run in. An effect no preset uses sits with the artefacts, late.
def random_stage_rank
  @random_stage_rank ||= begin
    positions = Hash.new { |table, key| table[key] = [] }
    PRESETS.each_value do |p|
      chain = Array(p[:fx])
      chain.each_with_index do |fx, index|
        positions[fx] << (chain.size < 2 ? 0.5 : index.to_f / (chain.size - 1))
      end
    end
    measured = positions.transform_values { |seen| seen.sum / seen.size }
    # The finishing grain is appended after the drawn steps, so it ranks last.
    RECIPE_ALLOWED.to_h { |fx| [fx, measured.fetch(fx, 0.85)] }.merge(RANDOM_ALWAYS => 1.0)
  end
end

# An ordered list of [effect, params] pairs, which is what recipe() iterates. A
# list rather than a hash precisely so an effect can appear twice.
#
# `avoid` holds the chains this run has already drawn. A draw that overlaps one
# of them too far is thrown back, up to a bounded number of attempts, after
# which the least similar of them is used — a run of five pictures that are five
# versions of one picture is the other way to waste somebody's afternoon.
def random_chain(rng = Random.new(postpro_seed), avoid: [], lane: nil)
  closest = nil
  lane = random_lane(rng) if lane.nil?
  RANDOM_DRAW_ATTEMPTS.times do
    picked, wildcard = random_draw(rng, lane:)
    overlap = avoid.map { |other| random_similarity(picked, other.map(&:first)) }.max || 0.0
    return random_finish(picked, wildcard, rng, avoid, lane:) if overlap <= RANDOM_SIMILARITY_CEILING

    closest = [overlap, picked, wildcard] if closest.nil? || overlap < closest.first
  end
  random_finish(closest[1], closest[2], rng, avoid, lane:)
end

# Two chains that share optical_blur, spectral_temp and film_curve share a
# spine, not a look — most presets carry all three. Similarity is measured over
# what is distinctive, meaning the effects fewer than half the presets use, so
# the common backbone stops reading as a resemblance.
def random_similarity(one, two)
  left = random_distinctive(one)
  right = random_distinctive(two)
  return 0.0 if left.empty? || right.empty?

  (left & right).length.to_f / (left | right).length
end

def random_distinctive(names) = names - random_common_spine

# The steps more than half the presets carry: today spectral_temp, film_curve,
# grain and optical_blur.
def random_common_spine
  @random_common_spine ||= begin
    counts = Hash.new(0)
    PRESETS.each_value { |p| Array(p[:fx]).uniq.each { |fx| counts[fx] += 1 } }
    counts.select { |_, n| n > PRESETS.length / 2 }.keys
  end
end

def random_chain_length = RANDOM_CHAIN_LENGTH

# Grow from one effect, admitting only what some preset puts beside all of it.
def random_draw(rng, lane:)
  pool = random_pool(lane)
  target = rng.rand(random_chain_length)
  # Seeded on something that could be the subject, and that can grow. Starting
  # from an artefact grows a chain of nothing but damage — reticulation into
  # fixing-bath fog into gate weave — and then something has to lead it, and dust
  # does. Starting from an effect no preset uses grows nothing at all: five of the
  # seventy-three have no affinity with anything, and seeding on one of those
  # rendered a picture whose whole grade was dual_base_density and grain. They
  # stay reachable as the wildcard, which is where a stranger belongs.
  seeds = random_seeds(lane)
  seeds = pool if seeds.empty?
  analog_pool = pool & (RANDOM_ANALOG_CORE - [RANDOM_ALWAYS])

  # Start with a seed plus two analog steps that are pairwise supported by the
  # observed preset graph. Adding arbitrary analog steps here broke the same
  # co-occurrence invariant the growth loop below enforces.
  picked = nil
  seeds.shuffle(random: rng).each do |seed|
    pairs = (analog_pool - [seed]).combination(2).select do |left, right|
      [[seed, left], [seed, right], [left, right]].all? do |a, b|
        random_affinity[[a, b].sort].positive?
      end
    end
    next if pairs.empty?

    picked = [seed, *pairs.sample(random: rng)]
    break
  end

  picked ||= [seeds.sample(random: rng)]
  2.times do
    analog = (analog_pool - picked).select do |candidate|
      picked.all? { |held| random_affinity[[candidate, held].sort].positive? }
    end.sample(random: rng)
    picked << analog if analog
  end
  while picked.length < target
    admissible = (pool - picked).select do |candidate|
      next false if RANDOM_WEAR.include?(candidate) &&
                    (picked & RANDOM_WEAR).length >= RANDOM_WEAR_CEILING

      picked.all? { |held| random_affinity[[candidate, held].sort].positive? }
    end
    break if admissible.empty?

    picked << admissible.sample(random: rng)
  end
  wildcard = rng.rand < RANDOM_WILDCARD_CHANCE ? (pool - picked).sample(random: rng) : nil
  [picked + [wildcard].compact + [RANDOM_SHAPES.sample(random: rng)], wildcard]
end

def random_finish(picked, wildcard, rng, avoid = [], lane: random_lane(rng))
  # Nor is the backbone the subject. optical_blur, spectral_temp and film_curve
  # are in most presets because most pictures want a little of each; leading
  # with optical_blur at 0.95 is not a look, it is an out-of-focus photograph.
  candidates = picked - [wildcard] - RANDOM_WEAR - random_common_spine
  candidates = picked - [wildcard] if candidates.empty?
  # The shape step is one of the leads, not an extra one: three leads is three
  # things asking to be looked at.
  shaping = picked & RANDOM_SHAPES
  leads = shaping | candidates.sample(rng.rand(RANDOM_LEADS) - shaping.length, random: rng)
  # A second pass belongs a quarter of the way further along the process, not at
  # the end and not next to the first: two adjacent passes of one effect are
  # just one stronger pass, and the interest is in what happened in between.
  # Never the shape step. Relighting twice in a row is relighting once, harder,
  # and the whole argument for a repeat is what happens between the passes.
  repeatable = leads - RANDOM_SHAPES
  repeat = repeatable.sample(random: rng) if repeatable.any? && rng.rand < RANDOM_DUPLICATE_CHANCE
  keyed = picked.map { |fx| [fx, random_stage_rank[fx], rng.rand] }
  keyed << [repeat, [random_stage_rank[repeat] + 0.25, 1.0].min, rng.rand] if repeat
  ordered = keyed.sort_by { |_, rank, jitter| [rank, jitter] }.map(&:first)
  seen = Hash.new(0)
  chain = ordered.map do |fx|
    repeat = (seen[fx] += 1) > 1
    band = if repeat || fx == wildcard then wildcard_or_repeat_strength(fx, wildcard)
           elsif leads.include?(fx) then RANDOM_LEAD_STRENGTH
           else RANDOM_SUPPORT_STRENGTH
           end
    [fx, (band.first + rng.rand * (band.last - band.first)).round(2)]
  end
  band = RANDOM_LANES.fetch(lane).fetch(:strength)
  chain << [RANDOM_ALWAYS, { "intensity" => (band.first + rng.rand * (band.last - band.first)).round(2),
                             "stock" => random_stock(rng, avoid).to_s }]
end

# A repeat is a lighter second pass; a wildcard is a suggestion. Same band.
def wildcard_or_repeat_strength(_fx, _wildcard) = RANDOM_WILDCARD_STRENGTH

# A fresh emulsion per picture while there are any left unused this run.
def random_stock(rng, avoid)
  spent = avoid.filter_map { |chain| chain.last&.last }
               .filter_map { |params| params.is_a?(Hash) ? params["stock"] : nil }
  (STOCKS.keys - spent.map(&:to_sym)).then { |left| left.empty? ? STOCKS.keys : left }
                                     .sample(random: rng)
end

def random_chain_name(chain)
  chain.map { |fx, _| fx }.tally.map { |fx, n| n > 1 ? "#{fx}x#{n}" : fx }.join("-")
end

# Looks that commit. A heavy take starts from one of these named presets at full
# strength, so five takes of one frame differ in what they decided and not only in
# how much they changed it. They span stocks and colour worlds on purpose.
HEAVY_LOOKS = %i[
  noir neon_night tokyo_night bleached magic_hour kodachrome_look technicolor_3strip
  cross_process cyanotype_look infrared_look cinematic blockbuster golden_age
  day_for_night process_e6 reversal dream silver_gelatin
].freeze

# A preset written as the ordered recipe the random chains speak, so a look can be
# merged with drawn steps. Effects the recipe vocabulary lacks are dropped.
def preset_as_recipe(name)
  data = PRESETS.fetch(name.to_sym)
  stock = (data[:stock] || :kodak_portra).to_s
  intensity = (data[:intensity] || 0.8).to_f.clamp(0.3, 1.0)
  Array(data[:fx]).map(&:to_s).uniq.filter_map do |fx|
    next unless RECIPE_ALLOWED.include?(fx)

    [fx, look_step_params(data, fx, intensity, stock)]
  end
end

# Everything the preset tells its own steps, so a look-led take runs the look as
# the preset does: its stops, exposure time, print stock, lens and age, not
# only its intensity and stock.
def look_step_params(data, fx, intensity, stock)
  params = { "intensity" => intensity, "stock" => stock }
  params["target_kelvin"] = data[:temp].to_f if fx == "spectral_temp" && data[:temp]
  params["kelvin"] = data[:temp].to_f if fx == "color_temp" && data[:temp]
  params["stops"] = data[:stops].to_f if fx == "push_pull" && data[:stops]
  params["exposure_seconds"] = data[:exposure_secs].to_f if fx == "reciprocity_failure" && data[:exposure_secs]
  params["print_stock"] = data[:print_stock].to_s if fx == "print_film" && data[:print_stock]
  params["lens"] = data[:lens].to_s if fx == "vintage_lens" && data[:lens]
  params["age"] = data[:age].to_f if data[:age] && %w[faded_print dye_fade expired_film].include?(fx)
  params["tonemap"] = data[:tonemap].to_s if fx == "tonemap" && data[:tonemap]
  params
end

# Each take must differ from the last in kind. The next look is drawn from the
# ones not yet used, on a stock no earlier take used, and a repeat of either is the
# last resort once the families run out.
def next_heavy_look(rng, used)
  stocks = used.map { |look| PRESETS.fetch(look)[:stock] }
  fresh = (HEAVY_LOOKS - used).shuffle(random: rng)
  fresh.find { |look| !stocks.include?(PRESETS.fetch(look)[:stock]) } || fresh.first || HEAVY_LOOKS.sample(random: rng)
end

# The look's own steps, then the strongest few steps of a random chain of light,
# texture and wear, up to HEAVY_MAX_STEPS in all, in physical order with one
# grain pass last.
def look_led_chain(rng, look:, avoid: [], lane: nil)
  base = preset_as_recipe(look)
  taken = base.map(&:first)
  drawn = random_chain(rng, avoid:, lane:).reject { |fx, _| taken.include?(fx) || fx == RANDOM_ALWAYS }
  # One step of the cap is always the closing grain pass.
  tail = strongest_steps(drawn, HEAVY_MAX_STEPS - 1 - base.count { |fx, _| fx != RANDOM_ALWAYS })
  stock = (PRESETS.fetch(look.to_sym)[:stock] || :kodak_portra).to_s
  grain = base.find { |fx, _| fx == RANDOM_ALWAYS } || [RANDOM_ALWAYS, { "intensity" => 0.6, "stock" => stock }]
  rank = random_stage_rank
  body = (base.reject { |fx, _| fx == RANDOM_ALWAYS } + tail)
         .each_with_index.sort_by { |(fx, _), index| [rank.fetch(fx, 0.85), index] }.map(&:first)
  body << grain
end

# The `room` strongest steps of a drawn chain, in their drawn order.
def strongest_steps(chain, room)
  return [] unless room.positive?

  kept = chain.each_with_index.max_by(room) { |(_, params), _| params.is_a?(Numeric) ? params : params["intensity"].to_f }
  kept.sort_by(&:last).map(&:first)
end

# A random take is named for what it is: its place in the run, the look it was
# built on, and the lane it was dealt. The number keeps one family's takes apart
# and in draw order; the dealt lane is named over the inferred one, which can
# read a bleeding-edge take as subtle. Without a take the chain stays in the
# name, which separates one-off random grades of the same photograph.
def random_take_label(chain, take = nil)
  lane = (take&.lane || random_chain_lane(chain)).to_s

  return "#{lane}_#{random_chain_name(chain)[0, 50]}" unless take

  [format("%02d", take.number), take.look, lane].compact.join("_")
end

# One take of a random run: its place in the run, the named look it was built
# on (nil outside heavy mode), and the lane it was dealt. It names the file and
# goes into the sidecar; every caller outside a random run leaves it out.
RandomTake = Data.define(:number, :look, :lane)

def random_chain_lane(chain)
  effects = chain.map(&:first).map(&:to_s)
  RANDOM_LANES.max_by do |_name, spec|
    (effects & spec.fetch(:effects)).uniq.length
  end&.first || :subtle_analog
end

RECIPE_ALLOWED = %w[
  grain film_curve highlight_roll shadow_lift micro_contrast color_separate
  chromatic_aberration vintage_lens split_toning split_grade bleach_bypass
  push_pull halation optical_blur tonemap dir_coupler spectral_temp color_temp
  skin_protect desaturate warmth green_push cross_fade infrared cyanotype
  lith_print technicolor kodachrome_sim faded_print base_tint dual_base_density
  reciprocity_failure bloom_pro teal_orange relight aerial_depth
  emulsion_defocus adjacency_effects longitudinal_ca lens_distortion bokeh_rendering
  anamorphic_flare diffraction_blur scan_noise newton_rings dust_and_hair
  film_curl_vignette selenium_tone dye_fade darkroom_print film_base_density
  paper_texture dodgeburn_artifacts fixing_bath_fog reticulation expired_film
  gate_weave lens_ghosting ortho_film tilt_shift stock_matrix
  adaptive_contrast film_shoulder clarity edge_aware_nr selective_sharpen
  vhs_luma_bleed vhs_chroma_delay vhs_head_switch_band vhs_tracking_noise
  vhs_interlace_comb crt_phosphor_bloom crt_scanlines minidv_block_dropout hi8_chroma_noise
  double_exposure polaroid_frame tape_degradation frame_distortion super8_flicker
  cinemascope_bars halftone_print film_scratches film_stock_emulation sprocket_holes
  lens_flare vhs_degrade color_fade anamorphic_simulation soft_focus
  film_grain film_halation bloom_effect cross_process golden_hour_glow lomo sepia
  teal_and_orange glitch dilla_head_bump dilla_tape_saturation dilla_vinyl_bandlimit
  dilla_phasy dilla_console_sum
].freeze

# The stock a recipe step names, or the default when it names none it knows.
def recipe_stock(params, default = :kodak_portra)
  name = params["stock"]&.to_sym
  STOCKS.key?(name) ? name : default
end

# A recipe grades exactly as a preset does: every step through grade_step, so
# it gets the same per-effect mix, the same source-aware taper and the same
# float pipeline with one clamp at the end. It used to call each effect at its
# raw recipe number with none of the three, and that difference, not the
# effects, is what wrecked most random takes.
def recipe(image, recipe_data)
  head = source_headroom(image)
  $postpro_float_pipeline = true
  processed = recipe_data.reduce(image) do |picture, (fx, params)|
    # Evaluated per step, as preset does: left lazy, the take check and the
    # write each ran the whole nested gaussblur chain, so a chain cost twice.
    recipe_step(picture, fx, params, head).copy_memory
  end
  $postpro_float_pipeline = false
  safe_cast(processed)
ensure
  $postpro_float_pipeline = false
end

def recipe_step(image, fx, params, head)
  method = fx.gsub("_professional", "")
  unless RECIPE_ALLOWED.include?(method)
    $cli_logger.warn "recipe: #{fx} is not an allowed effect — skipped"
    return image
  end

  grade_step(method, image, recipe_preset(params), head, "recipe step #{fx}")
end

# A recipe step's numbers in the shape grade_step reads from a preset. A bare
# number is the intensity; the object form may also name a stock, a print
# stock, a temperature, stops, an exposure time, an age, a lens or a tonemap.
# nil.to_f is 0.0, so an object without "intensity" runs at 1.0: absent means
# default, not off.
def recipe_preset(params)
  opts = params.is_a?(Hash) ? params : {}
  intensity = params.is_a?(Hash) ? opts.fetch("intensity", 1.0).to_f : params.to_f
  {
    intensity:, stock: recipe_stock(opts),
    temp: (opts["target_kelvin"] || opts["kelvin"] || 5600).to_f,
    print_stock: PRINT_STOCKS.key?(opts["print_stock"]&.to_sym) ? opts["print_stock"].to_sym : nil,
    # A random push_pull step's number is its stops, as it always was.
    stops: (opts["stops"] || intensity).to_f,
    # Reciprocity failure is a function of time; a step's number picks a long
    # exposure of up to half a minute, a night frame rather than a star trail.
    exposure_secs: (opts["exposure_seconds"] || (1.0 + (intensity * 30.0))).to_f,
    age: (opts["age"] || intensity).to_f,
    lens: LENSES.key?((opts["lens"] || opts["type"]).to_s.to_sym) ? (opts["lens"] || opts["type"]).to_s : nil,
    tonemap: opts["tonemap"]&.to_sym, iso: opts["iso"],
    second_image: opts["second_image_path"] || opts["image"], blend_mode: opts["blend_mode"],
  }.compact
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

# A contact page of every render in a folder, written beside the renders it lists.
def write_gallery(directory)
  require "cgi"
  folder = File.expand_path(directory)
  names = Dir.glob(File.join(folder, "postpro_*.{jpg,jpeg,png}")).sort.map { |path| File.basename(path) }
  cells = names.map do |name|
    safe = CGI.escapeHTML(name)
    "<a href='#{safe}' style='width:320px'><img src='#{safe}' style='width:320px;display:block' loading=lazy>" \
      "<div>#{CGI.escapeHTML(name[0, 52])}</div></a>"
  end
  page = "<!doctype html><meta charset=utf-8><title>postpro renders</title>" \
         "<body style='margin:0;background:#111;color:#ccc;font:12px monospace'>" \
         "<div style='display:flex;flex-wrap:wrap;gap:4px;padding:4px'>#{cells.join}</div>"
  File.write(File.join(folder, "index.html"), page)
  $cli_logger.info "gallery: #{names.size} renders listed in #{File.join(folder, "index.html")}"
end

# Introspection
def describe_preset(name)
  p = PRESETS[name.to_sym] or return "unknown preset: #{name}"
  stock = STOCKS[p[:stock]]
  [
    "#{name}: #{p[:stock]} / #{p.fetch(:temp, "?")}K / intensity #{p[:intensity]}",
    "fx: #{p[:fx].join(" → ")}",
    stock ? "grain σ=#{stock[:grain]}" : nil,
  ].compact.join("\n")
end

def list_presets = PRESETS.keys.map { |k| describe_preset(k) }.join("\n\n")
def list_stocks = STOCKS.keys.join(", ")
def list_lenses = LENSES.keys.join(", ")

# CSS filter string approximating a preset — for lightweight web previews.
def css_filter(preset_name = :portrait)
  p = PRESETS[preset_name.to_sym] || PRESETS[:portrait]
  stock = STOCKS[p[:stock]] || {}
  hd = stock[:hd] || {}
  contrast = (1 + ((hd[:r]&.last || 1.0) - 1.0) * 0.25).round(2)
  saturate = if p[:fx].include?("teal_orange")
1.20
else
p[:fx].include?("desaturate")  ? 0.65 : 1.0
end
  parts = ["contrast(#{contrast})", "saturate(#{saturate})"]
  parts << "sepia(0.12)"    if %i[kodak_portra kodak_vision3_50d].include?(p[:stock])
  parts << "grayscale(0.9)" if p[:stock] == :tri_x
  parts.join(" ")
end

# Replicate Integration
def check_replicate
  return unless REPLICATE_PRESENT

  $cli_logger.info "Replicate detected! Auto-processing generated images..."

  recent_files = Dir.glob("*_generated_*.{jpg,jpeg,png,webp}")
                    .select { |f| File.mtime(f) > (Time.now - 300) }

  return unless recent_files.any?
    $cli_logger.info "Found #{recent_files.count} recent Replicate outputs"
    preset_name = PROMPT ? PROMPT.select("Choose preset for Replicate outputs:", PRESETS.keys) : (CONFIG["default_preset"] || "house")
    recent_files.each { |file| process_file(file, 2, preset_name) }

end

def preset_chain(image, names)
  names.reduce(image) { |img, name| preset(img, name) }
end

# The method whose `case fx` is the effect dispatch, read by --vocab-check.
EFFECT_DISPATCH = "grade_step"

# What one call of process_file grades: the source, its camera-corrected
# picture, and either a preset or a random recipe with the take it belongs to.
GradeRequest = Data.define(:file, :image, :preset_name, :recipe, :take)

# Grades `file` `variations` times through a preset or a random recipe and
# returns how many variations were written. `take` is the RandomTake a random
# run is drawing, or nil for every other caller.
def process_file(file, variations, preset_name = nil, recipe_data = nil, take: nil)
  image = load_image(file)
  return 0 unless image

  request = GradeRequest.new(file:, image: camera_corrected(image, file), preset_name:, recipe: recipe_data, take:)
  written, failed = write_variations(request, variations)
  refuse_failed_family!(file, variations, failed) if written.zero? && failed.positive?
  written
end

# The body's own colour response, before anything else touches the picture.
#
# ON BY DEFAULT, and set false only by someone who has a reason. It was
# `if CONFIG["apply_camera_profile_first"]` against a CONFIG that is {} unless
# a master.json exists, so the answer was nil on every invocation this file
# has ever had — fifty lines of matching and matrix application that had never
# run, aimed at a profiles directory that had never existed.
#
# Both halves are real now: camera_profiles.json holds 121 bodies across
# six vendors, recovered from a VSCO DCP archive. A default of off would have
# kept them as decorative as the code that reads them.
#
# It no-ops safely on anything without EXIF Make/Model, which is every
# generated image — so a render is unaffected and a photograph is corrected.
def camera_corrected(image, file)
  return image if CONFIG.fetch("apply_camera_profile_first", true) == false

  profile = get_camera_profile(image)
  return image unless profile

  corrected = apply_camera_profile(image, profile)
  PostproBootstrap.dmesg "camera_profile src=#{File.basename(file)}"
  corrected
end

# Every variation is attempted; one that raises costs only itself. Returns the
# number written and the number that failed.
def write_variations(request, variations)
  failed = 0
  written = variations.times.count do |index|
    write_variation(request, index)
  rescue StandardError => e
    failed += 1
    report_failed_variation(index + 1, e)
    false
  end
  [written, failed]
end

# One variation: grade, finish, name, write, record. Returns the path written,
# or nil when there was nothing to grade.
def write_variation(request, index)
  processed = graded_variation(request)
  return unless processed

  output = variation_output_path(request, index)
  Postpro::Constitution.verify_chain!(chain: request.recipe, stage_rank: random_stage_rank) if request.recipe
  quality = CONFIG["jpeg_quality"] || 95
  write_graded_image(processed, output, quality)
  write_variation_sidecar(request, output, processed)
  PostproBootstrap.dmesg "write out=#{File.basename(output)} q=#{quality}"
  output
end

# The grade itself, then the finish every variation shares: the tone anchor,
# the survival check a random take must pass, the last grain, and three bands.
def graded_variation(request)
  return preset_variation(request) if request.preset_name
  return unless request.recipe

  balanced = balance_source(request.image)
  processed = hold_exposure(anchor_tones(recipe(balanced, request.recipe)), balanced)
  check_take_survives!(processed, request.image, request.take&.look)
  grained = request.recipe.any? { |fx, _| fx.to_s == RANDOM_ALWAYS }
  rgb_bands(apply_finishing_grain(processed, nil, grained:))
end

def preset_variation(request)
  processed = anchor_tones(preset(request.image, request.preset_name))
  rgb_bands(apply_finishing_grain(processed, request.preset_name, grained: nil))
end

# Balance before the look, as a colourist does: a look graded onto a frame that
# is off in white balance or exposure carries the error into every take. Only
# part of the way to neutral and to mid grey, and never further than
# BALANCE_MAX_CAST or BALANCE_MAX_EV, because a warm or a low-key frame may be
# that way on purpose.
BALANCE_SHARE = 0.5
BALANCE_MAX_CAST = 8.0
BALANCE_MAX_EV = 0.75
BALANCE_NEUTRAL_CHROMA = 10.0
MID_GREY = 0.18

def balance_source(image)
  expose_toward_grey(neutralise(rgb_bands(image).cast(:uchar).copy(interpretation: :srgb)))
rescue StandardError => e
  $logger.error "balance_source: #{e.message}"
  image
end

# Gray world on what is nearly grey already: the mean a* and b* of the
# near-neutral pixels is the cast, and half of it comes out.
def neutralise(image)
  lightness, red_green, yellow_blue = image.colourspace(:lab).bandsplit
  chroma = ((red_green * red_green) + (yellow_blue * yellow_blue))**0.5
  neutral = (chroma < BALANCE_NEUTRAL_CHROMA) & (lightness > 20) & (lightness < 90)
  shifts = [red_green, yellow_blue].map { |band| masked_mean(band, neutral, 0.05) }
  return image if shifts.any?(&:nil?)

  a_shift, b_shift = shifts.map { |mean| (-mean * BALANCE_SHARE).clamp(-BALANCE_MAX_CAST, BALANCE_MAX_CAST) }
  lightness.bandjoin([red_green + a_shift, yellow_blue + b_shift]).copy(interpretation: :lab)
           .colourspace(:srgb).cast(:uchar)
end

# Part of the way toward a mid-grey median, in linear light, with a shoulder so
# a lifted highlight rolls instead of clipping.
def expose_toward_grey(image)
  median = HD.srgb_to_linear(image.colourspace("b-w").extract_band(0).percent(50) / 255.0)
  return image if median <= 1e-4

  ev = (Math.log2(MID_GREY / median) * BALANCE_SHARE).clamp(-BALANCE_MAX_EV, BALANCE_MAX_EV)
  return image if ev.abs < 0.05

  exposed = push_shoulder(image.colourspace("scrgb") * (2.0**ev))
  safe_cast(clamp01(exposed).colourspace("srgb"))
end

# A look moves palette and contrast; it should not move exposure. Measured on
# nine photographs, takes drifted darker than their source, faces first. This
# bends the graded luminance so its median returns to the reference's, with
# black and white held (a power curve on 0..1) and every channel scaled by the
# same ratio, so hue holds.
EXPOSURE_HOLD_RANGE = (0.6..1.6)

def hold_exposure(graded, reference)
  target = luma_median(reference)
  current = luma_median(graded)
  return graded if target <= 0.01 || current <= 0.01 || current >= 0.99 || (target - current).abs < 0.01

  gamma = (Math.log(target) / Math.log(current)).clamp(EXPOSURE_HOLD_RANGE.first, EXPOSURE_HOLD_RANGE.last)
  luma = clamp01(graded.colourspace("b-w").extract_band(0).cast(:float) / 255.0)
  lifted = (luma > 1e-4).ifthenelse(luma, 1e-4)
  ratio = (lifted**gamma) / lifted
  safe_cast(clamp01(graded.cast(:float) / 255.0 * ratio.bandjoin([ratio, ratio])) * 255.0)
end

def luma_median(image) = rgb_bands(image).colourspace("b-w").extract_band(0).cast(:uchar).percent(50) / 255.0

# Built from dirname + basename, not String#sub on the extension: sub matches
# the first occurrence anywhere in the path, so a directory component
# containing the extension (shoots/2024.jpg/frame.jpg) was rewritten and the
# write went to a path that does not exist.
def variation_output_path(request, index)
  file = request.file
  ext = File.extname(file)
  safe_stem = File.basename(file, ext).gsub(/[^0-9A-Za-z_-]+/, "_")
  output_ext = ARGV.include?("--tiff16") ? ".tif" : ext
  name = "postpro_#{safe_stem}_#{variation_suffix(request)}_v#{index + 1}#{output_ext}"
  output = Postpro::Constitution.available_output_path(File.join(Postpro::Constitution.output_dir_for(file), name))
  Postpro::Constitution.verify_output!(input_path: file, output_path: output)
  output
end

def variation_suffix(request)
  return request.preset_name.to_s if request.preset_name

  request.recipe ? random_take_label(request.recipe, request.take) : "processed"
end

def write_graded_image(processed, output, quality)
  if ARGV.include?("--tiff16") || output.end_with?(".tif", ".tiff")
    processed.cast("ushort").write_to_file(output)
  else
    processed.write_to_file(output, Q: quality)
  end
end

# A random chain cannot be looked up again at all, so its recipe goes out
# beside the picture or it is gone. A preset can, but its tables change, so the
# grade's version and what it did to the picture go out too.
def write_variation_sidecar(request, output, processed)
  if request.recipe
    write_chain_sidecar(request.file, output, request.recipe, take: request.take)
  else
    write_grade_sidecar(request.file, output, request.preset_name, request.image, processed)
  end
end

def report_failed_variation(number, error)
  message = error.message
  $logger.error "Variation #{number} failed: #{message} at #{error.backtrace&.first(4)&.join(' <- ')}"
  $cli_logger.error "Variation #{number} failed: #{message}"
end

# run_random reads the "all " at the front of this message as a take that
# destroyed the picture, and draws that take again on another look.
def refuse_failed_family!(file, variations, failed)
  raise "all #{failed}/#{variations} variations failed for #{File.basename(file)}; no output was written"
end

# Main Workflow
def get_input
  $cli_logger.info "postpro.rb v18.0.0 full-analog#{REPLICATE_PRESENT ? " replicate=active" : ""}"

  check_replicate if REPLICATE_PRESENT

  if PROMPT
    workflow = PROMPT.select("Choose workflow:", [
      "Masterpiece Presets (Recommended)",
      "Random Effects (Experimental)",
      "Custom JSON Recipe",
    ])

    patterns = PROMPT.ask("File patterns:", default: "**/*.{jpg,jpeg,png,webp}").strip.split(",").map(&:strip)
    variations = PROMPT.ask("Variations per image:", convert: :int, default: CONFIG["variations"] || 7) { |q| q.in("5-10") }

    case workflow
    when "Masterpiece Presets (Recommended)"
      preset_name = PROMPT.select("Choose preset:", PRESETS.keys)
      [patterns, variations, { type: :preset, preset: preset_name }]

    when "Random Effects (Experimental)"
      mode = PROMPT.select("Mode:", %w[Professional Experimental])
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
    variations = CONFIG["variations"] || 7
    preset_name = CONFIG["default_preset"] || "house"
    [patterns, variations, { type: :preset, preset: preset_name }]
  end
end

def auto_mode
  PostproBootstrap.dmesg "auto mode enabled"
  patterns = ["**/*.{jpg,jpeg,png,webp}"]
  variations = CONFIG["variations"] || 7
  preset_name = CONFIG["default_preset"] || "house"

  [patterns, variations, { type: :preset, preset: preset_name }]
end

def postpro_quality_report(original, processed, reference_path = nil)
  before = rgb_bands(original).cast("float")
  after = rgb_bands(processed).cast("float")
  report = {
    dimensions: [processed.width, processed.height],
    mean_rgb_before: before.bandsplit.map { |band| band.avg.round(3) },
    mean_rgb_after: after.bandsplit.map { |band| band.avg.round(3) },
    clipped_highlights_percent: (((after >= 254).avg / 255.0) * 100).round(4),
    crushed_blacks_percent: (((after <= 1).avg / 255.0) * 100).round(4),
    warnings: [],
  }
  report[:warnings] << "highlight clipping exceeds 0.5%" if report[:clipped_highlights_percent] > 0.5
  report[:warnings] << "black clipping exceeds 0.5%" if report[:crushed_blacks_percent] > 0.5
  if reference_path && File.file?(reference_path)
    reference = rgb_bands(load_image(reference_path)).resize(processed.width.to_f / load_image(reference_path).width,
                                                              vscale: processed.height.to_f / load_image(reference_path).height)
    report[:reference_mean_absolute_error] = (after - reference.cast("float")).abs.avg.round(4)
  end
  report
rescue StandardError => e
  { warnings: ["quality analysis unavailable: #{e.message}"] }
end

# A sidecar another tool wrote keeps its fields and gains this one's under
# "postpro". replicate grades in place and hands over the path whose .json
# already holds the prompt, model and seed; replacing that file left the graded
# picture with a record of its grade and none of how it was made. A sidecar
# postpro wrote itself, or one that does not parse, is replaced.
def write_sidecar(output_path, data)
  path = "#{output_path}.json"
  existing = File.file?(path) ? JSON.parse(File.read(path)) : nil
  foreign = existing.is_a?(Hash) && !existing["schema"].to_s.start_with?("postpro.")
  File.write(path, JSON.pretty_generate(foreign ? existing.merge("postpro" => data) : data) + "\n")
  data
rescue JSON::ParserError
  File.write(path, JSON.pretty_generate(data) + "\n")
  data
end

# Which grade made a frame, as the hash of the code that graded it.
#
# The house look changes: a stock's curve is re-fitted, a step leaves `house`.
# A version somebody has to remember to bump is stale the first time they
# forget, and the recipe alone names effects whose arithmetic lives in this
# file. The digest of postpro.rb and its lib/ cannot drift from the grade, so a
# frame whose sidecar carries it can be re-graded identically by checking out
# the commit whose files hash to it.
GRADE_VERSION = Digest::SHA256.hexdigest(
  [__FILE__, *Dir[File.join(__dir__, "*.rb"), File.join(__dir__, "lib", "*.rb")].sort].uniq.map { |path| File.binread(path) }.join,
)[0, 12].freeze

# The four uncanny numbers on the picture that went in and the one that came
# out, so a sidecar says which way the grade moved texture and clipping without
# anyone re-reading two files.
def uncanny_readings(original, processed)
  { before: Postpro::Uncanny.read_image(rgb_bands(original)).to_h,
    after: Postpro::Uncanny.read_image(rgb_bands(processed)).to_h }
rescue StandardError => e
  { unavailable: e.message }
end

# `presets` is one name, or the two uplift stacks, in the order they ran.
def write_grade_sidecar(input_path, output_path, presets, original, processed)
  names = Array(presets).map(&:to_sym)
  report = postpro_quality_report(original, processed, argv_flag("--reference"))
  data = {
    schema: "postpro.grade.v2",
    generated_at: Time.now.utc.iso8601,
    input: File.expand_path(input_path),
    output: File.expand_path(output_path),
    preset: names.join("+"),
    recipe: names.map { |name| PRESETS.fetch(name) },
    grade_version: GRADE_VERSION,
    seed: $postpro_seed,
    output_sha256: Digest::SHA256.file(output_path).hexdigest,
    quality: report,
    uncanny: uncanny_readings(original, processed),
    capabilities: Studio::AnalogCapabilities.for(:postpro).map { |entry| entry[:id] },
  }
  write_sidecar(output_path, data)
end

def write_chain_sidecar(input_path, output_path, chain, take: nil)
  write_sidecar(output_path, {
    schema: "postpro.chain.v1",
    generated_at: Time.now.utc.iso8601,
    input: File.expand_path(input_path),
    output: File.expand_path(output_path),
    grade_version: GRADE_VERSION,
    seed: $postpro_seed,
    take: take&.number,
    look: take&.look&.to_s,
    lane: (take&.lane || random_chain_lane(chain)).to_s,
    chain: chain.map { |fx, params| { fx => params } },
  })
rescue StandardError => e
  $logger.error "chain sidecar: #{e.message}"
end

def write_comparison(original, processed, output_path)
  return unless ARGV.include?("--compare")

  height = [original.height, processed.height].min
  left = original.thumbnail_image(height, height:, size: :down)
  right = processed.thumbnail_image(height, height:, size: :down)
  comparison = Vips::Image.arrayjoin([rgb_bands(left), rgb_bands(right)], across: 2, shim: 8,
                                                                       background: [24, 24, 24])
  path = output_path.sub(/(\.[^.]+)\z/, "-comparison\\1")
  comparison.write_to_file(path, Q: CONFIG["jpeg_quality"] || 95)
  path
end

# One-shot mode for programmatic use:
#   ruby postpro.rb --input in.jpg --output out.jpg --preset portrait
def one_shot_mode?
  argv_flag("--input") && argv_flag("--output") && argv_flag("--preset")
end

def introspect_mode?
  (ARGV & %w[--vocab-check --capabilities --list-presets --list-stocks --list-lenses --describe-preset --css-filter --export-lut --fit-grain --gallery --map]).any?
end

# Does every preset name things that exist, and does every table have a row for
# every stock that reaches it?
#
# Nothing asked, and the answers were no. preset() returned the image unchanged
# for an fx name it had no arm for while still logging the step as run; five
# presets declared a lens that no chain applied; four stocks had no row in
# RECIPROCITY_SHIFT and one none in PUSH_RESPONSE, so they silently borrowed
# Portra's; every STOCKS entry carried a colour matrix that nothing read; and
# recipe() called two thirds of its allowed effects with an intensity in the
# slot where a stock symbol, an RGB triplet or a Kelvin value belongs.
#
# None of it raised. That is the whole reason for this: the failure mode of a
# table-driven pipeline is not a crash, it is a picture that came out slightly
# wrong and a log that says everything ran.
#
# No image processing and no files touched — it reads the tables.
# What grain does this scan actually carry?
#
# Until this existed the only way to set STOCKS[:grain] was to choose a number
# that looked about right, and every number in that column was chosen that way.
# Zhang, Wang, Tian and Pappas (TOG 42:4, 2023) derive the Boolean model's
# statistics in closed form and, with them, estimators that run backwards from
# a scan to the parameters. This is that estimator at the resolution this file
# needs: sigma per tone, which is the scaling function, and the correlation
# radius, which is the crystal.
#
# Point it at a flat frame — a sky, a wall, a grey card, a clear rebate.
# Structure in the picture reads as grain and inflates the answer, which is why
# the bins are printed rather than one confident number.
#
# Run against this file's own output at a known strength it reads about 15% low
# and one step fine: tri_x rendered at a declared 6.0 levels and a 4.0 px
# crystal comes back 5.0 and 3.4. The residual is a high-pass, so the grain's
# coarsest octave is subtracted along with the picture. Read the figures as a
# floor, and read the knots, which are a ratio and carry none of the bias.
FIT_GRAIN_BINS = 16
FIT_GRAIN_LAGS = 12

def fit_grain(path)
  image = load_image(path)
  return "fit-grain: cannot read #{path}" unless image

  luma = rgb_bands(image).colourspace("b-w").cast("float")
  local = luma.gaussblur(4.0)
  residual = luma - local
  pixels = luma.width * luma.height

  bins = (0...FIT_GRAIN_BINS).map do |bin|
    low = bin * 256.0 / FIT_GRAIN_BINS
    mask = ((local >= low) & (local < low + 256.0 / FIT_GRAIN_BINS)).linear([1.0 / 255], [0])
    share = mask.avg
    next [low.round, nil, 0] if share * pixels < 256

    [low.round, Math.sqrt((residual * residual * mask).avg / share), (share * pixels).round]
  end

  [fit_grain_report(path, luma, bins), fit_grain_correlation(residual)].join("\n")
end

# The first lag at which the residual stops agreeing with itself is the
# crystal, in pixels of this scan.
def fit_grain_correlation(residual)
  width = residual.width
  variance = residual.deviate**2
  return "  correlation: flat residual, nothing to measure" if variance < 1e-9

  correlations = (1..FIT_GRAIN_LAGS).map do |lag|
    shifted = residual.extract_area(lag, 0, width - lag, residual.height)
    (residual.extract_area(0, 0, width - lag, residual.height) * shifted).avg / variance
  end
  crossing = correlations.index { |c| c < Math::E**-1 }
  radius = crossing ? crossing + 1 : FIT_GRAIN_LAGS
  implied = radius * GRAIN_REFERENCE_WIDTH / width
  format("  correlation radius %d px at this width, which is GRAIN_CELL_BASE %.1f at the 2048 px reference\n" \
         "  lags 1..%d: %s", radius, implied, FIT_GRAIN_LAGS, correlations.map { |c| c.round(2) }.join(" "))
end

def fit_grain_report(path, luma, bins)
  midtone = bins.map { |low, sigma, _| [((low + 8) - 128).abs, sigma] }.reject { |_, s| s.nil? }.min_by(&:first)
  peak = midtone&.last
  knots = bins.map { |_, sigma, _| peak && sigma ? (sigma / peak).round(3) : 0.0 }
  lines = ["fit-grain #{File.basename(path)} #{luma.width}x#{luma.height}"]
  bins.each do |low, sigma, count|
    lines << format("  sRGB %3d-%3d  sigma %s  (%d px)", low, low + (256 / FIT_GRAIN_BINS) - 1,
                    sigma ? format("%5.2f", sigma) : "    -", count)
  end
  lines << format("  mid-grey sigma %.2f levels, which is STOCKS[:grain] %.0f at GRAIN_SIGMA_SCALE %.2f",
                  peak || 0.0, (peak || 0.0) / GRAIN_SIGMA_SCALE, GRAIN_SIGMA_SCALE)
  lines << "  grain_knots: [#{knots.join(", ")}]"
  # Newson et al. (SSVM 2017): coverage u of a Boolean crystal field has
  # variance u(1-u). GRAIN_SCALING_KNOTS is that envelope. R² against it says
  # whether this scan is emulsion or a LUT.
  r2 = boolean_envelope_r2(knots)
  lines << format("  Boolean envelope R² %.3f (Newson u(1-u); a LUT stock lands well below 0.9)", r2)
  lines.join("\n")
end

def boolean_envelope_knots(bins = FIT_GRAIN_BINS)
  denom = [bins - 1, 1].max.to_f
  (0...bins).map do |index|
    coverage = index / denom
    Math.sqrt(coverage * (1.0 - coverage)) * 2.0
  end
end

def boolean_envelope_r2(measured)
  model = boolean_envelope_knots(measured.size)
  n = measured.size.to_f
  mean_m = measured.sum / n
  mean_b = model.sum / n
  cov = measured.zip(model).sum { |m, b| (m - mean_m) * (b - mean_b) }
  var_m = measured.sum { |m| (m - mean_m)**2 }
  var_b = model.sum { |b| (b - mean_b)**2 }
  return 0.0 if var_m < 1e-12 || var_b < 1e-12

  (cov / Math.sqrt(var_m * var_b))**2
end

# Source audits need exact method spans. Regexes around `end` either stop inside
# nested blocks or absorb comments/constants after a method. Prism is a default
# gem on the supported Ruby line, so a missing parser is a real checker failure.
def postpro_source_methods(source)
  require "prism"
  parsed = Prism.parse(source)
  raise ArgumentError, "postpro source audit could not parse its own source" unless parsed.success?

  parsed.value.statements.body.each_with_object({}) do |node, methods|
    next unless node.is_a?(Prism::DefNode)

    methods[node.name.to_s] = source.byteslice(node.location.start_offset...node.location.end_offset)
  end
end

def postpro_source_method(source, name)
  postpro_source_methods(source)[name.to_s]
end

def postpro_method_calls(body)
  require "prism"
  parsed = Prism.parse(body)
  raise ArgumentError, "postpro method source could not be parsed" unless parsed.success?

  definition = parsed.value.statements.body.first
  return [] unless definition.is_a?(Prism::DefNode)

  names = []
  pending = [definition.body].compact
  until pending.empty?
    node = pending.pop
    next if node.is_a?(Prism::DefNode)

    names << node.name.to_s if node.is_a?(Prism::CallNode) && node.receiver.nil?
    pending.concat(node.child_nodes.compact)
  end
  names.uniq
end

def postpro_method_reaches?(methods, from, target, seen: [], calls: nil)
  method_name = from.to_s
  return false if seen.include?(method_name)
  return false unless methods.key?(method_name)

  calls ||= methods.transform_values { |body| postpro_method_calls(body) }
  callees = calls.fetch(method_name, [])
  return true if callees.include?(target.to_s)

  callees.any? do |callee|
    methods.key?(callee) &&
      postpro_method_reaches?(methods, callee, target, seen: seen + [method_name], calls:)
  end
end

def postpro_case_label_duplicates(body, predicate_name)
  return [] unless body

  require "prism"
  parsed = Prism.parse(body)
  raise ArgumentError, "postpro case inventory could not parse its method" unless parsed.success?

  duplicates = []
  pending = [parsed.value]
  until pending.empty?
    node = pending.pop
    if node.is_a?(Prism::CaseNode) &&
       node.predicate.is_a?(Prism::LocalVariableReadNode) &&
       node.predicate.name == predicate_name.to_sym
      seen = {}
      node.conditions.each do |branch|
        next unless branch.is_a?(Prism::WhenNode)

        branch.conditions.each do |condition|
          next unless condition.is_a?(Prism::StringNode)

          label = condition.unescaped
          previous_branch = seen[label]
          duplicates << label if previous_branch && !previous_branch.equal?(branch)
          seen[label] ||= branch
        end
      end
    end
    pending.concat(node.child_nodes.compact)
  end
  duplicates.uniq
end

def postpro_case_labels(body, predicate_name)
  return [] unless body

  require "prism"
  parsed = Prism.parse(body)
  raise ArgumentError, "postpro case inventory could not parse its method" unless parsed.success?

  labels = []
  pending = [parsed.value]
  until pending.empty?
    node = pending.pop
    if node.is_a?(Prism::CaseNode) &&
       node.predicate.is_a?(Prism::LocalVariableReadNode) &&
       node.predicate.name == predicate_name.to_sym
      node.conditions.each do |branch|
        next unless branch.is_a?(Prism::WhenNode)

        branch.conditions.each do |condition|
          labels << condition.unescaped if condition.is_a?(Prism::StringNode)
        end
      end
    end
    pending.concat(node.child_nodes.compact)
  end
  labels.uniq
end

def preset_effect_names
  source = File.read(__FILE__)
  postpro_case_labels(postpro_source_method(source, EFFECT_DISPATCH), :fx)
end

# A named step is not enough: the case arm must consume the value it promises
# to read. This catches a preset field that has a matching but disconnected FX.
# A preset key must be read by executable Ruby in the matching case arm.
# Prism excludes comments and strings, which source-text matching mistakes for code.
def postpro_node_reads_p_key?(root, key)
  pending = [root].compact
  until pending.empty?
    candidate = pending.pop
    if candidate.is_a?(Prism::CallNode)
      receiver = candidate.receiver
      p_receiver = (receiver.is_a?(Prism::LocalVariableReadNode) && receiver.name == :p) ||
                   (receiver.is_a?(Prism::CallNode) && receiver.receiver.nil? && receiver.name == :p)
      if p_receiver && (candidate.name == :[] || candidate.name == :fetch)
        arguments = candidate.arguments&.arguments || []
        return true if arguments.any? do |argument|
          argument.is_a?(Prism::SymbolNode) && argument.unescaped == key.to_s
        end
      end
    end
    pending.concat(candidate.child_nodes.compact)
  end
  false
end

# The matching effect call itself must consume the key. A discarded p[:temp]
# expression elsewhere in the same when arm does not configure the rendered effect.
def preset_effect_reads_key?(preset_source, effect, key)
  return false unless preset_source

  require "prism"
  parsed = Prism.parse(preset_source)
  return false unless parsed.success?

  # Ruby executes the first matching when branch. Later duplicate labels are
  # unreachable and must not lend a key read to the active effect arm.
  pending = [parsed.value]
  dispatch = nil
  until pending.empty?
    node = pending.shift
    if node.is_a?(Prism::CaseNode) &&
       node.predicate.is_a?(Prism::LocalVariableReadNode) &&
       node.predicate.name == :fx
      dispatch = node
      break
    end
    pending.concat(node.child_nodes.compact)
  end
  return false unless dispatch

  branch = dispatch.conditions.find do |candidate|
    candidate.is_a?(Prism::WhenNode) &&
      candidate.conditions.any? do |condition|
        condition.is_a?(Prism::StringNode) && condition.unescaped == effect.to_s
      end
  end
  return false unless branch

  pending = [branch.statements].compact
  until pending.empty?
    candidate = pending.pop
    if candidate.is_a?(Prism::CallNode) && candidate.receiver.nil? && candidate.name.to_s == effect.to_s
      return true if postpro_node_reads_p_key?(candidate, key)
    end
    pending.concat(candidate.child_nodes.compact)
  end
  false
end

# Preset data has a closed vocabulary. A newly added field must either be a
# built-in dispatch field, a mechanism-level field (iso), or have an explicit
# effect reader below. Unknown knobs must fail loudly rather than disappear.
def auditable_preset_rows(presets)
  return [{}, ["PRESETS is not a table"]] unless presets.is_a?(Hash)

  rows = {}
  problems = []
  presets.each do |name, definition|
    if definition.is_a?(Hash)
      rows[name] = definition
    else
      problems << "#{name}: preset definition is not a table"
    end
  rescue StandardError => e
    problems << "#{name}: preset definition cannot be read: #{e.class}: #{e.message}"
  end
  [rows, problems]
rescue StandardError => e
  [{}, ["PRESETS audit raises #{e.class}: #{e.message}"]]
end

def preset_unregistered_keys(preset_data, key_readers)
  return [[:invalid_preset_data, preset_data.class.name]] unless preset_data.is_a?(Hash)

  base_keys = %i[fx stock intensity iso]
  invalid_key_types = preset_data.keys.reject { |key| key.is_a?(Symbol) }
    .map { |key| [:invalid_key_type, key.inspect] }
  unknown = preset_data.keys.select { |key| key.is_a?(Symbol) } - base_keys - key_readers.keys
  unknown + invalid_key_types
end

# Keep checking the remaining probe presets after one renderer raises. A single
# broken chain must not hide later independent failures from the operator.
def preset_smoke_problems(names, probe)
  Array(names).filter_map do |name|
    begin
      out = yield(probe, name)
      "preset #{name} returned nothing for an 8x8 probe" unless out
    rescue StandardError => e
      "preset #{name} raises on an 8x8 probe: #{e.class}: #{e.message}"
    end
  end
end

# The finishing-grain bypass is a separate runtime proof. Its failure must be
# recorded as a finding, not allowed to abort the table diagnostics that follow.
def finishing_grain_probe_problems(names, probe)
  name = Array(names).first
  return ["no preset grains in its own chain; finishing-grain bypass cannot be verified"] unless name

  passed_through = yield(probe, name)
  return [] if passed_through == probe

  ["apply_finishing_grain still runs over a chain that grains itself"]
rescue StandardError => e
  ["finishing-grain bypass probe raises: #{e.class}: #{e.message}"]
end

# A broken H&D table is a finding, not a reason the rest of --vocab-check dies.
# Validate the numeric domain before asking the curve code to evaluate powers or
# divide by the pivot; keep each channel's failure local to its own record.
def hd_curve_problems(name, channel, parameters)
  values = parameters.is_a?(Array) ? parameters : []
  valid_numbers = values.length == 4 && values.all? do |value|
    value.is_a?(Numeric) && value.real? && value.to_f.finite?
  end
  return ["#{name} #{channel}: curve parameters must be four finite real numbers"] unless valid_numbers

  dmin, dmax, pivot, gamma = values
  problems = []
  problems << "#{name} #{channel}: Dmin #{dmin} is not below Dmax #{dmax}" unless dmin < dmax
  problems << "#{name} #{channel}: Dmin #{dmin} is outside [0, 1]" unless dmin >= 0 && dmin <= 1
  problems << "#{name} #{channel}: Dmax #{dmax} is outside [0, 1]" unless dmax >= 0 && dmax <= 1
  problems << "#{name} #{channel}: pivot #{pivot} is outside (Dmin, Dmax)" unless dmin < pivot && pivot < dmax
  problems << "#{name} #{channel}: pivot #{pivot} is outside (0, 1)" unless pivot > 0 && pivot < 1
  problems << "#{name} #{channel}: gamma #{gamma} is not positive" unless gamma > 0
  return problems unless problems.empty?

  drops = HD.channel_curve(values).each_cons(2).count { |a, b| b < a }
  problems << "#{name} #{channel}: curve inverts at #{drops} of 255 steps" if drops.positive?
  problems
rescue StandardError => e
  ["#{name} #{channel}: curve evaluation raises #{e.class}: #{e.message}"]
end

def stock_matrix_audit(name, matrix)
  return { offset: nil, problem: nil } if matrix.nil?

  valid = matrix.is_a?(Array) && matrix.length == 9 && matrix.all? do |value|
    value.is_a?(Numeric) && value.real? && value.to_f.finite?
  end
  return { offset: nil, problem: "#{name}: colour matrix must contain nine finite real numbers" } unless valid

  offset = matrix.each_slice(3).map { |row| (row.sum - 1.0).abs }.max
  { offset:, problem: nil }
rescue StandardError => e
  { offset: nil, problem: "#{name}: colour matrix audit raises #{e.class}: #{e.message}" }
end

def grain_knot_problems(name, knots)
  return [] if knots.nil?

  valid = knots.is_a?(Array) && knots.all? do |value|
    value.is_a?(Numeric) && value.real? && value.to_f.finite?
  end
  return ["#{name} grain_knots must be an array of finite real numbers"] unless valid

  problems = []
  problems << "#{name} grain_knots needs at least two knots" if knots.length < 2
  problems << "#{name} grain_knots go negative" if knots.any?(&:negative?)
  problems
rescue StandardError => e
  ["#{name} grain_knots audit raises #{e.class}: #{e.message}"]
end

def stock_grain_levels(stocks, scale)
  levels = {}
  problems = []
  stocks.each do |name, data|
    unless data.is_a?(Hash)
      problems << "#{name}: stock definition is not a table"
      next
    end

    grain = data[:grain]
    next if grain.nil?
    unless grain.is_a?(Numeric) && grain.real? && grain.to_f.finite? && grain >= 0
      problems << "#{name}: grain must be a finite nonnegative number"
      next
    end

    level = grain * scale
    unless level.to_f.finite?
      problems << "#{name}: scaled grain is not finite"
      next
    end
    levels[name] = level
  rescue StandardError => e
    problems << "#{name}: grain measurement raises #{e.class}: #{e.message}"
  end
  [levels, problems]
end

def vocab_check
  source = File.read(__FILE__)
  source_methods = postpro_source_methods(source)
  preset_source = source_methods[EFFECT_DISPATCH]
  implemented = postpro_case_labels(preset_source, :fx)
  problems = []
  valid_presets, malformed_preset_problems = auditable_preset_rows(PRESETS)
  problems.concat(malformed_preset_problems)
  postpro_case_label_duplicates(preset_source, :fx).each do |fx|
    problems << "preset(): duplicate effect arm #{fx.inspect}; later branch is unreachable"
  end

  valid_presets.each do |name, p|
    (Array(p[:fx]) - implemented).each { |fx| problems << "#{name}: fx #{fx.inspect} has no implementation in preset()" }
    problems << "#{name}: stock #{p[:stock].inspect} is not in STOCKS" unless STOCKS.key?(p[:stock])
    if p[:print_stock] && !PRINT_STOCKS.key?(p[:print_stock])
      problems << "#{name}: print_stock #{p[:print_stock].inspect} is not in PRINT_STOCKS"
    end
    if p[:lens]
      unless p[:lens].is_a?(String) || p[:lens].is_a?(Symbol)
        problems << "#{name}: lens #{p[:lens].inspect} must be a name"
      else
        problems << "#{name}: lens #{p[:lens].inspect} is not in LENSES" unless LENSES.key?(p[:lens].to_sym)
      end
    end
    if Array(p[:fx]).include?("vintage_lens") && p[:lens].nil?
      problems << "#{name}: has a vintage_lens step but names no lens, so it gets the zeiss default"
    end
    if Array(p[:fx]).include?("orange_mask") && !C41_STOCKS.include?(p[:stock])
      problems << "#{name}: orange_mask on #{p[:stock]}, which is not a C-41 stock and has no orange mask"
    end
  end

  # A stock reaching an effect whose per-stock table has no row for it does not
  # fail; it quietly becomes a different stock.
  { "GRAIN_CHAN_SCALE" => GRAIN_CHAN_SCALE, "FILM_BASE" => FILM_BASE,
    "PUSH_RESPONSE" => PUSH_RESPONSE, "RECIPROCITY_SHIFT" => RECIPROCITY_SHIFT }.each do |label, table|
    (STOCKS.keys - table.keys).each { |s| problems << "#{s} has no row in #{label}" }
    (table.keys - STOCKS.keys).each { |s| problems << "#{label} has a row for #{s}, which is not in STOCKS" }
  end

  # recipe() grades every step through grade_step, so an allowed effect
  # with no arm there raises instead of grading.
  (RECIPE_ALLOWED - implemented).each do |m|
    problems << "RECIPE_ALLOWED lists #{m}, which has no arm in #{EFFECT_DISPATCH}(), so recipe() raises on it"
  end

  # Reachability. An effect nothing can select is a comment with a runtime cost.
  used = valid_presets.values.flat_map { |p| Array(p[:fx]) }.uniq
  (implemented - used - RECIPE_ALLOWED).each { |fx| problems << "#{fx} is implemented but no preset and no recipe can reach it" }
  (STOCKS.keys - valid_presets.values.map { |p| p[:stock] }.uniq).each { |s| problems << "stock #{s} is defined but no preset uses it" }
  (LENSES.keys - valid_presets.values.filter_map { |p| (p[:lens].to_sym if p[:lens].is_a?(String) || p[:lens].is_a?(Symbol)) }.uniq).each { |l| problems << "lens #{l} is defined but no preset uses it" }
  (PRINT_STOCKS.keys - valid_presets.values.filter_map { |p| p[:print_stock] }.uniq).each { |s| problems << "print stock #{s} is defined but no preset uses it" }

  # A preset key is only honoured if some step in the chain reads it. lens: was
  # the first of these to be found, and it was not the only one -- street and
  # noir each declared a push with nothing to push, and tungsten an eight-second
  # exposure with nothing to fail reciprocity over. Same shape, four keys.
  key_readers = {
    stops: %w[push_pull], age: %w[faded_print dye_fade expired_film],
    print_stock: %w[print_film], exposure_secs: %w[reciprocity_failure],
    k1: %w[lens_distortion], f_number: %w[diffraction_blur], tonemap_ev: %w[tonemap],
    temp: %w[spectral_temp color_temp], tonemap: %w[tonemap],
    lens: %w[vintage_lens], azimuth: %w[relight], shape: %w[relight],
    aspect_ratio: %w[cinemascope_bars], border_style: %w[polaroid_frame],
  }

  # Validate the effect implementation as well as the preset's list. Otherwise
  # a name can remain in the chain while its case arm silently stops reading the
  # very field that made the preset configurable.
  preset_source = source_methods[EFFECT_DISPATCH]
  key_readers.each do |key, readers|
    readers.each do |reader|
      next if preset_effect_reads_key?(preset_source, reader, key)

      problems << "#{reader}: key reader #{key} is listed but preset() does not consume p[:#{key}]"
    end
  end

  valid_presets.each do |name, p|
    preset_unregistered_keys(p, key_readers).each do |key|
      problems << "#{name}: preset key #{key.inspect} has no declared reader contract"
    end
    key_readers.each do |key, readers|
      next unless p.key?(key)
      next unless (Array(p[:fx]) & readers).empty?
      problems << "#{name}: sets #{key}: #{p[key].inspect} but has no #{readers.join('/')} step to read it"
    end
  end

  notes = []

  # A colour matrix whose rows do not sum to 1 shifts neutrals. stock_matrix
  # normalises them at application time so this cannot reach a render, but a
  # row that drifts far from 1 usually means a cast was written into the matrix
  # that belongs in the H&D curve offsets, and that is worth knowing.
  drifting = STOCKS.filter_map do |name, data|
    unless data.is_a?(Hash)
      problems << "#{name}: stock definition is not a table"
      next
    end

    audit = stock_matrix_audit(name, data[:matrix])
    problems << audit[:problem] if audit[:problem]
    [name, audit[:offset]] if audit[:offset] && audit[:offset] > 0.005
  end
  unless drifting.empty?
    notes << "#{drifting.length} stock matrices have rows that do not sum to 1 " \
             "(worst: #{drifting.max_by(&:last).first} at #{(drifting.map(&:last).max * 100).round(1)}%); " \
             "stock_matrix normalises them, but the cast they encode belongs in the H&D offsets"
  end

  # Every H&D curve has to be a curve: monotonic, with the pivot inside the
  # range. A non-monotonic one inverts tones somewhere in the middle.
  STOCKS.merge(PRINT_STOCKS).each do |name, d|
    unless d.is_a?(Hash)
      problems << "#{name}: stock definition is not a table"
      next
    end
    hd = d[:hd]
    next if hd.nil?
    unless hd.is_a?(Hash)
      problems << "#{name}: hd must be a channel table"
      next
    end

    hd.each do |channel, parameters|
      problems.concat(hd_curve_problems(name, channel, parameters))
    end
  end
  STOCKS.each do |name, data|
    unless data.is_a?(Hash)
      problems << "#{name}: stock definition is not a table"
      next
    end
    problems << "#{name} has no speed:, so grain cannot rate it" unless data[:speed]
  end

  # All four output paths finish the same way, or this is two tools wearing one
  # name. Until 2026-08-12 process_file and run_random ran the finishing grain
  # and run_one_shot and run_watch did not, so the same --preset produced a
  # different negative depending on which entry point rendered it — and the thin
  # side of the split was replicate's --postpro handoff, which is the path that
  # makes the finals. Operator's call: all four grain.
  #
  # Read out of this file rather than asserted in prose, because the split had
  # already survived one round of being written down and left alone.
  # Reaching the finishing pass counts, and calling it by name is only one way to
  # reach it: run_random writes through process_file, and asserting on the
  # spelling failed a path whose behaviour was right. A check that measures a
  # spelling measures a spelling.
  calls_by_method = source_methods.transform_values { |body| postpro_method_calls(body) }
  ungrained = %w[process_file run_random run_uplift run_one_shot run_watch].reject do |name|
    postpro_method_reaches?(source_methods, name, "apply_finishing_grain", calls: calls_by_method)
  end
  unless ungrained.empty?
    problems << "output paths disagree on the finishing grain: #{ungrained.join(", ")} " \
                "#{ungrained.one? ? "does" : "do"} not run apply_finishing_grain, the rest do"
  end

  # apply_finishing_grain now stands down for a chain that grains itself, so the
  # standing note about every output being grained twice became a thing to check
  # rather than a thing to report.
  own = valid_presets.select { |_, p| Array(p[:fx]).include?("grain") }
  begin
    probe = Vips::Image.black(8, 8).bandjoin([Vips::Image.black(8, 8)] * 2).copy(interpretation: :srgb) + 128
    problems.concat(finishing_grain_probe_problems(own.keys, probe) do |image, name|
      apply_finishing_grain(image, name)
    end)
  rescue StandardError => e
    problems << "cannot build finishing-grain bypass probe: #{e.class}: #{e.message}"
  end
  notes << "#{own.length} of #{valid_presets.length} valid presets grain in their own chain; " \
           "the rest take the finishing pass"

  # One grain pass, at the end. A lane pool that also draws grain made
  # "grainx2" chains whose passes compounded with the halation drawn before
  # them — the destroyed rather than emulated complaint this tree had to grow
  # out of — so the pools are checked the way every other table is.
  grained_lanes = RANDOM_LANES.select { |_, spec| spec.fetch(:effects).include?(RANDOM_ALWAYS) }
  unless grained_lanes.empty?
    problems << "random lanes draw grain from their pools while the always-grain is appended: " \
                "#{grained_lanes.keys.join(", ")}"
  end

  # The grain model has its own vocabulary now, and the same rule applies to it:
  # a table nothing reads and a name nothing implements both fail quietly.
  problems << "GRAIN_CRYSTAL_FIELD is #{GRAIN_CRYSTAL_FIELD}, which grain_crystals does not build" \
    unless %i[worley perlin].include?(GRAIN_CRYSTAL_FIELD)
  stale = RANDOM_WEAR - RECIPE_ALLOWED
  problems << "RANDOM_WEAR names effects no chain can call: #{stale.join(", ")}" unless stale.empty?
  STOCKS.each do |name, data|
    unless data.is_a?(Hash)
      problems << "#{name}: stock definition is not a table"
      next
    end
    problems.concat(grain_knot_problems(name, data[:grain_knots]))
  end
  quoted, grain_problems = stock_grain_levels(STOCKS, GRAIN_SIGMA_SCALE)
  problems.concat(grain_problems)
  wild = quoted.select { |_, levels| levels < 0.5 || levels > 14.0 }
  problems << "granularity outside anything a scan measures: " \
              "#{wild.map { |n, l| "#{n} at #{l.round(1)} levels" }.join(", ")}" unless wild.empty?
  unless quoted.empty?
    notes << "grain is quoted in 8-bit levels at mid-grey: " \
             "#{quoted.minmax_by { |_, l| l }.map { |n, l| "#{n} #{l.round(1)}" }.join(" to ")}"
  end

  # CONFIG is empty unless a master.json sits beside this file, which is the
  # normal state. Saying so is the difference between a default and a setting
  # nobody can find the reader for.
  unless File.exist?(PostproBootstrap.master_config_path)
    notes << "no #{PostproBootstrap.master_config_path} — CONFIG is empty, so jpeg_quality, variations, " \
             "default_preset and apply_camera_profile_first all take their built-in fallbacks " \
             "(preset=house, and the camera-profile pass is ON: #{CAMERA_PROFILES.values.sum(&:size)} " \
             "bodies across #{CAMERA_PROFILES.size} vendors)"
  end

  # One actual pixel, through actual chains.
  #
  # Everything above reads tables, which is why a frozen memo cache — an error
  # raised in the first or second effect of every preset that has one — sat
  # here undetected while this same function printed "0 problems". A table
  # checker cannot see a runtime failure, so the checker has to run something.
  #
  # 8x8 pixels through four presets chosen to cover the machinery the table
  # checks cannot reach: HD.apply (film_curve), Spectral.adaptation_matrix
  # (spectral_temp), a black-and-white chain and a print chain. Milliseconds.
  smoke = %i[portrait cinematic noir masterpiece].select { |name| valid_presets.key?(name) }
  begin
    probe = Vips::Image.black(8, 8).add(128).cast("uchar").bandjoin([128, 128]).copy(interpretation: :srgb)
    problems.concat(preset_smoke_problems(smoke, probe) { |image, name| preset(image, name) })
  rescue StandardError => e
    problems << "cannot build 8x8 preset probe: #{e.class}: #{e.message}"
  end

  problems.each { |line| puts "BROKEN #{line}" }
  notes.each { |line| puts "NOTE   #{line}" }
  puts "#{PRESETS.length} presets, #{STOCKS.length} stocks, #{LENSES.length} lenses, " \
       "#{implemented.length} effects, #{RECIPE_ALLOWED.length} recipe-allowed — " \
       "#{problems.length} problem(s), #{notes.length} note(s)"
  problems.length
end

def run_introspect
  if ARGV.include?("--vocab-check")
    exit(vocab_check.zero? ? 0 : 1)
  elsif ARGV.include?("--capabilities")
    puts Studio::AnalogCapabilities.report(:postpro)
  elsif ARGV.include?("--list-presets")
    puts list_presets
  elsif ARGV.include?("--list-stocks")
    puts list_stocks
  elsif ARGV.include?("--list-lenses")
    puts list_lenses
  elsif (name = argv_flag("--describe-preset"))
    puts describe_preset(name)
  elsif (scan = argv_flag("--fit-grain"))
    puts fit_grain(scan)
  elsif ARGV.include?("--map")
    puts Studio::SourceMap.render(__FILE__)
  elsif ARGV.include?("--gallery")
    write_gallery(argv_flag("--gallery") || Dir.pwd)
  elsif (name = argv_flag("--css-filter"))
    puts css_filter(name.to_sym)
  elsif (name = argv_flag("--export-lut"))
    requested_output = argv_flag("--output")
    out = requested_output
    if out.to_s.empty?
      safe_name = name.to_s.gsub(/[^0-9A-Za-z_-]+/, "_")
      out = File.join(Postpro::Constitution::OUTPUT_DIR, "postpro_#{safe_name}.cube")
      out = Postpro::Constitution.available_output_path(out)
      Postpro::Constitution.verify_output!(input_path: __FILE__, output_path: out)
    else
      Postpro::Constitution.verify_distinct_source!(input_path: __FILE__, output_path: out)
    end
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

  if ARGV.include?("--tiff16")
    output_path = output_path.sub(/\.(jpg|jpeg|png|webp)$/i, ".tif")
  end
  Postpro::Constitution.verify_distinct_source!(input_path:, output_path:)

  image = load_image(input_path)
  unless image
    $cli_logger.error "Failed to load: #{input_path}"
    exit 1
  end

  processed = preset(image, preset_name)
  # Operator, 2026-08-12: the four entry points now grain identically. This one
  # and run_watch did not, so the same --preset gave a different negative
  # depending on whether it arrived through a batch or through replicate's
  # --postpro handoff -- and the handoff is the path that produces the finals.
  processed = apply_finishing_grain(anchor_tones(processed), preset_name)
  processed = rgb_bands(processed)
  quality = CONFIG["jpeg_quality"] || 95
  # process_file honours --tiff16 and this ignored it, so the one-shot mode
  # -- the mode replicate's --postpro handoff uses, and the only one with an
  # explicit output path -- quietly wrote 8-bit JPEG when asked for 16-bit TIFF.
  # A grading tool silently halving its bit depth is the kind of thing you find
  # much later, in the file.
  if ARGV.include?("--tiff16") || output_path.end_with?(".tif", ".tiff")
    output_path = output_path.sub(/\.(jpg|jpeg|png|webp)$/i, ".tif")
    processed.cast("ushort").write_to_file(output_path)
  else
    processed.write_to_file(output_path, Q: quality)
  end
  write_comparison(image, processed, output_path)
  sidecar = write_grade_sidecar(input_path, output_path, preset_name, image, processed)
  sidecar[:quality][:warnings].each { |warning| $cli_logger.info "warn #{warning}" }
  $cli_logger.info "ok preset=#{preset_name} out=#{output_path}"
end

def watch_mode?
  ARGV.include?("--watch")
end

# One frame through one preset on every stock, tiled in STOCKS order with each
# stock's name under its tile.
#
# The eye compares neighbours without moving between windows, and the
# difference between two emulsions is only visible side by side. Graded at
# STOCK_SHEET_CELL rather than at full size: fourteen full grades of a large
# frame take minutes, and grain is sized by image width, so a tile carries the
# grain a print of that size would.
STOCK_SHEET_CELL = 512
STOCK_SHEET_GAP = 12
STOCK_SHEET_LABEL = 22

def stock_sheet_label(stock, cell:)
  label = Vips::Image.text(stock.to_s, dpi: 62)
  label_height = STOCK_SHEET_LABEL - 4
  scale = [cell.to_f / label.width, label_height.to_f / label.height, 1.0].min
  label = label.resize(scale) if scale < 1.0
  label.ifthenelse([210, 210, 210], [18, 18, 18], blend: true)
end

def stock_sheet(image, preset_name, cell: STOCK_SHEET_CELL)
  small = rgb_bands(image.thumbnail_image(cell, height: cell, size: :down))
  stocks = STOCKS.keys
  tiles = stocks.map do |stock|
    graded = rgb_bands(apply_finishing_grain(preset(small, preset_name, stock: stock), preset_name))
    tag = stock_sheet_label(stock, cell:)
    tile = (Vips::Image.black(cell, cell + STOCK_SHEET_LABEL) + 18).cast(:uchar).bandjoin([18, 18])
    label_x = (cell - tag.width) / 2
    label_y = cell + 4 + ((STOCK_SHEET_LABEL - 4 - tag.height) / 2)
    tile.insert(graded.cast(:uchar), (cell - graded.width) / 2, (cell - graded.height) / 2)
        .insert(tag, label_x, label_y)
  end
  columns = Math.sqrt(stocks.length).ceil
  [Vips::Image.arrayjoin(tiles, across: columns, shim: STOCK_SHEET_GAP, background: [18, 18, 18]), stocks]
end

def run_stock_sheet
  input_path = argv_flag("--stock-sheet")
  preset_name = (argv_flag("--preset") || "house").to_sym
  abort "postpro: --stock-sheet needs a readable file" unless input_path && File.file?(input_path)
  abort "postpro: unknown preset #{preset_name}" unless PRESETS.key?(preset_name)

  ext = File.extname(input_path)
  requested_output = argv_flag("--output")
  output = requested_output
  if output.to_s.empty?
    safe_stem = File.basename(input_path, ext).gsub(/[^0-9A-Za-z_-]+/, "_")
    output = File.join(Postpro::Constitution.output_dir_for(input_path), "postpro_#{safe_stem}_stocks_#{preset_name}.jpg")
    output = Postpro::Constitution.available_output_path(output)
    Postpro::Constitution.verify_output!(input_path: input_path, output_path: output)
  else
    Postpro::Constitution.verify_distinct_source!(input_path:, output_path: output)
  end
  sheet, stocks = stock_sheet(load_image(input_path), preset_name)
  sheet.write_to_file(output, Q: CONFIG["jpeg_quality"] || 95)
  $cli_logger.info "ok stock sheet preset=#{preset_name} stocks=#{stocks.length} out=#{output}"
end

def random_mode?
  ARGV.include?("--random")
end

# A bare path names the subject: `postpro.rb photo.png` grades that one
# photograph, `postpro.rb ~/Pictures` a few random picks from the folder. Flag
# values are not paths (`--count 3` is not a file called 3), so every
# value-taking flag's token is set aside before the hunt.
VALUE_FLAGS = %w[
  --input --output --preset --reference --count -n --watch --describe-preset
  --css-filter --export-lut --size --stock-sheet --random --rescue --measure
  --against --set --fit-grain
].freeze

# Every bare path on the line is a subject, so `postpro.rb a.jpg b.jpg c.jpg`
# grades all three; it used to grade the first and drop the rest in silence.
# `uplift` is a mode word for --random, not a path.
def positional_subjects
  flag_values = VALUE_FLAGS.filter_map { |flag| argv_flag(flag) }
  ARGV.reject { |token| token.start_with?("-") || flag_values.include?(token) || token == "uplift" }
end

def positional_subject = positional_subjects.first

# --random names its subjects either as its own value (`--random photo.jpg`) or
# as bare paths anywhere else on the line. Without this, `--random --count 10
# photo.jpg` ignored the photograph and graded whatever sat in ~/Downloads.
def random_subjects
  named = argv_flag("--random")
  named = nil if named.nil? || named.start_with?("-") || named == "uplift" || !File.exist?(named)
  ([named] + positional_subjects).compact.uniq
end

# A batch is refused whole, before anything renders, when one of its paths is
# neither an image nor a folder: a typo at the end of the line must not cost
# the renders at the start of it a half-finished run.
def refuse_bad_subjects!(subjects)
  subjects.each do |subject|
    problem = subject_problem(subject)
    next unless problem

    $cli_logger.error "#{problem}: #{subject}"
    exit 1
  end
end

def subject_problem(subject)
  return "No such file or directory" unless File.exist?(subject)

  "Not an image" if File.file?(subject) && !subject.match?(/\.(jpe?g|png|webp)\z/i)
end

def run_random_subjects(subjects)
  return run_random if subjects.empty?

  refuse_bad_subjects!(subjects)
  subjects.each { |subject| run_random(subject) }
end

# Resolve the best available downloads directory on Android/Termux or desktop.
def downloads_dir
  candidates = [
    argv_flag("--random"),
    File.expand_path("~/storage/downloads"),
    "/sdcard/Download",
    File.expand_path("~/Downloads"),
    Dir.pwd,
  ]
  candidates.compact.find { |d| File.directory?(d) }
end

# --random [DIR] [uplift] [--count N], or a bare positional IMAGE | DIR
#
# Five to ten pictures per photograph (five in heavy mode, or exactly --count),
# each through its own chain, numbered in the order they were drawn and written
# beside the photograph they came from.
#
# The default used to be a pair of stacked presets applied to every image in
# the folder, which for a folder of two hundred is a long afternoon and two
# hundred near neighbours. A run is now a handful of genuinely different
# attempts, which is what random is for. `uplift` still stacks presets.
def run_random(subject = nil)
  dir = subject || downloads_dir

  files =
    if subject && File.file?(subject)
      [subject]
    else
      Dir.glob(File.join(dir, "**", "*.{jpg,jpeg,JPG,JPEG,png,PNG,webp,WEBP}"))
         .reject { |f| File.basename(f).match?(/processed|masterpiece|postpro|_v\d+_/) }
    end

  if files.empty?
    $cli_logger.error "No images in #{dir}"
    return
  end

  return run_uplift(dir, files) if ARGV.include?("uplift")

  # A fresh seed per run unless one was asked for, because the point of a random
  # run is that the next one differs. It is printed and written into every
  # sidecar, so POSTPRO_SEED=<that> renders the same variation family again.
  $postpro_seed = Random.new_seed % 2_147_483_647 unless ENV.key?("POSTPRO_SEED")
  rng = Random.new(postpro_seed)
  override = (argv_flag("--count") || argv_flag("-n"))&.to_i
  variations = override || RANDOM_TAKES
  PostproBootstrap.dmesg "random subject=#{subject || dir} pool=#{files.count} " \
                         "variations=#{variations} seed=#{$postpro_seed}"

  # A family of RANDOM_TAKES materially different attempts per image; --count
  # sets any other number. Heavy mode deals the lanes round-robin, so one run
  # always spans subtle analog to bleeding edge, and at ten it does so twice.
  files.each_with_index do |file, file_index|
    count = (override || RANDOM_TAKES).clamp(1, 24)

    Postpro::Constitution.verify_batch!(variation_count: count, explicit_count: !override.nil?)
    drawn = []
    looks = []
    Postpro::Constitution.retire_previous_renders!(file)
    count.times do |index|
      number = index + 1
      lane = heavy_mode? ? HEAVY_LANE_DEAL[index % HEAVY_LANE_DEAL.size] : nil

      attempts = 0
      refused = []
      begin
        look = heavy_mode? ? next_heavy_look(rng, looks + refused) : nil
        chain = look ? look_led_chain(rng, look:, avoid: drawn, lane:) : random_chain(rng, avoid: drawn, lane:)
        Postpro::Constitution.verify_chain!(chain: chain, stage_rank: random_stage_rank)
        drew = "#{File.basename(file)} — #{look} #{random_chain_name(chain)}"
        $cli_logger.info "#{file_index + 1}/#{files.count} #{number}/#{count}: #{drew}"

        take = RandomTake.new(number:, look:, lane: lane || random_chain_lane(chain))
        process_file(file, 1, nil, chain, take:)
        drawn << chain
        looks << look if look
      rescue RuntimeError => e
        # A take that destroyed the picture is drawn again, on another look.
        raise unless e.message.start_with?("all ") && (attempts += 1) < 4

        refused << look
        retry
      end
    rescue StandardError => e
      # One refused chain costs one take, not the rest of the family.
      failure = "take #{number} failed: #{e.message}"
      $logger.error "random #{File.basename(file)} #{failure}"
      $cli_logger.error failure
    end

    write_contact_sheet(file) if contact_sheet?
  rescue StandardError => e
    $logger.error "random #{File.basename(file)}: #{e.message}"
  end
end

# The contact sheet is on by default: a family of ten is judged side by side,
# not by opening ten files. POSTPRO_CONTACT=0 leaves it out.
def contact_sheet? = ENV.fetch("POSTPRO_CONTACT", "1") != "0"

# The takes of a source's current family, in draw order, read back from their
# sidecars rather than remembered, so the sheet shows what is on disk.
def family_takes(file)
  input = File.expand_path(file)
  sidecars = Dir.glob(File.join(Postpro::Constitution.output_dir_for(input), "postpro_*.json"))
  sidecars.filter_map { |sidecar| family_take(sidecar, input) }.sort_by { |entry| [entry[:take], entry[:path]] }
end

# One sidecar read as a take of `input`, or nil when it belongs to another
# source, is not a chain, has lost its picture, or cannot be read.
def family_take(sidecar, input)
  data = JSON.parse(File.read(sidecar, encoding: "UTF-8"))
  media = sidecar.delete_suffix(".json")
  return unless data["schema"] == "postpro.chain.v1" && data["input"] == input && File.file?(media)

  { take: data["take"].to_i, look: (data["look"] || data["lane"]).to_s, path: media }
rescue JSON::ParserError, SystemCallError => e
  $logger.debug "contact sheet skips #{File.basename(sidecar)}: #{e.message}"
  nil
end

CONTACT_TILE = [480, 720].freeze
CONTACT_ACROSS = 5
CONTACT_BACKGROUND = [17, 17, 17].freeze

# One picture of the whole family: every take tiled in draw order with its
# number and look beneath it, written beside the source like every render and
# carrying a sidecar, so the next run of that source retires it with the rest.
def write_contact_sheet(file)
  takes = family_takes(file)
  return if takes.size < 2

  output = contact_sheet_path(file)
  contact_sheet_image(takes).write_to_file(output, Q: 90)
  write_contact_sidecar(file, output:, takes:)
  $cli_logger.info "contact sheet: #{takes.size} takes in #{File.basename(output)}"

  output
rescue StandardError => e
  # The takes are the work; a sheet that cannot be drawn costs only itself.
  $logger.error "contact sheet #{File.basename(file)}: #{e.message}"
  $cli_logger.error "contact sheet failed: #{e.message}"
  nil
end

def contact_sheet_path(file)
  safe_stem = File.basename(file, File.extname(file)).gsub(/[^0-9A-Za-z_-]+/, "_")
  output = File.join(Postpro::Constitution.output_dir_for(file), "postpro_#{safe_stem}_contact.jpg")
  output = Postpro::Constitution.available_output_path(output)
  Postpro::Constitution.verify_output!(input_path: file, output_path: output)
  output
end

def contact_sheet_image(takes)
  cells = takes.map { |entry| contact_cell(entry) }
  Vips::Image.arrayjoin(cells, across: [CONTACT_ACROSS, cells.size].min, shim: 6,
                               background: CONTACT_BACKGROUND, valign: :low)
end

# A take's tile with its caption strip beneath it.
def contact_cell(entry)
  tile = rgb_bands(Vips::Image.thumbnail(entry[:path], CONTACT_TILE.first, height: CONTACT_TILE.last))
  caption = format("%02d  %s", entry[:take], entry[:look].tr("_", " "))
  tile.join(contact_label(caption, tile.width), :vertical, expand: true, background: CONTACT_BACKGROUND)
end

def write_contact_sidecar(file, output:, takes:)
  listed = takes.map { |entry| { take: entry[:take], look: entry[:look], file: File.basename(entry[:path]) } }

  write_sidecar(output, {
    schema: "postpro.contact.v1",
    generated_at: Time.now.utc.iso8601,
    input: File.expand_path(file),
    output: File.expand_path(output),
    seed: $postpro_seed,
    takes: listed,
  })
end

# A caption strip as wide as its tile. libvips draws text through Pango; a build
# without it still gets a sheet, captionless, rather than no sheet.
def contact_label(caption, width)
  text = Vips::Image.text(caption, dpi: 96, font: "sans 14")
  mask = text.embed(10, 8, width, text.height + 16)
  mask.ifthenelse([230, 230, 230], CONTACT_BACKGROUND, blend: true)
rescue Vips::Error
  (Vips::Image.black(width, 1) + CONTACT_BACKGROUND).cast(:uchar)
end

# The older behaviour, kept because stacking two presets is a different and
# still useful thing: it asks what the house grade does twice, where a random
# chain asks what the emulsion can do at all.
def run_uplift(dir, files)
  presets = PRESETS.keys.shuffle
  count = (argv_flag("--count") || argv_flag("-n") || 4).to_i.clamp(1, 6)
  PostproBootstrap.dmesg "uplift dir=#{dir} files=#{files.count}"
  files.each_with_index do |file, index|
    $cli_logger.info "#{index + 1}/#{files.count}: #{File.basename(file)}"
    count.times do |i|
      base = presets[(index + i) % presets.size]
      layer = (presets - [base]).sample
      image = load_image(file)
      next unless image

      processed = rgb_bands(apply_finishing_grain(preset_chain(image, [base, layer]), base))
      ext = File.extname(file)
      safe_stem = File.basename(file, ext).gsub(/[^0-9A-Za-z_-]+/, "_")
      output = File.join(Postpro::Constitution.output_dir_for(file),
                         "postpro_#{safe_stem}_#{base}+#{layer}_v#{i + 1}#{ext}")
      output = Postpro::Constitution.available_output_path(output)
      Postpro::Constitution.verify_output!(input_path: file, output_path: output)
      processed.write_to_file(output, Q: CONFIG["jpeg_quality"] || 95)
      write_grade_sidecar(file, output, [base, layer], image, processed)
      PostproBootstrap.dmesg "write chain=#{base}+#{layer} out=#{File.basename(output)}"
    end
    GC.start if (index % 5).zero?
  rescue StandardError => e
    $cli_logger.error "Error #{File.basename(file)}: #{e.message}"
  end
end

def run_watch
  dir = argv_flag("--watch") || "/sdcard/DCIM/Camera"
  preset_name = (argv_flag("--preset") || "cinematic").to_sym
  unless PRESETS.key?(preset_name)
    $cli_logger.error "Unknown preset: #{preset_name}"
    exit 1
  end
  # The output name matches the input glob, and run_watch carried none of the
  # reject guard the other two batch paths use, so every graded file was seen
  # as new and graded again: one seed image produced fourteen nested
  # generations in thirty seconds, on a directory that is a phone camera roll.
  already_graded = Regexp.union(PRESETS.keys.map(&:to_s) + %w[processed masterpiece postpro])
  watch_glob = lambda do
    Dir.glob(File.join(dir, "IMG_*.{jpg,jpeg,JPG,JPEG}"))
       .reject { |f| File.basename(f).match?(already_graded) || File.basename(f).match?(/_v\d+_/) }
  end
  seen = watch_glob.call.map { |f| [f, File.mtime(f)] }.to_h
  PostproBootstrap.dmesg "watch dir=#{dir} preset=#{preset_name} known=#{seen.size}"
  loop do
    sleep 2
    watch_glob.call.each do |path|
      mtime = File.mtime(path)
      next if seen[path] == mtime
      seen[path] = mtime
      next if File.size(path) < 50_000
      ext = File.extname(path)
      base = File.basename(path, ext).gsub(/[^0-9A-Za-z_-]+/, "_")
      out = File.join(Postpro::Constitution.output_dir_for(path), "postpro_#{base}_#{preset_name}#{ext}")
      out = Postpro::Constitution.available_output_path(out)
      Postpro::Constitution.verify_output!(input_path: path, output_path: out)
      PostproBootstrap.dmesg "new path=#{File.basename(path)} -> #{File.basename(out)}"
      begin
        grade_watched(path, out, preset_name)
        $cli_logger.info "ok preset=#{preset_name} out=#{out}"
      rescue StandardError => e
        $cli_logger.error "watch error: #{e.message}"
      end
    end
  end
end

# One photograph off the camera roll, graded and recorded. Out of the watch loop
# so a single arrival can be graded without a loop that never returns.
def grade_watched(path, out, preset_name)
  image = load_image(path)
  processed = rgb_bands(apply_finishing_grain(anchor_tones(preset(image, preset_name)), preset_name))
  processed.write_to_file(out, Q: CONFIG["jpeg_quality"] || 95)
  write_grade_sidecar(path, out, preset_name, image, processed)
end

def auto_launch
  return run_introspect if introspect_mode?
  return run_stock_sheet if ARGV.include?("--stock-sheet")
  return run_watch       if watch_mode?
  return run_one_shot    if one_shot_mode?
  return run_random_subjects(random_subjects) if random_mode?

  # A bare path is a subject, not a typo the menu swallows: an image gets the
  # chains --random would draw for it, a directory a few picks from it, and
  # several paths get one family each. A path that is neither file nor
  # directory is named and refused, because a menu opened on a typo reads as a
  # hang.
  subjects = positional_subjects

  return run_random_subjects(subjects) if subjects.any?
  if ARGV.include?("--auto") || (!$stdin.tty? && ARGV.include?("--from-replicate"))
    input = auto_mode
  elsif ARGV.include?("--from-replicate") && REPLICATE_PRESENT
    check_replicate
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
                process_file(file, variations, nil, random_chain)
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

  return unless REPLICATE_PRESENT && total_variations > 0
    $cli_logger.info "Tip: Run 'ruby replicate.rb' to generate more content!"

end

auto_launch if __FILE__ == $0
