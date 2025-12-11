#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for Claude CLI
# Tests basic functionality without requiring API key or SQLite3

require_relative "cli"
require "tempfile"
require "fileutils"

class CLITest
  def initialize
    @passed = 0
    @failed = 0
    @temp_dir = Dir.mktmpdir("claude_test")
  end
  
  def run_all
    puts "=" * 60
    puts "Claude CLI Test Suite"
    puts "=" * 60
    puts
    
    test_config_creation
    test_config_validation
    test_model_validation
    test_temperature_validation
    test_token_validation
    test_url_validation
    test_master_validator
    test_retry_calculation
    test_constants
    
    puts
    puts "=" * 60
    puts "Results: #{@passed} passed, #{@failed} failed"
    puts "=" * 60
    
    FileUtils.rm_rf(@temp_dir)
    
    exit(@failed > 0 ? 1 : 0)
  end
  
  def test(name)
    print "Testing #{name}... "
    begin
      yield
      @passed += 1
      puts "✓"
    rescue => e
      @failed += 1
      puts "✗"
      puts "  Error: #{e.message}"
      puts "  #{e.backtrace.first}"
    end
  end
  
  def test_config_creation
    test("config creation") do
      config_path = File.join(@temp_dir, "config.yml")
      config = Claude::Config.new(config_path)
      
      raise "Config not initialized" unless config
      raise "Default stream should be true" unless config.get("stream") == true
      raise "Default model incorrect" unless config.get("model").start_with?("claude")
    end
  end
  
  def test_config_validation
    test("config validation") do
      config_path = File.join(@temp_dir, "config2.yml")
      config = Claude::Config.new(config_path)
      
      errors = config.validate
      raise "Should have API key error" unless errors.any? { |e| e.include?("API key") }
      
      config.set("api_key", "sk-ant-test123")
      errors = config.validate
      raise "Should have no API key error" if errors.any? { |e| e.include?("API key") }
    end
  end
  
  def test_model_validation
    test("model validation") do
      config_path = File.join(@temp_dir, "config3.yml")
      config = Claude::Config.new(config_path)
      
      # Valid model should not raise
      config.set("model", "claude-3-5-sonnet-20241022")
      
      # Invalid model should warn but not raise
      config.set("model", "invalid-model")
    end
  end
  
  def test_temperature_validation
    test("temperature validation") do
      config_path = File.join(@temp_dir, "config4.yml")
      config = Claude::Config.new(config_path)
      
      # Valid temperatures
      config.set("temperature", 0.0)
      raise "Temp should be 0.0" unless config.get("temperature") == 0.0
      
      config.set("temperature", 1.0)
      raise "Temp should be 1.0" unless config.get("temperature") == 1.0
      
      config.set("temperature", 0.5)
      raise "Temp should be 0.5" unless config.get("temperature") == 0.5
      
      # Invalid temperatures
      begin
        config.set("temperature", -0.1)
        raise "Should reject negative temperature"
      rescue ArgumentError
        # Expected
      end
      
      begin
        config.set("temperature", 1.1)
        raise "Should reject temperature > 1.0"
      rescue ArgumentError
        # Expected
      end
    end
  end
  
  def test_token_validation
    test("token validation") do
      config_path = File.join(@temp_dir, "config5.yml")
      config = Claude::Config.new(config_path)
      
      # Valid tokens
      config.set("max_tokens", 100)
      raise "max_tokens should be 100" unless config.get("max_tokens") == 100
      
      config.set("max_tokens", 200_000)
      raise "max_tokens should be 200000" unless config.get("max_tokens") == 200_000
      
      # Invalid tokens
      begin
        config.set("max_tokens", 0)
        raise "Should reject zero max_tokens"
      rescue ArgumentError
        # Expected
      end
      
      begin
        config.set("max_tokens", -100)
        raise "Should reject negative max_tokens"
      rescue ArgumentError
        # Expected
      end
      
      begin
        config.set("max_tokens", 300_000)
        raise "Should reject max_tokens > 200000"
      rescue ArgumentError
        # Expected
      end
    end
  end
  
  def test_url_validation
    test("URL validation") do
      config_path = File.join(@temp_dir, "config6.yml")
      config = Claude::Config.new(config_path)
      
      # Valid URLs
      config.set("api_base", "https://api.anthropic.com")
      config.set("api_base", "http://localhost:8080")
      
      # Invalid URLs
      begin
        config.set("api_base", "not-a-url")
        raise "Should reject invalid URL"
      rescue ArgumentError
        # Expected
      end
      
      begin
        config.set("api_base", "ftp://example.com")
        raise "Should reject non-HTTP(S) URL"
      rescue ArgumentError
        # Expected
      end
    end
  end
  
  def test_master_validator
    test("master.yml validator") do
      # Create valid master.yml
      master_path = File.join(@temp_dir, "master.yml")
      File.write(master_path, <<~YAML)
        meta:
          version: 37.7.0
        principles:
          critical: test
      YAML
      
      validator = Claude::MasterValidator.new(master_path)
      raise "Should validate" unless validator.validate
      raise "Should have checksum" unless validator.checksum
      raise "Checksum should be hex" unless validator.checksum.match?(/^[0-9a-f]{64}$/)
      
      # Create invalid master.yml
      invalid_path = File.join(@temp_dir, "invalid.yml")
      File.write(invalid_path, <<~YAML)
        meta:
          wrong: field
      YAML
      
      validator2 = Claude::MasterValidator.new(invalid_path)
      raise "Should not validate" if validator2.validate
    end
  end
  
  def test_retry_calculation
    test("retry delay calculation") do
      config_path = File.join(@temp_dir, "config7.yml")
      config = Claude::Config.new(config_path)
      client = Claude::APIClient.new(config)
      
      # Test exponential backoff
      delay0 = client.send(:calculate_retry_delay, 0)
      delay1 = client.send(:calculate_retry_delay, 1)
      delay2 = client.send(:calculate_retry_delay, 2)
      delay3 = client.send(:calculate_retry_delay, 3)
      
      raise "Delay 0 should be 1.0" unless delay0 == 1.0
      raise "Delay 1 should be 2.0" unless delay1 == 2.0
      raise "Delay 2 should be 4.0" unless delay2 == 4.0
      raise "Delay 3 should be 8.0" unless delay3 == 8.0
      
      # Test max delay cap
      delay10 = client.send(:calculate_retry_delay, 10)
      raise "Delay should be capped at MAX_DELAY" unless delay10 == Claude::RETRY_MAX_DELAY
    end
  end
  
  def test_constants
    test("constants defined") do
      raise "VERSION not defined" unless Claude::VERSION
      raise "KNOWN_MODELS not defined" unless Claude::KNOWN_MODELS
      raise "DEFAULT_CONFIG not defined" unless Claude::DEFAULT_CONFIG
      raise "API_TIMEOUT not defined" unless Claude::API_TIMEOUT
      raise "MAX_RETRIES not defined" unless Claude::MAX_RETRIES
      
      raise "KNOWN_MODELS should be array" unless Claude::KNOWN_MODELS.is_a?(Array)
      raise "KNOWN_MODELS should not be empty" unless Claude::KNOWN_MODELS.any?
      
      raise "DEFAULT_CONFIG should have stream=true" unless Claude::DEFAULT_CONFIG["stream"] == true
    end
  end
end

# Run tests
CLITest.new.run_all
