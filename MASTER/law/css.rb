# frozen_string_literal: true

# law/css.rb — every css law, one Law.define per law.
# REDUCED_MOTION and NO_IMPORTANT live once, in the registry (web_laws.rb).
# Both judge a FILE's posture — whether the reset block exists, whether an
# !important erases or paints, whether it sits inside an override media —
# and the per-line twins here fired on face.css's own reduced-motion reset,
# twenty-six findings against a file already doing the right thing.

Law.define(:CLAMP_TYPOGRAPHY) do
  source "CSS fluid typography — clamp() (web.dev)"
  detect { |line| line.match?(/@media.*\{[^}]*font-size:/) }
  fix "Use font-size: clamp(1rem, 2.5vw, 1.5rem)."
  bad  "@media (min-width: 40em) { h1 { font-size: 2rem; } }"
  good "h1 { font-size: clamp(1.5rem, 2.5vw, 2.5rem); }"
end

Law.define(:LOGICAL_PROPERTIES) do
  source "CSS Logical Properties and Values (W3C)"
  detect { |line| line.match?(/(margin|padding)-(left|right):/) }
  fix "Use margin-inline-start/end, padding-inline-start/end."
  bad  "margin-left: 8px;"
  good "margin-inline-start: 8px;"
end

# MAGIC_COLOR lives once, in the registry (js_laws.rb): its narrowing —
# token definitions, intentional markers, the mailer and manifest carve-outs —
# is behavioural, measured across 596 retired findings, and a bare hex detector
# beside it double-counted every one it got wrong.

Law.define(:MEASURE_OPTIMUM) do
  source "Bringhurst, Elements of Typographic Style — the measure (45–75 chars)"
  # A media query bound is a viewport question, not a text measure.
  detect { |line| !line.include?("@media") && line.match?(/max-width:\s*([89]\d{2}|\d{4,})px/) }
  fix "Bound running-text columns to ~66ch (≈ 33rem), not wide px values."
  bad  "article { max-width: 960px; }"
  good "article { max-width: 66ch; }"
end

