# frozen_string_literal: true

module Master
  module CLI
    module Face
      # The eyes, brows, nose line and mouth, drawn as explicit glyphs over the
      # shading rather than left to it. Their anchors are the mesh's landmarks
      # (Head#landmarks puts them on the surface, so the terminal and the
      # browser keep one morphology); a mesh read from a file has none and so no
      # features. Each anchor is projected like a vertex and drawn only where
      # nothing nearer hides it.
      class Features
        GLYPHS = Glyphs::CONFIG.fetch("features").freeze
        SHUT = 0.5

        def initialize(mesh)
          @anchors = mesh.landmarks
          @mask = mesh.params
          xlo, xhi, _, @top = mesh.bounds
          @side = [-xlo, xhi].max
          @mouth_slack = 0.0
          @slack = 0.0
        end

        def draw(ascii, frame, look, state)
          return unless @anchors

          @ascii = ascii
          @frame = frame
          @look = look
          @rings = @mask && @mask["ring"] >= Masks::TAKEOVER
          @slack = @mask ? (@mask["beak_projection"] + @mask["brow_ridge"]) * ascii.scale : 0.0
          @mouth_slack = @mask ? Masks::MOUTH_SLACK * ascii.scale : 0.0
          @anchors[:eyes].each { |eye| @rings ? ring_eye(eye) : eyebrow_and_eye(eye) }
          nose
          mouth(state)
          return unless @mask

          halo
          discs
        end

        private

        def cell(point, slack = 0.0)
          px, py, depth = @ascii.project(point[0], point[1], point[2])
          [px, py, depth, @ascii.hidden?(px, py, depth, slack) || !@ascii.covered?(px, py) || !@ascii.facing?(point[0], point[2])]
        end

        def put(col, row, glyph)
          return unless row >= 0 && row < @frame.chars.size && col >= 0 && col < @frame.chars[0].size

          @frame.chars[row][col] = glyph
          @frame.depth[row][col] = 2
        end

        def run(col, row, glyphs)
          glyphs.each_char.with_index { |g, i| put(col + i, row, g) }
        end

        def eyebrow_and_eye(eye)
          lx, _, _, lh = cell(eye[:left])
          rx, _, _, rh = cell(eye[:right])
          px, py, _, ph = cell(eye[:pupil])
          return if ph || (lh && rh)

          span = (rx - lx).abs.floor
          width = [(span.even? ? span + 1 : span), eye_limit].min
          col = Glyphs.half_up(px)
          row = (py / 2).floor
          return put(col, row, @look.eye_open < SHUT ? GLYPHS["lid"] : GLYPHS["pupil"]) if width < 3

          left = col - (width / 2)
          tall = width >= GLYPHS.fetch("eye_tall_at")
          lift = tall ? 2 : 0
          if @look.eye_open < SHUT
            run(left, row, GLYPHS["lid"] * width)
          else
            inner = width - 2
            reach = inner / 2
            glance = Glyphs.half_up(@look.gaze[0] * 14).clamp(-reach, reach)
            run(left, row, GLYPHS["eye_open"] + (" " * inner) + GLYPHS["eye_close"])
            almond(left, row, width) if tall
            put(col + glance, row, tall ? GLYPHS["pupil_large"] : GLYPHS["pupil"])
          end
          run(left, row - 1 - lift, GLYPHS["brow"] * width) if @mask.nil? || @mask["brow_line"] >= 0.5
          run(left, row - 2 - lift, Masks::GLYPHS["brow_heavy"] * width) if @mask && @mask["brow_ridge"] >= Masks::BROW_MIN
        end

        # An eye wide enough to have lids: the upper one a row above the line of
        # the eye, the lower one a row below, their corners ' and ..
        def almond(left, row, width)
          top = GLYPHS.fetch("eye_lid_top")
          bottom = GLYPHS.fetch("eye_lid_bottom")
          run(left, row - 1, top[0] + (top[1] * (width - 2)) + top[2])
          run(left, row + 1, bottom[0] + (bottom[1] * (width - 2)) + bottom[2])
        end

        # An eye is at most eye_floor wide, or eye_share of the window's columns
        # if that is more, so a big face has big eyes and a small one the same as ever.
        def eye_limit = [GLYPHS.fetch("eye_floor"), (@frame.chars[0].size * GLYPHS.fetch("eye_share")).floor].max

        def nose
          return if @mask && @mask["nose_line"] < 0.5

          bx, by, _, bh = cell(@anchors[:bridge])
          tx, ty, _, th = cell(@anchors[:tip])
          return if bh || th
          return beak(bx, by, tx, ty) if @mask && @mask["beak_projection"] >= Masks::BEAK_MIN

          steps = [(tx - bx).abs, (ty - by).abs / 2].max.ceil
          glyph = Glyphs.line(tx - bx, by - ty)
          (0...steps).each do |i|
            f = i / steps.to_f
            put(Glyphs.half_up(bx + ((tx - bx) * f)), ((by + ((ty - by) * f)) / 2).floor, glyph)
          end
          put(Glyphs.half_up(tx), (ty / 2).floor, GLYPHS["nose_tip"])
          nostrils(tx, ty, (ty - by).abs / 2)
        end

        # A nose long enough to show its nostrils: a pair flanking the tip.
        def nostrils(tx, ty, length)
          return if length < GLYPHS.fetch("nostril_at")

          wing = [(length / GLYPHS.fetch("nostril_at")).floor + 1, 3].min
          put(Glyphs.half_up(tx) - wing, (ty / 2).floor, GLYPHS["nostril"][0])
          put(Glyphs.half_up(tx) + wing, (ty / 2).floor, GLYPHS["nostril"][1])
        end

        # The nose as a ridge: two rails that part from the bridge toward the
        # tip, and the tip's own glyphs, where the plain face draws one line.
        def beak(bx, by, tx, ty)
          tip = @anchors[:tip]
          flare = (@ascii.project(tip[0] + @mask["beak_flare"], tip[1], tip[2])[0] - tx).abs
          steps = [(tx - bx).abs, (ty - by).abs / 2].max.ceil
          rails = [-1, 1].map { |side| [side, Glyphs.line((tx + (side * flare)) - bx, by - ty)] }
          (0...steps).each do |i|
            f = i / steps.to_f
            y = ((by + ((ty - by) * f)) / 2).floor
            rails.each { |side, glyph| put(Glyphs.half_up(bx + ((tx - bx) * f) + (side * flare * f)), y, glyph) }
          end
          run(Glyphs.half_up(tx) - (Masks::GLYPHS["beak_tip"].size / 2), (ty / 2).floor, Masks::GLYPHS["beak_tip"])
        end

        # Eyes as concentric rings of the eye's own plane, outermost glyph
        # first, with the pupil (or the lid, shut) at the centre.
        def ring_eye(eye)
          px, py, _, ph = cell(eye[:pupil])
          return if ph || (cell(eye[:left])[3] && cell(eye[:right])[3])

          count = Glyphs.half_up(@mask["ring_count"])
          radius = @mask["ring_radius"] * @mask["ring"]
          clear(eye[:pupil], radius)
          (1..count).each do |i|
            circle(eye[:pupil], radius * i / count, Masks::GLYPHS["ring"][(count - i) % Masks::GLYPHS["ring"].size])
          end
          put(Glyphs.half_up(px), (py / 2).floor, @look.eye_open < SHUT ? GLYPHS["lid"] : GLYPHS["pupil"])
        end

        # An arc above the crown in the contour glyphs, a row of it per arc.
        def halo
          amount = @mask["halo"]
          span = @mask["halo_span"] * amount
          return if span < 1.0

          radius = @mask["halo_radius"]
          centre = @top + (@mask["halo_rise"] * amount) - radius
          steps = (2 * span).ceil
          Glyphs.half_up(@mask["halo_rows"]).times do |row|
            r = radius - (row * @mask["halo_gap"])
            seen = (0..steps).map do |i|
              angle = (-span + (2 * span * i / steps)) * Math::PI / 180
              @ascii.project(r * Math.sin(angle), centre + (r * Math.cos(angle)), 0.0)
            end
            seen.each_with_index do |(px, py, depth), i|
              next if @ascii.hidden?(px, py, depth)

              before = seen[[i - 1, 0].max]
              after = seen[[i + 1, steps].min]
              glyph = Glyphs.line(after[0] - before[0], before[1] - after[1])
              glyph = Masks::GLYPHS["halo"][row.positive? ? 1 : 0] if glyph == "-"
              put(Glyphs.half_up(px), (py / 2).floor, glyph)
            end
          end
        end

        # A pair of ear discs, each two circles, at the head's widest.
        def discs
          amount = @mask["disc"]
          radius = @mask["disc_radius"] * amount
          return if radius <= 0.0

          y = (@anchors[:eyes].sum { |e| e[:pupil][1] } / 2.0) + @mask["disc_height"]
          [-1, 1].each do |side|
            centre = [side * (@side + (@mask["disc_offset"] * amount)), y, 0.0]
            Masks::GLYPHS["disc"].each_char.with_index { |g, i| circle(centre, radius * (1.0 - (i * 0.5)), g) }
          end
        end

        # Blank every cell whose centre falls within r of a point, so rings stand
        # on clear ground. A column's centre is its index, a row's its second
        # sub-row, as put places a glyph.
        def clear(centre, r)
          cx, cy, = @ascii.project(*centre)
          edge = (@ascii.project(centre[0] + r, centre[1], centre[2])[0] - cx).abs
          return if edge < Masks::RING_MIN_PX

          (((cy / 2).floor - edge.ceil)..((cy / 2).floor + edge.ceil)).each do |row|
            next if row.negative? || row >= @frame.chars.size

            ((cx - edge).floor..(cx + edge).ceil).each do |col|
              next if col.negative? || col >= @frame.chars[0].size

              dx = col - cx
              dy = ((2 * row) + 1) - cy
              @frame.chars[row][col] = " " if Math.sqrt((dx * dx) + (dy * dy)) <= edge
            end
          end
        end

        # A circle of radius r in the head's x-y plane about a point, sampled
        # densely enough that no cell between two samples is skipped.
        def circle(centre, r, glyph)
          edge = @ascii.project(centre[0] + r, centre[1], centre[2])[0] - @ascii.project(centre[0], centre[1], centre[2])[0]
          return if edge.abs < Masks::RING_MIN_PX

          steps = [(9.42 * edge.abs).ceil, 12].max
          steps.times do |i|
            angle = 2 * Math::PI * i / steps
            px, py, depth = @ascii.project(centre[0] + (r * Math.cos(angle)), centre[1] + (r * Math.sin(angle)), centre[2])
            put(Glyphs.half_up(px), (py / 2).floor, glyph) unless @ascii.hidden?(px, py, depth, @slack)
          end
        end

        def mouth(state)
          lx, _, _, lh = cell(@anchors[:mouth][:left], @mouth_slack)
          rx, _, _, rh = cell(@anchors[:mouth][:right], @mouth_slack)
          return if lh && rh

          mid = cell(@anchors[:mouth][:centre])
          row = (mid[1] / 2).floor
          opened = @look.mouth * @look.mouth_open
          width = [Glyphs.half_up((rx - lx).abs + 1), 2].max
          width += Glyphs.half_up(@look.mouth_wide * width * 0.3)
          left = Glyphs.half_up(mid[0]) - (width / 2)
          return put(Glyphs.half_up(mid[0]), row, GLYPHS["nose"]) if (lx - rx).abs < 1.5

          if opened > 0.12
            drop = opened > 0.5 ? 2 : 1
            top = row - (drop / 2)
            inner = [width - 2, 1].max
            run(left, top, GLYPHS["mouth_corner_top"] + (GLYPHS["mouth_line"] * inner) + GLYPHS["mouth_corner_top"])
            (1...drop).each { |i| run(left, top + i, " " * (inner + 2)) }
            run(left, top + drop, GLYPHS["mouth_corner_bottom"] + (GLYPHS["mouth_line"] * inner) + GLYPHS["mouth_corner_bottom"])
          elsif state == :listening
            a, b, c = GLYPHS["mouth_listening"]
            run(left, row, a + (b * [width - 2, 1].max) + c)
          else
            run(left - 1, row - 1, " " * (width + 2))
            run(left - 1, row + 1, " " * (width + 2))
            run(left, row, GLYPHS["mouth_line"] * width)
          end
        end
      end
    end
  end
end
