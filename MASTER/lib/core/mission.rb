# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"
require "time"
require_relative "../io/atomic_write"

module Master
  module Core
    # Mission — one durable contract for autonomous work.
    #
    # It does not perform work. It records the goal, scope, model, effort,
    # lifecycle and evidence pointers around the Fold so CLI, web and headless
    # callers see the same mission state. File contents remain Git/checkpoints'
    # responsibility.
    class Mission
      include Master::Io::AtomicWrite

      VERSION = 1
      REL_PATH = ".master/mission.json"
      MAX_GOAL_BYTES = 2_048
      MAX_PLAN_BYTES = 4_096
      STATES = %w[running completed failed interrupted].freeze
      STAGES = %w[discover plan execute verify deliver].freeze

      attr_reader :root, :id

      def initialize(root: Master::ROOT, bus: nil, checkpoint: nil)
        @root = File.expand_path(root)
        @bus = bus
        @checkpoint = checkpoint
        @id = nil
      end

      def start!(goal:, scope: @root, model: nil, effort: "medium", plan: nil)
        @id = SecureRandom.hex(10)
        @record = {
          "version" => VERSION,
          "id" => @id,
          "state" => "running",
          "stage" => "discover",
          "goal" => goal.to_s.byteslice(0, MAX_GOAL_BYTES).to_s,
          "scope" => relative(scope),
          "model" => model.to_s,
          "effort" => normalize_effort(effort),
          "plan" => plan.to_s.byteslice(0, MAX_PLAN_BYTES),
          "started_at" => now,
          "finished_at" => nil,
          "checkpoint" => nil,
          "artifacts" => [],
          "error" => nil,
        }
        persist!
        emit("mission:start", @record.slice("id", "goal", "scope", "model", "effort"))
        self
      end

      def transition!(stage, **payload)
        return self unless @record
        stage = stage.to_s
        raise ArgumentError, "unknown mission stage: #{stage}" unless STAGES.include?(stage)

        @record["stage"] = stage
        payload.each { |key, value| assign_payload(key, value) }
        persist!
        emit("mission:stage", id: @id, stage:, **payload)
        self
      end

      def checkpoint!(files: [])
        return self unless @record

        return self unless @checkpoint

        # Fix::Checkpoint#create answers with symbol keys; the record is JSON.
        checkpoint = @checkpoint.call(id: @id, root: @root, files: Array(files)).transform_keys(&:to_s)
        @record["checkpoint"] = checkpoint
        persist!
        emit("mission:checkpoint", id: @id, checkpoint: checkpoint["id"], files: checkpoint["files"].size)
        self
      end

      def artifact!(path)
        return self if path.to_s.empty? || !@record
        @record["artifacts"] = (@record["artifacts"] + [relative(path)]).uniq.last(32)
        persist!
        emit("mission:artifact", id: @id, path: relative(path))
        self
      end

      def finish!(state: "completed", summary: nil)
        return self unless @record
        raise ArgumentError, "unknown mission state: #{state}" unless STATES.include?(state.to_s)

        @record["state"] = state.to_s
        @record["stage"] = "deliver"
        @record["summary"] = summary.to_s.byteslice(0, 2_048) if summary
        @record["finished_at"] = now
        persist!
        emit("mission:finish", id: @id, state: @record["state"], summary: @record["summary"])
        self
      end

      def fail!(error)
        return self unless @record
        @record["state"] = "failed"
        @record["error"] = error.to_s.byteslice(0, 1_200)
        @record["finished_at"] = now
        persist!
        emit("mission:finish", id: @id, state: "failed", error: @record["error"])
        self
      rescue StandardError => e
        warn("mission0: #{e.class}: #{e.message}")
        self
      end

      def self.current(root: Master::ROOT)
        path = File.join(root, REL_PATH)
        return unless File.file?(path)

        JSON.parse(File.read(path, encoding: "UTF-8")).then do |record|
          record if record["version"].to_i == VERSION
        end
      rescue JSON::ParserError => e
        Master::Ground::Swallow.log(e, context: "mission.current")
        nil
      end

      def record
        @record&.dup
      end

      private

      def normalize_effort(value)
        text = value.to_s.downcase
        %w[low medium high].include?(text) ? text : "medium"
      end

      def assign_payload(key, value)
        case key.to_sym
        when :plan then @record["plan"] = value.to_s.byteslice(0, MAX_PLAN_BYTES)
        when :artifact then artifact!(value)
        when :checkpoint then @record["checkpoint"] = value
        end
      end

      def persist!
        path = File.join(@root, REL_PATH)
        FileUtils.mkdir_p(File.dirname(path))
        write_atomic(path, JSON.pretty_generate(@record) + "\n", mode: 0o600)
      end

      # Callers hand the payload either way: start! passes the record's slice
      # as a Hash, the rest pass keywords. Keywords alone raised on start!,
      # and a raising start aborted every /fix run it wrapped.
      def emit(event, payload = {}, **fields)
        @bus&.publish(event, payload.merge(fields))
      rescue StandardError => e
        warn("mission0: #{e.class}: #{e.message}") if ENV["MASTER_TRACE_STRICT"] == "1"
      end

      def relative(path)
        full = File.expand_path(path.to_s, @root)
        root = File.expand_path(@root)
        return path.to_s unless full == root || full.start_with?(root + File::SEPARATOR)

        full.delete_prefix(root + File::SEPARATOR)
      rescue ArgumentError
        path.to_s
      end

      def now = Time.now.utc.iso8601
    end
  end
end
