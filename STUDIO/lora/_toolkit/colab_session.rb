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

def install_ai_toolkit
  return puts "ok: ai-toolkit already present" if AI_TOOLKIT.join(".git").directory?

  sh!("git", "clone", "--depth", "1", "https://github.com/ostris/ai-toolkit.git", AI_TOOLKIT.to_s)
  # Colab's own torch is CUDA-matched to its driver; a clean venv would pull a
  # second multi-GB one off PyPI that is not. run_ai_toolkit.rb requires a venv
  # python, so it stays a venv — one that can see the image's packages.
  sh!("python3", "-m", "venv", "--system-site-packages", AI_TOOLKIT.join(".venv").to_s)
  pip = AI_TOOLKIT.join(".venv/bin/pip").to_s
  sh!(pip, "install", "-q", "--upgrade", "pip", "wheel")

  # NOT -q, and that is the whole point of this line.
  #
  # The requirements hard-pin versions that predate the interpreter Colab now
  # ships: scipy==1.12.0 has wheels for cp39-cp312 only, and Colab is on 3.13,
  # so pip falls back to building it from source and fails on a missing Fortran
  # toolchain. Several other pins (albumentations, albucore, optimum-quanto,
  # torchao) are the same shape.
  #
  # Under -q none of that reaches the log. The install failed, sh! aborted, the
  # notebook raised CalledProcessError, and the only visible artefact was a
  # Python traceback about subprocess.py — a diagnostic suppressed at the exact
  # point it was needed. Resolver output is verbose; a failure nobody can read
  # is worse.
  puts "note: installing ai-toolkit requirements verbosely — several pins predate Colab's Python,"
  puts "note: and under -q a resolution failure arrives as a traceback about subprocess.py."
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
