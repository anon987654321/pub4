# frozen_string_literal: true

require_relative "../fix/rollback"
require "etc"

module Master
  module CLI
    class Pipeline
      MS_PER_SECOND = 1000

      attr_reader :last_timings

      def initialize(stages, bus: nil, trace: false, root: nil, event_bus: nil, orchestrator: nil, scanner: nil)
        @stages       = stages
        @last_timings = {}
        @bus          = bus || event_bus
        @trace        = trace
        @root         = root
        @orchestrator = orchestrator
        @scanner      = scanner
        @rollback     = root ? Master::Fix::Rollback.new(root:, bus: @bus) : nil
      end

      def call(initial)
        wf_id   = "pipeline-#{Process.pid}-#{Time.now.to_i}"
        timings = {}
        @orchestrator&.execute(intent_type: :llm_call, workflow_id: wf_id, payload: { stage: "start" }) { nil }
        wrapped = initial_context_result(initial)
        gated = wrapped.and_then("deploy_gate") { |ctx| deploy_gate(ctx) }
        final = @stages.reduce(gated) do |result, stage|
          result.and_then(stage_label(stage)) { |ctx| run_stage(stage:, ctx:, timings:) }
        end
        publish_complete(final, timings)
        @orchestrator&.checkpoint(workflow_id: wf_id, label: final.ok? ? "ok" : "err")
        @orchestrator&.rotate!(keep_last: 1000)
        maybe_rollback(final)
        final
      end

      class ParallelGroup
        PARALLEL_TIMEOUT_S = 30
        POOL_SIZE = [Etc.nprocessors, 8].min.freeze

        def initialize(*stages, bus: nil)
          @stages = stages
          @bus    = bus
        end

        def call(ctx)
          frozen  = ctx.freeze
          results = run_stage_pool(frozen)
          Result.ok(merge_results(ctx, results))
        rescue StandardError => e
          Result.ok(ctx.merge(_parallel_errors: [e.message]))
        end

        private

        def run_stage_pool(frozen)
          jobs = Queue.new
          @stages.each_with_index { |stage, index| jobs << [stage, index] }
          results = Array.new(@stages.size)
          workers = Array.new([@stages.size, POOL_SIZE].min) do
            Thread.new do
              while (job = next_job(jobs))
                stage, index = job
                results[index] = run_parallel_stage(stage, frozen)
              end
            end
          end
          collect_pool_results(workers, results, frozen)
        end

        def next_job(jobs)
          jobs.pop(true)
        rescue ThreadError => e
          Master::Ground::Swallow.log(e, context: "ParallelGroup.next_job")
          nil
        end

        def run_parallel_stage(stage, frozen)
          stage.call(frozen)
        rescue StandardError => e
          @bus&.publish("pipeline:stage_error", stage: stage.class.name, error: e.message)
          Result.ok(frozen.merge(_stage_error: e.message))
        end

        def collect_pool_results(workers, results, frozen)
          deadline = Time.now + PARALLEL_TIMEOUT_S
          workers.each do |worker|
            remaining = [deadline - Time.now, 0].max
            if worker.join(remaining)
              Thread.current[:vector_clock] = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
            elsif worker.alive?
              worker.kill
              @bus&.publish("pipeline:stage_timeout", stage: "parallel")
            end
          end
          results.each_with_index.map do |result, index|
            result || Result.ok(frozen.merge(_parallel_timeout: @stages[index].class.name))
          end
        end

        def merge_results(ctx, results)
          merged = ctx
          errors = []
          results.each do |result|
            if result.ok?
              merged = merged.merge(result.value!)
            else
              errors << result.message
            end
          end
          errors.empty? ? merged : merged.merge(_parallel_errors: errors)
        end
      end

      private

      DEPLOY_RE = /\b(deploy|ship|shipping|release|publish)\b/i
      TIER1_CRITICAL_RULE_IDS = %w[PRESERVE_FIRST DECOUPLE DEGRADE_GRACEFULLY].freeze

      def initial_context_result(initial)
        return Result.ok(initial) if initial.is_a?(PipelineContext)

        Result.wrap(initial).map { |h| PipelineContext.wrap(h) }
      end

      def deploy_gate(ctx)
        return Result.ok(ctx) unless deploy_intent?(ctx)
        return Result.ok(ctx) unless @scanner && @root

        result = Master::Review::Scan::SelfScan.new(scanner: @scanner, root: @root, event_bus: @bus).call(autofix: true)
        return Result.err(result.message, category: :infrastructure) unless result.ok?

        summary = result.value!
        score = evidence_score(summary, ctx)
        @bus&.publish("pipeline:evidence_score", score:, threshold: evidence_threshold, violations: summary.violation_count)

        blocked = check_violation_gates(summary, score)
        return blocked if blocked

        propose_rollback_if_below_block_threshold(score)

        return Result.ok(ctx) if score >= evidence_threshold

        @bus&.publish("pipeline:blocked", gate: "evidence_score", violations: 0, score:)
        Result.err("deploy blocked: evidence score #{score} below #{evidence_threshold}", category: :policy)
      end

      def check_violation_gates(summary, score)
        tier1_violations = tier1_critical_violations(summary)
        unless tier1_violations.empty?
          @bus&.publish("pipeline:blocked", gate: "tier1_critical", violations: tier1_violations.size, score:)
          return Result.err("deploy blocked: tier1 critical violation(s): #{tier1_violations.uniq.join(", ")}",
                            category: :policy)
        end

        if summary.violation_count.positive?
          @bus&.publish("pipeline:blocked", gate: "self_scan", violations: summary.violation_count, score:)
          return Result.err("deploy blocked: self-scan has #{summary.violation_count} violation(s)", category: :policy)
        end

        nil
      end

      def propose_rollback_if_below_block_threshold(score)
        block_threshold = evidence_block_threshold
        return unless score < block_threshold

        @bus&.publish("pipeline:rollback_proposed", gate: "evidence_block", score:, threshold: block_threshold)
        @rollback&.call(Result.err("evidence score #{score} below block threshold #{block_threshold}", category: :policy))
      end

      def deploy_intent?(ctx)
        [ctx[:user_message], ctx[:message], ctx[:command], ctx[:task_type]].compact.any? { |value| value.to_s.match?(DEPLOY_RE) }
      end

      def tier1_critical_violations(summary)
        summary.pairs.flat_map do |(_path, result)|
          next [] unless result.ok?
          result.value!.filter_map do |finding|
            rule_id = finding.respond_to?(:rule_id) ? finding.rule_id : finding[:rule_id] || finding[:rule]
            rule_id.to_s if TIER1_CRITICAL_RULE_IDS.include?(rule_id.to_s)
          end
        end
      end

      def evidence_score(summary, ctx)
        weights = evidence_weights
        evidence = ctx[:metadata].is_a?(Hash) ? (ctx[:metadata][:evidence] || ctx[:metadata]["evidence"] || {}) : {}
        score = summary.violation_count.zero? ? weights.fetch("scan_clean", 0).to_i : 0
        evidence.each do |key, value|
          score += weights.fetch(key.to_s, 0).to_i if value
        end
        score
      end

      def evidence_weights
        evidence_config.fetch("weights", {})
      end

      def evidence_threshold
        evidence_config.fetch("pass_threshold", 80).to_i
      end

      def evidence_block_threshold
        evidence_config.fetch("block_threshold", 50).to_i
      end

      def evidence_config
        @evidence_config ||= Master.load_yaml(File.join(@root || Master::ROOT, "data", "rules.yml"))
                                   .fetch("evidence_scoring", {})
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Pipeline.evidence_config")
        {}
      end

      def run_stage(stage:, ctx:, timings:)
        label = stage_label(stage)
        Master::CLI::PipelineContext.assert_stage!(ctx, label.downcase.to_sym)

        @bus&.publish("pipeline:stage_start", stage: label, pressure: !!ctx.pressure)

        t0    = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        stage_result = stage.call(ctx)
        ms    = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * MS_PER_SECOND).round
        timings[label] = ms
        return stage_result if stage_result.err?

        @last_timings = timings.dup
        @bus&.publish("pipeline:stage_complete", stage: label, ms:, success: true)
        stage_result.map { |c| c.merge(_timings: timings.dup) }
      end

      def publish_complete(result, timings)
        @last_timings = timings.dup
        @bus&.publish("pipeline:complete",
          success: result.ok?,
          timings: timings.dup,
          stages: timings.keys,
          error: result.err? ? result.message : nil)
      end

      def maybe_rollback(result)
        @rollback&.call(result)
      end

      def stage_label(stage)
        qualified = stage.class.name
        qualified.split("::").last
      end
    end
  end
end
