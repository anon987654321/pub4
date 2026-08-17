# frozen_string_literal: true

# Migrated from data/rules.yml FIND_EACH.
Law.define(:FIND_EACH) do
  source "Rails — find_each batch processing (Rails Guides)"
  severity :warn
  languages %i[rails]
  detect { |line| line.match?(/\.(all\.each|where\(.*\)\.each)\b/) }
  fix "Use .find_each(batch_size: 1000)."
  bad  "User.all.each { |u| mail(u) }"
  good "User.find_each { |u| mail(u) }"
end
