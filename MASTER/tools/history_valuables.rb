#!/usr/bin/env ruby
# frozen_string_literal: true

# frozen_string_literal: true
# frozen_string_literal: true

require "open3"

ROOT = File.expand_path("../..", __dir__)
VALUABLE_PATTERNS = [
  /class\s+\w+/,
  /module\s+\w+/,
  /def\s+\w+/,
  /CREATE TABLE/i,
  /add_index/i,
  /foreign_key/i,
  /TODO|FIXME|XXX/,
  /OPENROUTER|SECRET|TOKEN|API_KEY/,
  /public_key|private_key/i,
  /rcctl|relayd|httpd|pfctl|doas/,
  /Stimulus|Turbo|Rails|Falcon/,
  /MASTER|OPERATOR|converge|council|critique/i,
].freeze

WINDOW = ENV.fetch("HISTORY_WINDOW", "--since=90.days.ago")
PATHS = ARGV.empty? ? ["."] : ARGV

def run_git(*argv)
  stdout, status = Open3.capture2e("git", *argv, chdir: ROOT)
  abort "err: git #{argv.join(" ")} failed\n#{stdout}" unless status.success?
  stdout
end

log = run_git(
  "log",
  WINDOW,
  "--find-renames",
  "--find-copies",
  "--diff-filter=DMR",
  "--patch",
  "--",
  *PATHS,
)

current_commit = nil
current_file = nil
hits = []

log.each_line do |line|
  if line.start_with?("commit ")
    current_commit = line.split.fetch(1)
    current_file = nil
    next
  end

  if line.start_with?("diff --git ")
    current_file = line.split.last&.delete_prefix("b/")
    next
  end

  next unless line.start_with?("-")
  next if line.start_with?("---")

  text = line.delete_prefix("-").strip
  next if text.empty?
  next unless VALUABLE_PATTERNS.any? { |pattern| text.match?(pattern) }

  hits << {
    commit: current_commit,
    file: current_file,
    line: text[0, 220],
  }
end

if hits.empty?
  puts "ok: no deleted or moved valuables matched in #{WINDOW} for #{PATHS.join(", ")}"
else
  hits.each do |hit|
    puts "#{hit[:commit]} #{hit[:file]} :: #{hit[:line]}"
  end
  abort "err: possible lost valuables detected (#{hits.size})"
end
