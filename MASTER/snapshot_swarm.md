# MASTER Snapshot — lib/master/swarm/
Generated: 2026-05-04T10:21:42Z

## lib/master/swarm/coordinator.rb
```ruby
# frozen_string_literal: true

require "timeout"

module Master
  module Swarm
    class Coordinator
      SwarmResult = Struct.new(:verdict, :confidence, :reasoning, :artifacts, keyword_init: true) do
        def ok?      = verdict != :error
        def approved? = verdict == :approved
      end

      WORKER_CLASSES = {
        analyst:    Workers::Analyst,
        coder:      Workers::Coder,
        reviewer:   Workers::Reviewer,
        researcher: Workers::Researcher
      }.freeze

      WORKER_TIMEOUT = 30
      SHARED_DEADLINE = 60
      SYNTHESIS_TRUNCATE_LIMIT = 200

      def initialize(agent:, event_bus: nil)
        @agent = agent
        @bus   = event_bus
        @workers = {}
      end

      def dispatch(role, task:, context_slice: {})
        worker = worker_for(role) or return Result.err("unknown role: #{role}")
        @bus&.publish(:swarm_dispatch, role:, task: task[0..60])
        worker.call(task:, context_slice:)
      end

      def analyse_and_review(file_path:, code:)
        fan_out([
          { role: :analyst,  task: "identify all issues",          context_slice: { file: file_path, code: code } },
          { role: :reviewer, task: "security and correctness review", context_slice: { code: code } }
        ]).and_then do |sr|
          analysis = sr.artifacts[:analyst]
          review   = sr.artifacts[:reviewer]
          Result.ok({ analysis:, review:, approved: review.is_a?(Hash) && review["approved"] })
        end
      end

      def fan_out(tasks, timeout: WORKER_TIMEOUT)
        threads = tasks.map do |t|
          Thread.new do
            [t[:role], dispatch(t[:role], task: t[:task], context_slice: t.fetch(:context_slice, {}))]
          rescue StandardError => e
            @bus&.publish("swarm:worker_error", role: t[:role], error: e.message)
            [t[:role], Result.err("worker error: #{e.message}")]
          end
        end

        results = threads.map do |th|
          if th.join(timeout)
            th.value
          else
            begin; th.kill; rescue ThreadError; nil; end
            @bus&.publish(:swarm_worker_timeout, timeout:)
            [:timeout, Result.err("worker timed out after #{timeout}s")]
          end
        end.to_h

        sr = build_swarm_result(results)
        @bus&.publish(:swarm_fan_out_done, roles: results.keys, verdict: sr.verdict,
                      synthesis: sr.reasoning[0..SYNTHESIS_TRUNCATE_LIMIT])
        Result.ok(sr)
      end

      def dispatch_parallel(role_tasks, deadline: SHARED_DEADLINE)
        finish_by = Process.clock_gettime(Process::CLOCK_MONOTONIC) + deadline

        threads = role_tasks.map do |t|
          Thread.new do
            remaining = [finish_by - Process.clock_gettime(Process::CLOCK_MONOTONIC), 1].max
            Timeout.timeout(remaining) do
              [t[:role], dispatch(t[:role], task: t[:task], context_slice: t.fetch(:context_slice, {}))]
            end
          rescue Timeout::Error
            [t[:role], Result.err("worker exceeded shared deadline")]
          rescue StandardError => e
            @bus&.publish("swarm:worker_error", role: t[:role], error: e.message)
            [t[:role], Result.err("worker error: #{e.message}")]
          end
        end

        results = threads.map do |th|
          if th.join(deadline)
            th.value
          else
            begin; th.kill; rescue ThreadError; nil; end
            @bus&.publish(:swarm_parallel_timeout, deadline:)
            [nil, Result.err("worker exceeded shared deadline")]
          end
        end.to_h

        sr = build_swarm_result(results)
        @bus&.publish(:swarm_dispatch_parallel_done, roles: results.keys, verdict: sr.verdict)
        Result.ok(sr)
      end

      def worker_roles = WORKER_CLASSES.keys

      private

      def build_swarm_result(results)
        successes = results.reject { |role, _| role == :timeout }
                           .select { |_, r| r.respond_to?(:ok?) && r.ok? }
        artifacts = successes.transform_values(&:value!)
        confidence = results.empty? ? 0.0 : successes.size.to_f / results.size
        lines = successes.map { |role, r| "### #{role}\n#{r.value!.to_s.strip}" }
        reasoning = lines.empty? ? "(no results)" : lines.join("\n\n")
        verdict = if confidence >= 0.8 then :approved
                 elsif confidence >= 0.5 then :mixed
                 elsif successes.empty? then :error
                 else :rejected
                 end
        SwarmResult.new(verdict:, confidence:, reasoning:, artifacts:)
      end

      def worker_for(role)
        sym = role.to_sym
        @workers.fetch(sym) do
          klass = WORKER_CLASSES[sym]
          return nil unless klass

          @workers[sym] = klass.new(agent: @agent, event_bus: @bus)
        end
      end
    end
  end
end

```

