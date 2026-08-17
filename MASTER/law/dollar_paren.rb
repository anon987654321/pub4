# frozen_string_literal: true

# Migrated from data/rules.yml DOLLAR_PAREN.
Law.define(:DOLLAR_PAREN) do
  source "ShellCheck SC2006 — $() over backticks"
  severity :warn
  languages %i[zsh]
  detect { |line| line.match?(/`[^`]+`/) }
  fix "Use $(command) — nestable and readable."
  bad  "now=`date`"
  good "now=$(date)"
end
