# frozen_string_literal: true

require "ruby_llm"

module MASTER
  module LLM
    # A2: RubyLLM::Tool wrappers for ToolDispatch methods
    # These wrap the existing ToolDispatch actions as proper RubyLLM::Tool subclasses
    # The original ToolDispatch module remains as a fallback/legacy interface

    class WebSearchTool < RubyLLM::Tool
      description "Search the web using DuckDuckGo"
      param :query, desc: "Search query string"

      def execute(query:)
        MASTER::ToolDispatch.web_search(query)
      end
    end

    class BrowsePageTool < RubyLLM::Tool
      description "Browse and fetch content from a URL"
      param :url, desc: "URL to browse (http or https)"

      def execute(url:)
        MASTER::ToolDispatch.browse_page(url)
      end
    end

    class FileReadTool < RubyLLM::Tool
      description "Read contents of a file"
      param :path, desc: "Path to the file to read"

      def execute(path:)
        MASTER::ToolDispatch.file_read(path)
      end
    end

    class FileWriteTool < RubyLLM::Tool
      description "Write content to a file"
      param :path, desc: "Path to the file to write"
      param :content, desc: "Content to write to the file"

      def execute(path:, content:)
        MASTER::ToolDispatch.file_write(path, content)
      end
    end

    class AnalyzeCodeTool < RubyLLM::Tool
      description "Analyze code quality and detect issues"
      param :path, desc: "Path to the code file to analyze"

      def execute(path:)
        MASTER::ToolDispatch.analyze_code(path)
      end
    end

    class ShellCommandTool < RubyLLM::Tool
      description "Execute a shell command (with safety checks)"
      param :command, desc: "Shell command to execute"

      def execute(command:)
        MASTER::ToolDispatch.shell_command(command)
      end
    end

    class MemorySearchTool < RubyLLM::Tool
      description "Search through stored memories"
      param :query, desc: "Search query for memories"

      def execute(query:)
        MASTER::ToolDispatch.memory_search(query)
      end
    end

    # Array of all tool classes for easy registration
    TOOL_CLASSES = [
      WebSearchTool,
      BrowsePageTool,
      FileReadTool,
      FileWriteTool,
      AnalyzeCodeTool,
      ShellCommandTool,
      MemorySearchTool,
    ].freeze

    # Append CommandRegistry-generated tools when available
    def self.all_tool_classes
      base = TOOL_CLASSES.dup
      base.concat(CommandRegistry.to_tool_classes) if defined?(CommandRegistry)
      base
    end
  end
end
