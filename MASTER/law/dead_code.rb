# frozen_string_literal: true

# Migrated from data/rules.yml DEAD_CODE.
Law.define(:DEAD_CODE) do
  source "Refactoring — remove dead code (Fowler) / Clean Code"
  severity :warn
  scope :file
  detect { |text| text.match?(/(?:return|exit|raise|throw)\b(?![^\n]*\b(?:if|unless)\b)[^\n]*\n\s*\w+/m) }
  fix "Remove code after return/exit/raise/throw."
  bad <<~X
    return x
    cleanup
  X
  good <<~X
    return x if done
    cleanup
  X
end
