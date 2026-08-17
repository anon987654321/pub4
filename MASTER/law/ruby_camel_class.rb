# frozen_string_literal: true

# Migrated from data/rules.yml RUBY_CAMEL_CLASS.
Law.define(:RUBY_CAMEL_CLASS) do
  source "Ruby Style Guide / RuboCop Naming/ClassAndModuleCamelCase"
  severity :warn
  languages %i[ruby]
  detect { |line| line.match?(/^\s*(class|module)\s+([a-z]|[A-Z]\w*_)/) }
  fix "Rename to CamelCase: class Album_store -> class AlbumStore."
  bad  "class Album_store"
  good "class AlbumStore"
end
