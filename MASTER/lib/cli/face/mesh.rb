# frozen_string_literal: true

module Master
  module CLI
    module Face
      # An indexed triangle mesh, outward wound, as the rasteriser takes it: the
      # head is one, and so is any model read from a file (an ASCII STL or an
      # OBJ, so a city block or an extruded wordmark turns in the same light).
      # Flat arrays of positions (x, y, z), vertex brightness and triangle
      # corners, with the landmarks and mask numbers a head carries. Normals
      # and cavity are derived once and kept; a morph makes a new Mesh.
      class Mesh
        BRIGHTNESS = 0.8
        GAIN = Glyphs::CONFIG.fetch("cavity").fetch("gain").to_f

        attr_reader :pos, :tris, :bright, :landmarks, :params, :margins

        def initialize(pos, tris, bright, landmarks: nil, params: nil, margins: [0.0, 0.0])
          @pos = pos
          @tris = tris
          @bright = bright
          @landmarks = landmarks
          @params = params
          @margins = margins
        end

        def mesh = self
        def vertex_count = @pos.size / 3
        def triangle_count = @tris.size / 3

        # A model read from text, centred on its bounding box; y is up (pass
        # up: :z for the CAD convention). Its winding is made outward by the
        # sign of its volume. Every triangle has vertices of its own, so its
        # normals are the faces' and it is shaded flat.
        def self.parse(text, up: :y)
          triangles = text.match?(/^\s*solid\b/i) && text.match?(/^\s*vertex\b/i) ? stl(text) : obj(text)
          raise ArgumentError, "mesh: no triangles found" if triangles.empty?

          triangles = triangles.map { |t| t.map { |x, y, z| up == :z ? [x, z, -y] : [x, y, z] } }
          flat = triangles.flatten(1)
          mid = [0, 1, 2].map { |a| flat.map { |v| v[a] }.minmax.sum / 2.0 }
          pos = flat.flat_map { |v| [v[0] - mid[0], v[1] - mid[1], v[2] - mid[2]] }
          tris = Array.new(triangles.size * 3) { |i| i }
          bright = Array.new(flat.size, BRIGHTNESS)
          made = new(pos, tris, bright)
          made.volume.negative? ? new(pos, tris.each_slice(3).flat_map { |a, b, c| [a, c, b] }, bright) : made
        end

        def self.read(path, up: :y) = parse(File.read(path), up:)

        def self.stl(text)
          text.scan(/^\s*vertex\s+(\S+)\s+(\S+)\s+(\S+)/i).map { |v| v.map(&:to_f) }.each_slice(3).select { |t| t.size == 3 }
        end

        def self.obj(text)
          verts = text.scan(/^v\s+(\S+)\s+(\S+)\s+(\S+)/).map { |v| v.map(&:to_f) }
          text.scan(/^f\s+(.+)$/).flat_map do |(line)|
            ids = line.split.map { |ref| (i = ref.split("/").first.to_i).negative? ? verts.size + i : i - 1 }
            (1...(ids.size - 1)).map { |k| [verts[ids[0]], verts[ids[k]], verts[ids[k + 1]]] }
          end
        end

        # The vertices of a and b blended by e, on a's triangles; the landmarks
        # and margins follow, the numbers are the caller's.
        def self.morph(a, b, e, params:)
          pos = a.pos.each_with_index.map { |v, i| v + ((b.pos[i] - v) * e) }
          bright = a.bright.each_with_index.map { |v, i| v + ((b.bright[i] - v) * e) }
          new(pos, a.tris, bright, landmarks: blend(a.landmarks, b.landmarks, e), params:, margins: blend(a.margins, b.margins, e))
        end

        def self.blend(a, b, e)
          case a
          when Hash then a.to_h { |k, v| [k, blend(v, b.fetch(k), e)] }
          when Array then a.each_with_index.map { |v, i| blend(v, b[i], e) }
          else a + ((b - a) * e)
          end
        end

        # [xmin, xmax, ymin, ymax, reach]: the box in x and y and the largest
        # hypot(x, z).
        def bounds
          @bounds ||= begin
            lo = [Float::INFINITY, Float::INFINITY]
            hi = [-Float::INFINITY, -Float::INFINITY]
            reach = 0.0
            i = 0
            while i < @pos.size
              x = @pos[i]
              y = @pos[i + 1]
              lo[0] = x if x < lo[0]
              hi[0] = x if x > hi[0]
              lo[1] = y if y < lo[1]
              hi[1] = y if y > hi[1]
              d = Math.sqrt((x * x) + (@pos[i + 2] * @pos[i + 2]))
              reach = d if d > reach
              i += 3
            end
            [lo[0], hi[0], lo[1], hi[1], reach].freeze
          end
        end

        # Unit vertex normals: the area-weighted mean of the faces round each.
        def normals
          @normals ||= begin
            n = Array.new(@pos.size, 0.0)
            each_triangle do |a, b, c|
              fx, fy, fz = face(a, b, c)
              [a, b, c].each do |v|
                n[v] += fx
                n[v + 1] += fy
                n[v + 2] += fz
              end
            end
            i = 0
            while i < n.size
              len = Math.sqrt((n[i] * n[i]) + (n[i + 1] * n[i + 1]) + (n[i + 2] * n[i + 2]))
              len = 1.0 if len.zero?
              n[i] /= len
              n[i + 1] /= len
              n[i + 2] /= len
              i += 3
            end
            n
          end
        end

        # 0..1 per vertex: how far the neighbours' mean stands out along the
        # normal, over the squared edge length, times the contract's gain.
        def cavity
          @cavity ||= concavity
        end

        # The face normal (unnormalised, twice the area) of a corner triple.
        def face(a, b, c)
          ux = @pos[b] - @pos[a]
          uy = @pos[b + 1] - @pos[a + 1]
          uz = @pos[b + 2] - @pos[a + 2]
          vx = @pos[c] - @pos[a]
          vy = @pos[c + 1] - @pos[a + 1]
          vz = @pos[c + 2] - @pos[a + 2]
          [(uy * vz) - (uz * vy), (uz * vx) - (ux * vz), (ux * vy) - (uy * vx)]
        end

        # Six times the enclosed volume; positive when the winding is outward.
        def volume
          sum = 0.0
          each_triangle do |a, b, c|
            sum += (@pos[a] * ((@pos[b + 1] * @pos[c + 2]) - (@pos[b + 2] * @pos[c + 1]))) -
                   (@pos[a + 1] * ((@pos[b] * @pos[c + 2]) - (@pos[b + 2] * @pos[c]))) +
                   (@pos[a + 2] * ((@pos[b] * @pos[c + 1]) - (@pos[b + 1] * @pos[c])))
          end
          sum
        end

        private

        def concavity
          sums = Array.new(@pos.size, 0.0)
          deg = Array.new(vertex_count, 0)
          edge2 = Array.new(vertex_count, 0.0)
          each_triangle do |a, b, c|
            [[a, b, c], [b, c, a], [c, a, b]].each do |v, p, q|
              3.times { |k| sums[v + k] += @pos[p + k] + @pos[q + k] }
              deg[v / 3] += 2
              edge2[v / 3] += dist2(v, p) + dist2(v, q)
            end
          end
          n = normals
          Array.new(vertex_count) do |v|
            d = deg[v]
            next 0.0 if d.zero?

            out = 0.0
            3.times { |k| out += ((sums[(3 * v) + k] / d) - @pos[(3 * v) + k]) * n[(3 * v) + k] }
            (GAIN * out / (edge2[v] / d)).clamp(0.0, 1.0)
          end
        end

        def each_triangle
          i = 0
          while i < @tris.size
            yield @tris[i] * 3, @tris[i + 1] * 3, @tris[i + 2] * 3
            i += 3
          end
        end

        def dist2(a, b)
          dx = @pos[a] - @pos[b]
          dy = @pos[a + 1] - @pos[b + 1]
          dz = @pos[a + 2] - @pos[b + 2]
          (dx * dx) + (dy * dy) + (dz * dz)
        end
      end
    end
  end
end
