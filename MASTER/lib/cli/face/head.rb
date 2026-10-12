# frozen_string_literal: true

require_relative "../../face"

module Master
  module CLI
    module Face
      # The head as a closed triangle mesh. Each of the window's rings is an
      # ellipse of vertices round the head, front at angle 0, whose front half
      # is lifted by the painted relief (DepthMap, the painting the web face
      # samples its particles from), so the eyes sink and the nose stands. The
      # rings' widths follow the painting's own face ellipse: a skull above its
      # widest row and a jaw below it; two poles close the top and bottom. The
      # grid is as fine as the window's cells can show and is built once per
      # window size and kept; a mask (Face::Masks) is the same grid under other
      # numbers, so every mask shares its topology and a morph is vertex
      # interpolation.
      class Head
        SPREAD = 0.62
        MORPHOLOGY = Master::Face::Contract.spatial.fetch("morphology", {}).freeze
        CRANIUM_SCALE = MORPHOLOGY.fetch("cranium_scale", 1.18).to_f
        CRANIAL_WIDTH = MORPHOLOGY.fetch("cranial_width", 1.06).to_f
        CRANIAL_HEIGHT = MORPHOLOGY.fetch("cranial_height", 1.04).to_f
        UPPER_FACE_SCALE = MORPHOLOGY.fetch("upper_face_scale", 0.96).to_f
        LOWER_FACE_SCALE = MORPHOLOGY.fetch("lower_face_scale", 0.80).to_f
        FACIAL_VERTICALIZATION = MORPHOLOGY.fetch("facial_verticalization", 1.04).to_f
        MASTICATORY_SCALE = MORPHOLOGY.fetch("masticatory_scale", 0.78).to_f
        ORBITAL_SCALE = MORPHOLOGY.fetch("orbital_scale", 1.10).to_f
        ORBITAL_VERTICAL_SCALE = MORPHOLOGY.fetch("orbital_vertical_scale", 1.06).to_f
        BROW_SCALE = MORPHOLOGY.fetch("brow_scale", 0.66).to_f
        NOSE_SCALE = MORPHOLOGY.fetch("nose_scale", 0.86).to_f
        NASAL_PROJECTION = MORPHOLOGY.fetch("nasal_projection", NOSE_SCALE).to_f
        JAW_PROJECTION = MORPHOLOGY.fetch("jaw_projection", 0.80).to_f
        JAW_SOFTENING = MORPHOLOGY.fetch("jaw_softening", 0.92).to_f
        MALAR_SCALE = MORPHOLOGY.fetch("malar_scale", 0.94).to_f
        PUPIL_SCALE = MORPHOLOGY.fetch("pupil_scale", 0.88).to_f
        ASYMMETRY = MORPHOLOGY.fetch("asymmetry", 0.010).to_f
        ASYMMETRY_SEED = MORPHOLOGY.fetch("asymmetry_seed", 73_421).to_i
        # The far-future profile keeps the human silhouette but shifts mass
        # upward and inward: fuller vault, compact lower face, shallow brow,
        # restrained nasal projection and a slightly deeper orbital field.
        # The contract owns the numbers so browser and terminal cannot drift.
        CACHE_LIMIT = 8
        # Where the eyes and the mouth sit in the depth map's own space, and how
        # far each reaches: the painted socket, the painted pupil, and the lips.
        EYES = [-1, 1].map do |side|
          bias = Math.sin((ASYMMETRY_SEED * 0.0001) + (side * 17.17) + MORPHOLOGY.fetch("generation", 0).to_f * 0.71)
          ex = (0.118 * ORBITAL_SCALE * side) + (side * ASYMMETRY * bias * 0.12)
          [((((DepthMap::CX + ex) * 2) - 1) * SPREAD), -((((DepthMap::CY - 0.088) * 2) - 1) * SPREAD)]
        end.freeze
        SOCKET = [0.187 * ORBITAL_SCALE, 0.142 * ORBITAL_SCALE * ORBITAL_VERTICAL_SCALE].freeze
        PUPIL = 0.07 * PUPIL_SCALE
        MOUTH = [(((DepthMap::CX * 2) - 1) * SPREAD), -((((DepthMap::CY + 0.205) * 2) - 1) * SPREAD)].freeze
        SKIN_ZONE = 0
        EYE_ZONE = 1
        PUPIL_ZONE = 2
        MOUTH_ZONE = 3
        # How far from the mouth's centre the widest void can reach.
        MOUTH_REACH = 0.14 * LOWER_FACE_SCALE * MORPHOLOGY.fetch("mouth_scale", 0.84).to_f
        MESH = Glyphs::CONFIG.fetch("mesh").freeze
        # The painting's face ellipse (DepthMap's first layer, x radius 0.255 of the
        # canvas) in the same space as the eyes: its centre and half width, and
        # where the skull and the jaw end, in half widths above and below the
        # widest row. CENTRE_Y is the middle of the head, which rings are centred on.
        CENTRE = ((DepthMap::CX * 2) - 1) * SPREAD
        MIDDLE = -((DepthMap::CY * 2) - 1) * SPREAD
        WIDEST = 0.255 * 2 * SPREAD
        TOP = MIDDLE + (WIDEST * MESH.fetch("skull"))
        BOTTOM = MIDDLE - (WIDEST * MESH.fetch("chin"))
        CENTRE_Y = (TOP + BOTTOM) / 2
        JAW = MESH.fetch("jaw").to_f
        ROWS = MESH.fetch("rows").freeze
        AROUND = MESH.fetch("around").freeze
        BACK = MESH.fetch("back").to_f
        BLUR = MESH.fetch("blur").to_f
        # Along the nose, the heights sampled for its tip.
        TIP_STEPS = 32

        attr_reader :rings, :around

        def self.for(rows, cols)
          @cache ||= {}
          @cache.clear if @cache.size >= CACHE_LIMIT
          @cache[[rows, cols]] ||= new(rows, cols)
        end

        def initialize(rows, cols)
          @rings = (rows * MESH.fetch("per_row")).round.clamp(*ROWS)
          around = (cols * MESH.fetch("per_col")).round.clamp(*AROUND)
          @around = around.odd? ? around + 1 : around
          @meshes = {}
          grid
        end

        # The human head, or the named mask's, on the same grid.
        def mesh(name = nil)
          @meshes[name] ||= build(Masks.params(name), name)
        end

        # Where a point of the painting (x about the centre, y as painted) sits on
        # the surface under params p: x is clamped to the head's width at y.
        def surface(p, xc, y)
          half = half_at(y)
          s = (xc / half).clamp(-1.0, 1.0)
          xa = xc + CENTRE
          vertex(p, half, y, s, Math.sqrt(1.0 - (s * s)), height(xa, y), zone(xa, y))
        end

        private

        # Half the head's width at height y: the skull an ellipse, the jaw the
        # same ellipse under mesh.jaw (smaller than one half pinches it less).
        def half_at(y)
          up = y > MIDDLE
          t = (y - MIDDLE) / (up ? TOP - MIDDLE : MIDDLE - BOTTOM)
          shape = [1.0 - (t * t), 0.0].max
          WIDEST * (up ? Math.sqrt(shape) : shape**JAW)
        end

        # Rings of vertices, the ring angles' sines and cosines, and the
        # parameter-free half of every front vertex: the painting's brightness
        # and zone. The triangles are the same for every set of numbers.
        def grid
          n = @around
          @ring_y = Array.new(@rings) { |j| TOP - ((TOP - BOTTOM) * (j + 1) / (@rings + 1)) }
          @ring_half = @ring_y.map { |y| half_at(y) }
          @sin = Array.new(n) { |i| Math.sin(2 * Math::PI * i / n) }
          @cos = Array.new(n) { |i| Math.cos(2 * Math::PI * i / n) }
          @lum = []
          @paint = []
          @zone = []
          @ring_y.each_with_index do |y, j|
            n.times do |i|
              xa = (@ring_half[j] * @sin[i]) + CENTRE
              front = @cos[i].positive?
              painted = front ? lum_at(xa, y) : 0.5
              @paint << painted
              @lum << (front ? height(xa, y, painted) : 0.5)
              @zone << (front ? zone(xa, y) : SKIN_ZONE)
            end
          end
          @tris = triangles
        end

        # Outward winding, front at ring column 0, rings running down.
        def triangles
          n = @around
          top = @rings * n
          tris = []
          n.times { |i| tris.push(top, i, (i + 1) % n) }
          (0...(@rings - 1)).each do |j|
            n.times do |i|
              a = (j * n) + i
              b = (j * n) + ((i + 1) % n)
              c = ((j + 1) * n) + i
              d = ((j + 1) * n) + ((i + 1) % n)
              tris.push(a, c, b, b, c, d)
            end
          end
          last = (@rings - 1) * n
          n.times { |i| tris.push(top + 1, last + ((i + 1) % n), last + i) }
          tris
        end

        def build(p, name)
          pos = []
          bright = []
          reach = 0.0
          @ring_y.each_with_index do |y, j|
            @around.times do |i|
              k = (j * @around) + i
              x, py, z = vertex(p, @ring_half[j], y, @sin[i], @cos[i], @lum[k], @zone[k])
              pos.push(x, py, z)
              reach = x.abs if x.abs > reach
              bright << shade(p, @paint[k], @cos[i])
            end
          end
          [TOP, BOTTOM].each do |y|
            pos.push(0.0, (y - CENTRE_Y) * p["facial_verticalization"] * p["face_length"], 0.0)
            bright << BACK
          end
          Mesh.new(pos, @tris, bright, landmarks: landmarks(p), params: name && p, margins: name ? Masks.margins(p, reach) : [0.0, 0.0])
        end

        # A vertex under params p: the ring's half width, its height y as
        # painted, the angle's sine and cosine, the painting's brightness there
        # and its zone. x runs across, y up, z toward the viewer.
        def vertex(p, half, y, sin, cos, lum, zone)
          base_y = (y - CENTRE_Y) * p["facial_verticalization"]
          upper = ((base_y + 0.38) / 0.80).clamp(0.0, 1.0)
          scale = p["lower_face_scale"] + ((p["upper_face_scale"] - p["lower_face_scale"]) * upper)
          across = half * sin * scale
          depth = half * 1.10 * p["jaw_projection"] * p["jaw_softening"] * p["masticatory_scale"] * p["cranium_scale"] * p["depth_scale"]
          front = cos.positive? ? cos : 0.0
          lift = ((lum - 0.5) * 0.20 * p["nasal_projection"] * p["relief"]) + Masks.bumps(p, across, base_y, zone)
          [across * p["cranial_width"] * p["width"], base_y * p["face_length"], (depth * cos) + (front * lift)]
        end

        # The vertex's painted brightness: the painting at the front, fading to
        # the back's flat tone round the side, pulled toward flat by a mask.
        def shade(p, lum, cos)
          w = [(cos.positive? ? cos : 0.0) * 2.0, 1.0].min
          b = BACK + ((lum - BACK) * w)
          b + ((p["flat_brightness"] - b) * p["flatten"])
        end

        def lum_at(x, y) = DepthMap.lum(((x / SPREAD) + 1) / 2, (1 - (y / SPREAD)) / 2)

        # The painting's brightness blurred over a cross of radius BLUR: the
        # relief, which has no use for the painting's pinholes and pupils.
        def height(x, y, centre = lum_at(x, y))
          ((4 * centre) + (2 * (lum_at(x - BLUR, y) + lum_at(x + BLUR, y) + lum_at(x, y - BLUR) + lum_at(x, y + BLUR)))) / 12.0
        end

        def zone(x, y)
          return MOUTH_ZONE if Math.hypot(x - MOUTH[0], y - MOUTH[1]) < MOUTH_REACH

          eye = EYES.find { |ex, ey| (((x - ex) / SOCKET[0])**2) + (((y - ey) / SOCKET[1])**2) <= 1.0 }
          return SKIN_ZONE unless eye

          Math.hypot(x - eye[0], y - eye[1]) < PUPIL ? PUPIL_ZONE : EYE_ZONE
        end

        # Where the face's parts stand on the surface under p, for the
        # features: each eye (its corners and pupil), the mouth (corners and
        # centre), the bridge of the nose and its tip, the highest point of the
        # centre line between the eyes and the mouth.
        def landmarks(p)
          eye_y = EYES.first[1]
          reach = 0.8 * SOCKET[0]
          eyes = EYES.map do |ex, ey|
            { left: surface(p, ex - CENTRE - reach, ey), right: surface(p, ex - CENTRE + reach, ey), pupil: surface(p, ex - CENTRE, ey) }
          end
          mouth = { left: surface(p, MOUTH[0] - CENTRE - MOUTH_REACH, MOUTH[1]), right: surface(p, MOUTH[0] - CENTRE + MOUTH_REACH, MOUTH[1]),
                    centre: surface(p, MOUTH[0] - CENTRE, MOUTH[1]) }
          low = MOUTH[1] + 0.05
          tip = nil
          TIP_STEPS.times do |k|
            point = surface(p, 0.0, eye_y + ((low - eye_y) * (k + 0.5) / TIP_STEPS))
            tip = point if tip.nil? || point[2] > tip[2]
          end
          { eyes:, mouth:, bridge: surface(p, 0.0, eye_y), tip: }
        end
      end
    end
  end
end
