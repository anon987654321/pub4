#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'json'

class TestPipeline < Minitest::Test
  def setup
    @master_root = File.expand_path('..', __dir__)
  end
  
  def test_intake_passthrough
    input = '{"text":"Hello world"}'
    output, status = Open3.capture2("ruby #{@master_root}/bin/intake", stdin_data: input)
    
    assert status.success?
    result = JSON.parse(output, symbolize_names: true)
    assert_equal 'Hello world', result[:text]
    assert result.key?(:density)
    assert result.key?(:persona)
  end
  
  def test_intake_compression
    input = '{"text":"I would like to say that in order to make this work"}'
    output, status = Open3.capture2("ruby #{@master_root}/bin/intake", stdin_data: input)
    
    assert status.success?
    result = JSON.parse(output, symbolize_names: true)
    # Should compress "in order to" → "to"
    assert result[:compressed]
    refute_equal input, result[:text]
  end
  
  def test_guard_allows_safe_input
    input = '{"text":"Write a function"}'
    output, status = Open3.capture2("ruby #{@master_root}/bin/guard", stdin_data: input)
    
    assert status.success?
    result = JSON.parse(output, symbolize_names: true)
    assert result[:allowed]
    assert_empty result[:violations]
  end
  
  def test_route_selects_model
    input = '{"text":"Simple question"}'
    output, status = Open3.capture2("ruby #{@master_root}/bin/route", stdin_data: input)
    
    assert status.success?
    result = JSON.parse(output, symbolize_names: true)
    assert result.key?(:model)
    assert result.key?(:tier)
    assert result.key?(:budget_remaining)
  end
  
  def test_remember_store_and_recall
    # Store a memory
    input = '{"action":"store","content":"Pipeline test memory","context":"test"}'
    output, status = Open3.capture2("ruby #{@master_root}/bin/remember", stdin_data: input)
    
    assert status.success?
    result = JSON.parse(output, symbolize_names: true)
    assert result[:stored]
    
    # Recall the memory
    input = '{"action":"recall","context":"test","limit":5}'
    output, status = Open3.capture2("ruby #{@master_root}/bin/remember", stdin_data: input)
    
    assert status.success?
    result = JSON.parse(output, symbolize_names: true)
    assert result[:recalled].any? { |m| m[:content] == 'Pipeline test memory' }
  end
  
  def test_full_pipeline_chain
    # Test intake → guard → route
    input = '{"text":"What is 2+2?"}'
    
    cmd = [
      "ruby #{@master_root}/bin/intake",
      "ruby #{@master_root}/bin/guard",
      "ruby #{@master_root}/bin/route"
    ].join(' | ')
    
    output, status = Open3.capture2(cmd, stdin_data: input)
    
    assert status.success?
    result = JSON.parse(output, symbolize_names: true)
    
    # Should have all accumulated fields
    assert result.key?(:text)
    assert result.key?(:density)
    assert result.key?(:allowed)
    assert result.key?(:model)
    assert result.key?(:tier)
  end
end
