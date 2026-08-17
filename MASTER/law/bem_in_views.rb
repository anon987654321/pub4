# frozen_string_literal: true

# Migrated from data/rules.yml BEM_IN_VIEWS.
Law.define(:BEM_IN_VIEWS) do
  source "style.yml bare_tag_targeting — no BEM in ERB"
  severity :warn
  languages %i[html]
  detect { |line| line.match?(/class=["'][^"']*__[^"']*["']/) }
  fix "Target bare tags in SCSS; remove __block__element classes from ERB."
  bad  "<div class=\"card__title\">"
  good "<h2>"
end
