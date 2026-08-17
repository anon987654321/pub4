# frozen_string_literal: true

# Migrated from data/rules.yml RUBY_SNAKE_METHODS.
Law.define(:RUBY_SNAKE_METHODS) do
  source "Ruby Style Guide / RuboCop Naming/MethodName"
  severity :warn
  languages %i[ruby]
  detect { |line| line.match?(/\bdef\s+[a-z][a-z0-9_]*[A-Z]/) }
  fix "Rename to snake_case: def fetchAlbum -> def fetch_album."
  bad  "def fetchAlbum"
  good "def fetch_album"
end
