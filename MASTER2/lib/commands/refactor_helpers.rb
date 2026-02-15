# frozen_string_literal: true

module MASTER
  module Commands
    # Helper methods for refactor command
    module RefactorHelpers
      def extract_mode(args)
        mode_arg = args.find { |a| a.start_with?("--") }
        case mode_arg
        when "--raw" then :raw
        when "--apply" then :apply
        when "--preview" then :preview
        else :preview # default
        end
      end

      def lint_output(text)
        lint_stage = Stages::Lint.new
        result = lint_stage.call({ response: text })
        result.ok? ? result.value[:response] : text
      end

      def render_output(text)
        render_stage = Stages::Render.new
        result = render_stage.call({ response: text })
        result.ok? ? result.value[:rendered] : text
      end

      def format_council_summary(council_info)
        return nil unless council_info

        if council_info[:vetoed_by]&.any?
          "  Council: VETOED by #{council_info[:vetoed_by].join(', ')}"
        elsif council_info[:consensus]
          pct = (council_info[:consensus] * 100).round(0)
          verdict = council_info[:verdict] || :unknown
          "  Council: #{verdict.to_s.upcase} (#{pct}% consensus)"
        else
          nil
        end
      end

      def display_raw_output(result, rendered, council_info)
        puts "\n  Proposals: #{result.value[:proposals].size}"
        puts "  Cost: #{UI.currency_precise(result.value[:cost])}"
        if (summary = format_council_summary(council_info))
          puts summary
        end
        puts "\n#{rendered}\n"
      end

      def display_preview(path, original, proposed, result, council_info)
        require_relative "diff_view"
        diff = DiffView.unified_diff(original, proposed, filename: File.basename(path))

        puts "\n  Proposals: #{result.value[:proposals].size}"
        puts "  Cost: #{UI.currency_precise(result.value[:cost])}"
        if (summary = format_council_summary(council_info))
          puts summary
        end
        puts "\n#{diff}"
        puts "  Use --apply to write changes, --raw to see full output"
      end

      def apply_refactor(path, original, proposed, result, council_info)
        require_relative "diff_view"
        diff = DiffView.unified_diff(original, proposed, filename: File.basename(path))

        puts "\n  Proposals: #{result.value[:proposals].size}"
        puts "  Cost: #{UI.currency_precise(result.value[:cost])}"
        if (summary = format_council_summary(council_info))
          puts summary
        end
        puts "\n#{diff}"

        # Prompt for confirmation
        print "\n  Apply these changes? [y/N] "
        response = $stdin.gets&.strip&.downcase

        if response == "y" || response == "yes"
          # Track original content for undo
          Undo.track_edit(path, original)

          # Write changes to disk
          File.write(path, proposed)

          puts "  ✓ Changes applied to #{path}"
          puts "  (Use 'undo' command to revert)"
        else
          puts "  Changes not applied"
        end
      end
    end
  end
end
