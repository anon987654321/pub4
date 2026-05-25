# frozen_string_literal: true

require "open3"
require_relative "../master_paths"

module History
  Fossil = Struct.new(:commit, :file, :line, keyword_init: true) do
    def to_h = { commit: commit, file: file, line: line }
  end

  class Fossils
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
      /MASTER|DEPLOY|converge|council|critique/i
    ].freeze

    def initialize(root: MasterPaths.repo, window: ENV.fetch("HISTORY_WINDOW", "--since=90.days.ago"))
      @root = root
      @window = window
    end

    def scan(*paths)
      paths = ["."] if paths.empty?
      parse(git_log(*paths))
    end

    private

    attr_reader :root, :window

    def git_log(*paths)
      stdout, status = Open3.capture2e(
        "git", "log", window, "--find-renames", "--find-copies", "--diff-filter=DMR", "--patch", "--", *paths,
        chdir: root
      )
      raise "git history audit failed: #{stdout}" unless status.success?
      stdout
    end

    def parse(log)
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

        hits << Fossil.new(commit: current_commit, file: current_file, line: text[0, 220])
      end

      hits
    end
  end
end
