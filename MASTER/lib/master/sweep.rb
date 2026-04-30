# frozen_string_literal: true

require "open3"
require "tempfile"
require "set"
require_relative "sweep/rewriter"
require_relative "sweep/convergence"


module Master
  # Sweep — iterative full-codebase refactor to convergence.
  #
  # Each cycle walks every matching file and sends it through a comprehensive
  # rewrite prompt. The model receives the full codebase map before touching
  # any individual file — structural context precedes every change.
  # Cycles continue until violations converge, rename oscillation is detected,
  # or max_cycles hit.
  #
  # Stopping criteria, per arxiv:2602.21833 ("From Restructuring to
  # Stabilization"):
  #   1. violation delta < CONVERGE_THRESHOLD for CONVERGE_WINDOW cycles
  #   2. rename oscillation detected (symbol A→B→A in the window)
  #   3. trajectory value (γ-discounted) stops improving
  #
  # Self-application: sweeping lib/ causes MASTER to rewrite its own source —
  # a true fixed-point process.
  class Sweep
    MAX_CYCLES         = 16
    CONVERGE_THRESHOLD = 0.05
    CONVERGE_WINDOW    = 2
    RENAME_WINDOW      = 3      # oscillation detected if A→B→A within 3 cycles.freeze
    TRAJECTORY_GAMMA   = 0.9    # γ for discounted improvement signal.freeze

    GLOBS = {
      rb:  "**/*.rb",
      sh:  "**/*.sh",
      yml: "**/*.yml",
      md:  "**/*.md",
      erb: "**/*.erb"
    }.freeze

    SYNTAX_CHECKERS = {
      ".rb" => ->(p) { system("ruby -c #{p} > /dev/null 2>&1") },
      ".sh"  => ->(p) { system("bash -n #{p}  > /dev/null 2>&1") },
      ".yml" => ->(p) { begin; Master.load_yaml(p); true; rescue => _e; false; end },
      ".erb" => ->(p) { begin; ERB.new(File.read(p)).result(binding); true; rescue SyntaxError; false; rescue => _e; true; end }
    }.freeze

    SEVERITY_RANK = Master::SEVERITY_RANK

    ERROR_PATTERNS = /
      \b(?:error|exception|traceback|failed|cannot|unable\sto|
      undefined\smethod|no\smethod|syntax\serror|
      internal\sserver|rate\slimit|quota\sexceeded|
      apologize|as\san\sai|i\scannot|i\sam\sunable|
circuit\sopen|retry\sin|llm_request)\b
    /ix.freeze

    PROMPTS_PATH = File.join(Master::ROOT, "data", "sweep_prompts.yml").freeze

    # Regex for Ruby method/class/constant names — used by rename tracker.
    NAME_RE = /\b(?:def\s+(\w+)|class\s+([A-Z]\w*)|[A-Z][A-Z_]+)\b/.freeze

    include Rewriter
    include Convergence

    def initialize(agent:, scanner:, council:, root:, event_bus: nil)
      @agent   = agent
      @scanner = scanner
      @council = council
      @root    = root
      @bus     = event_bus
      @map     = nil
      @prompts = nil
      @rename_log = Hash.new { |h, k| h[k] = [] }  # file => [cycle: {before:, after:}]
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
