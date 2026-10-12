#!/usr/bin/env ruby
# frozen_string_literal: true

# Exit 1 and list every tracked Ruby file that does not parse. Standalone on
# purpose: CI runs it with no bundle, and it must not need the runtime it is
# guarding to boot.
require_relative "../lib/operator/parse_sweep"

root = File.expand_path("../..", __dir__)
broken = Operator::ParseSweep.failures(root)
if broken.empty?
  puts "parse_sweep: every tracked Ruby file parses"
  exit 0
end

warn "parse_sweep: #{broken.size} file(s) do not parse"
warn Operator::ParseSweep.render(broken)
exit 1
