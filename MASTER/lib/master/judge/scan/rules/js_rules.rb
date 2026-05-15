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

  RuleDSL.rule :OPTIONAL_CHAINING,
    severity: :warning, tags: %i[READABILITY], applies_to: %i[javascript],
    description: "use ?. over && chains" do |src, path:|
    scan_lines(src, /(\w+)\s*&&\s*\1\.\w+/, message: "foo && foo.bar — use foo?.bar")
  end

  RuleDSL.rule :NULLISH_COALESCING,
    severity: :info, tags: %i[READABILITY], applies_to: %i[javascript],
    description: "use ?? over || for defaults" do |src, path:|
    scan_lines(src, /(\w+)\s*\|\|\s*\w+/, message: "foo || default — use foo ?? default to avoid falsy traps")
  end

  RuleDSL.rule :TEMPLATE_LITERALS,
    severity: :warning, tags: %i[READABILITY], applies_to: %i[javascript],
    description: "use template literals over concatenation" do |src, path:|
    scan_lines(src, /["']\s*\+\s*\w+\s*\+\s*["']/, message: "string concatenation — use template literal `...${var}...`")
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

  end
  end
  end
end
