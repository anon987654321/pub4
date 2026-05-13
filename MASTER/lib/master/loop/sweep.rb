# frozen_string_literal: true

require "open3"
require "erb"
require "tempfile"
require "set"
require_relative "sweep/rewriter"
require_relative "sweep/convergence"

module Master
  module Loop
  # Full-codebase refactor to convergence; stops on delta/oscillation/stall (arxiv:2602.21833).
  class Sweep
    MAX_CYCLES         = 16
    SMALL_CHANGE_LINES = 5
    MEDIUM_CHANGE_LINES = 30
    CONVERGE_THRESHOLD = 0.05
    CONVERGE_WINDOW    = 2
    RENAME_WINDOW    = 3
    TRAJECTORY_GAMMA = 0.9

    GLOBS = {
      rb:  "**/*.rb",
      sh:  "**/*.sh",
      yml: "**/*.yml",
      md:  "**/*.md",
      erb: "**/*.erb"
    }.freeze

    SYNTAX_CHECKERS = {
      ".rb"  => ->(p) { _, _, st = Open3.capture3("ruby", "-c", p); st.success? },
      ".sh"  => ->(p) { _, _, st = Open3.capture3("zsh", "-n", p); st.success? },
      ".yml" => ->(p) { begin; Master.load_yaml(p); true; rescue StandardError => _e; false; end },
      ".erb" => ->(p) { begin; RubyVM::InstructionSequence.compile(ERB.new(File.read(p, encoding: "UTF-8")).src); true; rescue SyntaxError, StandardError => _e; false; end }
    }.freeze

    SEVERITY_RANK = Master::SEVERITY_RANK

    ERROR_PATTERNS = /
      \b(?:error|exception|traceback|failed|cannot|unable\sto|
      undefined\smethod|no\smethod|syntax\serror|
      internal\sserver|rate\slimit|quota\sexceeded|
      apologize|as\san\sai|i\scannot|i\sam\sunable|
circuit\sopen|retry\sin|llm_request)\b
    /ix.freeze

    PROMPTS_PATH      = File.join(Master::ROOT, "data", "sweep_prompts.yml").freeze
    MIN_REWRITE_BYTES   = 500
    MIN_LENGTH_FRACTION = 0.50

    # Regex for Ruby method/class/constant names — used by rename tracker.
    NAME_RE = /\b(?:def\s+(\w+)|class\s+([A-Z]\w*)|[A-Z][A-Z_]+)\b/.freeze

    include Rewriter
    include Convergence

    def initialize(agent:, scanner:, root:, council: nil, event_bus: nil, code_index: nil)
      @agent      = agent
      @scanner    = scanner
      @root       = root
      @bus        = event_bus
      @code_index = code_index
      @map        = nil
      @prompts    = nil
      @rename_log = Hash.new { |h, k| h[k] = [] }
      @cycle_log  = []
    end

    def run(target = @root, max_cycles: MAX_CYCLES, types: GLOBS.keys)
      saved_model = @agent.model
      @agent.model = @agent.model_for(operation: :sweep)
      cfg = Master.load_yaml(File.join(@root, "data", "workflow.yml")).dig("sweep") || {}
      @converge_threshold = cfg.fetch("converge_threshold", CONVERGE_THRESHOLD)
      @converge_window    = cfg.fetch("converge_window",    CONVERGE_WINDOW)
      @map            = build_codebase_map
      @prompts        = load_prompts
      sweep_types     = select_types(target, types)
      violation_history = []
      converge_streak   = 0
      init_cycle_log

      max_cycles.times do |i|
        cycle       = i + 1
        changed     = 0
        cycle_viol  = 0
        cycle_fixed = 0
        cycle_defer = 0

        @bus&.publish("sweep:cycle", cycle:, target:)

        collect_files(target, sweep_types).each do |path|
          rel    = path.delete_prefix("#{@root}/")
          before = violations_in(path)
          src    = File.read(path, encoding: "UTF-8")

          new_src, after = evaluate_rewrite(rel, src, before, cycle)
          if new_src.nil?
            cycle_defer += before
            next
          end

          delta = before - after
          tmp_path = "#{path}.tmp.#{Process.pid}"
          File.write(tmp_path, new_src, encoding: "UTF-8")
          File.rename(tmp_path, path)
          changed     += 1
          cycle_viol  += after
          cycle_fixed += delta
          @bus&.publish("sweep:improved", file: rel, before:, after:)
          yield cycle, rel, delta if block_given?
        end

        violation_history << cycle_viol
        entry = record_cycle(violations: cycle_viol, fixed: cycle_fixed, deferred: cycle_defer)
        @bus&.publish("sweep:cycle_stats", cycle:, **entry)
        commit("sweep: full-codebase refactor [cycle #{cycle}]") if changed > 0 && git_dirty?

        converge_streak = converged?(violation_history) ? converge_streak + 1 : 0
        break if converge_streak >= @converge_window
        break if trajectory_stalled?(violation_history)
        break if should_halt_early?
      end

      summary = convergence_summary
      @bus&.publish("sweep:done", summary:)
      Result.ok(summary)
    rescue StandardError => e
      Result.err("sweep: #{e.message}", category: :unknown)
    ensure
      @agent.model = saved_model if defined?(saved_model) && saved_model
    end

    private

    def select_types(target, fallback_types)
      changed = changed_line_count(target)
      return %i[rb sh] if changed < SMALL_CHANGE_LINES
      return %i[rb sh yml] if changed <= MEDIUM_CHANGE_LINES
      fallback_types
    end

    def changed_line_count(target)
      rel = target.to_s == @root ? nil : target.delete_prefix(@root + "/")
      cmd = ["git", "-C", @root, "diff", "--numstat", "HEAD"]
      cmd << "--" << rel if rel && !rel.empty?
      out, = Open3.capture2(*cmd)
      out.lines.sum do |line|
        a, d, = line.split("	", 3)
        a.to_i + d.to_i
      end
    rescue StandardError
      MEDIUM_CHANGE_LINES
    end

    def evaluate_rewrite(rel, src, before, cycle)
      abs = File.join(@root, rel)
      native_src = native_autofix(abs, src)
      if native_src
        native_after = violations_in_text(native_src, abs)
        if native_after < before
          @bus&.publish("sweep:native_fix", file: rel, before:, after: native_after)
          return [native_src, native_after]
        end
        src = native_src
        before = native_after
      end
    
      new_src = rewrite(abs, rel)
      return unless new_src && new_src.strip != src.strip && syntax_ok?(abs, new_src)
    
      after = violations_in_text(new_src, abs)
      return if after > before
    
      if rename_oscillation?(rel, src, new_src, cycle)
        @bus&.publish("sweep:oscillation_rejected", file: rel, cycle:)
        return
      end
    
      [new_src, after]
    end
    
    def native_autofix(path, src)
      return unless path.end_with?(".rb")
      result = nil
      Tempfile.open(["sweep_native", ".rb"]) do |f|
        f.write(src)
        f.flush
        _, _, status = Open3.capture3(
          "bundle", "exec", "rubocop", "-A", "--no-color",
          "--format", "quiet", f.path, chdir: @root
        )
        next unless status.exitstatus.to_i <= 1
        candidate = File.read(f.path, encoding: "UTF-8")
        next if candidate == src
        next unless syntax_ok?(path, candidate)
        result = candidate
      end
      result
    rescue StandardError => _e
      nil
    end
  end
  end
end
