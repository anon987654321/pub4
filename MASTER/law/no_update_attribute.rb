# frozen_string_literal: true

# Migrated from data/rules.yml NO_UPDATE_ATTRIBUTE.
Law.define(:NO_UPDATE_ATTRIBUTE) do
  source "Rails — update_attribute skips validations (best practice)"
  severity :error
  languages %i[rails]
  detect { |line| line.match?(/\.update_attribute\(/) }
  fix "update_attribute skips validations. Use update!"
  bad  "user.update_attribute(:name, n)"
  good "user.update!(name: n)"
end
