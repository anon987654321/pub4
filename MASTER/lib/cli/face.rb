# frozen_string_literal: true

module Master
  module CLI
    # The face drawn in text, for a window too small or too plain for WebGL:
    # Termux:Float on a phone. It is the web face itself, as ai.brgen.no draws
    # it: a cloud of points sampled from the same painted depth map
    # (Face::Head), stippled grey to white on black, a void in the lower face
    # where the points thin out, turned in 3D and projected onto Braille
    # dots, two across and four down in every cell. Where points pile into
    # one cell it burns brighter, in the 256-colour greys from 240 to 255.
    # Face::Motion keeps all of it moving.
    #
    # A frame is a function of state, size, time and events, with one small
    # mutable Motion carried from frame to frame. Nothing here touches the
    # terminal, which is what lets a test draw it at any size.
    module Face
      STATES = %i[idle listening thinking speaking].freeze
      FPS = 15
      # Below this there is not room for a face worth the name, and the frame
      # names the state instead.
      MIN_ROWS = 8
      MIN_COLS = 16

      module_function

      # rows lines of cols cells, joined by newlines; with colour, each run
      # of cells carries its grey. t is seconds on any steady clock; events
      # are what happened since the last frame (Motion::EVENTS). level is the
      # audio's loudness from 0.0 to 1.0 while speaking, or nil when no
      # envelope reached us, and the mouth moves on a timer.
      def frame(state:, rows:, cols:, t:, level: nil, events: [], motion: Motion.new, color: false)
        raise ArgumentError, "face: unknown state #{state.inspect}" unless STATES.include?(state)

        look = motion.step(state:, t:, level:, events:, count: ((rows * cols) / 40).clamp(8, 60))
        return Braille.new(rows, cols).word(state.to_s) unless rows >= MIN_ROWS && cols >= MIN_COLS

        braille = Braille.new(rows, cols)
        Drawing.new(braille, look, t).draw
        braille.to_s(color:)
      end

      # The mouth on a timer, for a player that gives no envelope back.
      def timed_level(tick) = ((Math.sin(tick * 1.1).abs * 0.7) + ((tick % 3) * 0.15)).clamp(0.0, 1.0)

      # A grid of Braille cells, each a two-by-four block of dots, with how
      # much light has landed in each cell and whether it holds the head.
      class Braille
        # The bit for the dot at [row][column] inside a cell, from U+2800.
        BITS = [[0x01, 0x08], [0x02, 0x10], [0x04, 0x20], [0x40, 0x80]].freeze
        BASE = 0x2800
        GREYS = (240..255)
        # A cell reads as fully lit from about three bright points.
        FULL = 2.5

        attr_reader :rows, :cols

        def initialize(rows, cols)
          @rows = [rows.to_i, 1].max
          @cols = [cols.to_i, 1].max
          @bits = Array.new(@rows * @cols, 0)
          @light = Array.new(@rows * @cols, 0.0)
          @head = Array.new(@rows * @cols, false)
        end

        def dots_wide = cols * 2
        def dots_high = rows * 4

        # A dot at x, y in dot units; head dots mark their cell as the head's,
        # and a speck lands only in a cell the head left empty.
        def dot(x, y, light, head: true)
          return if x.negative? || y.negative? || x >= dots_wide || y >= dots_high

          cell = ((y >> 2) * cols) + (x >> 1)
          return if !head && @head[cell]

          @bits[cell] |= BITS[y & 3][x & 1]
          @light[cell] += light
          @head[cell] = true if head
        end

        def head?(col, row) = @head[(row * cols) + col]
        def lit?(col, row) = @bits[(row * cols) + col].positive?

        def word(text)
          label = text[0, cols]
          lines = Array.new(rows) { " " * cols }
          lines[rows / 2] = label.center(cols)
          lines.join("\n")
        end

        def to_s(color: false)
          (0...rows).map { |row| line(row, color) }.join("\n")
        end

        private

        def line(row, color)
          text = +""
          grey = nil
          (row * cols).upto(((row + 1) * cols) - 1) do |cell|
            bits = @bits[cell]
            next text << " " if bits.zero?

            shade = GREYS.min + ((@light[cell] / FULL).clamp(0.0, 1.0) * (GREYS.size - 1)).round
            text << "\e[38;5;#{grey = shade}m" if color && shade != grey
            text << (BASE + bits).chr(Encoding::UTF_8)
          end
          color && grey ? "#{text}\e[0m" : text
        end
      end

      # One Look on the Braille grid at time t: every point turned, the far
      # half dropped so the eye and mouth voids read against the near half,
      # a third of the rest dropped afresh each frame for the shimmer, and
      # what is left dotted; then the specks.
      class Drawing
        CAMERA = 3.2
        # Only points nearer than this, after turning, are drawn.
        NEAR = -0.05
        SHIMMER = 0.35
        # The void between the lips at rest, and how far the loudest syllable
        # opens it, in the points' own units.
        VOID = 0.045
        VOID_OPEN = 0.085
        # A blink closes a socket; below this the lid is shut.
        SHUT = 0.5
        # Particles orbit in head units; the points span 0.62 of centre.
        SPECK_SPAN = 0.45
        SPECK_LIGHT = 0.35

        def initialize(braille, look, t)
          @braille = braille
          @look = look
          @t = t.to_f
          @head = Head.for(braille.rows, braille.cols)
          @shimmer = Random.new((@t * FPS).floor)
        end

        def draw
          points
          specks
        end

        private

        # The hot loop: every point, every frame. The turn is yaw, then
        # pitch, then roll, unpacked into locals and inlined, because on a
        # phone a method call per point is the difference between fifteen
        # frames a second and five. Positive pitch lowers the face toward
        # the input line.
        def points
          cy, sy, cp, sp, cr, sr = [@look.yaw, @look.pitch, @look.roll].flat_map { |a| [Math.cos(a), Math.sin(a)] }
          reach = @head.scale * @look.scale
          mid_x = @braille.dots_wide / 2.0
          mid_y = (@braille.dots_high / 2.0) - (@look.bob * @head.scale)
          @head.each_point do |x, y, z, lum, zone, phase|
            next if @shimmer.rand < SHIMMER

            unless zone.zero?
              x, y = feature(x, y, zone, phase)
              next unless x
            end

            rx = (x * cy) + (z * sy)
            rz = (-x * sy) + (z * cy)
            ry = (y * cp) - (rz * sp)
            rz = (y * sp) + (rz * cp)
            next if rz < NEAR

            depth = CAMERA / (CAMERA - rz) * reach
            px = mid_x + (((rx * cr) - (ry * sr)) * depth)
            py = mid_y - (((rx * sr) + (ry * cr)) * depth)
            @braille.dot(px.floor, py.floor, lum)
          end
        end

        # Where a point of the face goes this frame, or nil where there is a
        # void: the socket round an open eye is empty but for the pupil,
        # which follows the gaze; a closing lid gathers the socket to a line;
        # the mouth void opens with the audio and thins at its rim.
        def feature(x, y, zone, phase)
          mouth_x, mouth_y = @head.mouth
          void = VOID + (VOID_OPEN * @look.mouth)
          if zone == Head::MOUTH_ZONE
            return if ((x - mouth_x)**2) + ((y - mouth_y)**2) < void * void * (0.7 + (0.3 * Math.sin(phase * 7)))

            return [x, y]
          end

          eye_x, eye_y = x.negative? ? @head.eyes[0] : @head.eyes[1]
          open = @look.eye_open
          return [x, eye_y + ((y - eye_y) * open)] if open < SHUT
          return if zone == Head::EYE_ZONE

          gaze_x, gaze_y = @look.gaze
          [x + (gaze_x * 0.3), y + (gaze_y * 0.3)]
        end

        def specks
          reach = @head.scale * SPECK_SPAN
          mid_x = @braille.dots_wide / 2.0
          mid_y = @braille.dots_high / 2.0
          @look.particles.each do |x, y, z|
            depth = CAMERA / (CAMERA - (z * SPECK_SPAN))
            @braille.dot((mid_x + (x * depth * reach)).floor, (mid_y - (y * depth * reach)).floor, SPECK_LIGHT, head: false)
          end
        end
      end
    end
  end
end
