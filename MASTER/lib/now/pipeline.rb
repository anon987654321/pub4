# frozen_string_literal: true

require_relative "../loop/rollback"

module Master
  module Now
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
        @rollback     = root ? Master::Loop::Rollback.new(root:, bus: @bus) : nil
      end

      def call(initial)
        wf_id   = "pipeline-#{Process.pid}-#{Time.now.to_i}"
        timings = {}
        @orchestrator&.execute(intent_type: :llm_call, workflow_id: wf_id, payload: { stage: "start" }) { nil }
        # Wrap plain Hash into typed PipelineContext at the pipeline boundary.
        wrapped = initial.map { |h| PipelineContext.wrap(h) }
        gated = wrapped.and_then("deploy_gate") { |ctx| deploy_gate(ctx) }
        final = @stages.reduce(gated) do |result, stage|
          result.and_then(stage_label(stage)) { |ctx| run_stage(stage, ctx, timings) }
        end
        @orchestrator&.checkpoint(workflow_id: wf_id, label: final.ok? ? "ok" : "err")
        @orchestrator&.rotate!(keep_last: 1000)
        @last_timings = timings
        @bus&.publish("pipeline:complete", timings:, ok: final.ok?)
        maybe_rollback(final)
        final
      end

      class ParallelGroup
        PARALLEL_TIMEOUT_S = 30

        def initialize(*stages, bus: nil)
          @stages = stages
          @bus    = bus
        end

        def call(ctx)
          frozen  = ctx.freeze
          threads = spawn_stage_threads(frozen)
          results = collect_results(threads, frozen)
          Result.ok(merge_results(ctx, results))
        rescue StandardError => e
          Result.ok(ctx.merge(_parallel_errors: [e.message]))
        end

        private

        def spawn_stage_threads(frozen)
          @stages.map do |stage|
            Thread.new do
              stage.call(frozen)
            rescue StandardError => e
              @bus&.publish("pipeline:stage_error", stage: stage.class.name, error: e.message)
              Result.ok(frozen.merge(_stage_error: e.message))
            end
          end
        end

        def collect_results(threads, frozen)
          threads.each_with_index.map do |thread, i|
            next thread.value if thread.join(PARALLEL_TIMEOUT_S)
            handle_timeout(thread, @stages[i], frozen)
          end
        end

        def handle_timeout(thread, stage, frozen)
          thread.kill
          @bus&.publish("pipeline:stage_timeout", stage: stage.class.name)
          Result.ok(frozen.merge(_parallel_timeout: stage.class.name))
        rescue ThreadError => e
          Master::Ground::Swallow.log(e, context: "Pipeline::ParallelGroup.handle_timeout")
          Result.ok(frozen.merge(_parallel_timeout: stage.class.name))
        end

        def merge_results(ctx, results)
          merged = results.filter_map { |r| r.value! if r.ok? }.reduce(ctx, &:merge)
          errors = results.filter_map { |r| r.message if r.err? }
          errors.empty? ? merged : merged.merge(_parallel_errors: errors)
        end
      end

      class SkipOnPressure
        def initialize(stage, bus: nil)
          @stage = stage
          @bus   = bus
        end

        def call(ctx)
          return @stage.call(ctx) unless ctx.pressure
          label = pressure_label
          @bus&.publish("pipeline:skipped", stage: label, reason: "pressure")
          $stdout.puts "pipeline: skipped #{label} (pressure)"
          $stdout.flush
          Result.ok(ctx)
        end

        private

        def pressure_label
          stage_class = @stage.class.name
          short_name  = stage_class.split("::").last
          return short_name unless @stage.respond_to?(:stages)
          names = @stage.stages.map { |s| s.class.name.split("::").last }.join(",")
          "parallel[#{names}]"
        end
      end

      private

      DEPLOY_RE = /\b(deploy|ship|shipping|release|publish)\b/i
      TIER1_CRITICAL_RULE_IDS = %w[PRESERVE_FIRST DECOUPLE DEGRADE_GRACEFULLY].freeze

      def deploy_gate(ctx)
        return Result.ok(ctx) unless deploy_intent?(ctx)
        return Result.ok(ctx) unless @scanner && @root

        result = Master::Judge::Scan::SelfScan.new(scanner: @scanner, root: @root, event_bus: @bus).call(autofix: true)
        return Result.err(result.message, category: :infrastructure) unless result.ok?

        summary = result.value!
        score = evidence_score(summary, ctx)
        @bus&.publish("pipeline:evidence_score", score:, threshold: evidence_threshold, violations: summary.violation_count)

        tier1_violations = tier1_critical_violations(summary)
        unless tier1_violations.empty?
          @bus&.publish("pipeline:blocked", gate: "tier1_critical", violations: tier1_violations.size, score:)
          err = Result.err("deploy blocked: tier1 critical violation(s): #{tier1_violations.uniq.join(", ")}",
                           category: :policy,
                           context: { file: "now/pipeline.rb", method: "deploy_gate", attempted: "tier1_halt" })
          @rollback&.call(err)
          return err
        end

        if summary.violation_count.positive?
          @bus&.publish("pipeline:blocked", gate: "self_scan", violations: summary.violation_count, score:)
          return Result.err("deploy blocked: self-scan has #{summary.violation_count} violation(s)", category: :policy)
        end

        return Result.ok(ctx) if score >= evidence_threshold

        @bus&.publish("pipeline:blocked", gate: "evidence_score", violations: 0, score:)
        Result.err("deploy blocked: evidence score #{score} below #{evidence_threshold}", category: :policy)
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

      def evidence_config
        @evidence_config ||= Master.load_yaml(File.join(@root || Master::ROOT, "data", "rules.yml"))
                                   .fetch("evidence_scoring", {})
      rescue StandardError
        {}
      end

      def run_stage(stage, ctx, timings)
        label = stage_label(stage)
        Master::Now::PipelineContext.assert_stage!(ctx, label.downcase.to_sym)

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
