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

# LORA_BASE=sdxl — train against SDXL instead of FLUX.1-dev.
#
# Not a preference. FLUX.1-dev's weights are 23.8 GB of fp16 and diffusers
# materialises them in host RAM before quantisation can move anything to the
# card; a free Colab has 12.7 GB and the kernel is killed at "Loading checkpoint
# shards". Swap would let it spill, and Colab's container refuses swapon. There
# is no arrangement of that machine in which 23.8 fits in 12.7.
#
# SDXL is 6.9 GB and fits with room to spare. It is a genuine step down for this
# job — 2.6B UNet against a 12B rectified-flow transformer — and where it shows
# is exactly the thing a subject LoRA is for: FLUX holds a specific face across
# changes of light and angle, SDXL drifts toward a generic one as the scene
# varies, and it follows a long prompt less faithfully. Twelve validation
# prompts each naming a lighting setup, a film stock and a focal length are more
# than it will honour.
#
# It is the right call anyway when the alternative is no photographs tonight.
#
# Everything FLUX-specific has to go, not just the path. flowmatch is FLUX's
# scheduler and SDXL wants ddpm. guidance 3.5 is a FLUX number; SDXL is trained
# for about 7 and looks washed out below 5. quantize exists to make 12B fit and
# costs quality on a model that already does. And SDXL is trained at 1024, so
# the 512 buckets the T4 profile imposes for FLUX would train it below its own
# native resolution — 768 is the compromise that fits a 16 GB card.
SDXL_MODEL = "stabilityai/stable-diffusion-xl-base-1.0"

def apply_sdxl!(process)
  model = process["model"]
  model["name_or_path"] = SDXL_MODEL
  model.delete("is_flux")
  model["is_xl"] = true
  # Both were for a 12B transformer on a 16 GB card. SDXL needs neither, and
  # quantising a model that already fits only costs precision.
  model["quantize"] = false
  model["low_vram"] = false

  train = process["train"]
  train["noise_scheduler"] = "ddpm"
  # timestep_type belongs to flowmatch. Under ddpm it is at best ignored and at
  # worst a config error, and leaving a key the scheduler does not read is the
  # inert-declaration failure this repo keeps finding.
  train.delete("timestep_type")

  sample = process["sample"]
  sample["guidance_scale"] = 7.0
  sample["sample_steps"] = 30

  # 768 rather than the T4 profile's 512: SDXL is trained at 1024 and 512 costs
  # it detail it was built to carry. 1024 does not fit alongside the optimizer
  # on a 16 GB Turing card.
  process["datasets"].first["resolution"] = [768] unless ENV.key?("LORA_RESOLUTIONS")

  warn "note: LORA_BASE=sdxl — SDXL 1.0 at 768, ddpm, guidance 7, no quantisation."
  warn "note: chosen because FLUX.1-dev cannot be loaded in 12.7 GB of host RAM."
  warn "note: likeness across varied light will be weaker than FLUX would give."
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
  apply_sdxl!(process) if ENV["LORA_BASE"].to_s.strip.downcase == "sdxl"

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
