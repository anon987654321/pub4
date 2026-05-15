# frozen_string_literal: true

module Master
  module Judge
  module Scan
  module Rules

  RuleDSL.rule :NO_MULTIPLE_LANGUAGES,
    severity: :warning, tags: %i[SMALL_PARTS],
    description: "one medium per artifact" do |src, path:|
    scan_lines(src, /<%|<script|<style|SQL|HEREDOC/,
      message: "mixed medium — extract to a dedicated file")
  end

  RuleDSL.rule :SAFE_NAVIGATION,
    severity: :warning, tags: %i[READABILITY],
    description: "use null-safe navigation over nil-guard && chains" do |src, path:|
    scan_lines(src, /(\w+)\s*&&\s*\1\.\w+/,
      message: "foo && foo.bar — use foo&.bar (Ruby) or foo?.bar (JS/TS)")
  end

  RuleDSL.rule :FEW_ARGUMENTS,
    severity: :warning, tags: %i[SMALL_PARTS],
    description: "ideal is zero to two arguments" do |src, path:|
    scan_lines(src, /def \w+\([^)]*,[^:)]+,[^:)]+,[^:)]+\)/,
      message: "4+ positional args — refactor into keyword args or a value object")
  end

  RuleDSL.rule :KEYWORD_ARGS,
    severity: :info, tags: %i[SMALL_PARTS],
    description: "keyword arguments for 3+ parameters" do |src, path:|
    scan_lines(src, /def \w+\([^)]*,\s*[^:)]+,\s*[^:)]+,\s*[^:)]+\)/,
      message: "3+ positional args — use keyword arguments")
  end

  RuleDSL.rule :N_PLUS_ONE,
    severity: :warning, tags: %i[PERFORMANCE],
    description: "loading records one-by-one inside a loop" do |src, path:|
    scan_lines(src, /\.(each|map|collect)\s*(do|\{).*\.\w+\.\w+/,
      message: "N+1 query candidate — use includes/eager_load or equivalent")
  end

  RuleDSL.rule :NO_FLAG_ARGUMENTS,
    severity: :warning, tags: %i[SMALL_PARTS],
    description: "a flag that selects behavior means two things hiding as one" do |src, path:|
    scan_lines(src, /def \w+\([^)]*\btrue\b|def \w+\([^)]*\bfalse\b/,
      message: "boolean flag arg — split into two methods")
  end

  RuleDSL.rule :LAW_OF_DEMETER,
    severity: :warning, tags: %i[COUPLING],
    description: "only talk to immediate friends" do |src, path:|
    scan_lines(src, /\w+\.\w+\.\w+\.\w+/,
      message: "4-level chain — introduce a local variable or delegation")
  end

  RuleDSL.rule :MEANINGFUL_NAMES,
    severity: :info, tags: %i[READABILITY],
    description: "names reveal intent" do |src, path:|
    scan_lines(src, /\b(tmp|temp|data|result|val|ret|obj|str|arr|buf)\b\s*=/,
      message: "generic name — use a name that reveals intent")
  end

  RuleDSL.rule :WHY_NOT_WHAT,
    severity: :info, tags: %i[BE_CONCISE],
    description: "comments explain why, not what" do |src, path:|
    scan_lines(src, /#\s*(increment|set|get|update|return|initialize|create|add)\s+\w+/,
      message: "comment describes what the code does — explain why instead")
  end

  RuleDSL.rule :TYPOGRAPHIC_EXCELLENCE,
    severity: :info, tags: %i[TYPOGRAPHY],
    description: "typographic excellence in user-facing text" do |src, path:|
    scan_lines(src, /["']\.\.\.[\"']|["']--["']/,
      message: "ASCII typography — use Unicode ellipsis … and em dash —")
  end

  RuleDSL.rule :TYPOGRAPHY_DISCIPLINE,
    severity: :info, tags: %i[TYPOGRAPHY],
    description: "hierarchy via weight and brightness, not decoration" do |src, path:|
    scan_lines(src, /[-=]{3,}|[╭╮╰╯│─]/,
      message: "ASCII decoration — use whitespace and typographic weight instead")
  end

  RuleDSL.rule :NULL_BLINDNESS,
    severity: :error, tags: %i[CORRECTNESS],
    description: "comparisons against nullable columns must use IS NULL" do |src, path:|
    scan_lines(src, /= NULL|!= NULL|== nil.*column|column.*== nil/,
      message: "NULL comparison — use IS NULL / IS NOT NULL in SQL; .nil? in Ruby")
  end

  RuleDSL.rule :SECRET_PROXIMITY,
    severity: :error, tags: %i[SECURITY],
    description: "secrets and consumers must not share a file" do |src, path:|
    scan_lines(src, /(password|secret|token|api_key|private_key)\s*=\s*['"][^'"]{8,}/,
      message: "hardcoded secret — move to environment variable or secrets manager")
  end

  RuleDSL.rule :MAGIC_COLOR,
    severity: :warning, tags: %i[MAINTAINABILITY],
    description: "color values must reference design tokens, not raw hex/rgb" do |src, path:|
    scan_lines(src, /#[0-9a-fA-F]{3,6}\b|rgb\(|rgba\(|hsl\(/,
      message: "raw color value — reference a CSS custom property or design token")
  end

  RuleDSL.rule :UNBOUNDED_RETRY,
    severity: :error, tags: %i[ROBUSTNESS],
    description: "retry loops must have a max_attempts cap and backoff" do |src, path:|
    scan_lines(src, /\bretry\b|loop\s*do|while\s+true/,
      message: "unbounded retry/loop — add max_attempts cap and exponential backoff")
  end

  end
  end
  end
end
