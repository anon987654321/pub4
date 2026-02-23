# frozen_string_literal: true

# ConventionExtractor — Samples the project's actual Ruby style and injects it
# into the system prompt so the LLM mimics existing conventions instead of
# inventing its own. Implements gist item #9 (Gemini CLI / Warp 2.0 pattern).
#
# Detects: module naming style, indent width, extend-self vs module_function,
# frozen_string_literal presence, Result monad usage.

module MASTER
  module ConventionExtractor
    SAMPLE_COUNT      = 3    # files to sample; small to keep system prompt lean
    SAMPLE_CHAR_LIMIT = 1500 # chars read per sampled file
    RESULT_CHAR_LIMIT = 800  # chars read from result.rb

    module_function

    # Returns a compact prose summary of detected conventions, ~8 lines.
    def extract(root: MASTER.root, sample_count: SAMPLE_COUNT)
      rb_files = Dir.glob(File.join(root, "lib", "**", "*.rb"))
                    .reject { |f| f.include?("test") || f.include?("vendor") }
      return "" if rb_files.empty?

      samples = rb_files.sample(sample_count).map { |f| File.read(f)[0..SAMPLE_CHAR_LIMIT] rescue "" }
      all_content = File.read(File.join(root, "lib", "result.rb"))[0..RESULT_CHAR_LIMIT] rescue ""
      all_content += "\n" + samples.join("\n")

      lines = ["PROJECT CONVENTIONS (mimic exactly — do not invent new patterns):"]
      lines << "- Frozen string literals: #{frozen_string_style(all_content)}"
      lines << "- Module pattern: #{module_pattern(all_content)}"
      lines << "- Indent: #{indent_style(all_content)}"
      lines << "- Error handling: #{error_handling_style(all_content)}"
      lines << "- Return values: #{return_style(all_content)}"
      lines << "- Naming: #{naming_style(rb_files)}"
      lines.join("\n")
    rescue StandardError
      ""
    end

    class << self
      private

      def frozen_string_style(content)
        ratio = content.scan(/# frozen_string_literal: true/).size.to_f /
                [content.scan(/^# frozen/).size + 1, 1].max
        ratio >= 0.8 ? "always present on line 1" : "sometimes present"
      end

      def module_pattern(content)
        extend_count  = content.scan(/extend self/).size
        modfunc_count = content.scan(/module_function/).size
        if extend_count > modfunc_count
          "extend self (NOT module_function)"
        elsif modfunc_count > extend_count
          "module_function"
        else
          "mixed — prefer extend self per rubocop config"
        end
      end

      def indent_style(content)
        two   = content.scan(/^  \w/).size
        four  = content.scan(/^    \w/).size
        two >= four ? "2 spaces" : "4 spaces"
      end

      def error_handling_style(content)
        result_count = content.scan(/Result\.ok|Result\.err/).size
        raise_count  = content.scan(/raise\s+\w/).size
        if result_count > raise_count
          "Result monad (Result.ok / Result.err) — prefer over exceptions"
        else
          "raise/rescue exceptions"
        end
      end

      def return_style(content)
        content.include?("Result.ok") ? "wrap returns in Result.ok(value) / Result.err(message)" : "plain return values"
      end

      def naming_style(rb_files)
        snake = rb_files.count { |f| File.basename(f, ".rb") =~ /^[a-z][a-z0-9_]*$/ }
        camel = rb_files.count { |f| File.basename(f, ".rb") =~ /^[A-Z]/ }
        snake >= camel ? "snake_case files, CamelCase classes/modules" : "CamelCase files"
      end
    end
  end
end
