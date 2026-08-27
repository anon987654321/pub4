#!/usr/bin/env ruby
# frozen_string_literal: true

# The Colab side of the Colab lane. Everything the session does happens here.
#
# Colab runs Python notebooks, so the notebook cannot be Ruby — but it can be a
# handover, and this is what it hands over to. Same split as every other lane:
# Ruby owns the chain, Python appears only where ai-toolkit's run.py does.
#
# Why Colab at all: Kaggle gates both GPU and internet behind phone
# verification. An unverified account gets a CPU box with no network — measured,
# not assumed: a probe kernel reported torch 2.10.0+cpu, no nvidia-smi, no DNS,
# and no ruby. Colab's free tier asks for a Google account and nothing else.
#
# The GPU is the same 16 GB Turing T4 Kaggle would have given, so the cuda_t4
# profile in render_config.rb applies unchanged: fp16 because Turing has no
# bf16, quantised because 16 GB will not hold FLUX.1-dev otherwise.
#
# Invoked as:  ruby STUDIO/lora/_toolkit/colab_session.rb <subject>
# Expects:     HF_TOKEN in the environment, put there by the notebook

require "fileutils"
require "pathname"

SUBJECT = ARGV.fetch(0) { abort "warn: usage: colab_session.rb <subject>" }
REPO = Pathname.new(__dir__).join("../../..").expand_path
SUBJECT_DIR = REPO.join("STUDIO/lora", SUBJECT)
AI_TOOLKIT = Pathname.new(ENV.fetch("AI_TOOLKIT_ROOT", "/content/ai-toolkit"))

# Colab keeps nothing when the runtime recycles, and a free session is capped
# around 12 h with an idle disconnect well before that. Whatever is worth having
# after the tab closes goes to Drive, if the notebook mounted it.
PERSIST = Pathname.new(ENV.fetch("LORA_PERSIST_DIR", "/content/persist"))

IMAGE_EXT = %w[.jpg .jpeg .png .webp].freeze

# ai-toolkit saves as <name>_<step zero-padded to 9>.safetensors, and the name
# carries its own digits — ragnhild_v2_000001500 begins with a 2. Reading the
# first digit run scored every checkpoint identically and silently resumed from
# whichever had the newest mtime.
def step_of(path)
  path.basename.to_s[/(\d+)\.safetensors\z/, 1].to_i
end

def sh!(*command)
  puts "run: #{command.join(' ')}"
  return if system(*command)

  # A banner, because of where this output ends up. The notebook invokes this
  # script through subprocess.run(check=True), so a non-zero exit surfaces in
  # Colab as a CalledProcessError traceback with the Python frames of
  # subprocess.py in it and nothing about what actually failed. The real reason
  # is here, above that traceback, and it does not look like a heading — so
  # people paste the traceback and the traceback says only that ruby exited 1.
  #
  # The same shape as the Kaggle failure documented in lora/README.md, where
  # IPython's own formatter crashed while rendering a DNS error and buried it 80
  # lines up. Worth a marker anyone can search for.
  warn ""
  warn "=" * 72
  warn "FAILED: #{command.join(' ')}"
  warn "The Python traceback below this only reports that ruby exited non-zero."
  warn "The cause is the output ABOVE this banner."
  warn "=" * 72
  abort "warn: failed: #{command.join(' ')}"
end

def subject_env
  Hash[SUBJECT_DIR.join("subject.env").read.lines.filter_map do |line|
    key, value = line.strip.split("=", 2)
    [key, value] if value && !key.start_with?("#")
  end]
end

MODEL = subject_env.fetch("MODEL")
WEIGHTS_DIR = SUBJECT_DIR.join("weights", MODEL)
OUT_DIR = SUBJECT_DIR.join("out")

def prepare
  abort "warn: HF_TOKEN missing — the notebook did not set it" if ENV["HF_TOKEN"].to_s.strip.empty?
  ENV["HUGGINGFACE_HUB_TOKEN"] = ENV.fetch("HF_TOKEN")
  ENV["AI_TOOLKIT_ROOT"] = AI_TOOLKIT.to_s
  abort "warn: no subject at #{SUBJECT_DIR}" unless SUBJECT_DIR.directory?
  [WEIGHTS_DIR, PERSIST].each(&:mkpath)
  puts "ok: subject #{SUBJECT} model #{MODEL}"
end

