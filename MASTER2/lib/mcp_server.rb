# frozen_string_literal: true

require "fast_mcp"

module MASTER
  # McpServer -- exposes MASTER2 tools via the Model Context Protocol.
  # Claude Desktop, VS Code Copilot, and any MCP client can call these directly.
  #
  # stdio transport:  bundle exec ruby bin/mcp_server
  # rack transport:   mounted at /mcp in lib/server.rb
  module McpServer
    SERVER_VERSION = defined?(MASTER::VERSION) ? MASTER::VERSION : "2.0"

    def self.build
      require_relative "master" unless defined?(MASTER::ToolDispatch)
      server = FastMcp::Server.new(name: "MASTER2", version: SERVER_VERSION)
      server.register_tools(*tool_classes)
      server
    end

    def self.start_stdio
      build.start
    end

    def self.rack_app
      build.start_rack({})
    end

    def self.tool_classes
      [
        FileReadMcpTool,
        FileWriteMcpTool,
        ShellCommandMcpTool,
        WebSearchMcpTool,
        BrowsePageMcpTool,
        AnalyzeCodeMcpTool,
        FixCodeMcpTool,
        AskLlmMcpTool,
        CouncilReviewMcpTool,
        MemorySearchMcpTool,
        SelfTestMcpTool,
      ]
    end

    # ---- Tool definitions ----

    class FileReadMcpTool < FastMcp::Tool
      description "Read a file from the working directory"
      arguments do
        required(:path).filled(:string).description("Path to the file")
      end
      def call(path:)
        MASTER::ToolDispatch.file_read(path)
      end
    end

    class FileWriteMcpTool < FastMcp::Tool
      description "Write content to a file"
      arguments do
        required(:path).filled(:string).description("Destination file path")
        required(:content).filled(:string).description("Content to write")
      end
      def call(path:, content:)
        MASTER::ToolDispatch.file_write(path, content)
      end
    end

    class ShellCommandMcpTool < FastMcp::Tool
      description "Execute a sandboxed shell command"
      arguments do
        required(:command).filled(:string).description("Shell command to run")
      end
      def call(command:)
        MASTER::ToolDispatch.shell_command(command)
      end
    end

    class WebSearchMcpTool < FastMcp::Tool
      description "Search the web via DuckDuckGo"
      arguments do
        required(:query).filled(:string).description("Search query")
      end
      def call(query:)
        MASTER::ToolDispatch.web_search(query)
      end
    end

    class BrowsePageMcpTool < FastMcp::Tool
      description "Fetch and extract text from a URL"
      arguments do
        required(:url).filled(:string).description("URL to browse (http/https)")
      end
      def call(url:)
        MASTER::ToolDispatch.browse_page(url)
      end
    end

    class AnalyzeCodeMcpTool < FastMcp::Tool
      description "Constitutional code review: detect axiom violations"
      arguments do
        required(:path).filled(:string).description("Path to the Ruby file to analyze")
      end
      def call(path:)
        MASTER::ToolDispatch.analyze_code(path)
      end
    end

    class FixCodeMcpTool < FastMcp::Tool
      description "Auto-fix constitutional violations in a file"
      arguments do
        required(:path).filled(:string).description("Path to the Ruby file to fix")
      end
      def call(path:)
        MASTER::ToolDispatch.fix_code(path)
      end
    end

    class AskLlmMcpTool < FastMcp::Tool
      description "Delegate a sub-question to the fast LLM tier"
      arguments do
        required(:prompt).filled(:string).description("Question or task for the LLM")
      end
      def call(prompt:)
        MASTER::ToolDispatch.ask_llm(prompt)
      end
    end

    class CouncilReviewMcpTool < FastMcp::Tool
      description "Multi-model council deliberation on a topic"
      arguments do
        required(:topic).filled(:string).description("Topic or proposal to deliberate")
      end
      def call(topic:)
        MASTER::ToolDispatch.council_review(topic)
      end
    end

    class MemorySearchMcpTool < FastMcp::Tool
      description "Search session history and learnings"
      arguments do
        required(:query).filled(:string).description("Search query")
      end
      def call(query:)
        MASTER::ToolDispatch.memory_search(query)
      end
    end

    class SelfTestMcpTool < FastMcp::Tool
      description "Run MASTER2 constitutional self-test"
      # no arguments needed
      def call
        MASTER::ToolDispatch.self_test
      end
    end
  end
end
