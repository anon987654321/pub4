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
  languages %i[css]
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

# Migrated from data/rules.yml NO_LONG_TRANSITION.
Law.define(:NO_LONG_TRANSITION) do
  source "style.yml motion budget / FrontendRuleSet MOTION"
  severity :warn
  languages %i[css]
  detect { |line| line.match?(/transition(?:-duration)?\s*:\s*([4-9]\d\d|\d{4,})\s*ms/) }
  fix "Keep transitions ≤300ms."
  bad  "transition-duration: 600ms;"
  good "transition-duration: 200ms;"
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
Law.define(:NO_MULTIPLE_LANGUAGES) do
  source "MASTER-native (one language per file)"
  severity :warn
  languages %i[ruby javascript css scss zsh]
  detect { |line| line.match?(/<%|<script|<style|SQL|HEREDOC/) }
  fix "One language per layer. Separate into distinct files or clearly demarcated sections."
  bad  "rows = connection.exec(<<~SQL)"
  good "rows = connection.exec(query)"
end