Law.define(:MOBILE_FIRST) do
  source "Mobile First (Luke Wroblewski, 2011)"
  detect { |line| line.match?(/@media\s*\(\s*max-width/) }
  fix "Use min-width (mobile-first, progressive enhancement)."
  bad  "@media (max-width: 600px) {"
  good "@media (min-width: 600px) {"
end

Law.define(:NO_IMPORT_SCSS) do
  source "Sass best practice — @use over @import (Sass team)"
  detect { |line| line.match?(/@import\s+["']/) }
  fix "@import is deprecated. Use @use/@forward."
  bad  "@import \"base\";"
  good "@use \"base\";"
end

Law.define(:NO_LONG_TRANSITION) do
  source "style.yml motion budget / FrontendLawSet MOTION"
  detect { |line| line.match?(/transition(?:-duration)?\s*:[^;]*?\b(?:[4-9]\d\d|\d{4,})\s*ms/i) }
  fix "Keep transitions ≤300ms."
  bad  ".card { transition: opacity 500ms var(--ease-out); }"
  good ".card { transition: opacity var(--transition-fast) var(--ease-out); }"
end

# One language per layer: a query language inside Ruby, markup inside
# JavaScript, a heredoc smuggling a third grammar past the reader.
#
# Templates are exempt, and have to be. A template is two languages on purpose —
# that is the entire definition — so matching the ERB opening tag flagged the
# thing that makes the file work. Across RAILS' 428 views this rule produced
# 6,826 findings, 75% of everything MASTER reported about those files, and every
# one of them said "this template contains a template". The law/ header calls
# that the decorator-massacre failure mode: a rule whose false-positive rate
# makes the report unreadable stops being enforcement and becomes noise.
#
# The genuine html case — an inline script or style block, five files in the
# whole tree — is NO_INLINE_SCRIPT_BLOCK, where the detector can be honest about
# what it wants instead of catching a language marker by accident.
# The registry twin retired 2026-08-21: its non-erb branch duplicated this
# detector and its erb branch duplicated NO_INLINE_SCRIPT_BLOCK. The bare
# `SQL|HEREDOC` word-match retired with it — it fired on every heredoc
# closing delimiter and on prose that mentioned SQL; only an opening heredoc
# tag smuggles a grammar in.
Law.define(:NO_MULTIPLE_LANGUAGES) do
  source "MASTER-native (one language per file)"
  ask "Does this file embed multiple languages or notations, or does the artifact mix incompatible frameworks or media layers?"
  # A regex that matches `<%` is not ERB, and a string naming a heredoc tag is
  # not a heredoc. Unmasked this flagged the scanner's own ERB detectors, the
  # source-masking constants and css_coverage_lint's comment stripper — 35 of 72
  # findings were code ABOUT an embedded language rather than an instance of one,
  # which is the shape law.rb's `conduct` already neutralises for law/ itself.
  #
  # A heredoc bound to a constant is exempt because it is the fix: `good` here is
  # `connection.exec(query)`, meaning the other language lives in a name rather
  # than inside a call. PROBE = <<~JS and SCHEMA = <<~SQL are already that, and
  # flagging them asks for a change the rule cannot describe.
  # Strings are not masked, and must not be: `template = "<%= x %>"` is a Ruby
  # file carrying an ERB template, which is the defect exactly, and blanking
  # string literals made the rule blind to its own primary case. What
  # distinguishes it from a scanner naming the delimiter is completeness — an
  # ERB tag opens and closes. `ERB_OPEN = "<%"` is a pattern; `"<%= x %>"` is a
  # template. Regexes stay masked, since `/<%|<script\b/` is a detector.
  detect do |line|
    next false if line.match?(/\A\s*[A-Z][A-Z0-9_]*\s*=\s*<<[~-]/)
    # A needle is not a template. The source checks search a file for the exact
    # text they require — `body.include?('import("<%= asset_path(...) %>")')` —
    # and the ERB tag there is the thing being looked for, not a second language
    # this file speaks.
    next false if line.match?(/\.(?:include\?|match\?|scan|index|start_with\?|end_with\?)\(/)

    masked = line.gsub(Regexp.new('(?<![\w)\]])/(?:[^/\\\\\n]|\\\\.)+/[mixo]*')) { |m| "\0" * m.length }
    masked.gsub!(/%r[{(\[](?:[^})\]\\]|\\.)*[})\]][mixo]*/) { |m| "\0" * m.length }
    masked.match?(/<%.*%>|<script\b|<style\b|<<[~-]?["'`]?(?:SQL|HTML|CSS|JS|JAVASCRIPT)\b/)
  end
  fix "One language per layer. Separate into distinct files or clearly demarcated sections."
  bad  "rows = connection.exec(<<~SQL)"
  good "rows = connection.exec(query)"
end

# Every Layout (Bell & Pickering): let the content size the box. A fixed pixel
# height on a container is a promise about content the container cannot keep —
# text wraps, translations run long (Norwegian does), and the box clips or
# spills. min-height states the same floor without the ceiling. Below 100px
# the element is a control or a media frame sizing itself, not a text
# container, so the law starts where flowing content starts.
#
# The book's other axiom — space between siblings belongs to the parent (gap),
# not the children (margin-bottom chains) — is not per-line decidable: whether
# a margin is a chain depends on the siblings, which only the rendered tree
# knows. It stays a review judgment, not a detector.
Law.define(:FIXED_HEIGHT) do
  source "Every Layout (Bell & Pickering) — the content sizes the box"
  # A drawn stage — an art frame, a product-photo crop window — sizes itself
  # by contract, not by its content. Those lines carry scan: intentional with
  # the reason; the marker keeps the law on flowing-content boxes.
  detect { |line| line.match?(/(?<![a-z-])height:\s*[1-9]\d{2,}px/) && !line.match?(/scan:\s*intentional\b/) }
  fix "Use min-height for a floor, or let the content size the box."
  bad  ".card { height: 300px; }"
  good ".card { min-height: 300px; }"
end

# Modern web-platform laws are review laws: the rendered tree, browser support,
# and component context decide whether a platform primitive is appropriate.

Law.define(:INTRINSIC_LAYOUT) do
  source "Modern CSS intrinsic layout — web.dev Learn CSS"
  ask "Does the layout solve content and component sizing with fixed dimensions or breakpoint patches where intrinsic sizing could express the relationship?"
  fix "Prefer min/max-content, fit-content, auto, flex/grid, clamp(), and content-sized controls before adding fixed dimensions or breakpoint overrides."
  bad "card { width: 420px; }"
  good "card { width: min(100%, 28rem); }"
end

Law.define(:CONTAINER_RESPONSIVENESS) do
  source "CSS Container Queries — web.dev Learn CSS"
  ask "Does a reusable component respond to the viewport even though its actual constraint is the size of its containing component?"
  fix "Use a named or nearest container query when the component's behavior depends on container size."
  bad "@media (max-width: 700px) { .card { ... } }"
  good "@container (max-width: 30rem) { .card { ... } }"
end

Law.define(:MODERN_FORMS) do
  source "CSS field-sizing — Baseline 2026"
  ask "Does a form control use brittle fixed sizing where its content, label, validation state, or user input should determine its size?"
  fix "Prefer intrinsic form sizing and field-sizing when it improves the control without harming predictability."
  bad "textarea { height: 96px; }"
  good "textarea { field-sizing: content; }"
end

Law.define(:NATIVE_DISCLOSURE) do
  source "Popover and dialog — web.dev Learn CSS"
  ask "Does the interface recreate a disclosure, popover, or dialog primitive with unnecessary custom state and positioning?"
  fix "Prefer semantic dialog, popover, details, and native open-state behavior when their contracts match the interaction."
  bad ".menu.is-open { display: block; }"
  good "[popover]:popover-open { ... }"
end

Law.define(:ANCHOR_RELATIONSHIPS) do
  source "CSS Anchor Positioning — web.dev Learn CSS"
  ask "Is a floating element positioned relative to another element through brittle coordinates or JavaScript when their spatial relationship is stable?"
  fix "Prefer declarative anchor positioning where browser support and the interaction contract permit it."
  bad ".menu { left: 183px; top: 72px; }"
  good ".menu { position-anchor: --trigger; position-area: block-end span-inline-end; }"
end

Law.define(:SCOPED_CSS) do
  source "CSS @scope — Baseline 2026"
  ask "Can a component's styles leak across unrelated DOM regions because its selectors are broader than its ownership boundary?"
  fix "Prefer component-local selectors or @scope where it removes selector leakage without adding unnecessary abstraction."
  bad ".card h2 { ... }"
  good "@scope (.card) { h2 { ... } }"
end

Law.define(:MOBILE_VIEWPORT) do
  source "Modern viewport units — web platform"
  ask "Does a mobile layout assume a stable viewport height when browser chrome, safe areas, or the virtual keyboard can change the available space?"
  fix "Use svh, dvh, lvh, env(safe-area-inset-*), and intrinsic layout according to the actual interaction requirement."
  bad ".screen { height: 100vh; }"
  good ".screen { min-height: 100dvh; }"
end

Law.define(:SCROLL_INTEGRITY) do
  source "CSS overflow and modern scroll containers — web.dev Learn CSS"
  ask "Does the layout create accidental page overflow, nested scroll traps, or a scroll container that breaks sticky or touch interaction?"
  fix "Give each scroll container one intentional axis and verify the rendered scroll and sticky behavior at mobile widths."
  bad ".shell { overflow: auto; }"
  good ".shell { overflow-x: clip; overflow-y: auto; }"
end

Law.define(:MOTION_ACCESSIBILITY) do
  source "Web accessibility and reduced motion — web.dev"
  ask "Does motion ignore the user's reduced-motion preference or animate a state whose continuity can be communicated without motion?"
  fix "Respect prefers-reduced-motion and keep transitions short, purposeful, and nonessential."
  bad ".page { animation: zoom 2s infinite; }"
  good "@media (prefers-reduced-motion: reduce) { * { animation-duration: 1ms; } }"
end

Law.define(:NAVIGATION_CONTINUITY) do
  source "View Transitions and Navigation API — Baseline 2026"
  ask "Does a same-origin navigation or state transition unnecessarily destroy context when continuity would make the relationship between states clearer?"
  fix "Preserve scroll, focus, state, and visual continuity first; use View Transitions or the Navigation API only when they simplify a real transition."
  bad "navigate_to(result); reset_all_page_state"
  good "navigate_to(result); preserve_context"
end

Law.define(:INTERACTION_PERFORMANCE) do
  source "Web rendering performance — compositor-safe interaction motion"
  ask "Does frequent interaction motion stay on transform and opacity where possible, avoid layout properties such as top/width/height, and avoid permanent will-change or expensive visual effects?"
  fix "Animate transform and opacity for interaction feedback; let layout properties remain stable, and add will-change only around a measured animation boundary when it removes a real hitch."
  bad ".card { transition: width 300ms, top 300ms; }"
  good ".card { transition: transform var(--duration-m3-short) var(--ease-m3-spring), opacity var(--transition-fast) var(--ease-out); }"
end

Law.define(:STATE_CHOREOGRAPHY) do
  source "Interaction feedback — loading, success and failure are observable states"
  ask "Does an action expose a coherent state sequence such as idle → working → success/failure, with the final state remaining understandable after motion stops? Do not rely on color, motion, or a short-lived flash as the only evidence."
  fix "Give each important action an explicit state, choreograph its transition with the shared motion tokens, and keep a static success or failure representation for reduced motion."
  bad "Tap Pay; briefly spin; disappear with no persistent result."
  good "Tap Pay → working state → self-drawing success mark or persistent failure state; all meanings remain available without motion."
end

Law.define(:GESTURE_OWNERSHIP) do
  source "Pointer Events and touch-action — gesture ownership"
  ask "Does a drag or swipe surface explicitly declare which pan remains with the browser and which axis belongs to the interaction? A direct-manipulation gesture must not compete silently with page scrolling, navigation gestures, or pull-to-refresh."
  fix "Declare touch-action on the gesture surface: use pan-y for horizontal swipes in a vertical page, pan-x for vertical rails, or none when the interaction deliberately owns both axes. Keep an equivalent keyboard/control path."
  bad ".card-stack { touch-action: auto; }"
  good ".card-stack { touch-action: pan-y; }"
end

# Five decorative devices a model reaches for by habit. Each is judged by what
# the mark does for the reader, not by its look, and each carries the
# constitutional law it serves: DENSITY (a mark that carries no information is
# noise) or LINEARITY (structure belongs to the element tree, not to glyphs
# between words). Rendered values stay operator-owned (RENDERED_VALUES), so none
# of these names a replacement colour, face or size. Detection lives once, here,
# so the laws and the false-positive census in test_design_marks.rb read the
# same patterns.
module DesignMarks
  module_function

  # Guarded: Law.load_all re-evaluates a changed law file in the same process.
  ARROW_GLYPH = "(?:→|&rarr;|&#8594;|&#x2192;|->|&gt;&gt;|>>|▸|&#9656;|&#x25b8;)" unless const_defined?(:ARROW_GLYPH)
  DOT_GLYPH = "(?:·|&middot;|&#183;|&#xb7;)" unless const_defined?(:DOT_GLYPH)

  # The innermost { … } blocks of a stylesheet, with their selector.
  def blocks(text)
    text.scan(/([^{};]*)\{([^{}]*)\}/m).map { |selector, body| [selector.strip, body] }
  end

  # px / rem / em value under the body size, or a named small step.
  def small_size?(body)
    value = body[/font-size\s*:\s*([^;}\n]+)/i, 1].to_s.strip
    return false if value.empty?
    return true if value.match?(/(?:--|\$)(?:font-?(?:size-?)?)?(?:2?xs|sm|small|caption|label|micro|tiny)\b/i)

    number = value[/\A([\d.]+)(rem|em|px)\b/i, 1]
    return false unless number

    value.match?(/px\b/i) ? number.to_f < 16 : number.to_f < 1
  end

  # Tracked all-caps eyebrows: uppercase and non-zero tracking together, on text
  # that is small or that the author named an eyebrow, kicker or overline.
  def eyebrow_blocks(text)
    blocks(text).select do |selector, body|
      next false unless body.match?(/text-transform\s*:\s*uppercase/i)

      # Heading case is structural, not a decorative label treatment. A heading
      # remains a finding even when it is large or has no tracking; proper case
      # is consistent across the levels and the page H1 carries the hierarchy.
      heading = selector.match?(/(?:\A|[\s,>])h[1-6](?=$|[\s,.:#\[])/i) ||
                selector.match?(/\.(?:page-title|section-title|empty-state-title|luxury-title|amber-look-title|store-heading)\b/i)
      next true if heading

      next false unless body.match?(/letter-spacing\s*:\s*+(?!0(?:\.0+)?(?:px|r?em)?\s*[;}\n]|normal|inherit|initial|unset)[^;}\n]+/i)

      selector.match?(/eyebrow|kicker|overline/i) || small_size?(body)
    end
  end

  def eyebrow_class?(line) = line.match?(/class\s*[:=]\s*["'][^"']*\b(?:eyebrow|kicker|overline)\b/i)

  # A glyph that points at the next step, appended to the label of a link or button.
  def arrow_label?(line)
    return true if line.match?(%r{<(?:a|button)\b[^>]*>[^<]*?\s#{ARROW_GLYPH}\s*</(?:a|button)>}i)
    return true if line.match?(%r{<span\b[^>]*>\s*#{ARROW_GLYPH}\s*</span>}i)

    line.match?(/\b(?:link_to|button_to|submit|link_to_if)\b\s*\(?\s*(["'])[^"']*?\S\s*#{ARROW_GLYPH}\s*\1/)
  end

  # `A · B · C`: two or more dot separators between words, or a join(" · ").
  def dotted_meta?(line)
    return false if line.match?(/<title\b|<meta\b/i)
    return true if line.match?(/\.join\(\s*["'] ?#{DOT_GLYPH} ?["']\s*\)/)

    line.scan(/\S\s+#{DOT_GLYPH}\s+\S/).length >= 2
  end

  # A gradient painted as a surface. A fade to transparent is a functional edge
  # (a scroll hint, a scrim under text), so it is spared, as is a mask, a solid
  # fill and a hard-stop data bar.
  def gradient_wash?(line)
    return false unless line.match?(/(?:background(?:-image)?|--[\w-]+)\s*:[^;]*(?:linear|radial|conic)-gradient\(/i)

    return false if line.match?(/transparent|\bmask/i)

    # A colour used twice is a hard stop or a solid fill: a hairline or a data bar.
    !line.scan(/var\(--[\w-]+\)|#\h{3,8}\b/).tally.value?(2)
  end

  # Leading-zero counters and literal 0N labels: ornament on items that need no order.
  def ordinal_ornament?(line)
    return true if line.match?(/counter\([^)]*decimal-leading-zero/i)
    return true if line.match?(/content\s*:\s*["']0\d\b/)
    return true if line.match?(/>\s*0[1-9]\s*[\/.]?\s*</)

    line.match?(/(?:["']0<%=|["']%02d["']\s*%\s*\(?\s*\w*(?:index|idx|\bi\b)\b?|<%=\s*["']%02d["']\s*%\s*\(?[^%]*(?:index|idx|\+\s*1))/)
  end
end

Law.define(:NO_EYEBROW_LABEL) do
  source "DENSITY — a small tracked all-caps line above a heading restates the heading's role; Strunk, omit needless words"
  scope :file
  detect do |text|
    DesignMarks.eyebrow_blocks(text).any? || text.each_line.any? { |line| DesignMarks.eyebrow_class?(line) }
  end
  fix "Drop the eyebrow; let the heading and the page structure say where the reader is. A label that names a field stays."
  bad  ".kicker { font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.1em; }"
  good ".field-label { font-size: 0.875rem; font-weight: 600; }"
end

Law.define(:NO_TRAILING_ARROW) do
  source "DENSITY — a link already says it can be followed; an arrow glyph in its text adds no information"
  detect { |line| DesignMarks.arrow_label?(line) }
  fix "Write the verb and the object (\"Les saken\"); the link styling carries the affordance."
  bad  '<a href="/news">Les mer →</a>'
  good '<a href="/news">Les saken</a>'
end

Law.define(:NO_DOT_SEPARATED_META) do
  source "LINEARITY — structure belongs to the element tree; glyphs between words make a flat string the reader must parse"
  detect { |line| DesignMarks.dotted_meta?(line) }
  fix "Put each fact in its own element (a list item or a span) and let spacing or a border separate them."
  bad  "<p>Bergen · 3 timer siden · 12 svar</p>"
  good "<ul class=\"meta\"><li>Bergen</li><li>3 timer siden</li><li>12 svar</li></ul>"
end

Law.define(:NO_DECORATIVE_GRADIENT) do
  source "RENDERED_VALUES and flat design — a gradient wash is a colour the operator did not choose; surfaces are flat tokens"
  detect { |line| DesignMarks.gradient_wash?(line) }
  fix "Paint the surface with its token colour. A fade to transparent over an edge or a scrim under text is allowed."
  bad  ".hero { background: linear-gradient(135deg, var(--a), var(--b)); }"
  good ".hero { background: var(--surface); }"
end

Law.define(:NO_ORDINAL_ORNAMENT) do
  source "LINEARITY — a 01, 02, 03 marker promises a sequence; on items with no order it is decoration"
  detect { |line| DesignMarks.ordinal_ornament?(line) }
  fix "Drop the number, or make the items an ordered list when the order is real."
  bad  ".card::before { content: counter(card, decimal-leading-zero); }"
  good "ol.steps li::marker { content: counter(list-item) \". \"; }"
end


Law.define(:SIGNAL_COLOR_IS_SEMANTIC) do
  source "pub4 visual identity contract — signal colour is a semantic marker, never a general surface or body-text colour"
  scope :file
  detect do |text|
    unsafe_signal_background = text.scan(/([^{}]+)\{([^{}]*)\}/m).any? do |selector, declarations|
      next false unless declarations.match?(/(?:\A|;)\s*background(?:-color)?\s*:\s*var\(\s*--pub4-signal\s*\)/i)

      !selector.strip.match?(/\A#cmd-palette-list\s+li\[data-active\s*=\s*["']?1["']?\]\z/i)
    end
    direct_signal_text = text.scan(/([^{}]+)\{([^{}]*)\}/m).any? do |_selector, declarations|
      declarations.match?(/(?:\A|;)\s*color\s*:\s*var\(\s*--pub4-signal\s*\)\s*(?:!important\s*)?;/i)
    end

    unsafe_signal_background || direct_signal_text
  end
  fix "Use the signal only as a selected-state marker with explicit signal ink; use the local product accent for ordinary buttons, page surfaces and text."
  bad <<~CSS
    .hero {
      background: var(--pub4-signal);
      color: var(--pub4-signal);
    }
  CSS
  good <<~CSS
    #cmd-palette-list li[data-active="1"] {
      background: var(--pub4-signal);
      color: var(--pub4-signal-ink);
    }

    .home-feed-view.is-active {
      border-block-end-color: var(--pub4-signal);
    }

    .page {
      background: var(--surface);
      color: var(--text);
    }
  CSS
end

