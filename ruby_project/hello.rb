#!/usr/bin/env ruby

# Simple Hello World in Ruby
puts "Hello, World!"

# Demonstrate basic Ruby features
name = ARGV[0] || "User"
puts "Welcome, #{name}!"

# Array demonstration
languages = ["Ruby", "Python", "JavaScript", "Rust"]
puts "\nPopular programming languages:"
languages.each_with_index do |lang, index|
  puts "#{index + 1}. #{lang}"
end
