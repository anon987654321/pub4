# frozen_string_literal: true

module TTY
  module Screen
    class << self
      def width
        (ENV["COLUMNS"] || 80).to_i
      end

      def height
        (ENV["LINES"] || 24).to_i
      end
    end
  end
end
