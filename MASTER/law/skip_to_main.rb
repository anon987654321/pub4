# frozen_string_literal: true

# Migrated from data/rules.yml SKIP_TO_MAIN.
Law.define(:SKIP_TO_MAIN) do
  source "WCAG 2.4.1 Bypass Blocks / style.yml accessibility"
  severity :warn
  languages %i[html]
  scope :file
  detect { |text| text.match?(/\A(?!.*(?:skip|#main-content))/m) }
  fix "Add skip link to #main-content in layout."
  bad  "<body><nav></nav><main></main></body>"
  good "<body><a href=\"#main-content\">skip</a><main id=\"main-content\"></main></body>"
end
