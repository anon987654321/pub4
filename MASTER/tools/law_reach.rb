#!/usr/bin/env ruby
# frozen_string_literal: true

lib = File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "master"
require_relative "../lib/operator/law_reach"

exit Operator::LawReach.run(json: ARGV.include?("--json"))
