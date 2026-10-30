# frozen_string_literal: true

# law/javascript.rb — every javascript law, one Law.define per law.
Law.define(:ASYNC_AWAIT) do
  source "ECMAScript 2017 — async/await over raw promises"
  detect { |line| line.match?(/\.then\(.*\.then\(.*\.then\(/) }
  fix "Use async/await for readability."
  bad  "a().then(b).then(c).then(d)"
  good "await a(); await b();"
end

# CONST_BY_DEFAULT lives once, in the registry (js_rules.rb): it reads the
# rest of the file to ask whether the variable is ever reassigned before it
# calls a `let` wrong. This line detector flagged every `let` in the tree,
# including the ones whose reassignment is the reason they are `let`.

Law.define(:FOR_OF) do
  source "Airbnb JS Style Guide — for...of over for...in"
  detect { |line| line.match?(/for\s*\(\s*(const|let|var)\s+\w+\s+in\s+/) }
  fix "for...in iterates prototype properties. Use for...of."
  bad  "for (const k in list) {"
  good "for (const k of list) {"
end

Law.define(:NO_VAR) do
  source "Airbnb JS Style Guide — no var (ES6 let/const)"
  # A declaration sits at a statement position: the start of a line, or straight
  # after a brace, a semicolon or an opening paren. \bvar\s+\w alone matched the
  # word anywhere, including inside a string — stt_endpointing.test.mjs carries
  # Norwegian speech fixtures, and "det var veldig hyggelig å høre" is the verb
  # "was", which this rule read as a variable declaration.
  detect { |line| line.match?(/(?:^|[{};(])\s*var\s+\w/) }
  fix "Use const (default) or let (when reassigned)."
  bad  "var x = 1;"
  # Both directions: a declaration is still caught after a brace, and the word
  # inside a sentence is not a declaration.
  good %(const x = 1;\nconst said = "det var veldig hyggelig";\n)
end

Law.define(:NULLISH_COALESCING) do
  source "ECMAScript 2020 — nullish coalescing (??)"
  # The fix line already says when `??` is the answer: where 0 or '' are valid
  # values. A bare `\w+ \|\| \w+` says nothing about that and fired on 21 of 41
  # JavaScript files — every boolean condition in the tree, where `??` is not an
  # improvement but a syntax error: `if (!this.tracking || this.startPos === null)`
  # cannot mix `??` with `||` unparenthesised, and `event.currentTarget ||
  # this.element` falls back between two objects, neither of which is ever 0.
  #
  # The defect needs a literal on the right — `x || 0`, `x || ''` — which is
  # where a falsy-but-valid left side silently takes the fallback. An identifier
  # or member expression on the right is an object default and idiomatic `||`.
  detect do |line|
    next false if line.match?(/\b(?:if|while|switch)\s*\(/)
    next false unless line.match?(/=\s*[^=]*\|\|/)
    next false if line.match?(/[!<>=]=/)
    # A numeric coercion answers NaN, not null, when its input is junk. `||` is
    # the operator that turns NaN into the default; `??` would let it through.
    next false if line.match?(/\b(?:Number|parseFloat|parseInt)\([^()]*\)\s*\|\|/)

    line.match?(/\|\|\s*(?:-?\d+(?:\.\d+)?|""|''|``)\s*[;,)\]}]?\s*$/)
  end
  fix "Use ?? when 0 or '' are valid values."
  bad  "const n = count || 0"
  good "const n = count ?? 0"
end

Law.define(:OPTIONAL_CHAINING) do
  source "ECMAScript 2020 — optional chaining (?.)"
  detect { |line| line.match?(/(\w+)\s*&&\s*\1\.\w+/) }
  fix "Rewrite to obj?.foo?.bar"
  bad  "user && user.name"
  good "user?.name"
end

Law.define(:TEMPLATE_LITERALS) do
  source "Airbnb JS Style Guide — template literals (ES6)"
  detect { |line| line.match?(/["']\s*\+\s*\w+\s*\+\s*["']/) }
  fix "Use `Hello ${name}!` template literals."
  bad  "'Hello ' + name + '!'"
  good "`Hello ${name}!`"
end

# The face is a field of pixels, and a pixel has one size. The renderer draws
# into a capped buffer that CSS upscales with image-rendering:pixelated, so one
# fragment is one visible square block — a point that scales with depth or
# curvature stops being a pixel and becomes a blob, and a field of overlapping
# blobs is what made the face read as a lit wireframe mass. Depth, curvature and
# silhouette belong in brightness instead, which is where 1-bit imagery has
# always carried form.
Law.define(:FACE_POINT_IS_ONE_PIXEL) do
  source "pixel_perfection — MASTER/data/laws.yml, extended to WebGL"
  detect do |line|
    line.match?(/gl_PointSize\s*=/) && !line.match?(/gl_PointSize\s*=\s*1\.0\s*;/)
  end
  fix "One point, one pixel: gl_PointSize=1.0. Put depth and curvature into brightness, not size."
  bad  "  gl_PointSize=clamp(uSize*(260./-mv.z)*sizeBoost,2.0,4.0);"
  good "  gl_PointSize=1.0;"
end

# pixel_perfection bans soft glow in CSS. It was implemented in WebGL instead,
# where the CSS scanner could not see it: a second THREE.Points pass over the
# same geometry at 1.22x size with additive blending, which is a halo by
# construction. It also doubled every vertex and cost ~13 blended fragments per
# particle. The brutalist profile "removed" it by setting the scale to 1.0 —
# which co-sites the pass rather than deleting it, so the face just rendered
# twice as bright. A knob cannot switch off a layer that should not exist.
Law.define(:NO_WEBGL_GLOW_PASS) do
  source "pixel_perfection forbidden_css: soft glow — the WebGL spelling of it"
  detect { |line| line.match?(/blending:\s*THREE\.AdditiveBlending/) }
  fix "Delete the additive pass. Brightness states form; a second offset pass is a glow."
  bad  "    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending"
  good "    transparent: true, depthWrite: false"
end

Law.define(:TACTILE_FEEDBACK) do
  source "Haptic interaction feedback — optional secondary signal"
  ask "When haptic feedback is used, is it attached to a meaningful user action or threshold, fired at the start of direct manipulation when appropriate, gracefully unavailable, power-conscious, and never the only confirmation?"
  fix "Keep haptics short and optional, trigger them only for meaningful interactions, suppress them when the page is hidden or the device is power-constrained, and preserve a visible or semantic equivalent."
  bad "navigator.vibrate([100,100,100,100,100]) for every hover or pointermove"
  good "pointerdown → brief tick; commit → success pattern; unsupported or suppressed → visible feedback remains"
end

Law.define(:POINTER_FEEDBACK_EARLY) do
  source "Pointer Events — early input acknowledgement"
  ask "Does a direct-manipulation interaction acknowledge pointer input at pointerdown or an equivalent active state instead of making a click handler carry all perceived responsiveness? Preserve keyboard and assistive-technology behavior."
  fix "Move only the immediate acknowledgement to pointerdown/active state; leave the actual command and confirmation semantics on the existing action path."
  bad "button.addEventListener('click', showPressedState)"
  good "button.addEventListener('pointerdown', showPressedState)"
end

Law.define(:HAPTIC_SINGLE_SOURCE) do
  source "Shared RAILS haptics controller — one tactile implementation"
  ask "Does Rails interaction code use the shared haptics implementation instead of reaching directly for navigator.vibrate, so suppression, timing and future native adapters remain one source of truth?"
  fix "Import the shared pub4/haptics controller or its pulse API. Keep raw navigator.vibrate behind that shared implementation."
  bad "navigator.vibrate(10)"
  good "Haptics.pulse(10)"
end

module Master
  module Review
    module Scan
      module Laws
        # Retired registry twins — each lives once, in law/:
        #   DOLLAR_PAREN
        # (test_scan_rule_contracts proves each reaches findings through the bridge).

        VENDORED_JS_RE = %r{/public/three\.module\.js\z}.freeze

        ::Law.define(:CONST_BY_DEFAULT) do
          tags %i[IMMUTABLE]
          fix "use const unless reassigned"
          bad "let total = 0\n"
          good "let total = 0\ntotal += 1\n"
          check do |src, path|
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
        end

        # NULLISH_COALESCING lives once, in law/javascript.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # TEMPLATE_LITERALS lives once, in law/javascript.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # ASYNC_AWAIT lives once, in law/javascript.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # FOR_OF lives once, in law/javascript.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).
        ::Law.define(:QUOTE_VARIABLES) do
          tags %i[ROBUSTNESS]
          fix "quote $variables where the shell word-splits"
          bad "#!/bin/bash\ngrep $pattern file\n"
          good "#!/bin/zsh\ngrep $pattern file\n"
          check do |src, path|
            # Quoting is a fact about the interpreter: zsh does not word-split or
            # glob an unquoted parameter expansion; sh, ksh and bash all do. The
            # deep scan's 455 zsh findings were idiomatic code flagged by a sh
            # doctrine, so the rule reads the shebang before it judges.
            shebang = src.lines.first.to_s
            next [] unless shebang.match?(%r{\A#!.*\b(?:sh|ksh|bash)\b}) && !shebang.include?("zsh")
            # Even where the shell splits, three shapes never do and one splits
            # on purpose: an assignment (var=$x is unsplit in every shell), a
            # [[ ]] test (ksh and bash suppress splitting inside it), text in
            # single quotes (awk positionals), and `for x in $list` (the split
            # IS the iteration). Only an unquoted expansion in argument
            # position remains — the shape that actually breaks.
            # Line-lexed, statefully: heredoc bodies and the insides of a
            # multi-line double-quoted string are text, not argument position,
            # and a per-line regex cannot know that without carrying the state.
            heredoc_end = nil
            in_dquote = false
            in_squote = false
            src.each_line.with_index(1).filter_map do |line, n|
              if heredoc_end
                heredoc_end = nil if line.strip == heredoc_end
                next
              end
              if in_squote
                in_squote = false if line.count("'").odd?
                next
              end
              if in_dquote
                in_dquote = false if line.count('"') - line.scan(/\\"/).size == 1
                next
              end
              # State first, even on lines the skips below would drop: an awk
              # program often opens its single quote on an assignment line.
              if (m = line.match(/<<-?\s*["']?(\w+)["']?/))
                heredoc_end = m[1]
              end
              bare = line.gsub(/"(?:\\.|[^"\\])*"/, '""').gsub(/'[^']*'/, "''")
                         .gsub(/\[\[.*?\]\]/, "[[]]").gsub(/\$0\b/, "")
              in_dquote = true if bare.scan(/(?<!\\)"/).size.odd?
              in_squote = true if line.gsub(/"(?:\\.|[^"\\])*"/, "").count("'").odd?
              next if in_dquote || in_squote
              next if line.lstrip.start_with?("#")
              next if line.match?(/\A\s*(?:typeset|local|export|readonly)?\s*\w+=[^=]/)
              next if line.match?(/\bfor\s+\w+\s+in\b/)
              # `case $x in` never field-splits its word; `set -- $x` IS the split.
              next if line.match?(/\bcase\s+\$\w+\s+in\b/) || line.match?(/\bset\s+--\s+\$/)
              next unless bare.match?(/(?<!\\)\$\w+/)
              # Beyond this line lexer: a nested command substitution carrying its
              # own quotes ($(field "$x" 1) inside a string) can leave one false
              # positive; shellcheck is the tool that lexes that, when it lands.
              finding(line: n, message: "unquoted $variable in argument position — word-splits in this shell; wrap in double quotes")
            end
          end
        end

        ::Law.define(:DOUBLE_BRACKET) do
          tags %i[ROBUSTNESS]
          fix "use [[ ]] over [ ]"
          bad "#!/bin/zsh\nif [ -f x ]; then echo y; fi\n"
          good "#!/bin/zsh\nif [[ -f x ]]; then echo y; fi\n"
          check do |src, path|
            # POSIX sh shebang — [[ ]] is a keyword only in zsh/bash/ksh, not in sh.
            # A sourced library has no shebang, so it declares its dialect in its
            # opening comment instead, the way lib/ci_lock.sh does.
            next [] if src.lines.first.to_s.match?(%r{#!/(?:usr/bin/env sh|bin/sh)\b|\A#\s*POSIX sh\b})
            # A comment quoting `[ -x file ]` describes a test rather than running one.
            scan_lines(without_comment_lines(src), /(?<!\[)\[\s+[^\[]/, message: "[ ] test — use [[ ]] in zsh")
          end
        end

        # NO_VAR lives once, in law/javascript.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        ::Law.define(:JS_MODULE_SIZE) do
          tags %i[SMALL_PARTS]
          fix "JS files over 300 lines — split at module boundaries"
          bad ("// line\n" * 301)
          good ("// line\n" * 300)
          check do |src, path|
            next [] if path.to_s.match?(VENDORED_JS_RE)

            line_count = src.lines.size
            next [] if line_count <= 300
            [finding(line: 1, message: "JS file #{line_count} lines — split at 300; extract cohesive modules",
                      blast_radius: Detector::SPANS_FILES)]
          end
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
        ::Law.define(:MAGIC_COLOR) do
          tags %i[DESIGN]
          fix "color values must reference design tokens, not raw hex/rgb"
          bad ".btn { color: #c0392b; }\n"
          good ":root { --danger: #c0392b; }\n"
          check do |src, path|
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
              # (?<![\w-]): a # preceded by a word char is not a colour — Stimulus
              # action descriptors (nested-form#add) spell controller#method.
              /(?<![\w-])#[0-9a-fA-F]{3,6}\b/ => "raw hex color — use CSS custom property or design token",
              # rgb(from var(--x) ...) is relative colour syntax DERIVING from
              # the token — that is citing it, not bypassing it.
              /\brgba?\s*\((?!from\s+var\()/ => "raw rgb() color — use CSS custom property or design token",
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
        end

      # A11 OPTIONAL_CHAINING_JS — && guard chains in JavaScript (OPTIONAL_CHAINING).
        ::Law.define(:OPTIONAL_CHAINING_JS) do
          tags %i[READABILITY]
          fix "use ?. over && chains"
          bad "const name = user && user.name\n"
          good "const name = user?.name\n"
          check do |src, path|
            scan_lines(src, /(\w+)\s*&&\s*\1\.\w+/, message: "nil-guard chain — use optional chaining (?.) instead")
          end
        end

      end
    end
  end
end
