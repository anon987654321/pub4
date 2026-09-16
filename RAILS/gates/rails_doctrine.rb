#!/usr/bin/env ruby
# frozen_string_literal: true

# Thin wrapper to invoke MASTER's /fix for the Rails tree.
# This ensures ALL constitutional rules are applied, not just a subset.

REPO_ROOT = File.expand_path("../../..", __dir__)
MASTER_BIN = File.join(REPO_ROOT, "MASTER/bin/ruby")
MASTER_CLI = File.join(REPO_ROOT, "MASTER/bin/cli")

# We invoke /fix on the RAILS tree. 
# By omitting the --rules flag, MASTER defaults to the full universal ruleset in data/rules.yml.
cmd = [MASTER_BIN, MASTER_CLI, "-m", "/fix RAILS/"]
output = `#{cmd.join(' ')} 2>&1`
exit $?.success? ? 0 : 1
