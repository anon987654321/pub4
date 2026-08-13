# frozen_string_literal: true

require "yaml"

module Master
  module Fix
    class Heartbeat
      include Master::Ground::AtomicWrite
      POLL_INTERVAL = 60
      JOURNAL_KEEP = 50
      STATE_PATH = ".master/heartbeat_state.yml".freeze

      RESULT_TRUNCATE = 200
      SECONDS_PER_HOUR = 3600

      JOB_HANDLERS = {
        "prune_memory" => :prune_memory,
        "check_models" => :check_model_availability,
        "self_test" => :run_self_test,
        "prune_undo" => :prune_undo_journal,
        "snapshot" => :run_snapshot,
        "personal_pulse" => :personal_pulse,
      }.freeze

      def initialize(root:, agent: nil, scanner: nil, memory: nil, event_bus: nil, homeostat: nil)
        @root = root
        @agent = agent
        @scanner = scanner
        @memory = memory
        @bus = event_bus
        @homeostat = homeostat
        @jobs = load_jobs
        @state = load_state
        @thread = nil
        @stop = false
      end

      def start!
        return unless ENV["MASTER_HEARTBEAT"] == "1"
        return if @jobs.empty?

        @stop = false
        @thread = Thread.new do
          loop do
            break if @stop
            run_due!
            @homeostat&.observe(:idle_tick)
            sleep POLL_INTERVAL
          end
        rescue StandardError => e
          @bus&.publish("heartbeat:error", message: e.message)
        end
      end

      def stop!
        @stop = true
        @thread&.kill
        @thread = nil
      end

      def run_due!
        now = Time.now.to_i
        results = @jobs.filter_map { |job| run_job_if_due(job, now) }
        persist_state unless results.empty?
        results
      end

      def run_job_if_due(job, now)
        name = job["name"]
        interval = job["interval_seconds"].to_i
        last_run = @state.dig(name, "last_run").to_i
        return unless now - last_run >= interval

        @bus&.publish("heartbeat:run", job: name)
        result = execute_job(job)
        @state[name] = @state.fetch(name, {}).merge(
          "last_run" => now,
          "result" => result.to_s[0, RESULT_TRUNCATE],
        )
        { name:, result: }
      end

      def list
        @jobs.map do |job|
          last = @state.dig(job["name"], "last_run").to_i
          ago = last.zero? ? "never" : "#{(Time.now.to_i - last) / 60}m ago"
          "#{job["name"]}: every #{job["interval_seconds"] / 60}m, last: #{ago}"
        end.join("\n")
      end

      private

      def execute_job(job)
        method_name = JOB_HANDLERS[job["action"]]
        return "unknown action: #{job["action"]}" unless method_name

        Master::Trace::Telemetry.span("heartbeat.tick", job: job["name"].to_s) do
          send(method_name)
        end
      rescue StandardError => e
        "error: #{e.message}"
      end

      def prune_memory
        @memory&.consolidate!(agent: @agent) || "no memory"
      end

      def check_model_availability
        return "no agent" unless @agent
        id = @agent.model.to_s
        return "no active model" if id.empty?
        alive = model_reachable?(id)
        "model: #{id.split("/").last} #{alive ? "reachable" : "unreachable"}"
      end

      def model_reachable?(model_id)
        RubyLLM.chat(model: model_id).ask("ping")
        true
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Heartbeat.model_reachable?", event_bus: @bus, model_id:)
        false
      end

      def run_self_test
        return "no scanner" unless @scanner

        result = Master::Review::Scan::SelfTest.new(root: @root, event_bus: @bus).call
        return "scan failed" unless Result.wrap(result).ok?

        summary = result.value!
        @bus&.publish("heartbeat:self_test", violations: summary.violation_count, checks: summary.to_h)
        publish_scan_metrics(summary)
        summary.line
      end

      def publish_scan_metrics(summary)
        if summary.violation_count.zero?
          @state["self_test"] = @state.fetch("self_test", {}).merge("last_fixed" => Time.now.to_i)
          @bus&.publish("heartbeat:scan_clean", violations: 0, last_fixed: @state.dig("self_test", "last_fixed"))
          return
        end

        @bus&.publish("heartbeat:violations",
          violations: summary.violation_count,
          last_fixed: @state.dig("self_test", "last_fixed"))
      end

      def prune_undo_journal
        journal_path = File.join(@root, ".master", "undo.jsonl")
        return "no journal" unless File.exist?(journal_path)

        lines = File.readlines(journal_path)
        return "journal empty" if lines.empty?

        keep = [lines.size / 2, JOURNAL_KEEP].max
        File.write(journal_path, lines.last(keep).join)
        "pruned undo: kept #{keep}/#{lines.size} entries"
      end

      def run_snapshot
        container = { root: @root, bus: @bus }
        Builder.boot_snapshot(container)
        "snapshot: generated"
      end

      def personal_pulse
        Master::Ground::PersonalWorkspace.pulse(root: @root)
      end

      def load_jobs
        path = File.join(@root, "data", "patterns.yml")
        return default_jobs unless File.exist?(path)

        result = (Master.load_yaml(path) || {})["heartbeat"]
        jobs = result.is_a?(Array) ? result : default_jobs
        jobs.select { |j| j["enabled"] != false }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Heartbeat.load_jobs", event_bus: @bus)
        default_jobs
      end

      def default_jobs
        [
          { "name" => "prune_memory", "action" => "prune_memory", "interval_seconds" => SECONDS_PER_HOUR },
          { "name" => "self_test", "action" => "self_test", "interval_seconds" => SECONDS_PER_HOUR },
          { "name" => "prune_undo", "action" => "prune_undo", "interval_seconds" => 86_400 },
          { "name" => "snapshot", "action" => "snapshot", "interval_seconds" => 14_400 },
        ]
      end

      def load_state
        path = File.join(@root, STATE_PATH)
        return {} unless File.exist?(path)

        Master.load_yaml(path) || {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Heartbeat.load_state", event_bus: @bus, path:)
        {}
      end

      def persist_state
        path = File.join(@root, STATE_PATH)
        FileUtils.mkdir_p(File.dirname(path))
        write_atomic(path, @state.to_yaml)
      end
    end
  end
end
