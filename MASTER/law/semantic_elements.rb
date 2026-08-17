# frozen_string_literal: true

# Migrated from data/rules.yml SEMANTIC_ELEMENTS. Folds ANTI_DIVITIS (identical detector).
Law.define(:SEMANTIC_ELEMENTS) do
  source "HTML5 semantics / WCAG 1.3.1 (W3C)"
  severity :warn
  languages %i[html]
  detect { |line| line.match?(/<div\s+class="(header|footer|nav|main|sidebar|article|section)"/) }
  fix "Use <header>, <footer>, <nav>, <main>, <aside>, <article>, <section>."
  bad  "<div class=\"header\">"
  good "<header>"
end
