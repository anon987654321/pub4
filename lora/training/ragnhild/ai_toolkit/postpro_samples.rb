#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "optparse"
require "open3"
require "pathname"
require "rbconfig"
require "shellwords"

SCRIPT_DIR = Pathname.new(__dir__).expand_path.freeze
DEFAULT_INPUT_DIR = SCRIPT_DIR.join("output", "ragnhild_v2").freeze
DEFAULT_OUTPUT_DIR = DEFAULT_INPUT_DIR.join("postpro").freeze
DEFAULT_PRESETS = %w[portrait].freeze
IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp].freeze
DERIVED_IMAGE_PATTERN = /(?:contact|grid|reel|_portrait|_cinematic|_quality_uplift|_blockbuster|_magic_hour|_postpro)\b/i

def repo_root
  SCRIPT_DIR.ascend.find { |path| path.join("MASTER", "tools", "postpro.rb").file? }
end

def parse_options
  options = {
    input_dir: DEFAULT_INPUT_DIR,
    output_dir: DEFAULT_OUTPUT_DIR,
    postpro: nil,
    presets: DEFAULT_PRESETS,
    limit: 12,
    clean_output: true,
    dry_run: false
  }

  OptionParser.new do |parser|
    parser.banner = "Usage: ruby postpro_samples.rb [options]"
    parser.on("--input-dir DIR", "Directory containing generated sample images") { |value| options[:input_dir] = Pathname.new(value).expand_path }
    parser.on("--output-dir DIR", "Directory for graded copies") { |value| options[:output_dir] = Pathname.new(value).expand_path }
    parser.on("--postpro PATH", "Path to MASTER/tools/postpro.rb") { |value| options[:postpro] = Pathname.new(value).expand_path }
    parser.on("--presets LIST", "Comma-separated postpro presets") { |value| options[:presets] = value.split(",").map(&:strip).reject(&:empty?) }
    parser.on("--limit N", Integer, "Maximum source images to grade") { |value| options[:limit] = value }
    parser.on("--keep-output", "Keep existing generated postpro files") { options[:clean_output] = false }
    parser.on("--dry-run", "Print commands without running postpro") { options[:dry_run] = true }
  end.parse!

  options
end

def image_files(input_dir, output_dir, limit)
  output_prefix = "#{output_dir.expand_path}/"
  files = Dir.glob(input_dir.join("**", "*"), File::FNM_CASEFOLD).select do |path|
    file = Pathname.new(path)
    file.file? &&
      IMAGE_EXTENSIONS.include?(file.extname.downcase) &&
      !file.expand_path.to_s.start_with?(output_prefix) &&
      !file.basename.to_s.match?(DERIVED_IMAGE_PATTERN)
  end

  files.sort_by { |path| [File.mtime(path), path] }.last(limit).map { |path| Pathname.new(path).expand_path }
end

def output_path_for(output_dir, input_path, preset_name)
  stem = input_path.basename(input_path.extname).to_s
  output_dir.join("#{stem}_#{preset_name}.jpg")
end

def run_postpro(postpro, input_path, output_path, preset_name, dry_run:)
  command = [
    RbConfig.ruby,
    postpro.to_s,
    "--input", input_path.to_s,
    "--output", output_path.to_s,
    "--preset", preset_name
  ]

  puts command.shelljoin if dry_run
  return true if dry_run

  stdout, status = Open3.capture2e(*command, chdir: repo_root.to_s)
  unless status.success? && output_path.file?
    warn stdout
    warn "postpro failed preset=#{preset_name} input=#{input_path}"
    return false
  end

  puts "postpro ok preset=#{preset_name} output=#{output_path}"
  true
end

def main
  options = parse_options
  root = repo_root
  abort "repo root with MASTER/tools/postpro.rb not found" unless root

  postpro = options[:postpro] || root.join("MASTER", "tools", "postpro.rb")
  abort "postpro.rb not found at #{postpro}" unless postpro.file?
  abort "input dir not found: #{options[:input_dir]}" unless options[:input_dir].directory?

  FileUtils.rm_rf(options[:output_dir]) if options[:clean_output] && !options[:dry_run]
  FileUtils.mkdir_p(options[:output_dir]) unless options[:dry_run]
  files = image_files(options[:input_dir], options[:output_dir], options[:limit])
  abort "no generated sample images found in #{options[:input_dir]}" if files.empty?

  failures = 0
  files.each do |input_path|
    options[:presets].each do |preset_name|
      output_path = output_path_for(options[:output_dir], input_path, preset_name)
      failures += 1 unless run_postpro(postpro, input_path, output_path, preset_name, dry_run: options[:dry_run])
    end
  end

  abort "postpro completed with #{failures} failure(s)" if failures.positive?
end

main if $PROGRAM_NAME == __FILE__
