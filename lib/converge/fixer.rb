#!/usr/bin/env ruby
# frozen_string_literal: true

# Auto-fixer for convergence violations
# Attempts to automatically fix common violations

require 'json'
require 'fileutils'

module Converge
  class Fixer
    def initialize(violations, dry_run: false)
      @violations = violations
      @dry_run = dry_run
      @fixes_applied = []
    end

    def fix_all
      @violations.each do |violation|
        fix_violation(violation)
      end
      
      {
        total_violations: @violations.size,
        fixes_applied: @fixes_applied.size,
        fixes: @fixes_applied
      }
    end

    def to_json
      JSON.pretty_generate(fix_all)
    end

    private

    def fix_violation(violation)
      case violation[:type]
      when 'small_functions'
        # For now, just log - actual refactoring is complex
        log_fix(violation, 'MANUAL', 'Function extraction requires manual refactoring')
      when 'file_size_lines'
        log_fix(violation, 'MANUAL', 'File splitting requires manual refactoring')
      when 'banned_tool'
        attempt_tool_replacement(violation)
      when 'meaningful_names'
        log_fix(violation, 'MANUAL', 'Variable renaming requires context understanding')
      when 'duplication_trigger'
        log_fix(violation, 'MANUAL', 'Duplication extraction requires analysis')
      when 'max_complexity'
        log_fix(violation, 'MANUAL', 'Complexity reduction requires refactoring')
      when 'banned_shell'
        attempt_shebang_fix(violation)
      else
        log_fix(violation, 'SKIP', 'Unknown violation type')
      end
    end

    def attempt_shebang_fix(violation)
      file = violation[:file]
      return unless File.exist?(file)
      
      content = File.read(file)
      lines = content.lines
      
      if lines.first =~ /^#!.*bash/
        if @dry_run
          log_fix(violation, 'DRY_RUN', 'Would replace bash shebang with zsh')
        else
          lines[0] = "#!/usr/bin/env zsh\n"
          File.write(file, lines.join)
          log_fix(violation, 'FIXED', 'Replaced bash shebang with zsh')
        end
      end
    end

    def attempt_tool_replacement(violation)
      # This would require complex AST manipulation
      # For now, just suggest the fix
      suggestions = {
        'sed' => 'Use zsh parameter expansion: ${var//pattern/replacement}',
        'awk' => 'Use zsh parameter expansion: ${${(s: :)line}[N]}',
        'wc' => 'Use zsh parameter expansion: ${#var}',
        'head' => 'Use zsh array slicing: ${lines[1,N]}',
        'tail' => 'Use zsh array slicing: ${lines[-N,-1]}',
        'tr' => 'Use zsh case modification: ${(U)var} or ${(L)var}',
        'cut' => 'Use zsh parameter expansion: ${var:start:length}',
        'find' => 'Use zsh glob patterns: **/*.ext',
        'bash' => 'Use zsh instead',
        'python' => 'Use ruby or zsh',
        'sudo' => 'Run as appropriate user with doas'
      }
      
      tool = violation[:tool]
      suggestion = suggestions[tool] || 'Use allowed tools only'
      
      log_fix(violation, 'SUGGEST', suggestion)
    end

    def log_fix(violation, status, message)
      @fixes_applied << {
        file: violation[:file],
        line: violation[:line],
        type: violation[:type],
        status: status,
        message: message
      }
    end
  end
end

# CLI interface
if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: #{$0} <violations.json> [--dry-run]"
    exit 1
  end

  violations_file = ARGV[0]
  dry_run = ARGV.include?('--dry-run')

  unless File.exist?(violations_file)
    STDERR.puts "Violations file not found: #{violations_file}"
    exit 1
  end

  data = JSON.parse(File.read(violations_file), symbolize_names: true)
  violations = data[:violations]

  fixer = Converge::Fixer.new(violations, dry_run: dry_run)
  puts fixer.to_json
end
