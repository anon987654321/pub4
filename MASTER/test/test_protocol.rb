#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/json_protocol'

class TestProtocol < Minitest::Test
  def test_read_valid_json
    input = '{"text":"hello","value":42}'
    $stdin = StringIO.new(input)
    
    result = MASTER::Protocol.read
    
    assert_equal 'hello', result[:text]
    assert_equal 42, result[:value]
  ensure
    $stdin = STDIN
  end
  
  def test_read_empty_input
    $stdin = StringIO.new('')
    
    result = MASTER::Protocol.read
    
    assert_equal({}, result)
  ensure
    $stdin = STDIN
  end
  
  def test_read_invalid_json
    $stdin = StringIO.new('not json')
    
    result = MASTER::Protocol.read
    
    assert result.key?(:error)
    assert_match(/Invalid JSON/, result[:error])
  ensure
    $stdin = STDIN
  end
  
  def test_write_json
    output = StringIO.new
    $stdout = output
    
    MASTER::Protocol.write({ status: 'ok', count: 3 })
    
    result = JSON.parse(output.string, symbolize_names: true)
    assert_equal 'ok', result[:status]
    assert_equal 3, result[:count]
  ensure
    $stdout = STDOUT
  end
  
  def test_validate_keys
    data = { text: 'hello', model: 'gpt-4' }
    
    valid, missing = MASTER::Protocol.validate_keys(data, :text, :model)
    assert valid
    assert_empty missing
    
    valid, missing = MASTER::Protocol.validate_keys(data, :text, :tier, :cost)
    refute valid
    assert_equal [:tier, :cost], missing
  end
end
