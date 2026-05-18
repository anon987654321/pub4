# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module Master
  module Now
  module Orchestration
  # EventSequenceOrchestrator — append-only event coordination layer.
  # Issue #396 items 1, 4, 8: replace implicit mutable state with append-only
  # event streams; separate cognition from orchestration; replay/checkpoint.
  #
  # Every intent proposed by a model is validated before execution. Every
  # mutation emits a before/after event. The event stream is replayable from
  # any checkpoint. Orchestration state is derived from the stream, never stored
  # separately.
  class EventSequenceOrchestrator
    STREAM_PATH    = File.join(Master::ROOT, "runtime", "events", "sequence.ndjson").freeze
    CHECKPOINT_DIR = File.join(Master::ROOT, "runtime", "checkpoints").freeze

    Event = Data.define(:id, :ts, :type, :workflow_id, :payload)

    VALID_INTENT_TYPES = %i[
      llm_call tool_execution file_mutation git_op
      provider_route session_save ui_update
    ].freeze

    def initialize(path: STREAM_PATH, checkpoint_dir: CHECKPOINT_DIR,
                   event_bus: nil, now: -> { Time.now.utc })
      @path           = path
      @checkpoint_dir = checkpoint_dir
      @bus            = event_bus
      @now            = now
    end

    # Validate an intent before allowing execution
    def propose(intent_type:, workflow_id:, payload: {})
      unless VALID_INTENT_TYPES.include?(intent_type.to_sym)
        return Result.err("unknown intent type: #{intent_type}", category: :validation)
      end
      event = emit(:intent_proposed, workflow_id:, payload: payload.merge(intent_type:))
      Result.ok(event)
    end

    # Wrap execution with before/after events; capture outcome
    def execute(intent_type:, workflow_id:, payload: {}, &block)
      proposal = propose(intent_type:, workflow_id:, payload:)
      return proposal unless proposal.ok?

      emit(:execution_started, workflow_id:, payload: { intent_type:, **payload })
      result = block.call
      emit(:execution_completed, workflow_id:, payload: { intent_type:, ok: true })
      Result.ok(result)
    rescue StandardError => e
      emit(:execution_failed, workflow_id:, payload: { intent_type:, error: e.message })
      Master::Ground::Swallow.log(e, context: "EventSequenceOrchestrator.execute(#{intent_type})", event_bus: @bus)
      Result.err("execution failed: #{e.message}", category: :infrastructure)
    end

    # Create a replayable checkpoint at the current stream offset
    def checkpoint(workflow_id:, label: "auto")
      FileUtils.mkdir_p(@checkpoint_dir)
      offset = stream_size
      entry  = { workflow_id:, label:, offset:, ts: @now.call.iso8601 }
      path   = File.join(@checkpoint_dir, "#{workflow_id}-#{label}-#{offset}.json")
      File.write(path, JSON.pretty_generate(entry))
      emit(:checkpoint_created, workflow_id:, payload: { label:, offset: })
      Result.ok(entry)
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "EventSequenceOrchestrator.checkpoint", event_bus: @bus)
      Result.err(e.message, category: :infrastructure)
    end

    # Replay events from a checkpoint offset — yields each event to the block
    def replay(from_offset: 0, workflow_id: nil)
      return Result.err("no block given", category: :validation) unless block_given?
      events = stream_events(from_offset:, workflow_id:)
      events.each { |e| yield e }
      Result.ok(events.size)
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "EventSequenceOrchestrator.replay", event_bus: @bus)
      Result.err(e.message, category: :infrastructure)
    end

    def recent(n = 20, workflow_id: nil)
      stream_events(workflow_id:).last(n)
    end

    def rotate!(keep_last: 1000)
      return unless File.file?(@path)
      lines = File.readlines(@path, chomp: true)
      return if lines.size <= keep_last
      tail = lines.last(keep_last)
      File.write(@path, tail.join("\n") + "\n")
      emit(:stream_rotated, workflow_id: "system", payload: { kept: keep_last, dropped: lines.size - keep_last })
      Result.ok(lines.size - keep_last)
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "EventSequenceOrchestrator.rotate!", event_bus: @bus)
      Result.err(e.message, category: :infrastructure)
    end

    private

    def emit(type, workflow_id:, payload: {})
      event = {
        id:          SecureRandom.hex(8),
        ts:          @now.call.iso8601,
        type:        type.to_s,
        workflow_id: workflow_id.to_s,
        payload:
      }
      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, "a") { |f| f.puts(JSON.generate(event)) }
      @bus&.publish("orchestration:#{type}", **event)
      event
    end

    def stream_events(from_offset: 0, workflow_id: nil)
      return [] unless File.file?(@path)
      lines = File.readlines(@path, chomp: true).drop(from_offset)
      lines.filter_map do |line|
        next if line.strip.empty?
        e = JSON.parse(line)
        next if workflow_id && e["workflow_id"] != workflow_id.to_s
        e
      rescue JSON::ParserError
        nil
      end
    end

    def stream_size
      return 0 unless File.file?(@path)
      File.readlines(@path).size
    end
  end
  end
  end
end
