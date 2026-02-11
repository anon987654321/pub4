# frozen_string_literal: true

module MASTER
  # ErrorSuggestions - NN/g: Help users recognize, diagnose, and recover from errors
  module ErrorSuggestions
    extend self

    SUGGESTIONS = {
      # API errors
      /401|unauthorized/i => [
        "Check your OPENROUTER_API_KEY in .env",
        "Verify the API key hasn't expired",
        "Run: echo $OPENROUTER_API_KEY to verify it's set"
      ],
      /429|rate.?limit/i => [
        "Wait a few minutes and retry",
        "Try a cheaper model tier",
        "Check your API quota at openrouter.ai"
      ],
      /timeout|timed?.?out/i => [
        "Check your internet connection",
        "The API might be slow - try again",
        "Try a faster model tier"
      ],
      /connection.?refused/i => [
        "Check if the service is running",
        "Verify the host and port are correct",
        "Check firewall settings"
      ],

      # File errors
      /file.?not.?found|no.?such.?file/i => [
        "Check the file path is correct",
        "Use tab completion to verify the path",
        "Run: ls to see available files"
      ],
      /permission.?denied/i => [
        "Check file permissions",
        "You may need sudo/admin access",
        "Verify you own the file"
      ],

      # Ruby errors
      /undefined.?method/i => [
        "The method doesn't exist on this object",
        "Check for typos in the method name",
        "Verify the object type is what you expect"
      ],
      /undefined.?local.?variable/i => [
        "The variable hasn't been defined yet",
        "Check for typos in the variable name",
        "Verify scope - is it defined in this block?"
      ],
      /syntax.?error/i => [
        "Check for missing 'end' keywords",
        "Look for unclosed strings or brackets",
        "Verify method definitions are complete"
      ],

      # MASTER specific
      /budget.?exceeded|insufficient.?budget/i => [
        "Your session budget is exhausted",
        "Start a new session for fresh budget",
        "Use cheaper model tier"
      ],
      /circuit.?open|circuit.?tripped/i => [
        "That model has too many failures",
        "Wait for circuit cooldown (5 min)",
        "Try a different model"
      ],
      /dangerous.?command|blocked/i => [
        "This command was blocked for safety",
        "Rephrase without destructive operations",
        "Use --force if you're sure (not recommended)"
      ]
    }.freeze

    def suggest(error_message)
      return [] unless error_message

      SUGGESTIONS.each do |pattern, suggestions|
        return suggestions if error_message.match?(pattern)
      end

      # Generic fallback
      ["Check the error message for details", "Try 'help' for available commands"]
    end

    def format_error(error, context: nil)
      suggestions = suggest(error.to_s)

      lines = ["Error: #{error}"]
      lines << "Context: #{context}" if context

      if suggestions.any?
        lines << ""
        lines << "Suggestions:"
        suggestions.each { |s| lines << "  • #{s}" }
      end

      lines.join("\n")
    end

    def wrap(result)
      return result if result.ok?

      suggestions = suggest(result.error.to_s)
      enhanced_error = {
        message: result.error,
        suggestions: suggestions
      }

      Result.err(enhanced_error)
    end
  end
end
