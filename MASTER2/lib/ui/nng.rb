# frozen_string_literal: true

module MASTER
  module UI
    # Merged from nng_checklist.rb
    module NNGChecklist
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

      def lint_html(file_path)
        return { error: "File not found: #{file_path}" } unless File.exist?(file_path)

        content = File.read(file_path)
        issues = []

        # Check for CSS custom properties usage (no raw hex outside :root)
        if content.include?('<style>')
          style_section = content[/<style>(.*?)<\/style>/m, 1]
          if style_section
            # Extract :root section
            root_section = style_section[/:root\s*\{[^}]*\}/m]
            non_root = style_section.gsub(/:root\s*\{[^}]*\}/m, '')

            # Check for hex colors outside :root
            hex_colors = non_root.scan(/#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\b/)
            unless hex_colors.empty?
              issues << "Found #{hex_colors.length} raw hex colors outside :root (should use CSS vars)"
            end
          end
        end

        # Check for prefers-reduced-motion media query
        unless content.include?('prefers-reduced-motion')
          issues << "Missing @media (prefers-reduced-motion) support"
        end

        # Check for focus styles
        has_focus = content.include?('focus-visible') || content.include?(':focus')
        unless has_focus
          issues << "Missing focus styles (:focus or :focus-visible)"
        end

        # Check for dialog element vs custom modal
        if content.include?('modal') && !content.include?('<dialog')
          issues << "Consider using <dialog> element instead of custom modal"
        end

        # Check for semantic HTML
        semantic_score = 0
        semantic_score += 1 if content.include?('<nav')
        semantic_score += 1 if content.include?('<header')
        semantic_score += 1 if content.include?('<main')
        semantic_score += 1 if content.include?('<footer')
        semantic_score += 1 if content.include?('<article')
        semantic_score += 1 if content.include?('<section')

        if semantic_score == 0 && content.length > 1000
          issues << "Consider using semantic HTML elements (nav, header, main, footer, article, section)"
        end

        {
          file: file_path,
          issues: issues,
          pass: issues.empty?
        }
      end

      def lint_views
        views_dir = File.join(MASTER.root, 'lib', 'views')
        return { error: "Views directory not found" } unless Dir.exist?(views_dir)

        results = []
        Dir.glob(File.join(views_dir, '*.html')).each do |file|
          results << lint_html(file)
        end

        {
          total: results.length,
          passed: results.count { |r| r[:pass] },
          failed: results.count { |r| !r[:pass] },
          results: results
        }
      end

      def check_contrast(fg_hex, bg_hex)
        # Convert hex to RGB
        fg_rgb = [fg_hex[1..2], fg_hex[3..4], fg_hex[5..6]].map { |h| h.to_i(16) / 255.0 }
        bg_rgb = [bg_hex[1..2], bg_hex[3..4], bg_hex[5..6]].map { |h| h.to_i(16) / 255.0 }

        # Calculate relative luminance
        fg_lum = relative_luminance(fg_rgb)
        bg_lum = relative_luminance(bg_rgb)

        # Calculate contrast ratio
        lighter = [fg_lum, bg_lum].max
        darker = [fg_lum, bg_lum].min
        ratio = (lighter + 0.05) / (darker + 0.05)

        {
          ratio: ratio.round(2),
          wcag_aa: ratio >= 4.5,
          wcag_aaa: ratio >= 7.0
        }
      end

      private

      def relative_luminance(rgb)
        rgb.map do |c|
          c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
        end.then do |r, g, b|
          0.2126 * r + 0.7152 * g + 0.0722 * b
        end
      end
    end

  end
end
