# frozen_string_literal: true

module Master
  class Pipeline
    def initialize(stages)
      @stages = stages
    end

    # Run stages in sequence. Each stage's elapsed time is accumulated in
    # ctx[:_timings] (Hash of stage_name => ms).
    def call(initial)
      timings = {}
      @stages.reduce(initial) do |result, stage|
        result.and_then(stage_label(stage)) do |ctx|
          t0  = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          res = stage.call(ctx)
          ms  = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
          timings[stage_label(stage)] = ms
          res.respond_to?(:ok?) && res.ok? ? Result.ok(res.value!.merge(_timings: timings.dup)) : res
        end
      end
    end

    # Group of stages that run concurrently and merge their ctx contributions.
    # Non-conflicting keys are additive; conflicting keys: last-writer wins by
    # stage order. Errors in individual stages are non-fatal — they are
    # attached as `ctx[:_parallel_errors]` and execution continues.
    class ParallelGroup
      TIMEOUT_S = 30

      def initialize(*stages)
        @stages = stages
      end

      def call(ctx)
        frozen_ctx = ctx.freeze
        threads    = @stages.map { |s| Thread.new { s.call(frozen_ctx) } }

        results = threads.each_with_index.map do |t, i|
          if t.join(TIMEOUT_S)
            t.value
          else
            t.kill rescue nil
            Result.ok(frozen_ctx.merge(_parallel_timeout: @stages[i].class.name))
          end
        end

        errors  = results.filter_map { |r| r.respond_to?(:err?) && r.err? ? r.message : nil }
        merged  = results.reduce(ctx) { |acc, r| r.respond_to?(:ok?) && r.ok? ? acc.merge(r.value!) : acc }
        merged  = merged.merge(_parallel_errors: errors) unless errors.empty?

        Result.ok(merged)
      rescue => e
        Result.ok(ctx.merge(_parallel_errors: [e.message]))
      end
    end

    private

    def stage_label(stage)
      stage.class.name.split("::").last
    end
  end
end
