# frozen_string_literal: true

# Migrated from data/rules.yml FEW_ARGUMENTS.
Law.define(:FEW_ARGUMENTS) do
  source "Clean Code — minimize arguments (R.C. Martin)"
  severity :warn
  languages %i[ruby]
  detect { |line| line.match?(/def \w+\([^)]*,[^:)]+,[^:)]+,[^:)]+\)/) }
  fix "Group into keyword arguments or parameter object."
  bad  "def build(name, size, color, weight)"
  good "def build(spec:)"
end
