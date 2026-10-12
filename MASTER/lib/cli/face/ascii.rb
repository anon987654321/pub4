# frozen_string_literal: true

require "digest"

module Master
  module CLI
    module Face
      # A point source drawn in plain ASCII: contours (| - / \ and the half-cell
      # ' _), a dithered ink ramp for the surface, features on top, and depth
      # as bold and dim. The steps, in order, are written in data/tokens.yml
      # beside the numbers (face_interface.ascii); the web face ports them.
      #
      # A frame is a pure function of the points, the size and the Look: no
      # randomness, floor() for every index, so two readers agree to the cell.
      class Ascii
        CONFIG = Glyphs::CONFIG
        LIGHT = begin
          x, y, z = CONFIG.fetch("light").map(&:to_f)
          length = Math.sqrt((x * x) + (y * y) + (z * z))
          [x / length, y / length, z / length].freeze
        end
        CAMERA = CONFIG.fetch("camera").to_f
        FIT = CONFIG.fetch("fit").to_f
        SPLAT = CONFIG.fetch("splat").freeze
        CREASE = CONFIG.fetch("crease").to_f
        EDGE = CONFIG.fetch("edge_gradient").to_f
        HOLLOW = CONFIG.fetch("hollow").to_f
        GAP = CONFIG.fetch("gap").to_i
        SEE_THROUGH = CONFIG.fetch("see_through").to_f
        BASE, GAIN, PAINT, CEILING = CONFIG.fetch("shade").values_at("base", "gain", "paint", "ceiling").map(&:to_f)
        NEAR, FAR = CONFIG.fetch("depth").values_at("near", "far").map(&:to_f)
        OCCLUSION = CONFIG.fetch("occlusion").to_f
        NONE = -1.0e9
        LIVE = NONE / 2

        # Points are [x, y, z, brightness, zone] in the source's own space;
        # the source answers each_point (Head and Mesh both do).
        def initialize(source, rows, cols, chars: nil, mode: nil)
          @rows = rows
          @cols = cols
          @w = cols
          @h = rows * 2
          @ramp = Glyphs.ramp(chars || ENV["MASTER_FACE_CHARS"] || Glyphs::DEFAULT_CHARS, mode || ENV["MASTER_FACE_MODE"] || CONFIG.fetch("mode"))
          @points = []
          source.each_point { |x, y, z, b, zone, *| @points << [x, y, z, b, zone] }
          lift = @points.map { |p| p[1] }.minmax.sum / 2.0
          @points.each { |p| p[1] -= lift }
          reach = @points.map { |p| Math.hypot(p[0], p[2]) }.max
          span = @points.map { |p| p[1] }.minmax.then { |lo, hi| hi - lo }
          @scale = [((@w / 2.0) - 1) / reach, (@h - 2) / span].min * FIT
          @features = Features.new(@points, source)
        end

        # A short summary of the points as fitted, to compare two readers' input.
        def digest
          Digest::SHA256.hexdigest(@points.map { |p| p.first(4).map { |v| format("%.4f", v) }.join(",") }.join(";"))[0, 16]
        end

        def render(look, state: :idle)
          turn(look)
          buffer
          @frame = Frame.new(Array.new(@rows) { Array.new(@w, " ") }, Array.new(@rows) { Array.new(@w, 1) })
          @rows.times { |r| @w.times { |c| cell(c, r) } }
          @features.draw(self, @frame, look, state)
          @frame
        end

        # A source-space point in sub-pixels, and its depth in the same units.
        def project(x, y, z)
          rx = (x * @cy) + (z * @sy)
          rz = (-x * @sy) + (z * @cy)
          ry = (y * @cp) - (rz * @sp)
          rz = (y * @sp) + (rz * @cp)
          k = @gain * @camera / (@camera - rz)
          [@w / 2.0 + (((rx * @cr) - (ry * @sr)) * k), @rows - (((rx * @sr) + (ry * @cr)) * k) - @bob, rz * @scale]
        end

        def hidden?(px, py, depth)
          x = px.floor
          y = py.floor
          return true unless x.between?(0, @w - 1) && y.between?(0, @h - 1)

          @zb[(y * @w) + x] > depth + OCCLUSION
        end

        private

        def turn(look)
          @cy, @sy, @cp, @sp, @cr, @sr = [look.yaw + look.turn, look.pitch, look.roll].flat_map { |a| [Math.cos(a), Math.sin(a)] }
          @camera = CAMERA / look.dolly
          @gain = @scale * look.scale
          @bob = look.bob * @scale
        end

        def buffer
          @zb = Array.new(@w * @h, NONE)
          @bb = Array.new(@w * @h, 0.0)
          @points.each do |x, y, z, b, _|
            px, py, depth = project(x, y, z)
            ix = px.floor
            iy = py.floor
            SPLAT.each do |dx, dy|
              qx = ix + dx
              qy = iy + dy
              next unless qx >= 0 && qx < @w && qy >= 0 && qy < @h

              i = (qy * @w) + qx
              next unless depth > @zb[i]

              @zb[i] = depth
              @bb[i] = b
            end
          end
          close
          seen = @zb.select { |v| v > LIVE }
          @near_lo = seen.min || 0.0
          @near_span = [(seen.max || 0.0) - @near_lo, 1.0].max
          @zs = smoothed(smoothed(@zb))
        end

        # Seen near edge-on a surface is sampled sparsely, and the far side
        # shows through the gaps. A pixel with a nearer pixel on both sides
        # within GAP pixels, along a row or a column, takes the mean of the
        # two nearest (greatest depth) of them.
        def close
          fills = []
          @h.times do |y|
            @w.times do |x|
              i = (y * @w) + x
              own = @zb[i] + SEE_THROUGH
              pair = gap(i, 1, x, @w, own) || gap(i, @w, y, @h, own)
              fills << [i, pair] if pair
            end
          end
          fills.each do |i, (a, b)|
            @zb[i] = (@zb[a] + @zb[b]) / 2.0
            @bb[i] = (@bb[a] + @bb[b]) / 2.0
          end
        end

        # The greatest-depth pixel on each side of i along a stride, or nil
        # unless both stand nearer than own.
        def gap(i, stride, at, limit, own)
          lo = hi = nil
          d = 1
          while d <= GAP
            j = i - (stride * d)
            lo = j if at - d >= 0 && @zb[j] > own && (lo.nil? || @zb[j] > @zb[lo])
            k = i + (stride * d)
            hi = k if at + d < limit && @zb[k] > own && (hi.nil? || @zb[k] > @zb[hi])
            d += 1
          end
          lo && hi ? [lo, hi] : nil
        end

        # A 3x3 mean of the live neighbours, as a row sum then a column sum.
        def smoothed(src)
          n = @w * @h
          sums = Array.new(n, 0.0)
          counts = Array.new(n, 0)
          i = 0
          while i < n
            x = i % @w
            [-1, 0, 1].each do |dx|
              next if x + dx < 0 || x + dx >= @w || src[i + dx] <= LIVE

              sums[i] += src[i + dx]
              counts[i] += 1
            end
            i += 1
          end
          out = Array.new(n, NONE)
          i = 0
          while i < n
            if src[i] > LIVE
              y = i / @w
              sum = 0.0
              count = 0
              [-1, 0, 1].each do |dy|
                next if y + dy < 0 || y + dy >= @h

                sum += sums[i + (dy * @w)]
                count += counts[i + (dy * @w)]
              end
              out[i] = sum / count
            end
            i += 1
          end
          out
        end

        def live?(x, y) = x >= 0 && x < @w && y >= 0 && y < @h && @zb[(y * @w) + x] > LIVE

        # Smoothed depth with the pixel's own as stand-in off the head.
        def z(x, y, own) = live?(x, y) ? @zs[(y * @w) + x] : own

        def occupancy(x, y)
          n = 0
          (-2..2).each { |dy| (-2..2).each { |dx| n += 1 if live?(x + dx, y + dy) } }
          n / 25.0
        end

        def cell(c, r)
          top = live?(c, 2 * r)
          bottom = live?(c, (2 * r) + 1)
          return unless top || bottom

          ys = [top ? 2 * r : nil, bottom ? (2 * r) + 1 : nil].compact
          edge = !(top && bottom) || !(live?(c, (2 * r) - 1) && live?(c, (2 * r) + 2)) || [c - 1, c + 1].any? { |x| !live?(x, 2 * r) && !live?(x, (2 * r) + 1) }
          glyph = edge ? silhouette(c, ys, top, bottom) : crease(c, ys)
          @frame.chars[r][c] = glyph || shade(c, r, ys)
          @frame.depth[r][c] = band(@zb[(ys.last * @w) + c])
        end

        def band(depth)
          fraction = (depth - @near_lo) / @near_span
          return 2 if fraction >= NEAR
          return 0 if fraction <= FAR

          1
        end

        def silhouette(c, ys, top, bottom)
          gx = 0.0
          gy = 0.0
          ys.each do |y|
            gx += occupancy(c + 1, y) - occupancy(c - 1, y)
            gy += occupancy(c, y + 1) - occupancy(c, y - 1)
          end
          return nil if Math.hypot(gx, gy) < EDGE

          glyph = Glyphs.line(gy, gx)
          glyph == "-" ? Glyphs.level(top, bottom, gy.negative?) : glyph
        end

        def crease(c, ys)
          xx = yy = xy = 0.0
          ys.each do |y|
            own = @zs[(y * @w) + c]
            here = own * 2
            xx += (z(c + 2, y, own) + z(c - 2, y, own) - here) / 4.0
            yy += (z(c, y + 2, own) + z(c, y - 2, own) - here) / 4.0
            xy += (z(c + 2, y + 2, own) - z(c - 2, y + 2, own) - z(c + 2, y - 2, own) + z(c - 2, y - 2, own)) / 16.0
          end
          xx /= ys.size
          yy /= ys.size
          xy /= ys.size
          half = Math.sqrt((((xx - yy) / 2)**2) + (xy * xy))
          mid = (xx + yy) / 2
          return nil if mid.abs + half < CREASE

          angle = 0.5 * Math.atan2(2 * xy, xx - yy)
          return Glyphs.line(-Math.sin(angle), -Math.cos(angle)) if (mid + half).abs >= (mid - half).abs

          Glyphs.line(-Math.cos(angle), Math.sin(angle))
        end

        def shade(c, r, ys)
          nx = ny = bright = hollow = 0.0
          ys.each do |y|
            own = @zs[(y * @w) + c]
            nx -= (z(c + 2, y, own) - z(c - 2, y, own)) / 4.0
            ny += (z(c, y + 2, own) - z(c, y - 2, own)) / 4.0
            hollow += (z(c + 2, y, own) + z(c - 2, y, own) + z(c, y + 2, own) + z(c, y - 2, own) - (4 * own)) / 16.0
            bright += @bb[(y * @w) + c]
          end
          nx /= ys.size
          ny /= ys.size
          bright /= ys.size
          hollow /= ys.size
          length = Math.sqrt((nx * nx) + (ny * ny) + 1.0)
          lum = [(((nx * LIGHT[0]) + (ny * LIGHT[1]) + LIGHT[2]) / length), 0.0].max
          tone = [((BASE + (GAIN * lum)) * (1.0 - PAINT + (PAINT * bright))) - (HOLLOW * hollow.clamp(-0.4, 0.4)), CEILING].min.clamp(0.0, 1.0)
          @ramp[Glyphs.index(tone, @ramp.size, c, r)]
        end
      end
    end
  end
end
