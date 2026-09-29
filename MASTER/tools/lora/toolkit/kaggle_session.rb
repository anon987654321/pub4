#!/usr/bin/env ruby
# frozen_string_literal: true

# The Kaggle side of the Kaggle lane. Everything the session does happens here.
#
# Kaggle notebooks accept python, r and rmarkdown — Ruby has been asked for on
# their forums for years and is not offered — so the notebook itself cannot be
# Ruby. What it can be is four lines that install Ruby and call this file, which
# is what run_train_kaggle.rb generates. The training logic, the tree layout and
# the harvest all live in Ruby, on this side of that boundary.
#
# Invoked as:  ruby /kaggle/input/<dataset>/kaggle_session.rb
# Reads:       kaggle_session.json beside it, written when the payload was staged
# Expects:     HF_TOKEN in the environment, put there by the notebook

require "fileutils"
require "json"
require "pathname"

MOUNT = Pathname.new(__dir__).expand_path.freeze
PLAN = JSON.parse(MOUNT.join("kaggle_session.json").read).freeze

# The Kaggle paths, overridable so the rebuild and harvest can be exercised off
# Kaggle. This code only ever runs once per rented GPU-hour; being able to test
# it on a laptop is worth two env lookups.
ROOT = Pathname.new(ENV.fetch("LORA_KAGGLE_ROOT", "/kaggle/tmp/lora"))
SUBJECT_DIR = ROOT.join(PLAN.fetch("subject"))
TOOLKIT_DIR = ROOT.join("_toolkit")
DATASET_DIR = SUBJECT_DIR.join("dataset")
WEIGHTS_DIR = SUBJECT_DIR.join("weights", PLAN.fetch("model"))
OUT_DIR = SUBJECT_DIR.join("out")
WORKING = Pathname.new(ENV.fetch("LORA_KAGGLE_WORKING", "/kaggle/working"))
AI_TOOLKIT = Pathname.new(ENV.fetch("AI_TOOLKIT_ROOT", "/kaggle/tmp/ai-toolkit"))

IMAGE_EXT = %w[.jpg .jpeg .png .webp].freeze

def sh!(*command)
  puts "run: #{command.join(' ')}"
  system(*command) or abort "warn: failed: #{command.join(' ')}"
end

def abort_unless(condition, message)
  abort "warn: #{message}" unless condition
end

# /kaggle/working is capped at 20 GB and persists; /kaggle/tmp is ~60 GB and does
# not. FLUX.1-dev is larger than the former and worth nothing after the session,
# so the cache goes in the latter.
def prepare_environment
  abort_unless(!ENV["HF_TOKEN"].to_s.strip.empty?, "HF_TOKEN missing — the notebook did not set it")
  ENV["HUGGINGFACE_HUB_TOKEN"] = ENV.fetch("HF_TOKEN")
  ENV["HF_HOME"] = "/kaggle/tmp/hf"
  ENV["AI_TOOLKIT_ROOT"] = AI_TOOLKIT.to_s
  FileUtils.mkdir_p("/kaggle/tmp/hf")
end

# ai-toolkit stays a clone: it is upstream, this repo pins nothing in it, and its
# installer is its own business. --system-site-packages so the image's torch is
# reused — a clean venv pulls a second multi-GB torch off PyPI that is not
# matched to this box's driver, and spends session time doing it.
def install_ai_toolkit
  return puts "ok: ai-toolkit already present" if AI_TOOLKIT.join(".git").directory?

  sh!("git", "clone", "--depth", "1", "https://github.com/ostris/ai-toolkit.git", AI_TOOLKIT.to_s)
  sh!("python3", "-m", "venv", "--system-site-packages", AI_TOOLKIT.join(".venv").to_s)
  pip = AI_TOOLKIT.join(".venv/bin/pip").to_s
  sh!(pip, "install", "-q", "--upgrade", "pip", "wheel")
  sh!(pip, "install", "-q", "-r", AI_TOOLKIT.join("requirements.txt").to_s)
end

# The payload is flat, because `kaggle datasets` defaults to --dir-mode skip and
# Kaggle expands some archives on upload but not others. The split is decided by
# the generator and written into the plan, so nothing here guesses from names.
def rebuild_tree
  [TOOLKIT_DIR, DATASET_DIR, WEIGHTS_DIR].each(&:mkpath)
  toolkit = PLAN.fetch("toolkit")
  config = PLAN.fetch("subject_config")
  counts = Hash.new(0)

  MOUNT.children.sort.each do |item|
    next unless item.file?

    target =
      if toolkit.include?(item.basename.to_s) then TOOLKIT_DIR.join(item.basename).tap { counts[:toolkit] += 1 }
      elsif config.include?(item.basename.to_s) then SUBJECT_DIR.join(item.basename).tap { counts[:config] += 1 }
      elsif item.extname == ".safetensors" then WEIGHTS_DIR.join(item.basename).tap { counts[:checkpoint] += 1 }
      elsif IMAGE_EXT.include?(item.extname.downcase) || item.extname == ".txt"
        DATASET_DIR.join(item.basename).tap { counts[:data] += 1 }
      end
    next unless target

    FileUtils.cp(item, target)
    FileUtils.chmod(0o755, target)
  end

  puts "ok: #{counts.map { |key, value| "#{key} #{value}" }.join(', ')}"
  abort_unless(counts[:toolkit] == toolkit.length,
               "expected #{toolkit.length} toolkit files, mounted #{counts[:toolkit]}")
end

# cuda_t4 is a render_config.rb profile, not an ai-toolkit device: fp16 because
# Turing has no bf16, quantised because 16 GB will not hold FLUX.1-dev
# otherwise, 512 buckets because the budget here is the clock.
def train
  ENV["LORA_DEVICE"] = "cuda_t4"
  ENV["LORA_STEPS"] = PLAN.fetch("steps").to_s
  ENV["LORA_SAMPLE_EVERY"] = PLAN.fetch("sample_every").to_s
  ENV["LORA_SKIP_POSTPRO"] = "1"
  Dir.chdir(SUBJECT_DIR) { sh!("sh", SUBJECT_DIR.join("lora").to_s, "--train") }
end

# The adapter and the validation portraits leave the session; everything else is
# reproducible. ai-toolkit samples the curated prompt suite as it trains, so a
# training run is also the generate run — which is why this lane does not need a
# paid one to see a face.
def harvest
  checkpoints = WEIGHTS_DIR.glob("*.safetensors").sort
  checkpoints.each { |path| FileUtils.cp(path, WORKING.join(path.basename)) }

  portraits = OUT_DIR.directory? ? OUT_DIR.children.select { |p| IMAGE_EXT.include?(p.extname.downcase) } : []
  portraits.sort.each { |path| FileUtils.cp(path, WORKING.join(path.basename)) }

  puts "ok: wrote #{checkpoints.length} checkpoint(s) and #{portraits.length} portrait(s) to #{WORKING}"
  abort_unless(checkpoints.any?, "training produced no .safetensors")
end

STAGES = {
  "prepare" => -> { prepare_environment }, "install" => -> { install_ai_toolkit },
  "rebuild" => -> { rebuild_tree }, "train" => -> { train }, "harvest" => -> { harvest }
}.freeze

ENV.fetch("LORA_KAGGLE_STAGES", STAGES.keys.join(",")).split(",").each do |stage|
  STAGES.fetch(stage.strip) { abort "warn: no stage #{stage}" }.call
end
puts "ok: session complete"
