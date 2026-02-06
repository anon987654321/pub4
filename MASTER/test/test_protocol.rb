# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../lib/json_protocol'

class TestProtocol < Minitest::Test
  def test_successful_pipe
    input = { text: "hello", value: 42 }
    
    # Simulate stdin/stdout
    $stdin = StringIO.new(JSON.generate(input))
    $stdout = StringIO.new
    
    MASTER::Protocol.pipe do |data|
      assert_equal "hello", data[:text]
      assert_equal 42, data[:value]
      data.merge(result: "processed")
    end
    
    $stdout.rewind
    output = JSON.parse($stdout.read, symbolize_names: true)
    
    assert_equal "hello", output[:text]
    assert_equal 42, output[:value]
    assert_equal "processed", output[:result]
  ensure
    $stdin = STDIN
    $stdout = STDOUT
  end
  
  def test_error_handling
    input = { text: "test" }
    
    $stdin = StringIO.new(JSON.generate(input))
    $stdout = StringIO.new
    
    begin
      MASTER::Protocol.pipe do |data|
        raise StandardError, "Test error"
      end
    rescue SystemExit
      # Expected - protocol exits on error
    end
    
    $stdout.rewind
    output = JSON.parse($stdout.read, symbolize_names: true)
    
    assert output[:error]
    assert_equal "Test error", output[:error]
    assert output[:backtrace]
  ensure
    $stdin = STDIN
    $stdout = STDOUT
  end
end
