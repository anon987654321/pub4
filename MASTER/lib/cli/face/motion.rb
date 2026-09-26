# frozen_string_literal: true

module Master
  module CLI
    module Face
      # Everything about the face that moves, and never stops moving: a slow
      # breath, a weightless bob, a restrained turn or a settle by state,
      # glances and blinks at irregular times, and a sparse field of particles
      # that orbit the head, drift upward and keep clear of it. Events push it:
      # a key twitches the head toward the input line and scatters the particles
      # near it, listening draws them in and leans the head forward, a finished
      # reply nods.
      #
      # All of it is springs and noise over real time, so no two seconds look
      # alike and nothing snaps. This is the one mutable part of the face: the
      # window keeps one Motion and hands it to Face.frame with each tick.
      class Motion
        TAU = 2 * Math::PI
        # Radians a second: the face turns only a little at rest and in thought.
        # Full rotation made the Braille head collapse into a narrow silhouette.
        YAW = { idle: [0.20, 0.32], thinking: [0.28, 0.55] }.freeze
        EVENTS = %i[key listen nod thinking phantom council].freeze

        # A critically damped spring, stepped implicitly so a long frame can
        # never make it overshoot or blow up.
        Spring = Struct.new(:x, :v) do
          def toward(target, omega, dt)
            f = 1.0 + (2.0 * dt * omega)
            hoo = dt * omega * omega
            det = f + (dt * hoo)
            self.x, self.v = ((f * x) + (dt * v) + (dt * hoo * target)) / det, (v + (hoo * (target - x))) / det
            x
          end
        end

        Particle = Struct.new(:angle, :radius, :height, :spin, :rise, :push, :lift)

        def initialize(seed: 7)
          @rng = Random.new(seed)
          @seed = seed
          @t = nil
          @yaw, @pitch, @roll, @lean, @dip = Array.new(5) { Spring.new(0.0, 0.0) }
          @eye = Spring.new(1.0, 0.0)
          @gaze_lon, @gaze_lat, @mouth = Array.new(3) { Spring.new(0.0, 0.0) }
          @next_blink = 2.2
          @next_glance = 0.9
          @glance = [0.0, 0.0]
          @particles = []
        end

        # Advances to time t in seconds and answers the Look to draw.
        def step(state:, t:, level: nil, events: [], count: 24)
          dt = @t ? (t - @t).clamp(0.0, 0.25) : 0.0
          @t = t
          events.each { |event| react(event) }
          turn(state, t, dt)
          features(state, t, dt, level)
          drift(state, t, dt, count)
          look(t)
        end

        def particles = @particles

        private

        def react(event)
          raise ArgumentError, "face: unknown event #{event.inspect}" unless EVENTS.include?(event)

          case event
          when :key
            @pitch.v += 0.9
            @yaw.v += @rng.rand(-0.4..0.4)
            @dip.v -= 0.25
            @particles.each { |p| p.push += @rng.rand(0.6..1.4) if p.height < -0.2 }
          when :listen
            @particles.each { |p| p.push -= 0.5 }
          when :nod
            @pitch.v += 1.6
          when :thinking
            @pitch.v -= 0.35
            @yaw.v += @rng.rand(-0.12..0.12)
          when :phantom
            @roll.v += @rng.rand(-0.8..0.8)
            @dip.v += 0.5
            @particles.each { |p| p.push += @rng.rand(0.8..1.5) }
          when :council
            @yaw.v += @rng.rand(-0.3..0.3)
            @pitch.v += 0.45
          end
        end

        # The face stays readable in front view. State changes alter the
        # amount and speed of the turn, but never enough to hide the features.
        def turn(state, t, dt)
          if (sway = YAW[state])
            amount, speed = sway
            @yaw.toward(amount * Math.sin(t * speed), 3.5, dt)
          else
            sway = state == :speaking ? 0.2 * noise(t * 0.4, 1) : 0.05 * noise(t * 0.3, 2)
            @yaw.toward(sway, 2.5, dt)
          end
          @pitch.toward(pitch_for(state, t), 6.0, dt)
          @roll.toward(state == :listening ? 0.13 : 0.18 * Math.sin(t * 0.7), 4.0, dt)
          @lean.toward(state == :listening ? 0.1 : 0.0, 4.0, dt)
          @dip.toward(0.0, 7.0, dt)
        end

        def pitch_for(state, t)
          nod = 0.12 * Math.sin(t * 0.43)
          return nod - 0.12 if state == :thinking
          return 0.08 if state == :listening

          nod
        end

        def features(state, t, dt, level)
          blink(t)
          @eye.toward(eye_target(state, t), 32.0, dt)
          glance(state, t)
          @gaze_lon.toward(@glance[0], 26.0, dt)
          @gaze_lat.toward(@glance[1], 26.0, dt)
          heard = level.nil? ? Face.timed_level((t * FPS).to_i) : level.to_f.clamp(0.0, 1.0)
          @mouth.toward(state == :speaking ? heard : 0.0, 24.0, dt)
        end

        def blink(t)
          return if t < @next_blink + 0.16

          double = @rng.rand < 0.15
          @next_blink = t + (double ? 0.25 : @rng.rand(1.8..5.5))
        end

        def eye_target(state, t)
          return 0.0 if t.between?(@next_blink, @next_blink + 0.16)

          state == :listening ? 1.4 : 1.0
        end

        # A glance lands somewhere near centre and holds for a moment; now
        # and then it comes home. Thinking looks up and away.
        def glance(state, t)
          return if t < @next_glance

          @next_glance = t + @rng.rand(0.35..2.2)
          home = @rng.rand < 0.3
          @glance = home ? [0.0, 0.0] : [@rng.rand(-0.09..0.09), @rng.rand(-0.04..0.04)]
          @glance = [@glance[0] + 0.05, @glance[1] + 0.05] if state == :thinking
        end

        def drift(state, t, dt, count)
          @particles << spawn(@rng.rand(-1.1..1.1)) while @particles.size < count
          @particles.pop while @particles.size > count
          @particles.each { |p| move(p, state, t, dt) }
        end

        def spawn(height)
          Particle.new(@rng.rand(TAU), @rng.rand(1.1..1.7), height, @rng.rand(0.15..0.45) * [-1, 1].sample(random: @rng),
                       @rng.rand(0.03..0.09), 0.0, @rng.rand(TAU))
        end

        # Orbit, rise and ease back to a resting radius; thinking pulls them
        # into a fast flat ring, listening pulls them close.
        def move(particle, state, t, dt)
          thinking = state == :thinking
          particle.angle += particle.spin * (thinking ? 4.0 : 1.0) * dt
          rest = { thinking: 1.2, listening: 0.95 }.fetch(state, 1.35)
          particle.push += ((rest - particle.radius) * 1.5 - particle.push) * (1 - Math.exp(-3.0 * dt))
          particle.radius = [particle.radius + (particle.push * dt), 0.85].max
          particle.height += thinking ? -particle.height * 2.0 * dt : particle.rise * dt
          particle.height += 0.02 * noise((t * 0.5) + particle.lift, 5) * dt
          return unless particle.height > 1.15

          spawn(-1.15).each_pair { |field, value| particle[field] = value }
        end

        def look(t)
          breath = 1.0 + (0.025 * Math.sin(t * 1.6))
          Look.new(
            yaw: @yaw.x, pitch: @pitch.x, roll: @roll.x, scale: breath * (1.0 + @lean.x),
            bob: (0.02 * Math.sin(t * 1.1)) + (0.01 * noise(t * 0.5, 6)) + @dip.x,
            eye_open: @eye.x.clamp(0.0, 1.5), gaze: [@gaze_lon.x, @gaze_lat.x], mouth: @mouth.x.clamp(0.0, 1.0),
            particles: @particles.map { |p| place(p, t) }
          )
        end

        # Where a particle sits in the world, with the mouth's ripple on it.
        def place(particle, t)
          ripple = 1.0 + (0.08 * @mouth.x * Math.sin((3 * particle.angle) + (9 * t)))
          r = particle.radius * ripple
          [r * 0.75 * Math.sin(particle.angle), particle.height, r * 0.65 * Math.cos(particle.angle)]
        end

        # One frame's worth of motion, in model units and radians.
        Look = Data.define(:yaw, :pitch, :roll, :scale, :bob, :eye_open, :gaze, :mouth, :particles)

        # Smooth value noise in [-1, 1]: lattice values from an integer hash,
        # eased between, so drift wanders without repeating.
        def noise(x, channel)
          i = x.floor
          f = x - i
          ease = f * f * (3 - (2 * f))
          a = lattice(i, channel)
          a + ((lattice(i + 1, channel) - a) * ease)
        end

        def lattice(i, channel)
          h = ((i * 374_761_393) + (channel * 668_265_263) + (@seed * 2_246_822_519)) & 0xffffffff
          h = ((h ^ (h >> 13)) * 1_274_126_177) & 0xffffffff
          ((h ^ (h >> 16)) / 2_147_483_647.5) - 1.0
        end
      end
    end
  end
end
