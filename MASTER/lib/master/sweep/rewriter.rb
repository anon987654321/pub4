# frozen_string_literal: true

require "tempfile"

module Master
  class Sweep
    module Rewriter
      private

      def load_prompts = Master.load_yaml(PROMPTS_PATH)

      def build_codebase_map
        files = library_files
        return simple_codebase_map(files) unless @code_index&.built?
        indexed_codebase_map(files)
      end

      def library_files
        Dir.glob(File.join(@root, "lib", "**", Scan::Scanner::SCAN_GLOB))
           .reject { |path| path.include?("/vendor/") || path.include?("/knowledge/") }
           .map    { |path| path.delete_prefix("#{@root}/") }
           .sort
      end

      def codebase_header(files) = "## Codebase (#{files.size} files)"

      def simple_codebase_map(files)
        ([codebase_header(files)] + files.map { |path| "  #{path}" }).join("\n")
      end

      def indexed_codebase_map(files)
        ([codebase_header(files)] + files.flat_map { |rel| symbol_lines(rel) }).join("\n")
      end

      def symbol_lines(rel)
        symbols = @code_index.symbols_in(File.join(@root, rel))
        return ["  #{rel}"] if symbols.empty?
        [rel] + class_lines(symbols) + method_lines(symbols)
      end

      def class_lines(symbols)
        symbols.select { |sym| %i[class module].include?(sym.type) }
               .map    { |sym| "  class #{sym.fqn}" }
      end

      def method_lines(symbols)
        symbols.select { |sym| sym.type == :method }
               .map    { |sym| "  def #{sym.fqn}" }
      end

      def collect_files(dir, types)
        sacred = Tools::PathGuard::SACRED_PATHS
        types.flat_map { |type| Dir.glob(File.join(dir, GLOBS[type].to_s)) }
             .reject { |path| sacred_match?(path, sacred) }
             .uniq.sort
      end

      def sacred_match?(path, sacred)
        rel = path.delete_prefix("#{@root}/")
        sacred.any? { |s| rel == s || rel.start_with?(s) }
      end

      CANDIDATE_THRESHOLD_BYTES = 4_000
      CANDIDATE_COUNT           = 3

      def rewrite(path, rel)
        source = File.read(path, encoding: "UTF-8")
        lang   = Scan::Rule::EXT_LANG.fetch(File.extname(path).downcase, "text")
        if source.bytesize >= CANDIDATE_THRESHOLD_BYTES
          rewrite_best_of(source, path, rel, lang, n: CANDIDATE_COUNT)
        else
          single_rewrite(source, rel, lang)
        end
      rescue StandardError => e
        @bus&.publish("sweep:rewrite_error", file: path, error: e.message)
        nil
      end

      def single_rewrite(source, rel, lang)
        response = @agent.ask(build_prompt(source, rel, lang))
        extract(response.to_s, lang, original_size: source.bytesize)
      end

      def rewrite_best_of(source, path, rel, lang, n:)
        baseline = violations_in_text(source, path)
        candidates = n.times.map { single_rewrite(source, rel, lang) }.compact
        return nil if candidates.empty?
        scored = candidates.map { |c| [score_candidate(c, path, baseline, source.bytesize), c] }
        winner = scored.max_by { |s, _| s }
        @bus&.publish("sweep:best_of_picked", file: path, n: candidates.size,
                      baseline_violations: baseline, winner_score: winner.first)
        winner.last
      end

      def score_candidate(content, path, baseline, original_size)
        violations  = violations_in_text(content, path)
        delta_viol  = baseline - violations
        delta_size  = (content.bytesize - original_size).abs
        (delta_viol * 10) - (delta_size / 100.0)
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

      def extract(text, lang, original_size: 0)
        return if text.strip == "UNCHANGED"
        return if ERROR_PATTERNS.match?(text)
        return if too_short?(text, original_size)
        fenced = extract_fenced(text, lang)
        return fenced if fenced
        text.strip.empty? ? nil : text
      end

      def too_short?(text, original_size)
        original_size > 0 && text.bytesize < (original_size * MIN_LENGTH_FRACTION)
      end

      def extract_fenced(text, lang)
        langs    = "#{Regexp.escape(lang)}|ruby|sh|yaml|erb"
        fence_re = /```(?:#{langs})?\n(.*?)```/m
        match    = text.match(fence_re)
        return match[1] if match
        bare = text.match(/```\n(.*?)```/m)
        bare&.[](1)
      end

      def syntax_ok?(path, content)
        checker = SYNTAX_CHECKERS[File.extname(path)]
        return true unless checker
        Tempfile.open(["sweep", File.extname(path)]) do |file|
          file.write(content); file.flush; checker.call(file.path)
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
        Tempfile.open(["vcheck", ext]) do |file|
          file.write(content); file.flush
          scan_result = @scanner.scan(file.path, depth: :deep)
          scan_result.ok? ? scan_result.value!.size : 0
        end
      rescue StandardError => _e
        0
      end
    end
  end
end
