# frozen_string_literal: true

module Master
  module Review
    module Scan
      require_relative "finding"

      class Rule
        EXT_LANG = Master::FILE_LANGUAGE_MAP
        COMMENT_LINE = %r{^[ \t]*(#|//)[^\n]*}

        attr_reader :id, :description, :severity, :rule_tags, :auto_fix

        @registry = []
        @registry_mutex = Mutex.new

        def self.inherited(subclass)
          @registry_mutex.synchronize { @registry << subclass }
        end

        def self.registry
          @registry_mutex.synchronize { @registry.dup }
        end

        # Rules that need constructor args (root:, agent:) override this to false.
        # Builder uses it to auto-discover zero-arg rules from the registry.
        def self.auto_build?
          true
        end

        def initialize
          @id = self.class.name&.split("::")&.last&.downcase || "unknown"
          @description = ""
          @severity = :warning
          @rule_tags = []
          @auto_fix = true
        end

        # Default for AST-based rules: subclasses implement check_ast(ast, code,
        # path:) and get this for free instead of repeating it. This exact body
        # was copy-pasted byte-for-byte across 11 rule classes in
        # structural_rules.rb/convention_rules.rb before being hoisted here.
        # Rules with non-AST logic (e.g. SmallFilesRule's line-count check)
        # override #check directly and never hit this default.
        def check(code, path:)
          raise NotImplementedError, "#{self.class}#check not implemented" unless respond_to?(:check_ast)

          return [] unless path.to_s.end_with?(".rb", ".rake")

          check_ast(Prism.parse(code).value, code, path:)
        rescue StandardError
          []
        end

        def language(path)
          return "javascript" if File.basename(path).match?(/\Aface\.part\d+\.txt\z/)
          EXT_LANG[File.extname(path).downcase]
        end

        def applies_to?(path, languages)
          return true if languages.nil? || languages.empty?
          lang = language(path)
          lang && languages.include?(lang)
        end

        protected

        def finding(line:, message:, fix: nil, confidence: nil, why: nil, genealogy: nil, impact_radius: nil, dedupe_key: nil)
          Finding.build(
            rule: @id,
            message:,
            line:,
            severity: @severity,
            fix:,
            tags: @rule_tags,
            confidence: confidence || default_confidence,
            why: why || default_why(message),
            genealogy: genealogy || default_genealogy(message),
            dedupe_key: dedupe_key || default_dedupe_key(message),
            impact_radius:,
          )
        end

        def scan_lines(code, pattern, message:, fix: nil)
          code.each_line.with_index(1).filter_map do |line, num|
            finding(line: num, message:, fix:) if line.match?(pattern)
          end
        end

        # A raw regex over raw lines makes a comment that names the thing the rule
        # forbids into a finding about itself. BARE_RESCUE and FAIL_VISIBLY both
        # fired on the paragraph in lexical_rules.rb explaining which rescue shape
        # each rule owns; veto unsafe_calls fires on a comment describing a shell
        # interpolation. Blanked to spaces, so line numbers still line up.
        #
        # Comment-only lines, not trailing comments: blanking from an unquoted `#`
        # needs to know whether it is inside a string, and guessing wrong drops real
        # findings. This is the half that is provably safe. scan_lines itself is
        # deliberately untouched — several rules mean to read comments.
        def without_comment_lines(code) = code.gsub(COMMENT_LINE) { |line| " " * line.length }

        # The same trick for ERB output tags, and for the same reason.
        #
        # Attribute rules ask "does this tag contain alt=" as `<img\s+(?![^>]*alt=)`.
        # `[^>]*` cannot cross a `>` — and `<%= deal.image_url %>` ends in one. So on
        # the ordinary Rails shape
        #
        #   <img src="<%= deal.image_url %>" alt="<%= deal.title %>">
        #
        # the lookahead gives up at the `%>` of src, never reaches alt=, and the rule
        # reports a missing alt on a tag that has one. Every <img> in this repo whose
        # src is dynamic and whose alt comes after it was a finding; all four IMG_ALT
        # hits across the fleet were this, and none was a real missing alt. The rule
        # could not pass on correct Rails markup, which makes its zero unreachable
        # and its findings unactionable.
        #
        # Blanked to spaces with newlines kept, so line numbers and multi-line tags
        # both survive.
        ERB_OUTPUT = /<%.*?%>/m
        def without_erb_tags(code) = code.gsub(ERB_OUTPUT) { |tag| tag.gsub(/[^\n]/, " ") }

        # Blanking ERB is half of it. The other half is that scan_lines asks the
        # question one line at a time, and these views wrap tag attributes:
        #
        #   <input type="text" placeholder="…"
        #          aria-label="…"
        #          data-…-target="commentInput">
        #
        # Line 1 holds no aria-label and no `>`, so `[^>]*` runs to end-of-line and
        # the lookahead reports a missing label on a labelled control. Every
        # FORM_LABEL hit that survived the ERB fix was this shape.
        #
        # Each multi-line tag is rewritten onto its opening line and its newlines
        # moved after it, so the tag is matchable in one piece, the finding still
        # reports the line the tag opens on, and every later line keeps its number.
        # Quote-aware, because `>` is legal inside an attribute value and this repo
        # has it: `data-action="input->playlist#setVolume"` and an embed field whose
        # value is an escaped <iframe …></iframe>. A plain [^<>]* ends the tag at
        # that `>` and loses every attribute after it.
        MULTILINE_TAG = /<[a-zA-Z](?:"[^"]*"|'[^']*'|[^<>"'])*>/m
        def with_tags_flattened(code)
          spans = code.to_enum(:scan, MULTILINE_TAG).filter_map do
            m = Regexp.last_match
            [m.begin(0), m.end(0), m[0]] if m[0].include?("\n")
          end
          result = code.dup
          spans.reverse_each do |from, to, text|
            result[from...to] = text.gsub(/\s*\n\s*/, " ") + ("\n" * text.count("\n"))
          end
          result
        end

        # What an HTML attribute rule should read: no ERB, one tag per line.
        def tag_source(code) = with_tags_flattened(without_erb_tags(code))

        # A control wrapped in a <label> that has text is labelled — that is the
        # implicit association in the HTML spec, and the most common spelling of it
        # here:
        #
        #   <label class="field--check-label">
        #     <input type="checkbox" name="…">
        #     <span><%= t("newsletter.marketing_consent") %></span>
        #   </label>
        #
        # FORM_LABEL looked only for aria-label/aria-labelledby/id=, so it asked for
        # an explicit label on controls that already had one and would have been
        # "fixed" by bolting a redundant aria-label onto correct markup. Every
        # remaining FORM_LABEL finding across the fleet was this or a `>` inside an
        # attribute value; none was an unlabelled control.
        LABEL_ELEMENT = %r{<label\b[^>]*>.*?</label>}m
        def without_labelled_controls(code) = code.gsub(LABEL_ELEMENT) { |el| el.gsub(/[^\n]/, " ") }

        # What a control-labelling rule should read: also blind to controls whose
        # <label> wrapper already names them.
        def control_source(code) = with_tags_flattened(without_labelled_controls(without_erb_tags(code)))

        # Does the CSS block containing `line_number` paint a dark background?
        #
        # Contrast is a relation, so a rule that reads only the foreground cannot
        # answer it. Walks back to the nearest `{` — the enclosing rule — and takes
        # the last background colour declared in it. Deliberately narrow: a
        # background set on a parent selector, or in a token, is not visible from
        # here, so this says "no" and the finding stands.
        BACKGROUND_HEX = /background(?:-color)?\s*:\s*#([0-9a-fA-F]{3,8})\b/
        def dark_background_near?(code, line_number)
          lines = code.lines
          start = line_number - 1
          start -= 1 while start.positive? && !lines[start].to_s.include?("{")
          block = lines[start..(line_number - 1)].to_s
          hex = block.scan(BACKGROUND_HEX).flatten.last or return false

          relative_luminance(hex) < 0.4
        end

        def relative_luminance(hex)
          h = hex.length < 6 ? hex.chars.flat_map { |c| [c, c] }.join : hex
          r, g, b = h[0, 6].scan(/../).map { |pair| pair.to_i(16) / 255.0 }
          (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
        end

        def default_confidence
          case @severity
          when :error then 0.9
          when :warning then 0.78
          else 0.62
          end
        end

        def default_why(message)
          "#{message} because it tends to increase maintenance risk and regression cost."
        end

        def default_genealogy(message)
          [@rule_tags.first || "GENERAL", @id, message.to_s.split(" — ").first.to_s]
        end

        def default_dedupe_key(message)
          "#{@id}:#{message.to_s.downcase.gsub(/\b\d+\b/, "#")}"
        end
      end
    end
  end
end
