# frozen_string_literal: true


module Master
  module CLI
    module Face
      # What a cell says: the line glyph for a direction, the half-cell edge
      # glyph, and the ramp character for a tone. Pure functions over the
      # constants in data/tokens.yml (face_interface.ascii), which the web face
      # reads too; rounding is half up and every index a floor, so a port
      # agrees to the cell.
      module Glyphs
        CONFIG = Master::Face::Contract.ascii.freeze
        ASPECT = CONFIG.fetch("aspect", 2.0).to_f
        DITHER = CONFIG.fetch("dither").freeze
        DITHER_GAIN = CONFIG.fetch("dither_gain").to_f
        DEFAULT_CHARS = CONFIG.fetch("chars", " .:-=+*#%@")
        # A "/" crosses a cell corner to corner, which is steeper than 45
        # degrees on a cell twice as tall as it is wide.
        SLASH = Math.atan(ASPECT)
        FLAT = SLASH / 2
        STEEP = (SLASH + (Math::PI / 2)) / 2
        UPRIGHT = (Math::PI - STEEP)
        CEILING = Math::PI - FLAT

        module_function

        def half_up(value) = (value + 0.5).floor

        # The glyph for a line running along (dx, dy) with y up, in square
        # sub-pixels.
        def line(dx, dy)
          angle = Math.atan2(dy, dx)
          angle += Math::PI if angle.negative?
          return "-" if angle < FLAT || angle >= CEILING
          return "/" if angle < STEEP
          return "|" if angle < UPRIGHT

          "\\"
        end

        # A horizontal edge, placed by the sub-row it falls on: a boundary at
        # the cell's top is ', its middle -, its bottom _. Both halves filled
        # means the edge is the cell's own, and open_below says which.
        def level(top, bottom, open_below)
          return "-" unless top && bottom

          open_below ? "_" : "'"
        end

        # The ramp, dense ink last; light mode reverses it for a pale page.
        def ramp(chars = DEFAULT_CHARS, mode = "dark")
          glyphs = chars.to_s.chars
          glyphs = [" ", "#"] if glyphs.size < 2
          mode.to_s == "light" ? glyphs.reverse : glyphs
        end

        # The ramp index for a tone, nudged by the integer dither matrix fixed
        # in screen space, so turning does not shimmer.
        def index(tone, size, col, row)
          threshold = 0.5 + ((((DITHER[row % 4][col % 4] + 0.5) / 16.0) - 0.5) * DITHER_GAIN)
          ((tone * (size - 1)) + threshold).floor.clamp(0, size - 1)
        end
      end
    end
  end
end
