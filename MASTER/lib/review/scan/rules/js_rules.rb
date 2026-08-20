# frozen_string_literal: true

module Master
  module Review
    module Scan
      module Rules
        VENDORED_JS_RE = %r{/public/three\.module\.js\z}.freeze

        RuleDSL.rule :CONST_BY_DEFAULT,
          severity: :warning, tags: %i[IMMUTABLE], applies_to: %i[javascript],
          description: "use const unless reassigned" do |src, path:|
          next [] if path.to_s.match?(VENDORED_JS_RE)

          lines = src.lines
          lines.each_with_index.filter_map do |line, idx|
            match = line.match(/\blet\s+([A-Za-z_$][\w$]*)\s*=/)
            next unless match

            name = Regexp.escape(match[1])
            tail = line[match.end(0)..].to_s
            rest = lines[(idx + 1)..].join
            reassigned = tail.match?(/\b#{name}\s*(?:[+\-*\/%&|^]?=|\+\+|--)/) ||
                         rest.match?(/\b#{name}\s*(?:[+\-*\/%&|^]?=|\+\+|--)/)
            next if reassigned

            finding(line: idx + 1, message: "let — use const unless value is reassigned")
          end
        end

        RuleDSL.rule :NULLISH_COALESCING,
          severity: :info, tags: %i[READABILITY], applies_to: %i[javascript],
          description: "use ?? over || for defaults" do |src, path:|
          next [] if path.to_s.match?(VENDORED_JS_RE)

          scan_lines(src, /(\w+)\s*\|\|\s*\w+/, message: "foo || default — use foo ?? default to avoid falsy traps")
        end

        RuleDSL.rule :TEMPLATE_LITERALS,
          severity: :warning, tags: %i[READABILITY], applies_to: %i[javascript],
          description: "use template literals over concatenation" do |src, path:|
          next [] if path.to_s.match?(VENDORED_JS_RE)

          scan_lines(src, /["']\s*\+\s*\w+\s*\+\s*["']/,
                     message: "string concatenation — use template literal \`…\${var}…\`")
        end

        RuleDSL.rule :ASYNC_AWAIT,
          severity: :warning, tags: %i[READABILITY], applies_to: %i[javascript],
          description: "prefer async/await over .then chains" do |src, path:|
          next [] if path.to_s.match?(VENDORED_JS_RE)

          scan_lines(src, /\.then\(.*\.then\(.*\.then\(/, message: "3+ .then chain — convert to async/await")
        end

        RuleDSL.rule :FOR_OF,
          severity: :error, tags: %i[CORRECTNESS], applies_to: %i[javascript],
          description: "use for...of instead of for...in for arrays" do |src, path:|
          next [] if path.to_s.match?(VENDORED_JS_RE)

          scan_lines(src, /for\s*\(\s*(const|let|var)\s+\w+\s+in\s+/,
            message: "for...in iterates keys — use for...of for array values")
        end

        RuleDSL.rule :QUOTE_VARIABLES,
          severity: :error, tags: %i[ROBUSTNESS], applies_to: %i[zsh],
          description: "always quote $variables" do |src, path:|
          scan_lines(src, /(?<!["'\\])\$\w+(?!["'])/, message: "unquoted $variable — wrap in double quotes")
        end

        RuleDSL.rule :DOUBLE_BRACKET,
          severity: :warning, tags: %i[ROBUSTNESS], applies_to: %i[zsh],
          description: "use [[ ]] over [ ]" do |src, path:|
          # POSIX sh shebang — [[ ]] is a keyword only in zsh/bash, not in sh
          next [] if src.lines.first.to_s.match?(%r{#!/(?:usr/bin/env sh|bin/sh)\b})
          scan_lines(src, /(?<!\[)\[\s+[^\[]/, message: "[ ] test — use [[ ]] in zsh")
        end

        RuleDSL.rule :DOLLAR_PAREN,
          severity: :warning, tags: %i[READABILITY], applies_to: %i[zsh],
          description: "replace backticks with $(command)" do |src, path:|
          scan_lines(src, /`[^`]+`/, message: "backtick substitution — use $(command) for clarity")
        end

        RuleDSL.rule :NO_VAR,
          severity: :error, tags: %i[CORRECTNESS], applies_to: %i[javascript],
          description: "var is function-scoped and hoisted — use const or let" do |src, path:|
          next [] if path.to_s.match?(VENDORED_JS_RE)

          scan_lines(src, /\bvar\s+\w/, message: "var declaration — use const (default) or let (when reassigned)")
        end

        RuleDSL.rule :JS_MODULE_SIZE,
          severity: :warning, tags: %i[SMALL_PARTS], applies_to: %i[javascript],
          description: "JS files over 300 lines — split at module boundaries" do |src, path:|
          next [] if path.to_s.match?(VENDORED_JS_RE)

          line_count = src.lines.size
          next [] if line_count <= 300
          [finding(line: 1, message: "JS file #{line_count} lines — split at 300; extract cohesive modules")]
        end

        # STIMULUS_CONTROLLER_SIZE lives in surface_rules.rb with the rest of the
        # STIMULUS_* family; the copy that stood here was a duplicate registration of
        # the same id (SINGULARITY) and double-counted every hit — test_rule_ids_unique.

      # A02 MAGIC_COLOR — raw color values must reference design tokens (MAGIC_COLOR).
      #
      # Before trying to fix these in bulk, read this. It has been measured twice,
      # from two directions, and the answer both times was that there is no
      # mechanical substitution available in this repo.
      #
      # A substitution is only safe if it preserves the rendered value. The tokens
      # whose values match the commonest literals — --bg, --surface, --border,
      # --search-bg — are theme-responsive: _dialect_tokens.scss defines them
      # inside @mixin brgen-old-dark-tokens and @mixin brgen-old-light-tokens, and
      # brgen includes both, under different selectors. So `--bg` is #000000 in
      # dark and #ffffff in light *within one app*. A literal is theme-independent
      # by construction; swapping it for the token makes it follow the theme,
      # which changes the other theme. That is a behaviour change wearing the
      # clothes of a lint fix.
      #
      # Scoping per app does not rescue it: brgen defines four single-valued
      # tokens of its own and no remaining literal equals any of them.
      #
      # So the question each finding actually asks is not "which token is this" —
      # it is "should this colour follow the theme or not", which only the person
      # who chose it can answer. Six passes over this rule removed 596 findings
      # and every one was the rule misreading something; none was a substitution.
        RuleDSL.rule :MAGIC_COLOR,
          severity: :warning, tags: %i[DESIGN], applies_to: %i[css scss javascript html],
          description: "color values must reference design tokens, not raw hex/rgb" do |src, path:|
          next [] if path.to_s.match?(%r{/spec/|/test/})
          next [] if File.basename(path.to_s).match?(/\Aface\.part\d+\.txt\z/)
          # A documented brand parody or a token source declares raw colors
          # intentional with `scan: intentional-colors` in its head; one line opts
          # out with an inline `scan: intentional`. A `--x:`/`$x:` line is a token
          # definition — where a raw value belongs — not a usage that should cite one.
          next [] if src.lines.first(20).join.match?(/scan:\s*intentional-colors/)
          # Email cannot use custom properties. Outlook, Gmail's web client and
          # every other mail renderer drop var() and leave the declaration
          # unresolved, so _mailer_styles.html.erb is written in hex on purpose —
          # 25 findings telling the one file that must not cite a token to cite
          # one. The rest of the fleet is unaffected by this exemption because
          # nothing else renders into a mail client.
          next [] if path.to_s.match?(/mailer/)
          # The OS-level colour declarations, which are not CSS and cannot hold a
          # var(). A web app manifest is JSON the operating system reads to paint
          # the task switcher and splash screen, and <meta name="theme-color">
          # colours the browser chrome itself — both take a literal or nothing.
          next [] if File.basename(path.to_s).start_with?("manifest.json")

          # Anchored to line start OR to an opening brace, because a theme override
          # is routinely written on one line: `:root { --border: #2c2824; }` inside
          # a media query. Anchored only at the start, the guard saw `:root {` and
          # called the definition a usage — and this was the last MAGIC_COLOR
          # finding in the tree that looked substitutable, which is what sent me
          # looking at it.
          definition = /(?:\A|\{)\s*(--[\w-]+|\$[\w-]+)\s*:/
          messages = {
            /#[0-9a-fA-F]{3,6}\b/ => "raw hex color — use CSS custom property or design token",
            /\brgba?\s*\(/ => "raw rgb() color — use CSS custom property or design token",
            /\bhsla?\s*\(/ => "raw hsl() color — use CSS custom property or design token",
          }
          # Comment lines blanked, which is what without_comment_lines exists for
          # and what its own note predicts: "a comment that names the thing the
          # rule forbids [becomes] a finding about itself". Here that was a
          # comment explaining *why* a colour was chosen — `// #d8d6e0 is brgen's
          # own --text` — reported as a raw colour, and the note recording that a
          # source pen used #fe9900 reported as a colour to tokenise.
          #
          # Canvas is the other one. `ctx.fillStyle = "#222"` is not a style
          # choice avoiding a token, it is the only form the 2D context accepts:
          # CSS custom properties do not resolve inside canvas, WebGL or Three.js
          # material colours. Asking these to cite a token asks for something that
          # does not render.
          canvas_sink = /\b(?:fillStyle|strokeStyle|shadowColor|backgroundColor|setHexColor)\b|\bnew\s+THREE\.Color\b|theme-color|theme_color/
          scanned = without_var_fallbacks(without_block_comments(without_erb_comments(without_comment_lines(src))))
          # Stylesheets get the value-position filter; JS and HTML do not, because
          # a colour there is an argument or an attribute, not a declaration.
          scanned = declaration_values_only(without_mask_gradients(scanned)) if path.to_s.match?(/\.(css|scss)\z/)
          # Guards read the ORIGINAL line, the search reads the filtered one. The
          # value filter strips the `--token:` prefix, so asking `definition` about
          # the filtered line stopped recognising token definitions and counted
          # every one of them — 234 findings became 333 before this was split.
          original = src.lines
          scanned.each_line.with_index(1).flat_map do |line, number|
            raw = original[number - 1].to_s
            next [] if raw.match?(/scan:\s*intentional/) || raw.match?(definition)
            next [] if raw.match?(canvas_sink)

            messages.filter_map { |pattern, message| finding(line: number, message:) if line.match?(pattern) }
          end
        end

      # A11 OPTIONAL_CHAINING_JS — && guard chains in JavaScript (OPTIONAL_CHAINING).
        RuleDSL.rule :OPTIONAL_CHAINING_JS,
          severity: :warning, tags: %i[READABILITY], applies_to: %i[javascript],
          description: "use ?. over && chains" do |src, path:|
          scan_lines(src, /(\w+)\s*&&\s*\1\.\w+/, message: "nil-guard chain — use optional chaining (?.) instead")
        end

      end
    end
  end
end
