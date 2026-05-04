# MASTER Snapshot — lib/master/sweep/
Generated: 2026-05-04T10:21:42Z

## lib/master/sweep/convergence.rb
```ruby
# frozen_string_literal: true

module Master
  class Sweep
    # Per-cycle metrics tracking and early-stop logic for sweep loops.
    # Detects stall, low success rate, and sign-reversal oscillation.
    module Convergence
      LOW_SUCCESS_RATE = 0.10

      private

      def init_cycle_log
        @cycle_log = []
      end

      # Record one cycle's metrics. Returns the entry for bus publishing.
      def record_cycle(violations:, fixed:, deferred:)
        prev  = @cycle_log.last
        delta = prev ? (prev[:violations] - violations) : fixed
        total = violations + fixed
        rate  = total.zero? ? 0.0 : (fixed.to_f / total).round(3)
        entry = { violations:, fixed:, deferred:, delta:, rate: }
        @cycle_log << entry
        entry
      end

      # Unified early-stop: stall, low success rate, oscillation, or done.
      def should_halt_early?
        return false if @cycle_log.size < 2

        last = @cycle_log.last
        return true if last[:violations].zero?
        return true if last[:rate] < LOW_SUCCESS_RATE
        return true if @cycle_log.last(2).all? { |entry| entry[:delta] == 0 }
        return true if oscillating?

        false
      end

      def oscillating?
        signs = @cycle_log.last(3).map { |entry| entry[:delta] <=> 0 }
        return false if signs.size < 3
        signs.each_cons(2).all? { |x, y| x != 0 && x == -y }
      end

      def convergence_summary
        return "sweep: no cycles recorded" if @cycle_log.empty?
        count = @cycle_log.size
        last  = @cycle_log.last
        prev  = count > 1 ? @cycle_log[-2][:violations] : "?"
        osc   = oscillating? ? 1 : 0
        "sweep: iter=#{count} violations=#{prev}->#{last[:violations]} " \
          "fixed=#{last[:fixed]} deferred=#{last[:deferred]} rate=#{last[:rate]} oscillating=#{osc}"
      end

      # A→B→A within RENAME_WINDOW cycles signals oscillation (arxiv:2602.21833 §4.3).
      def rename_oscillation?(rel, old_src, new_src, cycle)
        old_names   = extract_names(old_src)
        new_names   = extract_names(new_src)
        removed_now = old_names - new_names
        added_now   = new_names - old_names
        history     = @rename_log[rel]
        oscillates  = history.last(RENAME_WINDOW).any? { |entry| names_reverted?(entry, added_now, removed_now) }
        history << { cycle:, removed: removed_now, added: added_now }
        @rename_log[rel] = history.last(RENAME_WINDOW * 2)
        oscillates
      end

      def names_reverted?(entry, added_now, removed_now)
        (entry[:removed] & added_now).any? && (entry[:added] & removed_now).any?
      end

      def extract_names(source) = source.scan(NAME_RE).flatten.compact.uniq

      def converged?(history)
        return false if history.size < 2
        prev, curr = history[-2], history[-1]
        return true if curr.zero?
        (prev - curr).abs.to_f / [prev, 1].max < CONVERGE_THRESHOLD
      end

      def trajectory_stalled?(history)
        return false if history.size < 3
        deltas = history.each_cons(2).map { |a, b| a - b }
        weighted = deltas.last(CONVERGE_WINDOW + 1).each_with_index.sum { |d, idx| d * (TRAJECTORY_GAMMA**idx) }
        weighted.abs < 1.0
      end

      def commit(msg)
        Open3.capture2e("git", "-C", @root, "add", "-A")
        Open3.capture2e("git", "-C", @root, "commit", "-m", msg.to_s)
      end

      def git_dirty?
        out, = Open3.capture2e("git", "-C", @root, "status", "--porcelain")
        !out.strip.empty?
      end
    end
  end
end

```

## lib/master/sweep/rewriter.rb
```ruby
# frozen_string_literal: true

require "tempfile"

module Master
  class Sweep
    module Rewriter
      private

      def load_prompts = Master.load_yaml(PROMPTS_PATH)

      def build_codebase_map
        files = Dir.glob(File.join(@root, "lib", "**", Scan::Scanner::SCAN_GLOB))
                   .reject { |f| f.include?("/vendor/") || f.include?("/knowledge/") }
                   .map    { |f| f.delete_prefix("#{@root}/") }
                   .sort
        unless @code_index&.built?
          return "## Codebase (#{files.size} files)\n" + files.map { |f| "  #{f}" }.join("\n")
        end

        lines = ["## Codebase (#{files.size} files)"]
        files.each do |rel|
          syms = @code_index.symbols_in(File.join(@root, rel))
          if syms.empty?
            lines << "  #{rel}"
          else
            lines << rel
            syms.select { |s| %i[class module].include?(s.type) }.each { |s| lines << "  class #{s.fqn}" }
            syms.select { |s| s.type == :method }.each { |s| lines << "  def #{s.fqn}" }
          end
        end
        lines.join("\n")
      end

      def collect_files(dir, types)
        types.flat_map { |t| Dir.glob(File.join(dir, GLOBS[t].to_s)) }
             .reject { |f| f.include?("/data/") }
             .uniq.sort
      end

      def rewrite(path, rel)
        src  = File.read(path, encoding: "UTF-8")
        lang = Scan::Rule::EXT_LANG.fetch(File.extname(path).downcase, "text")
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
        return nil if text.bytesize < MIN_REWRITE_BYTES && ERROR_PATTERNS.match?(text)
        fence_re = /```(?:#{Regexp.escape(lang)}|ruby|sh|bash|yaml|erb)?\n(.*?)```/m
        return text.match(fence_re)[1]         if text.match?(fence_re)
        return text.match(/```\n(.*?)```/m)[1] if text.match?(/```\n(.*?)```/m)
        text.strip.empty? ? nil : text
      end

      def syntax_ok?(path, content)
        checker = SYNTAX_CHECKERS[File.extname(path)]
        return true unless checker
        Tempfile.open(["sweep", File.extname(path)]) do |f|
          f.write(content); f.flush; checker.call(f.path)
        end
      end

      def violations_in(path)
        return 0 unless Scan::Rule::EXT_LANG.key?(File.extname(path).downcase) && File.exist?(path)
        scan_result = @scanner.scan(path, depth: :deep)
        scan_result.ok? ? scan_result.value!.size : 0
      rescue StandardError => _e
        0
      end

      def violations_in_text(content, ref_path)
        ext = File.extname(ref_path).downcase
        return 0 unless Scan::Rule::EXT_LANG.key?(ext)
        Tempfile.open(["vcheck", ext]) do |f|
          f.write(content); f.flush
          scan_result = @scanner.scan(f.path, depth: :deep)
          scan_result.ok? ? scan_result.value!.size : 0
        end
      rescue StandardError => _e
        0
      end
    end
  end
end

```
