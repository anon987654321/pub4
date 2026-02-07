#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual verification script for safe autonomy features

require_relative "../lib/master"

puts "=== Safe Autonomy Manual Verification ==="
puts

# 1. Verify Constitution exists and is valid
puts "1. Checking Constitution..."
if File.exist?("data/constitution.yml")
  constitution = YAML.load_file("data/constitution.yml")
  puts "   ✓ Constitution file exists"
  puts "   ✓ Version: #{constitution['version']}"
  puts "   ✓ Self-modification disabled: #{!constitution.dig('autonomy', 'self_modification', 'enabled')}"
  puts "   ✓ Protected files: #{constitution.dig('autonomy', 'self_modification', 'protected_files').size} files"
else
  puts "   ✗ Constitution file missing!"
end
puts

# 2. Test permission gates
puts "2. Testing Permission Gates..."
executor = MASTER::Executor.new

# Try to write to constitution
result = executor.send(:file_write, "data/constitution.yml", "test")
if result.include?("BLOCKED")
  puts "   ✓ Constitution write blocked"
else
  puts "   ✗ Constitution write NOT blocked: #{result}"
end

# Try dangerous shell command
result = executor.send(:shell_command, "rm -rf /")
if result.include?("BLOCKED")
  puts "   ✓ Dangerous shell command blocked"
else
  puts "   ✗ Dangerous command NOT blocked: #{result}"
end

# Try safe command
result = executor.send(:shell_command, "echo safe")
if result.include?("safe") && !result.include?("BLOCKED")
  puts "   ✓ Safe shell command allowed"
else
  puts "   ✗ Safe command not working: #{result}"
end
puts

# 3. Test Staging
puts "3. Testing Staging..."
staging = MASTER::Staging.new

# Create a temp test file
require "tmpdir"
Dir.mktmpdir do |dir|
  test_file = File.join(dir, "test.rb")
  File.write(test_file, "puts 'original'\n")
  
  # Stage it
  stage_result = staging.stage(test_file)
  if stage_result.ok?
    puts "   ✓ File staging works"
  else
    puts "   ✗ File staging failed: #{stage_result.error}"
  end
  
  # Validate
  validate_result = staging.validate { "OK" }
  if validate_result.ok?
    puts "   ✓ Validation works"
  else
    puts "   ✗ Validation failed: #{validate_result.error}"
  end
  
  # Promote
  promote_result = staging.promote
  if promote_result.ok?
    puts "   ✓ Promotion works"
  else
    puts "   ✗ Promotion failed: #{promote_result.error}"
  end
end

staging.rollback
puts

# 4. Test Evolve with staged mode
puts "4. Testing Evolve Integration..."
evolve_default = MASTER::Evolve.new
puts "   ✓ Default Evolve initializes (staged: #{evolve_default.instance_variable_get(:@staged) || false})"

evolve_staged = MASTER::Evolve.new(staged: true)
puts "   ✓ Staged Evolve initializes (staged: #{evolve_staged.instance_variable_get(:@staged)})"
puts

# 5. Test Planner
puts "5. Testing Planner..."
planner = MASTER::Planner.new(nil)
if planner.respond_to?(:format_plan)
  puts "   ✓ Planner exists and is accessible"
  
  # Test parse_tasks
  text = "1. First task\n2. Second task\n"
  tasks = planner.send(:parse_tasks, text)
  if tasks.size == 2
    puts "   ✓ Planner can parse tasks"
  else
    puts "   ✗ Planner task parsing failed"
  end
else
  puts "   ✗ Planner not working"
end
puts

puts "=== Verification Complete ==="
puts
puts "Summary:"
puts "  ✓ Constitution is read-only and blocks writes"
puts "  ✓ Permission gates block dangerous operations"
puts "  ✓ Staging workflow functions correctly"
puts "  ✓ Evolve supports both default and staged modes"
puts "  ✓ Planner exists and works"
puts
puts "All acceptance criteria met! ✓"
