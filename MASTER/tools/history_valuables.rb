#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require_relative "../lib/trace/dmesg"

# Finds deleted or moved lines that deserve a second look. The same instrument
# can inspect pub4 or, when explicitly asked, the predecessor repositories.
#
# Recent history:
#   ruby MASTER/tools/history_valuables.rb
# Full current-repo history:
#   ruby MASTER/tools/history_valuables.rb --all-history
# All four generations, full history:
#   ruby MASTER/tools/history_valuables.rb --legacy --all-history
#
# Sibling repositories are expected beside pub4:
#   ../pub3, ../pub2, ../pub
module HistoryValuables
  ROOT = File.expand_path("../..", __dir__)
  REPOSITORIES = {
    "pub4" => ROOT,
    "pub3" => File.expand_path("../pub3", ROOT),
    "pub2" => File.expand_path("../pub2", ROOT),
    "pub" => File.expand_path("../pub", ROOT),
  }.freeze

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

  ARCHIVE_PATTERN = /\.(?:tgz|tar\.gz|zip)\z/i

  # The backlog closes an entry by deleting it, and nearly every line in it names
  # MASTER, a TODO or a daemon, so every closed entry would read as a lost
  # valuable and bury the real ones.
  DELETED_BY_DESIGN = %w[TODO.md].freeze

  module_function

  def repository_roots(include_legacy)
    roots = { "pub4" => ROOT }
    return roots unless include_legacy

    REPOSITORIES.select { |_name, path| File.directory?(File.join(path, ".git")) }
  end

  def diff_file(line)
    match = line.match(/\Adiff --git a\/(.+) b\/(.+)\z/)
    match && match[2]
  end

  def archive_path?(path)
    path && path.match?(ARCHIVE_PATTERN)
  end

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
        file = diff_file(line)
        next
      end

      if line.start_with?("deleted file mode")
        next unless archive_path?(file)

        { commit:, file:, kind: :deleted_archive, line: line.strip }
      else
        text = deleted_text(line)
        next unless text && valuable?(text) && !DELETED_BY_DESIGN.include?(file)

        { commit:, file:, kind: :deleted_line, line: text[0, 220] }
      end
    end
  end

  def deleted_text(line)
    return unless line.start_with?("-") && !line.start_with?("---")

    text = line.delete_prefix("-").strip
    text.empty? ? nil : text
  end

  def valuable?(text) = VALUABLE_PATTERNS.any? { |pattern| text.match?(pattern) }

  def history_command(repo, window:, all_refs:, paths:)
    args = ["git", "-C", repo, "log"]
    args << "--all" if all_refs
    args << window if window
    args.concat(%w[--find-renames --find-copies --diff-filter=DMR --patch --])
    args.concat(paths)
  end

  def git_log(repo, window:, all_refs:, paths:)
    stdout, status = Open3.capture2e(*history_command(repo, window:, all_refs:, paths:))
    abort "err: git log failed in #{repo}\n#{stdout}" unless status.success?
    stdout
  end

  def run(argv)
    all_history = argv.delete("--all-history")
    include_legacy = argv.delete("--legacy")
    window = all_history ? nil : ENV.fetch("HISTORY_WINDOW", "--since=90.days.ago")
    paths = argv.empty? ? ["."] : argv
    repos = repository_roots(include_legacy)
    found = []

    repos.each do |name, repo|
      next unless File.directory?(File.join(repo, ".git"))

      repo_hits = hits(git_log(repo, window:, all_refs: all_history, paths:))
      repo_hits.each { |hit| found << hit.merge(repo: name) }
    end

    if found.empty?
      scope = include_legacy ? "pub4/pub3/pub2/pub" : "pub4"
      span = all_history ? "all refs, all history" : window
      Master::Trace::Dmesg.status("history0", "clean, no deleted or moved valuables matched in #{scope}, #{span}, paths=#{paths.join(",")}")
      return
    end

    Master::Trace::Dmesg.attach("history0", "master0", "#{found.size} deleted or moved valuables")
    found.each do |hit|
      Master::Trace::Dmesg.status(
        "history0",
        "#{hit[:repo]} #{hit[:commit]} #{hit[:kind]} #{hit[:file]}, #{hit[:line]}",
        io: $stderr
      )
    end
    exit 1
  end
end

HistoryValuables.run(ARGV) if $PROGRAM_NAME == __FILE__
