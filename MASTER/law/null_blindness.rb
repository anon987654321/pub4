# frozen_string_literal: true

# Migrated from data/rules.yml NULL_BLINDNESS.
Law.define(:NULL_BLINDNESS) do
  source "SQL/Ruby — explicit NULL/nil handling"
  severity :error
  detect { |line| line.match?(/= NULL|!= NULL|== nil.*column|column.*== nil/) }
  fix "Use IS NULL / IS NOT NULL in SQL; .nil? in Ruby."
  bad  "WHERE deleted_at = NULL"
  good "WHERE deleted_at IS NULL"
end
