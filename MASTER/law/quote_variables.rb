# frozen_string_literal: true

# Migrated from data/rules.yml QUOTE_VARIABLES.
Law.define(:QUOTE_VARIABLES) do
  source "ShellCheck / Google Shell Style Guide — quote variables"
  severity :error
  languages %i[zsh]
  detect { |line| line.match?(/(?<!["'\\])\$\w+(?!["'])/) }
  fix "Use \"$VAR\" to prevent word splitting."
  bad  "echo $HOME"
  good "echo \"$HOME\""
end
