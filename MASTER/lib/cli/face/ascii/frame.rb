# frozen_string_literal: true

module Master
  module CLI
    module Face
      class Ascii
        # Rows of characters and, beside them, 0 far, 1 mid, 2 near.
        Frame = Struct.new(:chars, :depth) do
          # Trimmed, for a test to compare; to_s keeps every row the window's width.
          def lines = chars.map { |row| row.join.rstrip }

          def to_s(color: false)
            return chars.map(&:join).join("\n") unless color

            chars.each_index.map { |r| paint(r) }.join("\n")
          end

          private

          def paint(row)
            tone = nil
            text = +""
            chars[row].each_with_index do |ch, col|
              level = ch == " " ? 1 : depth[row][col]
              text << ["\e[0;2;38;2;96;118;150m", "\e[0;38;2;168;190;220m", "\e[0;1;38;2;232;242;255m"][level] if level != tone
              tone = level
              text << ch
            end
            "#{text}\e[0m"
          end
        end
      end
    end
  end
end
