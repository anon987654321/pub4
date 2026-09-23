# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "boot_receipt"
require_relative "../io/atomic_write"

module Master
  module Ground
    # The last repository state that passed MASTER's delivery checks.
    #
    # Promotion is metadata-only and happens after a successful commit + push.
    # Rollback is deliberately explicit, refuses a dirty checkout, and moves
    # the checkout to the recorded commit rather than silently deleting work.
    class KnownGood
      PATH = ".master/known_good.json"
      VERSION = 1

      def initialize(root:, bus: nil)
        @root = root
        @bus = bus
      end

      def current
        path = File.join(@root, PATH)
        return nil unless File.file?(path)

        JSON.parse(File.read(path, encoding: "UTF-8"))
      rescue JSON::ParserError => e
        raise "known-good record is corrupt: #{e.message}"
      end

      def promote!(commit:, paths: [])
        record = {
          "version" => VERSION,
          "commit" => commit.to_s,
          "paths" => Array(paths).map { |path| relative(path) }.compact.uniq.sort,
          "constitution" => safe_digest,
          "promoted_at" => Time.now.utc.iso8601,
        }
        path = File.join(@root, PATH)
        FileUtils.mkdir_p(File.dirname(path))
        write_atomic(path, JSON.pretty_generate(record) + "\n", mode: 0o600)
        @bus&.publish("runtime:promoted", commit: record["commit"], paths: record["paths"])
        Result.ok(record)
      rescue StandardError => e
        @bus&.publish("runtime:promotion_failed", error: e.message)
        Result.err("known-good promotion: #{e.message}", category: :infrastructure)
      end

      def matches_head?
        record = current
        return false unless record

        out, status = Master::Io::Exec.capture2e("git", "-C", @root, "rev-parse", "HEAD")
        status.success? && out.strip == record["commit"]
      end

      def rollback!
        record = current
        return Result.err("no known-good runtime", category: :validation) unless record
        return Result.err("rollback refused: working tree is dirty", category: :policy) if dirty?
        return Result.ok("already at known-good #{record["commit"]}") if matches_head?

        sha = record.fetch("commit")
        run("git", "-C", @root, "reset", "--hard", sha)
        @bus&.publish("runtime:rollback", commit: sha)
        Result.ok("rolled back to known-good #{sha}")
      rescue StandardError => e
        @bus&.publish("runtime:rollback_failed", error: e.message)
        Result.err("known-good rollback: #{e.message}", category: :infrastructure)
      end

      private

      def safe_digest
        BootReceipt.digest(root: @root)
      rescue StandardError
        "unmeasured"
      end

      def dirty?
        out, status = Master::Io::Exec.capture3("git", "-C", @root, "status", "--porcelain")
        status.success? && !out.strip.empty?
      end

      def run(*argv)
        out, status = Master::Io::Exec.capture2e(*argv)
        raise out.strip unless status.success?

        out.strip
      end

      def relative(path)
        return unless path

        full = File.expand_path(path, @root)
        root = File.expand_path(@root)
        return unless full == root || full.start_with?(root + File::SEPARATOR)

        full.delete_prefix(root + File::SEPARATOR)
      end
    end
  end
end
