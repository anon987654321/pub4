# frozen_string_literal: true

# law/shell.rb — every shell law, one Law.define per rule.
# Was 6 one-rule files; Law.load_all and every fixture proof are
# unchanged by the grouping (2026-08-19 file-sprawl consolidation).

# Migrated from data/rules.yml DOLLAR_PAREN.
Law.define(:DOLLAR_PAREN) do
  source "ShellCheck SC2006 — $() over backticks"
  severity :warn
  languages %i[zsh]
  detect { |line| line.match?(/`[^`]+`/) }
  fix "Use $(command) — nestable and readable."
  bad  "now=`date`"
  good "now=$(date)"
end

# Migrated from data/rules.yml DOUBLE_BRACKET.
Law.define(:DOUBLE_BRACKET) do
  source "ShellCheck — [[ ]] over [ ] in bash/zsh"
  severity :warn
  languages %i[zsh]
  detect { |line| line.match?(/(?<!\[)\[\s+[^\[]/) }
  fix "Use [[ ... ]] for safe conditionals."
  bad  "if [ -f x ]; then"
  good "if [[ -f x ]]; then"
end

# New. Restores the guard added after the 2026-01-05 incident (16 untracked
# files batch-deleted before a conversion step) that did not survive the
# master.yml -> MASTER migration. Consequence class: unrecoverable data loss.
Law.define(:NEVER_BATCH_DELETE) do
  source "master.yml v66 file_deletion_protocol — never batch-delete files"
  severity :error
  languages %i[ruby shell]
  detect do |line|
    line.match?(/\brm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)*[^\s;|&]*[*?{]/) ||
      line.match?(/FileUtils\.rm(_r|_rf|_f)?\(?\s*Dir\[/) ||
      line.match?(/\.each\s*\{[^}]*(?:File\.delete|FileUtils\.rm)/)
  end
  fix "Delete one named path per call and confirm first; globs and .each { rm } need an explicit operator ack."
  bad  <<~RUBY
    FileUtils.rm_rf(Dir["tmp/*.txt"])
    system("rm -f build/*.o")
    stale.each { |f| File.delete(f) }
  RUBY
  good <<~RUBY
    FileUtils.rm("tmp/session.txt")
    system("rm", "-f", "build/main.o")
    File.delete(path) if confirmed?(path)
  RUBY
end

# Migrated from data/rules.yml NO_INLINE_ASSETS_IN_SHELL.
Law.define(:NO_INLINE_ASSETS_IN_SHELL) do
  source "RAILS/shared frontend convention"
  severity :warn
  languages %i[zsh]
  detect { |line| line.match?(/<style\b|<script\b/) }
  fix "Move the markup into app/views and the style into a tracked stylesheet."
  bad  "print '<style>body{}</style>' > index.html"
  good "cp app/assets/site.css out/"
end

# QUOTE_VARIABLES lives once, in the registry (js_rules.rb): quoting is a
# fact about the interpreter — zsh does not word-split or glob unquoted
# parameter expansions; sh, ksh and bash all do — and only the registry can
# read the shebang. 455 of the deep scan's 573 quoting errors were idiomatic
# zsh flagged by a sh doctrine.

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
