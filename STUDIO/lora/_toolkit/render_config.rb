#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "yaml"
require "pathname"

# The subject is chosen by the wrapper that invoked this (see _toolkit/lib.sh):
# SUBJECT_DIR points at STUDIO/lora/<subject>, and subject.env there
# names SUBJECT, MODEL and TRIGGER.
SUBJECT = ENV.fetch("SUBJECT") { abort "run a subject wrapper, not this script directly" }
MODEL = ENV.fetch("MODEL") { abort "run a subject wrapper, not this script directly" }
SUBJECT_DIR = Pathname.new(ENV.fetch("SUBJECT_DIR")).expand_path.freeze

# Per-subject data lives with the subject, not with the shared toolkit. The file
# is train.yaml, not train_<subject>.yaml, for the reason the LORA_* env knobs
# are not RAGNHILD_*: the directory already says whose it is.
ROOT = SUBJECT_DIR.to_s
BASE = File.join(ROOT, "train.yaml")

# cuda_t4 is not a device ai-toolkit knows — it is a cuda profile. Kaggle's free
# tier is a 16 GB Turing T4, which has no bf16 at all and cannot hold FLUX.1-dev
# unquantised, so it needs the low-VRAM settings the Mac uses with the 8-bit
# optimizer the Mac cannot use. See DEVICE_YAML for what actually reaches YAML.
ALLOWED_DEVICES = %w[mps cuda cuda_t4 cpu].freeze
DEVICE_YAML = { "cuda_t4" => "cuda" }.freeze

def load_mapping(path)
  data = YAML.load_file(path)
  abort "warn: expected mapping in #{path}" unless data.is_a?(Hash)
  data
end

def resolve_device
  device = ENV.fetch("LORA_DEVICE", "mps").downcase
  unless ALLOWED_DEVICES.include?(device)
    abort "warn: LORA_DEVICE must be one of: #{ALLOWED_DEVICES.join(', ')}"
  end
  device
end

def apply_device!(process)
  device = resolve_device
  process["device"] = DEVICE_YAML.fetch(device, device)

  model = process["model"]
  if ENV.key?("LORA_LOW_VRAM")
    low = ENV["LORA_LOW_VRAM"] != "0"
    model["low_vram"] = low
    model["quantize"] = low
    return
  end

  train = process["train"]
  case device
  when "cuda"
    model["low_vram"] = false
    model["quantize"] = false
    train["optimizer"] = "adamw8bit"
  when "cuda_t4"
    # 16 GB will not hold FLUX.1-dev in bf16, so quantise and stream like the Mac.
    model["low_vram"] = true
    model["quantize"] = true
    # bitsandbytes needs sm_75, which Turing is exactly; the Mac's blocker was
    # CUDA-only kernels, not capability, so the T4 keeps the 8-bit optimizer.
    train["optimizer"] = "adamw8bit"
    # Turing has no bf16 at all — a bf16 config here is a hard failure, not a
    # slow path. This is the one setting that must not be inherited.
    train["dtype"] = "fp16"
    # A 12 h session ceiling is the real budget; 1024 buckets spend it on
    # resolution instead of steps, and identity comes from steps.
    process["datasets"].first["resolution"] = [512] unless ENV.key?("LORA_RESOLUTIONS")
  when "mps"
    model["low_vram"] = true
    model["quantize"] = true
    # bitsandbytes 8-bit optimizers are CUDA-only; adamw runs on MPS.
    train["optimizer"] = "adamw"
    # bf16 on MPS can yield NaN loss; fp16 is more stable on Apple Silicon.
    train["dtype"] = "fp16"
    train["lr"] = 1.0e-5 unless ENV.key?("LORA_LR")
    # M2 8 GB: single resolution bucket reduces VRAM churn.
    process["datasets"].first["resolution"] = [512] unless ENV.key?("LORA_RESOLUTIONS")
  when "cpu"
    # cpu was in ALLOWED_DEVICES and in run_generate.sh's help, and had no
    # branch here at all -- so it fell through the case and inherited
    # train.yaml verbatim: adamw8bit, which IS bitsandbytes and IS CUDA-only,
    # plus 512/768/1024 buckets. The one device that certainly has no CUDA was
    # the one configured to use a CUDA optimizer. It would not have failed at
    # config time; it would have failed inside torch, after the model download.
    model["low_vram"] = true
    model["quantize"] = true
    train["optimizer"] = "adamw"
    process["datasets"].first["resolution"] = [512] unless ENV.key?("LORA_RESOLUTIONS")
    # Not a lane, an escape hatch. FLUX.1-dev is 12B parameters; a CPU step is
    # minutes, so 1800 of them is not a training run you will finish. Say so
    # rather than let it look like a supported choice.
    warn "warn: LORA_DEVICE=cpu will run, but FLUX.1-dev on CPU is minutes per step — " \
         "use --train-kaggle or --train-colab for a free GPU"
  end
