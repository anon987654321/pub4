# frozen_string_literal: true

# Migrated from data/rules.yml NO_MULTIPLE_LANGUAGES.
Law.define(:NO_MULTIPLE_LANGUAGES) do
  source "MASTER-native (one language per file)"
  severity :warn
  detect { |line| line.match?(/<%|<script|<style|SQL|HEREDOC/) }
  fix "One language per layer. Separate into distinct files or clearly demarcated sections."
  bad  "<div><script>x()</script></div>"
  good "<div class=\"card\"></div>"
end
