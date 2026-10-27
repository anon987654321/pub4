# frozen_string_literal: true

require "digest"
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
    #
    # Each line carries the hash of the line before it and its own, so an edited,
    # dropped or reordered line shows when Transcript.verify reads the file back.
    # The chain is per file and starts from GENESIS; a resumed run continues the
    # chain from the file's last line.
    class Transcript
      GENESIS = "0" * 64
      Verdict = Data.define(:ok, :lines, :broken_at, :reason)
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
        @heads = {}
      end

      # Appends one record to <name>.ndjson. Returns false once the run's cap is
      # reached; the first refusal leaves a marker so a reader knows why the
      # transcript stops.
      def append(name, record)
        @mutex.synchronize do
          FileUtils.mkdir_p(@dir)
          prune_once
          body = redact({ at: Time.now.utc.iso8601(3) }.merge(record))
          line = chained(name, body)
          return false if over_cap?(line)

          write(name, line)
          true
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Transcript.append") if defined?(Master::Ground::Swallow)
        false
      end

      # The verdict on one transcript file: every line's prev equals the hash before it
      # and every hash is the digest of prev plus the line's own body.
      def self.verify(path)
        previous = GENESIS
        count = 0
        File.foreach(path) do |raw|
          count += 1
          row = JSON.parse(raw)
          body = row.reject { |key, _| %w[prev hash].include?(key) }
          return Verdict.new(ok: false, lines: count, broken_at: count, reason: "prev does not match the line before") unless row["prev"] == previous
          return Verdict.new(ok: false, lines: count, broken_at: count, reason: "hash does not match the line's body") unless row["hash"] == digest(previous, body)

          previous = row["hash"]
        end
        Verdict.new(ok: true, lines: count, broken_at: nil, reason: nil)
      rescue JSON::ParserError => e
        Verdict.new(ok: false, lines: count, broken_at: count, reason: "line is not JSON: #{e.message[0, 80]}")
      end

      def self.digest(previous, body) = Digest::SHA256.hexdigest("#{previous}#{JSON.generate(body)}")

      def redact(value)
        case value
        # A patch is git's output and arrives BINARY; json warns on it today and will raise in json 3.0.
        when String then Master::Ground::Redactor.text(as_text(value))
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

      def as_text(text) = text.encoding == Encoding::BINARY ? text.dup.force_encoding(Encoding::UTF_8).scrub : text

      def chained(name, body)
        previous = head(name)
        "#{JSON.generate(body.merge(prev: previous, hash: self.class.digest(previous, body)))}\n"
      end

      # The head moves only once the line is on disk, so a refused line leaves the chain intact.
      def write(name, line)
        File.open(File.join(@dir, "#{name}.ndjson"), "a") { |io| io.write(line) }
        @heads[name] = JSON.parse(line)["hash"]
      end

      def head(name)
        @heads[name] ||= last_hash(File.join(@dir, "#{name}.ndjson"))
      end

      def last_hash(path)
        return GENESIS unless File.file?(path)

        last = nil
        File.foreach(path) { |raw| last = raw }
        last ? JSON.parse(last).fetch("hash", GENESIS) : GENESIS
      rescue JSON::ParserError
        GENESIS
      end

      def over_cap?(line)
        return true if @truncated
        return false if size + line.bytesize <= @max_bytes

        @truncated = true
        marker = chained("critique", { at: Time.now.utc.iso8601(3), kind: "truncated", reason: "run transcript reached #{@max_bytes} bytes" })
        write("critique", marker)
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
