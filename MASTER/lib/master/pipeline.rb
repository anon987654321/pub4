# frozen_string_literal: true

module Master
  # Pipeline — Result-monadic stage chain.
  #
  # Adds lightweight rollback: if a stage raises a dangerous error category
  # AND a git-backed workspace exists, reset the working tree before
  # returning the error. Safe for non-git contexts (Sweep, tests) via the
  # dirty? check.
  class Pipeline
    ROLLBACK_CATEGORIES = %i[validation axiom_violation].freeze

    attr_reader :last_timings

    def initialize(stages, bus: nil, trace: false, root: nil, event_bus: nil)
      @stages = stages
      @last_timings = {}
      @bus   = bus || event_bus
      @trace = trace
      @root  = root
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
          if res.respond_to?(:ok?) && res.ok?
            @last_timings = timings.dup
            @bus&.publish("pipeline:stage", stage: stage_label(stage), ms:) if @trace
            Result.ok(res.value!.merge(_timings: timings.dup))
          else
            res
          end
        end
      end.tap { |final| maybe_rollback(final) }
    end

    # Group of stages that run concurrently and merge their ctx contributions.
    # Non-conflicting keys are additive; conflicting keys: last-writer wins by
    # stage order. Errors in individual stages are non-fatal — they are
    # attached as `ctx[:_parallel_errors]` and execution continues.
    class ParallelGroup
      PARALLEL_TIMEOUT_S = 30

      def initialize(*stages)
        @stages = stages
      end

      def call(ctx)
        frozen_ctx = ctx.freeze
        threads    = @stages.map { |s| Thread.new { s.call(frozen_ctx) } }

        results = threads.each_with_index.map do |t, i|
          if t.join(PARALLEL_TIMEOUT_S)
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
      rescue StandardError => e
        Result.ok(ctx.merge(_parallel_errors: [e.message]))
      end
    end


# Wraps a stage -- skips it transparently when ctx[:pressure] is truthy.
class SkipOnPressure
  def initialize(stage) = @stage = stage
  def call(ctx) = ctx[:pressure] ? Result.ok(ctx) : @stage.call(ctx)
end

    private

    def maybe_rollback(result)
      return unless result.respond_to?(:err?) && result.err?
      return unless ROLLBACK_CATEGORIES.include?(result.category)
      return unless @root && git_workspace?
      return unless dirty?

      @bus&.publish("pipeline:rollback", category: result.category, message: result.message[0, 120])
      system("git -C #{@root} reset --hard HEAD", out: File::NULL, err: File::NULL)
    end

    def git_workspace?
      @root && Dir.exist?(File.join(@root, ".git"))
    end

    def dirty?
      out = `git -C #{@root} status --porcelain 2>/dev/null`
      !out.to_s.strip.empty?
    end

    def stage_label(stage)
      stage.class.name.split("::").last
    end
  end
end
