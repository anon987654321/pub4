# frozen_string_literal: true

# Migrated from data/rules.yml NO_JQUERY.
Law.define(:NO_JQUERY) do
  source "RAILS/shared frontend convention"
  severity :warn
  languages %i[javascript html]
  detect { |line| line.match?(/jQuery\(|\$\((?=\s*["\x27#.])/) }
  fix "Replace the selector call with a Stimulus target or querySelector."
  bad  "$('#menu').show()"
  good "document.querySelector('#menu').hidden = false"
end
