# frozen_string_literal: true

require_relative "../face"

module Master
  module Face
    # The shared particle field used by the terminal projection and the web
    # stipple renderer. All visual parameters originate in tokens.yml.
    module Swarm
      Particle = Struct.new(
        :x, :y, :z, :vx, :vy, :vz, :depth_rank, :home_depth,
        keyword_init: true
      )

      # No renderer-side constants for visual values: tokens.yml is the only authority.

      module_function

      def config(root: Master::ROOT)
        Contract.data(root:).fetch("swarm", {})
      end

      def enabled?(root: Master::ROOT)
        config(root:).fetch("enabled", false) == true
      end

      def canonical_mode(mode)
        case mode.to_s.downcase
        when "thinking" then "thinking"
        when "attentive", "listening", "working", "speaking", "ready" then "attentive"
        else "idle"
        end
      end

      def mode_multipliers(mode, config: self.config)
        modes = config.fetch("mode_multipliers")
        modes.fetch(canonical_mode(mode)) { modes.fetch("idle") }
      end

      # The new swarm ceiling is subordinate to the existing spatial particle
      # budget. A renderer can request fewer particles, never more.
      def particle_budget(root: Master::ROOT, config: self.config, mobile: false, reduced_motion: false)
        spatial = Contract.budget(root:)
        total_key = mobile ? "mobile_points" : "desktop_points"
        allocation = spatial.fetch("point_allocation", {})
        fraction = Float(allocation.fetch("stipple_fraction", 1.0)).clamp(0.0, 1.0)
        total = Integer(spatial.fetch(total_key, config.fetch("particle_budget", 1)))
        allocated = [(total * fraction).floor, 1].max
        # reduced_motion freezes the existing particles; it does not respawn a
        # smaller cloud. The reduced_motion_particles dial belongs to sparse_field.
        [Integer(config.fetch("particle_budget", allocated)), allocated].min
      end
      def build(count: nil, seed: 0, root: Master::ROOT, config: self.config, mobile: false, reduced_motion: false)
        limit = particle_budget(root:, config:, mobile:, reduced_motion:)
        amount = [[Integer(count || limit), 0].max, limit].min
        rng = Random.new(Integer(seed))
        field = config.fetch("target_field")
        Array.new(amount) do
          x, y, z = sample_position(rng, field)
          Particle.new(
            x:, y:, z:, vx: 0.0, vy: 0.0, vz: 0.0,
            depth_rank: depth_rank(z), home_depth: z
          )
        end
      end

      def sample_position(rng, field)
        choice = rng.rand
        head = field.fetch("head")
        center = head.fetch("center")
        scale = head.fetch("scale")
        if choice < 0.68 || !field["eyes"] || !field["mouth"]
          loop do
            u = (rng.rand * 2.0) - 1.0
            v = (rng.rand * 2.0) - 1.0
            radius_squared = (u * u) + (v * v)
            next if radius_squared > 1.0

            front = Math.sqrt(1.0 - radius_squared)
            z = center[2] + (scale[2] * front * (0.82 + rng.rand * 0.18))
            return [center[0] + (scale[0] * u), center[1] + (scale[1] * v), z]
          end
        elsif choice < 0.86
          eye = field.fetch("eyes").values.fetch(rng.rand(2))
          sample_attractor(rng, eye)
        elsif choice < 0.97
          sample_attractor(rng, field.fetch("mouth"))
        else
          u = (rng.rand * 2.0) - 1.0
          v = (rng.rand * 2.0) - 1.0
          [center[0] + (scale[0] * u * 0.9), center[1] + (scale[1] * v * 0.9),
           center[2] + (scale[2] * (0.35 + rng.rand * 0.55))]
        end
      end

      def sample_attractor(rng, attractor)
        point = attractor.fetch("pos")
        radius = Float(attractor.fetch("radius"))
        angle = rng.rand * Math::PI * 2.0
        radial = Math.sqrt(rng.rand) * radius
        [
          point[0] + (Math.cos(angle) * radial),
          point[1] + (Math.sin(angle) * radial),
          point[2] + ((rng.rand - 0.5) * radius * 0.22)
        ]
      end

      def depth_rank(z)
        (0.5 + (Float(z) * 0.5)).clamp(0.0, 1.0)
      end

      def glyph_for(rank, config: self.config)
        ramp = Array(config.fetch("glyph_ramp"))
        return "•" if ramp.empty?

        value = Float(rank)
        value = 0.5 unless value.finite?
        index = ((value.clamp(0.0, 1.0) * (ramp.length - 1)) + 0.5).floor
        ramp.fetch(index)
      end

      # One semi-implicit Euler step. Positions are snapshotted first so the
      # neighbor pass cannot depend on iteration order. Supplying an RNG makes
      # the force step reproducible in tests and recorded renders.
      def update!(particles, mode:, dt:, config: self.config, rng: Random.new)
        delta = Float(dt)
        return particles unless delta.positive?

        delta = delta.clamp(0.0, 0.05)
        field = config.fetch("target_field")
        multipliers = mode_multipliers(mode, config:)
        damping = Float(config.fetch("damping"))
        noise_scale = Float(config.fetch("noise_scale")) * Float(multipliers.fetch("noise"))
        head = field.fetch("head")
        center = head.fetch("center").map(&:to_f)
        scale = head.fetch("scale").map { |value| [Float(value).abs, 0.001].max }
        softness = [Float(field.fetch("softness", 0.72)), 0.001].max
        cohesion_radius = [Float(config.fetch("cohesion_radius")), 0.0].max
        separation_radius = [Float(config.fetch("separation_radius")), 0.0].max
        cohesion_squared = cohesion_radius * cohesion_radius
        separation_squared = separation_radius * separation_radius
        snapshot = particles.map { |p| [p.x, p.y, p.z, p.vx, p.vy, p.vz] }
        forces = Array.new(snapshot.length) { [0.0, 0.0, 0.0] }

        snapshot.each_with_index do |(x, y, z), index|
          dx = (center[0] - x) / scale[0]
          dy = (center[1] - y) / scale[1]
          dz = (center[2] - z) / scale[2]
          distance = Math.sqrt((dx * dx) + (dy * dy) + (dz * dz)) + 1.0e-5
          falloff = Math.exp(-(distance * distance) / softness)
          weight = Float(head.fetch("weight", 1.0)) * Float(multipliers.fetch("core"))
          force = forces[index]
          force[0] += weight * falloff * (center[0] - x)
          force[1] += weight * falloff * (center[1] - y)
          force[2] += weight * falloff * (center[2] - z)

          Array(field.fetch("eyes", {}).values).each do |eye|
            point = eye.fetch("pos")
            ex, ey, ez = point.map(&:to_f)
            ddx, ddy, ddz = ex - x, ey - y, ez - z
            d = Math.sqrt((ddx * ddx) + (ddy * ddy) + (ddz * ddz)) + 1.0e-5
            reach = [Float(eye.fetch("radius")), 0.001].max
            strength = Float(eye.fetch("weight", 1.0)) * Float(multipliers.fetch("eyes"))
            f = Math.exp(-((d / reach)**2))
            force[0] += strength * f * ddx
            force[1] += strength * f * ddy
            force[2] += strength * f * ddz
          end

          mouth = field.fetch("mouth")
          mx, my, mz = mouth.fetch("pos").map(&:to_f)
          mdx, mdy, mdz = mx - x, my - y, mz - z
          mouth_distance = Math.sqrt((mdx * mdx) + (mdy * mdy) + (mdz * mdz)) + 1.0e-5
          mouth_radius = [Float(mouth.fetch("radius")), 0.001].max
          mouth_falloff = Math.exp(-((mouth_distance / mouth_radius)**2))
          mouth_weight = Float(mouth.fetch("weight", 1.0))
          force[0] += mouth_weight * mouth_falloff * mdx
          force[1] += mouth_weight * mouth_falloff * mdy
          force[2] += mouth_weight * mouth_falloff * mdz

          if cohesion_squared.positive? || separation_squared.positive?
            cohort = [0.0, 0.0, 0.0]
            cohort_count = 0
            snapshot.each_with_index do |other, other_index|
              next if index == other_index

              ox, oy, oz = other
              vx, vy, vz = ox - x, oy - y, oz - z
              distance_squared = (vx * vx) + (vy * vy) + (vz * vz)
              if cohesion_squared.positive? && distance_squared < cohesion_squared
                cohort[0] += vx
                cohort[1] += vy
                cohort[2] += vz
                cohort_count += 1
              end
              if separation_squared.positive? && distance_squared.positive? && distance_squared < separation_squared
                d = Math.sqrt(distance_squared)
                factor = Float(config.fetch("separation_strength")) * (1.0 - d / separation_radius)
                force[0] -= (vx / d) * factor
                force[1] -= (vy / d) * factor
                force[2] -= (vz / d) * factor
              end
            end
            if cohort_count.positive?
              strength = Float(config.fetch("cohesion_strength")) / cohort_count
              force[0] += cohort[0] * strength
              force[1] += cohort[1] * strength
              force[2] += cohort[2] * strength
            end
          end

          force[0] += (rng.rand - 0.5) * noise_scale
          force[1] += (rng.rand - 0.5) * noise_scale
          force[2] += (rng.rand - 0.5) * noise_scale
        end

        particles.each_with_index do |particle, index|
          x, y, z, vx, vy, vz = snapshot[index]
          fx, fy, fz = forces[index]
          particle.vx = (vx + fx * delta) * damping
          particle.vy = (vy + fy * delta) * damping
          particle.vz = (vz + fz * delta) * damping
          particle.x = x + particle.vx
          particle.y = y + particle.vy
          particle.z = z + particle.vz
          particle.x = particle.x.clamp(center[0] - (scale[0] * 1.25), center[0] + (scale[0] * 1.25))
          particle.y = particle.y.clamp(center[1] - (scale[1] * 1.25), center[1] + (scale[1] * 1.25))
          particle.z = particle.z.clamp(center[2] - (scale[2] * 1.25), center[2] + (scale[2] * 1.25))
          particle.depth_rank = depth_rank(particle.z)
        end
        particles
      end

      # Overlay points from far to near; nearer glyphs deterministically win a
      # collision. The color path uses the same far/mid/near depth classification.
      def overlay!(frame, particles, config: self.config)
        return frame unless frame && frame.respond_to?(:chars) && frame.respond_to?(:depth)

        rows = frame.chars.length
        cols = frame.chars.first&.length.to_i
        return frame unless rows.positive? && cols.positive?

        head = config.fetch("target_field").fetch("head")
        center = head.fetch("center").map(&:to_f)
        scale = head.fetch("scale").map { |value| [Float(value).abs, 0.001].max }
        particles.each_with_index.sort_by { |particle, index| [particle.depth_rank || 0.5, index] }.each do |particle, _index|
          col = (((particle.x - (center[0] - scale[0])) / (2.0 * scale[0])) * (cols - 1)).round
          row = (((center[1] + scale[1] - particle.y) / (2.0 * scale[1])) * (rows - 1)).round
          next unless row.between?(0, rows - 1) && col.between?(0, cols - 1)

          frame.chars[row][col] = glyph_for(particle.depth_rank || 0.5, config:)
          rank = Float(particle.depth_rank || 0.5).clamp(0.0, 1.0)
          frame.depth[row][col] = rank >= 0.72 ? 2 : (rank <= 0.35 ? 0 : 1)
        end
        frame
      end

      class Simulation
        attr_reader :particles

        def initialize(root: Master::ROOT, seed: 261_028, count: nil, mobile: false)
          @root = root
          @config = Swarm.config(root:)
          @particles = Swarm.build(root:, config: @config, seed:, count:, mobile:)
          @last_time = nil
        end

        def step(mode:, time:, reduced_motion: false, rng: Random.new)
          now = Float(time)
          if reduced_motion
            @last_time = now
            return particles
          end

          delta = @last_time ? now - @last_time : 1.0 / 20.0
          @last_time = now
          Swarm.update!(particles, mode:, dt: delta, config: @config, rng:)
        end

        def overlay!(frame)
          Swarm.overlay!(frame, particles, config: @config)
        end
      end
    end
  end
end
