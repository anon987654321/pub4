# frozen_string_literal: true

# Migrated from data/rules.yml HTML_LANG.
Law.define(:HTML_LANG) do
  source "WCAG 3.1.1 Language of Page (W3C/WAI)"
  severity :error
  languages %i[html]
  detect { |line| line.match?(/<html(?!\s+[^>]*lang=)/) }
  fix "Add lang=\"en\" or appropriate locale."
  bad  "<html>"
  good "<html lang=\"nb\">"
end
