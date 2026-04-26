# frozen_string_literal: true

require "open3"
require "tempfile"
require "yaml"
require "set"

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
    RENAME_WINDOW      = 3      # oscillation detected if A→B→A within 3 cycles
    TRAJECTORY_GAMMA   = 0.9    # γ for discounted improvement signal

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
      ".yml" => ->(p) { begin; YAML.safe_load_file(p); true; rescue => _e; false; end },
      ".erb" => ->(p) { begin; ERB.new(File.read(p)).result(binding); true; rescue SyntaxError; false; rescue => _e; true; end }
    }.freeze

    SEVERITY_RANK = { info: 0, warning: 1, error: 2, critical: 3 }.freeze

    ERROR_PATTERNS = /
      \b(?:error|exception|traceback|failed|cannot|unable\sto|
      undefined\smethod|no\smethod|syntax\serror|
      internal\sserver|rate\slimit|quota\sexceeded|
      apologize|as\san\sai|i\scannot|i\sam\sunable)\b
    /ix.freeze

    PROMPTS_PATH = File.join(Master::ROOT, "data", "sweep_prompts.yml").freeze

    # Regex for Ruby method/class/constant names — used by rename tracker.
    NAME_RE = /\b(?:def\s+(\w+)|class\s+([A-Z]\w*)|[A-Z][A-Z_]+)\b/.freeze

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

    private

    def load_prompts
      YAML.safe_load_file(PROMPTS_PATH)
    end

    # Build a compact file map. Injected into every rewrite prompt so the model
    # has full structural context before touching any individual file.
    def build_codebase_map
      files = Dir.glob(File.join(@root, "lib", "**", "*.rb"))
                 .reject { |f| f.include?("/vendor/") }
                 .map    { |f| f.delete_prefix("#{@root}/") }
                 .sort
      "## Codebase (#{files.size} Ruby files)\n" +
        files.map { |f| "  #{f}" }.join("\n")
    end

    def collect_files(dir, types)
      types.flat_map { |t| Dir.glob(File.join(dir, GLOBS[t].to_s)) }.uniq.sort
    end

    def rewrite(path, rel)
      src  = File.read(path, encoding: "UTF-8")
      ext  = File.extname(path)
      lang = { ".rb" => "ruby", ".sh" => "sh", ".yml" => "yaml",
               ".md" => "markdown", ".erb" => "erb" }.fetch(ext, "text")

      response = @agent.ask(build_prompt(src, rel, lang))
      extract(response.to_s, lang)
    rescue StandardError => e
      @bus&.publish("sweep:rewrite_error", file: path, error: e.message)
      nil
    end

    def build_prompt(src, rel, lang)
      <<~PROMPT
        You are refactoring #{rel} (#{lang}). Study the full codebase map below
        before making any change — do not modify an interface without tracing its callers.

        #{@map}

        #{@prompts["axioms"]}
        #{@prompts["structural_techniques"]}
        #{@prompts["prose_techniques"]}

        Improve every dimension of #{rel} in a single pass.
        Return ONLY the improved file content — no explanation, no markdown fences
        unless the file is already markdown. If no improvement is possible, return
        exactly: UNCHANGED

        File content:
        #{src}
      PROMPT
    end

    def extract(text, lang)
      return nil if text.strip == "UNCHANGED"

      # Reject short responses that look like error messages
      if text.bytesize < 500 && ERROR_PATTERNS.match?(text)
        return nil
      end

      fence_re = /```(?:#{Regexp.escape(lang)}|ruby|sh|bash|yaml|erb)?\n(.*?)```/m
      return text.match(fence_re)[1]         if text.match?(fence_re)
      return text.match(/```\n(.*?)```/m)[1] if text.match?(/```\n(.*?)```/m)

      text.strip.empty? ? nil : text
    end

    def syntax_ok?(path, content)
      checker = SYNTAX_CHECKERS[File.extname(path)]
      return true unless checker

      Tempfile.open(["sweep", File.extname(path)]) do |f|
        f.write(content)
        f.flush
        checker.call(f.path)
      end
    end

    def violations_in(path)
      return 0 unless path.end_with?(".rb") && File.exist?(path)
      r = @scanner.scan(path, depth: :deep)
      r.respond_to?(:value!) ? r.value!.size : 0
    rescue StandardError
      0
    end

    def violations_in_text(content, ref_path)
      return 0 unless ref_path.end_with?(".rb")

      Tempfile.open(["vcheck", ".rb"]) do |f|
        f.write(content)
        f.flush
        r = @scanner.scan(f.path, depth: :deep)
        r.respond_to?(:value!) ? r.value!.size : 0
      end
    rescue StandardError
      0
    end

    # Oscillation detector — rejects a proposed rewrite when it reintroduces
    # a name that was removed in a recent cycle. A→B then B→A within
    # RENAME_WINDOW is the signature documented in arxiv:2602.21833.
    def rename_oscillation?(rel, old_src, new_src, cycle)
      removed_now = extract_names(old_src) - extract_names(new_src)
      added_now   = extract_names(new_src) - extract_names(old_src)

      history = @rename_log[rel]
      recent  = history.last(RENAME_WINDOW)

      oscillates = recent.any? { |entry|
        # Was something currently being ADDED previously REMOVED, and vice versa?
        (entry[:removed] & added_now).any? && (entry[:added] & removed_now).any?
      }

      history << { cycle: cycle, removed: removed_now, added: added_now }
      # Keep only the window we actually query.
      @rename_log[rel] = history.last(RENAME_WINDOW * 2)

      oscillates
    end

    def extract_names(source)
      source.scan(NAME_RE).flatten.compact.uniq
    end

    def converged?(history)
      return false if history.size < 2

      prev, curr = history[-2], history[-1]
      return true if curr.zero?

      delta = (prev - curr).abs.to_f / [prev, 1].max
      delta < CONVERGE_THRESHOLD
    end

    # γ-discounted improvement signal. If the weighted sum of improvements
    # across recent cycles is near zero, we've stalled.
    # V = Σ γ^t · (prev_t − curr_t)
    def trajectory_stalled?(history)
      return false if history.size < 3
      deltas = history.each_cons(2).map { |a, b| a - b }
      v = deltas.last(CONVERGE_WINDOW + 1).each_with_index.sum { |d, i| d * (TRAJECTORY_GAMMA ** i) }
      v.abs < 1.0
    end

    def commit(msg)
      Dir.chdir(@root) do
        system("git add -A 2>/dev/null")
        system("git commit -m '#{msg}' 2>/dev/null")
      end
    end

    def git_dirty?
      out, = Open3.capture3("git -C #{@root} status --porcelain")
      !out.strip.empty?
    end
  end
end
