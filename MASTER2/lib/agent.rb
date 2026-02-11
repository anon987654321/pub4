# frozen_string_literal: true

require "securerandom"
require "timeout"

module MASTER
  class Agent
    attr_reader :id, :parent_id, :scope, :task, :budget, :axiom_filter, :status, :result

    def initialize(task:, budget:, scope: "general", axiom_filter: nil, parent_id: nil)
      @id = SecureRandom.hex(8)
      @parent_id = parent_id || "root"
      @scope = scope
      @task = task
      @budget = budget
      @axiom_filter = axiom_filter
      @status = :pending
      @result = nil
      @started_at = nil
      @finished_at = nil
    end

    def user_agent
      axiom_count = DB.axioms.size
      "MASTER/#{VERSION} (agent:#{@id}; parent:#{@parent_id}; scope:#{@scope}; " \
        "axioms:#{axiom_count}; budget:$#{format('%.2f', @budget)})"
    end

    def run
      @status = :running
      @started_at = Time.now

      puts "agent0 at master0: #{@id} (parent:#{@parent_id}, scope:#{@scope}, " \
           "budget:$#{format('%.2f', @budget)})"

      pipeline = Pipeline.new
      @result = pipeline.call(@task)

      @status = @result.ok? ? :completed : :failed
      @finished_at = Time.now

      @result
    end

    def elapsed
      return nil unless @started_at

      (@finished_at || Time.now) - @started_at
    end

    def to_h
      {
        id: @id,
        parent_id: @parent_id,
        scope: @scope,
        status: @status,
        elapsed: elapsed,
        budget: @budget,
        user_agent: user_agent,
      }
    end
  end

  class AgentPool
    MAX_CONCURRENT = 4
    AGENT_TIMEOUT = 300

    attr_reader :agents

    def initialize(parent_budget:)
      @agents = []
      @parent_budget = parent_budget
      @mutex = Mutex.new
    end

    def spawn(task:, scope: "general", budget_fraction: 0.25, axiom_filter: nil, parent_id: nil)
      agent_budget = @parent_budget * budget_fraction

      agent = Agent.new(
        task: task,
        budget: agent_budget,
        scope: scope,
        axiom_filter: axiom_filter,
        parent_id: parent_id,
      )

      @mutex.synchronize { @agents << agent }
      agent
    end

    def run_all
      results = {}

      @agents.each_slice(MAX_CONCURRENT) do |batch|
        threads = batch.map do |agent|
          Thread.new do
            Timeout.timeout(AGENT_TIMEOUT) { agent.run }
          rescue Timeout::Error
            agent.instance_variable_set(:@status, :timeout)
            agent.instance_variable_set(
              :@result,
              Result.err("Agent #{agent.id} timed out after #{AGENT_TIMEOUT}s"),
            )
          end
        end

        threads.each(&:join)
      end

      @agents.each { |a| results[a.id] = a }
      results
    end

    def completed
      @agents.select { |a| a.status == :completed }
    end

    def failed
      @agents.reject { |a| a.status == :completed }
    end

    def total_budget_used
      @agents.sum(&:budget)
    end
  end

  # Firewall for agent input/output - blocks prompt injections and destructive operations
  class AgentFirewall
    Rule = Struct.new(:action, :direction, :pattern, :quick, :tag, keyword_init: true)

    DEFAULT_RULES = [
      # Block prompt injections in both directions
      Rule.new(action: :block, pattern: /ignore (?:all )?(?:previous|above|prior) instructions/i, quick: true),
      Rule.new(action: :block, pattern: /you are now/i, quick: true),
      Rule.new(action: :block, pattern: /new system prompt/i, quick: true),
      Rule.new(action: :block, pattern: /forget (?:everything|all|your)/i, quick: true),
      Rule.new(action: :block, pattern: /override (?:axiom|principle|rule)/i, quick: true),
      Rule.new(action: :block, pattern: /disregard (?:axiom|principle|rule|safety)/i, quick: true),
      # Block privilege escalation (inbound only)
      Rule.new(action: :pass, direction: :in, pattern: /\bdoas\b/, quick: false, tag: :needs_review),
      Rule.new(action: :block, direction: :in, pattern: /\bsudo\b/, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /\bsu\s+-?\s/, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /\bpfctl\s+-f\b/, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /\brcctl\s+restart\b/, quick: true),
      # Block destructive operations (inbound only)
      Rule.new(action: :block, direction: :in, pattern: /\brm\s+-rf?\s+\//, quick: true),
      Rule.new(action: :block, direction: :in, pattern: />\s*\/dev\/[sh]da/, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /DROP\s+TABLE/i, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /mkfs\./, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /dd\s+if=/, quick: true),
      # Pass with tag for review
      Rule.new(action: :pass, pattern: /escalation:/, quick: false, tag: :needs_review),
      # Default pass for clean content
      Rule.new(action: :pass, pattern: /.*/, quick: false),
    ].freeze

    MAX_OUTPUT_SIZE = 100_000

    class << self
      def evaluate(text, rules: DEFAULT_RULES, direction: :in)
        if text.length > MAX_OUTPUT_SIZE
          return { verdict: :block, reason: "Output too large: #{text.length} chars (max #{MAX_OUTPUT_SIZE})" }
        end

        rules.each do |rule|
          next if rule.direction && rule.direction != direction
          next unless text.match?(rule.pattern)

          return { verdict: :block, rule: rule, reason: "Blocked by rule: #{rule.pattern.source}" } if rule.action == :block
          return { verdict: :pass, tag: rule.tag } if rule.tag
          return { verdict: :pass } if rule.action == :pass
        end

        { verdict: :block, reason: "Default deny — no rule matched" }
      end

      def sanitize(agent_result, direction: :out)
        return Result.err("Agent returned error: #{agent_result.error}") if agent_result.err?

        output = agent_result.value
        text = output[:response] || output[:text] || output[:rendered] || ""

        verdict = evaluate(text, direction: direction)

        return Result.err("Agent output blocked: #{verdict[:reason]}") if verdict[:verdict] == :block

        clean_text = text.gsub(/```system.*?```/m, "[REDACTED SYSTEM BLOCK]")

        Result.ok(output.merge(text: clean_text, sanitized: true, firewall_tag: verdict[:tag]))
      end
    end
  end
end
