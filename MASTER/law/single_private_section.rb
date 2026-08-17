# frozen_string_literal: true

# Migrated from data/rules.yml SINGLE_PRIVATE_SECTION.
Law.define(:SINGLE_PRIVATE_SECTION) do
  source "Ruby Style Guide / RuboCop Style/AccessModifierDeclarations"
  severity :info
  languages %i[ruby]
  detect { |line| line.match?(/private\s+:\w+/) }
  fix "Use a single 'private' keyword with methods below it."
  bad  "private :helper"
  good <<~X
    private

    def helper; end
  X
end
