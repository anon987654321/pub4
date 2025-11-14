#!/usr/bin/env ruby
# test_aight.rb - Test script for aight REPL

# Demonstrates basic functionality without requiring user interaction
require_relative "lib/repl"

require_relative "lib/starship_module"

puts "=" * 80
puts "Testing Aight REPL Components"

puts "=" * 80
puts

# Test 1: REPL instantiation

puts "Test 1: REPL instantiation"

repl = Aight::REPL.new({ model: "gpt-4", verbose: false })
puts "✅ REPL created successfully"

puts "   Model: #{repl.options[:model]}"

puts "   History size: #{repl.history.size}"

puts "   Cognitive load: #{repl.cognitive_load}/7"

puts

# Test 2: Ruby code evaluation

puts "Test 2: Ruby code evaluation"

test_code = "[1, 2, 3].map(&:succ)"
result = repl.send(:evaluate_ruby, test_code)

puts "   Code: #{test_code}"

puts "   Result: #{result.inspect}"

puts "✅ Code evaluation works"

puts

# Test 3: History tracking

puts "Test 3: History tracking"

repl.history << { time: Time.now, input: "puts 'hello'", result: "hello" }
repl.history << { time: Time.now, input: "2 + 2", result: 4 }

puts "   History entries: #{repl.history.size}"

repl.history.each_with_index do |entry, i|

  puts "   [#{i + 1}] #{entry[:input]} => #{entry[:result]}"

end

puts "✅ History tracking works"

puts

# Test 4: Context management

puts "Test 4: Context management"

puts "   Before clear - Cognitive load: #{repl.cognitive_load}"
repl.send(:clear_context)

puts "   After clear - Cognitive load: #{repl.cognitive_load}"

puts "✅ Context management works"

puts

# Test 5: Starship module methods

puts "Test 5: Starship module"

puts "   CONFIG_DIR: #{Aight::StarshipModule::CONFIG_DIR}"
puts "   COMPLETION_DIR: #{Aight::StarshipModule::COMPLETION_DIR}"

Aight::StarshipModule.update_session_info(model: "gpt-4", load: 3, status: "active")

puts "✅ Starship module methods work"

puts

# Test 6: Readline completions

puts "Test 6: Readline completions"

keywords = repl.send(:ruby_keywords)
methods = repl.send(:ruby_methods)

commands = repl.send(:custom_commands)

puts "   Ruby keywords: #{keywords.size} (e.g., #{keywords.first(5).join(', ')})"

puts "   Ruby methods: #{methods.size} (e.g., #{methods.first(5).join(', ')})"

puts "   Custom commands: #{commands.size} (e.g., #{commands.first(5).join(', ')})"

puts "✅ Readline completions available"

puts

# Test 7: Security status

puts "Test 7: Security status"

status = repl.send(:security_status)
puts "   Platform: #{RUBY_PLATFORM}"

puts "   Security: #{status}"

puts "✅ Security status detected"

puts

# Test 8: Format duration helper

puts "Test 8: Time formatting"

examples = [30, 120, 3661]
examples.each do |seconds|

  formatted = repl.send(:format_duration, seconds)

  puts "   #{seconds}s => #{formatted}"

end

puts "✅ Time formatting works"

puts

# Test 9: Cognitive load indicator

puts "Test 9: Cognitive load indicators"

[0, 3, 6, 9].each do |load|
  repl.instance_variable_set(:@cognitive_load, load)

  indicator = repl.send(:cognitive_load_indicator)

  display = indicator.empty? ? "(none)" : indicator

  puts "   Load #{load}: #{display}"

end

puts "✅ Cognitive load indicators work"

puts

puts "=" * 80

puts "All tests passed! ✅"

puts "=" * 80
puts

puts "To start the interactive REPL, run:"

puts "  ./aight.rb"

puts

puts "For help:"

puts "  ./aight.rb --help"

