#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "design_tokens"

changed = DesignTokens.sync_dialect_tokens!
if changed.empty?
  puts "dialect tokens already in sync with design_tokens.yml"
else
  changed.each { |line| puts line }
end
