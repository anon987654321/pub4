# frozen_string_literal: true

require "open3"

module Master
  module Now
    class Pipeline
      ROLLBACK_CATEGORIES = %i[validation axiom_violation unknown provider_error llm_call_failure].freeze
      MS_PER_SECOND = 1000
      ROLLBACK_MSG_TRUNCATE = 120

      attr_reader :last_timings

      def initialize(stages, bus: nil, trace: false, root: nil, event_bus: nil, orchestrator: nil, scanner: nil)
        @stages       = stages
        @last_timings = {}
        @bus          = bus || event_bus
        @trace        = trace
        @root         = root
        @orchestrator = orchestrator
        @scanner      = scanner
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

      def deploy_gate(ctx)
        return Result.ok(ctx) unless deploy_intent?(ctx)
        return Result.ok(ctx) unless @scanner && @root

        result = Master::Judge::Scan::SelfScan.new(scanner: @scanner, root: @root, event_bus: @bus).call(autofix: true)
        return Result.err(result.message, category: :infrastructure) unless result.ok?

        summary = result.value!
        return Result.ok(ctx) if summary.violation_count.zero?

        @bus&.publish("pipeline:blocked", gate: "self_scan", violations: summary.violation_count)
        Result.err("deploy blocked: self-scan has #{summary.violation_count} violation(s)", category: :policy)
      end

      def deploy_intent?(ctx)
        [ctx[:user_message], ctx[:message], ctx[:command], ctx[:task_type]].compact.any? { |value| value.to_s.match?(DEPLOY_RE) }
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
        return unless rollback_eligible?(result)

        category = result.category
        tag = "master:rollback:#{category}:#{Process.pid}"
        @bus&.publish("pipeline:rollback", category:, message: result.message[0, ROLLBACK_MSG_TRUNCATE], tag:)
        Open3.capture2e("git", "-C", @root, "stash", "push", "-u", "-m", tag)
        Open3.capture2e("git", "-C", @root, "reset", "--hard", "HEAD")
      end

      def rollback_eligible?(result)
        return false unless result.is_a?(Master::Result::Err)
        return false unless ROLLBACK_CATEGORIES.include?(result.category)
        @root && git_workspace? && dirty?
      end

      def git_workspace?
        @root && Dir.exist?(File.join(@root, ".git"))
      end

      def dirty?
        out, _, st = Open3.capture3("git", "-C", @root, "status", "--porcelain")
        st.success? && !out.strip.empty?
      end

      def stage_label(stage)
        qualified = stage.class.name
        qualified.split("::").last
      end
    end
  end
end
