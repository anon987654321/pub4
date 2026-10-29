# frozen_string_literal: true

module Master
  module CLI
    module Face
      # The Look for a still frame as a pure function of (state, t, seed): no
      # springs, no noise, no memory. Face::Motion is the live head, reacting
      # to keys and speech; this is the head at rest on a given second, which a
      # test or the web face can reproduce exactly from data/tokens.yml.
      module Pose
        MOTION = Master::Face::Contract.ascii.fetch("motion").freeze

        module_function

        # schedule is {session:, since:, from:}: who is wearing the mask, when the
        # state last changed and how far the mask had come then. Without one
        # there is no mask.
        def at(state, t, seed = 0, schedule: nil)
          m = MOTION
          spinning = m.fetch("spin_states").include?(state.to_s)
          shut = ((t + ((seed % 7) * 0.37)) % m.fetch("blink_period")) >= m.fetch("blink_period") - m.fetch("blink_length")
          k = (t * FPS).floor
          Motion.rest(
            turn: spinning ? m.fetch("spin") * t : 0.0,
            scale: 1.0 + (m.fetch("breath") * Math.sin(m.fetch("breath_rate") * t)),
            pitch: m.fetch("pitch_sway") * Math.sin(m.fetch("pitch_rate") * t),
            roll: m.fetch("roll") * Math.sin(m.fetch("roll_rate") * t),
            bob: m.fetch("bob") * Math.sin(m.fetch("bob_rate") * t),
            light: Motion::LIGHT.fetch("start") + (Motion::LIGHT.fetch("orbit") * t),
            dolly: m.fetch("dolly").fetch(state.to_s, 1.0),
            eye_open: shut ? 0.0 : 1.0,
            mouth: state.to_sym == :speaking ? Face.timed_level(k) : 0.0,
            **Masks.worn(state, t, schedule),
          )
        end
      end
    end
  end
end
