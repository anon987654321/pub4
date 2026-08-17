# frozen_string_literal: true

# Migrated from data/rules.yml GUARD_CLAUSE.
Law.define(:GUARD_CLAUSE) do
  source "Ruby Style Guide / RuboCop Style/GuardClause"
  severity :info
  languages %i[ruby]
  scope :file
  detect { |text| text.match?(/^\s*def \w+.*\n\s*if .+\n(?:.*\n)*?\s*else\n(?:.*\n)*?\s*end\s*$/m) }
  fix "Flatten to: return ... unless condition"
  bad <<~X
    def go(x)
      if x
        run
      else
        nil
      end
    end
  X
  good <<~X
    def go(x)
      return unless x
      run
    end
  X
end
