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
        @max = @taxonomy.dig("spawn_policy", "max_concurrent_children") || MAX_CONCURRENT
        @workers = []
        @mutex = Mutex.new
      end

      def spawn(type:, tag: nil, &block)
        parsed = Ground::Policy::Subagent.parse(type)
        allowed = Ground::Policy::Subagent.allowed_tool_names(parsed, @parent_tools)
        @mutex.synchronize do
          reap_dead
          return Result.err("agent_pool: at capacity (#{@max})", category: :validation) if @workers.size >= @max
        end

        if @governor && !spawn_permitted?(parsed, tag)
          return Result.err("agent_pool: governor denied spawn", category: :policy)
        end

        thread = spawn_worker_thread(parsed, allowed, tag, &block)
        @mutex.synchronize { @workers << Worker.new(type: parsed, thread:, started_at: Time.now, tag:, tools: allowed) }
        Result.ok(thread)
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
          Ground::SubagentContext.run(type: parsed, allowed:) do
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
        @governor.permit?("spawn_agent", :guarded, ctx).ok?
      rescue StandardError
        true
      end

      def reap_dead
        @workers.reject! { |w| !w.thread.alive? }
      end
    end
  end
end
