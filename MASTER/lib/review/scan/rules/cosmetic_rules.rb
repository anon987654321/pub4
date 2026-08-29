# frozen_string_literal: true

module Master
  module Review
    module Scan
      module Rules
        # Retired registry twins — each lives once, in law/:
        #   MEASURE_OPTIMUM
        # (test_scan_rule_contracts proves each reaches findings through the bridge).

        ABBREV_IDENT_RE = /\b(?:def|class|module|\|)\s+.*\b(tmp|idx|cfg|ctx|num|val|obj|str|arr|buf|temp|ret)\b/.freeze
        EN_DASH_RANGE_RE = /\b\d+\s?-\s?\d+\b/.freeze

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

        RuleDSL.rule :RUBY_TERNARY_NOT_NESTED,
          severity: :warning, tags: %i[STYLE], applies_to: %i[ruby],
          description: "no nested ternaries" do |src, path:|
          next [] if path.to_s.include?("/review/scan/rules/")
          result = Prism.parse(src)
          next [] if result.failure?

          findings = []
          walk = lambda do |node|
            return unless node
            if node.is_a?(Prism::IfNode) && node.if_keyword.nil? && Rules.nested_ternary_branch?(node)
              findings << finding(line: node.location.start_line,
                message: "nested ternary — expand to if/elsif/else or case")
            end
            node.child_nodes.compact.each { |child| walk.call(child) }
          end
          walk.call(result.value)
          findings.uniq { |f| f[:line] }
        end

        RuleDSL.rule :NO_ABBREVIATED_IDENTIFIERS,
          severity: :info, tags: %i[STYLE], applies_to: %i[ruby javascript],
          description: "spell identifiers in full — no tmp/idx/cfg/ctx" do |src, path:|
          next [] if path.to_s.include?("/review/scan/rules/")
          src.each_line.with_index(1).filter_map do |line, number|
            next if line.strip.start_with?("#", "//")
            next unless line.match?(ABBREV_IDENT_RE)
            finding(line: number, message: "abbreviated identifier — spell it out (temporary_path not tmp)")
          end
        end

        RuleDSL.rule :DOUBLE_QUOTES_RUBY,
          severity: :info, tags: %i[STYLE], applies_to: %i[ruby],
          description: "double-quoted strings per style.yml" do |src, path:|
          next [] if path.to_s.include?("/review/scan/rules/")
          src.each_line.with_index(1).filter_map do |line, number|
            next if line.match?(/#[^"']*'[^']*'/) && !line.match?(/"[^"]*"/)
            next unless line.match?(/'[^'\\]*(\\.[^'\\]*)*'/)
            next if line.match?(/%w\[|%i\[|<<[-~]?'|require\s+'|gem\s+'/)
            finding(line: number, message: "single-quoted string — use double quotes per style.yml")
          end
        end

        RuleDSL.rule :EN_DASH_RANGE,
          severity: :info, tags: %i[TYPOGRAPHY], applies_to: %i[markdown yaml html],
          description: "numeric ranges use en dash not hyphen" do |src, path:|
          next [] if path.to_s.include?("/review/scan/rules/")
          next [] if path.end_with?(".rb", ".js", ".css", ".scss")
          src.each_line.with_index(1).filter_map do |line, number|
            stripped = line.strip
            next if stripped.start_with?("#", "//", "detect_lexical:", "- id:")
            next unless stripped.match?(EN_DASH_RANGE_RE)
            next if stripped.match?(/^\s*-\s+\w/) # YAML list item
            finding(line: number, message: "numeric range — use en dash: 45–75 not 45-75")
          end
        end

        RuleDSL.rule :ALL_CAPS_NO_TRACKING,
          severity: :info, tags: %i[TYPOGRAPHY], applies_to: %i[css scss],
          description: "all-caps labels need letter-spacing" do |src, path:|
          next [] unless src.match?(/text-transform:\s*uppercase/i)
          next [] if src.match?(/letter-spacing\s*:/i)
          [finding(line: 1, message: "uppercase without letter-spacing — add tracking per design_rules.yml")]
        end

        RuleDSL.rule :TAB_CHARACTER,
          severity: :warning, tags: %i[HYGIENE],
          description: "tabs forbidden — use two spaces" do |src, path:|
          scan_lines(src, /\t/, message: "tab character — indent with two spaces")
        end

        RuleDSL.rule :FINAL_NEWLINE,
          severity: :info, tags: %i[HYGIENE],
          description: "files end with a single newline" do |src, path:|
          next [] if src.empty? || src.end_with?("\n")
          [finding(line: src.lines.size, message: "missing final newline at EOF")]
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

        RuleDSL.rule :COMMENTS_AS_DEODORANT,
          severity: :warning, tags: %i[CLEAN_CODE SELF_EXPLAINING], applies_to: %i[ruby],
          description: "a comment that restates the line below it says nothing the code did not" do |src, path:|
          next [] if path.to_s.include?("/review/scan/rules/")

          lines = src.lines
          lines.each_with_index.filter_map do |line, index|
            next unless line.strip.start_with?("#")
            next if line.include?("frozen_string_literal") || line.strip.start_with?("#!")

            code = lines[index + 1].to_s
            next if code.strip.empty? || code.strip.start_with?("#", "end")

            said = Rules.content_words(line.sub(/^\s*#\s*/, ""))
            next if said.size < COMMENT_RESTATEMENT_FLOOR

            shared = (said & Rules.content_words(code)).size
            next if shared.to_f / said.size < COMMENT_RESTATEMENT_RATIO

            finding(line: index + 1,
                    message: "comment restates the line below it — delete it, or say why instead of what")
          end
        end

        RuleDSL.rule :README_PROSE,
          severity: :info, tags: %i[TYPOGRAPHY DOMAIN_LANGUAGE], applies_to: %i[markdown],
          description: "a README is prose — a bold visionary opening, tables never, code only under the final heading" do |src, path:|
          next [] unless path.to_s.end_with?("README.md")
          findings = []
          lines = src.lines
          # A demonstration — a terminal transcript, one prized source excerpt —
          # earns its place once the argument is made, under the closing heading.
          # A fence before that chops the flowing prose the rest of this rule
          # exists to protect; a table chops it anywhere.
          last_heading = lines.rindex { |line| line.start_with?("## ") } || -1
          lines.each_with_index do |line, index|
            findings << finding(line: index + 1, message: "a code block interrupts the prose — a demonstration belongs under the final heading, not mid-argument") if line.start_with?("```") && index < last_heading
            findings << finding(line: index + 1, message: "README carries a table — say it in a sentence") if line.match?(/\A\s*\|.*\|\s*\z/)
          end
          lead = src.sub(/\A#\s+[^\n]+\n+/, "").lstrip
          # A hero image or video (and its HTML comment) may sit between the
          # title and the opening line — skip it before checking the opening is
          # bold, so the face can lead the page and the prose still has to.
          lead = lead.sub(%r{\A(?:<!--.*?-->\s*|<(?:video|img|picture|p)\b[^>]*>.*?(?:</(?:video|picture|p)>|/?>)\s*)+}m, "").lstrip
          findings << finding(line: 1, message: "README opening is not bold — lead with one bold, visionary sentence") unless lead.empty? || lead.start_with?("**")
          findings
        end
      end
    end
  end
end
