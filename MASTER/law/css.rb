# frozen_string_literal: true

# law/css.rb — every css law, one Law.define per rule.
# Was 10 one-rule files; Law.load_all and every fixture proof are
# unchanged by the grouping (2026-08-19 file-sprawl consolidation).

# Migrated from data/rules.yml CLAMP_TYPOGRAPHY.
# REDUCED_MOTION and NO_IMPORTANT live once, in the registry (web_rules.rb).
# Both judge a FILE's posture — whether the reset block exists, whether an
# !important erases or paints, whether it sits inside an override media —
# and the per-line twins here fired on face.css's own reduced-motion reset,
# twenty-six findings against a file already doing the right thing.

Law.define(:CLAMP_TYPOGRAPHY) do
  source "CSS fluid typography — clamp() (web.dev)"
  severity :info
  languages %i[css scss]
  detect { |line| line.match?(/@media.*\{[^}]*font-size:/) }
  fix "Use font-size: clamp(1rem, 2.5vw, 1.5rem)."
  bad  "@media (min-width: 40em) { h1 { font-size: 2rem; } }"
  good "h1 { font-size: clamp(1.5rem, 2.5vw, 2.5rem); }"
end

# Migrated from data/rules.yml LOGICAL_PROPERTIES.
Law.define(:LOGICAL_PROPERTIES) do
  source "CSS Logical Properties and Values (W3C)"
  severity :info
  # scss too: the fleet's styles are authored in .scss, and a css-only scope
  # made this law inert everywhere it mattered — the registry twin was the
  # live one until its retirement carried the language here.
  languages %i[css scss]
  detect { |line| line.match?(/(margin|padding)-(left|right):/) }
  fix "Use margin-inline-start/end, padding-inline-start/end."
  bad  "margin-left: 8px;"
  good "margin-inline-start: 8px;"
end

# MAGIC_COLOR lives once, in the registry (js_rules.rb): its narrowing —
# token definitions, intentional markers, the mailer and manifest carve-outs —
# is behavioural, measured across 596 retired findings, and a bare hex detector
# beside it double-counted every one it got wrong.

# Migrated from data/rules.yml MEASURE_OPTIMUM.
Law.define(:MEASURE_OPTIMUM) do
  source "Bringhurst, Elements of Typographic Style — the measure (45–75 chars)"
  severity :info
  languages %i[css scss]
  # A media query bound is a viewport question, not a text measure.
  detect { |line| !line.include?("@media") && line.match?(/max-width:\s*([89]\d{2}|\d{4,})px/) }
  fix "Bound running-text columns to ~66ch (≈ 33rem), not wide px values."
  bad  "article { max-width: 960px; }"
  good "article { max-width: 66ch; }"
end

# Migrated from data/rules.yml MOBILE_FIRST.
Law.define(:MOBILE_FIRST) do
  source "Mobile First (Luke Wroblewski, 2011)"
  severity :warn
  languages %i[css scss]
  detect { |line| line.match?(/@media\s*\(\s*max-width/) }
  fix "Use min-width (mobile-first, progressive enhancement)."
  bad  "@media (max-width: 600px) {"
  good "@media (min-width: 600px) {"
end

# Migrated from data/rules.yml NO_IMPORT_SCSS.
Law.define(:NO_IMPORT_SCSS) do
  source "Sass best practice — @use over @import (Sass team)"
  severity :warn
  languages %i[scss]
  detect { |line| line.match?(/@import\s+["']/) }
  fix "@import is deprecated. Use @use/@forward."
  bad  "@import \"base\";"
  good "@use \"base\";"
end

# Migrated from data/rules.yml NO_LONG_TRANSITION. The registry twin found
# with its own fixture (2026-08-07) that the duration is rarely the first
# token — `transition: opacity 500ms var(--ease-out)` is the normal
# shorthand, and anchoring to the colon missed every one. Its detector and
# that fixture moved here with the retirement.
Law.define(:NO_LONG_TRANSITION) do
  source "style.yml motion budget / FrontendRuleSet MOTION"
  severity :warn
  languages %i[css scss]
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
  severity :warn
  languages %i[ruby javascript css scss zsh]
  # A database adapter's job is to speak SQL. Flagging it there asks the layer
  # to stop doing the one thing it exists for, and the rule is about a document
  # mixing languages — the shape RAILS/CLAUDE.md names when it says split large
  # mixed HTML/CSS/JS files.
  path_exclude %r{/(?:knowledge_store|knowledge_schema|catalog_index)\.rb\z|/memory/search\.rb\z}
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
  detect do |line|
    next false if line.match?(/\A\s*[A-Z][A-Z0-9_]*\s*=\s*<<[~-]/)

    masked = line.dup
    masked.gsub!(/"(?:[^"\\]|\\.)*"/) { |m| "\0" * m.length }
    masked.gsub!(/'(?:[^'\\]|\\.)*'/) { |m| "\0" * m.length }
    masked.gsub!(Regexp.new('(?<![\w)\]])/(?:[^/\\\\\n]|\\\\.)+/[mixo]*')) { |m| "\0" * m.length }
    masked.match?(/<%|<script\b|<style\b|<<[~-]?["'`]?(?:SQL|HTML|CSS|JS|JAVASCRIPT)\b/)
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
  severity :info
  languages %i[css scss]
  detect { |line| line.match?(/(?<![a-z-])height:\s*[1-9]\d{2,}px/) }
  fix "Use min-height for a floor, or let the content size the box."
  bad  ".card { height: 300px; }"
  good ".card { min-height: 300px; }"
end
