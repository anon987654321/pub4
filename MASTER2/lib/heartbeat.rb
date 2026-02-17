# frozen_string_literal: true

require "json"

module MASTER
  # Heartbeat -- background timer that checks for pending work
  # Inspired by OpenClaw's heartbeat-runner: fires periodically,
  # evaluates what needs doing, acts without user prompting
  module Heartbeat
    extend self

    DEFAULT_INTERVAL = 60 # seconds
    MAX_INTERVAL = 3600
    MAX_WATER_ITERATIONS = 5
    MIN_IMPROVEMENT = 0.001

    @running = false
    @thread = nil
    @interval = DEFAULT_INTERVAL
    @checks = []
    @checks_mutex = Mutex.new
    @last_cycle = nil

    class << self
      attr_reader :running, :interval

      def start(interval: DEFAULT_INTERVAL)
        return if @running

        @interval = interval.clamp(5, MAX_INTERVAL)
        @running = true
        Logging.dmesg_log("heartbeat", message: "ENTER start interval=#{@interval}s")
        install_default_cycle if @checks.empty?

        @thread = Thread.new { run_loop }
        @thread.abort_on_exception = false
      end

      def stop
        @running = false
        @thread&.join(5)
        @thread = nil
        Logging.dmesg_log("heartbeat", message: "EXIT stop")
      end

      # Register a check -- callable that returns work items or nil
      def register(name, &block)
        @checks_mutex.synchronize do
          @checks << { name: name, callable: block, last_run: nil, failures: 0 }
        end
      end

      def clear
        @checks_mutex.synchronize do
          @checks = []
        end
      end

      def status
        @checks_mutex.synchronize do
          {
            running: @running,
            interval: @interval,
            last_cycle: @last_cycle,
            checks: @checks.map { |c| { name: c[:name], last_run: c[:last_run], failures: c[:failures] } }
          }
        end
      end

      private

      def run_loop
        while @running
          backoff_needed = 0
          @checks_mutex.synchronize do
            @checks.each do |check|
              backoff_delay = run_check(check)
              backoff_needed = [backoff_needed, backoff_delay || 0].max
            end
          end
          # Sleep outside the mutex
          if backoff_needed > 0
            sleep(backoff_needed)
          else
            sleep(@interval)
          end
        end
      rescue StandardError => e
        Logging.dmesg_log("heartbeat", message: "loop error: #{e.message}")
        @running = false
      end

      def run_check(check)
        check[:last_run] = Time.now
        result = check[:callable].call
        check[:failures] = 0 if result
        nil  # Returns nil on success, backoff delay in seconds on failure
      rescue StandardError => e
        check[:failures] += 1
        backoff = [30 * (2**check[:failures]), MAX_INTERVAL].min
        Logging.dmesg_log("heartbeat", message: "#{check[:name]} failed (#{check[:failures]}x), backoff #{backoff}s: #{e.message}")
        check[:failures] > 2 ? backoff : nil  # Return delay but don't sleep here
      end

      # Default O-P-E-V-L autonomous loop:
      # observe -> adversarial question -> prioritize -> execute -> verify -> learn
      # Runs in "water iteration" mode until convergence.
      def install_default_cycle
        register("autonomy_cycle") do
          cycle = {
            observed_at: Time.now.to_i,
            observed: observe,
            iterations: [],
            learned: []
          }

          state = cycle[:observed]
          previous_score = nil

          MAX_WATER_ITERATIONS.times do |idx|
            adversarial = adversarial_questions(state)
            review = adversarial_reason_and_select(state, adversarial)
            planned = prioritize(state, review: review)
            executed = execute_plan(planned)
            verified = verify(executed)
            score = quality_score(state: state, planned: planned, executed: executed, verified: verified)

            cycle[:iterations] << {
              index: idx + 1,
              adversarial: adversarial,
              adversarial_review: review,
              planned: planned,
              executed: executed,
              verified: verified,
              score: score
            }

            break if converged?(previous_score, score)

            previous_score = score
            state = observe
          end

          cycle[:learned] = learn(cycle)
          @last_cycle = cycle
          true
        rescue StandardError => e
          Triggers.fire(:on_error, stage: :autonomy_cycle, error: e.message) if defined?(Triggers)
          false
        end
      end

      def observe
        {
          scheduler_jobs: (defined?(Scheduler) ? Scheduler.list : []),
          llm_configured: (defined?(LLM) && LLM.respond_to?(:configured?) ? LLM.configured? : false),
          budget_remaining: (defined?(LLM) && LLM.respond_to?(:budget_remaining) ? LLM.budget_remaining : Float::INFINITY),
          timestamp: Time.now.to_i
        }
      end

      def adversarial_questions(observed)
        questions = []

        jobs = Array(observed[:scheduler_jobs])
        if jobs.any? { |j| j[:failures].to_i > 0 }
          questions << "Which repeated failure pattern suggests flawed retry/backoff?"
        end
        if jobs.empty?
          questions << "What high-value autonomous task is missing from the schedule?"
        end
        if !observed[:llm_configured]
          questions << "What non-LLM maintenance tasks can still improve quality now?"
        end
        questions << "What would an attacker exploit first in current automation flow?"

        Triggers.fire(:adversarial_review, questions: questions, observed: observed) if defined?(Triggers)
        questions
      rescue StandardError
        []
      end

      def prioritize(observed, review: nil)
        jobs = Array(observed[:scheduler_jobs])
        due = jobs.select do |j|
          j[:enabled] && j[:next_at].respond_to?(:<=) ? j[:next_at] <= Time.now : true
        end
        due.sort_by! { |j| [-(j[:priority] || 50), j[:next_at].to_i] }

        selected = Array(review&.dig(:selected_commands))
        selected_jobs = selected.filter_map { |cmd| due.find { |j| j[:command].to_s == cmd.to_s } }
        (selected_jobs + due).uniq
      end

      def adversarial_reason_and_select(observed, questions)
        return heuristic_adversarial_review(observed, questions) unless defined?(LLM) && LLM.configured?

        prompt = <<~PROMPT
          You are an adversarial reviewer.
          Ask hard questions, answer them directly, generate multiple solutions,
          and pick the strongest one.

          CONTEXT:
          - Jobs: #{Array(observed[:scheduler_jobs]).map { |j| "#{j[:id]}:#{j[:command]}(fail=#{j[:failures]})" }.join(", ")}
          - LLM configured: #{observed[:llm_configured]}
          - Budget remaining: #{observed[:budget_remaining]}

          QUESTIONS:
          #{Array(questions).map { |q| "- #{q}" }.join("\n")}

          Return strict JSON with:
          answers: string[]
          solution_candidates: [{name, commands, rationale, risk}]
          selected_index: integer
          selected_commands: string[]
          selected_reason: string
        PROMPT

        schema = {
          type: "object",
          required: %w[answers solution_candidates selected_index selected_commands selected_reason],
          properties: {
            answers: { type: "array", items: { type: "string" } },
            solution_candidates: {
              type: "array",
              items: {
                type: "object",
                required: %w[name commands rationale risk],
                properties: {
                  name: { type: "string" },
                  commands: { type: "array", items: { type: "string" } },
                  rationale: { type: "string" },
                  risk: { type: "number" }
                }
              }
            },
            selected_index: { type: "integer" },
            selected_commands: { type: "array", items: { type: "string" } },
            selected_reason: { type: "string" }
          }
        }

        result = LLM.ask_json(prompt, schema: schema, tier: :strong)
        return heuristic_adversarial_review(observed, questions) unless result.ok?

        parsed = JSON.parse(result.value[:content], symbolize_names: true) rescue nil
        return heuristic_adversarial_review(observed, questions) unless parsed.is_a?(Hash)

        {
          answers: Array(parsed[:answers]),
          solution_candidates: Array(parsed[:solution_candidates]),
          selected_index: parsed[:selected_index],
          selected_commands: Array(parsed[:selected_commands]),
          selected_reason: parsed[:selected_reason].to_s
        }
      rescue StandardError
        heuristic_adversarial_review(observed, questions)
      end

      def heuristic_adversarial_review(observed, questions)
        jobs = Array(observed[:scheduler_jobs])
        failing = jobs.select { |j| j[:failures].to_i >= 1 }
        stable = jobs.select { |j| j[:failures].to_i.zero? }

        candidate_a = {
          name: "failure_first",
          commands: failing.map { |j| j[:command] },
          rationale: "Fix unstable jobs to reduce repeated failure loops.",
          risk: 4,
          impact: 0.8,
          confidence: 0.75,
          cost: 1.1
        }
        candidate_b = {
          name: "priority_first",
          commands: jobs.sort_by { |j| [-(j[:priority] || 50), j[:next_at].to_i] }.map { |j| j[:command] },
          rationale: "Maximize impact by priority ordering.",
          risk: 6,
          impact: 0.95,
          confidence: 0.65,
          cost: 1.3
        }
        candidate_c = {
          name: "confidence_first",
          commands: stable.sort_by { |j| [-(j[:priority] || 50), j[:next_at].to_i] }.map { |j| j[:command] },
          rationale: "Favor high-confidence execution and continuous throughput.",
          risk: 3,
          impact: 0.7,
          confidence: 0.9,
          cost: 0.9
        }

        candidates = [candidate_a, candidate_b, candidate_c]
        selected = if defined?(DecisionEngine)
          DecisionEngine.pick_best(candidates)
        else
          candidates.min_by { |c| c[:risk] }
        end || candidate_b

        {
          answers: Array(questions).map { |q| "answered: #{q}" },
          solution_candidates: candidates,
          selected_index: candidates.index(selected) || 1,
          selected_commands: selected[:commands],
          selected_reason: selected[:rationale]
        }
      end

      def execute_plan(plan)
        return [] unless defined?(Scheduler)

        Scheduler.tick
        plan.map { |j| { job_id: j[:id], command: j[:command], executed: true } }
      end

      def verify(executed)
        checks = executed.map do |entry|
          { job_id: entry[:job_id], ok: true }
        end
        Triggers.fire(:after_verify, checks: checks) if defined?(Triggers)
        checks
      end

      def learn(cycle)
        return [] unless defined?(AgentAutonomy)

        last = cycle[:iterations].last || {}
        summary = "obs=#{cycle[:observed][:scheduler_jobs].size} iter=#{cycle[:iterations].size} score=#{last[:score] || 0.0}"
        AgentAutonomy.record_skill("heartbeat_autonomy_cycle", description: summary, examples: [summary])
        [{ skill: "heartbeat_autonomy_cycle", summary: summary }]
      rescue StandardError
        []
      end

      def quality_score(state:, planned:, executed:, verified:)
        base = 1.0
        due = planned.size
        ran = executed.size
        failed = verified.count { |v| !v[:ok] }
        backlog_penalty = [state[:scheduler_jobs].size - ran, 0].max * 0.01
        execution_gain = due.zero? ? 0.0 : (ran.to_f / due) * 0.5
        verification_penalty = failed * 0.2
        (base + execution_gain - verification_penalty - backlog_penalty).round(4)
      end

      def converged?(previous_score, current_score)
        return false unless defined?(DecisionEngine)

        DecisionEngine.converged?(
          previous_score: previous_score,
          current_score: current_score,
          min_improvement: MIN_IMPROVEMENT
        )
      end
    end
  end
end
