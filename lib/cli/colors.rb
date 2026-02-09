module MASTER
  module CLI
    module Colors
      CODES = {
        red: 31,
        green: 32,
        yellow: 33,
        blue: 34,
        reset: 0
      }

      def self.enabled?
        !ENV['NO_COLOR'] && $stdout.tty?
      end

      def self.colorize(text, color)
        return text unless enabled?
        "\e[#{CODES[color]}m#{text}\e[#{CODES[:reset]}m"
      end

      def self.red(text)
        colorize(text, :red)
      end

      def self.green(text)
        colorize(text, :green)
      end

      def self.yellow(text)
        colorize(text, :yellow)
      end

      def self.blue(text)
        colorize(text, :blue)
      end
    end
  end
end
