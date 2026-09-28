#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/operator/autofix_reach"

ok = Operator::AutofixReach.run(json: ARGV.include?("--json"))
exit(ok ? 0 : 1)
