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
    next [] if path.to_s.include?("/judge/scan/rules/")
    scan_lines(src, /\b(binding\.pry|debugger|byebug|binding\.irb)\b/, message: "debug breakpoint")
  end

  RuleDSL.rule :NO_PUTS,
    severity: :warning, tags: %i[CLEAN_CODE], applies_to: %i[ruby],
    description: "no bare puts in library code" do |src, path:|
    next [] if path.to_s.match?(%r{/exe/|/spec/|/bin/|/now/cli})
    scan_lines(src, /^\s*puts\b(?!\s*\()/, message: "bare puts — use event bus or logger")
  end

  RuleDSL.rule :FROZEN_LITERAL,
    severity: :warning, tags: %i[PERFORMANCE], applies_to: %i[ruby],
    description: "missing frozen_string_literal magic comment" do |src, path:|
    next [] if src.lines.first&.include?("frozen_string_literal")
    magic = "# frozen_string_literal: true"
    [finding(line: 1, message: "add #{magic}")]
  end

  RuleDSL.rule :LONG_LINE,
    severity: :info, tags: %i[READABILITY], autofix: false,
    description: "lines exceeding 120 characters" do |src, path:|
    next [] if path.to_s.match?(%r{/voice/personality\.rb|/reach/llm\.rb})
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
    description: "unresolved work markers" do |src, path:|
    next [] if path.to_s.include?("/judge/scan/rules/")
    scan_lines(src, /\b(TODO|FIXME|HACK|XXX)\b/, message: "unresolved marker — resolve or delete")
  end

  RuleDSL.rule :RESCUE_EXCEPTION,
    severity: :warning, tags: %i[ERROR_HANDLING], applies_to: %i[ruby],
    description: "rescue StandardError not Exception" do |src, path:|
    scan_lines(src, /rescue\s+Exception\b/, message: "catches signals — use StandardError")
  end

  RuleDSL.rule :EMPTY_RESCUE,
    severity: :error, tags: %i[ERROR_HANDLING FAIL_VISIBLY], applies_to: %i[ruby],
    description: "empty rescue swallows errors silently" do |src, path:|
    src.each_line.with_index(1).filter_map { |line, n|
      bare_rescue   = line.match?(/^\s*rescue\s*$/)
      naked_class   = line.match?(/^\s*rescue\s+\S+\s*$/) && !line.match?(/=>/)
      finding(line: n, message: "empty rescue — use Ground::Swallow.log or re-raise") if bare_rescue || naked_class
    }
  end

<<<<<<< HEAD
  # Regexes hoisted out of the per-call hot path (HOIST).
  RESCUE_DISCARD = /\A(nil|false|0|\[\]|\{\}|next|return|return\s+(nil|false|0|\[\]|\{\})|raise)?\z/
  RESCUE_SINK    = /\b(raise\b|Swallow\.log|\.publish\b|\bwarn\b|\blog\b|Diag\b|Result\.err)/
  RESCUE_HEAD    = /^(\s*)rescue\b([^;#]*?)(?:=>\s*(\w+))?\s*(?:;\s*(.*))?$/

  # 1-based line numbers of rescues whose handler discards the error.
  def self.silent_rescue_lines(src, blanket_only:)
    lines = src.lines
    lines.each_with_index.filter_map do |line, idx|
      m = RESCUE_HEAD.match(line)
      next unless m && rescue_in_scope?(m[2].to_s.strip, blanket_only)
      body = rescue_body(lines, idx, m[4].to_s.strip)
      next unless rescue_silent?(body, m[3])
      [idx + 1, m[3], m[2].to_s.strip]
    end
  end

  # Blanket = bare rescue or StandardError/Exception only; narrow = a named class.
  def self.rescue_in_scope?(classes, blanket_only)
    blanket = classes.empty? ||
              classes.split(",").map(&:strip).all? { |c| %w[StandardError Exception].include?(c) }
    blanket_only ? blanket : !blanket
  end

  # Handler body — the inline `; expr` form, or lines down to the matching end.
  def self.rescue_body(lines, idx, inline)
    return [inline] unless inline.empty?
    collected = []
    ((idx + 1)...lines.size).each do |j|
      stripped = lines[j].strip
      break if stripped.match?(/\A(end|else|ensure|rescue)\b/)
      collected << stripped unless stripped.empty? || stripped.start_with?("#")
    end
    collected
  end

  # Silent: body discards, never names the error, never reaches a sink.
  def self.rescue_silent?(body, err_name)
    return false unless body.reject { |b| b.match?(RESCUE_DISCARD) }.empty?
    return false if err_name && body.any? { |b| b.match?(/\b#{Regexp.escape(err_name)}\b/) }
    body.none? { |b| b.match?(RESCUE_SINK) }
  end

  RuleDSL.rule :SILENT_RESCUE,
    severity: :error, tags: %i[ERROR_HANDLING FAIL_VISIBLY], applies_to: %i[ruby],
    autofix: false,
    description: "blanket rescue discards the error instead of logging or re-raising" do |src, path:|
    next [] if path.to_s.include?("/judge/scan/rules/")
    Rules.silent_rescue_lines(src, blanket_only: true).map do |line, err_name, _classes|
      hint = err_name ? "rescue binds #{err_name} but never uses it" : "blanket rescue discards the error"
      finding(line:, message: "#{hint} — use Ground::Swallow.log or re-raise")
    end
  end

  RuleDSL.rule :NARROW_SILENT_RESCUE,
    severity: :warning, tags: %i[ERROR_HANDLING FAIL_VISIBLY], applies_to: %i[ruby],
    autofix: false,
    description: "narrow rescue discards the error — confirm the case is truly expected" do |src, path:|
    next [] if path.to_s.include?("/judge/scan/rules/")
    Rules.silent_rescue_lines(src, blanket_only: false).map do |line, _err_name, classes|
      finding(line:, message: "rescue #{classes} discards the error — " \
                              "Ground::Swallow.log it if expected, re-raise if not")
    end
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

  RuleDSL.rule :DEBUG_OUTPUT,
    severity: :error, tags: %i[FAIL_VISIBLY], applies_to: %i[ruby],
    description: "debug output left in lib/" do |src, path:|
    next [] unless path.to_s.include?("/lib/")
    next [] if path.to_s.include?("/judge/scan/rules/")
    findings = scan_lines(src, /^\s*pp?\s+(?!self\b)/, message: "p/pp debug call — remove or publish via event bus")
    findings += scan_lines(src, /\$stderr\.puts\b/, message: "$stderr.puts — use @bus.publish or $stdout")
    findings
  end

  RuleDSL.rule :TRAILING_COMMENT,
    severity: :info, tags: %i[BE_CONCISE],
    description: "trailing comment after code" do |src, path:|
    src.each_line.with_index(1).filter_map { |line, n|
      next if line.strip.start_with?("#")
      finding(line: n, message: "trailing comment — promote above the line or delete") if line.match?(/\S\s+#\s+\S/)
    }
  end

  RuleDSL.rule :TIME_ZONE_UNSAFE,
    severity: :warning, tags: %i[ROBUSTNESS], applies_to: %i[ruby],
    description: "bare Time.now/Date.today bypasses Rails Time.zone" do |src, path:|
    next [] unless path.match?(%r{/app/|/spec/|/test/})
    findings  = scan_lines(src, /(?<![A-Za-z_.])Time\.now\b/,
                           message: "Time.now ignores Time.zone — use Time.current")
    findings += scan_lines(src, /(?<![A-Za-z_.])Date\.today\b/,
                           message: "Date.today ignores Time.zone — use Date.current")
    findings += scan_lines(src, /(?<![A-Za-z_.])DateTime\.now\b/,
                           message: "DateTime.now — use Time.current.to_datetime")
    findings
  end

  RuleDSL.rule :NO_ASCII_LINE_ART,
    severity: :warning, tags: %i[BE_CONCISE],
    description: "ASCII divider decorations" do |src, path:|
    scan_lines(src, /(?:^|\s)(?:={3,}|-{3,})(?:\s|$)/, message: "remove ASCII divider decorations")
  end
  end
  end
  end
end
