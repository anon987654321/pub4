# frozen_string_literal: true

module Master
  module Judge
  module Scan
  module Rules

  RuleDSL.rule :HTML_LANG,
    severity: :error, tags: %i[ACCESSIBILITY], applies_to: %i[html],
    description: "lang attribute on <html>" do |src, path:|
    next [] unless src.match?(/<html\b/i)
    scan_lines(src, /<html(?!\s+[^>]*lang=)/, message: "<html> missing lang= attribute")
  end

  RuleDSL.rule :SEMANTIC_ELEMENTS,
    severity: :warning, tags: %i[ACCESSIBILITY], applies_to: %i[html],
    description: "use semantic HTML5 elements" do |src, path:|
    scan_lines(src, /<div\s+class="(header|footer|nav|main|sidebar|article|section)"/,
      message: "use <header>/<footer>/<nav>/<main>/<aside>/<article>/<section> instead of div.class")
  end

  RuleDSL.rule :I18N_COVERAGE,
    severity: :warning, tags: %i[I18N], applies_to: %i[html],
    description: "wrap user-facing literals in I18n helpers" do |src, path:|
    next [] unless path.include?("/app/views/")
    scan_lines(src, />\s*[A-Za-z][^<]{3,}</, message: "bare text — wrap with t('…')")
  end

  RuleDSL.rule :IMG_ALT,
    severity: :error, tags: %i[ACCESSIBILITY], applies_to: %i[html],
    description: "require alt on every <img>" do |src, path:|
    scan_lines(src, /<img\s+(?![^>]*alt=)/, message: "<img> missing alt= attribute")
  end

  RuleDSL.rule :BUTTON_OVER_ANCHOR,
    severity: :warning, tags: %i[ACCESSIBILITY], applies_to: %i[html],
    description: "use <button> for actions, not <a href='#'>" do |src, path:|
    scan_lines(src, /<a\s+href=["']#["']/, message: "use <button> for actions; <a> is for navigation")
  end

  RuleDSL.rule :ARIA_INTERACTIVE,
    severity: :warning, tags: %i[ACCESSIBILITY], applies_to: %i[html],
    description: "ARIA on non-semantic interactive elements" do |src, path:|
    scan_lines(src, /<(div|span)\s+[^>]*onclick/,
               message: "use <button> or <a> for interactive elements, not div/span with onclick")
  end

  RuleDSL.rule :LAZY_IMAGES,
    severity: :info, tags: %i[PERFORMANCE], applies_to: %i[html],
    description: "loading=lazy on below-fold images" do |src, path:|
    scan_lines(src, /<img\s+(?![^>]*loading=)/, message: "<img> missing loading=lazy")
  end

  RuleDSL.rule :NO_INLINE_STYLES,
    severity: :warning, tags: %i[MAINTAINABILITY], applies_to: %i[html],
    description: "replace inline styles with classes" do |src, path:|
    scan_lines(src, /\bstyle="[^"]*"/, message: "inline style — move to stylesheet")
  end

  RuleDSL.rule :MOBILE_FIRST,
    severity: :warning, tags: %i[RESPONSIVE], applies_to: %i[css scss],
    description: "mobile-first media queries" do |src, path:|
    scan_lines(src, /@media\s*\(\s*max-width/, message: "max-width query — flip to min-width for mobile-first")
  end

  RuleDSL.rule :NO_IMPORT_SCSS,
    severity: :warning, tags: %i[MAINTAINABILITY], applies_to: %i[scss],
    description: "replace @import with @use/@forward" do |src, path:|
    scan_lines(src, /@import\s+["']/, message: "@import is deprecated — use @use or @forward")
  end

  RuleDSL.rule :NO_IMPORTANT,
    severity: :warning, tags: %i[MAINTAINABILITY], applies_to: %i[css scss],
    description: "no !important" do |src, path:|
    scan_lines(src, /!\s*important/, message: "!important overrides cascade — fix specificity instead")
  end

  RuleDSL.rule :LOGICAL_PROPERTIES,
    severity: :info, tags: %i[I18N], applies_to: %i[css scss],
    description: "prefer logical properties for RTL support" do |src, path:|
    scan_lines(src, /(margin|padding)-(left|right):/,
      message: "use logical property (margin-inline-start/end) for RTL support")
  end

  RuleDSL.rule :CLAMP_TYPOGRAPHY,
    severity: :info, tags: %i[RESPONSIVE], applies_to: %i[css scss],
    description: "use clamp() for fluid typography" do |src, path:|
    scan_lines(src, /@media.*\{[^}]*font-size:/,
      message: "media-query font-size — use clamp(min, fluid, max) instead")
  end

  RuleDSL.rule :META_CHARSET,
    severity: :error, tags: %i[CORRECTNESS], applies_to: %i[html],
    description: "HTML must declare charset early in <head>" do |src, path:|
    next [] unless path.to_s.match?(/\.(html|erb|haml|slim)\z/)
    next [] unless src.match?(/<head\b/i) || src.match?(/<html\b/i)
    next [] if src.match?(/<meta\s+charset=/i)
    [finding(line: 1, message: "missing <meta charset=UTF-8> — declare encoding as first element in <head>")]
  end

  end
  end
  end
end
