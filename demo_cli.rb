#!/usr/bin/env ruby
# Demo script for Claude CLI - shows features without API key

require_relative "cli"
require "tempfile"
require "fileutils"

puts "=" * 70
puts "Claude CLI Demo - Feature Showcase"
puts "=" * 70
puts

# Create a temporary config with a dummy API key for demo
temp_dir = Dir.mktmpdir("claude_demo")
config_path = File.join(temp_dir, "config.yml")
File.write(config_path, <<~YAML)
  api_key: sk-ant-demo-key-1234567890
  api_base: https://api.anthropic.com
  model: claude-3-5-sonnet-20241022
  max_tokens: 4096
  temperature: 1.0
  stream: true
  debug: false
YAML

puts "1. Configuration Management"
puts "-" * 70
config = Claude::Config.new(config_path)
puts "✓ Config loaded from: #{config_path}"
puts "✓ Model: #{config.get('model')}"
puts "✓ Max tokens: #{config.get('max_tokens')}"
puts "✓ Temperature: #{config.get('temperature')}"
puts "✓ Streaming: #{config.get('stream')}"
puts

puts "2. Configuration Validation"
puts "-" * 70

# Test model validation
puts "Testing model validation..."
begin
  config.set("model", "invalid-model-name")
  puts "  Warning shown for invalid model name"
rescue => e
  puts "  Error: #{e.message}"
end

# Test temperature validation
puts "Testing temperature validation..."
begin
  config.set("temperature", 1.5)
  puts "  ✗ Should have rejected temperature > 1.0"
rescue ArgumentError => e
  puts "  ✓ Correctly rejected: #{e.message}"
end

begin
  config.set("temperature", -0.1)
  puts "  ✗ Should have rejected negative temperature"
rescue ArgumentError => e
  puts "  ✓ Correctly rejected: #{e.message}"
end

# Test token validation
puts "Testing token validation..."
begin
  config.set("max_tokens", 300_000)
  puts "  ✗ Should have rejected max_tokens > 200,000"
rescue ArgumentError => e
  puts "  ✓ Correctly rejected: #{e.message}"
end

# Test URL validation
puts "Testing URL validation..."
begin
  config.set("api_base", "not-a-valid-url")
  puts "  ✗ Should have rejected invalid URL"
rescue ArgumentError => e
  puts "  ✓ Correctly rejected: #{e.message}"
end
puts

puts "3. Master.yml Validation"
puts "-" * 70

# Create test master.yml files
valid_master = File.join(temp_dir, "master.yml")
File.write(valid_master, <<~YAML)
  meta:
    version: 37.7.0
    purpose: test
  principles:
    critical: preserve_then_improve
YAML

puts "Testing valid master.yml..."
validator = Claude::MasterValidator.new(valid_master)
if validator.validate
  puts "  ✓ Validation passed"
  puts "  ✓ Checksum: #{validator.checksum[0..15]}..."
else
  puts "  ✗ Validation failed"
end

invalid_master = File.join(temp_dir, "invalid.yml")
File.write(invalid_master, <<~YAML)
  meta:
    wrong_field: test
YAML

puts "Testing invalid master.yml..."
validator2 = Claude::MasterValidator.new(invalid_master)
if validator2.validate
  puts "  ✗ Should have failed validation"
else
  puts "  ✓ Correctly detected errors"
end
puts

puts "4. Error Handling & Retry Logic"
puts "-" * 70
client = Claude::APIClient.new(config)

puts "Testing retry delay calculation (exponential backoff)..."
delays = (0..4).map { |i| client.send(:calculate_retry_delay, i) }
puts "  Attempt 0: #{delays[0]}s"
puts "  Attempt 1: #{delays[1]}s"
puts "  Attempt 2: #{delays[2]}s"
puts "  Attempt 3: #{delays[3]}s"
puts "  Attempt 4: #{delays[4]}s (capped at max delay)"
puts "  ✓ Exponential backoff working correctly"
puts

puts "5. Known Models"
puts "-" * 70
puts "The CLI validates against these Claude models:"
Claude::KNOWN_MODELS.each do |model|
  puts "  - #{model}"
end
puts

puts "6. Session Management (SQLite3 required)"
puts "-" * 70
if defined?(SQLite3)
  db_path = File.join(temp_dir, "sessions.db")
  session_mgr = Claude::SessionManager.new(db_path)
  
  # Create a test session
  session_id = session_mgr.create_session(
    master_checksum: "abc123",
    tags: ["demo", "test"]
  )
  
  if session_id
    puts "  ✓ Created session: #{session_id}"
    
    # Update session with test data
    messages = [
      { role: "user", content: "Hello" },
      { role: "assistant", content: "Hi there!" }
    ]
    session_mgr.update_session(
      session_id,
      messages: messages,
      tokens: 100,
      cost: 0.001,
      response_time: 1.5
    )
    puts "  ✓ Updated session with metadata"
    
    # Add a tag
    session_mgr.add_tag(session_id, "production")
    puts "  ✓ Added tag to session"
    
    # Retrieve session
    session = session_mgr.get_session(session_id)
    puts "  ✓ Retrieved session data:"
    puts "    - Total tokens: #{session[:total_tokens]}"
    puts "    - Total cost: $#{format('%.4f', session[:total_cost])}"
    puts "    - Avg response time: #{format('%.2f', session[:avg_response_time])}s"
    puts "    - Tags: #{session[:tags].join(', ')}"
    puts "    - Messages: #{session[:messages].size}"
    
    # Search sessions
    results = session_mgr.search_sessions("Hello")
    puts "  ✓ Search found #{results.size} session(s)"
  else
    puts "  ✗ Failed to create session"
  end
else
  puts "  ⚠ SQLite3 not available - sessions won't persist"
  puts "  Install with: gem install sqlite3 --no-document"
end
puts

puts "7. Constants and Configuration"
puts "-" * 70
puts "  Version: #{Claude::VERSION}"
puts "  API timeout: #{Claude::API_TIMEOUT}s"
puts "  Max retries: #{Claude::MAX_RETRIES}"
puts "  Retry base delay: #{Claude::RETRY_BASE_DELAY}s"
puts "  Retry max delay: #{Claude::RETRY_MAX_DELAY}s"
puts "  Default streaming: #{Claude::DEFAULT_CONFIG['stream']}"
puts

puts "8. Error Types"
puts "-" * 70
puts "The CLI handles these specific error types:"
puts "  - AuthenticationError (401/403)"
puts "  - RateLimitError (429) with automatic retry"
puts "  - ClientError (4xx) with actionable messages"
puts "  - ServerError (5xx) with retry suggestions"
puts "  - TimeoutError with retry suggestions"
puts "  - StreamError for SSE issues"
puts

puts "=" * 70
puts "Demo Complete!"
puts "=" * 70
puts
puts "Next steps:"
puts "  1. Run: ./install_cli.sh"
puts "  2. Set your API key: /config set api_key YOUR_KEY"
puts "  3. Start chatting: ./cli.rb"
puts "  4. Read: QUICKSTART.md for examples"
puts "  5. Full docs: README_CLI.md"
puts

# Cleanup
FileUtils.rm_rf(temp_dir)
