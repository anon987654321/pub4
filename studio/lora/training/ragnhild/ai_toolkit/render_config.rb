#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "yaml"

ROOT = File.expand_path(__dir__)
BASE = File.join(ROOT, "train_ragnhild.yaml")
PROMPTS = File.join(ROOT, "prompts.yaml")

ALLOWED_DEVICES = %w[mps cuda cpu].freeze

def load_mapping(path)
  data = YAML.load_file(path)
  abort "warn: expected mapping in #{path}" unless data.is_a?(Hash)
  data
end

def resolve_device
  device = ENV.fetch("RAGNHILD_DEVICE", "mps").downcase
  unless ALLOWED_DEVICES.include?(device)
    abort "warn: RAGNHILD_DEVICE must be one of: #{ALLOWED_DEVICES.join(', ')}"
  end
  device
end

def apply_device!(process)
  device = resolve_device
  process["device"] = device

  model = process["model"]
  if ENV.key?("RAGNHILD_LOW_VRAM")
    low = ENV["RAGNHILD_LOW_VRAM"] != "0"
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
  when "mps"
    model["low_vram"] = true
    model["quantize"] = true
    # bitsandbytes 8-bit optimizers are CUDA-only; adamw runs on MPS.
    train["optimizer"] = "adamw"
    # bf16 on MPS can yield NaN loss; fp16 is more stable on Apple Silicon.
    train["dtype"] = "fp16"
    train["lr"] = 1.0e-5 unless ENV.key?("RAGNHILD_LR")
    # M2 8 GB: single resolution bucket reduces VRAM churn.
    process["datasets"].first["resolution"] = [512] unless ENV.key?("RAGNHILD_RESOLUTIONS")
  end
end

def build(mode)
  config = load_mapping(BASE)
  prompts = load_mapping(PROMPTS)
  process = config.fetch("config").fetch("process").first

  process["training_folder"] = File.join(ROOT, "weights")
  process["datasets"].first["folder_path"] = File.join(ROOT, "dataset")
  requested_prompt = ENV["RAGNHILD_PROMPT"].to_s.strip
  # A direct request gets one exact prompt, while training keeps the curated suite.
  process["sample"]["prompts"] = requested_prompt.empty? ? prompts.fetch("prompts") : [requested_prompt]
  process["sample"]["neg"] = prompts.fetch("negative")
  apply_device!(process)

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
