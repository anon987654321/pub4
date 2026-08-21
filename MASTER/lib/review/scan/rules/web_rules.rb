# frozen_string_literal: true

module Master
  module Review
    module Scan
      module Rules

        # Retired registry twins — each lives once, in law/:
        #   ARIA_INTERACTIVE, BUTTON_OVER_ANCHOR, CLAMP_TYPOGRAPHY, I18N_COVERAGE
        #   MOBILE_FIRST, NO_IMPORT_SCSS
        #   NO_INLINE_STYLES
        # (test_scan_rule_contracts proves each reaches findings through the bridge).

        RuleDSL.rule :HTML_LANG,
          severity: :error, tags: %i[ACCESSIBILITY], applies_to: %i[html],
          description: "lang attribute on <html>" do |src, path:|
          next [] unless src.match?(/<html\b/i)
          scan_lines(tag_source(src), /<html(?!\s+[^>]*lang=)/, message: "<html> missing lang= attribute")
        end

        RuleDSL.rule :SEMANTIC_ELEMENTS,
          severity: :warning, tags: %i[ACCESSIBILITY], applies_to: %i[html],
          description: "use semantic HTML5 elements" do |src, path:|
          scan_lines(src, /<div\s+class="(header|footer|nav|main|sidebar|article|section)"/,
            message: "use <header>/<footer>/<nav>/<main>/<aside>/<article>/<section> instead of div.class")
        end

        # IMG_ALT and LAZY_IMAGES returned from the twin batch: both judge a
        # TAG, and law/ scans lines — the attribute-per-line spelling made
        # every multi-line <img> a finding. tag_source flattens first.
        RuleDSL.rule :IMG_ALT,
          severity: :error, tags: %i[ACCESSIBILITY], applies_to: %i[html],
          description: "require alt on every <img>" do |src, path:|
          scan_lines(tag_source(src), /<img\s+(?![^>]*alt=)/, message: "<img> missing alt= attribute")
        end

        RuleDSL.rule :LAZY_IMAGES,
          severity: :info, tags: %i[PERFORMANCE], applies_to: %i[html],
          description: "loading=lazy on below-fold images" do |src, path:|
          scan_lines(tag_source(src), /<img\s+(?![^>]*loading=)/, message: "<img> missing loading=lazy")
        end

        RuleDSL.rule :NO_IMPORTANT,
          severity: :warning, tags: %i[MAINTAINABILITY], applies_to: %i[css scss],
          description: "no !important" do |src, path:|
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
          scan_lines(without_block_comments(without_override_media(src)), /!\s*important/,
                     message: "!important overrides cascade — fix specificity instead")
        end

        RuleDSL.rule :LOGICAL_PROPERTIES,
          severity: :info, tags: %i[I18N], applies_to: %i[css scss],
          description: "prefer logical properties for RTL support" do |src, path:|
          scan_lines(src, /(margin|padding)-(left|right):/,
            message: "use logical property (margin-inline-start/end) for RTL support")
        end

        RuleDSL.rule :META_CHARSET,
          severity: :error, tags: %i[CORRECTNESS], applies_to: %i[html],
          description: "HTML must declare charset early in <head>" do |src, path:|
          next [] unless path.to_s.match?(/\.(html|erb|haml|slim)\z/)
          next [] unless src.match?(/<head\b/i) || src.match?(/<html\b/i)
          next [] if src.match?(/<meta\s+charset=/i)
          # The http-equiv spelling counts: mail clients honour it more
          # reliably than the HTML5 short form, and the mailer layout uses it
          # on purpose.
          next [] if src.match?(/charset=["']?utf-8/i)
          [finding(line: 1, message: "missing <meta charset=UTF-8> — declare encoding as first element in <head>")]
        end

        RuleDSL.rule :ARIA_LABELS,
          severity: :warning, tags: %i[ACCESSIBILITY], applies_to: %i[html],
          description: "interactive controls need accessible names" do |src, path:|
          next [] unless path.include?("/app/views/")
          nameless_control_lines(src).map do |line|
            finding(line:, message: "control has no accessible name — give it text content, aria-label, " \
                                    "aria-labelledby, or an id a <label for> points at")
          end
        end

        RuleDSL.rule :NO_TODO_IN_VIEWS,
          severity: :warning, tags: %i[MAINTAINABILITY], applies_to: %i[html],
          description: "no TODO/FIXME in shipped views" do |src, path:|
          next [] unless path.include?("/app/views/")
          scan_lines(src, /\b(TODO|FIXME|HACK)\b/, message: "unfinished marker in view — resolve before ship")
        end

        BEM_CLASS_RE = /class=["'][^"']*__[^"']*["']/.freeze
        UTILITY_SOUP_RE = /class=["'][^"']*(?:\b(?:mt|mb|ml|mr|px|py|col|row|d-flex|flex|grid|w-|h-)\b[^"']*){3,}[^"']*["']/i.freeze

        RuleDSL.rule :ANTI_DIVITIS,
          severity: :warning, tags: %i[DESIGN], applies_to: %i[html],
          description: "avoid styling-only wrappers and semantic div substitutes" do |src, path:|
          next [] unless path.include?("/app/views/")
          findings = scan_lines(src, /<div\s+class="(header|footer|nav|main|sidebar|article|section)"/i,
            message: "semantic landmark belongs on <header>/<nav>/<main>/<article>, not div.class")
          findings += scan_lines(src, /<div[^>]*>\s*<div[^>]*>\s*<div[^>]*>\s*<div/i,
            message: "div nesting depth > 3 — flatten or use semantic elements")
          findings
        end

        SIMPLE_WRAPPER_TAG_RE = %r{
          <(p|div|span|li|h[1-6]|strong|em|small|label|td|th|dt|dd|caption)(?:\s[^>]*)?>
          \s*<%=\s*[^%<]+?\s*%>\s*
          </\1>
        }ix.freeze

        RuleDSL.rule :PREFER_TAG_HELPERS,
          severity: :info, tags: %i[DESIGN RAILS_IDIOM], applies_to: %i[html],
          description: "prefer Rails tag helpers over raw HTML wrapping a single ERB expression" do |src, path:|
          next [] unless path.include?("/app/views/")
          scan_lines(src, SIMPLE_WRAPPER_TAG_RE,
            message: "<tag><%= … %></tag> — prefer tag.tagname(…) (e.g. tag.p t(\"hello_world\")) so the " \
              "element and its content stay in one Ruby expression instead of splitting across ERB/HTML")
        end

        RuleDSL.rule :BEM_IN_VIEWS,
          severity: :warning, tags: %i[DESIGN], applies_to: %i[html],
          description: "bare tag targeting — no BEM class soup in views" do |src, path:|
          next [] unless path.include?("/app/views/")
          scan_lines(src, BEM_CLASS_RE, message: "BEM class in view — use bare tag/structural selectors per style.yml")
        end

        RuleDSL.rule :UTILITY_CLASS_SOUP,
          severity: :warning, tags: %i[DESIGN], applies_to: %i[html],
          description: "no framework utility class explosion" do |src, path:|
          next [] unless path.include?("/app/views/")
          scan_lines(src, UTILITY_SOUP_RE, message: "utility class soup — move layout to SCSS with bare targeting")
        end

        RuleDSL.rule :ERB_HTML_SAFE,
          severity: :error, tags: %i[SECURITY], applies_to: %i[html],
          description: "html_safe only after sanitize" do |src, path:|
          next [] unless path.include?("/app/views/")
          next [] unless src.match?(/<%=\s*[^%]+\.html_safe\s*%>/)
          next [] if src.match?(/sanitize|strip_tags|\.to_json\.html_safe/)
          [finding(line: 1, message: "raw html_safe in view — sanitize first or use auto-escaped <%= %>")]
        end

        RuleDSL.rule :SINGLE_H1,
          severity: :warning, tags: %i[SEO ACCESSIBILITY], applies_to: %i[html],
          description: "one h1 per view surface" do |src, path:|
          next [] unless path.include?("/app/views/")
          # A locale-branched page renders one h1 per request while carrying
          # two in source; the marker names that shape.
          next [] if src.include?("single_h1: locale-branched")
          count = src.scan(/<h1\b/i).size
          next [] if count <= 1
          [finding(line: 1, message: "#{count} <h1> tags — keep one primary heading per view")]
        end

        RuleDSL.rule :FORM_LABEL,
          severity: :warning, tags: %i[ACCESSIBILITY], applies_to: %i[html],
          description: "inputs require labels or aria-label" do |src, path:|
          next [] unless path.include?("/app/views/")
          scan_lines(control_source(src), /<input\s+(?![^>]*(?:type=["']hidden|aria-label|aria-labelledby|id=))/i,
            message: "input missing label association — add <label for> or aria-label")
        end

        RuleDSL.rule :SKIP_TO_MAIN,
          severity: :warning, tags: %i[ACCESSIBILITY], applies_to: %i[html],
          description: "layouts expose skip link to main content" do |src, path:|
          next [] unless path.include?("/app/views/layouts/")
          # A meta/head partial in layouts/ has no body and cannot hold a skip
          # link; only a document with a body owes one.
          next [] unless src.match?(/<body\b/i)
          # Mailer layouts are not pages. There is no viewport to skip past, no
          # #main-content to land on, and mailer.text.erb is plain text — it asked
          # a text email for a skip link. Both SKIP_TO_MAIN findings in this repo
          # were mailer layouts and neither was actionable.
          next [] if File.basename(path).start_with?("mailer", "_mailer") || path.include?("/mailer")
          next [] if src.match?(/skip|#main-content/i)
          [finding(line: 1, message: "layout missing skip link to #main-content")]
        end

        RuleDSL.rule :H1_VISIBILITY,
          severity: :info, tags: %i[ACCESSIBILITY], applies_to: %i[html],
          description: "async regions expose status for screen readers" do |src, path:|
          next [] unless path.include?("/app/views/")
          # data-controller alone is not asynchrony: a theme toggle or a logo
          # mounts a controller and loads nothing. Only a turbo frame swaps
          # content in later, so only a turbo frame owes a status surface.
          next [] unless src.match?(/data-turbo-frame|turbo-frame/i)
          next [] if src.match?(/aria-live|role=["']status|loading|spinner|progress/i)
          [finding(line: 1, message: "async UI without aria-live/status — expose progress within 100ms")]
        end

        RuleDSL.rule :NO_LONG_TRANSITION,
          severity: :warning, tags: %i[PERFORMANCE], applies_to: %i[css scss],
          description: "UI transitions stay under 300ms",
          example_path: "/repo/app/assets/stylesheets/_example.scss",
          fires: ".card { transition: opacity 500ms var(--ease-out); }\n",
          # transition: none has no duration, and a token duration is not a literal.
          does_not_fire: ".card { transition: none; }\n.b { transition: opacity var(--transition-fast) var(--ease-out); }\n" do |src, path:|
          # The duration is rarely the first token: `transition: opacity 500ms
          # var(--ease-out)` is the normal shorthand, and anchoring to the colon
          # missed every one of them. Found by this rule's own fixture, 2026-08-07.
          scan_lines(src, /transition(?:-duration)?\s*:[^;]*?\b([4-9]\d\d|\d{4,})\s*ms/i,
            message: "transition >300ms — keep motion snappy (≤300ms) per style.yml")
        end

        RuleDSL.rule :REDUCED_MOTION,
          severity: :info, tags: %i[ACCESSIBILITY], applies_to: %i[css scss],
          description: "animations respect prefers-reduced-motion",
          example_path: "/repo/app/assets/stylesheets/_example.scss",
          fires: "@keyframes spin { to { transform: rotate(360deg); } }\n",
          does_not_fire: "@keyframes spin { to { transform: rotate(360deg); } }\n@media (prefers-reduced-motion: reduce) { * { animation: none !important; } }\n" do |src, path:|
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

        RuleDSL.rule :TABINDEX_ABOVE_ZERO,
          severity: :warning, tags: %i[ACCESSIBILITY], applies_to: %i[html],
          description: "tabindex above zero disrupts natural tab order" do |src, path:|
          next [] unless path.include?("/app/views/")
          scan_lines(src, /\btabindex\s*=\s*["']?[1-9]/i,
            message: "tabindex > 0 — remove or use 0/-1 with roving focus pattern")
        end

        RuleDSL.rule :NO_JS_ERB,
          severity: :warning, tags: %i[HOTWIRE], applies_to: %i[html],
          description: "RJS and format.js — migrate to Turbo Streams" do |src, path:|
          next [] unless path.include?("/app/views/")
          findings = scan_lines(src, /format\.js\s*\{/, message: "format.js — use format.turbo_stream")
          findings += scan_lines(src, /\.js\.erb\b/, message: ".js.erb — replace with turbo_stream templates")
          findings
        end

        RuleDSL.rule :DATA_REMOTE,
          severity: :warning, tags: %i[HOTWIRE], applies_to: %i[html],
          description: "rails-ujs data-remote — use Turbo native forms" do |src, path:|
          next [] unless path.include?("/app/views/")
          scan_lines(src, /data-remote\s*=|remote:\s*true/,
            message: "data-remote/remote:true is rails-ujs — use Turbo Frame or standard form")
        end

        INPUT_GENERIC_TYPE_RE = /
          <input\s+[^>]*(?:name|id)\s*=\s*["'][^"']*(?:email|phone|tel|url|date|password)[^"']*["'][^>]*type\s*=\s*["']text["']
          |
          <input\s+[^>]*type\s*=\s*["']text["'][^>]*(?:name|id)\s*=\s*["'][^"']*(?:email|phone|tel|url|date|password)
        /ix.freeze

        RuleDSL.rule :INPUT_TYPE_SPECIFIC,
          severity: :info, tags: %i[ACCESSIBILITY], applies_to: %i[html],
          description: "semantic input types for email/url/tel/date" do |src, path:|
          next [] unless path.include?("/app/views/")
          scan_lines(src, INPUT_GENERIC_TYPE_RE,
            message: "type=text for specialized field — use email/url/tel/date/password input type")
        end

        RuleDSL.rule :FOCUS_VISIBLE,
          severity: :info, tags: %i[ACCESSIBILITY], applies_to: %i[css scss],
          description: "interactive surfaces expose visible focus" do |src, path:|
          next [] unless path.match?(/application|_minimal|_tokens|layout/i)
          next [] unless src.match?(/:hover|button|a\s*\{|\.btn/)
          next [] if src.match?(/:focus-visible|:focus\b/)
          [finding(line: 1, message: "interactive styles without :focus-visible — keyboard users need visible focus")]
        end

      end
    end
  end
end
