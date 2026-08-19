# frozen_string_literal: true

# Migrated from data/rules.yml NULL_BLINDNESS. The second retired twin: the
# registry version's regex flagged IS NULL — the correct form its own message
# prescribes — and survived on a path exemption; this detector flags the
# defect, and the good fixture below is the line the registry version would
# have failed on. A comment only talks about the pattern.
Law.define(:NULL_BLINDNESS) do
  source "SQL/Ruby — explicit NULL/nil handling"
  severity :error
  detect { |line| (s = line.strip) && !s.start_with?("#") && s.match?(/= NULL|!= NULL|== nil.*column|column.*== nil/) }
  fix "Use IS NULL / IS NOT NULL in SQL; .nil? in Ruby."
  bad  "WHERE deleted_at = NULL"
  good <<~X
    WHERE deleted_at IS NULL
    # `= NULL` -> `IS NULL`, in SQL and nowhere else.
  X
end
