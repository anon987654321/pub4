# frozen_string_literal: true

# law/rails.rb — every rails law, one Law.define per rule.
# Was 4 one-rule files; Law.load_all and every fixture proof are
# unchanged by the grouping (2026-08-19 file-sprawl consolidation).

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

# Migrated from data/rules.yml N_PLUS_ONE.
Law.define(:N_PLUS_ONE) do
  source "Rails performance — avoid N+1 queries (Bullet/Rails Guides)"
  severity :warn
  languages %i[rails]
  detect { |line| line.match?(/\.(each|map|collect)\s*(do|\{).*\.\w+\.\w+/) }
  fix "Add .includes(:association)."
  bad  "posts.each do |p| p.author.name end"
  good "posts.includes(:author).each { |p| p.author }"
end

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