# Can the toolkit actually run, as opposed to having been downloaded?
#
# The guard here used to be `.git exists`, and that is a fact about the clone
# rather than about the install. A session that cloned and then died — a pip
# failure, a runtime recycle, a closed tab — left a directory with .git in it
# and no dependencies, and every retry afterwards printed "ok: ai-toolkit
# already present" and went straight to training, where run.py died on its third
# line importing dotenv. The step that would have fixed it was the step being
# skipped, so the failure was perfectly repeatable and its cause was three lines
# above it saying everything was fine.
#
# Asked of the venv instead, which is where the answer lives: import the things
# run.py imports first. dotenv is what it actually failed on; torch and
# safetensors cost nothing extra to check and fail earlier if the venv was built
# against the wrong interpreter.
TOOLKIT_SENTINELS = "import dotenv, torch, safetensors, transformers"

def toolkit_ready?
  python = AI_TOOLKIT.join(".venv/bin/python")
  return false unless python.file?

  system(python.to_s, "-c", TOOLKIT_SENTINELS, out: File::NULL, err: File::NULL)
end

# A venv with pip in it, by whichever route works.
#
# `python3 -m venv` is not self-contained on Debian. The stdlib is split into
# packages and venv's bootstrap step, ensurepip, ships separately — so on an
# image without python3-venv the command creates the directory, reaches
# ensurepip, and exits 1 reporting the name of the subprocess that failed rather
# than the name of the package that is missing. It reads as a Python fault and
# is an apt one.
#
# The notebook installs python3-venv now, which should make the first branch
# work. This exists because that is a fix in a different file: a notebook
# regenerated from an older run_train_colab.rb, or any host whose image differs,
# lands back here. virtualenv carries its own pip and needs no stdlib package,
# so it works where venv does not.
def make_venv(path)
  return puts "ok: venv already at #{path}" if path.join("bin/python").file?

  puts "run: python3 -m venv --system-site-packages #{path}"
  return puts "ok: venv created" if system("python3", "-m", "venv", "--system-site-packages", path.to_s)

  puts ""
  puts "note: `python3 -m venv` failed. On Debian that is usually python3-venv"
  puts "note: missing rather than anything wrong with Python — ensurepip lives in"
  puts "note: that package. Falling back to virtualenv, which bundles its own pip."
  FileUtils.rm_rf(path)
  sh!("python3", "-m", "pip", "install", "-q", "--upgrade", "virtualenv")
  sh!("python3", "-m", "virtualenv", "--system-site-packages", path.to_s)
  puts "ok: venv created by virtualenv"
end

def install_ai_toolkit
  return puts "ok: ai-toolkit present and importable" if toolkit_ready?

  if AI_TOOLKIT.join(".git").directory?
    puts "note: ai-toolkit is cloned but its dependencies do not import — installing"
  else
    sh!("git", "clone", "--depth", "1", "https://github.com/ostris/ai-toolkit.git", AI_TOOLKIT.to_s)
  end
  # Colab's own torch is CUDA-matched to its driver; a clean venv would pull a
  # second multi-GB one off PyPI that is not. run_ai_toolkit.rb requires a venv
  # python, so it stays a venv — one that can see the image's packages.
  make_venv(AI_TOOLKIT.join(".venv"))
  pip = AI_TOOLKIT.join(".venv/bin/pip").to_s
  sh!(pip, "install", "-q", "--upgrade", "pip", "wheel")

  install_requirements(pip)
end

# Exact pins that predate the interpreter Colab now ships.
#
# ai-toolkit pins these to a single version, and none of those versions
# publishes a cp313 wheel. On Colab's Python 3.13 pip therefore falls back to
# building from source, which for scipy wants a Fortran toolchain that is not
# on the image. The pin is the problem, not the package: every one of these has
# a later release that installs cleanly.
#
# Relaxed to a floor rather than removed, so pip still refuses a version older
# than the one the toolkit was written against.
STALE_PINS = %w[scipy albumentations albucore optimum-quanto torchao].freeze

# Install, and if an exact pin is what stopped it, relax those pins and say so.
#
# Deliberately a fallback rather than the first attempt. The pins are the
# author's intent and they may matter; trying them first means an environment
# where they work gets what ai-toolkit asked for. Only when that fails does this
# trade an exact version for an install that exists at all — and it prints what
# it changed, because a silent version substitution in a training pipeline is
# the kind of thing that surfaces three hours later as a strange loss curve.
def install_requirements(pip)
  requirements = AI_TOOLKIT.join("requirements.txt")
  puts "run: #{pip} install -r #{requirements} (verbose; several pins predate Colab's Python 3.13)"
  return puts "ok: requirements installed as pinned" if system(pip, "install", "-r", requirements.to_s)

  relaxed = relax_pins(requirements)
  puts ""
  puts "note: the pinned install failed. Retrying with these exact pins relaxed to floors:"
  puts "note:   #{STALE_PINS.join(', ')}"
  puts "note: none of them publishes a wheel for Python 3.13, which is what Colab runs."
  sh!(pip, "install", "-r", relaxed.to_s)
  puts "ok: requirements installed with #{STALE_PINS.length} pin(s) relaxed"
