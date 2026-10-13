# frozen_string_literal: true

module Master
  module CLI
    module Face
      # How big the face is drawn: the terminal's own size, less the margins,
      # between a floor and a cap, in the head's proportions. Pure over its
      # arguments, so a test gives it a fake window. The numbers are in
      # data/tokens.yml (face_interface.ascii.size).
      module Sizing
        CONFIG = Glyphs::CONFIG.fetch("size").freeze
        FLOOR = CONFIG.fetch("floor").map(&:to_i).freeze
        CAP = CONFIG.fetch("cap").map(&:to_i).freeze
        MARGIN = CONFIG.fetch("margin").freeze
        SPAN = CONFIG.fetch("span").to_f
        FALLBACK = [24, 80].freeze
        MIN = [Glyphs::CONFIG.fetch("min_rows").to_i, Glyphs::CONFIG.fetch("min_cols").to_i].freeze
        SHAPE = /\A(\d+)\s*[x*]\s*(\d+)\z/i

        @mode = nil

        module_function

        # The session's choice: set by `/face size`, else MASTER_FACE_SIZE, else
        # the token.
        def mode = @mode || ENV["MASTER_FACE_SIZE"] || CONFIG.fetch("mode")

        def mode=(value)
          @mode = value.nil? ? nil : parse(value)
        end

        # A mode word as stored: auto, small, large, or "WxH"; nil if it is none.
        def parse(text)
          word = text.to_s.strip.downcase
          return word if %w[auto small large].include?(word)

          shape = word.match(SHAPE)
          shape ? "#{shape[1].to_i}x#{shape[2].to_i}" : nil
        end

        # The terminal's [rows, cols]: the console's, else LINES and COLUMNS,
        # else 24 by 80. A console that answers zero (no size set) is no answer.
        def winsize(console: IO.console, env: ENV)
          size = begin
            console&.winsize
          rescue StandardError
            nil
          end
          return size if size.is_a?(Array) && size.all?(&:positive?)

          rows = env["LINES"].to_i
          cols = env["COLUMNS"].to_i
          rows.positive? && cols.positive? ? [rows, cols] : FALLBACK.dup
        end

        # [rows, cols] of the face in a space of avail_rows by avail_cols cells,
        # a cell aspect times as tall as wide.
        def fit(avail_rows, avail_cols, mode: self.mode, aspect: Glyphs::ASPECT)
          rows_room = [avail_rows - (2 * MARGIN.fetch("rows").to_i), 1].max
          cols_room = [avail_cols - (2 * MARGIN.fetch("cols").to_i), 1].max
          word = parse(mode) || "auto"
          wanted = case word
                   when "small" then FLOOR
                   when "large" then CAP
                   when "auto" then [rows_room, cols_room]
                   else word.split("x").map(&:to_i).reverse
                   end
          rows = clamp(wanted[0], FLOOR[0], CAP[0], rows_room)
          cols = clamp(wanted[1], FLOOR[1], CAP[1], cols_room)
          cols = [cols, (rows * aspect * SPAN).ceil].min if word == "auto"
          [rows, [cols, [MIN[1], cols_room].min].max]
        end

        # wanted, no less than the floor and no more than the cap, and never
        # more than the room the terminal has.
        def clamp(wanted, floor, cap, room) = [[wanted, floor].max, cap, room].min
      end
    end
  end
end
