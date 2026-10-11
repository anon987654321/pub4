# frozen_string_literal: true

require "json"
require_relative "../trace/dmesg"

module Operator
  # `bin/operator fix tail`: follows the newest /fix log and the newest run's
  # transcript, printing lines as they arrive. A /fix child writes its log
  # lines to stdout and its full records to .master/fix_transcripts/<run>/;
  # this is the one place that shows both while the run is going.
  module FixTail
    POLL_SECONDS = 0.5
    DEFAULT_LINES = 20

    module_function

    # argv: --tail[=N] lines of history first, --transcript for the records
    # only, --once to print and stop instead of following.
    def run(argv, roots:, io: $stdout, sleeper: ->(seconds) { sleep(seconds) }, rounds: nil)
      lines = argv.filter_map { |arg| arg[/\A--(?:tail|n)=(\d+)\z/, 1] }.first
      limit = (lines || DEFAULT_LINES).to_i
      transcript_only = argv.include?("--transcript")
      once = argv.include?("--once")
      found = sources(roots, transcript_only)
      return missing(io) if found.empty?

      offsets = {}
      found.each { |path| print_history(path, limit, offsets, io) }
      return 0 if once

      count = 0
      loop do
        break if rounds && (count += 1) > rounds

        sleeper.call(POLL_SECONDS)
        sources(roots, transcript_only).each { |path| print_new(path, offsets, io) }
      end
      0
    end

    def missing(io)
      Master::Trace::Dmesg.status("fix0", "no /fix log or transcript found", io:)
      1
    end

    def sources(roots, transcript_only)
      found = []
      newest = roots.flat_map { |root| Dir.glob(File.join(root, ".master", "fix_transcripts", "*")) }.select { |p| File.directory?(p) }.max_by { |p| File.mtime(p) }
      found.concat(Dir.glob(File.join(newest, "*.ndjson")).sort) if newest
      unless transcript_only
        log = roots.flat_map { |root| Dir.glob(File.join(root, ".master", "fix-*.log")) }.max_by { |p| File.mtime(p) }
        found.unshift(log) if log
      end
      found
    end

    def print_history(path, limit, offsets, io)
      text = File.binread(path).force_encoding("UTF-8").scrub
      offsets[path] = text.bytesize
      text.lines.last(limit).each { |line| io.puts(render(path, line)) }
      io.flush
    end

    def print_new(path, offsets, io)
      size = File.size(path)
      from = offsets.fetch(path, 0)
      from = 0 if size < from
      return if size == from

      chunk = File.open(path, "rb") { |file| file.seek(from) && file.read }.to_s.force_encoding("UTF-8").scrub
      return unless chunk.include?("\n")

      complete = chunk[0..chunk.rindex("\n")]
      offsets[path] = from + complete.bytesize
      complete.lines.each { |line| io.puts(render(path, line)) }
      io.flush
    end

    def render(path, line)
      return line.chomp unless path.end_with?(".ndjson")

      row = JSON.parse(line)
      detail = [row["law"], row["file"] && File.basename(row["file"]), row["outcome"] || row["reason"], row["pick"] && row["pick"].to_s[0, 160], row["status"]].compact.join(" ")
      "#{File.basename(path, ".ndjson")}: #{row["at"]} #{row["kind"]} #{detail}".strip
    rescue JSON::ParserError
      line.chomp
    end
  end
end
