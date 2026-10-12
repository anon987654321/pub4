# frozen_string_literal: true

module Master
  module CLI
    module Face
      # Any model the ASCII renderer can show: an ASCII STL or an OBJ read into
      # triangles and sampled into points, so a city block or an extruded
      # wordmark turns in the same ink as the head. Centred on its bounding box;
      # y is up (pass up: :z for the CAD convention).
      class Mesh
        BRIGHTNESS = 0.8
        ACROSS = 90

        def self.parse(text, up: :y)
          triangles = text.match?(/^\s*solid\b/i) && text.match?(/^\s*vertex\b/i) ? stl(text) : obj(text)
          raise ArgumentError, "mesh: no triangles found" if triangles.empty?

          new(triangles, up:)
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

        attr_reader :triangles

        def initialize(triangles, up: :y)
          triangles = triangles.map { |t| t.map { |x, y, z| up == :z ? [x, z, -y] : [x, y, z] } }
          flat = triangles.flatten(1)
          mid = [0, 1, 2].map { |a| flat.map { |v| v[a] }.minmax.sum / 2.0 }
          @triangles = triangles.map { |t| t.map { |v| [v[0] - mid[0], v[1] - mid[1], v[2] - mid[2]] } }
          longest = [0, 1, 2].map { |a| flat.map { |v| v[a] }.minmax.then { |lo, hi| hi - lo } }.max
          @step = longest / ACROSS.to_f
          @points = sample
        end

        def each_point
          @points.each { |x, y, z| yield x, y, z, BRIGHTNESS, 0, 0.0 }
        end

        private

        def sample
          @triangles.flat_map do |a, b, c|
            n = [[a, b], [b, c], [c, a]].map { |p, q| Math.sqrt(p.zip(q).sum { |u, v| (u - v)**2 }) }.max.fdiv(@step).ceil.clamp(1, 400)
            (0..n).flat_map do |i|
              (0..(n - i)).map do |j|
                u = i.fdiv(n)
                v = j.fdiv(n)
                w = 1.0 - u - v
                [0, 1, 2].map { |k| (a[k] * w) + (b[k] * u) + (c[k] * v) }
              end
            end
          end
        end
      end
    end
  end
end
