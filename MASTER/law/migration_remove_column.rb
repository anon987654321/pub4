# frozen_string_literal: true

# Migrated from data/rules.yml MIGRATION_REMOVE_COLUMN.
Law.define(:MIGRATION_REMOVE_COLUMN) do
  source "Strong Migrations — safe column removal (Andrew Kane)"
  severity :error
  languages %i[ruby]
  path "/db/migrate/"
  detect { |line| line.match?(/remove_column/) }
  fix "Document safety/backfill path before removing a column."
  bad  "remove_column :users, :legacy"
  good "add_column :users, :name, :string"
end
