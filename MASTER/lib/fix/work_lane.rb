# frozen_string_literal: true

module Master
  module Fix
    # Which half of /fix a run does (not a model lane, Io::LaneSelection). A RAILS run once
    # rendered, researched and mapped for fifty minutes before a one-line RuboCop repair.
    module WorkLane
      # code (default): code laws only, no claim about anything rendered. visual (RAILS only): one
      # sweep grouped by cause, mechanical fixers first. all: both, as /fix ran before lanes.
      NAMES = %i[code visual all].freeze
      DEFAULT = :code

      # The stages a lane may start. A stage absent from a lane's row is skipped and
      # named in the run's summary, so a code run never reads as visual proof.
      STAGES = {
        research: "research0 web research", architecture: "architecture exploration",
        layout_sweep: "layout sweep", browser_checks: "browser checks",
        visual_pass: "rendered visual review", code_passes: "code-law repair passes",
        visual_groups: "grouped visual repair"
      }.freeze

      RUNS = {
        code: %i[code_passes],
        visual: %i[layout_sweep browser_checks visual_groups],
        all: %i[research architecture layout_sweep browser_checks visual_pass code_passes],
      }.freeze

      @current = DEFAULT
      @lock = Mutex.new

      module_function

      def current = @lock.synchronize { @current }

      def set!(name) = @lock.synchronize { @current = parse(name) }

      def restore(name) = @lock.synchronize { @current = name }

      def parse(name)
        lane = name.to_s.strip.downcase.to_sym
        return lane if NAMES.include?(lane)

        raise ArgumentError, "unknown lane #{name.inspect}; one of #{NAMES.join(", ")}"
      end

      def runs?(stage, lane = current) = RUNS.fetch(lane).include?(stage)

      def skipped(lane = current) = (STAGES.keys - RUNS.fetch(lane)).map { |stage| STAGES.fetch(stage) }

      def visual?(lane = current) = lane == :visual

      # The visual lane measures the RAILS apps; every other tree has nothing to render.
      def refusal(target, lane = current)
        return unless visual?(lane)

        relative = target.to_s.sub(%r{\A.*?(?=RAILS(?:/|\z))}, "")
        return if relative == "RAILS" || relative.start_with?("RAILS/")

        "--lane visual renders the RAILS apps; #{target} has no rendered surface"
      end

      # The child check runner reads this: CHECK_LANE=code leaves its browser checks out.
      def check_env(lane = current) = { "CHECK_LANE" => lane.to_s }

      def summary(lane = current)
        skipped = skipped(lane)

        line = "lane=#{lane}"
        line += ", skipped: #{skipped.join(", ")}" unless skipped.empty?
        line += "; rendered findings are not measured or proven by this run" unless runs?(:layout_sweep, lane)
        line
      end
    end
  end
end
