#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/operator/law_reach"

exit Operator::LawReach.run(json: ARGV.include?("--json"))