end

# Flatten the -r includes, then relax. Both halves are necessary.
#
# requirements.txt opens with `-r requirements_base.txt` and holds exactly one
# stale pin of its own; the other four are in that base file. So relaxing only
# the top-level file misses four of the five. And a relaxed copy written
# somewhere else keeps the `-r requirements_base.txt` line, which pip resolves
# relative to the file it is reading — so the copy would look for a base file
# that is not beside it and fail on something unrelated to the pins.
#
# Inlining the includes solves both: one flat file, every pin visible, no
# relative reference left to break. Written into the toolkit directory anyway,
# so anything else in there resolving by relative path still does.
def relax_pins(requirements, depth = 0)
  out = AI_TOOLKIT.join("requirements_relaxed.txt")
  out.write(flatten_requirements(requirements).map { |line| relax_line(line) }.join)
  out
end

def flatten_requirements(path, seen = [])
  return [] if seen.include?(path.to_s) || seen.length > 8

  seen << path.to_s
  path.readlines.flat_map do |line|
    include = line[/\A\s*-r\s+(\S+)/, 1]
    next [line] unless include

    nested = path.dirname.join(include)
    nested.file? ? ["# inlined from #{include}\n", *flatten_requirements(nested, seen)] : [line]
  end
end

def relax_line(line)
  name = line[/\A\s*([A-Za-z0-9_.\-]+)\s*==/, 1]
  return line unless name && STALE_PINS.include?(name.downcase)

  line.sub("==", ">=")
end

# A checkpoint saved to Drive last session is the only reason a second session
# is cheaper than a first. ai-toolkit resumes from the newest save in the
# training folder, reading the step back out of the safetensors metadata.
def restore_checkpoints
  saved = PERSIST.glob("*.safetensors").sort
  return puts "ok: no checkpoint to resume from" if saved.empty?

  newest = saved.max_by { |path| [step_of(path), path.mtime] }
  FileUtils.cp(newest, WEIGHTS_DIR.join(newest.basename))
  puts "ok: resuming from #{newest.basename}"
end

def train
  ENV["LORA_DEVICE"] = "cuda_t4"
  ENV["LORA_SKIP_POSTPRO"] = "1"
  ENV["LORA_STEPS"] = ENV["LORA_STEPS"].to_s.strip.empty? ? "1800" : ENV["LORA_STEPS"]
  ENV["LORA_SAMPLE_EVERY"] = ENV["LORA_SAMPLE_EVERY"].to_s.strip.empty? ? "500" : ENV["LORA_SAMPLE_EVERY"]
  Dir.chdir(SUBJECT_DIR) { sh!("sh", SUBJECT_DIR.join("lora").to_s, "--train") }
end

# The adapter and the validation portraits are the deliverables. ai-toolkit
# samples the curated prompt suite as it trains, so a training run is also the
# generate run — which is why this lane needs no paid one to see a face.
def harvest
  checkpoints = WEIGHTS_DIR.glob("*.safetensors").sort
  portraits = OUT_DIR.directory? ? OUT_DIR.children.select { |p| IMAGE_EXT.include?(p.extname.downcase) }.sort : []
  (checkpoints + portraits).each { |path| FileUtils.cp(path, PERSIST.join(path.basename)) }

  puts "ok: #{checkpoints.length} checkpoint(s) and #{portraits.length} portrait(s) in #{PERSIST}"
  abort "warn: training produced no .safetensors" if checkpoints.empty?
end

STAGES = {
  "prepare" => -> { prepare }, "install" => -> { install_ai_toolkit },
  "restore" => -> { restore_checkpoints }, "train" => -> { train }, "harvest" => -> { harvest }
}.freeze

ENV.fetch("LORA_COLAB_STAGES", STAGES.keys.join(",")).split(",").each do |stage|
  STAGES.fetch(stage.strip) { abort "warn: no stage #{stage}" }.call
end
puts "ok: session complete"
