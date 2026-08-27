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

# SDXL's own VAE overflows in fp16 and the loss becomes NaN.
#
# Observed, not anticipated: a 1000-step run reported `loss: 0.000e+00` from
# step one and then several hundred consecutive `loss is nan` lines. It saved
# checkpoints at 250 and 500 and both are worthless — a NaN gradient updates
# nothing, so the adapter came out untrained while the run looked healthy from
# the progress bar.
#
# The cause is well known and specific: SDXL was trained in fp32/bf16 and its
# VAE has activations that exceed fp16's range. Everywhere else the answer is
# bf16 — and Turing, which is what a free Colab T4 is, has no bf16 at all. That
# is the same constraint that forced fp16 here in the first place, so the two
# requirements collide and the VAE is the only place to break the deadlock.
#
# madebyollin/sdxl-vae-fp16-fix is that break: the same VAE with its weights
# rescaled so the activations stay inside fp16. It is the standard remedy and
# costs nothing.
SDXL_VAE_FP16_FIX = "madebyollin/sdxl-vae-fp16-fix"

def apply_sdxl!(process)
  model = process["model"]
  model["name_or_path"] = SDXL_MODEL
  model.delete("is_flux")
  model["is_xl"] = true
  model["vae_path"] = SDXL_VAE_FP16_FIX if process.dig("train", "dtype").to_s == "fp16"
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
  # Sample with the scheduler the model was trained under. train.yaml is written
  # for FLUX, where flowmatch is right for both; switching only the training half
  # left SDXL being denoised on a flow-matching sigma schedule it has never seen.
  #
  # This is what "blurry, like hairy skin" was. A mismatched schedule does not
  # fail — it takes the wrong size step at every point on the curve and arrives
  # somewhere soft, so the picture looks like an undertrained adapter and gets
  # blamed on the training. The first twelve portraits of Ragnhild were rendered
  # this way.
  # Train the text encoder on SDXL, where the trigger token has to learn to mean
  # a specific person.
  #
  # train.yaml says false because it was written for FLUX, whose T5 is frozen by
  # design and where the transformer carries identity on its own. SDXL is not
  # that: with the text encoder frozen, "ragnhild" keeps whatever CLIP already
  # thought the word meant, and the UNet has to drag the face there against a
  # fixed conditioning vector. It is the single largest likeness lever available
  # on this base and it was off all day.
  #
  # Found by reading a LoRA Johann trained on Replicate in June, still sitting in
  # his Downloads: 386 tensors, `text_encoder:N:rank: 16` throughout, plus <s1>
  # and <s2> embeddings. Whatever produced that had this on.
  #
  # FLUX is left alone — apply_sdxl! is the only caller, so this cannot reach a
  # FLUX run. LORA_TEXT_ENCODER=0 turns it off if a 16 GB card refuses it.
  unless ENV["LORA_TEXT_ENCODER"].to_s.strip == "0"
    process["train"]["train_text_encoder"] = true
    warn "note: training the text encoder — on SDXL the trigger token has to learn the person."
  end

  sample["sampler"] = "ddpm"
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

  # Johann set LORA_RANK=16 and LORA_ALPHA=16 in a notebook cell to cut VRAM, the
  # cell printed "Set LORA_RANK to 16", and the run trained at 32 — no reader
  # existed. Eight other LORA_* knobs had one, which is exactly what makes a
  # missing ninth invisible: the convention says it should work.
  #
  # Worth having beyond that. Rank is the adapter's capacity, and on a
  # seven-image set 32 is enough capacity to memorise the pictures rather than
  # the person — including their grade and their backgrounds. 16 is the usual
  # recommendation for a single-subject set this small. The default stays 32
  # because changing it silently would swap one unexamined number for another;
  # the knob is what was missing.
  #
  # alpha defaults to rank when unset, since alpha/rank is the scaling factor and
  # setting one without the other changes the effective learning rate by the
  # ratio — a surprise that reads as "rank 16 trains worse".
  # What size to render, and how many steps.
  #
  # train.yaml samples at 1024x1024 and 30 steps, which is SDXL's native size and
  # the right default on a real GPU. On an M2 with 8 GB of unified memory it is
  # not a slow path, it is a different regime: Metal asked for 12.5 GB, the
  # machine paged on every denoising step, GPU utilisation sat at 22%, and one
  # frame had not finished after fifty minutes. 24 frames would have been twenty
  # hours.
  #
  # Dropping to 768 cuts the activation tensors to roughly half, which is the
  # difference between fitting and not fitting. That is a step change rather than
  # a percentage — a run that stops paging does not get 40% faster, it gets whole
  # multiples faster.
  #
  # Separate knobs because the reasons differ: size is a memory decision and
  # steps is a time-quality one.
  sample_size = ENV["LORA_SAMPLE_SIZE"].to_s.strip
  unless sample_size.empty?
    process["sample"]["width"] = process["sample"]["height"] = Integer(sample_size)
    warn "note: sampling at #{sample_size}px"
  end

  sample_steps = ENV["LORA_SAMPLE_STEPS"].to_s.strip
  unless sample_steps.empty?
    process["sample"]["sample_steps"] = Integer(sample_steps)
    warn "note: #{sample_steps} denoising steps"
  end

  rank = ENV["LORA_RANK"].to_s.strip
  alpha = ENV["LORA_ALPHA"].to_s.strip
  unless rank.empty? && alpha.empty?
    network = process["network"]
    network["linear"] = Integer(rank) unless rank.empty?
    network["linear_alpha"] = alpha.empty? ? network["linear"] : Integer(alpha)
    warn "note: LoRA rank #{network['linear']}, alpha #{network['linear_alpha']}"
  end

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

