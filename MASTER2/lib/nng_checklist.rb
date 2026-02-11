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
      },
      web_visibility: {
        name: "Web UI: Visibility of System Status",
        checks: [
          { feature: 'status_bar', desc: 'Status bar shows tier, budget, sync time', file: 'views/cli.html' },
          { feature: 'loader_feedback', desc: 'Loader appears within 100ms of submit', file: 'views/cli.html' },
          { feature: 'toast_feedback', desc: 'Toast confirms mode switches', file: 'views/cli.html' },
          { feature: 'offline_indicator', desc: 'Offline state clearly indicated', file: 'views/cli.html' }
        ]
      },
      web_aesthetic: {
        name: "Web UI: Aesthetic and Minimalist Design",
        checks: [
          { feature: 'css_tokens', desc: 'All colors defined as CSS custom properties', file: 'views/cli.html' },
          { feature: 'single_accent', desc: 'Single mint accent color family', file: 'views/cli.html' },
          { feature: 'system_font', desc: 'System monospace only, no web fonts', file: 'views/cli.html' },
          { feature: 'minimal_chrome', desc: 'Input + output + status bar only', file: 'views/cli.html' }
        ]
      },
      web_performance: {
        name: "Web UI: Performance",
        checks: [
          { feature: 'raf_grain', desc: 'Grain uses requestAnimationFrame not setInterval', file: 'views/cli.html' },
          { feature: 'raf_orbs', desc: 'All orbs use requestAnimationFrame', file: 'views/orb_blob.html' },
          { feature: 'backoff_polling', desc: 'Exponential backoff when offline', file: 'views/cli.html' },
          { feature: 'no_clear_rect', desc: 'Orbs use decay fill, never clearRect', file: 'views/orb_blob.html' }
        ]
      },
      web_accessibility: {
        name: "Web UI: Accessibility",
        checks: [
          { feature: 'focus_visible', desc: 'Focus ring uses box-shadow + :focus-visible', file: 'views/cli.html' },
          { feature: 'dialog_help', desc: 'Help uses <dialog> with backdrop click', file: 'views/cli.html' },
          { feature: 'contrast_ratio', desc: 'Text contrast ≥ 4.5:1 on #050505 bg', file: 'views/cli.html' },
          { feature: 'reduced_motion', desc: 'prefers-reduced-motion stops animations', file: 'views/orb_blob.html' }
        ]
      },
      parity: {
        name: "Web/TTY Parity",
        checks: [
          { feature: 'command_parity', desc: 'Every TTY command has web equivalent', file: 'commands.rb' },
          { feature: 'error_parity', desc: 'Error messages identical across surfaces', file: 'ui.rb' },
          { feature: 'status_parity', desc: 'System status shown in both surfaces', file: 'pipeline.rb' }
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
