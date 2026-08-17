# frozen_string_literal: true

# Migrated from data/rules.yml META_CHARSET.
Law.define(:META_CHARSET) do
  source "HTML Living Standard — <meta charset=\"utf-8\"> (WHATWG)"
  severity :error
  languages %i[html]
  scope :file
  detect { |text| text.match?(/\A(?!.*<meta\s+charset=)/m) }
  fix "Add <meta charset=UTF-8> as first element in <head>."
  bad  "<head><title>x</title></head>"
  good "<head><meta charset=\"UTF-8\"></head>"
end
