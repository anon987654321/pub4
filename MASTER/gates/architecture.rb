#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/master"

root = File.expand_path("..", __dir__)
report = Master::Phoenix.check(root:)

if report.clean
  puts Master::Phoenix.line(root:)
  exit 0
end

report.failures.each { |failure| warn "phoenix0: #{failure}" }
exit 1
