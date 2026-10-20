# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Master
  module CLI
    # `/incident`: a private, dated log of things that happened to the operator, kept on this machine only
    # (MASTER_INCIDENT_LOG names another file). It records what the operator wrote, when they wrote it, and
    # nothing else: no microphone, no network. `summary` counts entries by week, weekday and part of day and
    # how many mention a denial; it describes the notes, never the other person, and cannot prove what was said.
    module IncidentLog
      DENIAL = /\b(?:denied|denies|never said|didn'?t say|did not say|pretend|imagining|made it up|nothing happened)\b/i
      PARTS = { "night" => 0...6, "morning" => 6...12, "afternoon" => 12...18, "evening" => 18...24 }.freeze

      module_function

      def path = ENV.fetch("MASTER_INCIDENT_LOG") { File.join(Dir.home, ".master", "incidents.ndjson") }

      def add(text, now: Time.now, file: path)
        entry = { "at" => now.iso8601, "text" => text.to_s.strip }
        return if entry["text"].empty?

        FileUtils.mkdir_p(File.dirname(file))
        File.open(file, "a", 0o600) { |io| io.puts(JSON.generate(entry)) }
        entry
      end

      def entries(file: path)
        return [] unless File.file?(file)

        File.readlines(file, chomp: true).filter_map { |line| JSON.parse(line) rescue nil }
      end

      def list(file: path)
        entries(file:).map { |entry| "#{entry["at"][0, 16].tr("T", " ")}  #{entry["text"]}" }.join("\n")
      end

      def summary(file: path)
        rows = entries(file:)
        return "incident0: no entries yet; add one with /incident add <what happened>" if rows.empty?

        times = rows.map { |row| Time.parse(row["at"]) }
        [header(rows, times), *counts(rows, times),
         "These counts describe your notes. They cannot show what was said, and say nothing about her."].join("\n")
      end

      def counts(rows, times)
        ["by week: #{tally(times) { |time| time.strftime("%G-W%V") }}",
         "by weekday: #{tally(times) { |time| time.strftime("%a") }}",
         "by part of day: #{tally(times) { |time| part(time.hour) }}",
         "entries that mention a denial: #{rows.count { |row| row["text"].match?(DENIAL) }} of #{rows.size}"]
      end

      def header(rows, times)
        "incident0: #{rows.size} entries, #{times.min.strftime("%Y-%m-%d")} to #{times.max.strftime("%Y-%m-%d")}"
      end

      def part(hour)
        PARTS.each { |name, hours| return name if hours.cover?(hour) }
        nil
      end

      def tally(times, &key)
        times.group_by(&key).sort.map { |name, group| "#{name} #{group.size}" }.join(", ")
      end
    end
  end
end
