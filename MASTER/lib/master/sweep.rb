# frozen_string_literal: true

require "open3"
require "tempfile"
require "set"
require_relative "sweep/rewriter"
require_relative "sweep/convergence"

module Master
  # Full-codebase refactor to convergence; stops on delta/oscillation/stall (arxiv:2602.21833).
  class Sweep
    MAX_CYCLES         = 16
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
      ".sh"  => ->(p) { _, _, st = Open3.capture3("bash", "-n", p); st.success? },
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
    MIN_REWRITE_BYTES = 500

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
    end

    def run(target = @root, max_cycles: MAX_CYCLES, types: GLOBS.keys)
      @map            = build_codebase_map
      @prompts        = load_prompts
      violation_history = []
      converge_streak   = 0

      max_cycles.times do |i|
        cycle   = i + 1
        changed = 0
        cycle_viol = 0

        @bus&.publish("sweep:cycle", cycle:, target:)

        collect_files(target, types).each do |path|
          rel     = path.delete_prefix("#{@root}/")
          before  = violations_in(path)
          src     = File.read(path, encoding: "UTF-8")
          new_src = rewrite(path, rel)

          next unless new_src
          next if new_src.strip == src.strip
          next unless syntax_ok?(path, new_src)

          after = violations_in_text(new_src, path)
          next if after > before

          # Oscillation check: track name-level renames and reject if they
          # revert recent changes. Naming-focused prompts are the known
          # trigger (see arxiv:2602.21833 §4.3 — naming-focused prompts may
          # induce oscillatory renaming behavior).
          if rename_oscillation?(rel, src, new_src, cycle)
            @bus&.publish("sweep:oscillation_rejected", file: rel, cycle:)
            next
          end

          File.write(path, new_src, encoding: "UTF-8")
          changed    += 1
          cycle_viol += after
          @bus&.publish("sweep:improved", file: rel, before:, after:)
          yield cycle, rel, before - after if block_given?
        end

        violation_history << cycle_viol
        commit("sweep: full-codebase refactor [cycle #{cycle}]") if changed > 0 && git_dirty?

        converge_streak = converged?(violation_history) ? converge_streak + 1 : 0
        break if converge_streak >= CONVERGE_WINDOW

        # Trajectory-value early stop: if γ-discounted improvement signal
        # has flatlined, further cycles are unlikely to help and risk
        # the "rare but non-zero per iteration" functionality breaks
        # documented in arxiv:2602.21833.
        break if trajectory_stalled?(violation_history)
      end

      final = violation_history.last.to_i
      Result.ok("sweep: #{violation_history.size} cycle(s), #{final} violation(s) remaining")
    rescue StandardError => e
      Result.err("sweep: #{e.message}", category: :unknown)
    end
  end
end
