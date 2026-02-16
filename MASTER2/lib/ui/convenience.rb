# frozen_string_literal: true

module MASTER
  module UI
    # Convenience - high-level convenience methods
    module Convenience
      def success(msg)
        puts pastel.green("+ #{msg}")
      end

      def error(msg)
        $stderr.puts pastel.red("- #{msg}")
      end

      def warn(msg)
        $stderr.puts pastel.yellow("! #{msg}")
      end

      def info(msg)
        puts pastel.dim("  #{msg}")
      end

      def dim(msg)
        pastel.dim(msg)
      end

      def bold(msg)
        pastel.bold(msg)
      end

      def with_spinner(message, &block)
        s = spinner(message)
        s.auto_spin
        result = yield
        s.success
        result
      rescue StandardError => e
        s.error
        raise
      end

      def select(question, choices)
        return nil unless prompt
        prompt.select(question, choices, cycle: true)
      end

      def multi_select(question, choices)
        return [] unless prompt
        prompt.multi_select(question, choices, cycle: true)
      end

      def confirm(question, default: true)
        return default unless prompt
        prompt.yes?(question, default: default)
      end

      def ask(question, default: nil)
        return default unless prompt
        prompt.ask(question, default: default)
      end

      def paginate(text)
        pager.page(text)
      end

      def clear_line
        print cursor.clear_line + cursor.column(0)
      end

      def move_up(n = 1)
        print cursor.up(n)
      end

      def hide_cursor(&block)
        print cursor.hide
        yield
      ensure
        print cursor.show
      end
    end
  end
end
