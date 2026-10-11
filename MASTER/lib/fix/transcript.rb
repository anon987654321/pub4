# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "../ground/redactor"

module Master
  module Fix
    # Full records of what the council said and how the model tried to fix, as
    # NDJSON under .master/fix_transcripts/<run_id>/. The live log carries one
    # line per event; the reason behind a line lives here. Every string is
    # redacted before it is written, the run directory is capped, and only the
    # newest runs are kept, so a long run cannot fill the disk.
    class Transcript
      DIR = ".master/fix_transcripts"
      MAX_BYTES = 50 * 1024 * 1024
      KEEP_RUNS = 10

      attr_reader :dir

      def initialize(root:, run_id:, max_bytes: MAX_BYTES, keep: KEEP_RUNS)
        @base = File.join(root, DIR)
        @dir = File.join(@base, run_id.to_s.gsub(/[^A-Za-z0-9._-]/, "_"))
        @max_bytes = max_bytes
        @keep = keep
        @mutex = Mutex.new
        @truncated = false
        @pruned = false
      end

      # Appends one record to <name>.ndjson. Returns false once the run's cap is
      # reached; the first refusal leaves a marker so a reader knows why the
      # transcript stops.
      def append(name, record)
        @mutex.synchronize do
          FileUtils.mkdir_p(@dir)
          prune_once
          line = "#{JSON.generate(redact({ at: Time.now.utc.iso8601(3) }.merge(record)))}\n"
          return false if over_cap?(line)

          File.open(File.join(@dir, "#{name}.ndjson"), "a") { |io| io.write(line) }
          true
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Transcript.append") if defined?(Master::Ground::Swallow)
        false
      end

      def redact(value)
        case value
        when String then Master::Ground::Redactor.text(value)
        when Hash then value.to_h { |key, item| [key, key.to_s.match?(Master::Ground::Redactor::SENSITIVE_KEYS) ? "[REDACTED]" : redact(item)] }
        when Array then value.map { |item| redact(item) }
        when Symbol then value.to_s
        else value
        end
      end

      def size
        Dir.glob(File.join(@dir, "*")).sum { |path| File.file?(path) ? File.size(path) : 0 }
      end

      private

      def over_cap?(line)
        return true if @truncated
        return false if size + line.bytesize <= @max_bytes

        @truncated = true
        marker = "#{JSON.generate({ at: Time.now.utc.iso8601(3), kind: "truncated", reason: "run transcript reached #{@max_bytes} bytes" })}\n"
        File.open(File.join(@dir, "critique.ndjson"), "a") { |io| io.write(marker) }
        true
      end

      def prune_once
        return if @pruned

        @pruned = true
        runs = Dir.glob(File.join(@base, "*")).select { |path| File.directory?(path) && path != @dir }
        stale = runs.sort_by { |path| File.mtime(path) }.reverse.drop([@keep - 1, 0].max)
        stale.each { |path| FileUtils.rm_rf(path) }
      end
    end
  end
end
