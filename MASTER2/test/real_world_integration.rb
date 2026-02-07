#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/master"

puts "=== Real-World Integration Test ==="
puts

# Test 1: Try to modify constitution (should fail)
puts "1. Attempting to modify constitution..."
executor = MASTER::Executor.new
result = executor.send(:file_write, "data/constitution.yml", "malicious")
if result.include?("BLOCKED")
  puts "   ✓ Blocked successfully"
else
  puts "   ✗ FAILED: Constitution was not protected!"
  exit 1
end

# Test 2: Create a temporary file and use staging
puts "2. Testing staging workflow..."
require "tmpdir"
Dir.mktmpdir do |dir|
  # Create test file
  test_file = File.join(dir, "sample.rb")
  File.write(test_file, "puts 'hello'")
  
  # Use staging
  staging = MASTER::Staging.new
  staging.stage(test_file)
  
  # Modify in staging
  staged_path = staging.staged_files.first[:staged]
  File.write(staged_path, "puts 'world'")
  
  # Validate and promote
  staging.validate { "OK" }
  result = staging.promote
  
  if result.ok? && File.read(test_file).include?("world")
    puts "   ✓ Staging workflow successful"
  else
    puts "   ✗ FAILED: Staging did not work"
    exit 1
  end
  
  staging.rollback
end

# Test 3: Verify Evolve can be used in both modes
puts "3. Testing Evolve modes..."
evolve_default = MASTER::Evolve.new
evolve_staged = MASTER::Evolve.new(staged: true)

if !evolve_default.instance_variable_get(:@staged) && evolve_staged.instance_variable_get(:@staged)
  puts "   ✓ Both Evolve modes work"
else
  puts "   ✗ FAILED: Evolve modes not working"
  exit 1
end

# Test 4: Verify planner works
puts "4. Testing Planner..."
planner = MASTER::Planner.new(nil)
tasks = planner.send(:parse_tasks, "1. Task one\n2. Task two\n")
if tasks.size == 2
  puts "   ✓ Planner functional"
else
  puts "   ✗ FAILED: Planner not working"
  exit 1
end

puts
puts "=== All Integration Tests Passed ✓ ==="
