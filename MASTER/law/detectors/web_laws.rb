# frozen_string_literal: true

module Master
  module Review
    module Scan
      module Laws

        # Retired registry twins — each lives once, in law/:
        #   ARIA_INTERACTIVE, BUTTON_OVER_ANCHOR, CLAMP_TYPOGRAPHY, I18N_COVERAGE
        #   MOBILE_FIRST, NO_IMPORT_SCSS
        #   NO_INLINE_STYLES
        # (test_scan_rule_contracts proves each reaches findings through the bridge).

        ::Law.define(:HTML_LANG) do
          tags %i[ACCESSIBILITY]
          fix "lang attribute on <html>"
          bad %(<html>\n)
          good %(<html lang="nb">\n)
          check do |src, path|
            next [] unless src.match?(/<html\b/i)
            scan_lines(tag_source(src), /<html(?!\s+[^>]*lang=)/, message: "<html> missing lang= attribute")
          end
        end

        # SEMANTIC_ELEMENTS lives once, in law/html.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # IMG_ALT and LAZY_IMAGES returned from the twin batch: both judge a
        # TAG, and law/ scans lines — the attribute-per-line spelling made
        # every multi-line <img> a finding. tag_source flattens first.
        ::Law.define(:IMG_ALT) do
          tags %i[ACCESSIBILITY]
          fix "require alt on every <img>"
          bad %(<img src="a.png">\n)
          good %(<img src="a.png" alt="a garment">\n)
          check do |src, path|
            scan_lines(tag_source(src), /<img\s+(?![^>]*alt=)/, message: "<img> missing alt= attribute")
          end
        end

        ::Law.define(:LAZY_IMAGES) do
          tags %i[PERFORMANCE]
          fix "loading=lazy on below-fold images"
          bad %(<img src="a.png" alt="a">\n)
          good %(<img src="a.png" alt="a" loading="lazy">\n)
          check do |src, path|
            scan_lines(tag_source(src), /<img\s+(?![^>]*loading=)/, message: "<img> missing loading=lazy")
          end
        end

        ::Law.define(:NO_IMPORTANT) do
          tags %i[MAINTAINABILITY]
          fix "no !important"
          bad ".btn { background: #c00 !important; }\n"
          good ".btn { border: none !important; }\n"
          check do |src, path|
            # Not inside the media queries whose entire job is to override.
            #
            # `@media (prefers-reduced-motion: reduce) { * { animation: none
            # !important } }` is the recommended spelling, and it needs !important
            # precisely because it must beat whatever the author set — dropping it
            # would leave motion running for someone who asked the OS to stop it.
            # 73 of the 139 findings in this repo were that block, plus three in
            # prefers-contrast/forced-colors/print, which override for the same
            # reason. Telling an accessibility reset to "fix specificity instead" is
            # telling it to stop working.
            #
            # The same override exists class-shaped: _battery_aware.scss applies
            # .battery-low/.network-save-data from JS and must beat the author for
            # the same reason the media reset must. A file whose whole job is
            # overriding declares it with `scan: intentional-important` in its
            # head, the way a token source declares intentional-colors.
            next [] if src.lines.first(20).join.match?(/scan:\s*intentional-important/)
            #
            # An !important that ERASES chrome is a guarantee; one that PAINTS is
            # an argument. The flat system armours its wordmark, grips and
            # toggles with border/background/outline erased from anywhere —
            # converging styling to nothing cannot start the specificity war
            # this rule exists to prevent — so erase-shaped importants
            # (none/transparent/0) pass and painting ones still fire.
            erase = /(?:border|outline|background|padding|animation|transition|box-shadow|display)[\w-]*\s*:\s*(?:none|transparent|0)[^;!]*!\s*important/
            source_text = without_block_comments(without_override_media(src))
            # Markers are consulted on the ORIGINAL lines: the block-comment
            # stripping above blanks /* scan: intentional-marker */ before scan_lines
            # could see it.
            originals = src.lines
            source_text = source_text.each_line.with_index.map do |l, i|
              l.match?(erase) || l.lstrip.start_with?("//") || originals[i].to_s.match?(/scan:\s*intentional\b/) ? "\n" : l
            end.join
            scan_lines(source_text, /!\s*important/,
                       message: "!important overrides cascade — fix specificity instead")
          end
        end

        # LOGICAL_PROPERTIES lives once, in law/css.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # META_CHARSET lives once, in law/html.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        ::Law.define(:ARIA_LABELS) do
          tags %i[ACCESSIBILITY]
          fix "interactive controls need accessible names"
          bad %(<button class="icon-only"><svg></svg></button>\n)
          good %(<button class="icon-only" aria-label="Close"><svg></svg></button>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            nameless_control_lines(src).map do |line|
              finding(line:, message: "control has no accessible name — give it text content, aria-label, " \
                                      "aria-labelledby, or an id a <label for> points at")
            end
          end
        end

        ::Law.define(:NO_TODO_IN_VIEWS) do
          tags %i[MAINTAINABILITY]
          fix "no TODO/FIXME in shipped views"
          bad %(<%# FIXME: wire the filter %>\n)
          good %(<%# the filter is Marketplace::ListingFacets %>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            scan_lines(src, /\b(TODO|FIXME|HACK)\b/, message: "unfinished marker in view — resolve before ship")
          end
        end

        ::Law.define(:ANTI_DIVITIS) do
          tags %i[DESIGN]
          fix "avoid styling-only wrappers and semantic div substitutes"
          bad %(<div class="header">\n)
          good %(<header class="header">\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            findings = scan_lines(src, /<div\s+class="(header|footer|nav|main|sidebar|article|section)"/i,
              message: "semantic landmark belongs on <header>/<nav>/<main>/<article>, not div.class")
            findings += scan_lines(src, /<div[^>]*>\s*<div[^>]*>\s*<div[^>]*>\s*<div/i,
              message: "div nesting depth > 3 — flatten or use semantic elements")
            findings
          end
        end

        SIMPLE_WRAPPER_TAG_RE = %r{
          <(p|div|span|li|h[1-6]|strong|em|small|label|td|th|dt|dd|caption)(?:\s[^>]*)?>
          \s*<%=\s*[^%<]+?\s*%>\s*
          </\1>
        }ix.freeze

        ::Law.define(:PREFER_TAG_HELPERS) do
          tags %i[DESIGN RAILS_IDIOM]
          fix "prefer Rails tag helpers over raw HTML wrapping a single ERB expression"
          bad %(<p><%= t("hello_world") %></p>\n)
          good %(<%= tag.p t("hello_world") %>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            scan_lines(src, SIMPLE_WRAPPER_TAG_RE,
              message: "<tag><%= … %></tag> — prefer tag.tagname(…) (e.g. tag.p t(\"hello_world\")) so the " \
                "element and its content stay in one Ruby expression instead of splitting across ERB/HTML")
          end
        end

        # BEM_IN_VIEWS lives once, in law/html.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # UTILITY_CLASS_SOUP lives once, in law/html.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        ::Law.define(:ERB_HTML_SAFE) do
          tags %i[SECURITY]
          fix "html_safe only after sanitize"
          bad %(<%= @post.body.html_safe %>\n)
          good %(<%= sanitize(@post.body).html_safe %>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            # html_safe is judged per output expression: sanitizing one ERB tag
            # cannot excuse a different tag, and JSON serialization is not HTML
            # escaping. Only a scan: intentional comment associated with the next
            # output can excuse generated markup (the 2FA QR SVG).
            output_pattern = /<%=\s*(.*?)\s*%>/m
            marker_pattern = /<%#.*?\bscan:\s*intentional\b(?!-).*?%>|<!--.*?\bscan:\s*intentional\b(?!-).*?-->/m
            marker_ends = []
            src.scan(marker_pattern) { marker_ends << Regexp.last_match.end(0) }
            marker_index = 0
            previous_output_end = 0
            findings = []

            src.scan(output_pattern) do
              match = Regexp.last_match
              expression = match[1]
              output_start = match.begin(0)
              output_end = match.end(0)
              marker_end = nil

              while marker_index < marker_ends.length && marker_ends[marker_index] < output_start
                marker_end = marker_ends[marker_index]
                marker_index += 1
              end

              if expression.match?(/\.html_safe\b/)
                sanitized_in_this_expression = expression.match?(/\b(?:sanitize|strip_tags)\b/)
                intentional_for_this_expression = marker_end && marker_end > previous_output_end

                unless sanitized_in_this_expression || intentional_for_this_expression
                  line = src[0...output_start].count("\n") + 1
                  findings << finding(
                    line:,
                    message: "raw html_safe in view — prefer auto-escaped output or raw json_escape(valid_json) for script payloads",
                  )
                end
              end

              previous_output_end = output_end
            end

            findings
          end
        end

        ::Law.define(:SINGLE_H1) do
          tags %i[SEO ACCESSIBILITY]
          fix "one h1 per view surface"
          bad %(<h1>Bergen</h1>\n<h1>Oslo</h1>\n)
          good %(<h1>Bergen</h1>\n<h2>Oslo</h2>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            # A locale-branched page renders one h1 per request while carrying
            # two in source; the marker names that shape.
            next [] if src.include?("single_h1: locale-branched")
            count = src.scan(/<h1\b/i).size
            next [] if count <= 1
            [finding(line: 1, message: "#{count} <h1> tags — keep one primary heading per view")]
          end
        end

        ::Law.define(:FORM_LABEL) do
          tags %i[ACCESSIBILITY]
          fix "inputs require labels or aria-label"
          bad %(<input type="text" name="query">\n)
          good %(<label>Search<input type="text" name="query"></label>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            scan_lines(control_source(src), /<input\s+(?![^>]*(?:type=["']hidden|aria-label|aria-labelledby|id=))/i,
              message: "input missing label association — add <label for> or aria-label")
          end
        end

        # SKIP_TO_MAIN lives once, in law/html.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        ::Law.define(:ASYNC_STATUS) do
          tags %i[ACCESSIBILITY]
          fix "async regions expose status for screen readers"
          bad %(<turbo-frame id="feed"></turbo-frame>\n)
          good %(<turbo-frame id="feed" aria-live="polite"></turbo-frame>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            # data-controller alone is not asynchrony: a theme toggle or a logo
            # mounts a controller and loads nothing. Only a turbo frame swaps
            # content in later, so only a turbo frame owes a status surface.
            next [] unless src.match?(/data-turbo-frame|turbo-frame/i)
            next [] if src.match?(/aria-live|role=["']status|loading|spinner|progress/i)
            [finding(line: 1, message: "async UI without aria-live/status — expose progress within 100ms")]
          end
        end

        # NO_LONG_TRANSITION lives once, in law/css.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        ::Law.define(:REDUCED_MOTION) do
          tags %i[ACCESSIBILITY]
          fix "animations respect prefers-reduced-motion"
          example_path "/repo/app/assets/stylesheets/_example.scss"
          bad "@keyframes spin { to { transform: rotate(360deg); } }\n"
          good "@keyframes spin { to { transform: rotate(360deg); } }\n@media (prefers-reduced-motion: reduce) { * { animation: none !important; } }\n"
          check do |src, path|
            next [] unless src.match?(/@keyframes|animation\s*:/i)
            # Either direction of the query satisfies this. `reduce` turns motion off
            # for people who asked; `no-preference` never turns it on for them in the
            # first place, which is the stronger form — motion is opt-in rather than
            # opt-out, so a browser that reports nothing gets the still version.
            # visualizer.css wraps every animation in `no-preference` and was the last
            # REDUCED_MOTION finding in the tree: the rule was flagging the better
            # pattern for not being the one it knew.
            next [] if src.match?(/prefers-reduced-motion:\s*(?:reduce|no-preference)/i)
            [finding(line: 1, message: "animation without prefers-reduced-motion override")]
          end
        end

        ::Law.define(:TABINDEX_ABOVE_ZERO) do
          tags %i[ACCESSIBILITY]
          fix "tabindex above zero disrupts natural tab order"
          bad %(<a href="/" tabindex="3">Home</a>\n)
          good %(<a href="/" tabindex="0">Home</a>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            scan_lines(src, /\btabindex\s*=\s*["']?[1-9]/i,
              message: "tabindex > 0 — remove or use 0/-1 with roving focus pattern")
          end
        end

        ::Law.define(:NO_JS_ERB) do
          tags %i[HOTWIRE]
          fix "RJS and format.js — migrate to Turbo Streams"
          bad %(<%= render "posts/create.js.erb" %>\n)
          good %(<%= render "posts/create.turbo_stream.erb" %>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            findings = scan_lines(src, /format\.js\s*\{/, message: "format.js — use format.turbo_stream")
            findings += scan_lines(src, /\.js\.erb\b/, message: ".js.erb — replace with turbo_stream templates")
            findings
          end
        end

        ::Law.define(:DATA_REMOTE) do
          tags %i[HOTWIRE]
          fix "rails-ujs data-remote — use Turbo native forms"
          bad %(<%= link_to "Slett", post_path(post), remote: true %>\n)
          good %(<%= link_to "Slett", post_path(post), data: { turbo_method: :delete } %>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            scan_lines(src, /data-remote\s*=|remote:\s*true/,
              message: "data-remote/remote:true is rails-ujs — use Turbo Frame or standard form")
          end
        end

        INPUT_GENERIC_TYPE_RE = /
          <input\s+[^>]*(?:name|id)\s*=\s*["'][^"']*(?:email|phone|tel|url|date|password)[^"']*["'][^>]*type\s*=\s*["']text["']
          |
          <input\s+[^>]*type\s*=\s*["']text["'][^>]*(?:name|id)\s*=\s*["'][^"']*(?:email|phone|tel|url|date|password)
        /ix.freeze

        ::Law.define(:INPUT_TYPE_SPECIFIC) do
          tags %i[ACCESSIBILITY]
          fix "semantic input types for email/url/tel/date"
          bad %(<input type="text" name="email_address">\n)
          good %(<input type="email" name="email_address">\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            scan_lines(src, INPUT_GENERIC_TYPE_RE,
              message: "type=text for specialized field — use email/url/tel/date/password input type")
          end
        end

        ::Law.define(:FOCUS_VISIBLE) do
          tags %i[ACCESSIBILITY]
          fix "interactive surfaces expose visible focus"
          example_path "/repo/app/assets/stylesheets/application.scss"
          bad ".btn:hover { background: var(--hover); }\n"
          good ".btn:hover { background: var(--hover); }\n.btn:focus-visible { outline: 2px solid; }\n"
          check do |src, path|
            next [] unless path.match?(/application|_minimal|_tokens|layout/i)
            next [] unless src.match?(/:hover|button|a\s*\{|\.btn/)
            next [] if src.match?(/:focus-visible|:focus\b/)
            [finding(line: 1, message: "interactive styles without :focus-visible — keyboard users need visible focus")]
          end
        end

      end
    end
  end
end
