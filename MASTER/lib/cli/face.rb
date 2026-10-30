# frozen_string_literal: true

require_relative "../face/swarm"

module Master
  module CLI
    # The face drawn in plain ASCII, for a window too small or too plain for
    # WebGL: Termux:Float on a phone. It is the web face's head (Face::Head,
    # the same morphology and painted depth map) turned in 3D and inked with
    # | - / \ contours, a dithered ramp for the surface and glyph features
    # (Face::Ascii); any mesh (Face::Mesh) shows the same way. Braille is
    # retired. Face::Motion keeps it moving: a constant slow turn, a breath, a
    # pitch sway, blinks and glances.
    #
    # A frame is a function of state, size, time and events, with one small
    # mutable Motion carried from frame to frame. Nothing here touches the
    # terminal, which is what lets a test draw it at any size.
    module Face
      STATES = %i[idle listening thinking working speaking warning error sleeping ready].freeze
      FPS = 20
      # Below this there is not room for a face worth the name, and the frame
      # names the state instead.
      MIN_ROWS = Glyphs::CONFIG.fetch("min_rows")
      MIN_COLS = Glyphs::CONFIG.fetch("min_cols")
      RENDERERS = {}
      SWARMS = {}

      module_function

      # rows lines of cols cells, joined by newlines; with colour, each run of
      # cells carries its depth tone (near bold, far dim). t is seconds on any
      # steady clock; events are what happened since the last frame
      # (Motion::EVENTS). level is the audio's loudness from 0.0 to 1.0 while
      # speaking, or nil when no envelope reached us. source is any point
      # source (Head by default); chars and mode replace the ramp and invert it
      # (MASTER_FACE_CHARS, MASTER_FACE_MODE=light). MASTER_FACE_QUIET=1 draws
      # the plain word only; CLI log quietness never hides the face. MASTER_REDUCED_MOTION=1
      # holds the head still.
      def frame(state:, rows:, cols:, t:, level: nil, events: [], motion: Motion.new, color: false, heard: false, viseme: "neutral", source: nil, chars: nil, mode: nil, show_laws: nil)
        raise ArgumentError, "face: unknown state #{state.inspect}" unless STATES.include?(state)

        look = motion.step(state:, t:, level:, events:, heard:, viseme:, count: 0)
        return word(state.to_s, rows, cols) unless rows >= MIN_ROWS && cols >= MIN_COLS && ENV["MASTER_FACE_QUIET"] != "1"

        look = look.with(yaw: 0.0, turn: 0.0, pitch: 0.0, roll: 0.0, scale: 1.0, dolly: 1.0, bob: 0.0, mix: 0.0, light: Motion::LIGHT.fetch("start")) if ENV["MASTER_REDUCED_MOTION"] == "1"
        look = look.with(turn: 0.0) if ENV["MASTER_FACE_ROTATE"] == "0"
        law_config = Master::Face::LawField.config
        enabled = law_config.fetch("terminal_law_ring", true) != false
        visible = enabled && (show_laws.nil? || !!show_laws)
        laws = visible ? Master::Face::LawField.laws : []
        head = source || Head.for(rows, cols)
        shaped = source.nil? && look.mix.positive? ? Masks.source(head, look.mask, look.mix) : head
        # A morphed head is new every frame, so it is not worth keeping.
        ascii = shaped.equal?(head) ? renderer(head, rows, cols, chars, mode) : Ascii.new(shaped, rows, cols, chars:, mode:)
        frame = ascii.render(look, state:, laws:)
        if source.nil? && Master::Face::Swarm.enabled? && ENV.fetch("MASTER_FACE_SWARM", "1") != "0"
          SWARMS.clear if SWARMS.size >= 4
          requested = ENV["MASTER_FACE_SWARM_BUDGET"]
          configured_budget = Integer(Master::Face::Swarm.config.fetch("particle_budget"))
          count = requested&.match?(/\A-?\d+\z/) ? Integer(requested).clamp(0, configured_budget) : nil
          swarm_key = [rows, cols, count]
          swarm = (SWARMS[swarm_key] ||= Master::Face::Swarm::Simulation.new(count:))
          swarm.step(mode: state, time: t, reduced_motion: ENV["MASTER_REDUCED_MOTION"] == "1", events:)
          swarm.overlay!(frame)
        end
        frame.to_s(color:)
      end

      def renderer(source, rows, cols, chars, mode)
        RENDERERS.clear if RENDERERS.size >= 6
        named_ramp = Glyphs::CONFIG.fetch("ramps", {}).fetch(ENV.fetch("MASTER_FACE_RAMP", "").to_s, Glyphs::DEFAULT_CHARS)
        chosen_chars = chars || ENV["MASTER_FACE_CHARS"] || named_ramp
        chosen_mode = mode || ENV["MASTER_FACE_MODE"] || Glyphs::CONFIG.fetch("mode")
        RENDERERS[[source.object_id, rows, cols, chosen_chars, chosen_mode]] ||= Ascii.new(source, rows, cols, chars: chosen_chars, mode: chosen_mode)
      end

      # The state's name, centred, on an otherwise empty window.
      def word(text, rows, cols)
        lines = Array.new(rows) { " " * cols }
        lines[rows / 2] = text[0, cols].center(cols)
        lines.join("\n")
      end

      # The mouth on a timer, for a player that gives no envelope back.
      def timed_level(tick) = ((Math.sin(tick * 1.1).abs * 0.7) + ((tick % 3) * 0.15)).clamp(0.0, 1.0)
    end
  end
end
