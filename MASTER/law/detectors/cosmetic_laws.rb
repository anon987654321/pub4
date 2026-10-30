# frozen_string_literal: true

module Master
  module Review
    module Scan
      module Laws
        # What DOUBLE_QUOTES_RUBY may rewrite. A module rather than lambdas
        # inside the rule block, which is instance_exec'd once per file and
        # would rebuild them every time.
        module CosmeticRuleSupport
          LITERAL_QUOTE_CALLS = %w[require require_relative gem].freeze

          MEANING_CHANGES_RE = Regexp.union('"', "\\", '#{', "\#$", "\#@")

          # True for a single-quoted string literal whose content means the
          # same thing between double quotes.
          def self.convertible_single_quote?(node)
            return false unless node.opening_loc&.slice == "'"

            !node.content_loc.slice.match?(MEANING_CHANGES_RE)
          end
        end

        # Retired registry twins — each lives once, in law/:
        #   MEASURE_OPTIMUM
        # (test_scan_rule_contracts proves each reaches findings through the bridge).

        # What may stand between a README's title and its opening sentence: an HTML
        # comment, a void media tag, or a wrapped media element with a real closing tag.
        #
        # Three branches because the previous single one demanded a closing `>` after
        # every tag, and `<img …>` has none — so `.*?` ran off looking for one, the
        # alternation failed, and the branch matched nothing. MASTER/README.md, the file
        # CLAUDE.md names as the reference for this rule, therefore failed it: the bold
        # check ran against `<img src="loop.gif">`. A rule that cannot see the thing it
        # was written to permit is the shape law/ refuses in the lexical case.
        HERO = %r{
          \A(?:
            <!--.*?-->\s*                                    |
            <(?:img|source|br|hr)\b[^>]*/?>\s*               |
            <(?:video|picture|p|div|a)\b[^>]*>.*?</(?:video|picture|p|div|a)>\s*
          )+
        }mx.freeze

        ABBREV_IDENT_RE = /\b(?:def|class|module|\|)\s+.*\b(tmp|idx|cfg|ctx|num|val|obj|str|arr|buf|temp|ret)\b/.freeze
        EN_DASH_RANGE_RE = /\b\d+\s?-\s?\d+\b/.freeze

        # Three things wear the shape of a range without being one, and this tree is
        # full of all three: an ISO date is a single day, a model or version id is a
        # name, and a hyphen inside a regex character class or a code span is syntax.
        # Blank them before looking, or the rule reports the repo's own decision log
        # as a typography defect — 200 of 207 findings over the tracked markdown were
        # dates, and one was `claude-opus-4-8`.
        # A fourth wears it too: three or more hyphenated numbers is a tuple, not
        # a range. CSS specificity is written 0-1-0 and reads as two ranges to a
        # two-number pattern.
        EN_DASH_NOT_A_RANGE = %r{
          `[^`]*` |
          \b\d+(?:-\d+){2,}\b |
          \b\d{4}-\d{2}(?:-\d{2})?\b |
          \[[^\]]*\] |
          [A-Za-z][\w.]*-\d[\w.]*(?:-[\w.]+)*
        }x.freeze

        # In YAML a mapping line's value is data, and a hyphen in data is a
        # character some reader parses. Measured over the tracked markdown and
        # YAML: 39 findings, of which 32 were mapping values — 28 of those
        # `bpm_range: 84-90` in the old dilla engine's reference_sonic.yml (tag dilla-engine-final), which dilla
        # parses to render audio. YAML also carries real prose, in comments and
        # in block scalars, and those lines are not mappings, so the seven that
        # survive are all paragraphs.
        YAML_MAPPING_LINE = /\A[\w.-]+:\s/.freeze

        module_function

        def unwrap_ternary_branch(node)
          case node
          when Prism::ParenthesesNode then unwrap_ternary_branch(node.body)
          when Prism::StatementsNode
            node.body.size == 1 ? unwrap_ternary_branch(node.body.first) : node
          when Prism::ElseNode then unwrap_ternary_branch(node.statements)
          else node
          end
        end

        def ternary_branch_exprs(branch)
          return [] unless branch

          body = case branch
                 when Prism::StatementsNode then branch.body
                 when Prism::ElseNode then ternary_branch_exprs(branch.statements)
                 else [branch]
                 end
          body.map { |expr| unwrap_ternary_branch(expr) }
        end

        def nested_ternary_branch?(node)
          return false unless node.is_a?(Prism::IfNode) && node.if_keyword.nil?

          branches = ternary_branch_exprs(node.statements)
          branches += ternary_branch_exprs(node.subsequent) if node.subsequent
          branches.any? { |expr| expr.is_a?(Prism::IfNode) && expr.if_keyword.nil? }
        end

        # RUBY_SNAKE_METHODS lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # RUBY_CAMEL_CLASS lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # RUBY_NUMERIC_UNDERSCORE lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # RUBY_SYMBOL_TO_PROC lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # RUBY_BLOCK_DELIMITER lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        ::Law.define(:RUBY_TERNARY_NOT_NESTED) do
          tags %i[STYLE]
          fix "no nested ternaries"
          bad "value = a ? (b ? 1 : 2) : 3\n"
          good "value = a ? 1 : 2\n"
          check do |src, path|
            next [] if path.to_s.include?("/law/detectors/")
            result = Prism.parse(src)
            next [] if result.failure?

            findings = []
            walk = lambda do |node|
              return unless node
              if node.is_a?(Prism::IfNode) && node.if_keyword.nil? && Laws.nested_ternary_branch?(node)
                findings << finding(line: node.location.start_line,
                  message: "nested ternary — expand to if/elsif/else or case")
              end

              node.child_nodes.compact.each { |child| walk.call(child) }
            end
            walk.call(result.value)
            findings.uniq { |f| f[:line] }
          end
        end

        ::Law.define(:NO_ABBREVIATED_IDENTIFIERS) do
          tags %i[STYLE]
          fix "spell identifiers in full — no tmp/idx/cfg/ctx"
          bad "def call(tmp)\nend\n"
          good "def call(temporary_path)\nend\n"
          check do |src, path|
            next [] if path.to_s.include?("/law/detectors/")

            src.each_line.with_index(1).filter_map do |line, number|
              next if line.strip.start_with?("#", "//")
              next unless line.match?(ABBREV_IDENT_RE)
              finding(line: number, message: "abbreviated identifier — spell it out (temporary_path not tmp)")
            end
          end
        end

        # Read off the parse tree, not the line. A line-based reading cannot
        # tell a single-quoted string from an apostrophe inside a double-quoted
        # one, so an interpolated hash lookup and a comment reading "it's the
        # caller's job" both counted: 588 findings across MASTER, and
        # converting any of them would have broken the file. Prism knows which
        # quote opened a string.
        #
        # Five exemptions, each because double quotes would change meaning or
        # convention: a string carrying its own double quote, one carrying an
        # interpolation sequence it means literally, one carrying a backslash
        # escape that single quotes leave alone, the argument to require or gem
        # where single quotes are the Bundler convention, and a string nested
        # inside an interpolation, where doubling repeats the delimiter that
        # opened the enclosing string. That last one is the whole remainder:
        # once the parse tree is read instead of the line, MASTER holds 376
        # single-quoted strings and every one of them sits inside a `#{}`.
        ::Law.define(:DOUBLE_QUOTES_RUBY) do
          tags %i[STYLE]
          fix "double-quoted strings per style.yml"
          bad %(name = 'osman'\n)
          good %(name = "osman"\n)
          check do |src, path|
            next [] if path.to_s.include?("/law/detectors/")

            parsed = Prism.parse(src)
            next [] if parsed.failure?

            exempt = each_node(parsed.value, Prism::CallNode)
              .select { |call| CosmeticRuleSupport::LITERAL_QUOTE_CALLS.include?(call.name.to_s) }
              .flat_map { |call| Array(call.arguments&.arguments) }
              .map { |argument| argument.location.start_offset }

            interpolations = each_node(parsed.value, Prism::EmbeddedStatementsNode)
              .map { |node| node.location.start_offset...node.location.end_offset }

            each_node(parsed.value, Prism::StringNode).filter_map do |node|
              next unless CosmeticRuleSupport.convertible_single_quote?(node)
              next if exempt.include?(node.location.start_offset)
              next if interpolations.any? { |span| span.cover?(node.location.start_offset) }

              finding(line: node.location.start_line, message: "single-quoted string — use double quotes per style.yml")
            end
          end
        end

        ::Law.define(:EN_DASH_RANGE) do
          tags %i[TYPOGRAPHY]
          fix "numeric ranges use en dash not hyphen"
          example_path "/repo/docs/example.md"
          bad "The band is 45-75 wide.\n"
          good "The band is 45–75 wide.\n"
          check do |src, path|
            next [] if path.to_s.include?("/law/detectors/")

            next [] if path.end_with?(".rb", ".js", ".css", ".scss")
            data_file = path.end_with?(".yml", ".yaml")
            src.each_line.with_index(1).filter_map do |line, number|
              stripped = line.strip

              next if stripped.start_with?("#", "//", "detect_lexical:", "- id:")
              next unless stripped.gsub(EN_DASH_NOT_A_RANGE, " ").match?(EN_DASH_RANGE_RE)
              next if stripped.match?(/^\s*-\s+\w/) # YAML list item
              # A locale's values are the copy a reader sees, so there a mapping
              # line is prose and its value is read.
              next if data_file && stripped.match?(YAML_MAPPING_LINE) && !path.include?("/config/locales/")
              finding(line: number, message: "numeric range — use en dash: 45–75 not 45-75")
            end
          end
        end

        ::Law.define(:ALL_CAPS_NO_TRACKING) do
          tags %i[TYPOGRAPHY]
          fix "all-caps labels need letter-spacing"
          bad ".label { text-transform: uppercase; }\n"
          good ".label { text-transform: uppercase; letter-spacing: 0.08em; }\n"
          check do |src, path|
            next [] unless src.match?(/text-transform:\s*uppercase/i)
            next [] if src.match?(/letter-spacing\s*:/i)
            [finding(line: 1, message: "uppercase without letter-spacing — add tracking per laws.yml")]
          end
        end

        # A tab is indentation in source and a field separator in data. A .tsv is
        # tabs by definition, and login.conf and newsyslog.conf are kept as the
        # base system ships them, $OpenBSD$ id and tab-aligned columns included,
        # so a diff against the base file stays readable.
        TAB_DELIMITED_BASENAMES = %w[login.conf newsyslog.conf].freeze

        ::Law.define(:TAB_CHARACTER) do
          tags %i[HYGIENE]
          fix "tabs forbidden — use two spaces"
          bad "def call\n\tvalue\nend\n"
          good "def call\n  value\nend\n"
          check do |src, path|
            next [] if path.to_s.end_with?(".tsv") || TAB_DELIMITED_BASENAMES.include?(File.basename(path.to_s))

            scan_lines(src, /\t/, message: "tab character — indent with two spaces")
          end
        end

        ::Law.define(:FINAL_NEWLINE) do
          tags %i[HYGIENE]
          fix "files end with a single newline"
          bad "puts 1"
          good "puts 1\n"
          check do |src, path|
            next [] if src.empty? || src.end_with?("\n")
            [finding(line: src.lines.size, message: "missing final newline at EOF")]
          end
        end

        # USE_THEN lives once, in law/ruby.rb (2026-08-21 twin retirement).
        # The copy that stood here required the SAME function on both lines
        # (`r = parse(src)` then `parse(r)`) and so never fired on the pipeline
        # shape it was written for; the law fixture pins the real one.

        # RESCUE_ON_DEF lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # COMMENTS_AS_DEODORANT declared only a detect_semantic prompt, so it
        # cost an LLM call and reached a file only when the cheap passes had
        # already flagged it — the comment on a file that reads clean was never
        # examined. Restatement is the mechanical half of the rule and needs no
        # model: a comment whose content words are mostly the identifiers on the
        # next line is saying it twice.
        #
        # Content words only, and a floor of three, because "# Cache the user"
        # over `def cache_user` is a two-word coincidence and flagging it would
        # train people to delete the comments that earn their place.
        COMMENT_STOPWORDS = %w[the and for that with not its this are was were does def end
                               self new nil true false].freeze

        COMMENT_RESTATEMENT_FLOOR = 3
        COMMENT_RESTATEMENT_RATIO = 0.75

        # snake_case splits, so `increment_wear_count` is three words rather than
        # one token that can never match the prose above it.
        def self.content_words(text)
          text.downcase.scan(/[a-z]{3,}/).reject { |word| COMMENT_STOPWORDS.include?(word) }.uniq
        end

        ::Law.define(:COMMENTS_AS_DEODORANT) do
          source "Refactoring — comments as deodorant (Fowler/Beck)"
          ask "Is a comment compensating for code or prose that could instead be rewritten to make the intent obvious?"
          tags %i[CLEAN_CODE SELF_EXPLAINING]
          fix "Refactor the underlying artifact first; keep comments for rationale that cannot be encoded directly."
          bad "# increment the wear count\nincrement_wear_count\n"
          good "# a torn hem is still a wearing\nincrement_wear_count\n"
          check do |src, path|
            next [] unless %w[ruby].include?(language(path))
            next [] if path.to_s.include?("/law/detectors/")

            lines = src.lines
            lines.each_with_index.filter_map do |line, index|
              next unless line.strip.start_with?("#")
              next if line.include?("frozen_string_literal") || line.strip.start_with?("#!")

              code = lines[index + 1].to_s
              next if code.strip.empty? || code.strip.start_with?("#", "end")

              said = Laws.content_words(line.sub(/^\s*#\s*/, ""))
              next if said.size < COMMENT_RESTATEMENT_FLOOR

              shared = (said & Laws.content_words(code)).size
              next if shared.to_f / said.size < COMMENT_RESTATEMENT_RATIO

              finding(line: index + 1,
                      message: "comment restates the line below it — delete it, or say why instead of what")
            end
          end
        end

        ::Law.define(:VERTICAL_BREATH) do
          tags %i[BEAUTY]
          fix "vertical breath — avoid dense blocks of 10+ lines without a blank line"
          transform "add_vertical_breath"
          bad (1..10).map { |i| "line#{i} = 1\n" }.join
          good "a = 1\n\nb = 2\n"
          check do |src, path|
            next [] if path.to_s.include?("/law/detectors/")

            findings = []
            lines = src.lines
            dense_count = 0
            start_line = 1

            lines.each_with_index do |line, n|
              if line.strip.empty?
                if dense_count >= 10
                  findings << finding(line: start_line, message: "suffocated block — add a blank line for breath")
                end
                dense_count = 0
                start_line = n + 2
              else
                dense_count += 1
              end
            end

            # A dense block that reaches end of file without a trailing blank
            # line misses the check above — every file that reaches EOF mid-block
            # (the common case) went unreported.
            if dense_count >= 10
              findings << finding(line: start_line, message: "suffocated block — add a blank line for breath")
            end
            findings
          end
        end

        ::Law.define(:CODE_SYMMETRY) do
          tags %i[BEAUTY]
          fix "source symmetry — avoid jagged indentation shifts"
          bad "def foo\n        return true\nend\n"
          good "def foo\n  return true\nend\n"
          check do |src, path|
            next [] if path.to_s.include?("/law/detectors/")

            findings = []
            lines = src.lines
            lines.each_with_index.each_slice(2) do |pair|
              next unless pair.size == 2
              l1, l2 = pair[0][0], pair[1][0]

              line2_number = pair[1][1]
              # a jagged shift is a sudden jump of 4+ spaces for a single line
              indent1 = l1[/\A\s*/].size
              indent2 = l2[/\A\s*/].size
              l2_stripped = l2.strip

              if (indent1 - indent2).abs >= 4 && l2_stripped.size < 40 &&
                 l2_stripped.match?(/^(?:return|break|next|raise)/)
                findings << finding(line: line2_number + 1, message: "jagged symmetry — align this line with its block")
              end
            end
            findings
          end
        end

        ::Law.define(:TYPOGRAPHIC_GRID) do
          tags %i[TYPOGRAPHY]
          fix "typographic grid — maintain line length and vertical rhythm"
          example_path "/repo/README.md"
          bad "#{"x" * 105}\n"
          good "short line\n"
          check do |src, path|
            next [] if path.to_s.include?("/law/detectors/")
            findings = []
            lines = src.lines

            lines.each_with_index do |line, n|
              # Bringhurst's ideal measure is ~66 characters; we allow 100 for technical prose
              if line.size > 100 && !line.match?(/\A\s*`.*`\s*\z/)
                findings << finding(line: n + 1, message: "line too long — break for typographic measure")
              end
            end
            findings
          end
        end

        ::Law.define(:README_PROSE) do
          tags %i[TYPOGRAPHY DOMAIN_LANGUAGE]
          fix "a README is prose — a bold visionary opening, " \
            "tables never, code only under the final heading"
          example_path "/repo/README.md"
          bad "# Title\n\n| one | two |\n"
          good "# Title\n\n**One bold sentence carrying the argument.**\n"
          check do |src, path|
            next [] unless path.to_s.end_with?("README.md")
            findings = []

            lines = src.lines
            # A demonstration — a terminal transcript, one prized source excerpt —
            # earns its place once the argument is made, under the closing heading.
            # A fence before that chops the flowing prose the rest of this rule
            # exists to protect; a table chops it anywhere.
            last_heading = lines.rindex { |line| line.start_with?("## ") } || -1
            lines.each_with_index do |line, index|
              if line.start_with?("```") && index < last_heading
                findings << finding(line: index + 1,
                                    message: "a code block interrupts the prose — a demonstration belongs " \
                                             "under the final heading, not mid-argument")
              end

              if line.match?(/\A\s*\|.*\|\s*\z/)
                findings << finding(line: index + 1, message: "README carries a table — say it in a sentence")
              end
            end
            lead = src.sub(/\A#\s+[^\n]+\n+/, "").lstrip
            # A hero image or video (and its HTML comment) may sit between the
            # title and the opening line — skip it before checking the opening is
            # bold, so the face can lead the page and the prose still has to.
            lead = lead.sub(HERO, "").lstrip

            unless lead.empty? || lead.start_with?("**")
              findings << finding(line: 1,
                                  message: "README opening is not bold — lead with one bold, visionary sentence")
            end
            findings
          end
        end
      end
    end
  end
end
