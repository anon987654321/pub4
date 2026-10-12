# frozen_string_literal: true

require_relative "layout_score_render"
require_relative "visual_quality_gates"
require_relative "tool_breaker"

module Master
  module Fix
    # Best-of-N for one visual finding, the way postpro keeps the best-scoring
    # of several drafts: the fixer proposes N distinct candidates, each is
    # written in turn, the affected surfaces are re-rendered and measured, and
    # the file goes back to its original before the next. A candidate is
    # discarded when its layout score drops past the tolerance, a quality-gate
    # metric worsens, or chrome drifts off its budget. Of the survivors the
    # highest mean layout score wins, the smallest diff breaking a tie.
    #
    # MASTER_FIX_BEST_OF sets N (default 1). At 1 the pass is inactive and
    # RepairLoop behaves exactly as it did without it.
    module BestOfN
      LAW_ID = "RENDERED_VISUAL_REFINEMENT"
      MAX_N = 8
      TIE = 0.05
      STYLE_EXTENSIONS = %w[.css .scss].freeze
      VARIANTS = [
        "Candidate approach: change as little as possible, only the property the finding names.",
        "Candidate approach: reach the same goal through a different selector or property than the obvious one.",
        "Candidate approach: prefer an existing design token or layout primitive over a new value.",
      ].freeze
      Scored = Data.define(:source, :score, :problems, :diff)

      module_function

      def n = Integer(ENV.fetch("MASTER_FIX_BEST_OF", "1")).clamp(1, MAX_N)

      # A tuple the ToolBreaker has fused gets no N-way fan-out either: N more model
      # calls on a prompt that failed three times against this unchanged file.
      def active?(violation, custody, tool: LAW_ID)
        return false if ToolBreaker.refuse?(tool, violation, ToolBreaker.state_of(violation))

        n > 1 && custody && violation[:law].to_s == LAW_ID && STYLE_EXTENSIONS.include?(File.extname(violation[:file].to_s).downcase)
      end

      # The first proposal plus N-1 more, scored; returns the winning source
      # or nil when every candidate regressed.
      def pick(loop, violation, first, custody:, root:, measurer: LayoutScoreRender.method(:measure))
        path = violation[:file]
        root = File.basename(root) == "MASTER" ? File.dirname(root) : root
        original = File.read(path, encoding: "UTF-8")
        ext = File.extname(path).downcase
        extra = (1...n).filter_map do |i|
          prompt = loop.send(:build_prompt_for, violation:, src: original, path:) + "\n\n#{VARIANTS[(i - 1) % VARIANTS.size]}"
          loop.send(:extract_code, loop.send(:ask_agent, prompt, image: loop.instance_variable_get(:@visual_image)).to_s, ext)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "BestOfN.candidate") if defined?(Master::Ground::Swallow)
          nil
        end
        rank([first, *extra], original:, surfaces: custody.surfaces, root:, measurer:, anchors: [violation[:anchor]].compact,
             write: ->(src) { loop.send(:write_atomic, path, src) })
      end

      def rank(candidates, original:, surfaces:, root:, measurer:, write:, anchors: [])
        pool = candidates.map(&:to_s).reject { |c| c.strip.empty? || c == original }.uniq
        scored = pool.each_with_index.map do |source, i|
          write.call(source)
          row = score(source, original, measurer.call(surfaces, root:), root:, anchors:)
          log(i + 1, pool.size, row)
          row
        ensure
          write.call(original)
        end
        scored.select { |row| row.problems.empty? }.max_by { |row| [(row.score / TIE).round, -row.diff] }&.source
      end

      def score(source, original, measured, root:, anchors:)
        return Scored.new(source:, score: 0.0, problems: ["not rendered"], diff: 0) if measured.empty?

        problems = measured.flat_map { |surface, payload| judge(surface, payload, root:, anchors:) }
        mean = LayoutScoreRender.scores(measured, root:).values
        Scored.new(source:, score: (mean.sum / mean.size).round(1), problems:, diff: diff_size(original, source))
      end

      def judge(surface, payload, root:, anchors:)
        base = VisualQualityGates.load(root, surface)
        cur = VisualQualityGates.measure(surface, payload, baseline_rects: base && base["rects"])
        worse = base ? VisualQualityGates.worse(base, cur) : []
        drift = VisualDriftBudget.check(surface, payload, root:, anchors:)
        worse + LayoutScoreStore.judge(surface, payload, root:) + (drift.empty? ? [] : ["chrome drift #{drift.first(2).join(", ")}"])
      end

      def diff_size(a, b)
        old = a.lines
        (b.lines - old).size + (old - b.lines).size
      end

      def log(index, total, row)
        verdict = row.problems.empty? ? "kept" : "discarded: #{row.problems.first(2).join("; ")}"
        Master::Trace::Dmesg.status("best0", "candidate #{index}/#{total} score #{row.score} diff #{row.diff} #{verdict}")
      rescue StandardError
        nil
      end
    end
  end
end
