# frozen_string_literal: true

# Migrated from data/rules.yml FROZEN_STRING_LITERAL.
Law.define(:FROZEN_STRING_LITERAL) do
  source "Ruby Style Guide / RuboCop Style/FrozenStringLiteralComment"
  severity :warn
  languages %i[ruby]
  scope :file
  detect { |text| text.match?(/\A(?!# frozen_string_literal)/m) }
  fix "Add '# frozen_string_literal: true' as first line."
  bad <<~X
    require "json"
  X
  good <<~X
    # frozen_string_literal: true
  X
end
