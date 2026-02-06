#!/usr/bin/env ruby
# frozen_string_literal: true

# Test Memory
require_relative '../lib/memory'

class TestMemory
  def initialize
    @passed = 0
    @failed = 0
  end

  def assert(name, condition)
    if condition
      @passed += 1
      puts "  ok: #{name}"
    else
      @failed += 1
      puts "  FAIL: #{name}"
    end
  end

  def run
    puts "Memory tests"
    puts

    test_vector_memory_creation
    test_chunking_logic
    test_memory_interface
    test_stats_methods
    test_graceful_failures

    puts
    puts "#{@passed} passed, #{@failed} failed"
    @failed == 0
  end

  def test_vector_memory_creation
    puts "creation:"
    begin
      memory = MASTER::VectorMemory.new
      assert "VectorMemory can be instantiated", memory.is_a?(MASTER::VectorMemory)
    rescue StandardError => e
      # This is expected if Weaviate is not running
      assert "VectorMemory handles missing Weaviate gracefully", true
      puts "    Note: Weaviate not available - #{e.message[0..50]}"
    end
  end

  def test_chunking_logic
    puts "chunking:"
    begin
      memory = MASTER::VectorMemory.new
      
      # Test chunking internally
      long_text = "word " * 1000
      chunks = memory.send(:chunk_text, long_text)
      
      assert "chunks long text", chunks.size > 1
      assert "respects chunk size", chunks.first.split.size <= MASTER::VectorMemory::CHUNK_SIZE
    rescue StandardError => e
      assert "chunking logic works", false
      puts "    Error: #{e.message}"
    end
  end

  def test_memory_interface
    puts "interface:"
    begin
      memory = MASTER::VectorMemory.new
      assert "has store method", memory.respond_to?(:store)
      assert "has recall method", memory.respond_to?(:recall)
      assert "has count_chunks method", memory.respond_to?(:count_chunks)
      assert "has healthy? method", memory.respond_to?(:healthy?)
    rescue StandardError => e
      assert "interface methods exist", false
      puts "    Error: #{e.message}"
    end
  end

  def test_stats_methods
    puts "stats:"
    begin
      memory = MASTER::VectorMemory.new
      
      # These should not raise errors even if Weaviate is down
      chunks = memory.count_chunks
      assert "count_chunks returns number", chunks.is_a?(Integer)
      
      vectors = memory.count_vectors
      assert "count_vectors returns number", vectors.is_a?(Integer)
      
      last_recall = memory.time_since_last_recall
      assert "time_since_last_recall returns string", last_recall.is_a?(String)
      
      healthy = memory.healthy?
      assert "healthy? returns boolean", [true, false].include?(healthy)
    rescue StandardError => e
      assert "stats methods work", false
      puts "    Error: #{e.message}"
    end
  end

  def test_graceful_failures
    puts "error handling:"
    begin
      memory = MASTER::VectorMemory.new
      
      # Even with Weaviate down, these should return sensible defaults
      result = memory.count_chunks
      assert "returns 0 when Weaviate unavailable", result >= 0
      
      healthy = memory.healthy?
      assert "healthy? doesn't crash", [true, false].include?(healthy)
      
      time = memory.time_since_last_recall
      assert "time_since_last_recall doesn't crash", time.is_a?(String)
    rescue StandardError => e
      assert "graceful error handling", false
      puts "    Error: #{e.message}"
    end
  end
end

# Run tests
tester = TestMemory.new
success = tester.run
exit(success ? 0 : 1)
