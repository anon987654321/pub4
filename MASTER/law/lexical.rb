# frozen_string_literal: true

module Master
  module Review
  module Scan
  module Laws
  # Lexical Laws whose detector is a `check` over the whole file; Law.load_all
  # loads them with law/, and the scanner runs every enforceable one.
  # Several are RuboCop-shaped and stay here rather than delegating to RuboCop:
  # each id is a name the law addresses, and delegating renames the law.

  # Defined before the Laws that call it: a Law proves its fixtures as it is defined.
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
    #
    # `next` is not in the list, and that is the same argument the predicate
    # exemption above makes. A rescue whose whole body is `next` sits in a loop
    # over members, and skipping the member IS the handling: the method's answer
    # is that this one contributed nothing. All 17 in the four trees are that
    # shape — a census walking files, a check walking hosts — and 16 of them
    # would land at error severity, so adding the token asks the fleet to
    # annotate its own idiom.
    def discard_token?(body)
      body.match?(/\A(?:nil|false|\[\]|\{\}|_\w+|end)\s*\z/)
    end
  end

  ::Law.define(:NO_DEBUG) do
    tags %i[CLEAN_CODE]
    fix "no debug breakpoints in committed code"
    bad "  binding.pry\n"
    good "debugger_enabled = false\n"
    check do |src, path|
      parsed = Prism.parse(src)
      next [] if parsed.failure?

      findings = []
      walk(parsed.value) do |node|
        if node.is_a?(Prism::CallNode) && node.name.to_s.match?(/^(pry|debugger|byebug|irb)$/)
          findings << finding(line: node.location.start_line, message: "debug breakpoint: #{node.name}")
        end
      end
      findings
    end
  end

  # A file that runs itself: `Tool.run(ARGV) if $PROGRAM_NAME == __FILE__`, or
  # the same guard opening a block or closing a `return unless`.
  PROGRAM_GUARD = /^[^#\n]*(?:\$PROGRAM_NAME|\$0|__FILE__)\s*==\s*(?:\$PROGRAM_NAME|\$0|__FILE__)\s*$/
  PROGRAM_PATH = %r{/test/|/db/seeds(?:\.rb\z|/)|\.rake\z|/Rakefile\z}

  ::Law.define(:NO_PUTS) do
    tags %i[CLEAN_CODE]
    fix "no puts, p or pp in library code"
    bad "  puts(\"ready\")\n"
    good "  @bus.publish(\"ready\")\n  p = point\n  p.x\n  p == q\n  p\n"
    check do |src, path|
      # The REPL prints for a living, so the path it lives at is exempt. This
      # exemption carries the whole of lib/cli/session/ -- 100 deliberate puts --
      # and it has to move whenever that directory does. An exemption whose
      # subject moves out from under it is a check that starts firing on exactly
      # what it exempted: when lib/now/ became lib/cli/ and this address stayed,
      # 105 findings arrived in selfcheck's largest actionable bucket overnight.
      next [] if path.to_s.match?(%r{/exe/|/spec/|/bin/|/cli/session})

      # A program's output is its interface, and the rule is about library code.
      # Measured over the four trees: 750 of 941 findings sat in a program — a
      # script with a shebang, a file that runs itself under a $PROGRAM_NAME
      # guard, a rake task, a seed file or a test — where `puts "ok: synced"` is
      # the line the operator reads and a logger would hide it.
      next [] if src.start_with?("#!") || src.match?(PROGRAM_GUARD) || path.to_s.match?(PROGRAM_PATH)

      parsed = Prism.parse(src)
      next [] if parsed.failure?

      findings = []
      walk(parsed.value) do |node|
        # A receiverless call only, so @bus.publish and io.puts are not debug output.
        next unless node.is_a?(Prism::CallNode) && node.receiver.nil? && node.name.to_s.match?(/^(puts|p|pp)$/)

        message = "debug output: #{node.name} — use event bus or logger"
        findings << finding(line: node.location.start_line, message:)
      end

      findings
    end
  end

  ::Law.define(:FROZEN_LITERAL) do
    tags %i[PERFORMANCE]
    fix "missing frozen_string_literal magic comment"
    bad "value = 1\n# frozen_string_literal: true\n"
    good "#!/usr/bin/env ruby\n# frozen_string_literal: true\n\nvalue = 1\n"
    check do |src, path|
      leading = src.each_line.take_while { |line| line.strip.empty? || line.lstrip.start_with?("#") }

      next [] if leading.any? { |line| line.include?("frozen_string_literal") }
      magic = "# frozen_string_literal: true"
      [finding(line: 1, message: "add #{magic}")]
    end
  end

  ::Law.define(:LONG_LINE) do
    tags %i[READABILITY]
    fix "lines exceeding 120 characters"
    bad "#{"x" * 121}\n"
    good "#{"x" * 120}\n#{"x" * 100} # scan: intentional — the marker is not the defect\n"
    check do |src, path|
      next [] if path.to_s.match?(%r{/voice/personality\.rb|/io/llm\.rb})

      src.each_line.with_index(1).filter_map do |line, n|
        next unless line.chomp.length > 120
        # Measured without the marker, so exempting a line does not create a
        # finding against the exemption.
        next unless without_scan_marker(line).length > 120

        finding(line: n, message: "line #{line.chomp.length} chars (max 120)")
      end
    end
  end

  ::Law.define(:TRAILING_WHITESPACE) do
    tags %i[HYGIENE]
    fix "trailing whitespace"
    bad "value = 1   \n"
    good "value = 1\n\n"
    check do |src, path|
      src.each_line.with_index(1).filter_map do |line, n|
        finding(line: n, message: "trailing whitespace") if line.match?(/[ \t]+\n?\z/)
      end
    end
  end

  ::Law.define(:TODO_FIXME) do
    tags %i[COMPLETENESS]
    fix "unresolved work markers"
    bad "  # FIXME: the retry has no cap\n"
    good "  # the reasoning is in TODO.md\n  MARKERS = /TODO|FIXME|XXX/\n"
    check do |src, path|
      # The lookahead keeps TODO.md, the repo-wide backlog, from reading as a
      # marker — see data/laws.yml `unfinished`, which learned this at :veto.
      #
      # A marker inside a regex literal is a detector, which is the reason this
      # rule already skips the directory it lives in — and detectors live outside
      # it too. Both of the tree's cases are that: personal_workspace greps a
      # MEMORY.md for the marker lines an operator left, history_valuables lists
      # the markers among the patterns worth recovering from git.
      scan_lines(without_regex_literals(src), /\b(TODO|FIXME|HACK|XXX)\b(?!\.md)/,
                 message: "unresolved marker — resolve or delete")
    end
  end

  ::Law.define(:RESCUE_EXCEPTION) do
    tags %i[ERROR_HANDLING]
    fix "rescue StandardError not Exception"
    bad "begin\nrescue Exception => e\nend\n"
    good "begin\n  # rescue Exception belongs to this rule\nrescue StandardError => e\nend\n"
    check do |src, path|
      # Comment lines blanked, not the directory skipped: a real `rescue
      # Exception` in a scanner rule is worth catching, and SILENT_RESCUE's note
      # below says why this population carries no path exemption.
      parsed = Prism.parse(src)

      next [] if parsed.failure?

      findings = []
      walk(parsed.value) do |node|
        next unless node.is_a?(Prism::RescueNode)

        # Prism::RescueNode#exceptions is the list of classes named on the
        # `rescue` line. A bare 'rescue' has none and defaults to StandardError.
        handled = node.exceptions
        next unless handled&.any? { |ex| ex.slice.to_s == "Exception" }

        findings << finding(line: node.location.start_line, message: "catches signals — use StandardError")
      end
      findings
    end
  end

  ::Law.define(:SILENT_RESCUE) do
    tags %i[ERROR_HANDLING FAIL_VISIBLY]
    fix "blanket rescue discards error without logging or re-raising"
    bad "begin\n  risky\nrescue StandardError\n  nil\nend\n"
    good "begin\n  risky\nrescue StandardError => e\n  warn e\nend\n"
    check do |src, path|
      # No path exemption for the scanner's own rules: a rule that returns [] on
      # error calls the file it failed on clean, so a swallow costs more in this
      # directory than anywhere else. The one exception is the rule's own test,
      # which must spell every shape it proves — the law-conduct argument.
      next [] if path.to_s.match?(/test_silent_rescue_rule\.rb\z|test_self_test\.rb\z/)

      SilentRescue.scan(src, narrow: false).map { |hit| finding(line: hit[:line], message: hit[:message]) }
    end
  end

  ::Law.define(:NARROW_SILENT_RESCUE) do
    tags %i[ERROR_HANDLING]
    fix "narrow-class rescue discards error without logging or re-raising"
    bad "begin\n  risky\nrescue Errno::ENOENT\n  nil\nend\n"
    good "begin\n  risky\nrescue Errno::ENOENT => e\n  warn e\nend\n"
    check do |src, path|
      SilentRescue.scan(src, narrow: true).map { |hit| finding(line: hit[:line], message: hit[:message]) }
    end
  end

  # An assignment, then any expression, then a modifier rescue returning a
  # discard. `(?<![=!<>*+\/%|&^-])=(?!=)` keeps comparisons out and lets `||=`,
  # `+=` and friends in, since each is still a binding.
  MODIFIER_RESCUE_DISCARD = %r{(?<![=!<>*+/%|&^-])=(?!=)[^=\n]*\S\s+rescue\s+(?:nil|false|\[\]|\{\})\s*(?:#.*)?$}

  ::Law.define(:MODIFIER_SILENT_RESCUE) do
    tags %i[ERROR_HANDLING]
    fix "modifier rescue binds a discarded error to a name"
    bad "value = parse(raw) rescue nil\n"
    good "File.delete(path) rescue nil\n"
    check do |src, path|
      scan_lines(without_law_fixtures(without_comment_lines(without_regex_literals(src))),
                 MODIFIER_RESCUE_DISCARD, message: "modifier rescue binds nil on failure — bind a meaningful value")
    end
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

  ::Law.define(:CONSECUTIVE_BLANK_LINES) do
    tags %i[HYGIENE]
    fix "no consecutive blank lines"
    bad "a = 1\n\n\nb = 2\n"
    good "a = 1\n\nb = 2\n"
    check do |src, path|
      findings = []
      prev_blank = false

      src.each_line.with_index(1) do |line, n|
        blank = line.strip.empty?
        findings << finding(line: n, message: "consecutive blank line") if blank && prev_blank
        prev_blank = blank
      end
      findings
    end
  end

  ::Law.define(:DEBUG_OUTPUT) do
    tags %i[FAIL_VISIBLY]
    fix "debug output left in lib/"
    example_path "/repo/lib/example.rb"
    bad "p value\n"
    good "p << value\n"
    check do |src, path|
      next [] unless path.to_s.include?("/lib/")
      next [] if path.to_s.include?("/scan/rules/")

      # `p` is a legal variable name, so a line starting `p <<` is an append to a
      # local, not a Kernel#p call. The old pattern read both the same way and
      # flagged attention_context.rb's `p << "zoom: …"` twice — an error-severity,
      # auto_fix=true rule pointed at correct code. Anything whose next token is an
      # assignment, append or comparison operator is the variable, not the call.
      #
      # `==` and `!=` were named and `<` and `>` were not, so dilla's
      # `p < 0.5 ? (p * 4.0) - 1.0 : 3.0 - (p * 4.0)` — the phase local of a
      # triangle oscillator — was an error-severity finding. `p <expr>` parses as
      # a comparison in every case; a Kernel#p whose argument opens with `<` is
      # `p <<~HEREDOC`, which the `<<` branch already spares.
      findings = scan_lines(src, /^\s*pp?\s+(?!self\b)(?!<<|[<>]|==|!=|\|\|=|&&=|[+\-*\/%|&^]?=)/,
        message: "p/pp debug call — remove or publish via event bus")

      findings += scan_lines(src, /\$stderr\.puts\b/, message: "$stderr.puts — use @bus.publish or $stdout")
      findings
    end
  end

  ::Law.define(:OMIT_NEEDLESS_WORDS) do
    tags %i[BE_CONCISE]
    fix "Strunk & White: omit needless words in comments"
    bad "# This is a helper for totals\n"
    good "# Sums the line items\n"
    check do |src, path|
      src.lines.each_with_index.filter_map do |line, n|
        next unless line.strip.start_with?("#")
        next if line.match?(/scan:\s*intentional\b/)

        # a wordy comment usually starts with "This is a", "Here we", "This function"
        if line.match?(/\b(?:This is a|Here we|This function|Note that)\b/i)
          finding(line: n + 1, message: "wordy comment — omit needless words")
        end
      end
    end
  end

  ::Law.define(:TRAILING_COMMENT) do
    tags %i[BE_CONCISE]
    fix "trailing comment after code"
    bad "value = 1 # why one\n"
    good "# why one\nvalue = 1\nvalue = 2 # scan: intentional — the exemption is not the defect\n"
    check do |src, path|
      src.each_line.with_index(1).filter_map do |line, n|
        next if line.strip.start_with?("#")

        # A line keeps its finding when a second trailing comment survives the
        # marker's removal; it loses it when the marker was the whole of it.
        next unless without_scan_marker(line).match?(/\S\s+#\s+\S/)

        finding(line: n, message: "trailing comment — promote above the line or delete")
      end
    end
  end

  ::Law.define(:TIME_ZONE_UNSAFE) do
    tags %i[ROBUSTNESS]
    fix "bare Time.now/Date.today bypasses Rails Time.zone"
    example_path "/repo/app/models/example.rb"
    bad "stamp = Time.now.beginning_of_day\n"
    good "generated_at: Time.now.utc.iso8601, exp: Time.now.to_i\n# Date.today is the server's day\n"
    check do |src, path|
      next [] unless path.match?(%r{/app/|/spec/|/test/})

      # A comment explaining why the code avoids Date.today names it; amber's
      # PlannedOutfit did, and the rule sent it for repair. Blanking comment
      # lines keeps every line number.
      # Spaces and tabs only before the #: \s would take the newlines of the blank lines above a comment
      # with it, and every finding after it reported the wrong line.
      src = src.gsub(/^[ \t]*#.*$/, "")

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
  end

  # `a === b` is JavaScript's identity operator and Ruby's case-equality, and it
  # is exactly three `=` with a space each side — which is what the divider
  # pattern below matches. 486 of this rule's 636 findings across the four trees
  # were `mode === "speaking"` and its like, three quarters of everything it
  # reported. An operand on both sides is what separates the operator from a
  # decoration: a real divider has nothing to its right, or is a longer run, and
  # no dropped line carried a run of four or more.
  IDENTITY_COMPARISON = /[\w)\]}'"]\s*===\s*[\w({\[!'"@$:]/

  ::Law.define(:NO_ASCII_LINE_ART) do
    tags %i[BE_CONCISE]
    fix "ASCII divider decorations"
    bad "# --- section\n"
    good "# -- section\n"
    check do |src, path|
      # A test carries dividers as data — a YAML fixture's `---`, an expected
      # banner — so in a test only a comment line is read, and a section divider
      # there is the same decoration it is in lib/.
      in_test = path.to_s.match?(%r{(^|/)(test|spec)/})

      divider = /(?:^|\s)(?:={3,}|-{3,}|_{3,})(?:\s|$)/
      scan_lines(src, divider, message: "remove ASCII divider decorations").reject do |finding|
        line = src.lines[finding[:line].to_i - 1].to_s
        in_test && !line.lstrip.start_with?("#", "//") ||
          path.to_s.end_with?(".yml", ".yaml") && line.strip == "---" ||
          line.match?(/\b(assert|refute|expect|must_|wont_)/) ||
          line.match?(IDENTITY_COMPARISON)
      end
    end
  end

  # ASCII art is reserved for the face's own renderer. The boot, prompt,
  # source prose and UI chrome remain text; a logo made from punctuation is
  # still a logo even when every character is printable ASCII.
  FACE_ASCII_EXCEPTIONS = %r{(?:^|/)(?:MASTER/lib/cli/face(?:/|\.rb\z)|RAILS/master/public/(?:face_ascii|face_2d_fallback)\.js\z|RAILS/master/test/face_ascii\.test\.mjs\z|MASTER/test/test_cli_ascii_face\.rb\z|MASTER/test/fixtures/face_ascii_frames\.json\z|MASTER/tools/face_ascii_fixtures\.rb\z|MASTER/law/interface\.rb\z)}

  ::Law.define(:NO_ASCII_ART_OUTSIDE_FACE) do
    source "Rendered-values law — ASCII art is reserved for the face itself"
    ask "Does this file add ASCII-art logos, boot banners, decorative prompt drawings, or other " \
        "typographic pictures outside the face renderer? ASCII art is forbidden everywhere except " \
        "the face itself and the fixtures that prove its rendering. Ordinary text, a real wordmark " \
        "set in a font, shell prompt characters, and dmesg-like status lines are not ASCII art. " \
        "Return CLEAN when no decorative ASCII picture exists outside the face."
    tags %i[BE_CONCISE]
    fix "Delete ASCII-art banners, wordmarks, and prompt drawings. Keep ASCII geometry only inside " \
        "the terminal/browser face renderer and its matching fixtures."
    bad "ascii_art: true\n"
    good "prompt = \"~/repo main %\"\n"
    check do |src, path|
      next [] if path.to_s.match?(FACE_ASCII_EXCEPTIONS)

      lines = src.lines
      findings = []
      art_row = lambda do |line|
        visual = line.to_s.strip.sub(/\A(?:#|\/\/)\s*/, "").delete(" \t'\",")
        symbols = visual.scan(/[|\/\\_+=*#~^<>-]/).length
        visual.length >= 8 && symbols >= 4 && symbols.fdiv(visual.length) >= 0.33
      end

      lines.each_with_index do |line, index|
        next if line.match?(/scan:\s*intentional\b/)
        next unless line.match?(/^\s*(?:ascii_art|ascii_logo|banner_art)\s*:/)

        findings << finding(line: index + 1, message: "remove ASCII art; only the face renderer may draw it")
      end

      lines.each_with_index do |line, index|
        next unless line.match?(/^\s*wordmark\s*:/)
        next unless lines[(index + 1), 5].to_a.any? { |candidate| art_row.call(candidate) }

        findings << finding(line: index + 1, message: "remove ASCII art; only the face renderer may draw it")
      end

      art_lines = lines.each_with_index.filter_map { |line, index| index if art_row.call(line) }
      art_lines.each_with_index do |index, position|
        next if position.positive? && index == art_lines[position - 1] + 1
        next unless art_lines[position + 1] == index + 1

        findings << finding(line: index + 1, message: "remove ASCII art; only the face renderer may draw it")
      end
      findings.uniq { |item| item[:line] }
    end
  end

  end
  end
  end
end
