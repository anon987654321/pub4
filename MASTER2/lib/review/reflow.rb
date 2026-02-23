# frozen_string_literal: true

# ReflowProcessor — LLM-driven importance ordering pass.
# Reorders a file's sections top-to-bottom by descending importance,
# following the INVERTED_PYRAMID axiom and design_codex importance_flow rules.
#
# Public interface first:
#   ReflowProcessor.call(path:)  → Result with :content and :path
#   ReflowProcessor.call(code:, filename:) → Result with :content

module MASTER
  module Review
    module ReflowProcessor
      extend self

      EXTMAP = {
        ".rb"   => "Ruby",
        ".yml"  => "YAML",
        ".yaml" => "YAML",
        ".zsh"  => "Zsh",
        ".md"   => "Markdown",
      }.freeze

      # Rules hoisted from design_codex importance_flow — keeps prompt grounded.
      ORDERING_RULES = {
        "Ruby" => <<~RULES,
          1. `# frozen_string_literal: true` comment
          2. require / require_relative statements
          3. Module/class constants (SCREAMING_SNAKE_CASE)
          4. Class-level DSL (attr_*, validates, belongs_to, has_many…)
          5. Public class methods (.new, .call, .build…)
          6. Public instance methods — primary interface first
          7. protected methods
          8. private methods — most-called first, one-liners last
          Within every method body:
            guard clauses → setup → core logic → result → rescue → cleanup
          Arguments: required positional → optional positional → required keyword → optional keyword → &block
        RULES
        "YAML" => <<~RULES,
          1. Metadata (version, name, description)
          2. ABSOLUTE protection entries
          3. PROTECTED entries
          4. ADJUSTABLE entries
          5. Examples, templates, commentary
        RULES
        "Zsh" => <<~RULES,
          1. #!/usr/bin/env zsh
          2. set -euo pipefail + setopt declarations
          3. Configuration constants
          4. main() function definition
          5. Helper function definitions (in call order)
          6. main "$@" call site
        RULES
        "Markdown" => <<~RULES,
          1. # Title — single line
          2. One-sentence summary
          3. Key concept or TL;DR
          4. Usage / quickstart
          5. Reference / details
          6. Edge cases / appendix
        RULES
      }.freeze

      def call(path: nil, code: nil, filename: nil)
        if path
          return Result.err("File not found: #{path}") unless File.exist?(path)

          filename = File.basename(path)
          code     = File.read(path)
        end

        return Result.err("No code provided") unless code && filename

        ext      = File.extname(filename)
        lang     = EXTMAP[ext]
        return Result.err("Unsupported filetype: #{ext}") unless lang

        return Result.err("LLM not available") unless defined?(LLM)

        rules   = ORDERING_RULES.fetch(lang, "")
        prompt  = build_prompt(code, lang, rules)
        result  = LLM.ask(prompt, tier: :standard)
        return result unless result.ok?

        reflowed = strip_fences(result.value[:content])

        if path
          File.write(path, reflowed)
          Result.ok(content: reflowed, path: path)
        else
          Result.ok(content: reflowed, filename: filename)
        end
      end

      private

      def build_prompt(code, lang, rules)
        <<~PROMPT
          You are a #{lang} code editor applying the Inverted Pyramid layout principle.
          Reorder this #{lang} file top-to-bottom by descending importance.

          Importance ordering rules for #{lang}:
          #{rules}

          Requirements:
          - Preserve ALL logic exactly — only reorder sections/blocks
          - Do NOT change any expressions, method bodies, or data values
          - Do NOT add or remove any code
          - Output the complete reflowed file and nothing else
          - No explanations, no markdown fences

          File to reflow:
          ```#{lang.downcase}
          #{code}
          ```
        PROMPT
      end

      def strip_fences(text)
        text
          .sub(/\A```[a-z]*\n/, "")
          .sub(/\n```\z/, "")
          .strip
          .concat("\n")
      end
    end
  end
end
