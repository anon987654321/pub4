#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

# Lines that recent commits deleted or moved and that look worth a second look:
# definitions, schema, secrets, OpenBSD daemons.
#
#   ruby MASTER/tools/history_valuables.rb [paths...]
module HistoryValuables
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

  # The backlog closes an entry by deleting it, and nearly every line in it names
  # MASTER, a TODO or a daemon, so every closed entry would read as a lost
  # valuable and bury the real ones.
  DELETED_BY_DESIGN = %w[TODO.md].freeze

  module_function

  def hits(log)
    commit = nil
    file = nil
    log.each_line.filter_map do |line|
      if line.start_with?("commit ")
        commit = line.split.fetch(1)
        file = nil
        next
      end
      if line.start_with?("diff --git ")
        file = line.split.last&.delete_prefix("b/")
        next
      end

      text = deleted_text(line)
      next unless text && valuable?(text) && !DELETED_BY_DESIGN.include?(file)

      { commit:, file:, line: text[0, 220] }
    end
  end

  def deleted_text(line)
    return unless line.start_with?("-") && !line.start_with?("---")

    text = line.delete_prefix("-").strip
    text.empty? ? nil : text
  end

  def valuable?(text) = VALUABLE_PATTERNS.any? { |pattern| text.match?(pattern) }

  def git_log(window, paths)
    stdout, status = Open3.capture2e("git", "log", window, "--find-renames", "--find-copies",
                                     "--diff-filter=DMR", "--patch", "--", *paths, chdir: ROOT)
    abort "err: git log failed\n#{stdout}" unless status.success?
    stdout
  end

  def run(argv)
    window = ENV.fetch("HISTORY_WINDOW", "--since=90.days.ago")
    paths = argv.empty? ? ["."] : argv
    found = hits(git_log(window, paths))
    if found.empty?
      puts "ok: no deleted or moved valuables matched in #{window} for #{paths.join(", ")}"
      return
    end

    found.each { |hit| puts "#{hit[:commit]} #{hit[:file]} :: #{hit[:line]}" }
    abort "err: possible lost valuables detected (#{found.size})"
  end
end

HistoryValuables.run(ARGV) if $PROGRAM_NAME == __FILE__
