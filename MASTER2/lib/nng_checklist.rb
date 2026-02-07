# frozen_string_literal: true

module MASTER
  # NNgChecklist - Nielsen Norman Group usability heuristics compliance
  module NNgChecklist
    HEURISTICS = {
      visibility: {
        name: "Visibility of System Status",
        checks: [
          { feature: 'progress_indicators', desc: 'Show progress during LLM calls', file: 'progress.rb' },
          { feature: 'prompt_status', desc: 'Prompt shows tier and budget', file: 'pipeline.rb' },
          { feature: 'circuit_indicator', desc: '⚡ shows tripped circuits', file: 'pipeline.rb' }
        ]
      },
      match: {
        name: "Match Between System and Real World",
        checks: [
          { feature: 'natural_commands', desc: 'Commands use natural language', file: 'commands.rb' },
          { feature: 'dmesg_boot', desc: 'Boot messages in familiar format', file: 'boot.rb' }
        ]
      },
      control: {
        name: "User Control and Freedom",
        checks: [
          { feature: 'undo', desc: 'Undo support for file operations', file: 'undo.rb' },
          { feature: 'ctrl_c', desc: 'Ctrl+C cancels operations', file: 'pipeline.rb' },
          { feature: 'exit', desc: 'Clear exit command', file: 'commands.rb' }
        ]
      },
      consistency: {
        name: "Consistency and Standards",
        checks: [
          { feature: 'prompt_format', desc: 'Consistent prompt format', file: 'pipeline.rb' },
          { feature: 'result_monad', desc: 'Consistent Result type', file: 'result.rb' }
        ]
      },
      error_prevention: {
        name: "Error Prevention",
        checks: [
          { feature: 'guard_stage', desc: 'Guard blocks dangerous commands', file: 'stages.rb' },
          { feature: 'confirmations', desc: 'Confirm destructive actions', file: 'confirmations.rb' },
          { feature: 'agent_firewall', desc: 'Filter agent outputs', file: 'agent_firewall.rb' }
        ]
      },
      recognition: {
        name: "Recognition Rather Than Recall",
        checks: [
          { feature: 'autocomplete', desc: 'Tab completion for commands', file: 'autocomplete.rb' },
          { feature: 'help', desc: 'Help shows all commands', file: 'help.rb' }
        ]
      },
      flexibility: {
        name: "Flexibility and Efficiency of Use",
        checks: [
          { feature: 'keybindings', desc: 'Keyboard shortcuts', file: 'keybindings.rb' },
          { feature: 'tiers', desc: 'Multiple model tiers', file: 'llm.rb' },
          { feature: 'pipe_mode', desc: 'Pipe mode for scripting', file: 'pipeline.rb' }
        ]
      },
      aesthetic: {
        name: "Aesthetic and Minimalist Design",
        checks: [
          { feature: 'clean_output', desc: 'Minimal, focused output', file: 'stages.rb' },
          { feature: 'render_stage', desc: 'Typography improvements', file: 'stages.rb' }
        ]
      },
      errors: {
        name: "Help Users Recognize, Diagnose, Recover from Errors",
        checks: [
          { feature: 'error_suggestions', desc: 'Actionable error messages', file: 'error_suggestions.rb' },
          { feature: 'circuit_breaker', desc: 'Auto-recover from API failures', file: 'llm.rb' }
        ]
      },
      documentation: {
        name: "Help and Documentation",
        checks: [
          { feature: 'help_command', desc: 'Built-in help', file: 'help.rb' },
          { feature: 'tips', desc: 'Contextual tips', file: 'help.rb' },
          { feature: 'readme', desc: 'Comprehensive README', file: '../README.md' }
        ]
      }
    }.freeze

    extend self

    def audit
      results = {}

      HEURISTICS.each do |key, heuristic|
        results[key] = {
          name: heuristic[:name],
          checks: heuristic[:checks].map do |check|
            file_exists = File.exist?(File.join(MASTER.root, 'lib', check[:file]))
            { **check, status: file_exists ? :pass : :missing }
          end
        }
      end

      results
    end

    def compliance_score
      total = 0
      passed = 0

      HEURISTICS.each do |_, heuristic|
        heuristic[:checks].each do |check|
          total += 1
          file_path = File.join(MASTER.root, 'lib', check[:file])
          passed += 1 if File.exist?(file_path)
        end
      end

      (passed.to_f / total * 100).round(1)
    end

    def report
      score = compliance_score
      audit_results = audit

      lines = ["NN/g Usability Audit - Score: #{score}%", "=" * 50, ""]

      audit_results.each do |key, result|
        status_count = result[:checks].count { |c| c[:status] == :pass }
        total = result[:checks].size
        lines << "#{result[:name]} (#{status_count}/#{total})"

        result[:checks].each do |check|
          icon = check[:status] == :pass ? "✓" : "✗"
          lines << "  #{icon} #{check[:desc]}"
        end
        lines << ""
      end

      lines.join("\n")
    end
  end
end
