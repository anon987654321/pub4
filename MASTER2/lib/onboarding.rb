# frozen_string_literal: true

module MASTER
  # Onboarding - First-run experience and helpful prompts
  module Onboarding
    extend self

    WELCOME = <<~MSG
      Welcome to MASTER v#{VERSION}

      Quick start:
        • Just type a question or request
        • Use 'help' for all commands
        • Use 'status' to see system state

      Examples:
        "Explain this Ruby code: def foo; end"
        "refactor lib/example.rb"
        "chamber lib/complex.rb"

    MSG

    EXAMPLES = [
      "Explain Ruby blocks vs procs",
      "How do I use OpenBSD pledge?",
      "Review this code for bugs",
      "help",
    ].freeze

    EMPTY_HINTS = [
      "Try: 'help' to see available commands",
      "Try: 'status' to see system state",
      "Try: 'budget' to check remaining funds",
      "Just type a question to ask the LLM",
    ].freeze

    class << self
      def first_run?
        !File.exist?(first_run_marker)
      end

      def show_welcome
        return unless first_run?

        puts
        puts UI.bold("MASTER v#{VERSION}")
        puts
        WELCOME.each_line { |l| puts "  #{l}" }
        mark_first_run
      end

      def suggest_on_empty
        hint = EMPTY_HINTS.sample
        puts UI.dim("  #{hint}")
      end

      def did_you_mean(input)
        commands = Help::COMMANDS.keys.map(&:to_s)
        word = input.strip.split.first&.downcase
        return nil unless word

        commands.find { |c| Utils.levenshtein(word, c) <= 2 }
      end

      def show_did_you_mean(input)
        suggestion = did_you_mean(input)
        return false unless suggestion

        puts UI.dim("  Did you mean: #{suggestion}?")
        true
      end

      private

      def first_run_marker
        File.join(Paths.var, ".first_run_complete")
      end

      def mark_first_run
        FileUtils.mkdir_p(File.dirname(first_run_marker))
        File.write(first_run_marker, Time.now.iso8601)
      end
    end
  end
end

