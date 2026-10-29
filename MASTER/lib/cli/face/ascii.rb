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
        LARGE = CONFIG.fetch("samples_large")
        COVER = CONFIG.fetch("cover").to_f
        EDGE_FADE = CONFIG.fetch("edge_fade").to_f
        EDGE = CONFIG.fetch("edge_gradient").to_f
        CREASE = CONFIG.fetch("crease").to_f
        PAINT = CONFIG.fetch("shade").fetch("paint").to_f
        CEILING = CONFIG.fetch("shade").fetch("ceiling").to_f
        GAIN = CONFIG.fetch("shade").fetch("gain").to_f
        GAMMA = CONFIG.fetch("shade").fetch("gamma").to_f
        DEPTH_EDGE = CONFIG.fetch("depth_edge").to_f
        VOTE = CONFIG.fetch("vote").to_f
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

        # Samples a side: the full count, fewer on a window big enough that the
        # cells themselves carry the detail (the cheaper path).
        def self.samples_for(rows, cols)
          rows * cols >= LARGE.fetch("cells").to_i ? LARGE.fetch("samples").to_i : SAMPLES
        end

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
          @samples = Ascii.samples_for(rows, cols)
          @per_cell = (@samples * 2 * @samples).to_f
          @sw = cols * @samples
          @sh = rows * 2 * @samples
          named_ramp = Glyphs::CONFIG.fetch("ramps", {}).fetch(ENV.fetch("MASTER_FACE_RAMP", "").to_s, Glyphs::DEFAULT_CHARS)
          chosen_chars = chars || ENV["MASTER_FACE_CHARS"] || named_ramp
          chosen_mode = mode || ENV["MASTER_FACE_MODE"] || CONFIG.fetch("mode")
          @ramp = Glyphs.ramp(chosen_chars, chosen_mode)
          @levels = Glyphs.levels(@ramp, chosen_mode)
          above, aside = @mesh.margins
          _, _, ylo, yhi, reach = @mesh.bounds
          @lift = (ylo + yhi + above) / 2.0
          @scale = [((cols / 2.0) - 1) / [reach, aside].max, ((rows * 2) - 2) / (yhi - ylo + above)].min * FIT
          @features = Features.new(@mesh)
        end

        # A short summary of the vertices as fitted, to compare two readers' input.
        def digest
          pos = @mesh.pos
          rows = Array.new(@mesh.vertex_count) do |v|
            at = 3 * v
            [pos[at], pos[at + 1] - @lift, pos[at + 2], @mesh.bright[v]]
          end
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
          x = (px * @samples).floor
          y = (py * @samples).floor
          x.between?(0, @sw - 1) && y.between?(0, @sh - 1) && @tri[(y * @sw) + x] >= 0
        end

        def hidden?(px, py, depth, slack = 0.0)
          x = (px * @samples).floor
          y = (py * @samples).floor
          return true unless x.between?(0, @sw - 1) && y.between?(0, @sh - 1)

          @zb[(y * @sw) + x] > depth + OCCLUSION + slack
        end

        private

        def turn(look)
          angles = [look.yaw + look.turn, look.pitch, look.roll]
          @cy, @sy, @cp, @sp, @cr, @sr = angles.flat_map { |a| [Math.cos(a), Math.sin(a)] }
          @camera = CAMERA / look.dolly
          @gain = @scale * look.scale
          @bob = look.bob * @scale
          orbit = look.light
          lift = Math.cos(ELEVATION)
          @key = Ascii.unit(Math.sin(orbit) * lift, Math.sin(ELEVATION), Math.cos(orbit) * lift)
          @rim = Ascii.unit(-Math.sin(orbit), 0.4, -Math.cos(orbit))
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
            at = 3 * v
            x, y, z = rotate(pos[at], pos[at + 1] - @lift, pos[at + 2])
            k = @gain * @camera / (@camera - z)
            @sx[v] = @samples * ((@cols / 2.0) + (x * k))
            @sy_[v] = @samples * (@rows - (y * k) - @bob)
            @sd[v] = z * @scale
            @nx[v], @ny[v], @nz[v] = rotate(norm[at], norm[at + 1], norm[at + 2])
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
                inside = b0 >= 0.0 && b1 >= 0.0 && b2 >= 0.0
                @zb[idx], @tri[idx], @bu[idx], @bv[idx] = z, t, b1, b2 if inside && z > @zb[idx]
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
            nx, ny, nz = Ascii.unit((b0 * @nx[i0]) + (b1 * @nx[i1]) + (b2 * @nx[i2]),
                                    (b0 * @ny[i0]) + (b1 * @ny[i1]) + (b2 * @ny[i2]),
                                    (b0 * @nz[i0]) + (b1 * @nz[i1]) + (b2 * @nz[i2]))
            paint = (b0 * bright[i0]) + (b1 * bright[i1]) + (b2 * bright[i2])
            ao = (b0 * cavity[i0]) + (b1 * cavity[i1]) + (b2 * cavity[i2])
            @lum[idx] = radiance(nx, ny, nz, paint, ao)
            facing = nz > 0.25 ? nz : 0.25
            @slope_x[idx] = -nx / facing
            @slope_y[idx] = ny / facing
          end
        end

        def radiance(nx, ny, nz, brightness, ao)
          k = (nx * @key[0]) + (ny * @key[1]) + (nz * @key[2])
          f = (nx * FILL_DIR[0]) + (ny * FILL_DIR[1]) + (nz * FILL_DIR[2])
          r = (nx * @rim[0]) + (ny * @rim[1]) + (nz * @rim[2])
          direct = AMBIENT + (KEY * (k > 0.0 ? k : 0.0)) + (FILL * (f > 0.0 ? f : 0.0)) + (RIM * (r > 0.0 ? r : 0.0))
          lum = direct * (1.0 - PAINT + (PAINT * brightness))
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
              (0...(2 * @samples)).each do |dy|
                base = (((r * 2 * @samples) + dy) * @sw) + (c * @samples)
                @samples.times do |dx|
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

        def coverage(c, r) = c >= 0 && c < @cols && r >= 0 && r < @rows ? @count[(r * @cols) + c] / @per_cell : 0.0

        def cell(c, r)
          i = (r * @cols) + c
          cover = @count[i] / @per_cell
          return if cover < COVER

          edge = (c > 0 && coverage(c - 1, r) < COVER) || (c < @cols - 1 && coverage(c + 1, r) < COVER) ||
                 (r > 0 && coverage(c, r - 1) < COVER) || (r < @rows - 1 && coverage(c, r + 1) < COVER)
          fraction = depth_at(i)
          glyph = edge ? silhouette(c, r) : (step(c, r, fraction) || crease(c, r))
          @frame.chars[r][c] = glyph || shade(c, r, i, cover, fraction)
          @frame.depth[r][c] = if fraction >= NEAR
                                 2
                               elsif fraction <= FAR
                                 0
                               else
                                 1
                               end
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
          return if Math.hypot(gx, gy) < EDGE

          glyph = Glyphs.line(gy, gx)
          return glyph unless glyph == "-"

          top, bottom = halves(c, r)
          Glyphs.level(top, bottom, gy.negative?)
        end

        # Whether the cell's upper and lower halves are mostly covered.
        def halves(c, r)
          covered = [0, 0]
          (0...(2 * @samples)).each do |dy|
            base = (((r * 2 * @samples) + dy) * @sw) + (c * @samples)
            @samples.times { |dx| covered[dy / @samples] += 1 unless @tri[base + dx].negative? }
          end
          covered.map { |n| n >= @samples * @samples / 2.0 }
        end

        # A cell's mean depth as a fraction of the visible range.
        def depth_at(i) = ((@depth_sum[i] / @count[i]) - @near_lo) / @near_span

        # An occluding step inside the surface (a nose against the cheek behind
        # it, the jaw against the neck): the depth jumps by more than depth_edge
        # to a neighbouring cell. The line runs across the depth gradient, found
        # as the silhouette's is, a row being two square sub-pixels tall.
        def step(c, r, fraction)
          jump = 0.0
          here = (r * @cols) + c
          jump = [jump, (depth_at(here - 1) - fraction).abs].max if c > 0 && @count[here - 1].positive?
          jump = [jump, (depth_at(here + 1) - fraction).abs].max if c < @cols - 1 && @count[here + 1].positive?
          jump = [jump, (depth_at(here - @cols) - fraction).abs].max if r > 0 && @count[here - @cols].positive?
          jump = [jump, (depth_at(here + @cols) - fraction).abs].max if r < @rows - 1 && @count[here + @cols].positive?
          return if jump < DEPTH_EDGE

          gx = depth_gradient(c - 1, r, c + 1, r, fraction)
          gy = depth_gradient(c, r - 1, c, r + 1, fraction) / 2.0
          return if gx.zero? && gy.zero?

          Glyphs.line(gy, gx)
        end

        # The depth difference across a pair of cells, a missing one standing in
        # as the cell itself.
        def depth_gradient(c0, r0, c1, r1, fraction)
          lo = c0 >= 0 && c0 < @cols && r0 >= 0 && r0 < @rows && @count[(r0 * @cols) + c0].positive? ? depth_at((r0 * @cols) + c0) : fraction
          hi = c1 >= 0 && c1 < @cols && r1 >= 0 && r1 < @rows && @count[(r1 * @cols) + c1].positive? ? depth_at((r1 * @cols) + c1) : fraction
          hi - lo
        end

        # Where the surface's slope changes: every covered sample whose four
        # neighbours are covered too reads the change of slope across itself
        # (its tensor, central differences, a sample being square) and, if the
        # larger |eigenvalue| (scaled to a cell's width) reaches `crease`, votes
        # for the glyph of the ridge's direction. The cell takes the glyph with
        # most votes when they are at least `vote` of its covered samples.
        def crease(c, r)
          horizontal = diagonal_up = vertical = diagonal_down = 0
          seen = 0
          (0...(2 * @samples)).each do |dy|
            y = (r * 2 * @samples) + dy
            next if y.zero? || y >= @sh - 1

            (0...@samples).each do |dx|
              x = (c * @samples) + dx
              idx = (y * @sw) + x
              next if @tri[idx].negative?

              seen += 1
              next if x.zero? || x >= @sw - 1

              l = idx - 1
              rt = idx + 1
              u = idx - @sw
              d = idx + @sw
              next if @tri[l].negative? || @tri[rt].negative? || @tri[u].negative? || @tri[d].negative?

              xx = (@slope_x[rt] - @slope_x[l]) / 2.0
              yy = (@slope_y[d] - @slope_y[u]) / 2.0
              xy = (((@slope_y[rt] - @slope_y[l]) + (@slope_x[d] - @slope_x[u])) / 4.0)
              spread = (xx - yy) / 2
              half = Math.sqrt((spread * spread) + (xy * xy))
              mid = (xx + yy) / 2
              major = mid + half
              minor = mid - half
              next if @samples * [major.abs, minor.abs].max < CREASE

              angle = 0.5 * Math.atan2(2 * xy, xx - yy)
              case major.abs >= minor.abs ? Glyphs.line(-Math.sin(angle), -Math.cos(angle)) : Glyphs.line(-Math.cos(angle), Math.sin(angle))
              when "-" then horizontal += 1
              when "/" then diagonal_up += 1
              when "|" then vertical += 1
              else diagonal_down += 1
              end
            end
          end
          return if seen.zero?

          # Ties go to the glyph later in character order, as a port's sort would.
          votes, glyph = [[horizontal, "-"], [diagonal_up, "/"], [diagonal_down, "\\"], [vertical, "|"]].max
          votes >= VOTE * seen && votes.positive? ? glyph : nil
        end

        def shade(c, r, i, cover, fraction)
          tone = GAIN * (@lum_sum[i] / @count[i]) * (1.0 - EDGE_FADE + (EDGE_FADE * cover))
          tone = (tone.clamp(0.0, CEILING)**GAMMA) + (DEPTH_TONE * (fraction - 0.5))
          @ramp[Glyphs.index(tone.clamp(0.0, 1.0), @levels, c, r)]
        end
      end
    end
  end
end
