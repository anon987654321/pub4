# frozen_string_literal: true

# CI-facing wrapper around DesignTokens.dialect_token_drift (RAILS/tools/design_tokens.rb)
# -- reports any shared_chrome/luxury value that's drifted from
# design_tokens.yml across the per-app copies it gets hand-duplicated into.
# Fails CI on drift; fix with `ruby RAILS/tools/sync_dialect_tokens.rb`.

pub4_rails_root = ENV["PUB4_RAILS_ROOT"] || File.expand_path("../../..", __dir__)
require File.join(pub4_rails_root, "tools", "design_tokens")

findings = DesignTokens.dialect_token_drift
if findings.empty?
  puts "dialect_token_drift_check: ok (shared_chrome/luxury values match design_tokens.yml everywhere)"
  exit 0
else
  findings.each { |f| warn "dialect_token_drift_check: #{f} -- run: ruby RAILS/tools/sync_dialect_tokens.rb" }
  exit 1
end
