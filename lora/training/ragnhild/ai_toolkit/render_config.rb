#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "yaml"

ROOT = File.expand_path(__dir__)
BASE = File.join(ROOT, "train_ragnhild.yaml")
PROMPTS = File.join(ROOT, "prompts.yaml")

def load_mapping(path)
  data = YAML.load_file(path)
  abort "warn: expected mapping in #{path}" unless data.is_a?(Hash)
  data
end

def build(mode)
  config = load_mapping(BASE)
  prompts = load_mapping(PROMPTS)
  process = config.fetch("config").fetch("process").first

  process["training_folder"] = File.join(ROOT, "weights")
  process["datasets"].first["folder_path"] = File.join(ROOT, "dataset")
  process["sample"]["prompts"] = prompts.fetch("prompts")
  process["sample"]["neg"] = prompts.fetch("negative")

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