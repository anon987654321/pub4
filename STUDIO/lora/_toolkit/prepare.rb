#!/usr/bin/env ruby
# frozen_string_literal: true

# Photographs in sources/ become a training set in dataset/.
#
# curate.rb judges each photograph (resolution, sharpness, blown highlights),
# spreads the pick over the set so ten frames of one moment do not count as ten,
# and writes 1024-pixel copies, each with a stub caption of the trigger word.
# The stubs are the part left to a person: caption what varies, never the face,
# the hair colour, the eye colour or the age (the caption law in curate.rb).
# preflight.rb then checks the finished set before anything is paid for.
#
#   ./lora --prepare               report only; writes nothing
#   ./lora --prepare --write       write dataset/ (refuses a non-empty one)
#   ./lora --prepare --count 18    choose up to 18 frames (default 18)

require "optparse"
require "pathname"
require "fileutils"
require_relative "curate"

SUBJECT = ENV.fetch("SUBJECT") { abort "run a subject wrapper, not this script directly" }
SUBJECT_DIR = Pathname.new(ENV.fetch("SUBJECT_DIR")).expand_path
TRIGGER = ENV.fetch("TRIGGER", SUBJECT)

options = { write: false, count: 18 }
OptionParser.new do |p|
  p.banner = "Usage: prepare.rb [--write] [--count N]"
  p.on("--write", "Write dataset/ (default: report only)") { options[:write] = true }
  p.on("--count N", Integer, "Frames to choose (default 18)") { |v| options[:count] = v }
  p.on("-h", "--help") { puts p; exit 0 }
end.parse!

sources = SUBJECT_DIR.join("sources")
abort "warn: no #{sources}\nfix: put photographs of #{SUBJECT} there" unless sources.directory?

verdicts = Lora::Curate.assess(sources.to_s)
abort "warn: no photographs in #{sources}" if verdicts.empty?

chosen = Lora::Curate.select(verdicts, count: options[:count])
puts Lora::Curate.report(verdicts, chosen)
puts "ok: #{chosen.length} chosen of #{verdicts.length}; trigger #{TRIGGER.inspect}"

unless options[:write]
  puts "ok: report only; add --write to create #{Lora::Curate.dataset_dir(SUBJECT_DIR)}"
  exit 0
end

dataset = Pathname.new(Lora::Curate.dataset_dir(SUBJECT_DIR.to_s))
abort "warn: #{dataset} is not empty; move it aside first" if dataset.directory? && !dataset.children.empty?

FileUtils.mkdir_p(dataset)
written = Lora::Curate.prepare(chosen, into: dataset.to_s, token: TRIGGER)
puts "ok: wrote #{written.length} image(s) with stub captions to #{dataset}"
puts "next: complete each .txt (pose, clothing, light, setting), then ./lora --train-replicate --dry-run"
