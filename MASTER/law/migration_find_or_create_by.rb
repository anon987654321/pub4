# frozen_string_literal: true

# Migrated from data/rules.yml MIGRATION_FIND_OR_CREATE_BY.
Law.define(:MIGRATION_FIND_OR_CREATE_BY) do
  source "Rails best practice — find_or_create_by races"
  severity :warn
  languages %i[ruby]
  path "/db/migrate/"
  detect { |line| line.match?(/find_or_create_by/) }
  fix "Back find_or_create_by with a unique index to prevent duplicates."
  bad  "Role.find_or_create_by(name: 'admin')"
  good "Role.create!(name: 'admin')"
end
