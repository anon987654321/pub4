# frozen_string_literal: true

# Migrated from data/rules.yml DOUBLE_BRACKET.
Law.define(:DOUBLE_BRACKET) do
  source "ShellCheck — [[ ]] over [ ] in bash/zsh"
  severity :warn
  languages %i[zsh]
  detect { |line| line.match?(/(?<!\[)\[\s+[^\[]/) }
  fix "Use [[ ... ]] for safe conditionals."
  bad  "if [ -f x ]; then"
  good "if [[ -f x ]]; then"
end
