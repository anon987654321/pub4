#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/operator/rule_reach"

exit Operator::RuleReach.run(
  ratchet: ARGV.include?("--ratchet"),
  json: ARGV.include?("--json")
)
