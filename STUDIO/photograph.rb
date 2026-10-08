#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "visual/generators/idea_picture"

if $PROGRAM_NAME == __FILE__
  options = { film: false, duration: 5 }
  OptionParser.new do |parser|
    parser.on("--film", "also render the short film") { options[:film] = true }
    parser.on("--duration N", Integer, "film duration in seconds") { |value| options[:duration] = value }
  end.parse!

  prompt = ARGV.join(" ").strip
  abort "usage: ruby STUDIO/photograph.rb [--film] PROMPT" if prompt.empty?

  result = Studio::Visual::IdeaPicture.new.write(prompt, film: options[:film], duration: options[:duration])
  puts JSON.generate(result)
end