# The twelve in train.yaml and the fifty in shoots.yml are different jobs.
#
# The twelve are a validation suite, chosen to disagree with each other as much
# as possible — hard sun against candlelight against overcast — so that watching
# them during training shows whether the likeness holds when the light changes.
# Diversity is the whole point and swapping them costs the diagnostic.
#
# The fifty are the record: what gets rendered once there is a model worth
# pointing at them. LORA_PROMPT_SET=shoots selects them, optionally narrowed:
#
#   LORA_PROMPT_SET=shoots                    all fifty
#   LORA_PROMPT_SET=shoots:Weather            one side
#   LORA_PROMPT_SET=shoots:1,7,12             named sittings
def apply_prompt_set!(process)
  request = ENV["LORA_PROMPT_SET"].to_s.strip
  return if request.empty?

  name, filter = request.split(":", 2)
  require_relative "shoots"
  unless available_sets.include?(name)
    abort "warn: unknown prompt set #{name} — have: #{available_sets.join(', ')}"
  end

  side = filter if filter && filter !~ /\A[\d,\s]+\z/
  only = filter.split(",").map(&:to_i) if filter && filter =~ /\A[\d,\s]+\z/

  built = prompts_for(File.basename(ROOT), side: side, only: only, set: name)
  abort "warn: prompt set #{request} matched no sittings" if built.empty?

  process["sample"]["prompts"] = built.map(&:last)
  warn "note: prompt set #{request} — #{built.length} sitting(s)"
end

# Sampling and training must agree about how noise is scheduled.
#
# They are two keys in two different sections written for two different base
# models, and nothing reconciled them. apply_sdxl! set train.noise_scheduler to
# ddpm and left sample.sampler at flowmatch, so twelve portraits were denoised on
# a schedule the model was never trained under. Nothing failed. The pictures came
# out soft and the softness read as an undertrained LoRA.
#
# flowmatch belongs to flow-matching models — FLUX, SD3. Everything else is
# epsilon/v-prediction on a DDPM-style curve. Crossing them is always a mistake
# and is never reported, which is the only reason it survived a full run.
FLOW_MATCHING = %w[flowmatch flow_match].freeze

def reconcile_scheduler!(process)
  scheduler = process.dig("train", "noise_scheduler").to_s
  sampler = process.dig("sample", "sampler").to_s
  return if scheduler.empty? || sampler.empty?
  return if FLOW_MATCHING.include?(scheduler) == FLOW_MATCHING.include?(sampler)

  abort <<~WARN
    warn: noise_scheduler #{scheduler.inspect} and sampler #{sampler.inspect} disagree.
    warn: one is flow-matching and the other is not, so every sample would be
    warn: denoised on a curve the model was not trained on. That does not fail —
    warn: it just produces soft, mushy frames that look like undertraining.
    warn: Set both to flowmatch (FLUX, SD3) or neither (SDXL, SD1.5).
  WARN
end

def build(mode)
  config = load_mapping(BASE)
  process = config.fetch("config").fetch("process").first

  process["training_folder"] = File.join(ROOT, "weights")
  process["datasets"].first["folder_path"] = File.join(ROOT, "dataset")
  requested_prompt = ENV["LORA_PROMPT"].to_s.strip
  # A direct request gets one exact prompt, while training keeps the curated suite.
  process["sample"]["prompts"] = [requested_prompt] unless requested_prompt.empty?
  apply_prompt_set!(process)
  apply_device!(process)
  apply_env_overrides!(process)

  if mode == "generate"
    train = process.fetch("train").dup
    train["start_step"] = train.fetch("steps")
    train["force_first_sample"] = true
    process["train"] = train
  end

  reconcile_scheduler!(process)

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
