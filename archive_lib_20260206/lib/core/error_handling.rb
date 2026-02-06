module MASTER
  module ErrorHandling
    def self.validate_input(value, rules = {})
      errors = []
      errors << "Required field" if rules[:required] && value.to_s.empty?
      errors << "Too short" if rules[:min_length] && value.length < rules[:min_length]
      errors
    end
    
    def self.error_message(field, errors, solutions = [])
      msg = "✗ #{field}: #{errors.join(', ')}"
      if solutions.any?
        suggestions = solutions.map { |s| "  • #{s}" }.join("\n")
        msg += "\nSuggestions:\n#{suggestions}"
      end
      msg
    end
    
    def self.confirm_destructive(action)
      "⚠ This will #{action}. Type 'yes' to confirm: "
    end
    
    def self.undo_available(action)
      "↶ Undo #{action} (Ctrl+Z)"
    end
  end
end
