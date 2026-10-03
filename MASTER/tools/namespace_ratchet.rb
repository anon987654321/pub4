#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/operator/namespace_ratchet"

exit Operator::NamespaceRatchet.run(
  ratchet: ARGV.include?("--ratchet"),
  json: ARGV.include?("--json")
)
