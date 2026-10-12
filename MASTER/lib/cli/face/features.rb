# frozen_string_literal: true


module Master
  module CLI
    module Face
      # The eyes, brows, nose line and mouth, drawn as explicit glyphs over the
      # shading rather than left to it. Anchors are found in the points
      # themselves by their zone (Head marks the sockets, pupils and mouth), so
      # the terminal and the browser keep one morphology; a source with no
      # zones, a mesh, has no features. Each anchor is projected like a point
      # and drawn only where nothing nearer hides it.
      class Features
        GLYPHS = Glyphs::CONFIG.fetch("features").freeze
        SHUT = 0.5
        MOUTH_ZONE = 3

        def initialize(points, source)
          @anchors = source.respond_to?(:eyes) ? anchors(points) : nil
        end

        def draw(ascii, frame, look, state)
          return unless @anchors

          @ascii = ascii
          @frame = frame
          @look = look
          @anchors[:eyes].each { |eye| eyebrow_and_eye(eye) }
          nose
          mouth(state)
        end

        private

        def anchors(points)
          eyes = [-1, 1].map do |side|
            zone = points.select { |p| p[4].between?(1, 2) && (p[0] <=> 0) == side }
            next if zone.empty?

            eye = mean_point(zone.select { |p| p[4] == 2 }) || mean_point(zone)
            reach = ((zone.map(&:first).max_by { |x| (x - eye[0]).abs } - eye[0]).abs * 0.8)
            { left: nearest(zone, eye[0] - reach, eye[1]), right: nearest(zone, eye[0] + reach, eye[1]), pupil: eye }
          end.compact
          mouth = points.select { |p| p[4] == MOUTH_ZONE }
          return nil if eyes.size < 2 || mouth.empty?

          mx = mouth.map(&:first).minmax
          my = mean(mouth, 1)
          skin = points.select { |p| p[4].zero? && p[0].abs < 0.05 && p[2] > 0 }
          eye_y = eyes.sum { |e| e[:pupil][1] } / 2.0
          between = skin.select { |p| p[1] < eye_y && p[1] > my + 0.05 }
          tip = between.max_by { |p| p[2] }
          { eyes:, mouth: { left: nearest(mouth, mx[0], my), right: nearest(mouth, mx[1], my), centre: mean_point(mouth) },
            bridge: nearest(skin, 0.0, eye_y), tip: }
        end

        def mean(list, axis) = list.sum { |p| p[axis] } / list.size.to_f
        def mean_point(list) = list.empty? ? nil : [0, 1, 2].map { |a| mean(list, a) }
        def nearest(list, x, y) = list.min_by { |p| ((p[0] - x)**2) + ((p[1] - y)**2) }

        def cell(point)
          px, py, depth = @ascii.project(point[0], point[1], point[2])
          [px, py, depth, @ascii.hidden?(px, py, depth)]
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
          return if lh && rh

          px, py, = cell(eye[:pupil])
          span = (rx - lx).abs.floor
          width = [(span.even? ? span + 1 : span), 9].min
          col = Glyphs.half_up(px)
          row = (py / 2).floor
          return put(col, row, @look.eye_open < SHUT ? GLYPHS["lid"] : GLYPHS["pupil"]) if width < 3

          left = col - (width / 2)
          if @look.eye_open < SHUT
            run(left, row, GLYPHS["lid"] * width)
          else
            inner = width - 2
            reach = inner / 2
            glance = Glyphs.half_up(@look.gaze[0] * 14).clamp(-reach, reach)
            run(left, row, GLYPHS["eye_open"] + (" " * inner) + GLYPHS["eye_close"])
            put(col + glance, row, GLYPHS["pupil"])
          end
          run(left, row - 1, GLYPHS["brow"] * width)
        end

        def nose
          bx, by, _, bh = cell(@anchors[:bridge])
          tx, ty, _, th = cell(@anchors[:tip])
          return if bh || th

          steps = [(tx - bx).abs, (ty - by).abs / 2].max.ceil
          glyph = Glyphs.line(tx - bx, by - ty)
          (0...steps).each do |i|
            f = i / steps.to_f
            put(Glyphs.half_up(bx + ((tx - bx) * f)), ((by + ((ty - by) * f)) / 2).floor, glyph)
          end
          put(Glyphs.half_up(tx), (ty / 2).floor, GLYPHS["nose_tip"])
        end

        def mouth(state)
          lx, _, _, lh = cell(@anchors[:mouth][:left])
          rx, _, _, rh = cell(@anchors[:mouth][:right])
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
