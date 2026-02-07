# frozen_string_literal: true

require "minitest/autorun"

# Mock MASTER module for testing
module MASTER
  def self.root
    File.expand_path("..", __dir__)
  end
  
  module LLM
    def self.call(context, model:, temperature:, max_tokens:)
      # Mock LLM response for testing
      "Thought: I will search for the answer\nAction: web_search \"test query\""
    end
  end
  
  module Memory
    def self.remember(content, type, tags:)
      # Mock memory storage
    end
    
    def self.search(query, tags:, limit:)
      []
    end
    
    def self.recall(tags:, limit:)
      []
    end
  end
end

require_relative "../lib/core/react_executor"
require_relative "../lib/core/reflection_memory"

module MASTER
  module Core
    class TestReActExecutor < Minitest::Test
      # Test 5: Tool validation
      def test_execute_tool_validates_tool_names
        result = ReActExecutor.execute_tool("invalid_tool_name \"test\"")
        assert_match(/Invalid tool/, result)
        assert_match(/Available tools/, result)
      end

      def test_execute_tool_accepts_valid_tool_names
        result = ReActExecutor.execute_tool("web_search \"test\"")
        refute_match(/Invalid tool/, result)
      end

      # Test 5: Shell command guard
      def test_execute_tool_blocks_dangerous_shell_commands
        result = ReActExecutor.execute_tool("shell_command \"rm -rf /\"")
        assert_match(/Blocked by safety filter/, result)
        
        result = ReActExecutor.execute_tool("shell_command \"DROP TABLE users\"")
        assert_match(/Blocked by safety filter/, result)
      end

      def test_execute_tool_allows_safe_shell_commands
        result = ReActExecutor.execute_tool("shell_command \"echo hello\"")
        refute_match(/Blocked by safety filter/, result)
      end

      # Test 5: File write path validation
      def test_execute_tool_validates_file_write_paths
        # Try writing outside MASTER.root
        result = ReActExecutor.execute_tool("file_write \"/etc/passwd\" \"malicious\"")
        assert_match(/path must be under/, result)
      end

      def test_execute_tool_allows_file_write_under_root
        # This would work if path is under MASTER.root
        # Path validation happens, so we should not see the error
        root_path = File.join(MASTER.root, "test.txt")
        result = ReActExecutor.execute_tool("file_write \"#{root_path}\" \"safe content\"")
        # Should not get path validation error
        refute_match(/path must be under/, result)
        
        # Clean up if file was created
        File.delete(root_path) if File.exist?(root_path)
      end
    end
  end
end
