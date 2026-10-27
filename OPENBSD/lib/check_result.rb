# frozen_string_literal: true

# The check kernel lives once, in MASTER/checks/support/check_result.rb. This path
# stays because checks and tests across RAILS and OPENBSD require it by name, and
# OPENBSD/lib already reads MASTER beside it: check_runner.rb loads MASTER/lib/io/exec.
# Both spellings resolve to one file, so a process that loads each still defines
# Deploy::CheckResult once.
require_relative "../../MASTER/checks/support/check_result"
