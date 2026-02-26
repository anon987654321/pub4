# frozen_string_literal: true

module MASTER
  module Autocomplete
    module_function

    COMMANDS = MASTER::CommandRegistry.autocomplete_commands.freeze

    def complete(partial, context: nil)
      completions = []

      # Command completion
      completions += COMMANDS.select { |c| c.start_with?(partial) } if partial.match?(/^\w*$/)

      # % meta-op completion
      if partial.start_with?("%")
        word = partial[1..]
        completions += COMMANDS.select { |c| c.start_with?(word) }.map { |c| "%#{c}" }
      end

      # File path completion
      if partial.include?("/") || partial.include?("\\") || partial.end_with?(".rb")
        completions += complete_path(partial)
      end

      # Context-aware completions after known commands
      if context
        case context
        when "refactor", "chamber", "scan", "fix", "learn", "evolve", "opportunities"
          completions += complete_path(partial)
        when "model", "use"
          completions += complete_models(partial)
        when "session"
          completions += %w[new save load info replay export diff ls].select { |s| s.start_with?(partial) }
        when "help"
          completions += COMMANDS.select { |c| c.start_with?(partial) }
          completions += %w[tips beginner].select { |c| c.start_with?(partial) }
        end
      end

      completions.uniq
    end

    def complete_path(partial)
      dir = File.dirname(partial)
      dir = "." if dir == partial
      base = File.basename(partial)

      return [] unless Dir.exist?(dir)

      Dir.entries(dir)
        .reject { |e| e.start_with?(".") }
        .select { |e| e.start_with?(base) }
        .map { |e| File.join(dir, e) }
    rescue StandardError
      []
    end

    def complete_models(partial)
      return [] unless defined?(MASTER::LLM)

      models = MASTER::LLM.respond_to?(:available_model_names) ? MASTER::LLM.available_model_names : []
      models.select { |m| m.start_with?(partial) }
    rescue StandardError
      []
    end

    def setup_readline
      return unless defined?(Readline)

      Readline.completion_proc = proc do |input|
        complete(input)
      end
      Readline.completion_append_character = " "
    end

    def setup_tty(reader)
      return unless reader.respond_to?(:on)

      reader.on(:keypress) do |event|
        if event.key.name == :tab
          line_text = event.line.respond_to?(:text) ? event.line.text : event.line.to_s
          words = line_text.split
          word = words.last || ""
          ctx = words.size > 1 ? words.first : nil
          matches = complete(word, context: ctx)
          if matches.size == 1
            replacement = line_text.sub(/#{Regexp.escape(word)}$/, matches.first)
            event.line.replace(replacement) if event.line.respond_to?(:replace)
          elsif matches.size > 1
            puts "\n#{matches.join('  ')}"
          end
        end
      rescue StandardError
        # Silently ignore autocomplete errors
      end
    end
  end
end
