#!/usr/bin/env ruby
# frozen_string_literal: true
cmd = case ARGV[0]
      when "render", nil then "analog"
      when "liveset" then "analog_liveset"
      else ARGV[0]
      end
args = %w[render liveset].include?(ARGV[0]) || ARGV[0].nil? ? ARGV.drop(1) : ARGV
exec("ruby", File.join(__dir__, "dilla.rb"), cmd, *args)