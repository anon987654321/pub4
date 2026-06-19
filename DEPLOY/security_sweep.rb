#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

ROOT = File.expand_path("..", __dir__)
QUARANTINE = File.join(ROOT, "DEPLOY", "quarantine", "virus_museum")

SECRET_PATTERNS = [
  /sk-[A-Za-z0-9_\-]{16,}/,
  /sk-ant-[A-Za-z0-9_\-]{16,}/,
  /AKIA[0-9A-Z]{16}/,
  /-----BEGIN (?:RSA |EC )?PRIVATE KEY-----/,
  /password\s*[:=]\s*["'][^"'\[\]]{8,}["']/i,
  /(?<![a-z_])api_key\s*[:=]\s*["'][^"']{8,}["']/i
].freeze

SKIP_PATH_RE = %r{
  \A(?:DEPLOY/quarantine/|
  DEPLOY/__predecessors/|
  .*/test/|
  .*/tests/|
  MASTER/data/eval_cases\.yml|
  MASTER/test/)
}x.freeze

TRACKED_DENY_GLOBS = [
  "DEPLOY/rails/*/config/master.key",
  "DEPLOY/rails/*/storage/**/*.sqlite3",
  "DEPLOY/rails/*/db/**/*.sqlite3",
  "**/.env",
  "**/credentials/*.key"
].freeze

def git_ls_files(pattern)
  out, status = Open3.capture2("git", "-C", ROOT, "ls-files", pattern)
  status.success? ? out.lines.map(&:chomp).reject(&:empty?) : []
end

def scan_tracked_secrets
  hits = []
  git_ls_files(".").each do |path|
    next if path.match?(SKIP_PATH_RE)
    next if path.end_with?("/db/seeds.rb")
    next unless File.file?(File.join(ROOT, path))
    next if File.size(File.join(ROOT, path)) > 512_000

    body = File.read(File.join(ROOT, path), mode: "rb").force_encoding(Encoding::UTF_8)
    next unless body.valid_encoding?

    SECRET_PATTERNS.each do |pattern|
      next if pattern.source.include?("api_key") && body.include?("API_KEY_PROVIDERS")
      next if pattern.source.include?("password") && body.match?(/password123|changeme|example|\[your password\]/i)
      hits << "#{path}: #{pattern}" if body.match?(pattern)
    end
  end
  hits
end

failures = []

TRACKED_DENY_GLOBS.each do |pattern|
  tracked = git_ls_files(pattern)
  failures.concat(tracked.map { |path| "tracked secret artifact: #{path}" })
end

failures.concat(scan_tracked_secrets)

unless File.file?(File.join(QUARANTINE, "README.md"))
  failures << "virus museum README missing"
end

quarantine_files = git_ls_files("DEPLOY/quarantine/virus_museum")
bad_ext = quarantine_files.reject { |path| path.end_with?(".txt") || path.end_with?("README.md") }
failures.concat(bad_ext.map { |path| "virus museum non-text file: #{path}" })

mode_lines, = Open3.capture2("git", "-C", ROOT, "ls-files", "-s", "DEPLOY/quarantine/virus_museum")
mode_lines.lines.each do |line|
  mode, _type, _sha, _stage, path = line.split(/\s+/, 5)
  failures << "virus museum executable: #{path}" if mode && mode != "100644"
end

if failures.any?
  warn "Security sweep failures:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts "Security sweep passed (#{quarantine_files.size} quarantine samples, 0 tracked secrets)."