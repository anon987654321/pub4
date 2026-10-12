# frozen_string_literal: true

module Master
  module CLI
    module Face
      # Mask morph targets for the ASCII face: the head eases toward one while
      # MASTER thinks and back when it stops. A target is a handful of numbers
      # (data/tokens.yml, face_interface.ascii.masks) laid over the human
      # head's morphology; nothing here stores or names an object. The lattice
      # is the head's own, point for point, so a morph moves points and never
      # adds or drops one. The web face ports every line (face_ascii.js).
      module Masks
        CONFIG = Glyphs::CONFIG.fetch("masks").freeze
        ORDER = CONFIG.fetch("order").freeze
        TRIGGERS = CONFIG.fetch("trigger_states").freeze
        EASE = CONFIG.fetch("ease").freeze
        TAKEOVER = CONFIG.fetch("takeover").to_f
        BEAK_MIN = CONFIG.fetch("beak_min").to_f
        BROW_MIN = CONFIG.fetch("brow_min").to_f
        MOUTH_SLACK = CONFIG.fetch("mouth_slack").to_f
        RING_MIN_PX = CONFIG.fetch("ring_min_px").to_f
        GLYPHS = CONFIG.fetch("glyphs").freeze
        # The geometry the human head is built from, under the keys the masks
        # override; the rest of the neutral set is in the data.
        NEUTRAL = {
          "cranium_scale" => Head::CRANIUM_SCALE, "cranial_width" => Head::CRANIAL_WIDTH,
          "upper_face_scale" => Head::UPPER_FACE_SCALE, "lower_face_scale" => Head::LOWER_FACE_SCALE,
          "facial_verticalization" => Head::FACIAL_VERTICALIZATION, "jaw_projection" => Head::JAW_PROJECTION,
          "jaw_softening" => Head::JAW_SOFTENING, "masticatory_scale" => Head::MASTICATORY_SCALE,
          "nasal_projection" => Head::NASAL_PROJECTION
        }.merge(CONFIG.fetch("neutral").transform_values(&:to_f)).freeze

        module_function

        def smoothstep(s)
          s = s.clamp(0.0, 1.0)
          s * s * (3.0 - (2.0 * s))
        end

        # The parameters of a target, or the human head's when name is nil.
        def params(name)
          return NEUTRAL if name.nil?

          target = CONFIG.fetch("targets").fetch(name.to_s).transform_values(&:to_f)
          unknown = target.keys - NEUTRAL.keys
          raise ArgumentError, "masks: #{name} sets unknown keys #{unknown.join(", ")}" unless unknown.empty?

          NEUTRAL.merge(target)
        end

        # Parameter-wise interpolation by smoothstep. The ends are exact: s <= 0
        # answers from and s >= 1 answers to, whatever float rounding says.
        def morph(from, to, s)
          return from if s <= 0.0
          return to if s >= 1.0

          e = smoothstep(s)
          from.to_h { |key, a| [key, a + ((to.fetch(key) - a) * e)] }
        end

        # How far toward the mask the face is at time t, linear, 0 to 1: it
        # was `from` at `since`, and it heads for 1 in a trigger state over
        # ease.in seconds, else for 0 over ease.out. Pure, so a caller that
        # remembers only when the state last changed reproduces it.
        def mix(state, t, since:, from: 0.0)
          trigger = TRIGGERS.include?(state.to_s)
          span = trigger ? EASE.fetch("in") : EASE.fetch("out")
          progress = span.positive? ? ((t - since) / span).clamp(0.0, 1.0) : 1.0
          from + (((trigger ? 1.0 : 0.0) - from) * progress)
        end

        # The mask a session wears: FNV-1a over its id's bytes, so the terminal
        # and the web face choose alike.
        def pick(session = nil)
          h = 2_166_136_261
          id = session.to_s
          id = CONFIG.fetch("default_session") if id.empty?
          id.each_byte { |b| h = ((h ^ b) * 16_777_619) & 0xffffffff }
          ORDER.fetch(h % ORDER.size)
        end

        # The Look's mask and mix for a schedule, or no mask without one.
        def worn(state, t, schedule)
          return { mask: nil, mix: 0.0 } unless schedule

          { mask: pick(schedule[:session]), mix: mix(state, t, since: schedule.fetch(:since), from: schedule.fetch(:from, 0.0)) }
        end

        # The point source for a mask at a mix: the head itself at 0.
        def source(head, name, amount)
          return head if name.nil? || amount <= 0.0

          Shape.new(head, morph(NEUTRAL, params(name), amount))
        end

        # The head's lattice under a morphology: the same rows, the same
        # points in the same order, each placed as Head#front and Head#back
        # place it with the numbers in params.
        class Shape
          BACK_LIGHT = 0.28
          attr_reader :params, :eyes, :mouth

          def initialize(head, params)
            @cells = head.cells
            @cx, @cy = head.centre
            @eyes = head.eyes
            @mouth = head.mouth
            @params = params
            @depth_ratio = 1.10 * params["jaw_projection"] * params["jaw_softening"] * params["masticatory_scale"]
            @relief = 0.20 * params["nasal_projection"]
          end

          def each_point
            p = @params
            @cells.each do |y, half, count, fronts|
              fronts.each { |x, lum, zone| yield(*front(x, y, lum, half, zone), zone, 0.0) }
              depth = half * @depth_ratio * p["cranium_scale"]
              (1...count).each do |i|
                angle = (Math::PI / 2) + (Math::PI * i / count)
                yield half * Math.sin(angle) * p["width"], (y - @cy) * p["face_length"], depth * Math.cos(angle) * p["depth_scale"], BACK_LIGHT, 0, 0.0
              end
            end
          end

          # How far past the head's points the extras reach, as [above, to the
          # side], so the fit leaves room for them.
          def margins
            p = @params
            reach = @cells.map { |_, half, *| half }.max * p["width"]
            halo = p["halo"]
            above = halo.positive? ? (p["halo_rise"] * halo) + ((Glyphs.half_up(p["halo_rows"]) - 1) * p["halo_gap"]) : 0.0
            disc = p["disc"]
            side = disc.positive? ? reach + (p["disc_offset"] * disc) + (p["disc_radius"] * disc) : 0.0
            [above, side]
          end

          private

          def front(x, y, lum, half, zone)
            p = @params
            base_y = (y - @cy) * p["facial_verticalization"]
            upper = ((base_y + 0.38) / 0.80).clamp(0.0, 1.0)
            local_x = (x - @cx) * (p["lower_face_scale"] + ((p["upper_face_scale"] - p["lower_face_scale"]) * upper))
            across = (local_x / (half * p["cranial_width"])).clamp(-1.0, 1.0)
            z = ((half * @depth_ratio * p["cranium_scale"] * Math.sqrt(1 - (across * across))) * p["depth_scale"]) + ((lum - 0.5) * @relief * p["relief"])
            z += bumps(local_x, base_y, zone)
            [local_x * p["width"], base_y * p["face_length"], z, lum + ((p["flat_brightness"] - lum) * p["flatten"])]
          end

          # Where the ridges and grooves lift or sink the surface, in the
          # human head's own frame (before the width and length scales).
          def bumps(x, y, zone)
            p = @params
            lift = 0.0
            lift += beak(x, y) if p["beak_projection"].positive?
            if p["brow_ridge"].positive?
              up = (y - p["brow_y"]) / p["brow_height"]
              across = x / p["brow_width"]
              lift += p["brow_ridge"] * Math.exp(-(up * up)) * Math.exp(-(across * across * across * across))
            end
            lift -= p["socket_depth"] * (zone == 1 ? 1.0 : 0.4) if p["socket_depth"].positive? && zone.between?(1, 2)
            lift
          end

          # A ridge down the middle that grows toward its tip and ends there.
          def beak(x, y)
            p = @params
            t = (p["beak_top"] - y) / p["beak_length"]
            return 0.0 if t.negative?

            past = (t - 1.0) * p["beak_length"] / 0.04
            taper = t <= 1.0 ? Masks.smoothstep(t) : Math.exp(-(past * past))
            side = x / p["beak_width"]
            p["beak_projection"] * taper * Math.exp(-(side * side))
          end
        end
      end
    end
  end
end
