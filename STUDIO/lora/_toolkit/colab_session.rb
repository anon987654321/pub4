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
  sh!("python3", "-m", "venv", "--system-site-packages", AI_TOOLKIT.join(".venv").to_s)
  pip = AI_TOOLKIT.join(".venv/bin/pip").to_s
  sh!(pip, "install", "-q", "--upgrade", "pip", "wheel")

  # NOT -q.
  #
  # This install has not yet been observed to run on Colab at all: the first
  # session cloned and stopped, and every session after it skipped this line
  # because of the guard above. So whether it succeeds is genuinely unknown, and
  # the one thing worth guaranteeing is that the answer arrives legibly.
  #
  # There is a specific reason to expect trouble rather than an assumption of
  # it. requirements.txt hard-pins versions older than the interpreter Colab now
  # ships — scipy==1.12.0 publishes wheels for cp39-cp312 and Colab is on 3.13,
  # which means a source build and a Fortran toolchain that is not there;
  # albumentations, albucore, optimum-quanto and torchao are pinned the same
  # way. If that is what happens, this line is where it will say so.
  puts "note: installing ai-toolkit requirements verbosely. Several pins predate Colab's"
  puts "note: Python 3.13 (scipy==1.12.0 has no cp313 wheel), so read this if it stops."
  sh!(pip, "install", "-r", AI_TOOLKIT.join("requirements.txt").to_s)
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
