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
require "time"
require_relative "curate"

SUBJECT = ENV.fetch("SUBJECT") { abort "run a subject wrapper, not this script directly" }
SUBJECT_DIR = Pathname.new(ENV.fetch("SUBJECT_DIR")).expand_path
TRIGGER = ENV.fetch("TRIGGER", SUBJECT)

options = { write: false, replace: false, count: 18 }
OptionParser.new do |p|
  p.banner = "Usage: prepare.rb [--write] [--count N]"
  p.on("--write", "Write dataset/ (default: report only)") { options[:write] = true }
  p.on("--replace", "Archive a non-empty old dataset before installing this source set; requires --write") { options[:replace] = true }
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

abort "warn: --replace requires --write" if options[:replace] && !options[:write]

unless options[:write]
  puts "ok: report only; add --write to create #{Lora::Curate.dataset_dir(SUBJECT_DIR)}"
  exit 0
end

dataset = Pathname.new(Lora::Curate.dataset_dir(SUBJECT_DIR.to_s))
abort "warn: refusing dataset symlink #{dataset}" if dataset.symlink?
if dataset.exist?
  abort "warn: dataset path is not a directory: #{dataset}" unless dataset.directory?
  abort "warn: #{dataset} is not empty; use --replace to archive it before refreshing" if !dataset.children.empty? && !options[:replace]
end

stamp = Time.now.utc.strftime("%Y%m%dT%H%M%S%N")
scratch = SUBJECT_DIR.join(".cache", "dataset-build-#{stamp}")
backup = nil
FileUtils.mkdir_p(scratch.dirname)
begin
  written = Lora::Curate.prepare(chosen, into: scratch.to_s, token: TRIGGER)
  if written.empty?
    FileUtils.rm_rf(scratch.to_s)
    abort "warn: curator produced no training images; previous dataset is unchanged"
  end

  if dataset.exist?
    if dataset.children.empty?
      dataset.rmdir
    else
      backup = SUBJECT_DIR.join(".cache", "dataset-backups", "dataset-#{stamp}")
      FileUtils.mkdir_p(backup.dirname)
      FileUtils.mv(dataset.to_s, backup.to_s)
    end
  end

  begin
    FileUtils.mv(scratch.to_s, dataset.to_s)
  rescue StandardError
    FileUtils.mv(backup.to_s, dataset.to_s) if backup&.exist? && !dataset.exist?
    raise
  end
rescue StandardError
  FileUtils.rm_rf(scratch.to_s) if scratch.exist?
  raise
end

puts "ok: wrote #{written.length} image(s) with stub captions to #{dataset}"
puts "ok: previous dataset archived at #{backup}" if backup
puts "next: review each .txt caption (pose, clothing, light, setting), then ./lora --train-replicate --dry-run"
