#!/usr/bin/env ruby
# frozen_string_literal: true

# RG-69 was the historical alternate name for Dilla. Keep one engine and
# forward the complete argument vector rather than maintaining a second CLI.
require "rbconfig"

target = File.expand_path("dilla.rb", __dir__)
exec(RbConfig.ruby, target, *ARGV)
