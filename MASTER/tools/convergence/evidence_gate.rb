#!/usr/bin/env ruby
# frozen_string_literal: true
# frozen_string_literal: true
# frozen_string_literal: true
# frozen_string_literal: true

require "json"
require "open3"

ROOT = File.expand_path("../../..", __dir__)
DEFAULT_THRESHOLD = 0.90
PRODUCTION_THRESHOLD = 0.95

WEIGHTS = {
  tests: 0.35,
  static: 0.25,
  complexity: 0.15,
  architecture: 0.15,
  security: 0.10,
}.freeze

TEXT_EXTENSIONS = %w[
  .rb .rake .ru .js .mjs .css .erb .html .yml .yaml .json .md .txt .zsh .ksh .sh
].freeze

SKIP_PREFIXES = %w[
  ARCHIVE/
  vendor/
  node_modules/
  tmp/
  log/
].freeze

class EvidenceGate
  def initialize(root:)
    @root = root
    @files = git_files
    @findings = []
  end

  def call
    scores = {
      tests: tests_score,
      static: static_score,
      complexity: complexity_score,
      architecture: architecture_score,
      security: security_score,
    }

    weighted = scores.sum { |key, value| value * WEIGHTS.fetch(key) }
    {
      score: weighted.round(4),
      threshold: threshold,
      pass: weighted >= threshold,
      components: scores.transform_values { |value| value.round(4) },
      findings: @findings
    }
  end

  private

  attr_reader :root, :files

  def threshold
    Float(ENV.fetch("PUB4_EVIDENCE_THRESHOLD", DEFAULT_THRESHOLD))
  rescue ArgumentError
    DEFAULT_THRESHOLD
  end

  def git_files
    stdout, status = Open3.capture2("git", "-C", root, "ls-files")
    return [] unless status.success?

    stdout.lines.map(&:chomp).reject(&:empty?)
  end

  def checked_files
    files.reject { |path| SKIP_PREFIXES.any? { |prefix| path.start_with?(prefix) } }
  end

  def text_files
    checked_files.select do |path|
      TEXT_EXTENSIONS.include?(File.extname(path)) && File.file?(File.join(root, path))
    end
  end

  def body(path)
    File.read(File.join(root, path))
  rescue StandardError
    ""
  end

  def tests_score
    test_files = files.select { |path| path.match?(%r{(^|/)(test|spec)/}) || path.end_with?("_test.rb", "_spec.rb") }
    gate_files = files.select { |path| path.end_with?("_gate.rb") || path.include?("/bin/ci") }

    @findings << "no test/spec files tracked" if test_files.empty?
    @findings << "no gate/ci files tracked" if gate_files.empty?

    partials = []
    partials << (test_files.empty? ? 0.0 : 1.0)
    partials << (gate_files.empty? ? 0.0 : 1.0)
    partials.sum / partials.size
  end

  def static_score
    bad = []
    text_files.each do |path|
      next if path == "MASTER/tools/convergence/evidence_gate.rb"
      source = body(path)
      bad << "#{path}: eval-like call" if source.match?(/\b(eval|instance_eval|class_eval|module_eval)\s*\(/)
      bad << "#{path}: unsafe YAML.load" if source.match?(/\bYAML\.load\s*\(/)
      bad << "#{path}: broad rescue without error class" if source.match?(/rescue\s*\n/)
      bad << "#{path}: TODO/FIXME left in production path" if !path.start_with?("docs/") && source.match?(/\b(TODO|FIXME)\b/)
    end

    @findings.concat(bad.first(30))
    ratio_score(bad.size, [text_files.size, 1].max, tolerance: 0.01)
  end

  def complexity_score
    ruby_files = text_files.select { |path| File.extname(path) == ".rb" }
    long_methods = []

    ruby_files.each do |path|
      method_lengths(path).each do |name, length|
        long_methods << "#{path}: #{name} has #{length} lines" if length > 40
      end
    end

    @findings.concat(long_methods.first(30))
    ratio_score(long_methods.size, [ruby_files.size, 1].max, tolerance: 0.08)
  end

  def architecture_score
    bad = []
    checked_files.each do |path|
      absolute = File.join(root, path)
      next unless File.file?(absolute)
      next if path.start_with?("ARCHIVE/")

      size = File.size(absolute)
      bad << "#{path}: very large source file #{size} bytes" if text_like_path?(path) && size > 250_000
      bad << "#{path}: tracked media binary" if path.match?(/\.(mp3|wav|flac|mov|mp4|zip)\z/i)
    end

    @findings.concat(bad.first(30))
    ratio_score(bad.size, [checked_files.size, 1].max, tolerance: 0.005)
  end

  def security_score
    bad = []
    secret_path_patterns = [
      /master\.key\z/,
      /\.env\z/,
      /id_rsa/,
      /id_ed25519/,
      /credentials\/.*\.key/
    ]

    files.each do |path|
      bad << "#{path}: secret-looking file tracked" if secret_path_patterns.any? { |pattern| path.match?(pattern) }
    end

    text_files.each do |path|
      source = body(path)
      bad << "#{path}: possible API secret" if source.match?(/\b(sk_live_|sk_test_|AKIA[0-9A-Z]{16})/)
      bad << "#{path}: approval bypass phrase" if source.match?(/\b(auto_execute|bypass_confirmation|require_approval["']?\s*[:=]\s*false)\b/)
      bad << "#{path}: public Rails port range" if source.match?(/port\s+10000:65535/)
      bad << "#{path}: random production port" if source.match?(/\$RANDOM|\bRANDOM\b/)
    end

    @findings.concat(bad.first(30))
    ratio_score(bad.size, [files.size, 1].max, tolerance: 0.0)
  end

  def method_lengths(path)
    lengths = []
    stack = []
    body(path).lines.each_with_index do |line, index|
      stripped = line.strip
      if stripped.match?(/\Adef\s+/)
        stack << [stripped.sub(/\Adef\s+/, ""), index + 1]
      elsif stripped == "end" && stack.any?
        name, start = stack.pop
        lengths << [name, index + 1 - start]
      end
    end
    lengths
  end

  def text_like_path?(path)
    TEXT_EXTENSIONS.include?(File.extname(path))
  end

  def ratio_score(count, total, tolerance:)
    ratio = count.to_f / total
    return 1.0 if ratio <= tolerance

    [0.0, 1.0 - ((ratio - tolerance) * 10)].max
  end
end

if $PROGRAM_NAME == __FILE__
  result = EvidenceGate.new(root: ROOT).call
  puts JSON.pretty_generate(result)
  exit(result.fetch(:pass) ? 0 : 1)
end
