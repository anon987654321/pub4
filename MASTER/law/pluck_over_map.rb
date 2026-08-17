# frozen_string_literal: true

# Migrated from data/rules.yml PLUCK_OVER_MAP.
Law.define(:PLUCK_OVER_MAP) do
  source "Rails performance — pluck over map(&:attr)"
  severity :info
  languages %i[rails]
  detect { |line| line.match?(/\.\w+\.map\(&:\w+\)/) }
  fix "Use .pluck(:column) to avoid AR object instantiation."
  bad  "User.all.map(&:email)"
  good "User.pluck(:email)"
end
