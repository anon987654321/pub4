# frozen_string_literal: true

# SelfHealing - Pattern-based automatic fixes for common command errors
module MASTER
  class SelfHealing
    # Known error patterns and their fixes
    FIXES = {
      /pathspec.*did not match/ => ->(m) { ["find . -name \"*\""] },
      /fetch first/ => ->(m) { ["git pull --rebase"] }
    }.freeze
    
    # Attempt to fix a failed command based on error output
    # Returns array of fix commands or false
    def self.fix(cmd, out, code)
      return false if code == 0
      
      FIXES.each do |pattern, fix_fn|
        if out.match(pattern)
          return fix_fn.call(out.match(pattern))
        end
      end
      
      false
    end
  end
end
