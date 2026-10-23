# frozen_string_literal: true

module Master
  module CLI
    module Face
      class Ascii
        # The colour of each depth, 0 far (faint) to 2 near (bold): face_interface.ascii tone_* in data/tokens.yml.
        RGB = ->(hex) { hex.delete("#").scan(/../).map(&:hex).join(";") }
        TONES = Master::Face::Contract.ascii.values_at("tone_far", "tone_mid", "tone_near").zip(%w[0;2 0 0;1])
                                       .map { |hex, weight| "\e[#{weight};38;2;#{RGB.call(hex)}m" }.freeze

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
              text << TONES.fetch(level) if level != tone
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
