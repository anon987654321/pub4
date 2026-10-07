require_relative "../../face/contract"

# frozen_string_literal: true

module Master
  module CLI
    module Face
      # The web face's particles, placed the way its sampleDepthMapGrid places
      # them: a hex lattice over the painted depth map (DepthMap), a point
      # wherever the painting is brighter than 0.08, at x and y within 0.62
      # of centre. The web face is a mask seen from the front; to turn all
      # the way round, the terminal face wraps that mask onto the front of a
      # head whose outline, row by row, is the mask's own, lifts each point
      # by its painted brightness, and closes the back with points at the
      # same spacing. The lattice is as fine as the window's Braille dots can
      # show, so a phone draws a few thousand points and a wide terminal more.
      #
      # Built once per window size and kept, since a resize is rare and a
      # frame is not.
      class Head
        THRESHOLD = 0.08
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
        ASYMMETRY_SEED = MORPHOLOGY.fetch("asymmetry_seed", 73421).to_i
        # The far-future profile keeps the human silhouette but shifts mass
        # upward and inward: fuller vault, compact lower face, shallow brow,
        # restrained nasal projection and a slightly deeper orbital field.
        # The contract owns the numbers so browser and terminal cannot drift.
        DEPTH_RATIO = 1.10 * JAW_PROJECTION * JAW_SOFTENING * MASTICATORY_SCALE
        RELIEF = 0.20 * NASAL_PROJECTION
        BACK_LIGHT = 0.28
        CACHE_LIMIT = 8
        # Where the eyes and the mouth void sit, in the points' own space, and
        # how far each reaches: the painted socket, the painted pupil, and the
        # hole between the lips.
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
        STRIDE = 7

        attr_reader :count, :dots_wide, :dots_high, :scale, :centre, :eyes, :mouth

        def self.for(rows, cols)
          @cache ||= {}
          @cache.clear if @cache.size >= CACHE_LIMIT
          @cache[[rows, cols]] ||= new(rows, cols)
        end

        def initialize(rows, cols)
          @dots_wide = cols * 2
          @dots_high = rows * 4
          mask = lattice(density)
          @centre = middle(mask)
          @points = wrap(mask).freeze
          @eyes = EYES.map { |ex, ey| [ex - @centre[0], ey - @centre[1]] }
          @mouth = [MOUTH[0] - @centre[0], MOUTH[1] - @centre[1]]
          @count = @points.size / STRIDE
          fit
        end

        # Yields x, y, z about the head's centre, brightness, zone, and a
        # phase for the shimmer, per point.
        def each_point
          p = @points
          i = 0
          while i < p.size
            yield p[i], p[i + 1], p[i + 2], p[i + 3], p[i + 4], p[i + 5]
            i += STRIDE
          end
        end

        private

        # Lattice columns, so that about a point a dot crosses the face before
        # the shimmer drops a third of them; the web face's desktop lattice
        # is 52 by 66.
        def density
          face_dots = [@dots_wide, @dots_high * 0.62].min * 0.55
          (face_dots * 2.0).round.clamp(40, 160)
        end

        # The mask, row by row: [y, [[x, brightness], ...]].
        def lattice(cols)
          rows = (cols * 66 / 52.0).round
          (0...rows).filter_map do |row|
            shift = row.odd? ? 0.5 : 0.0
            v = (row + 0.5) / rows
            points = (0...cols).filter_map do |col|
              u = (col + shift + 0.5) / cols
              lum = DepthMap.lum(u, v)
              [((u * 2) - 1) * SPREAD, lum] if lum >= THRESHOLD
            end
            [-((v * 2) - 1) * SPREAD, points] unless points.empty?
          end
        end

        def middle(mask)
          xs = mask.flat_map { |_, points| points.map(&:first) }
          ys = mask.map(&:first)
          [(xs.max + xs.min) / 2, (ys.max + ys.min) / 2]
        end

        def wrap(mask)
          phases = Random.new(52)
          spacing = mask.size > 1 ? (mask[0][0] - mask[1][0]).abs : 0.05
          mask.each_with_object([]) do |(y, points), flat|
            half = points.map { |x, _| (x - @centre[0]).abs }.max + (spacing / 2)
            points.each { |x, lum| flat.push(*front(x, y, lum, half), phases.rand(2 * Math::PI), 0) }
            back(y, half, spacing).each { |x, z| flat.push(x, y - @centre[1], z, BACK_LIGHT, SKIN_ZONE, phases.rand(2 * Math::PI), 0) }
          end
        end

        # A mask point on the front of its row's ellipse, lifted by its paint.
        def front(x, y, lum, half)
          local_y = (y - @centre[1]) * FACIAL_VERTICALIZATION
          upper = ((local_y + 0.38) / 0.80).clamp(0.0, 1.0)
          width_scale = LOWER_FACE_SCALE + ((UPPER_FACE_SCALE - LOWER_FACE_SCALE) * upper)
          local_x = (x - @centre[0]) * width_scale
          across = (local_x / (half * CRANIAL_WIDTH)).clamp(-1.0, 1.0)
          z = (half * DEPTH_RATIO * CRANIUM_SCALE * Math.sqrt(1 - (across * across))) + ((lum - 0.5) * RELIEF)
          [local_x, local_y, z, lum, zone(x, y)]
        end

        # The back half of the row's ellipse, at the lattice's spacing.
        def back(_y, half, spacing)
          depth = half * DEPTH_RATIO * CRANIUM_SCALE
          count = [(Math::PI * (half + depth) / 2 / spacing).round, 2].max
          (1...count).map do |i|
            angle = (Math::PI / 2) + (Math::PI * i / count)
            [half * Math.sin(angle), depth * Math.cos(angle)]
          end
        end

        def zone(x, y)
          return MOUTH_ZONE if Math.hypot(x - MOUTH[0], y - MOUTH[1]) < MOUTH_REACH

          eye = EYES.find { |ex, ey| (((x - ex) / SOCKET[0])**2) + (((y - ey) / SOCKET[1])**2) <= 1.0 }
          return SKIN_ZONE unless eye

          Math.hypot(x - eye[0], y - eye[1]) < PUPIL ? PUPIL_ZONE : EYE_ZONE
        end

        # Dots per unit, so the head fills about four fifths of the window at
        # its own aspect, with room for perspective to swell its near side.
        def fit
          xs = []
          ys = []
          each_point do |x, y, *|
            xs << x
            ys << y
          end
          # The dedicated face is the hero surface, not a prompt ornament.
          @scale = [(@dots_wide * 0.9) / (xs.max - xs.min), (@dots_high * 0.9) / (ys.max - ys.min)].min
        end
      end
    end
  end
end
