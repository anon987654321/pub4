# frozen_string_literal: true

# Migrated from data/rules.yml NO_COLUMN_ALIGN.
Law.define(:NO_COLUMN_ALIGN) do
  source "Ruby Style Guide / RuboCop Layout — no token alignment"
  severity :info
  detect { |line| line.match?(/\S {2,}(?:=>|[^=!<>]=[^=>]|:\s)/) }
  fix "Remove padding; one space before operators. Column alignment decays and hides diffs."
  bad  "name    = 1"
  good "name = 1"
end
