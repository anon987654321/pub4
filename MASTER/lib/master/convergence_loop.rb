# frozen_string_literal: true

module Master
  # Unified scan→fix loop; stops on convergence, max_cycles, or oscillation (arxiv:2602.21833).
  class ConvergenceLoop
    MAX_CYCLES  = 16
    THRESHOLD   = 0.05
    WINDOW      = 2

    STRATEGIES = %i[surgical rewrite].freeze

    def initialize(target:, scanner:, agent:, root:, strategy: :surgical,
                   intensity: :standard, max_cycles: MAX_CYCLES,
                   threshold: THRESHOLD, window: WINDOW, event_bus: nil)
      @target     = target
      @scanner    = scanner
      @agent      = agent
      @root       = root
      @strategy   = strategy
      @intensity  = intensity
      @max_cycles = max_cycles
      @threshold  = threshold
      @window     = window
      @bus        = event_bus
      @history    = []
    end

    def run
      @max_cycles.times do |i|
        cycle = i + 1
        @bus&.publish("convergence_loop:cycle", cycle:, strategy: @strategy, target: @target)

        violations = scan
        score = score_from(violations)
        @history << score

        @bus&.publish("convergence_loop:score", cycle:, score:, violations: violations.size)

        break if converged?
        break if oscillating?

        apply_fixes(violations)
      end

      Result.ok(cycles: @history.size, final_score: @history.last)
    end

    private

    def scan
      dirs = Array(@target).map { |t| File.expand_path(t, @root) }
      dirs.flat_map { |d| @scanner.scan_dir(d, depth: @intensity) }
    end

    def score_from(violations)
      return 100.0 if violations.empty?
      penalty = violations.sum { |v| severity_weight(v[:severity]) }
      [100.0 - penalty, 0.0].max
    end

    def severity_weight(sev)
      { critical: 5.0, error: 3.0, warning: 1.0, info: 0.2 }.fetch(sev.to_sym, 1.0)
    end

    def converged?
      return false if @history.size < @window
      recent = @history.last(@window)
      deltas = recent.each_cons(2).map { |a, b| (b - a).abs }
      deltas.all? { |d| d < @threshold }
    end

    def oscillating?
      return false if @history.size < 4
      last4 = @history.last(4)
      last4[0] < last4[1] && last4[1] > last4[2] && last4[2] < last4[3]
    end

    def apply_fixes(violations)
      case @strategy
      when :surgical then apply_surgical(violations)
      when :rewrite  then apply_rewrite
      end
    end

    def apply_surgical(violations)
      files = violations.map { |v| v[:path] }.compact.uniq.first(5)
      files.each do |path|
        next unless File.exist?(path)
        file_violations = violations.select { |v| v[:path] == path }
        prompt = build_surgical_prompt(path, file_violations)
        begin
          result = @agent.ask(prompt)
          apply_patch(path, result)
        rescue StandardError => e
          @bus&.publish("convergence_loop:fix_error", path:, error: e.message)
        end
      end
    end

    def apply_rewrite
      sweep = Sweep.new(agent: @agent, scanner: @scanner, root: @root, event_bus: @bus)
      sweep.run(@root, max_cycles: 1)
    end

    def build_surgical_prompt(path, violations)
      code = File.read(path, encoding: "utf-8") rescue ""
      msgs = violations.map { |v| "  line #{v[:line]}: #{v[:message]}" }.join("\n")
      "Fix violations in #{path}:\n#{msgs}\n\nCurrent code:\n```ruby\n#{code}\n```\nReturn corrected file only."
    end

    def apply_patch(path, result)
      content = result.is_a?(String) ? result : result.to_s
      return if content.strip.empty?
      return if content.lines.size < (File.readlines(path).size * 0.8)
      File.write(path, content)
    rescue StandardError
      nil
    end
  end
end
