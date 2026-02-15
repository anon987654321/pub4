# frozen_string_literal: true

module MASTER
  module Autocomplete
    extend self

    COMMANDS = %w[help status budget clear history refactor chamber evolve speak exit quit ask scan
                  model models pattern persona personas session schedule heartbeat policy phase
                  selftest fix harvest repligen postpro browse queue].freeze

    def complete(partial, context: nil)
      completions = []

      # Command completion
      if partial.match?(/^\w*$/)
        completions += COMMANDS.select { |c| c.start_with?(partial) }
      end

      # File path completion
      if partial.include?('/') || partial.include?('\\') || partial.end_with?('.rb')
        completions += complete_path(partial)
      end

      # After known commands, suggest relevant completions
      if context
        case context
        when 'refactor', 'chamber'
          completions += complete_path(partial).select { |p| p.end_with?('.rb') }
        when 'speak', 'say'
          # No completion for freeform text
        end
      end

      completions.uniq
    end

    def complete_path(partial)
      dir = File.dirname(partial)
      dir = '.' if dir == partial
      base = File.basename(partial)

      return [] unless Dir.exist?(dir)

      Dir.entries(dir)
         .reject { |e| e.start_with?('.') }
         .select { |e| e.start_with?(base) }
         .map { |e| File.join(dir, e) }
    rescue StandardError => e
      []
    end

    def setup_readline
      return unless defined?(Readline)

      Readline.completion_proc = proc do |input|
        complete(input)
      end
      Readline.completion_append_character = ' '
    end

    def setup_tty(reader)
      return unless reader.respond_to?(:on)

      reader.on(:keypress) do |event|
        if event.key.name == :tab
          line_text = event.line.respond_to?(:text) ? event.line.text : event.line.to_s
          word = line_text.split.last || ''
          matches = complete(word)
          if matches.size == 1
            replacement = line_text.sub(/#{Regexp.escape(word)}$/, matches.first)
            if event.line.respond_to?(:replace)
              event.line.replace(replacement)
            end
          elsif matches.size > 1
            puts "\n#{matches.join('  ')}"
          end
        end
      rescue StandardError => e
        # Silently ignore autocomplete errors
      end
    end
  end
end
