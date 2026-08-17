# frozen_string_literal: true

# Migrated from data/rules.yml NO_IMPORT_SCSS.
Law.define(:NO_IMPORT_SCSS) do
  source "Sass best practice — @use over @import (Sass team)"
  severity :warn
  languages %i[scss]
  detect { |line| line.match?(/@import\s+["']/) }
  fix "@import is deprecated. Use @use/@forward."
  bad  "@import \"base\";"
  good "@use \"base\";"
end
