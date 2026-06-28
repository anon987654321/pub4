#!/usr/bin/env ruby
# frozen_string_literal: true

# Block restored pub3 anti-patterns and verify archive artifacts exist.

require "open3"
require "yaml"

ROOT = File.expand_path("../..", __dir__)

def tracked_files
  stdout, status = Open3.capture2("git", "-C", ROOT, "ls-files")
  return [] unless status.success?

  stdout.lines.map(&:chomp)
end

def text_file?(path)
  return false unless File.file?(path)
  return false if path.match?(/\.(png|jpe?g|gif|webp|mp3|wav|flac|zip|gz|pdf)\z/i)

  sample = File.binread(path, 4096)
  sample.valid_encoding? && !sample.include?("\x00")
rescue StandardError
  false
end

failures = []
warnings = []

required = [
  "DEPLOY/archive/RESTORE_FROM_PUB2_PUB3.md",
  "DEPLOY/audio/akmd_mastering_chain.rb",
  "DEPLOY/audio/radio_bergen_tracks.yml",
  "DEPLOY/audio/radio_bergen_visualizer_controller.js",
  "DEPLOY/openbsd/domain_candidates_from_pub3.yml",
  "DEPLOY/openbsd/ptr_openbsd_amsterdam.rb",
  "MASTER/tools/convergence/evidence_gate.rb",
  "MASTER/data/lessons/pub_archive_restore.yml"
]

required.each do |rel|
  failures << "missing restored archive artifact: #{rel}" unless File.file?(File.join(ROOT, rel))
end

pattern_doc_allowlist = [
  "DEPLOY/rails/archive_restore_gate.rb",
  "MASTER/data/lessons/pub_archive_restore.yml",
  "MASTER/tools/convergence/evidence_gate.rb"
].freeze

forbidden_patterns = {
  /\bauto_execute\b/ => "do not restore pub3 auto_execute permissions",
  /\bbypass_confirmation\b/ => "do not restore pub3 bypass_confirmation permissions",
  /\brequire_approval["']?\s*[:=]\s*false\b/ => "do not restore pub3 require_approval=false permissions",
  /port\s+10000:65535/ => "do not expose Rails high ports publicly",
  /\$RANDOM|\(\(\s*RANDOM\s*%/ => "do not restore random production ports",
  /gem ['"]redis['"]|pkg_add\s+redis|rcctl\s+enable\s+redis/ => "do not reintroduce Redis dependency"
}

tracked_files.each do |rel|
  path = File.join(ROOT, rel)
  next unless text_file?(path)
  next if rel.start_with?("ARCHIVE/", "DEPLOY/archive/")
  next if pattern_doc_allowlist.include?(rel)

  body = File.read(path)
  forbidden_patterns.each do |pattern, message|
    failures << "#{rel}: #{message}" if body.match?(pattern)
  end
end

tracks_path = File.join(ROOT, "DEPLOY/audio/radio_bergen_tracks.yml")
if File.file?(tracks_path)
  tracks = YAML.safe_load_file(tracks_path)
  local = tracks.fetch("local_mp3", [])
  warnings << "radio_bergen_tracks.yml has no local tracks" if local.empty?
  failures << "radio_bergen_tracks.yml must mark external references as review-only" unless tracks.dig("external_reference", "policy") == "reference_only_until_rights_review"
end

chain_path = File.join(ROOT, "DEPLOY/audio/akmd_mastering_chain.rb")
if File.file?(chain_path)
  chain = File.read(chain_path)
  %w[highpass lowpass equalizer acompressor asoftclip alimiter].each do |token|
    failures << "akmd_mastering_chain.rb missing #{token}" unless chain.include?(token)
  end
end

if warnings.any?
  warn "Archive restore warnings:"
  warnings.each { |warning| warn "  - #{warning}" }
end

if failures.any?
  warn "Archive restore gate failures:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts "Archive restore gate passed."