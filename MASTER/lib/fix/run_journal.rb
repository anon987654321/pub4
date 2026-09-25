# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "../io/atomic_write"

module Master
  module Fix
    # Durable lifecycle journal for /fix runs.
    #
    # The journal is deliberately metadata-only. It never tries to reconstruct
    # files from JSON; Git, Checkpoint and the write journal remain the sources
    # of truth for content. Its job is to make interruption visible and let the
    # next run resume from a known completed pass instead of pretending the
    # previous run finished.
    class RunJournal
      include Master::Io::AtomicWrite

      VERSION = 1
      PATH = ".master/fix_runs.json"
      LOCK = ".master/fix_runs.lock"
      MAX_RUNS = 24
      RESUMABLE_STATES = %w[active crashed delivery_failed].freeze

      def initialize(root:, bus: nil)
        @root = root
        @bus = bus
      end

      def start_or_resume(target:, files:, max_passes:, budget_seconds:)
        with_lock do
          data = load
          resumable = data["runs"].reverse.find { |run| RESUMABLE_STATES.include?(run["state"].to_s) }
          resumable = nil if resumable && release_elsewhere(resumable, target)
          next resume_existing_run(resumable, target, data) if resumable

          create_new_run(target:, files:, max_passes:, budget_seconds:, data:)
        end
      rescue StandardError => e
        emit("fix:journal_error", operation: "start", error: e.message)
        raise
      end

      def pass_start(run_id, pass, transaction_id:)
        update(run_id) do |run|
          run["passes"] << {
            "pass" => pass.to_i,
            "state" => "active",
            "transaction_id" => transaction_id.to_s,
            "started_at" => Time.now.utc.iso8601,
          }
        end
      end

      def pass_finish(run_id, pass, status:, message: nil)
        update(run_id) do |run|
          entry = Array(run["passes"]).reverse.find { |row| row["pass"].to_i == pass.to_i }
          next unless entry

          entry["state"] = status.to_s
          entry["message"] = message.to_s[0, 400] unless message.nil?
          entry["finished_at"] = Time.now.utc.iso8601
        end
      end

      def terminal(run_id, state, message: nil)
        update(run_id) do |run|
          run["state"] = state.to_s
          run["message"] = message.to_s[0, 400] unless message.nil?
          run["finished_at"] = Time.now.utc.iso8601
        end
      end

      def crash(run_id, error)
        update(run_id) do |run|
          run["state"] = "crashed"
          run["error"] = error.to_s[0, 800]
          run["finished_at"] = Time.now.utc.iso8601
        end
      end

      def active_pass(run)
        Array(run["passes"]).reverse.find { |row| %w[active delivery_failed].include?(row["state"].to_s) }
      end

      def next_pass(run)
        completed = Array(run["passes"]).reject { |row| row["state"].to_s == "active" }
        completed.map { |row| row["pass"].to_i }.max.to_i + 1
      end

      def active
        load["runs"].reverse.find { |run| run["state"] == "active" }
      end

      def history(limit: MAX_RUNS)
        load["runs"].last(limit)
      end

      private

      # A resumable run on another target whose process is gone would block
      # every other target until someone reran exactly that one: a MASTER/tools run
      # that crashed on dilla.rb's length refused /fix RAILS for good. It is
      # closed as interrupted, with the reason, and a live one still refuses.
      # True when the run was released.
      def release_elsewhere(run, target)
        return false if run["target"] == relative(target)
        return false if process_alive?(run["pid"])

        previous = run["state"]
        run["state"] = "interrupted"
        run["message"] = "left #{previous}; #{relative(target)} started while its process was gone"
        run["finished_at"] = Time.now.utc.iso8601
        emit("fix:interrupted", run_id: run["id"], target: run["target"], previous_state: previous)
        true
      end

      def resume_existing_run(active, target, data)
        unless active["target"] == relative(target)
          raise "another fix run is active: #{active["id"]} for #{active["target"]}"
        end
        if active["state"] == "active" && active["pid"].to_i != Process.pid && process_alive?(active["pid"])
          raise "another fix process is active: #{active["id"]} pid=#{active["pid"]}"
        end
        previous_state = active["state"]
        active["state"] = "active"
        active["resumed_from"] = previous_state unless previous_state == "active"
        active["resumed_at"] = Time.now.utc.iso8601
        active["resume_count"] = active.fetch("resume_count", 0).to_i + 1
        remaining = remaining_seconds(active)
        persist(data)
        emit("fix:resume", run_id: active["id"], pass: next_pass(active),
                      resume_count: active["resume_count"], remaining_seconds: remaining)
        active.merge("resumed" => true, "remaining_seconds" => remaining)
      end

      def create_new_run(target:, files:, max_passes:, budget_seconds:, data:)
        now = Time.now.utc
        run = {
          "id" => SecureRandom.hex(10),
          "state" => "active",
          "target" => relative(target),
          "files" => Array(files).map { |path| relative(path) }.compact.uniq.sort,
          "max_passes" => Integer(max_passes),
          "budget_seconds" => Integer(budget_seconds),
          "started_at" => now.iso8601,
          "deadline_at" => (now + Integer(budget_seconds)).iso8601,
          "last_seen_at" => now.iso8601,
          "pid" => Process.pid,
          "passes" => [],
        }
        data["runs"] << run
        data["runs"] = data["runs"].last(MAX_RUNS)
        persist(data)
        emit("fix:start", run_id: run["id"], target: run["target"])
        run.merge("resumed" => false, "remaining_seconds" => Integer(budget_seconds).to_f)
      end

      # No external caller (checked: only start_or_resume calls this, without
      # an explicit receiver, which private allows).
      def remaining_seconds(run)
        deadline = Time.iso8601(run["deadline_at"].to_s)
        now = Time.now.utc
        last = run["last_seen_at"] && Time.iso8601(run["last_seen_at"].to_s)
        return 0.0 if last && now < last

        remaining = [deadline - now, 0.0].max
        run["last_seen_at"] = now.iso8601
        remaining
      rescue ArgumentError
        0.0
      end

      def emit(event, **payload)
        @bus&.publish(event, **payload)
      rescue StandardError => e
        warn("trace0: #{e.class}: #{e.message}") if ENV["MASTER_TRACE_STRICT"] == "1"
        nil
      end

      def process_alive?(pid)
        value = pid.to_i
        return false if value <= 0

        Process.kill(0, value)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      def update(run_id)
        with_lock do
          data = load
          run = data["runs"].find { |row| row["id"] == run_id }
          return unless run

          yield run
          persist(data)
        end
      end

      def load
        path = File.join(@root, PATH)
        return { "version" => VERSION, "runs" => [] } unless File.file?(path)

        raw = JSON.parse(File.read(path, encoding: "UTF-8"))
        raise "fix journal version #{raw["version"]} is unsupported" unless raw["version"].to_i == VERSION

        runs = raw["runs"]
        raise "fix journal runs must be an array" unless runs.is_a?(Array)

        { "version" => VERSION, "runs" => runs }
      rescue JSON::ParserError => e
        emit("fix:journal_corrupt", error: e.message)
        raise "fix journal is corrupt: #{e.message}"
      end

      def persist(data)
        path = File.join(@root, PATH)
        FileUtils.mkdir_p(File.dirname(path))
        write_atomic(path, JSON.pretty_generate(data) + "\n", mode: 0o600)
      end

      def with_lock
        lock_path = File.join(@root, LOCK)
        FileUtils.mkdir_p(File.dirname(lock_path))
        File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |io|
          io.flock(File::LOCK_EX)
          yield
        ensure
          io&.flock(File::LOCK_UN)
        end
      end

      def relative(path)
        value = path.to_s
        return if value.empty?

        full = File.expand_path(value, @root)
        root = File.expand_path(@root)
        return value unless full == root || full.start_with?(root + File::SEPARATOR)

        full.delete_prefix(root + File::SEPARATOR)
      rescue ArgumentError
        nil
      end
    end
  end
end
