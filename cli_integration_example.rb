#!/usr/bin/env ruby
# frozen_string_literal: true

# CONVERGENCE CLI - Integration Example
# Shows how to use the new components with existing cli.rb

require_relative "cli_webchat"
require_relative "cli_rag"
require_relative "cli_tools"

# Example 1: Using WebChatClient for free LLM access
def example_webchat
  client = Convergence::WebChatClient.new(initial_provider: :duckduckgo)
  
  # Send a message
  response = client.send_message("What is Ruby?")
  puts "Response: #{response}"
  
  # Take a screenshot
  screenshot_path = client.screenshot
  puts "Screenshot saved to: #{screenshot_path}"
  
  # Switch provider if rate limited
  client.switch_provider(:huggingchat)
  
  client.quit
end

# Example 2: Using RAG Pipeline for document search
def example_rag
  rag = Convergence::RAGPipeline.new
  
  # Ingest documents
  count = rag.ingest("./docs")
  puts "Ingested #{count} chunks"
  
  # Search with semantic similarity (if embeddings available)
  results = rag.search("how to use convergence cli", k: 5)
  puts "Found #{results.size} results"
  
  # Multi-query search with RRF fusion
  results = rag.multi_query_search("cli commands", k: 5)
  
  # Augment query with context
  augmented = rag.augment("what are the available commands?")
  puts "Augmented query: #{augmented[0..200]}..."
  
  puts "RAG Stats: #{rag.stats.inspect}"
end

# Example 3: Using Enhanced Tools with sandboxing
def example_tools
  # Initialize with master config integration
  master_config = defined?(MASTER_CONFIG) ? MASTER_CONFIG : nil
  registry = Convergence::ToolRegistry.new(
    sandbox_path: Dir.pwd,
    auto_tool_execution: false,
    master_config: master_config
  )
  
  # Setup callbacks
  registry.on(:on_tool_call) do |tool_name, params|
    puts "Executing: #{tool_name} with #{params.inspect}"
  end
  
  registry.on(:on_tool_result) do |tool_name, result|
    puts "Result from #{tool_name}: #{result[:error] || "success"}"
  end
  
  # Execute shell command (respects master.yml banned tools)
  result = registry.execute(:shell, command: "ls -la")
  puts "Shell output: #{result[:stdout]}"
  
  # Read a file (sandboxed to current directory)
  result = registry.execute(:read_file, path: "cli.rb", line_numbers: true)
  puts "File content (first 100 chars): #{result[:content][0..100]}"
  
  # Search files for pattern
  result = registry.execute(:search_files, query: "def initialize", path: ".")
  puts "Search results: #{result[:results_count]} files"
  
  # List directory
  result = registry.execute(:list_files, path: ".", recursive: false)
  puts "Files: #{result[:count]} items"
end

# Example 4: Integration with existing cli.rb patterns
def example_cli_integration
  # This would go in cli.rb's CLI class:
  
  # Replace WebChat with enhanced version
  # @client = Convergence::WebChatClient.new(initial_provider: :duckduckgo)
  
  # Replace RAG with production pipeline
  # @rag = Convergence::RAGPipeline.new
  
  # Use enhanced tools
  # @tools = Convergence::ToolRegistry.new(
  #   sandbox_path: Dir.pwd,
  #   master_config: MASTER_CONFIG
  # )
  
  puts "Integration pattern shown in comments"
end

# Mock LLM client for demonstration
class MockLLMClient
  def send(text)
    # Return mock response
    "This is a response to: #{text}"
  end
  
  def send_with_tool_results(results)
    "I executed the tools and here are the results: #{results.inspect}"
  end
end

# Example 5: Assistant with auto tool execution
def example_assistant
  llm = MockLLMClient.new
  
  assistant = Convergence::Assistant.new(
    llm_client: llm,
    auto_tool_execution: true
  )
  
  # Send a message
  response = assistant.send_message("List files in current directory")
  puts "Assistant response: #{response}"
  
  puts "Assistant state: #{assistant.state}"
end

# Run examples
if __FILE__ == $0
  puts "=== WebChat Example ==="
  # example_webchat  # Requires browser
  puts "(Skipped - requires browser)"
  
  puts "\n=== RAG Example ==="
  example_rag if File.directory?("./docs")
  puts "(Skipped - no docs directory)" unless File.directory?("./docs")
  
  puts "\n=== Tools Example ==="
  example_tools
  
  puts "\n=== CLI Integration Example ==="
  example_cli_integration
  
  puts "\n=== Assistant Example ==="
  example_assistant
end
