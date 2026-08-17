# frozen_string_literal: true

# Migrated from data/rules.yml UNBOUNDED_RETRY.
Law.define(:UNBOUNDED_RETRY) do
  source "Release It! — retry budgets / bounded retries (Nygard)"
  severity :error
  detect { |line| line.match?(/\bretry\b|while\s+true/) }
  fix "Add max_attempts cap and exponential backoff."
  bad  "retry"
  good "attempts += 1 and redo if attempts < 3"
end
