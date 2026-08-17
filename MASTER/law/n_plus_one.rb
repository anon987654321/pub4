# frozen_string_literal: true

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
