# frozen_string_literal: true

# Migrated from data/rules.yml I18N_COVERAGE.
Law.define(:I18N_COVERAGE) do
  source "Rails i18n best practice (no hardcoded strings)"
  severity :warn
  languages %i[html]
  path "/app/views/"
  detect { |line| line.match?(/>\s*[A-Za-z][^<]{3,}</) }
  fix "Replace literal with t('.key')."
  bad  "<p>Welcome back</p>"
  good "<p><%= t('.welcome') %></p>"
end
