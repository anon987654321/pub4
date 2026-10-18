# frozen_string_literal: true

require "thread"

module Master
  module Review
  # Typed child agents — replaces ad-hoc Thread.new in autoloop.
  # Reads agent_types from data/agent_taxonomy.yml at boot.
    class AgentPool
      MAX_CONCURRENT = 4

      Worker = Struct.new(:type, :thread, :started_at, :tag, :tools, keyword_init: true)

      # `taxonomy:` is the injection point the tests use. It defaults to the one
      # accessor rather than to a path this file builds itself — three files
      # spelled that path three ways, which reader_singularity counts as three
      # implementations of loading one file.
      def initialize(governor:, tools: nil, event_bus: nil, taxonomy: nil)
        @governor = governor
        @parent_tools = Array(tools)
        @bus = event_bus
        @taxonomy = taxonomy || Master.agent_taxonomy
        configured_max = @taxonomy.dig("spawn_policy", "max_concurrent_children") || MAX_CONCURRENT
        @max = Integer(configured_max)
        raise ArgumentError, "max_concurrent_children must be between 1 and 64" unless @max.between?(1, 64)

        @workers = []
        @reservations = 0
        @mutex = Mutex.new
      end

      def spawn(type:, tag: nil, &block)
        parsed = Ground::Policy::Subagent.parse(type)
        allowed = Ground::Policy::Subagent.allowed_tool_names(parsed, @parent_tools)
        reserved = @mutex.synchronize do
          reap_dead
          if @workers.size + @reservations >= @max
            false
          else
            @reservations += 1
            true
          end
        end
        return Result.err("agent_pool: at capacity (#{@max})", category: :validation) unless reserved

        reservation_active = true
        if @governor && !spawn_permitted?(parsed, tag)
          release_reservation
          reservation_active = false
          return Result.err("agent_pool: governor denied spawn", category: :policy)
        end

        thread = spawn_worker_thread(parsed, allowed, tag, &block)
        @mutex.synchronize do
          @reservations -= 1
          reservation_active = false
          @workers << Worker.new(type: parsed, thread:, started_at: Time.now, tag:, tools: allowed)
        end
        Result.ok(thread)
      rescue StandardError => e
        release_reservation if reservation_active
        @bus&.publish("agent:spawn_failed", type: parsed, tag:, error: e.class.name)
        Result.err("agent_pool: spawn failed (#{e.class})", category: :infrastructure)
      end

      def join_all(timeout: nil)
        @workers.map { |w| w.thread.join(timeout) }
      end

      def active_count
        @mutex.synchronize { reap_dead; @workers.size }
      end

      private

      def spawn_worker_thread(parsed, allowed, tag, &block)
        Thread.new do
          Thread.current.report_on_exception = false
          CLI::SubagentContext.run(type: parsed, allowed:) do
            @bus&.publish("agent:start", type: parsed, tag:, tools: allowed)
            block.call
          rescue StandardError => err
            @bus&.publish("agent:error", type: parsed, tag:, error: err.message)
            raise
          ensure
            @bus&.publish("agent:end", type: parsed, tag:)
          end
        end
      end

      def spawn_permitted?(type, tag)
        ctx = "spawn #{type}#{tag ? " #{tag}" : ""}"
        result = @governor.permit?("spawn_agent", :guarded, ctx)
        return result.ok? if result.respond_to?(:ok?)

        @bus&.publish("agent:spawn_check_failed", type:, tag:, reason: "invalid governor result")
        false
      rescue StandardError => e
        # An unavailable governor is not approval. A child process is additional
        # model authority, so uncertainty at this boundary must deny the spawn.
        @bus&.publish("agent:spawn_check_failed", type:, tag:, error: e.class.name)
        false
      end

      def release_reservation
        @mutex.synchronize { @reservations -= 1 if @reservations.positive? }
      end

      def reap_dead
        @workers.reject! { |w| !w.thread.alive? }
      end
    end
  end
end
