# frozen_string_literal: true

require "open3"
require "tempfile"

module Master
  # Sweep — iterative full-codebase refactor to convergence.
  #
  # Each cycle walks every matching file and sends it through a comprehensive
  # rewrite prompt. The model receives the full codebase map before touching
  # any individual file — structural context precedes every change.
  # Cycles continue until violations converge or max_cycles hit.
  #
  # Self-application: sweeping lib/ causes MASTER to rewrite its own source —
  # a true fixed-point process.
  class Sweep
    MAX_CYCLES         = 16
    CONVERGE_THRESHOLD = 0.05
    CONVERGE_WINDOW    = 2

    GLOBS = {
      rb:  "**/*.rb",
      sh:  "**/*.sh",
      yml: "**/*.yml",
      md:  "**/*.md",
      erb: "**/*.erb"
    }.freeze

    SYNTAX_CHECKERS = {
      ".rb" => ->(p) { system("ruby -c #{p} > /dev/null 2>&1") },
      ".sh" => ->(p) { system("bash -n #{p}  > /dev/null 2>&1") }
    }.freeze

    SEVERITY_RANK = { info: 0, warning: 1, error: 2, critical: 3 }.freeze

    AXIOMS = <<~TEXT.freeze
      AXIOMS (non-negotiable):
      A1. `# frozen_string_literal: true` on every Ruby file, first line.
      A2. No bare `rescue` — always name the exception class.
      A3. Methods under 15 lines. Extract if longer.
      A4. One responsibility per class. Split if two found.
      A5. `respond_to?(:ok?)` not `is_a?` for duck-typing Result values.
      A6. Never silently swallow a Result::Err — propagate or log it.
      A7. No magic literals — extract to named constants: `NAME = value.freeze`.
      A8. Inject dependencies; never instantiate collaborators inside a method.
      A9. Guard clauses first: fail fast at the top, happy path at the bottom.
      A10. CQS: queries don't mutate; commands don't return meaningful values.
    TEXT

    STRUCTURAL_TECHNIQUES = <<~TEXT.freeze
      STRUCTURAL TECHNIQUES:
      S1. GUARD CLAUSE — replace nested if/else with early returns.
      S2. EXTRACT — a cohesive block of 5+ lines with one job → named private method.
      S3. INLINE — a one-liner method used exactly once → fold it into the call site.
      S4. HOIST — move loop-invariant computation above the loop.
      S5. MERGE — two methods with ≥80% identical bodies → one with a parameter.
      S6. DECOUPLE — inject collaborators; remove hidden `new` calls inside methods.
      S7. DEFRAG — gather all code for one concept into one location.
      S8. REFLOW — happy path first, error/edge cases after.
      S9. TELL DON'T ASK — send commands; don't query state to decide for them.
      S10. SPLIT — if a class has two responsibilities, extract the second.
    TEXT

    PROSE_TECHNIQUES = <<~TEXT.freeze
      PROSE TECHNIQUES (Strunk & White):
      P1. OMIT NEEDLESS WORDS — every word must earn its place.
      P2. ACTIVE VOICE — "returns the token" not "the token is returned by".
      P3. DELETE OBVIOUS COMMENTS — `# increment counter` above `count += 1` is noise.
      P4. STRIP HEDGES — remove: simply, just, basically, obviously, easily,
          feel free to, keep in mind, please note, I think, I believe.
      P5. STRIP PREAMBLES — remove: Great question, Certainly, Of course, I'd be happy.
      P6. DIRECT ASSERTION — state facts; never qualify or apologize.
    TEXT

    def initialize(agent:, scanner:, council:, root:, event_bus: nil)
      @agent   = agent
      @scanner = scanner
      @council = council
      @root    = root
      @bus     = event_bus
      @map     = nil  # lazy; built once per sweep run
    end

    def run(target = @root, max_cycles: MAX_CYCLES, types: GLOBS.keys)
      @map            = build_codebase_map
      violation_history = []
      converge_streak   = 0

      max_cycles.times do |i|
        cycle   = i + 1
        changed = 0
        cycle_viol = 0

        @bus&.publish("sweep:cycle", cycle:, target:)

        collect_files(target, types).each do |path|
          rel    = path.delete_prefix("#{@root}/")
          before = violations_in(path)
          new_src = rewrite(path, rel)

          next unless new_src
          next if new_src.strip == File.read(path, encoding: "UTF-8").strip
          next unless syntax_ok?(path, new_src)

          after = violations_in_text(new_src, path)
          next if after > before

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
      end

      final = violation_history.last.to_i
      Result.ok("sweep: #{violation_history.size} cycle(s), #{final} violation(s) remaining")
    rescue StandardError => e
      Result.err("sweep: #{e.message}", category: :unknown)
    end

    private

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
    rescue StandardError
      nil
    end

    def build_prompt(src, rel, lang)
      <<~PROMPT
        You are refactoring #{rel} (#{lang}). Study the full codebase map below
        before making any change — do not modify an interface without tracing its callers.

        #{@map}

        #{AXIOMS}
        #{STRUCTURAL_TECHNIQUES}
        #{PROSE_TECHNIQUES}

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
      r = @scanner.scan(path, depth: :standard)
      r.respond_to?(:value!) ? r.value!.size : 0
    rescue StandardError
      0
    end

    def violations_in_text(content, ref_path)
      return 0 unless ref_path.end_with?(".rb")

      Tempfile.open(["vcheck", ".rb"]) do |f|
        f.write(content)
        f.flush
        r = @scanner.scan(f.path, depth: :standard)
        r.respond_to?(:value!) ? r.value!.size : 0
      end
    rescue StandardError
      0
    end

    def converged?(history)
      return false if history.size < 2

      prev, curr = history[-2], history[-1]
      return true if curr.zero?

      delta = (prev - curr).abs.to_f / [prev, 1].max
      delta < CONVERGE_THRESHOLD
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
