# frozen_string_literal: true
require "thread"

module Master
  module Judge
  # Typed child agents — replaces ad-hoc Thread.new in autoloop.
  # Reads agent_types from data/agent_taxonomy.yml at boot.
  class AgentPool
    MAX_CONCURRENT = 4

    Worker = Struct.new(:type, :thread, :started_at, :tag, keyword_init: true)

    def initialize(governor:, event_bus: nil, taxonomy_path: File.join(Master::ROOT, "data", "agent_taxonomy.yml"))
      @governor = governor
      @bus = event_bus
      @taxonomy = Master.load_yaml(taxonomy_path) || {}
      @max = @taxonomy.dig("spawn_policy", "max_concurrent_children") || MAX_CONCURRENT
      @workers = []
      @mutex = Mutex.new
    end

    def spawn(type:, tag: nil, &block)
      @mutex.synchronize do
        reap_dead
        return Result.err("agent_pool: at capacity (#{@max})", category: :validation) if @workers.size >= @max
      end

      thread = Thread.new do
        @bus&.publish("agent:start", type:, tag:)
        block.call
      rescue StandardError => err
        @bus&.publish("agent:error", type:, tag:, error: err.message)
      ensure
        @bus&.publish("agent:end", type:, tag:)
      end

      @mutex.synchronize { @workers << Worker.new(type:, thread:, started_at: Time.now, tag:) }
      Result.ok(thread)
    end

    # intentional — each thread is an independent worker, not a DB query
    def join_all(timeout: nil)
      @workers.map { |w| w.thread.join(timeout) }
    end

    def active_count
      @mutex.synchronize { reap_dead; @workers.size }
    end

    private

    def reap_dead
      @workers.reject! { |w| !w.thread.alive? }
    end
  end
  end
end
