# frozen_string_literal: true

module Master
  module Judge
  module Scan
  module Rules
  # Lexical rules defined via RuleDSL — pure Ruby, no YAML.
  # Each auto-registers in Rule.registry and runs on every scan.

  RuleDSL.rule :NO_DEBUG,
    severity: :error, tags: %i[CLEAN_CODE], applies_to: %i[ruby],
    description: "no debug breakpoints in committed code" do |src, path:|
    scan_lines(src, /\b(binding\.pry|debugger|byebug|binding\.irb)\b/, message: "debug breakpoint")
  end

  RuleDSL.rule :NO_PUTS,
    severity: :warning, tags: %i[CLEAN_CODE], applies_to: %i[ruby],
    description: "no bare puts in library code" do |src, path:|
    next [] if path.to_s.match?(%r{/exe/|/spec/|/bin/})
    scan_lines(src, /^\s*puts\b(?!\s*\()/, message: "bare puts — use event bus or logger")
  end

  RuleDSL.rule :FROZEN_LITERAL,
    severity: :warning, tags: %i[PERFORMANCE], applies_to: %i[ruby],
    description: "missing frozen_string_literal magic comment" do |src, path:|
    next [] if src.lines.first&.include?("frozen_string_literal")
    [finding(line: 1, message: "add # frozen_string_literal: true")]
  end

  RuleDSL.rule :LONG_LINE,
    severity: :info, tags: %i[READABILITY], autofix: false,
    description: "lines exceeding 120 characters" do |src, path:|
    src.each_line.with_index(1).filter_map { |line, n|
      finding(line: n, message: "line #{line.chomp.length} chars (max 120)") if line.chomp.length > 120
    }
  end

  RuleDSL.rule :TRAILING_WHITESPACE,
    severity: :info, tags: %i[HYGIENE],
    description: "trailing whitespace" do |src, path:|
    src.each_line.with_index(1).filter_map { |line, n|
      finding(line: n, message: "trailing whitespace") if line.match?(/[ \t]+\n?\z/)
    }
  end

  RuleDSL.rule :TODO_FIXME,
    severity: :info, tags: %i[COMPLETENESS], autofix: false,
    description: "unresolved TODO/FIXME markers" do |src, path:|
    scan_lines(src, /\b(TODO|FIXME|HACK|XXX)\b/, message: "unresolved marker — resolve or delete")
  end

  RuleDSL.rule :RESCUE_EXCEPTION,
    severity: :warning, tags: %i[ERROR_HANDLING], applies_to: %i[ruby],
    description: "rescue StandardError not Exception" do |src, path:|
    scan_lines(src, /rescue\s+Exception\b/, message: "rescue Exception catches signals — use StandardError")
  end

  RuleDSL.rule :EMPTY_RESCUE,
    severity: :error, tags: %i[ERROR_HANDLING FAIL_VISIBLY], applies_to: %i[ruby],
    description: "empty rescue swallows errors silently" do |src, path:|
    src.each_line.with_index(1).filter_map { |line, n|
      finding(line: n, message: "empty rescue — use Ground::Swallow.log or re-raise") if line.match?(/^\s*rescue\s*$/) || line.match?(/rescue\s+\S+\s*$/) && !line.match?(/=>/)
    }
  end

  RuleDSL.rule :CONSECUTIVE_BLANK_LINES,
    severity: :info, tags: %i[HYGIENE],
    description: "no consecutive blank lines" do |src, path:|
    findings = []
    prev_blank = false
    src.each_line.with_index(1) { |line, n|
      blank = line.strip.empty?
      findings << finding(line: n, message: "consecutive blank line") if blank && prev_blank
      prev_blank = blank
    }
    findings
  end
  end
  end
  end
end
