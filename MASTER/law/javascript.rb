# frozen_string_literal: true

# law/javascript.rb — every javascript law, one Law.define per rule.
# Was 7 one-rule files; Law.load_all and every fixture proof are
# unchanged by the grouping (2026-08-19 file-sprawl consolidation).
#
# The vendored three.module.js is upstream code this repo does not author;
# the registry twins carried that exclusion and it moved here with them
# (2026-08-21 twin retirement).

# Migrated from data/rules.yml ASYNC_AWAIT.
Law.define(:ASYNC_AWAIT) do
  source "ECMAScript 2017 — async/await over raw promises"
  severity :warn
  languages %i[javascript]
  path_exclude %r{/public/three\.module\.js\z}
  detect { |line| line.match?(/\.then\(.*\.then\(.*\.then\(/) }
  fix "Use async/await for readability."
  bad  "a().then(b).then(c).then(d)"
  good "await a(); await b();"
end

# CONST_BY_DEFAULT lives once, in the registry (js_rules.rb): it reads the
# rest of the file to ask whether the variable is ever reassigned before it
# calls a `let` wrong. This line detector flagged every `let` in the tree,
# including the ones whose reassignment is the reason they are `let`.

# Migrated from data/rules.yml FOR_OF.
Law.define(:FOR_OF) do
  source "Airbnb JS Style Guide — for...of over for...in"
  severity :error
  languages %i[javascript]
  path_exclude %r{/public/three\.module\.js\z}
  detect { |line| line.match?(/for\s*\(\s*(const|let|var)\s+\w+\s+in\s+/) }
  fix "for...in iterates prototype properties. Use for...of."
  bad  "for (const k in list) {"
  good "for (const k of list) {"
end

# Migrated from data/rules.yml NO_VAR.
Law.define(:NO_VAR) do
  source "Airbnb JS Style Guide — no var (ES6 let/const)"
  severity :error
  languages %i[javascript]
  path_exclude %r{/public/three\.module\.js\z}
  detect { |line| line.match?(/\bvar\s+\w/) }
  fix "Use const (default) or let (when reassigned)."
  bad  "var x = 1;"
  good "const x = 1;"
end

# Migrated from data/rules.yml NULLISH_COALESCING.
Law.define(:NULLISH_COALESCING) do
  source "ECMAScript 2020 — nullish coalescing (??)"
  severity :info
  languages %i[javascript]
  path_exclude %r{/public/three\.module\.js\z}
  detect { |line| line.match?(/(\w+)\s*\|\|\s*\w+/) }
  fix "Use ?? when 0 or '' are valid values."
  bad  "count || fallback"
  good "count ?? fallback"
end

# Migrated from data/rules.yml OPTIONAL_CHAINING.
Law.define(:OPTIONAL_CHAINING) do
  source "ECMAScript 2020 — optional chaining (?.)"
  severity :warn
  languages %i[javascript]
  path_exclude %r{/public/three\.module\.js\z}
  detect { |line| line.match?(/(\w+)\s*&&\s*\1\.\w+/) }
  fix "Rewrite to obj?.foo?.bar"
  bad  "user && user.name"
  good "user?.name"
end

# Migrated from data/rules.yml TEMPLATE_LITERALS.
Law.define(:TEMPLATE_LITERALS) do
  source "Airbnb JS Style Guide — template literals (ES6)"
  severity :warn
  languages %i[javascript]
  path_exclude %r{/public/three\.module\.js\z}
  detect { |line| line.match?(/["']\s*\+\s*\w+\s*\+\s*["']/) }
  fix "Use `Hello ${name}!` template literals."
  bad  "'Hello ' + name + '!'"
  good "`Hello ${name}!`"
end
