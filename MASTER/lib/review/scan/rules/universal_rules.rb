# frozen_string_literal: true

module Master
  module Review
    module Scan
      module Rules

      # SQL strings embedded in Ruby DB adapter files are expected — only flag
      # actual mixed-medium template files.
        # Retired registry twins — each lives once, in law/:
        #   MEANINGFUL_NAMES, WHY_NOT_WHAT
        # (test_scan_rule_contracts proves each reaches findings through the bridge).

        # NO_MULTIPLE_LANGUAGES lives once, in law/css.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # SAFE_NAVIGATION lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        RuleDSL.rule :FEW_ARGUMENTS,
          severity: :warning, tags: %i[SMALL_PARTS],
          fires: "def place(north, east, depth)\nend\n",
          does_not_fire: "def place(north:, east:, depth:)\nend\n",
          description: "ideal is zero to two positional arguments" do |src, path:|
          src.each_line.with_index(1).filter_map do |line, n|
            next unless line.match?(/\bdef\s+\w+\(/)
            args = line[/\(([^)]*)\)/, 1].to_s.split(",").map(&:strip)
            positional = args.reject { |arg| arg.empty? || arg.start_with?("*", "&") || arg.include?(":") || arg.include?("=") }
            finding(line: n, message: "3+ positional args — use keyword arguments or a value object") if positional.size >= 3
          end
        end

        RuleDSL.rule :N_PLUS_ONE,
          severity: :warning, tags: %i[PERFORMANCE],
          fires: "posts.each { |post| post.author.name }\n",
          does_not_fire: "posts.each { |post| post.title }\n",
          description: "loading records one-by-one inside a loop" do |src, path:|
          # Only meaningful in Rails app/ trees; non-AR enumerable chains are fine.
          next [] unless path.match?(%r{/app/|/spec/|/test/})
          scan_lines(src, /\.(each|map|collect)\s*(do|\{).*\.\w+\.\w+/,
            message: "N+1 query candidate — use includes/eager_load")
        end

      # Only positional boolean defaults are flag arguments. Keyword defaults
      # (stream: false, enabled: true) are not — they're fine API design.
        RuleDSL.rule :NO_FLAG_ARGUMENTS,
          severity: :warning, tags: %i[SMALL_PARTS],
          fires: "def render(body, cache = true)\nend\n",
          does_not_fire: "def render(body, cache: true)\nend\n",
          description: "a flag that selects behavior means two things hiding as one" do |src, path:|
          src.each_line.with_index(1).filter_map do |line, n|
            next unless line.match?(/def \w+\(/)
            args_str = line[/\(([^)]*)\)/, 1].to_s
            args = args_str.split(",").map(&:strip)
            positional_bool = args.any? do |a|
              a.match?(/\A\w+\s*=\s*(true|false)\z/) && !a.include?(":")
            end
            finding(line: n, message: "boolean flag arg — split into two methods") if positional_bool
          end
        end

      # Exclude numeric dot-chains (IP addresses, version numbers) and stdlib
      # transformation chains (.to_s.strip.empty?) which are idiomatic Ruby.
        RuleDSL.rule :LAW_OF_DEMETER,
          severity: :warning, tags: %i[COUPLING],
          fires: "city = order.buyer.profile.address\n",
          does_not_fire: "city = order.buyer.profile.to_s\n",
          description: "only talk to immediate friends" do |src, path:|
          src.each_line.with_index(1).filter_map do |line, n|
            next if line.strip.start_with?("#")
            next unless line.match?(/\b[a-z_]\w*(?:\.[a-z_]\w*){3}/)
            next if line.match?(/\d+\.\d+\.\d+\.\d+/)
            next if line.match?(/\.(to_s|to_i|to_f|to_a|to_h|strip|chomp|compact|first|last|join)\b/) ||
                    line.match?(/\.(empty\?|any\?|size|length)\b/)
            stripped = line.gsub(/["'][^"']*["']/, '""').gsub(/\(.*?\)/, "()")
            next unless stripped.match?(/\b[a-z_]\w*(?:\.[a-z_]\w*){3}/)
            finding(line: n, message: "4-level chain — introduce a local variable or delegation")
          end
        end

      # Generic names: only short or clearly placeholder names. `data` and
      # `result` are contextually meaningful in most Ruby code.

        RuleDSL.rule :TYPOGRAPHIC_EXCELLENCE,
          severity: :info, tags: %i[TYPOGRAPHY],
          # A quote against the ellipsis: the rule reads a bare quoted
          # ellipsis as the placeholder, not prose that happens to contain dots.
          fires: %(warn "..."\n),
          does_not_fire: %(warn "…"\n),
          description: "typographic excellence in user-facing text" do |src, path:|
          next [] if path.to_s.include?("/review/scan/rules/")
          src.each_line.with_index(1).filter_map do |line, n|
            next if line.match?(/Open3|capture2|capture3|gsub\(|Shellwords/)
            next if line.match?(/,\s*"--"\s*,|,\s*"--"\s*\)|<<\s*["']--/)
            # A leading-# line in an .erb file is a doc comment inside an ERB
            # block — its "..." is an example placeholder, not UI copy.
            next if path.to_s.end_with?(".erb") && line.lstrip.start_with?("#")
            next unless line.match?(/["']\.\.\.[\"']|["']--["']/)
            finding(line: n, message: "ASCII typography — use Unicode ellipsis … and em dash —")
          end
        end

      # Exclude YAML document separators (---) and data file structural lines;
      # only flag decorative runs inside code comments or string literals.
        RuleDSL.rule :TYPOGRAPHY_DISCIPLINE,
          severity: :info, tags: %i[TYPOGRAPHY],
          fires: "# ====\n",
          does_not_fire: "# ===\n",
          description: "hierarchy via weight and brightness, not decoration" do |src, path:|
          next [] if path.to_s.include?("/review/scan/rules/")
          src.each_line.with_index(1).filter_map do |line, n|
            stripped = line.strip
            next if stripped == "---" || stripped.start_with?("---") && path.end_with?(".yml", ".yaml")
            next if stripped.start_with?("//", "/*", "*")
            next unless stripped.match?(/[-=]{4,}|[╭╮╰╯│─]/)
            finding(line: n, message: "ASCII decoration — use whitespace and typographic weight instead")
          end
        end

      # NULL_BLINDNESS lives once, in law/ (domain files) — the second
      # retired twin (see TODO.md). This block's regex matched IS NULL, the
      # correct form its own message prescribed, and needed a path exemption
      # to stop reporting the fixer that emits that string as a repair. The
      # law version detects `= NULL`, proves itself on fixtures the inverted
      # detector would have failed, and needs no exemption.

      # SECRET_PROXIMITY lives once, in law/ — the third retired twin. The two
      # regexes were byte-identical; the registry block was a pure duplicate.

# MAGIC_COLOR lives once, in js_rules.rb (applies_to css/scss/html/js — where colors
# live). A second copy here with no applies_to double-counted every css/scss color
# under the same id (a SINGULARITY violation) and added no coverage worth keeping.

      # UNBOUNDED_RETRY lives once, in law/ (domain files) — the first of the
      # 72 law/registry twins retired (see TODO.md). The narrowing this block
      # learned — keyword not symbol, not predicate, not identifier, not regex
      # alternation, not a line continuation — moved into the law's detector
      # with each shape pinned as a good fixture, which is what the registry
      # version never had. Its /review/scan/rules/ self-exemption dies with it:
      # law/ text arrives conducted, and rule sources that spell the pattern in
      # strings are counted and triaged rather than excused by path.

        RuleDSL.rule :ONE_SOURCE,
          severity: :warning, tags: %i[COUPLING],
          fires: %(COUNCIL_PATH = "data/council.yml"\n),
          does_not_fire: "path = Master::COUNCIL_PATH\n",
          description: "constants defined locally when a canonical ONE_SOURCE exists" do |src, path:|
          next [] if path.to_s.include?("/review/scan/rules/")
          next [] if path.to_s.include?("master.rb")
          patterns = [
            [/COUNCIL_PATH\s*=/, "define COUNCIL_PATH once in master.rb; reference Master::COUNCIL_PATH"],
            [/RULES_PATH\s*=/, "define RULES_PATH once in master.rb; reference Master::RULES_PATH"],
            [/DATA_DIR\s*=\s*File\.join.*\bdata\b/, "use Master::DATA constant"],
          ]
          src.each_line.with_index(1).flat_map do |line, n|
            patterns.filter_map { |re, msg| finding(line: n, message: msg) if re.match?(line) }
          end
        end

      # Bias: SIMULATION — future tense in output implies intent without evidence.
        RuleDSL.rule :SIMULATION,
          severity: :warning, tags: %i[ANTI_SIMULATION DENSITY],
          fires: %(warn "the deploy will restart relayd"\n),
          does_not_fire: %(warn "the deploy restarted relayd"\n),
          description: "future tense implies without evidence — use indicative past" do |src, path:|
          next [] unless path.to_s.end_with?(".rb", ".md", ".txt", ".erb")
          next [] if path.to_s.include?("/review/scan/rules/")
          src.each_line.with_index(1).filter_map do |line, n|
            next if line.strip.start_with?("#")
            next unless line.match?(/\b(will\s+\w+|would\s+\w+|let('s|\s+us)\s+\w+|I\s+will\s+|we\s+will\s+)/i)
            finding(line: n, message: "simulation language — rewrite in indicative past or present tense")
          end
        end

      # Bias: COMPLETION_THEATER — ellipsis/etc as placeholder outputs.
      #
      # A placeholder "etc" is lowercase, bare, and not part of a path. Being loose
      # about that (/\betc\.?\b/i) matched `require "etc"`, `Etc.nprocessors` and
      # every /etc/… deploy path — 12 of selfcheck's 71 findings, none real. See
      # TODO.md, Scanner noise.
      #
      # `|`, `:` and `[` join the path characters because a word that sits inside
      # a regex alternation is a token in a pattern, not prose. Two lines in the
      # tree were reported for years on that shape and both are lists of real
      # names: ast_fixer's `%r{/OPENBSD/(?:etc|usr|var)/}` — the OPENBSD mirror
      # guard, at error severity, so `rake selfcheck` was red on the rule that
      # protects /etc — and a stdlib allowlist naming `etc` among a dozen others.
      # Measured over all four trees: exactly those two go, 57 findings stay.
      # `(` and `)` are deliberately NOT in the sets: "(etc.)" in prose is the
      # placeholder this rule exists to find.
        # `-` joins them for the same reason: `"etc-pre-sync"` is a label naming
        # the directory, and no abbreviation is ever hyphenated onward.
        PLACEHOLDER_ETC = %r{(?<![\w/|:\[-])etc\.?(?![\w/|\]-])}
        STDLIB_ETC_REQUIRE = /\brequire\s+["']etc["']/
        # /etc is a directory, and the exclusions above only knew it when a
        # slash was adjacent. Every other way this tree spells that path counted
        # as theater: File.join(ROOT, "etc", "rc.d"), `OPENBSD/{etc,usr,var}`,
        # the %w list of directory names in tools/doc_paths.rb — 25 of this
        # rule's 40 findings on 2026-09-06, none of them a placeholder.
        # `require "etc"` is the same lesson, learned once for one line.
        PATH_ETC = /["']etc["']|\{[\w,]*\betc\b[\w,]*\}|\betc(?=\s+(?:usr|var)\b)/
        # A comment is a comment wherever it starts. The rule skipped a line
        # that opens with one and read the same words as theater when they
        # followed code, so `|| continue   # skip CAM, TS, screener, etc.` was a
        # finding and the same sentence on its own line was not. Ruby's `#{` and
        # a shell `$#` are not comment openers.
        TRAILING_COMMENT = /(?<![$\\])#(?!\{).*\z/

        RuleDSL.rule :COMPLETION_THEATER,
          severity: :error, tags: %i[ROBUSTNESS COMPLETENESS],
          fires: "handle(first, second, etc.)\n",
          does_not_fire: %(require "etc"\n),
          description: "ellipsis or etcetera as placeholder violates completeness" do |src, path:|
          next [] if path.to_s.include?("/review/scan/rules/")

          # In prose "etc." is a word; in code it stands where the work should
          # be. Markdown is prose, and reading a documented list of examples as
          # an unfinished implementation is how a rule teaches its readers to
          # ignore it. An ellipsis still counts in both.
          prose = path.to_s.end_with?(".md", ".markdown")
          src.each_line.with_index(1).filter_map do |line, n|
            stripped = line.strip
            next if stripped.start_with?("#")
            next if stripped.match?(STDLIB_ETC_REQUIRE)
            # The marker the framework advertises. scan_lines honours it and
            # this rule wrote its own loop, so the one line in the tree that
            # needs it had no way to say so.
            next if stripped.match?(/scan:\s*intentional\b/)

            code = stripped.sub(TRAILING_COMMENT, "").rstrip
            etcetera = !prose && (code.gsub(PATH_ETC, "").match?(PLACEHOLDER_ETC) || code.match?(/\betcetera\b/i))
            next unless etcetera || code.match?(/\.\.\.\s*$/)

            finding(line: n, message: "completion theater — implement or delete, never placeholder")
          end
        end

        # Interpolation is not injection when the adapter did the quoting. A
        # bind parameter cannot be an identifier, so
        # `conn.execute("DELETE FROM #{conn.quote_table_name(table)}")` is the
        # documented way to name a table — and flagging it tells the reader the
        # rule does not know the fix it demands. Only an interpolation that is
        # nothing but one quoting call is spared; a second term inside the
        # braces still fires.
        QUOTED_INTERPOLATION = /
          \A[\w.:@]*\b
          (?:quote_table_name|quote_column_name|sanitize_sql_array|sanitize_sql|quote)
          \([^()]*\)\z
        /x
        INTERPOLATION = /\#\{([^{}]*)\}/

        RuleDSL.rule :SQL_INJECTION,
          severity: :error, tags: %i[SECURITY],
          fires: %q(conn.execute("DELETE FROM #{table}")) + "\n",
          does_not_fire: %q(conn.execute("DELETE FROM #{conn.quote_table_name(table)}")) + "\n",
          description: "parameterize all SQL — never interpolate user input" do |src, path:|
          # The two fixtures above are SQL injection and its fix, spelled out in
          # this file, so this rule reads its own source as two findings unless
          # it skips the directory it lives in. COMPLETION_THEATER carries the
          # same skip for the same reason.
          next [] if path.to_s.include?("/review/scan/rules/")

          src.each_line.with_index(1).filter_map do |line, n|
            stripped = line.strip
            next if stripped.start_with?("#")
            # The concatenation branch wanted a closed string before the `+` and
            # never asked for one, so it read `execute("SELECT a + b FROM t")` —
            # SQL arithmetic — as concatenation, and missed
            # `execute("SELECT * FROM " + name)`, which is the shape it is for.
            match = stripped.match(/\.(?:execute|query)\s*\(.*#\{/) ||
                    stripped.match(/\.(?:execute|query)\s*\(\s*["'][^"']*["']\s*\+/)
            next unless match

            interpolated = stripped.scan(INTERPOLATION).flatten
            next if interpolated.any? && interpolated.all? { |expr| expr.strip.match?(QUOTED_INTERPOLATION) }
            # A real `.execute(`/`.query(` call is never itself quoted string content —
            # skip when it sits inside a string literal (e.g. a human-readable label
            # like "Foo.execute(#{bar})" passed to a logger), which reads as an odd
            # number of open quote characters before the match on this line.
            prefix = stripped[0...match.begin(0)]
            next if prefix.count('"').odd? || prefix.count("'").odd?

            finding(line: n, message: "SQL injection risk — use parameterized queries or ActiveRecord helpers")
          end
        end

        # NO_COLUMN_ALIGN lives once, in law/universal.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # STRICT_MODE_ZSH lives once, in law/shell.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        RuleDSL.rule :CONTROL_CHARS,
          severity: :error, tags: %i[ROBUSTNESS],
          # An escape, not a literal, so this file keeps carrying no control
          # character of its own — which is why the rule counts by ordinal.
          fires: "value = 1\u0001\n",
          does_not_fire: "value = 1\t\n",
          description: "no non-printable control characters in source" do |src, path:|
          # Only tab (9), newline (10), and carriage return (13) are legal in
          # source. A stray SOH/NUL reads fine in most viewers but breaks parsing
          # or a byte-compare silently — corruption from a concurrent write or a
          # tool that left a sentinel byte behind. Checked by ordinal so this rule
          # carries no control character of its own.
          src.each_line.with_index(1).filter_map do |line, number|
            next unless line.each_char.any? { |char| ord = char.ord; ord < 9 || (ord > 13 && ord < 32) || ord == 127 }

            finding(line: number, message: "control character in source — corruption, remove it")
          end
        end

      end
    end
  end
end
