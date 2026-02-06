# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require_relative "../lib/result"
require_relative "../lib/stages/evolve"

class TestEvolve < Minitest::Test
  def setup
    @evolve = MASTER::Stages::Evolve.new
  end

  def test_returns_error_when_no_file_specified
    input = { response: "content" }
    result = @evolve.call(input)
    
    assert result.err?
    assert_match(/No file/, result.error)
  end

  def test_returns_error_when_file_does_not_exist
    input = {
      file: "/nonexistent/file.rb",
      response: "content"
    }
    result = @evolve.call(input)
    
    assert result.err?
    assert_match(/does not exist/, result.error)
  end

  def test_modifies_file_when_tests_pass
    Tempfile.create(["test", ".rb"]) do |file|
      file.write("original content")
      file.flush
      
      input = {
        file: file.path,
        response: "new content",
        test_command: "true"  # Command that always succeeds
      }
      
      result = @evolve.call(input)
      
      assert result.ok?
      assert result.value[:modified]
      assert result.value[:tests_passed]
      refute result.value[:rolled_back]
      
      # File should have new content
      assert_equal "new content", File.read(file.path)
    end
  end

  def test_rolls_back_when_tests_fail
    Tempfile.create(["test", ".rb"]) do |file|
      original = "original content"
      file.write(original)
      file.flush
      
      input = {
        file: file.path,
        response: "new content",
        test_command: "false"  # Command that always fails
      }
      
      result = @evolve.call(input)
      
      # Should still be ok (rolled back successfully)
      assert result.ok?
      assert result.value[:modified]
      refute result.value[:tests_passed]
      assert result.value[:rolled_back]
    end
  end
end
