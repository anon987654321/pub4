# frozen_string_literal: true

module MASTER
  # Conversational interface for natural language commands
  # Maintains context and handles follow-up questions
  class Conversation
    MAX_HISTORY = 10
    PRONOUNS = %w[it that this them these those].freeze

    attr_reader :history, :context

    def initialize
      @history = []
      @context = {
        current_file: nil,
        current_directory: nil,
        last_files: [],
        last_result: nil,
        last_intent: nil
      }
    end

    # Process a natural language command
    # @param input [String] Natural language input
    # @return [Hash] Result with response and action
    def process(input)
      return error_response("Empty input") if input.nil? || input.strip.empty?

      # Parse intent using NLU
      intent = parse_with_context(input)

      # Handle clarification needs
      if intent[:clarification_needed] && intent[:suggested_question]
        return clarification_response(intent[:suggested_question])
      end

      # Resolve pronouns if present
      intent = resolve_pronouns(intent, input)

      # Execute command based on intent
      result = execute_intent(intent)

      # Update history and context
      update_history(input, intent, result)
      update_context(intent, result)

      result
    rescue StandardError => e
      error_response("Conversation error: #{e.message}")
    end

    # Get conversation summary
    # @return [String] Summary of conversation
    def summary
      return "No conversation history" if @history.empty?

      lines = ["Conversation Summary:", ""]
      @history.each_with_index do |entry, idx|
        lines << "#{idx + 1}. User: #{entry[:input]}"
        lines << "   Intent: #{entry[:intent][:intent]} (#{entry[:intent][:confidence]})"
        lines << "   Result: #{entry[:result][:status]}"
        lines << ""
      end

      lines.join("\n")
    end

    # Clear conversation history
    def clear
      @history = []
      @context = {
        current_file: nil,
        current_directory: nil,
        last_files: [],
        last_result: nil,
        last_intent: nil
      }
    end

    # Get last N commands from history
    # @param n [Integer] Number of commands to retrieve
    # @return [Array<Hash>] Recent history entries
    def recent(n = 5)
      @history.last(n)
    end

    private

    # Parse input with conversation context
    # @param input [String] User input
    # @return [Hash] Parsed intent with entities
    def parse_with_context(input)
      nlu_context = {
        previous_command: @history.last&.dig(:input),
        current_file: @context[:current_file],
        current_directory: @context[:current_directory]
      }

      NLU.parse(input, context: nlu_context)
    end

    # Resolve pronouns in input using context
    # @param intent [Hash] Parsed intent
    # @param input [String] Original input
    # @return [Hash] Intent with resolved entities
    def resolve_pronouns(intent, input)
      normalized = input.downcase

      # Check if input contains pronouns
      has_pronoun = PRONOUNS.any? { |p| normalized.include?(p) }
      return intent unless has_pronoun

      # Resolve file references
      if intent[:entities][:files].nil? || intent[:entities][:files].empty?
        if @context[:current_file]
          intent[:entities][:files] = [@context[:current_file]]
        elsif @context[:last_files].any?
          intent[:entities][:files] = @context[:last_files]
        end
      end

      # Resolve directory references
      if intent[:entities][:directories].nil? || intent[:entities][:directories].empty?
        if @context[:current_directory]
          intent[:entities][:directories] = [@context[:current_directory]]
        end
      end

      intent
    end

    # Execute intent and return result
    # @param intent [Hash] Parsed intent with entities
    # @return [Hash] Execution result
    def execute_intent(intent)
      case intent[:intent]
      when :refactor
        execute_refactor(intent)
      when :analyze
        execute_analyze(intent)
      when :explain
        execute_explain(intent)
      when :fix
        execute_fix(intent)
      when :search
        execute_search(intent)
      when :show
        execute_show(intent)
      when :list
        execute_list(intent)
      when :help
        execute_help(intent)
      else
        {
          status: :unknown,
          message: "I don't understand how to handle '#{intent[:intent]}' yet.",
          suggestion: "Try 'refactor <file>', 'analyze <file>', or 'explain <file>'"
        }
      end
    end

    # Execute refactor command
    # @param intent [Hash] Intent with entities
    # @return [Hash] Result
    def execute_refactor(intent)
      files = intent[:entities][:files] || []
      
      if files.empty?
        return {
          status: :error,
          message: "No files specified for refactoring",
          suggestion: "Please specify a file or directory to refactor"
        }
      end

      {
        status: :success,
        message: "Would refactor: #{files.join(', ')}",
        command: :refactor,
        files: files,
        note: "This is a simulated response. Actual refactoring requires MASTER2 CLI integration."
      }
    end

    # Execute analyze command
    # @param intent [Hash] Intent with entities
    # @return [Hash] Result
    def execute_analyze(intent)
      files = intent[:entities][:files] || []
      directories = intent[:entities][:directories] || []
      targets = files + directories

      if targets.empty?
        return {
          status: :error,
          message: "No files or directories specified for analysis",
          suggestion: "Please specify what to analyze"
        }
      end

      {
        status: :success,
        message: "Would analyze: #{targets.join(', ')}",
        command: :analyze,
        targets: targets,
        note: "This is a simulated response. Actual analysis requires MASTER2 CLI integration."
      }
    end

    # Execute explain command
    # @param intent [Hash] Intent with entities
    # @return [Hash] Result
    def execute_explain(intent)
      target = intent[:entities][:target] || intent[:entities][:files]&.first

      if target.nil?
        return {
          status: :error,
          message: "Nothing specified to explain",
          suggestion: "Please specify what you'd like explained"
        }
      end

      {
        status: :success,
        message: "Would explain: #{target}",
        command: :explain,
        target: target,
        note: "This is a simulated response. Actual explanation requires LLM integration."
      }
    end

    # Execute fix command
    # @param intent [Hash] Intent with entities
    # @return [Hash] Result
    def execute_fix(intent)
      files = intent[:entities][:files] || []

      if files.empty?
        return {
          status: :error,
          message: "No files specified for fixing",
          suggestion: "Please specify which file to fix"
        }
      end

      {
        status: :success,
        message: "Would fix issues in: #{files.join(', ')}",
        command: :fix,
        files: files,
        note: "This is a simulated response. Actual fixing requires MASTER2 CLI integration."
      }
    end

    # Execute search command
    # @param intent [Hash] Intent with entities
    # @return [Hash] Result
    def execute_search(intent)
      patterns = intent[:entities][:patterns] || []
      target = intent[:entities][:target]

      if patterns.empty? && target.nil?
        return {
          status: :error,
          message: "No search pattern specified",
          suggestion: "Please specify what to search for"
        }
      end

      search_terms = patterns.any? ? patterns : [target]

      {
        status: :success,
        message: "Would search for: #{search_terms.join(', ')}",
        command: :search,
        patterns: search_terms,
        note: "This is a simulated response. Actual search requires grep/file system integration."
      }
    end

    # Execute show command
    # @param intent [Hash] Intent with entities
    # @return [Hash] Result
    def execute_show(intent)
      files = intent[:entities][:files] || []

      if files.empty?
        return {
          status: :error,
          message: "No files specified to show",
          suggestion: "Please specify what to show"
        }
      end

      {
        status: :success,
        message: "Would show: #{files.join(', ')}",
        command: :show,
        files: files,
        note: "This is a simulated response. Actual display requires file system integration."
      }
    end

    # Execute list command
    # @param intent [Hash] Intent with entities
    # @return [Hash] Result
    def execute_list(intent)
      directories = intent[:entities][:directories] || ["."]

      {
        status: :success,
        message: "Would list files in: #{directories.join(', ')}",
        command: :list,
        directories: directories,
        note: "This is a simulated response. Actual listing requires file system integration."
      }
    end

    # Execute help command
    # @param intent [Hash] Intent with entities
    # @return [Hash] Result
    def execute_help(intent)
      {
        status: :success,
        message: "Available commands",
        commands: [
          "refactor <file> - Refactor code in file",
          "analyze <file/dir> - Analyze code quality",
          "explain <file/code> - Explain what code does",
          "fix <file> - Fix bugs or issues",
          "search <pattern> - Search for code or files",
          "show <file> - Display file contents",
          "list <dir> - List files in directory"
        ]
      }
    end

    # Create error response
    # @param message [String] Error message
    # @return [Hash] Error result
    def error_response(message)
      {
        status: :error,
        message: message
      }
    end

    # Create clarification response
    # @param question [String] Clarifying question
    # @return [Hash] Clarification result
    def clarification_response(question)
      {
        status: :clarification,
        message: question
      }
    end

    # Update conversation history
    # @param input [String] User input
    # @param intent [Hash] Parsed intent
    # @param result [Hash] Execution result
    def update_history(input, intent, result)
      @history << {
        input: input,
        intent: intent,
        result: result,
        timestamp: Time.now
      }

      # Keep only recent history
      @history = @history.last(MAX_HISTORY) if @history.size > MAX_HISTORY
    end

    # Update conversation context
    # @param intent [Hash] Parsed intent
    # @param result [Hash] Execution result
    def update_context(intent, result)
      # Update current file if files were processed
      files = intent[:entities][:files] || []
      if files.any?
        @context[:current_file] = files.first
        @context[:last_files] = files
      end

      # Update current directory if directories were specified
      directories = intent[:entities][:directories] || []
      if directories.any?
        @context[:current_directory] = directories.first
      end

      # Update last result and intent
      @context[:last_result] = result
      @context[:last_intent] = intent[:intent]
    end
  end
end
