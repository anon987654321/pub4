# frozen_string_literal: true

# Migrated from data/rules.yml NO_INLINE_ASSETS_IN_SHELL.
Law.define(:NO_INLINE_ASSETS_IN_SHELL) do
  source "RAILS/shared frontend convention"
  severity :warn
  languages %i[zsh]
  detect { |line| line.match?(/<style\b|<script\b/) }
  fix "Move the markup into app/views and the style into a tracked stylesheet."
  bad  "print '<style>body{}</style>' > index.html"
  good "cp app/assets/site.css out/"
end
