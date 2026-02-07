# frozen_string_literal: true

module MASTER
  # Confirmations - NN/g: Prevent errors by confirming destructive actions
  module Confirmations
    extend self

    DESTRUCTIVE_PATTERNS = [
      /rm\s+-rf/i,
      /delete/i,
      /drop\s+table/i,
      /truncate/i,
      /reset/i,
      /--force/i,
      /overwrite/i
    ].freeze

    def needs_confirmation?(input)
      DESTRUCTIVE_PATTERNS.any? { |pat| input.match?(pat) }
    end

    def confirm(message, default: false)
      if defined?(TTY::Prompt)
        prompt = TTY::Prompt.new
        prompt.yes?(message)
      else
        default_hint = default ? "[Y/n]" : "[y/N]"
        print "#{message} #{default_hint} "
        response = $stdin.gets&.strip&.downcase

        return default if response.nil? || response.empty?
        %w[y yes].include?(response)
      end
    end

    def confirm_destructive(action, details: nil)
      puts "\n  ⚠️  Destructive Action: #{action}"
      puts "  #{details}" if details
      puts

      confirm("Are you sure you want to proceed?", default: false)
    end

    def confirm_with_options(message, options)
      if defined?(TTY::Prompt)
        prompt = TTY::Prompt.new
        prompt.select(message, options)
      else
        puts message
        options.each_with_index { |opt, i| puts "  #{i + 1}. #{opt}" }
        print "Select (1-#{options.size}): "
        choice = $stdin.gets&.strip&.to_i
        options[choice - 1] if choice.between?(1, options.size)
      end
    end
  end
end