end

# Every LORA_* knob declared and never read.
#
# LORA_LR and LORA_RESOLUTIONS only suppressed a device default — the branches
# above test ENV.key? to hold off their own figure, and then nothing set the
# one you asked for. LORA_FLUX_MODEL and LORA_FLUX_MODEL_PATH were worse: they
# moved the licence check in check_hf_flux_access.rb to a repo the trainer did
# not then load, so a local FLUX checkout passed the gate and downloaded the
# gated one anyway.
def apply_env_overrides!(process)
  lr = ENV["LORA_LR"].to_s.strip
  process["train"]["lr"] = Float(lr) unless lr.empty?

  resolutions = ENV["LORA_RESOLUTIONS"].to_s.strip
  unless resolutions.empty?
    process["datasets"].first["resolution"] = resolutions.split(",").map { |value| Integer(value.strip) }
  end

  # A path on disk wins over a repo id, since having the weights locally is the
  # reason to name one.
  local = ENV["LORA_FLUX_MODEL_PATH"].to_s.strip
  repo = ENV["LORA_FLUX_MODEL"].to_s.strip
  process["model"]["name_or_path"] = repo unless repo.empty?
  process["model"]["name_or_path"] = local unless local.empty?

  # Sessions that end on a wall clock rather than at convergence — Kaggle caps a
  # GPU session at 12 h — train to a step count and resume from the last save.
  steps = ENV["LORA_STEPS"].to_s.strip
  process["train"]["steps"] = Integer(steps) unless steps.empty?

  # Twelve prompts is a real slice of a rented hour. On a machine billed by the
  # clock the suite is worth less often than on the Mac, where the run is only
  # competing with itself.
  sample_every = ENV["LORA_SAMPLE_EVERY"].to_s.strip
  process["sample"]["sample_every"] = Integer(sample_every) unless sample_every.empty?
end

def build(mode)
  config = load_mapping(BASE)
  process = config.fetch("config").fetch("process").first

  process["training_folder"] = File.join(ROOT, "weights")
  process["datasets"].first["folder_path"] = File.join(ROOT, "dataset")
  requested_prompt = ENV["LORA_PROMPT"].to_s.strip
  # A direct request gets one exact prompt, while training keeps the curated suite.
  process["sample"]["prompts"] = [requested_prompt] unless requested_prompt.empty?
  apply_device!(process)
  apply_env_overrides!(process)

  if mode == "generate"
    train = process.fetch("train").dup
    train["start_step"] = train.fetch("steps")
    train["force_first_sample"] = true
    process["train"] = train
  end

  config
end

options = { mode: "train", output: nil }
OptionParser.new do |parser|
  parser.on("--mode MODE", %w[train generate], "train or generate") { |value| options[:mode] = value }
  parser.on("--output PATH", "resolved ai-toolkit yaml path") { |value| options[:output] = value }
end.parse!

abort "warn: --output required" if options[:output].to_s.empty?

File.write(options[:output], YAML.dump(build(options[:mode])))
puts "ok: rendered #{options[:mode]} -> #{options[:output]}"
