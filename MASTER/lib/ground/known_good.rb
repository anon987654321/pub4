# frozen_string_literal: true

require "json"
require "fileutils"
require "time"
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
      include Master::Io::AtomicWrite

      PATH = ".master/known_good.json"
      VERSION = 1

      def initialize(root:, bus: nil)
        @root = root
        @bus = bus
      end

      def current
        path = File.join(@root, PATH)
        return nil unless File.file?(path)

        record = JSON.parse(File.read(path, encoding: "UTF-8"))
        raise "known-good version #{record["version"]} unsupported" unless record["version"].to_i == VERSION

        record
      rescue JSON::ParserError => e
        raise "known-good record is corrupt: #{e.message}"
      end

      def promote!(commit:, paths: [])
        sha = normalize_commit(commit)
        raise ArgumentError, "known-good commit is not present in repository" unless resolve_commit(sha)

        record = {
          "version" => VERSION,
          "commit" => sha,
          "paths" => Array(paths).map { |path| relative(path) }.compact.uniq.sort,
          "constitution" => safe_digest,
          "promoted_at" => Time.now.utc.iso8601,
        }
        path = File.join(@root, PATH)
        FileUtils.mkdir_p(File.dirname(path))
        write_atomic(path, JSON.pretty_generate(record) + "\n", mode: 0o600)
        emit("runtime:promoted", commit: record["commit"], paths: record["paths"])
        Result.ok(record)
      rescue StandardError => e
        emit("runtime:promotion_failed", error: e.message)
        Result.err("known-good promotion: #{e.message}", category: :infrastructure)
      end

      def matches_head?
        record = current
        return false unless record

        commit = normalize_commit(record.fetch("commit"))
        current = resolve_commit("HEAD")
        expected = resolve_commit(commit)
        current && expected && current == expected
      rescue KeyError, ArgumentError
        false
      end

      def rollback!
        record = current
        return Result.err("no known-good runtime", category: :validation) unless record
        return Result.err("rollback refused: working tree is dirty", category: :policy) if dirty?
        return Result.ok("already at known-good #{record["commit"]}") if matches_head?

        sha = normalize_commit(record.fetch("commit"))
        run("git", "-C", @root, "reset", "--hard", sha)
        emit("runtime:rollback", commit: sha)
        Result.ok("rolled back to known-good #{sha}")
      rescue StandardError => e
        emit("runtime:rollback_failed", error: e.message)
        Result.err("known-good rollback: #{e.message}", category: :infrastructure)
      end

      private
      def emit(event, **payload)
        @bus&.publish(event, **payload)
      rescue StandardError => e
        warn("trace0: #{e.class}: #{e.message}") if ENV["MASTER_TRACE_STRICT"] == "1"
        nil
      end


      def normalize_commit(value)
        commit = value.to_s
        raise ArgumentError, "known-good commit is not a Git SHA" unless commit.match?(/\A[0-9a-f]{7,64}\z/i)

        commit
      end

      def safe_digest
        BootReceipt.digest(root: @root)
      rescue StandardError
        "unmeasured"
      end

      def resolve_commit(ref)
        out, status = Master::Io::Exec.capture2e("git", "-C", @root, "rev-parse", "--verify", "#{ref}^{commit}")
        status.success? ? out.strip : nil
      end

      def dirty?
        out, status = Master::Io::Exec.capture2("git", "-C", @root, "status", "--porcelain")
        raise "git status failed while checking rollback safety" unless status.success?

        !out.strip.empty?
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
