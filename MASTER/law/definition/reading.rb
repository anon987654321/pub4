# frozen_string_literal: true

module Law
  # How a Definition reads a subject: the text it considers, by line or whole,
  # and what a check or detector class reports.
  module Reading
    private

    # File-scope laws get the same two exemptions the line-scope ones have. All
    # eleven had neither, so they were blind to comment leaders and to the
    # `scan: intentional` opt-out this framework advertises — which is how
    # RATE_LIMITING_MISSING fired at :error on a sixteen-line controller with no
    # actions, on the word "login" inside a comment. At :error that also checks
    # the file out of the semantic pass entirely.
    def scan_file(text, file)
      return [] if absent && text.match?(absent)
      return [] unless detect.call(considered_text(text, file))

      [Finding.new(id, file, 1, text[/.*/])]
    end

    # A check reads the raw text and runs on a Scan::Detector, whose helpers it
    # shares with every detector class: `finding`, the AST walks, source
    # masking. Raw, because a check decides what a comment or a `scan:
    # intentional` marker means for it — LONG_LINE measures a marked line with
    # the marker removed — so blanking either first would change what it judges.
    def scan_check(text, file)
      return [] if absent && text.match?(absent)

      runner = Master::Review::Scan::Detector.new.bind(self)
      law_findings(runner.instance_exec(text, file, &check), lines: text.lines, file:)
    end

    # A detector class runs as the scanner runs it, built for this Law.
    def scan_detector(text, file)
      law_findings(detector.build(self).check(text, path: file), lines: text.lines, file:)
    end

    def law_findings(hits, lines:, file:)
      Array(hits).map do |hit|
        line = Master::Review::Scan::Finding.read(hit, :line).to_i
        CheckFinding.new(id:, file:, text: lines[line - 1].to_s.chomp, detail: hit)
      end
    end

    # Comments and intentional-marked lines blanked, newlines kept, so a
    # multi-line detector still sees the file's shape.
    def considered_text(text, file)
      subject_view(text, file).considered(reads_comments) { compute_considered_text(text, file) }
    end

    # Held for the text it was built from; see SubjectView.
    def subject_view(text, file)
      view = Thread.current[:law_subject_view]
      return view if view&.fresh?(text, file)

      Thread.current[:law_subject_view] = SubjectView.new(
        text:, file:, leaders: Law.comment_leaders(file), continued: continued_comment_lines(text, file),
      )
    end

    def compute_considered_text(text, file)
      leaders = reads_comments ? [] : Law.comment_leaders(file)
      continued = reads_comments ? [] : continued_comment_lines(text, file)
      return text if leaders.empty? && continued.empty? && !text.include?("scan:")

      text.each_line.with_index.map do |line, index|
        next "\n" if continued.include?(index)

        # A shebang is not a comment here: STRICT_MODE_ZSH asks whether a script
        # that declares an interpreter also sets strict mode, so blanking line 1
        # made it unable to see the script at all.
        next line if index.zero? && line.start_with?("#!")

        skip = leaders.any? { |leader| line.lstrip.start_with?(leader) } ||
               line.match?(/scan:\s*intentional\b/)
        skip ? "\n" : line
      end.join
    end

    # Line indices, zero-based, that sit inside a comment which opened on an
    # earlier line.
    #
    # A leader test reads one line, so it sees where a comment starts and never
    # where it continues. An ERB comment is routinely six lines of prose about
    # the markup below it, and every line after the first was being read as
    # markup: I18N_COVERAGE fired on a comment explaining that a page carried no
    # <h1>, because "<h1> at all — two <h2>s" is a `>`, English, and a `<`. The
    # rule already refused the opening line; there was no way for it to refuse
    # the rest.
    #
    # ERB, and a stylesheet's /* */, whose prose names declarations as often as
    # an ERB comment names tags: _composer.scss explains a fix "(measured at
    # left: 0)" on a comment's second line, and _shell.scss quotes `left: 50%`
    # on another. JavaScript and <!-- --> stay on the leader test, because a
    # glob or a regex in a script can spell /* without opening anything, and a
    # span reader that is wrong is worse than a leader test that is narrow.
    COMMENT_SPANS = {
      ".erb" => ["<%#", "%" + ">"],
      ".css" => ["/*", "*/"],
      ".scss" => ["/*", "*/"],
    }.freeze

    def continued_comment_lines(text, file)
      opener, closer = COMMENT_SPANS[File.extname(file)]
      return [] unless opener && text.include?(opener)

      inside = false
      text.each_line.with_index.filter_map do |line, index|
        opened = inside
        unless inside
          open_at = line.rindex(opener)
          inside = true if open_at && !line[open_at..].include?(closer)
        end
        if inside && line.include?(closer)
          inside = false
          next opened ? index : nil
        end
        index if inside && opened
      end
    end

    def scan_lines(text, file)
      view = subject_view(text, file)
      # A rule that reads comments still honours the registry's one-line
      # opt-out: a line that declares itself intentional carries a reviewer's
      # reason beside it.
      skip = reads_comments ? view.intentional : view.skipped
      view.lines.each_with_index.filter_map do |line, index|
        next if skip.include?(index)

        Finding.new(id, file, index + 1, line.chomp) if detect.call(line)
      end
    end
  end
end