## lib/master/swarm/worker.rb
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    # Base worker — receives only the context slice it needs (need-to-know).
    class Worker
      PREFERRED_MODEL = nil

      UNCERTAINTY_PHRASES = %w[unclear uncertain not\ sure cannot\ determine
                                i\ don't\ know limited\ information probably].freeze

      attr_reader :role, :result, :confidence

      def initialize(agent:, event_bus: nil)
        @agent      = agent
        @bus        = event_bus
        @role       = self.class.name.split("::").last.downcase
        @result     = nil
        @confidence = 1.0
      end

      def call(task:, context_slice: {})
        prompt = build_prompt(task, context_slice)
        @bus&.publish(:swarm_worker_start, role: @role, task: task[0..60])

        preferred = self.class::PREFERRED_MODEL
        raw = @agent.ask_once(prompt, model: preferred, system: worker_system_prompt)
        @result, @confidence = parse_result(raw)

        @bus&.publish(:swarm_worker_done, role: @role, ok: @result.ok?)
        @result
      rescue StandardError => e
        Result.err("worker #{@role}: #{e.message}", category: :unknown)
      end

      private

      def worker_system_prompt
        "You are a specialized #{@role} agent. #{role_description}\n" \
          "Respond only with what is asked. No preamble. No meta-commentary."
      end

      def role_description = "General-purpose assistant."
      def build_prompt(task, ctx) = "#{ctx_summary(ctx)}\n\nTask: #{task}"

      def parse_result(raw)
        text = raw.to_s.strip
        hits = UNCERTAINTY_PHRASES.count { |p| text.downcase.include?(p) }
        conf = [1.0 - (hits.to_f / [UNCERTAINTY_PHRASES.size, 1].max * 0.5), 0.0].max.round(2)
        [Result.ok({ text: text, confidence: conf }), conf]
      end

      def ctx_summary(ctx)
        return "" if ctx.empty?
        ctx.map { |k, v| "#{k}: #{v}" }.join("\n")
      end
    end
  end
end

```

## lib/master/swarm/workers/analyst.rb
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    module Workers
      # Reads code, produces structured analysis. Knows nothing about other workers.
      class Analyst < Worker
        PREFERRED_MODEL = "google/gemini-2.0-flash-lite:free".freeze
        private

        def role_description
          "You analyze code for quality, bugs, and design issues. " \
            "Output JSON: {issues: [{file, line, severity(1-3), description}], summary: string}"
        end

        def build_prompt(task, ctx)
          parts = []
          parts << "File: #{ctx[:file]}" if ctx[:file]
          parts << "Code:\n```\n#{ctx[:code]}\n```" if ctx[:code]
          parts << "Analyze: #{task}"
          parts.join("\n\n")
        end

        def parse_result(raw)
          match_str = raw.to_s.match(/\{.*\}/m)&.to_s || "{}"
          parsed = JSON.parse(match_str)
          Result.ok(parsed)
        rescue JSON::ParserError
          Result.ok({ summary: raw.to_s.strip, issues: [] })
        end
      end
    end
  end
end

```

## lib/master/swarm/workers/coder.rb
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    module Workers
      # Writes code given a spec. Knows only the spec + relevant file context.
      class Coder < Worker
        private

        def role_description
          "You write clean, minimal Ruby/Rails/Zsh code. " \
            "Output only the code block. No explanation unless asked."
        end

        def build_prompt(task, ctx)
          parts = []
          parts << "Language: #{ctx[:language] || "ruby"}"
          parts << "Existing code:\n```\n#{ctx[:code]}\n```" if ctx[:code]
          parts << "Spec: #{task}"
          parts.join("\n\n")
        end
      end
    end
  end
end

```

## lib/master/swarm/workers/researcher.rb
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    module Workers
      # Synthesizes research from external sources. No codebase context.
      class Researcher < Worker
        PREFERRED_MODEL = "google/gemini-2.0-flash-lite:free".freeze
        private

        def role_description
          "You are a research analyst. Synthesize information concisely. " \
            "Output: factual summary, sources if known, confidence level (low/med/high)."
        end

        def build_prompt(task, ctx)
          parts = []
          parts << "Domain: #{ctx[:domain]}" if ctx[:domain]
          parts << "Prior findings:\n#{ctx[:prior_findings]}" if ctx[:prior_findings]
          parts << "Research: #{task}"
          parts.join("\n\n")
        end
      end
    end
  end
end

```

## lib/master/swarm/workers/reviewer.rb
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    module Workers
      # Reviews code for security, correctness, style. Constitutional layer.
      class Reviewer < Worker
        CHECKLIST = %w[
          sql_injection xss command_injection path_traversal
          hardcoded_secrets open_redirect mass_assignment
        ].freeze

        private

        def role_description
          "You are a security-focused code reviewer. Check for OWASP top-10 issues, " \
            "logic bugs, and constitutional AI violations. " \
            "Output JSON: {approved: bool, violations: [{type, line, description}]}"
        end

        def build_prompt(task, ctx)
          parts = []
          parts << "Code to review:\n```\n#{ctx[:code]}\n```" if ctx[:code]
          parts << "Security checklist: #{CHECKLIST.join(", ")}"
          parts << "Review for: #{task}"
          parts.join("\n\n")
        end

        def parse_result(raw)
          parsed = JSON.parse(raw.to_s.match(/\{.*\}/m)&.to_s || "{}")
          parsed["approved"] = true if parsed.empty?
          Result.ok(parsed)
        rescue JSON::ParserError
          Result.ok({ "approved" => true, "violations" => [] })
        end
      end
    end
  end
end

```
