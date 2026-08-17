# frozen_string_literal: true

# Migrated from data/rules.yml STRICT_MODE_ZSH.
Law.define(:STRICT_MODE_ZSH) do
  source "Shell strict mode set -euo pipefail (Google Shell Style Guide)"
  severity :error
  languages %i[zsh]
  scope :file
  detect { |text| text.match?(/^#!\/.*(?:ba|z)sh\n(?!set -)/m) }
  fix "Add 'set -euo pipefail' after shebang."
  bad <<~X
    #!/usr/bin/env zsh
    echo hi
  X
  good <<~X
    #!/usr/bin/env zsh
    set -euo pipefail
  X
end
