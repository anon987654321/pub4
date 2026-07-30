#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

ROOT = ENV.fetch("AI_TOOLKIT_ROOT", File.expand_path("~/ai-toolkit"))
CONFIG = ARGV.fetch(0)

venv = File.join(ROOT, ".venv/bin/python")
venv = File.join(ROOT, "venv/bin/python") unless File.executable?(venv)
abort "warn: ai-toolkit python missing under #{ROOT}" unless File.executable?(venv)
abort "warn: run.py missing in #{ROOT}" unless File.exist?(File.join(ROOT, "run.py"))
abort "warn: config missing #{CONFIG}" unless File.exist?(CONFIG)

if ENV["HF_TOKEN"] && !ENV["HUGGINGFACE_HUB_TOKEN"]
  ENV["HUGGINGFACE_HUB_TOKEN"] = ENV["HF_TOKEN"]
end

device = ENV.fetch("LORA_DEVICE", "mps").downcase
if device == "mps"
  # M2 8 GB: FLUX quantize/load needs unified memory past the default MPS cap.
  ENV["PYTORCH_MPS_HIGH_WATERMARK_RATIO"] ||= "0.0"
end

status = system(venv, "run.py", CONFIG, chdir: ROOT)
exit(status ? 0 : 1)