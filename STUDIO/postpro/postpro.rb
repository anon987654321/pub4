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

# The entrypoint and its directory, for the lib/ files that name this file;
# __FILE__ inside them is their own path.
POSTPRO_ENTRY = __FILE__
POSTPRO_DIR = __dir__

# Loaded in this order after the boot sections below: constants read the
# tables loaded before them.
POSTPRO_LIB = %w[
  stocks presets presets_more hd spectral grain
  relight effects_optical effects_process effects_video effects_print take_check
  effects_finish tonemap grade_step random_chain random_takes recipe
  pipeline sidecars fit_grain introspection audits vocab_check
  quality_analyzer correction_proposer
  cli contact_sheet launch
].freeze

# Everything --vocab-check reads as this tool's source.
POSTPRO_SOURCE_FILES = [
  POSTPRO_ENTRY,
  *(%w[early_modes] + POSTPRO_LIB).map { |name| File.join(POSTPRO_DIR, "lib", "#{name}.rb") },
  File.join(POSTPRO_DIR, "uncanny.rb"),
  File.join(POSTPRO_DIR, "motion.rb"),
  File.join(POSTPRO_DIR, "motion_process.rb"),
].freeze

BOOTSTRAP = PostproBootstrap.run

# Still-image batches accept jpg/jpeg/png/webp. The optional --video path below
# is a separate, bounded MP4 workflow: one Ruby process grades raw frames in
# process, and refuses variable-rate inputs, unbounded work or failed muxing.
# The original per-frame subprocess experiment was removed after an hour per
# minute of 1080p and timed-out tests; see ARCHAEOLOGY.md for the evidence.
POSTPRO_USAGE = <<~TXT
  usage: postpro.rb [flags]           with no flags, asks what to grade
  usage: postpro.rb IMAGE... | DIR... ten light analog takes per image and a contact
                                      sheet, all written beside the image
    --video FILE --output FILE.mp4 [--preset NAME] [--grain-hold]
                                    grade a constant-rate video in one Ruby process

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
dedicated_mode = (%w[--watch --stock-sheet --rescue --export-lut --video] & ARGV).any?
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

# --rescue, --set and --measure: each runs and exits straight after boot.
require_relative "lib/early_modes"

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

POSTPRO_LIB.each { |name| require_relative "lib/#{name}" }

# onnxruntime aborts the process in its native teardown at exit on macOS
# ("recursive_mutex lock failed"), after every write has finished, and a caller
# reads that abort as a failed grade. A run that loaded the depth model leaves
# by exit!, with the status it was about to return; any other run exits as usual.

if __FILE__ == $0
  status = begin
    if ARGV.include?("--video")
      require_relative "motion"
      postpro_video_mode
    else
      auto_launch
      0
    end
  rescue SystemExit => e
    e.status
  end
  exit(status) unless Postpro::Depth.loaded?

  $stdout.flush
  $stderr.flush
  exit!(status)
end
