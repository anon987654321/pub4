# frozen_string_literal: true

module Master
  module Judge
    module Scan
      module Rules

        RuleDSL.rule :CONST_BY_DEFAULT,
          severity: :warning, tags: %i[IMMUTABLE], applies_to: %i[javascript],
          description: "use const unless reassigned" do |src, path:|
          scan_lines(src, /\blet\s+(\w+)\s*=/, message: "let — use const unless value is reassigned")
        end

        RuleDSL.rule :NULLISH_COALESCING,
          severity: :info, tags: %i[READABILITY], applies_to: %i[javascript],
          description: "use ?? over || for defaults" do |src, path:|
          scan_lines(src, /(\w+)\s*\|\|\s*\w+/, message: "foo || default — use foo ?? default to avoid falsy traps")
        end

        RuleDSL.rule :TEMPLATE_LITERALS,
          severity: :warning, tags: %i[READABILITY], applies_to: %i[javascript],
          description: "use template literals over concatenation" do |src, path:|
          scan_lines(src, /["']\s*\+\s*\w+\s*\+\s*["']/,
                     message: "string concatenation — use template literal \`…\${var}…\`")
        end

        RuleDSL.rule :ASYNC_AWAIT,
          severity: :warning, tags: %i[READABILITY], applies_to: %i[javascript],
          description: "prefer async/await over .then chains" do |src, path:|
          scan_lines(src, /\.then\(.*\.then\(.*\.then\(/, message: "3+ .then chain — convert to async/await")
        end

        RuleDSL.rule :FOR_OF,
          severity: :error, tags: %i[CORRECTNESS], applies_to: %i[javascript],
          description: "use for...of instead of for...in for arrays" do |src, path:|
          scan_lines(src, /for\s*\(\s*(const|let|var)\s+\w+\s+in\s+/,
            message: "for...in iterates keys — use for...of for array values")
        end

        RuleDSL.rule :QUOTE_VARIABLES,
          severity: :error, tags: %i[ROBUSTNESS], applies_to: %i[zsh],
          description: "always quote $variables" do |src, path:|
          scan_lines(src, /(?<!["'\\])\$\w+(?!["'])/, message: "unquoted $variable — wrap in double quotes")
        end

        RuleDSL.rule :DOUBLE_BRACKET,
          severity: :warning, tags: %i[ROBUSTNESS], applies_to: %i[zsh],
          description: "use [[ ]] over [ ]" do |src, path:|
          scan_lines(src, /(?<!\[)\[\s+[^\[]/, message: "[ ] test — use [[ ]] in zsh")
        end

        RuleDSL.rule :DOLLAR_PAREN,
          severity: :warning, tags: %i[READABILITY], applies_to: %i[zsh],
          description: "replace backticks with $(command)" do |src, path:|
          scan_lines(src, /`[^`]+`/, message: "backtick substitution — use $(command) for clarity")
        end

        RuleDSL.rule :NO_VAR,
          severity: :error, tags: %i[CORRECTNESS], applies_to: %i[javascript],
          description: "var is function-scoped and hoisted — use const or let" do |src, path:|
          scan_lines(src, /\bvar\s+\w/, message: "var declaration — use const (default) or let (when reassigned)")
        end

        RuleDSL.rule :JS_MODULE_SIZE,
          severity: :warning, tags: %i[SMALL_PARTS], applies_to: %i[javascript],
          description: "JS files over 300 lines — split at module boundaries" do |src, path:|
          line_count = src.lines.size
          next [] if line_count <= 300
          [finding(line: 1, message: "JS file #{line_count} lines — split at 300; extract cohesive modules")]
        end

      # A02 MAGIC_COLOR — raw color values must reference design tokens (MAGIC_COLOR).
        RuleDSL.rule :MAGIC_COLOR,
          severity: :warning, tags: %i[DESIGN], applies_to: %i[css scss javascript html],
          description: "color values must reference design tokens, not raw hex/rgb" do |src, path:|
          next [] if path.to_s.match?(%r{/spec/|/test/})
          findings = scan_lines(src, /#[0-9a-fA-F]{3,6}\b/, message: "raw hex color — use CSS custom property or design token")
          findings += scan_lines(src, /\brgba?\s*\(/, message: "raw rgb() color — use CSS custom property or design token")
          findings += scan_lines(src, /\bhsla?\s*\(/, message: "raw hsl() color — use CSS custom property or design token")
          findings
        end

      # A11 OPTIONAL_CHAINING_JS — && guard chains in JavaScript (OPTIONAL_CHAINING).
        RuleDSL.rule :OPTIONAL_CHAINING_JS,
          severity: :warning, tags: %i[READABILITY], applies_to: %i[javascript],
          description: "use ?. over && chains" do |src, path:|
          scan_lines(src, /(\w+)\s*&&\s*\1\.\w+/, message: "nil-guard chain — use optional chaining (?.) instead")
        end

      end
    end
  end
end
