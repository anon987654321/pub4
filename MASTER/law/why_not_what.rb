# frozen_string_literal: true

# Migrated from data/rules.yml WHY_NOT_WHAT.
Law.define(:WHY_NOT_WHAT) do
  source "Clean Code / Code Complete — comments explain why, not what"
  severity :info
  detect { |line| line.match?(/#\s*(increment|set|get|update|return|initialize|create|add)\s+\w+/) }
  fix "Comments should explain intent, not restate the code."
  bad  "# increment counter"
  good "# retries are capped so a flapping host cannot pin the worker"
end
