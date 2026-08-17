# frozen_string_literal: true

# Migrated from data/rules.yml USE_THEN.
Law.define(:USE_THEN) do
  source "Ruby idiom — Object#then (yield_self) for pipelines"
  severity :info
  languages %i[ruby]
  scope :file
  detect { |text| text.match?(/(\w+)\s*=\s*\w+\(.*\)\n\s*\w+\(\1\)/m) }
  fix "Chain with .then { |r| next_step(r) }"
  bad <<~X
    r = parse(src)
    render(r)
  X
  good <<~X
    parse(src).then { |r| render(r) }
  X
end
