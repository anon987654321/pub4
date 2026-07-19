#!/usr/bin/env ruby
# frozen_string_literal: true
# frozen_string_literal: true

# Complete-file coverage manifest for pub4 archaeology.
# Reads every tracked byte, hashes it, and scans every complete text file.

require "digest"
require "json"
require "open3"
require "pathname"
require "time"

DEFAULT_ROOTS = [
  Pathname.new(__dir__).join("../..").expand_path,
  Pathname.new(__dir__).join("../../../pub").expand_path,
  Pathname.new(__dir__).join("../../../pub-compare/pub").expand_path,
  Pathname.new(__dir__).join("../../../pub-compare/pub2").expand_path,
  Pathname.new(__dir__).join("../../../pub-compare/pub3").expand_path,
].freeze

SIGNALS = {
  unfinished: /\b(?:TODO|FIXME|HACK|XXX)\b/,
  stub: /\b(?:not wired|not implemented|NotImplementedError|stub)\b/i,
  shell: /(?:Open3\.|system\s*\(|`[^`]+`|Kernel\.exec)/,
  secret_shape: /(?:api[_-]?key|access[_-]?token|private[_-]?key|password)\s*[:=]/i,
  swallowed_error: /rescue\s+(?:StandardError\s*)?(?:=>\s*\w+\s*)?\n\s*(?:nil|false|true|end)/,
}.freeze

def repository_files(root)
  out, status = Open3.capture2(
    "git", "-C", root.to_s, "ls-files", "-z", "--cached", "--others", "--exclude-standard"
  )
  raise "git ls-files failed for #{root}" unless status.success?

  out.split("\0").reject(&:empty?)
end

def binary?(bytes)
  bytes.include?("\0") || !bytes.dup.force_encoding(Encoding::UTF_8).valid_encoding?
end

def inspect_file(root, relative)
  path = root.join(relative)
  bytes = File.binread(path) # Deliberately complete; no sampling or truncation.
  row = {
    path: relative,
    bytes: bytes.bytesize,
    sha256: Digest::SHA256.hexdigest(bytes),
    binary: binary?(bytes),
  }
  return row if row[:binary]

  text = bytes.force_encoding(Encoding::UTF_8)
  row[:lines] = text.empty? ? 0 : text.count("\n") + (text.end_with?("\n") ? 0 : 1)
  row[:signals] = SIGNALS.each_with_object({}) do |(name, pattern), found|
    count = text.scan(pattern).length
    found[name] = count if count.positive?
  end
  row
rescue Errno::ENOENT => e
  { path: relative, error: e.message }
end

roots = ARGV.empty? ? DEFAULT_ROOTS : ARGV.map { |path| Pathname.new(path).expand_path }
report = {
  generated_at: Time.now.utc.iso8601,
  contract: "every tracked and non-ignored untracked repository file read in full; binary files hashed; UTF-8 text scanned in full",
  roots: []
}

roots.uniq.each do |root|
  next unless root.directory? && root.join(".git").exist?

  files = repository_files(root)
  rows = files.map { |relative| inspect_file(root, relative) }
  report[:roots] << {
    root: root.to_s,
    files: rows.length,
    bytes: rows.sum { |row| row[:bytes].to_i },
    binary_files: rows.count { |row| row[:binary] },
    text_files: rows.count { |row| row[:binary] == false },
    errors: rows.count { |row| row[:error] },
    entries: rows
  }
  warn "ok: audited #{root} files=#{rows.length} bytes=#{report[:roots].last[:bytes]}"
end

destination = ENV.fetch("FULL_REPO_AUDIT_OUTPUT", File.join(Dir.pwd, "full_repo_audit.json"))
File.write(destination, JSON.pretty_generate(report))
puts "ok: wrote #{destination}"
