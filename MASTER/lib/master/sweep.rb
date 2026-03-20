# frozen_string_literal: true

require "open3"
require "tempfile"

module Master
  # Sweep — iterative full-codebase refactor to convergence.
  #
  # Each cycle walks every matching file and sends it through a comprehensive
  # rewrite prompt covering all axioms, structural techniques, and Prune & White
  # prose rules. Violation counts gate whether a rewrite is applied. Cycles
  # continue until violations converge (diminishing returns) or max_cycles hit.
  #
  # Self-application: sweeping lib/ causes MASTER to rewrite its own source —
  # including prune.rb and this file — a true fixed-point process.
  class Sweep
    MAX_CYCLES         = 16
    CONVERGE_THRESHOLD = 0.05  # stop when cycle-over-cycle improvement < 5%
    CONVERGE_WINDOW    = 2     # consecutive below-threshold cycles confirm convergence

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

    def initialize(agent:, scanner:, council:, root:, event_bus: nil)
      @agent   = agent
      @scanner = scanner
      @council = council
      @root    = root
      @bus     = event_bus
    end

    def run(target = @root, max_cycles: MAX_CYCLES, types: GLOBS.keys)
      violation_history = []
      converge_streak   = 0

      max_cycles.times do |i|
        cycle      = i + 1
        changed    = 0
        cycle_viol = 0

        @bus&.publish("sweep:cycle", cycle:, target:)

        collect_files(target, types).each do |path|
          rel        = path.delete_prefix("#{@root}/")
          before     = violations_in(path)
          new_src    = rewrite(path, rel)

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
        commit(cycle) if changed > 0 && git_dirty?

        converge_streak = converged?(violation_history) ? converge_streak + 1 : 0
        break if converge_streak >= CONVERGE_WINDOW
      end

      final = violation_history.last.to_i
      Result.ok("sweep: #{violation_history.size} cycle(s), #{final} violation(s) remaining")
    rescue => e
      Result.err("sweep: #{e.message}", category: :unknown)
    end

    private

    AXIOMS = <<~TEXT.freeze
      AXIOMS (non-negotiable):
      A1. `# frozen_string_literal: true` on every Ruby file, first line.
      A2. No bare `rescue` — always name the exception class.
      A3. Methods under 15 lines. Extract if longer.
      A4. One responsibility per class. Split if two found.
      A5. `Arel.sql()` around every raw SQL string in order()/where().
      A6. `respond_to?(:ok?)` not `is_a?` for duck-typing Result values.
      A7. Never silently swallow a Result::Err — propagate or log it.
      A8. No `rescue nil` chains — explicit, named error handling at boundaries.
      A9. No magic literals — extract to named constants: `NAME = value.freeze`.
      A10. Inject dependencies; never instantiate collaborators inside a method.
    TEXT

    STRUCTURAL_TECHNIQUES = <<~TEXT.freeze
      STRUCTURAL TECHNIQUES — reshape the code using whichever apply:
      S1. FLATTEN / GUARD CLAUSE — replace nested if/else with early returns.
          `return unless valid?` before the main logic, not wrapping it.
      S2. EXTRACT — a cohesive block of 5+ lines with one job → named private method.
      S3. INLINE — a one-liner method used exactly once → fold it into the call site.
      S4. HOIST — move loop-invariant computation above the loop. Extract constants.
      S5. MERGE — two methods with ≥80% identical bodies → one method with a parameter.
      S6. DECOUPLE — inject collaborators; remove hidden `new` calls inside methods.
      S7. DEFRAG — gather all code for one concept into one location. No scattered logic.
      S8. REFLOW — happy path first, error/edge cases after. Fail fast at the top.
      S9. TELL DON'T ASK — send commands to objects; don't query state to decide for them.
      S10. EXPAND — if logic is too dense to follow, break it into named intermediate steps.
      S11. CONTRACT — if logic is bloated with indirection, collapse trivial wrappers.
      S12. SPLIT — if a class has two responsibilities, extract the second into its own class.
      S13. PARALLELIZE — replace sequential independent map operations with parallel where safe.
    TEXT

    PROSE_TECHNIQUES = <<~TEXT.freeze
      PROSE TECHNIQUES — Prune & White for all comments and strings:
      P1. OMIT NEEDLESS WORDS — every word must earn its place.
      P2. ACTIVE VOICE — "returns the token" not "the token is returned by".
      P3. DELETE OBVIOUS COMMENTS — `# increment counter` above `count += 1` is noise.
      P4. REPHRASE VAGUE — "handle stuff" → "validate CSRF, reject with 403 on mismatch".
      P5. STRIP HEDGES — remove: simply, just, basically, obviously, easily,
          feel free to, keep in mind, please note, I think, I believe, It's worth noting.
      P6. STRIP PREAMBLES — remove: Great question, Certainly, Of course, I'd be happy to.
      P7. DIRECT ASSERTION — state facts; never qualify or apologize.
      P8. ECONOMY IN NAMING — `user_authentication_validation_helper` → `auth_check`
          only if the shorter name retains the full meaning.
    TEXT

    DIMENSION_ASSESSMENT = <<~TEXT.freeze
      DIMENSION ASSESSMENT — evaluate and act on each:
      - EXPAND this file? Logic too dense; needs intermediate named steps.
      - CONTRACT this file? Bloated with indirection; collapse it.
      - SPLIT this file? Two responsibilities found; extract the second.
      - MERGE with another? Trivially thin; belongs inside its only caller.
    TEXT

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
        Improve every dimension of #{rel} (#{lang}) in a single pass.

        #{AXIOMS}
        #{STRUCTURAL_TECHNIQUES}
        #{PROSE_TECHNIQUES}
        #{DIMENSION_ASSESSMENT}
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
      return text.match(fence_re)[1]       if text.match?(fence_re)
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

    def converged?(history)
      return false if history.size < 2

      prev, curr = history[-2], history[-1]
      return true if curr.zero?

      delta = (prev - curr).abs.to_f / [prev, 1].max
      delta < CONVERGE_THRESHOLD
    end

    def commit(cycle)
      Dir.chdir(@root) do
        system("git add -A 2>/dev/null")
        system("git commit -m 'sweep: full-codebase refactor [cycle #{cycle}]' 2>/dev/null")
      end
    end

    def git_dirty?
      out, = Open3.capture3("git -C #{@root} status --porcelain")
      !out.strip.empty?
    end
  end
end
