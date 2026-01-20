#!/usr/bin/env ruby
# frozen_string_literal: true

# CONVERGENCE CLI - Tools Component
# Enhanced Tool Execution System with sandboxing and callbacks

require "open3"
require "timeout"
require "fileutils"
require "digest"
require "set"

module Convergence
  # SandboxedFileTool mixin for secure file operations
  module SandboxedFileTool
    def initialize(base_path:, **options)
      @base_path = File.expand_path(base_path)
      @base_path.freeze
      super(**options) if defined?(super)
    end

    def enforce_sandbox!(filepath)
      expanded = File.expand_path(filepath)
      unless expanded.start_with?(@base_path)
        raise SecurityError, "Access denied: #{filepath} outside sandbox #{@base_path}"
      end
      expanded
    end
  end

  # Tool Registry with state machine and auto-execution
  class ToolRegistry
    STATES = %i[ready in_progress requires_action completed failed].freeze

    attr_reader :state, :tools, :pending_calls, :callbacks

    def initialize(sandbox_path: Dir.pwd, auto_tool_execution: false, master_config: nil)
      @state = :ready
      @sandbox_path = File.expand_path(sandbox_path)
      @auto_tool_execution = auto_tool_execution
      @master_config = master_config
      @tools = {}
      @pending_calls = []
      @callbacks = {}
      @execution_history = []
      
      register_default_tools
    end

    def register_tool(name, tool)
      @tools[name.to_sym] = tool
    end

    def on(event, &block)
      @callbacks[event] = block
    end

    def execute(tool_name, **params)
      tool = @tools[tool_name.to_sym]
      raise "Unknown tool: #{tool_name}" unless tool

      @state = :in_progress
      
      trigger_callback(:on_tool_call, tool_name, params)
      
      result = tool.execute(**params)
      
      trigger_callback(:on_tool_result, tool_name, result)
      
      @execution_history << {
        tool: tool_name,
        params: params,
        result: result,
        timestamp: Time.now.to_i
      }
      
      @state = result[:error] ? :failed : :completed
      result
    rescue => e
      @state = :failed
      error_result = { error: e.message, backtrace: e.backtrace.first(3) }
      trigger_callback(:on_tool_result, tool_name, error_result)
      error_result
    end

    def queue_tool_call(tool_name, **params)
      @pending_calls << { tool: tool_name, params: params }
      @state = :requires_action
    end

    def execute_pending
      return [] if @pending_calls.empty?
      
      results = @pending_calls.map do |call|
        execute(call[:tool], **call[:params])
      end
      
      @pending_calls.clear
      @state = :completed
      results
    end

    def clear_pending
      @pending_calls.clear
      @state = :ready
    end

    def auto_execute?
      @auto_tool_execution
    end

    private

    def register_default_tools
      register_tool(:shell, EnhancedShellTool.new(master_config: @master_config))
      register_tool(:read_file, ReadFileTool.new(base_path: @sandbox_path))
      register_tool(:write_file, WriteFileTool.new(base_path: @sandbox_path))
      register_tool(:list_files, ListFilesTool.new(base_path: @sandbox_path))
      register_tool(:search_files, SearchFilesTool.new(base_path: @sandbox_path))
    end

    def trigger_callback(event, *args)
      @callbacks[event]&.call(*args)
    end
  end

  # Enhanced Shell Tool with dangerous pattern blocking
  class EnhancedShellTool
    DANGEROUS_PATTERNS = [
      "rm -rf /",
      "rm -rf /*",
      "rm -rf ~",
      "rm -rf $HOME",
      "> /etc/passwd",
      "> /etc/shadow",
      "> /etc/sudoers",
      "| sh",
      "| bash",
      "curl | sh",
      "wget | sh"
    ].freeze

    def initialize(master_config: nil)
      @master_config = master_config
    end

    def execute(command:, timeout: 30)
      # Check master config banned tools
      if @master_config && @master_config.respond_to?(:banned?)
        if @master_config.banned?(command)
          banned_tool = @master_config.banned_tool(command)
          return {
            error: "blocked: #{banned_tool}",
            alternative: @master_config.suggest_alternative(banned_tool)
          }
        end

        if @master_config.respond_to?(:dangerous?) && @master_config.dangerous?(command)
          return { error: "blocked: dangerous pattern detected" }
        end
      end

      # Check built-in dangerous patterns
      if DANGEROUS_PATTERNS.any? { |p| command.include?(p) }
        return { error: "blocked: dangerous pattern detected" }
      end

      shell_path = find_shell
      return { error: "no shell found" } unless shell_path && File.executable?(shell_path)
      
      begin
        Timeout.timeout(timeout) do
          stdout, stderr, status = Open3.capture3(shell_path, "-c", command)
          
          {
            stdout: stdout[0..4000],
            stderr: stderr[0..1000],
            exit_code: status.exitstatus,
            success: status.success?
          }
        end
      rescue Timeout::Error
        { error: "command timeout after #{timeout}s" }
      rescue => e
        { error: e.message }
      end
    end

    private

    def find_shell
      ["/usr/local/bin/zsh", "/bin/zsh", "/bin/sh"].find { |s| File.executable?(s) } || "/bin/sh"
    end
  end

  # Sandboxed Read File Tool
  class ReadFileTool
    include SandboxedFileTool

    def initialize(base_path:)
      @base_path = File.expand_path(base_path)
      @base_path.freeze
    end

    def execute(path:, line_numbers: false, start_line: nil, end_line: nil)
      safe_path = enforce_sandbox!(path)
      
      return { error: "file not found" } unless File.exist?(safe_path)
      return { error: "not a file" } unless File.file?(safe_path)
      
      content = File.read(safe_path)
      lines = content.lines
      
      # Apply line range if specified
      if start_line || end_line
        start_line ||= 1
        end_line ||= lines.size
        lines = lines[(start_line - 1)...end_line]
      end
      
      # Add line numbers if requested
      if line_numbers
        start_num = start_line || 1
        content = lines.map.with_index do |line, idx|
          "#{start_num + idx}. #{line}"
        end.join
      else
        content = lines.join
      end
      
      {
        content: content[0..50000],  # Limit to avoid memory issues
        size: File.size(safe_path),
        lines: lines.size,
        path: path
      }
    rescue SecurityError => e
      { error: e.message }
    rescue => e
      { error: "failed to read file: #{e.message}" }
    end
  end

  # Sandboxed Write File Tool
  class WriteFileTool
    include SandboxedFileTool

    def initialize(base_path:)
      @base_path = File.expand_path(base_path)
      @base_path.freeze
    end

    def execute(path:, content:, append: false)
      safe_path = enforce_sandbox!(path)
      
      # Create parent directories if needed
      FileUtils.mkdir_p(File.dirname(safe_path))
      
      if append
        File.open(safe_path, "a") { |f| f.write(content) }
      else
        File.write(safe_path, content)
      end
      
      {
        success: true,
        path: path,
        size: File.size(safe_path)
      }
    rescue SecurityError => e
      { error: e.message }
    rescue => e
      { error: "failed to write file: #{e.message}" }
    end
  end

  # Sandboxed List Files Tool
  class ListFilesTool
    include SandboxedFileTool

    def initialize(base_path:)
      @base_path = File.expand_path(base_path)
      @base_path.freeze
    end

    def execute(path: ".", recursive: false, pattern: nil)
      safe_path = enforce_sandbox!(File.join(@base_path, path))
      
      return { error: "directory not found" } unless File.exist?(safe_path)
      return { error: "not a directory" } unless File.directory?(safe_path)
      
      if recursive
        glob_pattern = pattern || "**/*"
        entries = Dir.glob(File.join(safe_path, glob_pattern))
          .reject { |e| File.basename(e).start_with?(".") }
      else
        entries = Dir.entries(safe_path)
          .reject { |e| e.start_with?(".") }
          .map { |e| File.join(safe_path, e) }
      end
      
      files = entries.map do |entry|
        relative = entry.sub("#{@base_path}/", "")
        {
          name: relative,
          type: File.directory?(entry) ? "directory" : "file",
          size: File.file?(entry) ? File.size(entry) : nil
        }
      end
      
      {
        path: path,
        count: files.size,
        files: files.sort_by { |f| [f[:type] == "directory" ? 0 : 1, f[:name]] }
      }
    rescue SecurityError => e
      { error: e.message }
    rescue => e
      { error: "failed to list directory: #{e.message}" }
    end
  end

  # Sandboxed Search Files Tool
  class SearchFilesTool
    include SandboxedFileTool

    def initialize(base_path:)
      @base_path = File.expand_path(base_path)
      @base_path.freeze
    end

    def execute(query:, path: ".", file_pattern: nil, case_sensitive: false)
      safe_path = enforce_sandbox!(File.join(@base_path, path))
      
      return { error: "directory not found" } unless File.exist?(safe_path)
      
      # Find files to search
      glob = file_pattern || "**/*"
      files = Dir.glob(File.join(safe_path, glob))
        .select { |f| File.file?(f) }
        .reject { |f| File.basename(f).start_with?(".") }
      
      # Search through files
      results = []
      
      # Use simple string search for better performance
      search_method = case_sensitive ? :include? : lambda { |text, q| text.downcase.include?(q.downcase) }
      
      files.each do |file|
        begin
          content = File.read(file)
          matches = []
          
          content.lines.each_with_index do |line, idx|
            if case_sensitive ? line.include?(query) : line.downcase.include?(query.downcase)
              matches << {
                line_number: idx + 1,
                line: line.strip[0..200]  # Truncate long lines
              }
            end
          end
          
          if matches.any?
            relative = file.sub("#{@base_path}/", "")
            results << {
              file: relative,
              matches: matches.first(10)  # Limit matches per file
            }
          end
        rescue => e
          # Skip files that can't be read
          next
        end
        
        break if results.size >= 50  # Limit total results
      end
      
      {
        query: query,
        path: path,
        results_count: results.size,
        results: results
      }
    rescue SecurityError => e
      { error: e.message }
    rescue => e
      { error: "search failed: #{e.message}" }
    end
  end

  # Assistant with state machine (langchainrb pattern)
  class Assistant
    STATES = %i[ready in_progress requires_action completed failed].freeze

    attr_reader :state, :tool_registry, :messages

    def initialize(llm_client:, tools: nil, auto_tool_execution: false)
      @llm_client = llm_client
      @state = :ready
      @messages = []
      @auto_tool_execution = auto_tool_execution
      @tool_registry = tools || ToolRegistry.new(auto_tool_execution: auto_tool_execution)
      
      setup_callbacks
    end

    def send_message(text)
      @state = :in_progress
      @messages << { role: "user", content: text }
      
      response = @llm_client.send(text)
      
      # Check if response includes tool calls
      if response.is_a?(Hash) && response[:tool_calls]
        @state = :requires_action
        
        if @auto_tool_execution
          process_tool_calls(response[:tool_calls])
        else
          { status: :requires_action, tool_calls: response[:tool_calls] }
        end
      else
        @state = :completed
        @messages << { role: "assistant", content: response }
        response
      end
    rescue => e
      @state = :failed
      { error: e.message }
    end

    def approve_tools
      return { error: "no pending tools" } unless @state == :requires_action
      
      results = @tool_registry.execute_pending
      submit_tool_results(results)
    end

    def reject_tools
      @tool_registry.clear_pending
      @state = :ready
      { status: :rejected }
    end

    private

    def setup_callbacks
      @tool_registry.on(:on_tool_call) do |tool_name, params|
        trigger_callback(:on_new_message, "Executing tool: #{tool_name}")
      end
      
      @tool_registry.on(:on_tool_result) do |tool_name, result|
        trigger_callback(:on_end_message, "Tool #{tool_name} completed")
      end
    end

    def process_tool_calls(tool_calls)
      tool_calls.each do |call|
        @tool_registry.queue_tool_call(call[:name], **call[:params])
      end
      
      results = @tool_registry.execute_pending
      submit_tool_results(results)
    end

    def submit_tool_results(results)
      @messages << { role: "tool_results", content: results }
      
      # Get final response from LLM
      response = @llm_client.send_with_tool_results(results)
      @state = :completed
      @messages << { role: "assistant", content: response }
      
      response
    end

    def trigger_callback(event, *args)
      @tool_registry.callbacks[event]&.call(*args)
    end
  end
end
