# frozen_string_literal: true

require "digest"

module Master
  module CLI
    module Face
      # A triangle mesh rasterised in software and drawn in plain ASCII: a
      # z-buffered, lit, supersampled picture reduced to one character a cell.
      # Contours (| - / \ and the half-cell ' _) are overlaid only where the
      # surface ends or creases, the ink ramp carries the shading, features are
      # glyphs on top, and depth is bold and dim. The steps, in order, are
      # written in data/tokens.yml beside the numbers (face_interface.ascii);
      # the web face ports them.
      #
      # A frame is a pure function of the mesh, the size and the Look: no
      # randomness, floor() for every index, so two readers agree to the cell.
      class Ascii
        CONFIG = Glyphs::CONFIG
        CAMERA = CONFIG.fetch("camera").to_f
        FIT = CONFIG.fetch("fit").to_f
        SAMPLES = CONFIG.fetch("samples").to_i
        PER_CELL = (SAMPLES * 2 * SAMPLES).to_f
        COVER = CONFIG.fetch("cover").to_f
        EDGE_FADE = CONFIG.fetch("edge_fade").to_f
        EDGE = CONFIG.fetch("edge_gradient").to_f
        CREASE = CONFIG.fetch("crease").to_f
        PAINT = CONFIG.fetch("shade").fetch("paint").to_f
        CEILING = CONFIG.fetch("shade").fetch("ceiling").to_f
        GAIN = CONFIG.fetch("shade").fetch("gain").to_f
        KNEE = CONFIG.fetch("shade").fetch("knee").to_f
        SHOULDER = CONFIG.fetch("shade").fetch("shoulder").to_f
        NEAR, FAR, DEPTH_TONE = CONFIG.fetch("depth").values_at("near", "far", "tone").map(&:to_f)
        OCCLUSION = CONFIG.fetch("occlusion").to_f
        FACING = CONFIG.fetch("facing").to_f
        LIGHT = CONFIG.fetch("light")
        ELEVATION = LIGHT.fetch("elevation").to_f
        AMBIENT, KEY, FILL, RIM, SPEC = %w[ambient key fill rim spec].map { |k| LIGHT.fetch(k).to_f }
        # Shininess is a power of two, taken by squaring this many times.
        SQUARINGS = LIGHT.fetch("shininess").to_i.bit_length - 1
        NONE = -1.0e9
        LIVE = NONE / 2

        def self.unit(x, y, z)
          length = Math.sqrt((x * x) + (y * y) + (z * z))
          [x / length, y / length, z / length].freeze
        end

        FILL_DIR = unit(*LIGHT.fetch("fill_dir").map(&:to_f))

        # The source answers #mesh: a Head or a Mesh does.
        def initialize(source, rows, cols, chars: nil, mode: nil)
          @mesh = source.mesh
          @rows = rows
          @cols = cols
          @sw = cols * SAMPLES
          @sh = rows * 2 * SAMPLES
          @ramp = Glyphs.ramp(chars || ENV["MASTER_FACE_CHARS"] || Glyphs::DEFAULT_CHARS, mode || ENV["MASTER_FACE_MODE"] || CONFIG.fetch("mode"))
          above, aside = @mesh.margins
          _, _, ylo, yhi, reach = @mesh.bounds
          @lift = (ylo + yhi + above) / 2.0
          @scale = [((cols / 2.0) - 1) / [reach, aside].max, ((rows * 2) - 2) / (yhi - ylo + above)].min * FIT
          @features = Features.new(@mesh)
        end

        # A short summary of the vertices as fitted, to compare two readers' input.
        def digest
          pos = @mesh.pos
          rows = Array.new(@mesh.vertex_count) { |v| [pos[3 * v], pos[(3 * v) + 1] - @lift, pos[(3 * v) + 2], @mesh.bright[v]] }
          Digest::SHA256.hexdigest(rows.map { |p| p.map { |v| format("%.4f", v) }.join(",") }.join(";"))[0, 16]
        end

        def render(look, state: :idle, laws: [])
          turn(look)
          transform
          raster
          light
          measure
          @frame = Frame.new(Array.new(@rows) { Array.new(@cols, " ") }, Array.new(@rows) { Array.new(@cols, 1) })
          @rows.times { |r| @cols.times { |c| cell(c, r) } }
          @features.draw(self, @frame, look, state)
          law_ring(laws)
          @frame
        end

        # Each glyph is a constitutional landmark, placed outside the face.
        # Existing contour and feature cells own their positions.
        def law_ring(laws)
          return if laws.empty? || @rows < 8 || @cols < 16

          cx = (@cols - 1) / 2.0
          cy = (@rows - 1) / 2.0
          rx = @cols * 0.47
          ry = @rows * 0.45
          laws.each_with_index do |law, index|
            angle = (-Math::PI / 2) + ((Math::PI * 2 * index) / laws.size)
            col = (cx + (Math.cos(angle) * rx)).round
            row = (cy + (Math.sin(angle) * ry)).round
            next unless row.between?(0, @rows - 1) && col.between?(0, @cols - 1)
            next unless @frame.chars[row][col] == " "

            glyph = law.fetch("glyph", "").to_s.chars.first
            next if glyph.nil? || glyph.empty?

            @frame.chars[row][col] = glyph
            @frame.depth[row][col] = 1
          end
        end

        # Sub-pixels per source unit, as fitted.
        attr_reader :scale

        # A source-space point in sub-pixels (a cell is one wide and two tall),
        # and its depth in the same units.
        def project(x, y, z)
          rx, ry, rz = rotate(x, y - @lift, z)
          k = @gain * @camera / (@camera - rz)
          [(@cols / 2.0) + (rx * k), @rows - (ry * k) - @bob, rz * @scale]
        end

        # Whether a landmark's side of the head, from the axis out through it, is
        # turned toward the viewer: a feature at the limb is not seen.
        def facing?(x, z)
          reach = Math.sqrt((x * x) + (z * z))
          reach.zero? || rotate(x, 0.0, z)[2] / reach >= FACING
        end

        # slack lets a feature that stands off the surface (a ring round a raised
        # beak) count as seen where the surface is a little nearer.
        def covered?(px, py)
          x = (px * SAMPLES).floor
          y = (py * SAMPLES).floor
          x.between?(0, @sw - 1) && y.between?(0, @sh - 1) && @tri[(y * @sw) + x] >= 0
        end

        def hidden?(px, py, depth, slack = 0.0)
          x = (px * SAMPLES).floor
          y = (py * SAMPLES).floor
          return true unless x.between?(0, @sw - 1) && y.between?(0, @sh - 1)

          @zb[(y * @sw) + x] > depth + OCCLUSION + slack
        end

        private

        def turn(look)
          @cy, @sy, @cp, @sp, @cr, @sr = [look.yaw + look.turn, look.pitch, look.roll].flat_map { |a| [Math.cos(a), Math.sin(a)] }
          @camera = CAMERA / look.dolly
          @gain = @scale * look.scale
          @bob = look.bob * @scale
          @key = Ascii.unit(Math.sin(look.light) * Math.cos(ELEVATION), Math.sin(ELEVATION), Math.cos(look.light) * Math.cos(ELEVATION))
          @rim = Ascii.unit(-Math.sin(look.light), 0.4, -Math.cos(look.light))
          @half = Ascii.unit(@key[0], @key[1], @key[2] + 1.0)
        end

        # Yaw, then pitch, then roll: x right, y up, z toward the viewer.
        def rotate(x, y, z)
          a = (x * @cy) + (z * @sy)
          b = (-x * @sy) + (z * @cy)
          y2 = (y * @cp) - (b * @sp)
          [(a * @cr) - (y2 * @sr), (a * @sr) + (y2 * @cr), (y * @sp) + (b * @cp)]
        end

        # Every vertex and normal turned, and the vertices in the sample grid:
        # sample columns run right and rows down, depth is larger nearer.
        def transform
          pos = @mesh.pos
          norm = @mesh.normals
          @sx, @sy_, @sd, @nx, @ny, @nz = Array.new(6) { Array.new(@mesh.vertex_count) }
          @mesh.vertex_count.times do |v|
            x, y, z = rotate(pos[3 * v], pos[(3 * v) + 1] - @lift, pos[(3 * v) + 2])
            k = @gain * @camera / (@camera - z)
            @sx[v] = SAMPLES * ((@cols / 2.0) + (x * k))
            @sy_[v] = SAMPLES * (@rows - (y * k) - @bob)
            @sd[v] = z * @scale
            @nx[v], @ny[v], @nz[v] = rotate(norm[3 * v], norm[(3 * v) + 1], norm[(3 * v) + 2])
          end
        end

        # Edge functions at sample centres, largest depth wins and the first
        # triangle keeps a tie. A sample keeps its triangle and two weights.
        def raster
          total = @sw * @sh
          @zb = Array.new(total, NONE)
          @tri = Array.new(total, -1)
          @bu, @bv = Array.new(2) { Array.new(total, 0.0) }
          @mesh.triangle_count.times do |t|
            i0, i1, i2 = @mesh.tris[3 * t, 3]
            x0, y0, z0 = @sx[i0], @sy_[i0], @sd[i0]
            x1, y1, z1 = @sx[i1], @sy_[i1], @sd[i1]
            x2, y2, z2 = @sx[i2], @sy_[i2], @sd[i2]
            area = ((x1 - x0) * (y2 - y0)) - ((x2 - x0) * (y1 - y0))
            next unless area < -1.0e-9

            inv = 1.0 / area
            cols = [([x0, x1, x2].min - 0.5).ceil, 0].max..[([x0, x1, x2].max - 0.5).floor, @sw - 1].min
            rows = [([y0, y1, y2].min - 0.5).ceil, 0].max..[([y0, y1, y2].max - 0.5).floor, @sh - 1].min
            rows.each do |j|
              py = j + 0.5
              px = cols.begin + 0.5
              e0 = ((x2 - x1) * (py - y1)) - ((y2 - y1) * (px - x1))
              e1 = ((x0 - x2) * (py - y2)) - ((y0 - y2) * (px - x2))
              e2 = ((x1 - x0) * (py - y0)) - ((y1 - y0) * (px - x0))
              cols.each do |i|
                b0 = e0 * inv
                b1 = e1 * inv
                b2 = e2 * inv
                idx = (j * @sw) + i
                z = (b0 * z0) + (b1 * z1) + (b2 * z2)
                @zb[idx], @tri[idx], @bu[idx], @bv[idx] = z, t, b1, b2 if b0 >= 0.0 && b1 >= 0.0 && b2 >= 0.0 && z > @zb[idx]
                e0 += y1 - y2
                e1 += y2 - y0
                e2 += y0 - y1
              end
            end
          end
        end

        # Light every covered sample and keep its luminance and the slope of its
        # surface (z against x and against y down), which creases are found in.
        def light
          total = @sw * @sh
          @lum, @slope_x, @slope_y = Array.new(3) { Array.new(total, 0.0) }
          tris = @mesh.tris
          bright = @mesh.bright
          cavity = @mesh.cavity
          total.times do |idx|
            t = @tri[idx]
            next if t.negative?

            b1 = @bu[idx]
            b2 = @bv[idx]
            b0 = 1.0 - b1 - b2
            i0, i1, i2 = tris[3 * t, 3]
            nx, ny, nz = Ascii.unit((b0 * @nx[i0]) + (b1 * @nx[i1]) + (b2 * @nx[i2]), (b0 * @ny[i0]) + (b1 * @ny[i1]) + (b2 * @ny[i2]),
                                    (b0 * @nz[i0]) + (b1 * @nz[i1]) + (b2 * @nz[i2]))
            @lum[idx] = radiance(nx, ny, nz, (b0 * bright[i0]) + (b1 * bright[i1]) + (b2 * bright[i2]), (b0 * cavity[i0]) + (b1 * cavity[i1]) + (b2 * cavity[i2]))
            facing = nz > 0.25 ? nz : 0.25
            @slope_x[idx] = -nx / facing
            @slope_y[idx] = ny / facing
          end
        end

        def radiance(nx, ny, nz, brightness, ao)
          k = (nx * @key[0]) + (ny * @key[1]) + (nz * @key[2])
          f = (nx * FILL_DIR[0]) + (ny * FILL_DIR[1]) + (nz * FILL_DIR[2])
          r = (nx * @rim[0]) + (ny * @rim[1]) + (nz * @rim[2])
          lum = (AMBIENT + (KEY * (k > 0.0 ? k : 0.0)) + (FILL * (f > 0.0 ? f : 0.0)) + (RIM * (r > 0.0 ? r : 0.0))) * (1.0 - PAINT + (PAINT * brightness))
          if k > 0.0
            h = (nx * @half[0]) + (ny * @half[1]) + (nz * @half[2])
            if h > 0.0
              SQUARINGS.times { h *= h }
              lum += SPEC * h
            end
          end
          lum * (1.0 - ao)
        end

        # Per cell: covered samples, their luminance and depth summed; and the
        # depth range of everything seen.
        def measure
          @count = Array.new(@rows * @cols, 0)
          @lum_sum = Array.new(@rows * @cols, 0.0)
          @depth_sum = Array.new(@rows * @cols, 0.0)
          lo = Float::INFINITY
          hi = -Float::INFINITY
          @rows.times do |r|
            @cols.times do |c|
              cell = (r * @cols) + c
              (0...(2 * SAMPLES)).each do |dy|
                base = (((r * 2 * SAMPLES) + dy) * @sw) + (c * SAMPLES)
                SAMPLES.times do |dx|
                  next if @tri[base + dx].negative?

                  d = @zb[base + dx]
                  @count[cell] += 1
                  @lum_sum[cell] += @lum[base + dx]
                  @depth_sum[cell] += d
                  lo = d if d < lo
                  hi = d if d > hi
                end
              end
            end
          end
          @near_lo = lo == Float::INFINITY ? 0.0 : lo
          @near_span = [(hi == -Float::INFINITY ? 0.0 : hi) - @near_lo, 1.0].max
        end

        def coverage(c, r) = c >= 0 && c < @cols && r >= 0 && r < @rows ? @count[(r * @cols) + c] / PER_CELL : 0.0

        def cell(c, r)
          i = (r * @cols) + c
          cover = @count[i] / PER_CELL
          return if cover < COVER

          edge = [[c - 1, r], [c + 1, r], [c, r - 1], [c, r + 1]].any? { |x, y| x >= 0 && x < @cols && y >= 0 && y < @rows && coverage(x, y) < COVER }
          glyph = edge ? silhouette(c, r) : crease(c, r)
          fraction = ((@depth_sum[i] / @count[i]) - @near_lo) / @near_span
          @frame.chars[r][c] = glyph || shade(c, r, i, cover, fraction)
          @frame.depth[r][c] = fraction >= NEAR ? 2 : (fraction <= FAR ? 0 : 1)
        end

        # The glyph for the cell's boundary, from the gradient of coverage over
        # the 3x3 cells (a row being two square sub-pixels tall).
        def silhouette(c, r)
          gx = 0.0
          gy = 0.0
          [-1, 0, 1].each do |d|
            weight = d.zero? ? 2.0 : 1.0
            gx += weight * (coverage(c + 1, r + d) - coverage(c - 1, r + d))
            gy += weight * (coverage(c + d, r + 1) - coverage(c + d, r - 1))
          end
          gy /= 2.0
          return nil if Math.hypot(gx, gy) < EDGE

          glyph = Glyphs.line(gy, gx)
          return glyph unless glyph == "-"

          top, bottom = halves(c, r)
          Glyphs.level(top, bottom, gy.negative?)
        end

        # Whether the cell's upper and lower halves are mostly covered.
        def halves(c, r)
          covered = [0, 0]
          (0...(2 * SAMPLES)).each do |dy|
            base = (((r * 2 * SAMPLES) + dy) * @sw) + (c * SAMPLES)
            SAMPLES.times { |dx| covered[dy / SAMPLES] += 1 unless @tri[base + dx].negative? }
          end
          covered.map { |n| n >= SAMPLES * SAMPLES / 2.0 }
        end

        # Where the surface's slope changes across the cell: the ridge's
        # direction from the larger |eigenvalue| of that change.
        def crease(c, r)
          return nil if SAMPLES < 2

          sums = Array.new(4) { [0, 0.0, 0.0] }
          (0...(2 * SAMPLES)).each do |dy|
            base = (((r * 2 * SAMPLES) + dy) * @sw) + (c * SAMPLES)
            SAMPLES.times do |dx|
              next if @tri[base + dx].negative?

              sum = sums[(dx * 2 / SAMPLES) + (2 * (dy / SAMPLES))]
              sum[0] += 1
              sum[1] += @slope_x[base + dx]
              sum[2] += @slope_y[base + dx]
            end
          end
          return nil if sums.any? { |n, *| n.zero? }

          lt, rt, lb, rb = sums
          mean = ->(u, v, k) { (u[k] + v[k]) / (u[0] + v[0]) }
          pl, ql, pr, qr = mean[lt, lb, 1], mean[lt, lb, 2], mean[rt, rb, 1], mean[rt, rb, 2]
          pt, pb = mean[lt, rt, 1], mean[lb, rb, 1]
          qt, qb = mean[lt, rt, 2], mean[lb, rb, 2]
          xx = pr - pl
          yy = qb - qt
          xy = ((qr - ql) + (pb - pt)) / 2.0
          spread = (xx - yy) / 2
          half = Math.sqrt((spread * spread) + (xy * xy))
          mid = (xx + yy) / 2
          return nil if mid.abs + half < CREASE

          angle = 0.5 * Math.atan2(2 * xy, xx - yy)
          return Glyphs.line(-Math.sin(angle), -Math.cos(angle)) if (mid + half).abs >= (mid - half).abs

          Glyphs.line(-Math.cos(angle), Math.sin(angle))
        end

        def shade(c, r, i, cover, fraction)
          tone = GAIN * (@lum_sum[i] / @count[i]) * (1.0 - EDGE_FADE + (EDGE_FADE * cover))
          tone = KNEE + ((tone - KNEE) * SHOULDER) if tone > KNEE
          tone = [tone, CEILING].min + (DEPTH_TONE * (fraction - 0.5))
          @ramp[Glyphs.index(tone.clamp(0.0, 1.0), @ramp.size, c, r)]
        end
      end
    end
  end
end
