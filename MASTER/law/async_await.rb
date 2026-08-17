# frozen_string_literal: true

# Migrated from data/rules.yml ASYNC_AWAIT.
Law.define(:ASYNC_AWAIT) do
  source "ECMAScript 2017 — async/await over raw promises"
  severity :warn
  languages %i[javascript]
  detect { |line| line.match?(/\.then\(.*\.then\(.*\.then\(/) }
  fix "Use async/await for readability."
  bad  "a().then(b).then(c).then(d)"
  good "await a(); await b();"
end
