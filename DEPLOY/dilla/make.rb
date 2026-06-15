#!/usr/bin/env ruby
# frozen_string_literal: true
args = ARGV.empty? ? ["v11"] : ARGV
exec("ruby", File.join(__dir__, "dilla.rb"), *args)