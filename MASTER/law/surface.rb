# frozen_string_literal: true

module Master
  module Review
    module Scan
      module Laws
        # Surface law: pixel/UI aesthetic + Rails HTML/JS/ERB conventions.
        # One file — views, CSS, Stimulus, touch targets, flat design.

        # Pixel-perfect UI/UX rules restored from master.yml aesthetics + design_laws.yml.
        # Applies to MASTER/web face, ERB views, and pub4/RAILS SCSS/HTML.

        UI_PATH = %r{(?:/app/views/|/app/assets/|/web/public/|/web/app/|face\.|/RAILS/)}i.freeze
        CSS_LANGS = %i[css scss].freeze
        HTML_LANGS = %i[html].freeze

        module_function

        def ui_path?(path)
          path.to_s.match?(UI_PATH) || path.to_s.include?("views") || path.to_s.end_with?(".erb", ".html", ".scss", ".css")
        end

        def thresholds
          Master::Design::Thresholds
        end
        
        # The design scale's rules over tokens.yml#scale, shared with ScaleLint and
        # AstFixer#snap_to_design_scale. Read once per process.
        def design_scale
          @design_scale ||= Master::Design::Scale.new(Master.tokens.fetch("scale"))
        end

        # STIMULUS_CONTROLLER_SIZE's numbers are declared, not invented here:
        # data/laws.yml carries `detect_structural: {max_lines: 200,
        # path_pattern: "_controller\.js$"}` and this rule held both as literals,
        # which is a declaration with no reader — the defect this repo hunts most
        # often, sitting inside the file that declares the hunt. Read once per
        # process: laws.yml is four thousand lines and load_laws memoizes
        # nothing.
        def stimulus_limits
          @stimulus_limits ||= begin
            entry = Master.law_entries(root: Master::ROOT)
                          .find { |r| r["id"].to_s.upcase == "STIMULUS_CONTROLLER_SIZE" }

            config = entry && entry["detect_structural"]
            config.is_a?(Hash) ? config : {}
          end
        end

        ::Law.define(:NO_DECORATIVE_FX) do
          tags %i[DESIGN AESTHETIC PIXEL]
          fix "flat UI — no blur, glow, or ornamental shadow"
          ask "Does the element use shadows or glows that serve no functional purpose?"
          # Structural question: Check for 'glow' or 'shadow' in filenames or directory names
          example_path "/repo/app/assets/stylesheets/_example.scss"
          bad ".card { box-shadow: 0 2px 8px rgba(0,0,0,.3); }\n"
          good ".card { box-shadow: none; }\n.b { text-shadow: none; }\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            findings = []
            # Block comments blanked: a rationale paragraph explaining a measured
            # value is prose, and its continuation lines do not start with * .
            without_block_comments(src).each_line.with_index(1) do |line, num|
              next if line.strip.start_with?("//", "/*", "*")

              # Allow a suppressed shadow — `none`, or an all-zero value. The old
              # pattern matched `0\s`, which is the first token of every real
              # shadow too: `box-shadow: 0 2px 8px rgba(0,0,0,.3)` was skipped as
              # if it were a suppression. Found by this rule's own fixture,
              # 2026-08-07. Match the whole value instead of its first token.
              next if line.match?(/box-shadow\s*:\s*(none|0(?:\s+0)*(?:\s+0)?)\s*(?:!important)?\s*;/i)
              next if line.match?(/text-shadow\s*:\s*(none|0(?:\s+0)*(?:\s+0)?)\s*(?:!important)?\s*;/i)

              if line.match?(/box-shadow\s*:/i) || line.match?(/text-shadow\s*:/i)
                findings << finding(line: num, message: "ornamental shadow — flat UI: use border/contrast, not glow (design_rules pixel_perfection)")
              end
              if line.match?(/filter\s*:\s*[^;]*blur\s*\(/i) || line.match?(/backdrop-filter\s*:/i)
                findings << finding(line: num, message: "blur/backdrop-filter — forbidden decorative FX for pixel-perfect flat surfaces")
              end
            end
            findings
          end
        end

        ::Law.define(:FLAT_PIXELS) do
          # One Law at two depths: the practice is the design principle, which binds
          # what gets built before there is a line to detect; the check is its lexical
          # detector for imageSmoothingEnabled and bloom/scanline language in a canvas
          # layer. They were two declarations in two files until the Law systems merged.
          source "MASTER constitution (soul.yml absolute.rules)"
          practice <<~TEXT
            Flat Design — UI and particles stay two-dimensional, uniform in size and
            alpha, with no fake depth or parallax. Exception: pixels that collectively
            resemble a 3D model, as in face mode.
          TEXT
          tags %i[DESIGN AESTHETIC PIXEL]
          fix "Keep the surface flat: uniform size and alpha, no fake depth or parallax."
          ask "Is the rendering intent 'crisp' or 'pixel-art', yet smoothing is enabled?"
          # Structural question: Check for 'smoothing' or 'blur' in JS filename/path
          example_path "/repo/web/public/face_vision.js"
          bad "ctx.imageSmoothingEnabled = true;\n"
          good "ctx.imageSmoothingEnabled = false;\n"
          check do |src, path|
            next [] unless %w[css scss javascript].include?(language(path))
            findings = []

            if path.to_s.match?(/\.(js|ts)\z/) || File.basename(path.to_s).match?(/face/)
              src.each_line.with_index(1) do |line, num|
                if line.match?(/imageSmoothingEnabled\s*=\s*true/i)
                  findings << finding(line: num, message: "imageSmoothingEnabled=true — pixel field requires false (integer scale)")
                end

                # `particle` is out of this list. bloom, scanline, vaporwave and crt
                # name decorative effects a flat surface does not want; a particle
                # is a rendering primitive, and this product's face is built from
                # them — face_vision_b.js opens "MASTER particle face 2026" and
                # face.part1.txt says it eight times. The rule was telling MASTER's
                # own particle face to stop calling itself one, and objecting to the
                # physics of a named feature (radio_brgen_tunnel's particle tunnel)
                # as though `particle.z += zDelta` were a style choice. 35 findings,
                # none actionable.
                if line.match?(/\b(bloom|scanline|vaporwave|crt)\b/i) && !line.strip.start_with?("//", "*", "/*")
                  findings << finding(line: num, message: "decorative particle/CRT language — use pixel-field/semantic cell terms per design_rules")
                end
              end
            end

            findings
          end
        end

        # The doctrine is Müller-Brockmann's (Grid Systems in Graphic Design,
        # 1981): a single spatial module, every dimension a multiple of it —
        # named here so the rule carries its book, not just its number.
        # Grid structure is a composition law, not a requirement that every page use CSS Grid.
        # The static pass catches only a high-signal anti-pattern; it leaves unusual
        # but legitimate overlays to the semantic review and rendered geometry checks.
        ::Law.define(:GRID_STRUCTURE) do
          tags %i[DESIGN LAYOUT]
          fix "grid structure — shared tracks, consistent alignment and parent-owned gap"
          ask "Does the interface express repeated relationships with coherent grid or flex tracks and parent-owned gap rather than arbitrary per-child offsets and widths?"
          # Structural question: Find grid-like containers whose direct children combine absolute positioning, a fixed physical offset and a fixed wide width.
          example_path "/repo/app/assets/stylesheets/_example.scss"
          bad ".cards > * { position: absolute; left: 17px; width: 243px; }\n"
          good ".cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 16rem), 1fr)); gap: var(--space-4); }\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            clean = without_block_comments(src)
            findings = []
            clean.to_enum(:scan, /([^{}\n]+)\{([^{}]*)\}/m).each do
              match = Regexp.last_match
              selector = match[1].strip
              body = match[2]

              next unless selector.match?(/(?:grid|cards|items|results|columns|layout|feed)\b/i)
              next unless selector.match?(/>\s*\*/)
              next unless body.match?(/\bposition\s*:\s*absolute\b/i)
              next unless body.match?(/\b(?:left|right|inset-inline-start|inset-inline-end)\s*:\s*-?\d+(?:\.\d+)?px\b/i)
              next unless body.match?(/\bwidth\s*:\s*\d{3,}(?:\.\d+)?px\b/i)

              line = clean[0...match.begin(0)].count("\n") + 1
              findings << finding(
                line:,
                message: "grid-like direct children use absolute offsets and a fixed wide width — prefer shared grid/flex tracks and parent-owned gap",
              )
            end
            findings.uniq { |item| [item[:line], item[:message]] }
          end
        end

        # One scale for the ratchet, this Law and its repair: Master::Design::Scale
        # reads tokens.yml#scale.space_px. This allowed any multiple of 4 up to 96
        # beside the declared steps, so 52px passed here and failed ScaleLint, and the
        # 8px snap that repaired it turned the scale's own 1px hairline into 0px.
        ::Law.define(:EIGHT_PX_RHYTHM) do
          tags %i[DESIGN AESTHETIC]
          fix "spacing on the declared scale (tokens.yml scale.space_px) — Müller-Brockmann grid module"
          ask "Does the spacing step off the declared scale rather than follow its rhythm?"
          transform "snap_to_design_scale"
          example_path "/repo/app/assets/stylesheets/_example.scss"
          bad ".card { padding: 10px; }\n"
          good "@media (min-width: 1280px) { .card { padding: 24px; min-height: 44px; } }\n.rule { margin: 1px 0; }\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)
        
            scale = ::Master::Review::Scan::Laws.design_scale
            rules = ::Master::Design::Scale
            raw = src.lines
            findings = []
            without_block_comments(src).each_line.with_index(1) do |line, num|
              next if line.strip.start_with?("//")
              next if line.include?(rules::OPT_OUT) || (num > 1 && raw[num - 2].to_s.include?(rules::OPT_OUT))
        
              line.scan(rules::DECLARATION) do
                prop = Regexp.last_match[:prop]
                next unless rules::SPACE_PROPS.include?(prop)
        
                scale.off_scale_lengths(Regexp.last_match[:value]).each do |step|
                  px = rules.to_px(*step.match(rules::LENGTH).captures)
                  findings << finding(line: num, message: "#{step} #{prop} off the spacing scale — " \
                                                          "use #{scale.nearest(px).to_i}px (tokens.yml scale.space_px)")
                end
              end
        
              # Token *definitions* (e.g. --space-7: 1.75rem), not just call sites — a
              # usage-only scan is structurally blind to a bad value baked into the
              # token itself. Reported, never snapped: a token's value is the operator's.
              line.scan(/--[\w-]*(?:space|gap)[\w-]*\s*:\s*(-?[\d.]+)(px|rem)\b/i) do |value, unit|
                px = rules.to_px(value, unit.downcase)
                next if px.zero? || scale.space_px.include?(px.abs.round(3))
        
                findings << finding(line: num, message: "#{px.to_i}px spacing token off the scale — " \
                                                        "use #{scale.nearest(px).to_i}px (tokens.yml scale.space_px)")
              end
            end
            findings.uniq { |f| [f[:line], f[:message]] }
          end
        end

        ::Law.define(:LINE_HEIGHT_ON_SCALE) do
          tags %i[DESIGN TYPOGRAPHY RHYTHM]
          fix "unitless line-height must be on the declared scale (tokens.yml scale.line_height)"
          transform "snap_to_design_scale"
          example_path "/repo/app/assets/stylesheets/_example.scss"
          bad ".prose { line-height: 1.45; }\n"
          good ".prose { line-height: 1.5; }\n.h1 { line-height: 1.25; }\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)
        
            scale = ::Master::Review::Scan::Laws.design_scale
            rules = ::Master::Design::Scale
            steps = scale.line_heights.map { |step| step == step.to_i ? step.to_i : step }.join("/")
            raw = src.lines
            findings = []
            without_block_comments(src).each_line.with_index(1) do |line, num|
              next if line.strip.start_with?("//")
              next if line.include?(rules::OPT_OUT) || (num > 1 && raw[num - 2].to_s.include?(rules::OPT_OUT))
        
              line.scan(rules::DECLARATION) do
                next unless Regexp.last_match[:prop] == "line-height"
        
                value = Regexp.last_match[:value].strip
                case scale.line_height_kind(value)
                when :absolute
                  findings << finding(line: num, message: "absolute line-height #{value} — prefer a unitless step #{steps} " \
                                                          "(tokens.yml scale.line_height; ScaleLint absolute_line_height)")
                when :off_scale
                  findings << finding(line: num, message: "line-height #{value} off scale — use #{steps} " \
                                                          "(tokens.yml scale.line_height; RAILS ScaleLint)")
                end
              end
            end
            findings.uniq { |f| [f[:line], f[:message]] }
          end
        end

        ::Law.define(:TOUCH_TARGET_MIN) do
          tags %i[DESIGN UX ACCESSIBILITY]
          fix "Fitts — interactive targets ≥44px"
          ask "Is the interactive element's hit area too small for comfortable thumb use?"
          # Structural question: Check if mobile-specific views lack minimum target constraints
          bad ".btn {\n  width: 12px;\n}\n"
          good ".btn {\n  width: 48px;\n}\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            min = ::Master::Review::Scan::Laws.thresholds.touch_min_px.to_i
            button_re = Master::Fix::Scan::AstFixer::WebTransforms::TOUCH_SELECTOR
            findings = []
            current_selector = ""

            src.each_line.with_index(1) do |line, num|
              # Standard SCSS puts the selector and its width/height on
              # separate lines (`.carousel-btn {` then `width: 12px;` on the
              # next) -- a same-line-only check is structurally blind to that
              # shape, which is the normal one (found 2026-07-21, empirically:
              # this exact rule missed the exact bug it exists to catch).
              # Tracks only the innermost selector, not full brace depth --
              # doesn't handle deep nesting (e.g. `&:hover {}` losing outer
              # context), but covers the common flat-block case.
              current_selector = line if line.include?("{")

              next unless line.match?(/min-(?:width|height)|height|width/i)
              next unless "#{current_selector}\n#{line}".match?(button_re) ||
                          (line.match?(/min-height|height/) && path.to_s.include?("button"))

              line.scan(Master::Fix::Scan::AstFixer::WebTransforms::TOUCH_DIMENSION) do |raw|
                px = raw[0].to_i
                next if px >= min || px.zero?

                findings << finding(line: num, message: "touch target #{px}px < #{min}px (Fitts / design_rules.ux_laws.fitts)")
              end
            end
            findings
          end
        end

        ::Law.define(:CHOICE_OVERLOAD) do
          tags %i[DESIGN UX]
          fix "Hick — too many peer choices without grouping"
          bad "<nav>#{(1..8).map { |n| "<a href=\"/#{n}\">#{n}</a>" }.join}</nav>\n"
          good "<ul>#{(1..8).map { |n| "<li>#{n}</li>" }.join}</ul>\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            max = ::Master::Review::Scan::Laws.thresholds.max_visible_choices.to_i
            findings = []

            # count sibling <li> or nav links in a single block
            #
            # A bare <ul> is not a choice surface. Hick's law is about how long it
            # takes to decide between alternatives, and a tag cloud, a search-results
            # list and "what is on in the city today" are content being browsed, not
            # options being chosen between — advising "group or progressive
            # disclosure" on search results says to hide the results. <nav> and
            # <select> are choice surfaces by definition and still count; a <ul> only
            # counts when it says it is one.
            menu_ul = /<ul[^>]*(?:role=["']menu|class=["'][^"']*(?:menu|nav|tabs|filters))/i

            src.scan(/<(?:ul|nav|select)[^>]*>(.*?)<\/(?:ul|nav|select)>/im) do |body|
              chunk = body[0].to_s

              # From the character BEFORE the body, or rindex answers with the
              # body's own first `<`: a chunk that opens `<li>` made every plain
              # <ul> look like a <li> and skipped the exemption below, which is
              # the whole reason this rule reads the opening tag. Found by its own
              # worked example, 2026-09-06.
              start = src.index(chunk)

              opening = src[start ? (src.rindex("<", [start - 1, 0].max) || 0) : 0, 200].to_s
              next if opening.start_with?("<ul") && !opening.match?(menu_ul)
              count = chunk.scan(/<li\b/i).size
              count = chunk.scan(/<option\b/i).size if count.zero?
              count = chunk.scan(/<a\b/i).size if count.zero?
              line = src[0, src.index(chunk) || 0].count("\n") + 1

              if count > max
                findings << finding(line:, message: "#{count} peer choices > #{max} (Hick) — group or progressive disclosure")
                next
              end

              # A Rails `.each` loop renders exactly one static <a>/<li> in the
              # source text regardless of runtime item count — the literal
              # count above is structurally blind to the normal way Rails
              # renders a nav (found 2026-07-21: brgen's 10-item nav_swiper
              # was exactly this shape and this rule never saw it). Can't know
              # the real count statically, so this is advisory, not a hard
              # count — skip if the block already shows a grouping signal.
              next unless count <= 1 && chunk.match?(/<%[-=]?\s*[\w."'\[\]]+\.each(?:_with_index)?\s+do\s*\|/)

              next if chunk.match?(/role=["']group["']|data-controller=["'][^"']*(?:group|collapse|disclosure)/i)
              next if chunk.scan(/\.each(?:_with_index)?\s+do\s*\|/).size > 1 # already chunked into sub-groups

              findings << finding(line:, message: "dynamic choice list (.each loop, real count unknown statically) with no grouping signal — verify it can't exceed #{max} peers, or add role=\"group\"/progressive disclosure (Hick)")
            end
            findings
          end
        end

        ::Law.define(:PROGRESSIVE_DISCLOSURE) do
          source "Progressive disclosure (Jakob Nielsen, NN/g)"
          ask "Does this present all complexity at once instead of revealing detail as the user's task requires it?"
          tags %i[DESIGN UX]
          fix "Lead with the common path and reveal advanced controls when they become relevant."
          example_path "/repo/app/views/settings/edit.html.erb"
          bad %(<form class="settings">\n<input name=\"f1\">\n<input name=\"f2\">\n<input name=\"f3\">\n<input name=\"f4\">\n<input name=\"f5\">\n<input name=\"f6\">\n</form>\n)
          good %(<form class="settings">\n<details><summary>Advanced</summary>\n<input name=\"f1\">\n<input name=\"f2\">\n<input name=\"f3\">\n<input name=\"f4\">\n<input name=\"f5\">\n<input name=\"f6\">\n</details>\n</form>\n)
          check do |src, path|
            next [] unless %w[html].include?(language(path))
            next [] unless path.to_s.include?("/app/views/") || path.to_s.include?("web/")

            # "Dumping all options at once" needs options to dump. This fired on any
            # view containing the word settings/options/advanced anywhere — a link
            # label, a translation key, a URL — so a community's edit page and a
            # playlist embed page were reported as settings UI without a disclosure
            # pattern. The structural signal is a form with enough controls to be
            # worth collapsing; below that there is nothing to progressively reveal.
            next [] unless src.match?(/advanced|settings|options|preferences/i)
            next [] unless src.scan(/<(?:input|select|textarea)\b|f\.(?:text_field|select|check_box|number_field|text_area)/i).size >= 6
            next [] if src.match?(/details|disclosure|collapsed|hidden|aria-expanded|data-controller=["'][^"']*disclosure/i)

            [finding(line: 1, message: "settings/advanced UI without disclosure pattern — collapse secondary controls")]
          end
        end

        ::Law.define(:WHITESPACE_RHYTHM) do
          tags %i[DESIGN AESTHETIC]
          fix "ma — breathing room via gap/section spacing tokens"
          bad ".card { color: red; }\n"
          good ".card { gap: var(--sp); }\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            # The keyword has to be a selector this file styles, not a word anywhere
            # in it. brgen's application.scss is a list of @use lines and nothing
            # else; it was reported for lacking section spacing because one of the
            # partials it imports is named _marketplace_cards. A file with no
            # declaration block cannot have spacing to set.
            next [] unless src.include?("{")
            next [] unless src.match?(/^[^{}\n]*\b(section|hero|card|panel|main)\b[^{}\n]*\{/i)
            next [] if src.match?(/gap\s*:|section.*padding|padding-block|margin-block/i)

            [finding(line: 1, message: "layout surface without gap/section spacing — set rhythm tokens (design_rules negative_space)")]
          end
        end

        ::Law.define(:TYPE_HIERARCHY) do
          tags %i[DESIGN TYPOGRAPHY]
          fix "modular type scale — flag one-off font sizes"
          bad ".s1 { font-size: 11px; }\n.s2 { font-size: 12px; }\n.s3 { font-size: 13px; }\n.s4 { font-size: 14px; }\n.s5 { font-size: 15px; }\n.s6 { font-size: 16px; }\n.s7 { font-size: 17px; }\n.s8 { font-size: 18px; }\n.s9 { font-size: 19px; }\n"
          good ".s1 { font-size: 11px; }\n.s2 { font-size: 12px; }\n.s3 { font-size: 13px; }\n.s4 { font-size: 14px; }\n.s5 { font-size: 15px; }\n.s6 { font-size: 16px; }\n.s7 { font-size: 17px; }\n.s8 { font-size: 18px; }\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            sizes = src.scan(/font-size\s*:\s*([\d.]+)px/i).flatten.map(&:to_f)
            next [] if sizes.size < 5

            unique = sizes.uniq
            next [] if unique.size <= 8

            [finding(line: 1, message: "#{unique.size} distinct px font sizes — prefer modular scale (Müller-Brockmann: one scale, few steps) ≤8 sizes (design_rules.type_scale)")]
          end
        end

        ::Law.define(:CONTRAST_TOKENS) do
          tags %i[DESIGN ACCESSIBILITY]
          fix "prefer token colors over low-contrast gray-on-gray magic"
          bad ".meta { color: #ccc; }\n"
          good ".meta { color: var(--text-secondary); }\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            findings = []
            src.each_line.with_index(1) do |line, num|
              next unless line.match?(/color\s*:\s*#([0-9a-f]{3,8})/i)
              hex = line[/color\s*:\s*#([0-9a-f]{3,8})/i, 1].to_s
              next if hex.empty?
              # crude: light gray text
              next unless hex.match?(/\A([ef]{3}|[ef]{6}|ccc|ddd|eee)\z/i)

              # …but light text is only low-contrast against a light background, and
              # this read the foreground alone. #navBar declares `background-color:
              # #131921` and `color: #fff` on adjacent lines — white on near-black,
              # about 17:1 — and was reported as low-contrast. Every finding here was
              # light-on-dark. If the enclosing block sets a dark background, the pair
              # is the high-contrast case and saying otherwise is backwards.
              next if dark_background_near?(src, num)

              findings << finding(line: num, message: "low-contrast light gray text ##{hex} — use semantic token with AAA body contrast")
            end
            findings
          end
        end

        ::Law.define(:PIXEL_EXACT) do
          tags %i[DESIGN AESTHETIC PIXEL]
          fix "avoid subpixel/fractional layout that breaks integer grids"
          bad ".card { width: 12.5px; }\n"
          good ".card { width: 12px; }\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            scan_lines(src, /(?:width|height|top|left|margin|padding|transform:\s*translate)\s*:\s*[\d.]+\.\d+px/i,
              message: "fractional px — prefer integer pixels for pixel-perfect alignment")
          end
        end

        # Family polish (design_rules ui_polish) — ERB chrome must be i18n; titles use tokens.
        ::Law.define(:ERB_HARDCODED_CHROME) do
          tags %i[DESIGN I18N RAILS VIEWS]
          fix "empty/search chrome uses t() not hardcoded English (default_locale nb)"
          bad %(<%= render "shared/empty", title: "No results" %>\n)
          good %(<%= render "shared/empty", title: t("empty.results") %>\n)
          check do |src, path|
            next [] unless path.to_s.include?("/app/views/") && path.to_s.end_with?(".erb")
            next [] if path.to_s.end_with?("shared/_empty_state.html.erb")

            findings = []
            src.each_line.with_index(1) do |line, num|
              next if line.include?("t(") || line.include?("I18n.t") || line.include?("chrome_i18n: ok")
              next if line.lstrip.start_with?("<%#", "#")

              if line.match?(/title:\s*["'](?:No\s|Nothing\s)/) ||
                 line.match?(/placeholder:\s*["']Search/)
                findings << finding(
                  line: num,
                  message: "hardcoded EN chrome — use t(\"empty.*\") / t(\"search.*\") " \
                           "(design_rules.ui_polish.chrome_i18n; RAILS chrome_i18n_lint)",
                )
              end
            end

            findings
          end
        end

        ::Law.define(:TYPE_TITLE_TOKEN) do
          tags %i[DESIGN TYPOGRAPHY]
          fix "page titles use --text-title token not raw 20px"
          bad ".page-header h1 { font-size: 20px; }\n"
          good ".page-header h1 { font-size: var(--text-title, 1.25rem); }\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            findings = []
            src.each_line.with_index(1) do |line, num|
              next if line.strip.start_with?("//", "/*", "*")
              next unless line.match?(/\.page-header\s+h1|page-header h1|sidebar-card h3/i) ||
                          (line.match?(/font-size\s*:\s*20px/i) && src.lines[[num - 3, 0].max...num].join.match?(/h1|title|header/i))

              if line.match?(/font-size\s*:\s*20px/i)
                findings << finding(
                  line: num,
                  message: "raw 20px title — use var(--text-title, 1.25rem) (design_rules.ui_polish.type_tokens)",
                )
              end
            end
            findings
          end
        end

        ::Law.define(:FORM_FOLLOWS_FUNCTION) do
          tags %i[DESIGN AESTHETIC]
          fix "decorative empty wrappers without content/role"
          bad %(<div class="decor"></div>\n)
          good %(<div class="decor"><%= yield %></div>\n)
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            scan_lines(src, /<div\s+class=["'][^"']*(?:decor|ornament|spacer|filler|gradient-bg)[^"']*["']\s*>\s*<\/div>/i,
              message: "decorative empty div — form follows function; remove or attach semantics")
          end
        end

        ::Law.define(:SIGNAL_NOISE) do
          tags %i[DESIGN AESTHETIC]
          fix "too many competing visual classes on one node"
          bad %(<div class="card card--wide is-open u-mt-2 u-p-1 shadow rounded muted">x</div>\n)
          good %(<div class="card card--wide is-open">x</div>\n)
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            src.each_line.with_index(1).filter_map do |line, num|
              m = line.match(/class=["']([^"']+)["']/)
              next unless m
              classes = m[1].split(/\s+/)
              next if classes.size < 8

              finding(line: num, message: "#{classes.size} classes on one node — signal/noise; move layout to SCSS")
            end
          end
        end

        ::Law.define(:AFFORDANCE_CLARITY) do
          tags %i[DESIGN UX]
          fix "clickable non-buttons need clear affordance"
          bad %(<div data-action="click->dropdown#toggle">Menu</div>\n)
          good %(<div data-action="click@window->dropdown#hide">Menu</div>\n)
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            # An element is interactive when something activates it, not when a
            # Stimulus controller is attached to it. `data-controller` was in this
            # list and produced 79 of the 87 findings — `<div
            # data-controller="character-counter">` is a wrapper that watches a
            # textarea and prints a number, with no handler and nothing to press.
            # Advising a <button> there is advice nobody can take, and eleven
            # unusable findings per usable one is how a rule stops being read.
            #
            # data-action is kept but narrowed to element-scoped activation.
            # Stimulus writes the global form as `click@window->dropdown#hide`,
            # which is a click-outside listener on the *window* and says nothing
            # about the div carrying it; drag and scroll bindings are drop zones and
            # observers, which are correctly divs. Element-scoped click/keydown on a
            # bare div is the case this rule is actually about.
            activation = /onclick|data-action="[^"]*(?<!@window|@document)\b(?:click|keydown|keyup)->/i

            scan_lines(src, /<(div|span)[^>]*#{activation}[^>]*>/i,
              message: "interactive div/span — use <button> or explicit role+tabindex+keyboard handler")
          end
        end

        ::Law.define(:AESTHETIC_MINIMALISM) do
          source "Nielsen Heuristic #8 — aesthetic and minimalist design"
          ask "Does this output contain information that does not earn its place for the current task?"
          tags %i[DESIGN AESTHETIC]
          fix "Remove redundant status, decoration, and secondary detail from the primary path."
          example_path "/repo/app/views/example.html.erb"
          bad %(<button class="btn"><svg class="icon"></svg><span>Save</span></button>\n)
          good %(<button class="btn">Save</button>\n)
          check do |src, path|
            next [] unless %w[html].include?(language(path))
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            scan_lines(src, /<(button|a)[^>]*>.*?<(svg|img|i)[^>]*>.*?<(span|small|badge)/im,
              message: "control packs icon+extra chrome — prefer one signal (label or icon)")
          end
        end

        # One rule per trait, so one worked example per trait. They are declared
        # here rather than inline because the five rules share a body and differ
        # only in the branch each takes, which is exactly what the examples must
        # pin: a shared body is where a change to one trait silently becomes a
        # change to five.
        RAMS_FIXTURES = {
          "USEFUL" => [%(<p>Coming soon</p>\n), %(<p>Bergen i kveld</p>\n)],
          "UNDERSTANDABLE" => [%(<input placeholder="Q">\n), %(<input placeholder="Søk i byen">\n)],
          "UNOBTRUSIVE" => [%(<div class="modal">…</div>\n),
                            # The compliant spelling of the thing it checks: a
                            # dialog that announces itself correctly.
                            %(<dialog aria-modal="true">…</dialog>\n)],
          "HONEST" => [%(<div class="bar">loading 100%</div>\n), %(<div class="bar">42%</div>\n)],
          "THOROUGH" => [%(<form action="/search"><input name="q"></form>\n),
                         %(<form action="/search"><input name="q"><span class="error"></span></form>\n)],
        }.freeze

        %w[USEFUL UNDERSTANDABLE UNOBTRUSIVE HONEST THOROUGH].each do |trait|
          ::Law.define(:"RAMS_#{trait}") do
            tags %i[DESIGN RAMS]
            fix "Rams checklist tag: #{trait.downcase}"
            bad RAMS_FIXTURES.fetch(trait)[0]
            good RAMS_FIXTURES.fetch(trait)[1]
            check do |src, path|
              next [] unless ::Master::Review::Scan::Laws.ui_path?(path)
              next [] unless path.to_s.include?("/app/views/") || path.to_s.include?("web/")

              # Soft detectors — high-signal anti-patterns only
              case trait
              when "HONEST"
                scan_lines(src, /loading.*?100%|progress.*?100%|fake[-_ ]progress/i,
                  message: "possible dishonest progress UI — state must match system (Rams honest)")
              when "THOROUGH"
                next [] unless src.match?(/<form\b/i)
                next [] if src.match?(/error|invalid|aria-invalid|field_with_errors|empty|blank/i)
                [finding(line: 1, message: "form without visible error/empty handling — Rams thorough")]
              when "UNOBTRUSIVE"
                # ERB blanked, and aria-modal exempt. This word-matched raw lines,
                # so it fired on `aria-modal="true"` — the attribute that makes a
                # dialog announce itself correctly, i.e. the compliant spelling of
                # the thing it is checking — and on ERB comments that merely say
                # "showModal()". Neither is attention-capturing chrome. What is left
                # is markup that actually builds an overlay, which is the soft
                # signal this was written to give.
                scan_lines(without_erb_tags(src).gsub(/aria-modal\s*=\s*"[^"]*"/, ""),
                           /modal|overlay|popup|interstitial/i,
                  message: "attention-capturing chrome — keep unobtrusive unless blocking is required")
              when "UNDERSTANDABLE"
                scan_lines(src, /placeholder=["'][^"']{1,3}["']/,
                  message: "cryptic placeholder — labels must explain without folklore")
              when "USEFUL"
                scan_lines(src, /coming soon|lorem ipsum|placeholder content/i,
                  message: "non-useful placeholder content in shipped view")
              else
                []
              end
            end
          end
        end

        ::Law.define(:HOST_CAPACITY) do
          tags %i[OPS]
          fix "carrying capacity — avoid full-repo scan/fix in hot paths"
          example_path "/repo/lib/example.rb"
          bad "scanner.scan_dir(Master::ROOT)\n"
          good "scanner.scan_dir(target_dir)\n"
          check do |src, path|
            next [] unless path.to_s.include?("lib/")

            scan_lines(src, /scan_dir\([^)]*ROOT|fix_loop\.run\(\s*(@root|root|Master::ROOT)/,
              message: "full-root scan/fix — scope to path; respect host carrying capacity")
          end
        end

        # Rails app surface.

        # Rails app law restored from master.yml rails_conventions — lexical/structural.
        # Applies under RAILS/, MASTER/web app views, and any app/ tree.

        RAILSISH = %r{(?:/RAILS/|/app/(?:controllers|models|helpers|views|javascript|assets)/)}i.freeze

        module_function

        def rails_path?(path)
          path.to_s.match?(RAILSISH)
        end

        # Line index of the matching `end` for a `def` starting at `start`,
        # via brace-depth tracking. Own method so its loop's nesting doesn't
        # compound with the caller's own while/if nesting (NESTING_DEPTH).
        def method_body_end_line(lines, start)
          depth = 0
          j = start

          while j < lines.size
            depth += lines[j].scan(/\b(do|def|class|module|if|unless|begin|case)\b/).size
            depth -= lines[j].scan(/\bend\b/).size
            j += 1
            break if depth <= 0 && j > start + 1
          end
          j
        end

        ::Law.define(:THIN_CONTROLLER) do
          tags %i[RAILS ARCHITECTURE]
          fix "thin controllers — business logic belongs in models/services"
          example_path "/repo/app/controllers/example_controller.rb"
          bad %(def index\n  @posts = Post.where("created_at > ? AND city_id = ? AND published = ?", a, b, c)\nend\n)
          good "def index\n  @posts = Post.recent\nend\n"
          check do |src, path|
            next [] unless path.to_s.include?("/controllers/")
            next [] unless path.to_s.end_with?(".rb")

            findings = []
            # fat action: many lines between def and end of public action methods
            lines = src.lines
            i = 0

            while i < lines.size
              if lines[i].match?(/^\s*def\s+\w+/)
                start = i
                j = ::Master::Review::Scan::Laws.method_body_end_line(lines, start)
                body_len = j - start
                if body_len > 40
                  findings << finding(line: start + 1, message: "controller action ~#{body_len} lines — thin controllers, fat models/services (rails_conventions)")
                end
                # SQL / business in controller
                chunk = lines[start...j].join
                if chunk.match?(/\b(?:ActiveRecord::Base\.connection|find_by_sql|\.where\([^)]{40,})/m)
                  findings << finding(line: start + 1, message: "query logic in controller — move to model/query object")
                end
                i = j
              else
                i += 1
              end
            end

            findings
          end
        end

        ::Law.define(:FAT_MODEL_CALLBACK_SOUP) do
          tags %i[RAILS ARCHITECTURE]
          fix "limit model callback piles"
          example_path "/repo/app/models/example.rb"
          bad %w[before_validation before_save after_save after_create after_update after_commit]
                 .map { |cb| "  #{cb} :touch_feed\n" }.join
          good "  before_validation :normalise_slug\n  after_commit :broadcast\n"
          check do |src, path|
            next [] unless path.to_s.include?("/models/")

            count = src.scan(/^\s*(?:before|after|around)_(?:validation|save|create|update|destroy|commit)/).size
            next [] if count <= 5
            [finding(line: 1, message: "#{count} AR callbacks — prefer services/events over callback soup")]
          end
        end

        ::Law.define(:RAILS_TAG_HELPER) do
          tags %i[RAILS VIEWS]
          fix "prefer tag helpers over raw HTML for dynamic content"
          bad %(<p><%= @post.title %></p>\n)
          good %(<%= tag.p @post.title %>\n)
          check do |src, path|
            next [] unless path.to_s.include?("/app/views/") && path.to_s.end_with?(".erb")
            findings = []

            src.each_line.with_index(1) do |line, num|
              if line.match?(/<(?:p|div|span|h[1-6])[^>]*>\s*<%=\s*(?!tag\.|content_tag|link_to|button_to|image_tag|t\(|translate)/)
                findings << finding(line: num, message: "raw HTML around <%= — prefer tag.p / content_tag per rails_conventions")
              end
            end
            findings
          end
        end

        ::Law.define(:STIMULUS_CONTROLLER_SIZE) do
          tags %i[RAILS JAVASCRIPT]
          fix "Stimulus controllers stay focused"
          bad "export default class extends Controller {\n#{"  step();\n" * 199}}\n"
          good "export default class extends Controller {\n  connect() {}\n}\n"
          check do |src, path|
            limits = ::Master::Review::Scan::Laws.stimulus_limits

            max = limits.fetch("max_lines", 200).to_i
            # The declared pattern is Stimulus's own naming convention, so it is
            # narrower than the guess it replaces and finds the same four files in
            # the fleet — measured before the change.
            next [] unless path.to_s.match?(Regexp.new(limits.fetch("path_pattern", '_controller\.js$')))
            next [] unless src.match?(/Controller\s+extends|export default class/)

            lines = src.lines.size
            next [] if lines <= max
            [finding(line: 1, message: "Stimulus controller #{lines} lines — split at #{max} (data/laws.yml); move targets/actions out (progressive enhancement)")]
          end
        end

        ::Law.define(:STIMULUS_PROGRESSIVE) do
          tags %i[RAILS JAVASCRIPT UX]
          fix "interactive UI should degrade without JS when possible"
          bad %(<div data-controller="map"></div>\n)
          good %(<div data-controller="map"><a href="/kart">Kart</a></div>\n)
          check do |src, path|
            next [] unless path.to_s.include?("/app/views/")

            next [] unless src.match?(/data-controller=/)
            next [] if src.match?(/<form\b|<a\s+href=|<button\b/i)
            [finding(line: 1, message: "Stimulus island without form/link fallback — progressive enhancement")]
          end
        end

        ::Law.define(:NO_LOGIC_IN_VIEW) do
          tags %i[RAILS VIEWS]
          fix "views present; models/helpers compute"
          bad %(<% @posts.select { |p| p.published? }.each do |post| %>\n)
          good %(<%= render @posts %>\n)
          check do |src, path|
            next [] unless path.to_s.include?("/app/views/") && path.to_s.end_with?(".erb")
            findings = []

            src.each_line.with_index(1) do |line, num|
              next unless line.include?("<%")
              if line.match?(/<%[^=].*\b(?:each|map|select|where|find|create|update|destroy|save!)\b/)
                findings << finding(line: num, message: "business/query logic in view — move to model/helper/component")
              end
            end
            findings
          end
        end

        ::Law.define(:HELPER_VIEW_ONLY) do
          tags %i[RAILS]
          fix "helpers format for views only"
          example_path "/repo/app/helpers/example_helper.rb"
          bad "def recent_posts\n  Post.where(published: true)\nend\n"
          good "def title_for(post)\n  post.title.upcase\nend\n"
          check do |src, path|
            next [] unless path.to_s.include?("/helpers/")

            next [] unless src.match?(/\b(?:ActiveRecord|ApplicationRecord|\.where\(|\.find\()/)
            [finding(line: 1, message: "AR access in helper — helpers format only; queries belong in models")]
          end
        end

        ::Law.define(:SCSS_NESTING_DEPTH) do
          tags %i[RAILS CSS DESIGN]
          fix "avoid deep SCSS nesting / preprocessor bloat"
          bad ".a {\n  .b {\n    .c {\n      .d {\n        .e {\n          color: red;\n        }\n      }\n    }\n  }\n}\n"
          good ".a {\n  .b {\n    color: red;\n  }\n}\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.rails_path?(path) || path.to_s.include?("/assets/")

            max = 0
            depth = 0

            src.each_line do |line|
              depth += line.count("{")
              depth -= line.count("}")
              depth = 0 if depth.negative?
              max = depth if depth > max
            end
            next [] if max <= 4
            [finding(line: 1, message: "SCSS nesting depth #{max} — flatten (modern CSS, no preprocessor bloat)")]
          end
        end

        ::Law.define(:PWA_MANIFEST_HINT) do
          tags %i[RAILS PWA]
          fix "PWA surfaces declare manifest"
          example_path "/repo/app/views/layouts/application.html.erb"
          bad "<html>\n<head><title>Brgen</title></head>\n</html>\n"
          good %(<html>\n<head><link rel="manifest" href="/manifest.json"></head>\n</html>\n)
          check do |src, path|
            next [] unless path.to_s.match?(/layout|application\.html|manifest/i)

            if path.to_s.end_with?(".erb", ".html") && src.match?(/<html/i)
              next [] if src.match?(/rel=["']manifest["']|webmanifest/i)
              [finding(line: 1, message: "layout missing web app manifest link (PWA convention)")]
            else
              []
            end
          end
        end
      end
    end
  end
end
