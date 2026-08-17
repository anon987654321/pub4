# frozen_string_literal: true

# Migrated from data/rules.yml LAZY_IMAGES.
Law.define(:LAZY_IMAGES) do
  source "Web performance — loading=\"lazy\" (web.dev / MDN)"
  severity :info
  languages %i[html]
  detect { |line| line.match?(/<img\s+(?![^>]*loading=)/) }
  fix "Add loading=\"lazy\"."
  bad  "<img src=\"a.png\" alt=\"a\">"
  good "<img src=\"a.png\" alt=\"a\" loading=\"lazy\">"
end
