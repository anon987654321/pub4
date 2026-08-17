# frozen_string_literal: true

# Migrated from data/rules.yml NO_INLINE_STYLES.
Law.define(:NO_INLINE_STYLES) do
  source "CSP / separation of concerns — no inline styles"
  severity :warn
  languages %i[html]
  detect { |line| line.match?(/\bstyle="[^"]*"/) }
  fix "Extract to CSS class."
  bad  "<p style=\"color:red\">"
  good "<p class=\"warn\">"
end
