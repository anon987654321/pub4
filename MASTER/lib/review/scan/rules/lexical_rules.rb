# frozen_string_literal: true

module Master
  module Review
  module Scan
  module Rules
  # Lexical rules defined via RuleDSL — pure Ruby, no YAML.
  # Each auto-registers in Rule.registry and runs on every scan.

  RuleDSL.rule :NO_DEBUG,
    severity: :error, tags: %i[CLEAN_CODE], applies_to: %i[ruby],
    description: "no debug breakpoints in committed code" do |src, path:|
    next [] if path.to_s.include?("/review/scan/rules/")
    scan_lines(src, /\b(binding\.pry|debugger|byebug|binding\.irb)\b/, message: "debug breakpoint")
  end

  RuleDSL.rule :NO_PUTS,
    severity: :warning, tags: %i[CLEAN_CODE], applies_to: %i[ruby],
    description: "no bare puts in library code" do |src, path:|
    # The REPL prints for a living, so the path it lives at is exempt. This
    # exemption carries the whole of lib/cli/session/ -- 100 deliberate puts --
    # and it has to move whenever that directory does. An exemption whose
    # subject moves out from under it is a gate that starts firing on exactly
    # what it exempted: when lib/now/ became lib/cli/ and this address stayed,
    # 105 findings arrived in selfcheck's largest actionable bucket overnight.
    next [] if path.to_s.match?(%r{/exe/|/spec/|/bin/|/cli/session})
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
    next [] if path.to_s.match?(%r{/voice/personality\.rb|/io/llm\.rb})
    src.each_line.with_index(1).filter_map do |line, n|
      finding(line: n, message: "line #{line.chomp.length} chars (max 120)") if line.chomp.length > 120
    end
  end

  RuleDSL.rule :TRAILING_WHITESPACE,
    severity: :info, tags: %i[HYGIENE],
    fires: "value = 1   \n",
    does_not_fire: "value = 1\n\n",
    description: "trailing whitespace" do |src, path:|
    src.each_line.with_index(1).filter_map do |line, n|
      finding(line: n, message: "trailing whitespace") if line.match?(/[ \t]+\n?\z/)
    end
  end

  RuleDSL.rule :TODO_FIXME,
    severity: :info, tags: %i[COMPLETENESS], autofix: false,
    description: "unresolved work markers" do |src, path:|
    next [] if path.to_s.include?("/review/scan/rules/")
    # The lookahead keeps TODO.md, the repo-wide backlog, from reading as a
    # marker — see data/rules.yml `unfinished`, which learned this at :veto.
    scan_lines(src, /\b(TODO|FIXME|HACK|XXX)\b(?!\.md)/, message: "unresolved marker — resolve or delete")
  end

  RuleDSL.rule :RESCUE_EXCEPTION,
    severity: :warning, tags: %i[ERROR_HANDLING], applies_to: %i[ruby],
    description: "rescue StandardError not Exception" do |src, path:|
    scan_lines(src, /rescue\s+Exception\b/, message: "catches signals — use StandardError")
  end

  RuleDSL.rule :SILENT_RESCUE,
    severity: :error, tags: %i[ERROR_HANDLING FAIL_VISIBLY], applies_to: %i[ruby],
    description: "blanket rescue discards error without logging or re-raising" do |src, path:|
    # No path exemption for the scanner's own rules: a rule that returns [] on
    # error calls the file it failed on clean, so a swallow costs more in this
    # directory than anywhere else. The one exception is the rule's own test,
    # which must spell every shape it proves — the law-conduct argument.
    next [] if path.to_s.match?(/test_silent_rescue_rule\.rb\z|test_self_test\.rb\z/)
    SilentRescue.scan(src, narrow: false).map { |hit| finding(line: hit[:line], message: hit[:message]) }
  end

  RuleDSL.rule :NARROW_SILENT_RESCUE,
    severity: :warning, tags: %i[ERROR_HANDLING], applies_to: %i[ruby],
    description: "narrow-class rescue discards error without logging or re-raising" do |src, path:|
    SilentRescue.scan(src, narrow: true).map { |hit| finding(line: hit[:line], message: hit[:message]) }
  end

  # EMPTY_RESCUE was deleted here on 2026-08-12. It shared SilentRescue's
  # discard_body? predicate with the two rules above and differed only in which
  # `rescue` lines it matched, so every finding it produced was already produced
  # by one of them: measured across MASTER at 37 findings, 0 unique. Its own
  # comment claimed it "doesn't re-flag what those already catch"; it re-flagged
  # all 37.
  #
  # It also made severity depend on comma count. Its naked-class branch matched
  # `rescue\s+\S+` — one token — so `rescue Errno::ESRCH` was an ERROR while the
  # identical `rescue Errno::ESRCH, Errno::EPERM` was only NARROW_SILENT_RESCUE's
  # warning. 8 sites carried both severities at once.
  #
  # Coverage is unchanged by construction, not just by measurement, and
  # test_scan_rule_false_positives.rb pins each shape: bare `rescue`,
  # `rescue StandardError` and `rescue Exception` fall to SILENT_RESCUE's
  # non-narrow branch; any other class name, scoped or not, matches
  # NARROW_SILENT_RESCUE.

  RuleDSL.rule :CONSECUTIVE_BLANK_LINES,
    severity: :info, tags: %i[HYGIENE],
    fires: "a = 1\n\n\nb = 2\n",
    does_not_fire: "a = 1\n\nb = 2\n",
    description: "no consecutive blank lines" do |src, path:|
    findings = []
    prev_blank = false
    src.each_line.with_index(1) do |line, n|
      blank = line.strip.empty?
      findings << finding(line: n, message: "consecutive blank line") if blank && prev_blank
      prev_blank = blank
    end
    findings
  end

  RuleDSL.rule :DEBUG_OUTPUT,
    severity: :error, tags: %i[FAIL_VISIBLY], applies_to: %i[ruby],
    description: "debug output left in lib/" do |src, path:|
    next [] unless path.to_s.include?("/lib/")
    next [] if path.to_s.include?("/scan/rules/")
    # `p` is a legal variable name, so a line starting `p <<` is an append to a
    # local, not a Kernel#p call. The old pattern read both the same way and
    # flagged attention_context.rb's `p << "zoom: …"` twice — an error-severity,
    # auto_fix=true rule pointed at correct code. Anything whose next token is an
    # assignment, append or comparison operator is the variable, not the call.
    findings = scan_lines(src, /^\s*pp?\s+(?!self\b)(?!<<|==|!=|\|\|=|&&=|[+\-*\/%|&^]?=)/,
      message: "p/pp debug call — remove or publish via event bus")
    findings += scan_lines(src, /\$stderr\.puts\b/, message: "$stderr.puts — use @bus.publish or $stdout")
    findings
  end

  RuleDSL.rule :TRAILING_COMMENT,
    severity: :info, tags: %i[BE_CONCISE],
    description: "trailing comment after code" do |src, path:|
    src.each_line.with_index(1).filter_map do |line, n|
      next if line.strip.start_with?("#")
      finding(line: n, message: "trailing comment — promote above the line or delete") if line.match?(/\S\s+#\s+\S/)
    end
  end

  RuleDSL.rule :TIME_ZONE_UNSAFE,
    severity: :warning, tags: %i[ROBUSTNESS], applies_to: %i[ruby],
    description: "bare Time.now/Date.today bypasses Rails Time.zone",
    example_path: "/repo/app/models/example.rb",
    fires: "stamp = Time.now.beginning_of_day\n",
    does_not_fire: "generated_at: Time.now.utc.iso8601, exp: Time.now.to_i\n" do |src, path:|
    next [] unless path.match?(%r{/app/|/spec/|/test/})
    # Time.now.utc and Time.now.to_i do not read Time.zone: one converts to UTC
    # explicitly, the other is epoch seconds. Every RAILS finding this rule
    # produced was one of those two forms — JWT exp/iat, a tmpfile suffix, and
    # generated_at timestamps already pinned to .utc — so the rule was reporting
    # 13 rewrites that would have changed no behaviour at all.
    findings = scan_lines(src, /(?<![A-Za-z_.])Time\.now\b(?!\s*\.\s*(?:utc|to_i|to_f|to_r))/,
                           message: "Time.now ignores Time.zone — use Time.current")
    findings += scan_lines(src, /(?<![A-Za-z_.])Date\.today\b/,
                           message: "Date.today ignores Time.zone — use Date.current")
    findings += scan_lines(src, /(?<![A-Za-z_.])DateTime\.now\b/,
                           message: "DateTime.now — use Time.current.to_datetime")
    findings
  end

  # `a === b` is JavaScript's identity operator and Ruby's case-equality, and it
  # is exactly three `=` with a space each side — which is what the divider
  # pattern below matches. 486 of this rule's 636 findings across the four trees
  # were `mode === "speaking"` and its like, three quarters of everything it
  # reported. An operand on both sides is what separates the operator from a
  # decoration: a real divider has nothing to its right, or is a longer run, and
  # no dropped line carried a run of four or more.
  IDENTITY_COMPARISON = /[\w)\]}'"]\s*===\s*[\w({\[!'"@$:]/

  RuleDSL.rule :NO_ASCII_LINE_ART,
    severity: :warning, tags: %i[BE_CONCISE],
    description: "ASCII divider decorations" do |src, path:|
    next [] if path.to_s.match?(%r{(^|/)(test|spec)/})

    scan_lines(src, /(?:^|\s)(?:={3,}|-{3,}|_{3,})(?:\s|$)/, message: "remove ASCII divider decorations").reject do |finding|
      line = src.lines[finding[:line].to_i - 1].to_s
      path.to_s.end_with?(".yml", ".yaml") && line.strip == "---" ||
        line.match?(/\b(assert|refute|expect|must_|wont_)/) ||
        line.match?(IDENTITY_COMPARISON)
    end
  end

  module SilentRescue
    module_function

    def scan(src, narrow:)
      lines = src.lines
      lines.each_with_index.flat_map do |line, index|
        lineno = index + 1
        next [] if line.match?(/scan:\s*intentional\b/)
        next [] unless matches_mode?(line, narrow:)
        next [] unless discard_body?(lines, index)

        [{ line: lineno, message: "rescue discards error — log, re-raise, or return a meaningful value" }]
      end
    end

    def matches_mode?(line, narrow:)
      stripped = line.strip
      return false unless stripped.start_with?("rescue")

      if narrow
        stripped.match?(/\Arescue\s+(?!StandardError\b|Exception\b)[A-Za-z][\w:]*(?:\s*=>\s*\w+)?\b/)
      else
        return false if stripped.match?(/\Arescue\s+(?!StandardError\b|Exception\b)[A-Za-z][\w:]*(?:\s*=>\s*\w+)?\b/)

        stripped.match?(/\Arescue(?:\s+StandardError(?:\s*=>\s*\w+)?|\s+Exception(?:\s*=>\s*\w+)?)?\b/) ||
          stripped.match?(/\Arescue\s*;/)
      end
    end

    def discard_body?(lines, index)
      line = lines[index]
      if line.include?(";")
        tail = line.split(";", 2)[1].to_s.strip
        return discard_token?(tail) unless tail.empty?
      end

      ((index + 1)...lines.size).each do |i|
        body = lines[i].strip
        next if body.empty?
        return false if handled_body?(body)
        return false unless discard_token?(body)

        # In a predicate, false IS the handling: tts_healthy? rescuing to
        # false has absorbed the error into its answer — the health-check
        # idiom, not a swallow. The fleet's health endpoints carried seven
        # error-severity findings for degrading gracefully. Only nil/false
        # qualify; a predicate rescuing to [] is still discarding.
        return !(body.match?(/\A(?:nil|false)\s*\z/) && predicate_method?(lines, index))
      end
      false
    end

    def predicate_method?(lines, index)
      (index - 1).downto(0) do |i|
        name = lines[i][/^\s*def\s+(?:self\.)?(\w+[?!]?)/, 1]
        return name.end_with?("?") if name
      end
      false
    end

    # Swallow.log is written three ways in this tree: bare, Ground:: and
    # Master::Ground::. All three are a report, so all three are handled.
    def handled_body?(body)
      body.match?(/\A(?:raise\b|warn\b|logger\.|@bus\.publish|(?:Master::)?(?:Ground::)?Swallow\.log)/)
    end

    # `end` on the first non-blank line after a rescue means an empty body:
    # nothing can open between the two. An empty body discards completely.
    def discard_token?(body)
      body.match?(/\A(?:nil|false|\[\]|\{\}|_\w+|end)\s*\z/)
    end
  end
  end
  end
  end
end
