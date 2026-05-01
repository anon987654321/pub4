# frozen_string_literal: true

require "open3"

module Master
  class Pipeline
    ROLLBACK_CATEGORIES   = %i[validation axiom_violation].freeze
    MS_PER_SECOND         = 1000
    ROLLBACK_MSG_TRUNCATE = 120

    attr_reader :last_timings

    def initialize(stages, bus: nil, trace: false, root: nil, event_bus: nil)
      @stages = stages
      @last_timings = {}
      @bus   = bus || event_bus
      @trace = trace
      @root  = root
    end

    def call(initial)
      timings = {}
      @stages.reduce(initial) do |result, stage|
        result.and_then(stage_label(stage)) do |ctx|
          t0     = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          stage_result = stage.call(ctx)
          ms     = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * MS_PER_SECOND).round
          timings[stage_label(stage)] = ms
          if stage_result.respond_to?(:ok?) && stage_result.ok?
            @last_timings = timings.dup
            @bus&.publish("pipeline:stage", stage: stage_label(stage), ms:) if @trace
            Result.ok(stage_result.value!.merge(_timings: timings.dup))
          else
            stage_result
          end
        end
      end.tap { |final| maybe_rollback(final) }
    end

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
            begin; t.kill; rescue StandardError; nil; end
            Result.ok(frozen_ctx.merge(_parallel_timeout: @stages[i].class.name))
          end
        end

        errors = results.filter_map { |r| r.respond_to?(:err?) && r.err? ? r.message : nil }
        merged = results.reduce(ctx) { |acc, r| r.respond_to?(:ok?) && r.ok? ? acc.merge(r.value!) : acc }
        merged = merged.merge(_parallel_errors: errors) unless errors.empty?

        Result.ok(merged)
      rescue StandardError => e
        Result.ok(ctx.merge(_parallel_errors: [e.message]))
      end
    end

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

      @bus&.publish("pipeline:rollback", category: result.category, message: result.message[0, ROLLBACK_MSG_TRUNCATE])
      Open3.capture2e("git", "-C", @root, "reset", "--hard", "HEAD")
    end

    def git_workspace?
      @root && Dir.exist?(File.join(@root, ".git"))
    end

    def dirty?
      out, _, st = Open3.capture3("git", "-C", @root, "status", "--porcelain")
      st.success? && !out.strip.empty?
    end

    def stage_label(stage)
      stage.class.name.split("::").last
    end
  end
end
