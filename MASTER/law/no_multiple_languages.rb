# frozen_string_literal: true

# One language per layer: a query language inside Ruby, markup inside
# JavaScript, a heredoc smuggling a third grammar past the reader.
#
# Templates are exempt, and have to be. A template is two languages on purpose —
# that is the entire definition — so matching the ERB opening tag flagged the
# thing that makes the file work. Across RAILS' 428 views this rule produced
# 6,826 findings, 75% of everything MASTER reported about those files, and every
# one of them said "this template contains a template". The law/ header calls
# that the decorator-massacre failure mode: a rule whose false-positive rate
# makes the report unreadable stops being enforcement and becomes noise.
#
# The genuine html case — an inline script or style block, five files in the
# whole tree — is NO_INLINE_SCRIPT_BLOCK, where the detector can be honest about
# what it wants instead of catching a language marker by accident.
Law.define(:NO_MULTIPLE_LANGUAGES) do
  source "MASTER-native (one language per file)"
  severity :warn
  languages %i[ruby javascript css scss zsh]
  detect { |line| line.match?(/<%|<script|<style|SQL|HEREDOC/) }
  fix "One language per layer. Separate into distinct files or clearly demarcated sections."
  bad  "rows = connection.exec(<<~SQL)"
  good "rows = connection.exec(query)"
end
