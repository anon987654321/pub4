# frozen_string_literal: true

# Migrated from data/rules.yml NO_FLAG_ARGUMENTS.
Law.define(:NO_FLAG_ARGUMENTS) do
  source "Clean Code — no flag arguments (Robert C. Martin)"
  severity :warn
  detect { |line| line.match?(/def \w+\([^)]*\btrue\b|def \w+\([^)]*\bfalse\b/) }
  fix "Split into two distinct units. Each does one thing."
  bad  "def render(doc, true)"
  good "def render(doc)"
end
