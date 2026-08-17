# frozen_string_literal: true

# Migrated from data/rules.yml UTILITY_CLASS_SOUP.
Law.define(:UTILITY_CLASS_SOUP) do
  source "style.yml html.forbidden.framework_class_explosion"
  severity :warn
  languages %i[html]
  detect { |line| line.match?(/class=["'][^"']*(?:\b(?:mt|mb|col|row|d-flex)\b[^"']*){3,}/) }
  fix "Move layout to SCSS with bare tag targeting."
  bad  "<div class=\"row col mt mb\">"
  good "<div class=\"toolbar\">"
end
