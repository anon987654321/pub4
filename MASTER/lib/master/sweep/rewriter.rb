# frozen_string_literal: true

require "tempfile"

module Master
  class Sweep
    module Rewriter
      private

      def load_prompts = Master.load_yaml(PROMPTS_PATH)

      def build_codebase_map
        files = Dir.glob(File.join(@root, "lib", "**", "*.rb"))
                   .reject { |f| f.include?("/vendor/") }
                   .map    { |f| f.delete_prefix("#{@root}/") }
                   .sort
        unless @code_index&.built?
          return "## Codebase (#{files.size} Ruby files)\n" + files.map { |f| "  #{f}" }.join("\n")
        end

        lines = ["## Codebase (#{files.size} Ruby files)"]
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
        return 0 unless path.end_with?(".rb") && File.exist?(path)
        scan_result = @scanner.scan(path, depth: :deep)
        scan_result.ok? ? scan_result.value!.size : 0
      rescue StandardError
        0
      end

      def violations_in_text(content, ref_path)
        return 0 unless ref_path.end_with?(".rb")
        Tempfile.open(["vcheck", ".rb"]) do |f|
          f.write(content); f.flush
          scan_result = @scanner.scan(f.path, depth: :deep)
          scan_result.ok? ? scan_result.value!.size : 0
        end
      rescue StandardError
        0
      end
    end
  end
end
