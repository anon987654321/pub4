#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "optparse"
require "open3"
require "pathname"
require "rbconfig"
require "shellwords"

ROOT = Pathname.new(__dir__).expand_path.freeze
# _toolkit -> lora. This resolved to the repo root, three levels too high, which
# went unnoticed because lib.sh always passes --input-dir and --output-dir.
LORA = ROOT.join("..").expand_path.freeze
IMAGE_EXT = %w[.jpg .jpeg .png .webp].freeze
SKIP_PREFIX = ["#{ENV.fetch("SUBJECT", "")}_final_", "hf_flux_"].freeze
SKIP_SUFFIX = /(?:contact|grid|reel|_portrait|_cinematic|_quality_uplift|_blockbuster|_magic_hour|_postpro)\b/i

def repo_root
  ROOT.ascend.find { |path| path.join("STUDIO", "postpro", "postpro.rb").file? }
end

def parse_options
  options = {
    input_dir: LORA,
    output_dir: LORA,
    postpro: nil,
    presets: %w[portrait],
    limit: 12,
    clean_output: true,
    dry_run: false
  }

  OptionParser.new do |parser|
    parser.banner = "Usage: ruby postpro_samples.rb [options]"
    parser.on("--input-dir DIR") { |value| options[:input_dir] = Pathname.new(value).expand_path }
    parser.on("--output-dir DIR") { |value| options[:output_dir] = Pathname.new(value).expand_path }
    parser.on("--postpro PATH") { |value| options[:postpro] = Pathname.new(value).expand_path }
    parser.on("--presets LIST") { |value| options[:presets] = value.split(",").map(&:strip).reject(&:empty?) }
    parser.on("--limit N", Integer) { |value| options[:limit] = value }
    parser.on("--keep-output") { options[:clean_output] = false }
    parser.on("--dry-run") { options[:dry_run] = true }
  end.parse!

  options
end

def sample_file?(path)
  return false unless path.file?
  return false unless IMAGE_EXT.include?(path.extname.downcase)

  name = path.basename.to_s
  return false if SKIP_PREFIX.any? { |prefix| name.start_with?(prefix) }
  !name.match?(SKIP_SUFFIX)
end

def image_files(input_dir, limit)
  Dir.children(input_dir).map { |entry| input_dir.join(entry) }
    .select { |path| sample_file?(path) }
    .sort_by { |path| [File.mtime(path), path.to_s] }
    .last(limit)
    .map(&:expand_path)
end

def output_path(output_dir, input_path, preset)
  stem = input_path.basename(input_path.extname).to_s
  output_dir.join("#{stem}_#{preset}.jpg")
end

def run_postpro(postpro, input_path, output_path, preset, dry_run:)
  command = [
    RbConfig.ruby,
    postpro.to_s,
    "--input", input_path.to_s,
    "--output", output_path.to_s,
    "--preset", preset
  ]

  puts command.shelljoin if dry_run
  return true if dry_run

  stdout, status = Open3.capture2e(*command, chdir: repo_root.to_s)
  unless status.success? && output_path.file?
    warn stdout
    warn "warn: postpro failed preset=#{preset} input=#{input_path}"
    return false
  end

  puts "ok: postpro preset=#{preset} output=#{output_path}"
  true
end

def main
  options = parse_options
  root = repo_root
  abort "warn: STUDIO/postpro/postpro.rb not found" unless root

  postpro = options[:postpro] || root.join("STUDIO", "postpro", "postpro.rb")
  abort "warn: postpro missing at #{postpro}" unless postpro.file?
  abort "warn: input dir missing #{options[:input_dir]}" unless options[:input_dir].directory?

  if options[:clean_output] && !options[:dry_run]
    Dir.glob(options[:output_dir].join("*_portrait.jpg")).each { |path| FileUtils.rm_f(path) } # scan: intentional — portraits regenerated into this run's output dir
  end
  FileUtils.mkdir_p(options[:output_dir]) unless options[:dry_run]

  files = image_files(options[:input_dir], options[:limit])
  abort "warn: no sample images in #{options[:input_dir]}" if files.empty?

  failures = 0
  files.each do |input_path|
    options[:presets].each do |preset|
      out = output_path(options[:output_dir], input_path, preset)
      failures += 1 unless run_postpro(postpro, input_path, out, preset, dry_run: options[:dry_run])
    end
  end

  abort "warn: postpro failed #{failures} time(s)" if failures.positive?
end

main if $PROGRAM_NAME == __FILE__
