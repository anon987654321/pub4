# frozen_string_literal: true

# Migrated from data/rules.yml MIGRATION_ADD_REFERENCE_NO_FK.
Law.define(:MIGRATION_ADD_REFERENCE_NO_FK) do
  source "Rails migrations — foreign_key: true (Strong Migrations)"
  severity :error
  languages %i[ruby]
  path "/db/migrate/"
  detect { |line| line.match?(/add_reference(?!.*foreign_key:)/) }
  fix "Add `foreign_key: true` to enforce referential integrity."
  bad  "add_reference :posts, :user"
  good "add_reference :posts, :user, foreign_key: true"
end
