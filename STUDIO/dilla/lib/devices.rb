# frozen_string_literal: true

# The devices: small machines with one idea each.
#
# Three files' worth of ringtone.tools-shaped primitives, in one, because they
# are one thing. Each takes a musical idea that is normally indivisible and
# splits it:
#
#   CopyMachine   one sound becomes several, at different speeds, at once.
#   Hocket        one line becomes an ensemble handing it between voices.
#   Bag           a note's PITCH and its TIME come from different parts.
#   WavMap        a picture becomes an oscillator.
#
# They were written as copy_machine.rb, midi_devices.rb and wav_map.rb and
# merged on the standing order in soul.yml: COLLAPSE_BEFORE_ADDING says try
# nine moves before writing a new file, and FLAT_HIERARCHY makes aggressive
# merge the default on every write. Three siblings of 79, 84 and 126 code lines
# that arrived in one change, share one purpose and are called from the same
# places are the "merge thin siblings into one" case exactly.
#
# What is NOT merged in here, and why: DillaModulation moves parameters rather
# than making sound, and lives with the automation it completes; DillaMacros is
# about knobs and lives with knobs.rb. Grouping by "things I added" rather than
# by what they are would be the same mistake in a bigger file.

# ------------------------------------------------------------------------
# CopyMachine
# ------------------------------------------------------------------------

# One sound, played several times at once, at different speeds.
#
# ringtone.tools' Copy Machine is the clearest small statement of an old idea:
# take a sample, play up to thirty-two copies of it simultaneously at different
# playback rates, let some of them run backwards. It is not a chorus and it is
# not a pitch shifter. Every copy is the whole sound at its own speed, so the
# copies drift apart in TIME as well as pitch -- a copy at 0.5x is still playing
# the first bar when the original is on the second -- and what comes out is a
# smeared, self-harmonising cloud that no single-voice effect produces.
#
# This engine already has the nearest thing to it and it is not the same thing.
# The granular pad cloud (pad_layers.rb) does simultaneous grains with octave
# shimmer, sub-octave haze and reversal -- but grains, at 30-400 ms, confined to
# the pad layer and to the chord sounding underneath each grain. organic_vary.rb
# does multi-speed copies of a loop but SEQUENTIALLY, concatenated pass after
# pass, so at any instant exactly one copy is sounding. Neither stacks whole
# copies of a sound on top of each other, which is the entire effect here.
#
# Varispeed, not pitch shift, and this is the decision the sound rests on.
# asetrate resamples: pitch and duration move together, the way a tape machine
# or a sampler's pitch knob does. A formant-preserving shift would keep every
# copy the same length and turn this into a chord; letting them run at their own
# lengths is what makes it a cloud. sample_loops.rb reaches the same conclusion
# for the same reason and says so.
module CopyMachine
  module_function

  # Speeds, as ratios to the original.
  #
  # Two families, because the choice between them is musical rather than
  # technical and neither is right for everything.
  #
  #   :harmonic   ratios from the harmonic series and its inverse -- 2, 3/2, 4/3,
  #               1/2, 2/3. Every copy lands on a note the original already
  #               implies, so a chord comes out sounding like one instrument
  #               played wide rather than like several instruments disagreeing.
  #               This is the default because the material this engine makes is
  #               harmonic and a cloud that fights the chord is noise.
  #
  #   :chromatic  equal-tempered semitone steps. Denser and more synthetic; the
  #               copies are in tune with the twelve-tone grid rather than with
  #               the sound's own overtones, which reads as a machine.
  #
  #   :spray      irrationals. Nothing is in tune with anything, which past four
  #               or five copies stops being harmony and becomes texture. The
  #               Copy Machine setting, and the one that sounds least like a
  #               plugin.
  RATIOS = {
    harmonic: [1.0, 2.0, 0.5, 1.5, 0.6667, 3.0, 0.3333, 1.3333,
               0.75, 4.0, 0.25, 2.5, 0.4, 1.25, 0.8, 5.0].freeze,
    chromatic: (-8..7).map { |s| (2.0**(s / 12.0)).round(6) }.freeze,
    spray: [1.0, 1.4142, 0.7071, 1.7321, 0.5774, 2.2361, 0.4472, 1.2599,
            0.7937, 2.6458, 0.3780, 1.5874, 0.6300, 3.3166, 0.3015, 1.9129].freeze,
  }.freeze

  # A copy slower than this is a drone rather than a copy -- the sound stops
  # being recognisable as itself, which is the point at which the effect stops
  # being Copy Machine and becomes a stretch. Faster than 6x it is a click.
  MIN_RATIO = 0.2
  MAX_RATIO = 6.0

  # The plan, as data, so it can be printed and pinned in a test without
  # rendering anything. Every decision this module makes is made here.
  Copy = Struct.new(:index, :ratio, :reverse, :pan, :delay_ms, :gain, keyword_init: true)

  # copies:  how many, including the original.
  # family:  :harmonic, :chromatic or :spray.
  # reverse: fraction of copies played backwards, 0..1.
  # width:   stereo spread, 0 (all centre) to 1 (hard across).
  # drift:   maximum start offset in ms, spread across the copies. Zero starts
  #          them together, which is a flam; a few hundred ms is what makes the
  #          cloud sound like it has depth rather than like a stacked chord.
  # tilt:    per-copy gain slope. Copies far from 1.0 are the strange ones and
  #          at equal level they dominate; this pulls them down as the ratio
  #          departs from unity, which keeps the original recognisable.
  def plan(copies:, family: :harmonic, reverse: 0.25, width: 0.8, drift: 220.0,
           tilt: 0.55, seed: 4242)
    ratios = RATIOS.fetch(family.to_sym) { RATIOS[:harmonic] }
    rng = Random.new(seed)
    n = copies.to_i.clamp(1, 32)
    (0...n).map do |i|
      ratio = ratios[i % ratios.length].to_f.clamp(MIN_RATIO, MAX_RATIO)
      # Copy 0 is the sound itself: never reversed, never delayed, never panned.
      # Without an anchor the effect has no centre and reads as a broken file.
      anchor = i.zero?
      octaves = Math.log2(ratio).abs
      Copy.new(
        index: i,
        ratio: ratio,
        reverse: !anchor && rng.rand < reverse.to_f.clamp(0.0, 1.0),
        # Alternating sides rather than random ones: random panning of a small
        # number of copies lands them all on one side often enough to matter.
        pan: anchor ? 0.0 : ((i.odd? ? 1 : -1) * width.to_f.clamp(0.0, 1.0) *
                             (0.35 + (0.65 * rng.rand))).round(3),
        delay_ms: anchor ? 0 : (rng.rand * drift.to_f).round,
        gain: (anchor ? 1.0 : 1.0 / (1.0 + (tilt.to_f * octaves))).round(4)
      )
    end
  end

  # The filter_complex for a plan, given the input index the source arrives on.
  #
  # One input, split N ways, rather than N inputs of the same file: ffmpeg
  # decodes once instead of N times, and on a 40 MB WAV with sixteen copies that
  # is the difference between a render and a wait.
  #
  # -stream_loop is the caller's business. A copy at 0.5x needs twice the source
  # to fill the same duration and a copy at 3x needs a third of it; whether the
  # shortfall is looped, padded or left short is a musical choice, so this pads
  # with silence and says so rather than deciding.
  def filter_complex(plan, input: "0:a", out: "copies", rate: 44_100, duration: nil)
    branches = ["[#{input}]asplit=#{plan.length}#{(0...plan.length).map { |i| "[cm#{i}]" }.join}"]
    labels = []
    plan.each do |copy|
      steps = ["aformat=channel_layouts=stereo"]
      # Reverse BEFORE the varispeed. areverse buffers the whole stream, so
      # reversing the shorter, faster version is cheaper -- and reversing after
      # a delay would reverse the silence into the tail instead of the head.
      steps << "areverse" if copy.reverse
      unless copy.ratio == 1.0
        steps << "asetrate=#{(rate * copy.ratio).round}"
        steps << "aresample=#{rate}"
      end
      steps << "adelay=#{copy.delay_ms}|#{copy.delay_ms}" if copy.delay_ms.positive?
      # A stereo pan as two channel gains. `pan` is exact where apulsator or a
      # haas delay would be an effect; this is placement, not width.
      unless copy.pan.zero?
        l = (1.0 - [copy.pan, 0.0].max).round(4)
        r = (1.0 + [copy.pan, 0.0].min).round(4)
        steps << "pan=stereo|c0=#{l}*c0|c1=#{r}*c1"
      end
      steps << "volume=#{copy.gain}"
      steps << "atrim=0:#{duration},apad=whole_dur=#{duration},asetpts=PTS-STARTPTS" if duration
      branches << "[cm#{copy.index}]#{steps.join(',')}[cmo#{copy.index}]"
      labels << "[cmo#{copy.index}]"
    end
    # normalize=0, for the reason audio_graph.rb gives: amix's default rescales
    # by input count, so adding a quiet copy would drop every other one.
    #
    # The closing gain is 1/sqrt(n) rather than 1/n. These copies are at
    # different speeds and therefore uncorrelated, so they sum as power rather
    # than as amplitude; 1/n would leave a sixteen-copy cloud four times quieter
    # than it should be, which is the mistake that makes a stacked effect read
    # as "it did nothing".
    branches << "#{labels.join}amix=inputs=#{plan.length}:" \
                "weights=#{plan.map(&:gain).join(' ')}:duration=longest:normalize=0," \
                "volume=#{(1.0 / Math.sqrt(plan.length)).round(4)}[#{out}]"
    branches.join(";")
  end

  # Render a plan over a file. Returns dest, or nil when the source is missing --
  # the engine's convention for an optional layer that could not be built.
  def build!(src:, dest:, copies: 6, family: :harmonic, reverse: 0.25, width: 0.8,
             drift: 220.0, tilt: 0.55, seed: 4242, duration: nil, rate: 44_100)
    return nil unless src && File.file?(src)

    made = plan(copies:, family:, reverse:, width:, drift:, tilt:, seed:)
    graph = filter_complex(made, input: "0:a", out: "copies", rate:, duration:)
    # Slower copies need more source than exists. Looping the input is the only
    # way to fill the duration without the cloud thinning out at the end, and it
    # is what a sampler holding a loop would do.
    args = ["ffmpeg", "-y"]
    args += ["-stream_loop", "-1"] if duration
    args += ["-i", src, "-filter_complex", graph, "-map", "[copies]"]
    args += ["-t", duration.to_s] if duration
    args += ["-ar", rate.to_s, "-ac", "2", "-c:a", "pcm_s16le", dest]
    sh!(*args)
    dest
  end

  # What a plan is, in one line per copy. `dilla copy-machine --describe`.
  def describe(plan)
    plan.map do |c|
      format("copy %2d  %sx%-8s %-9s pan %+.2f  +%dms  gain %.3f",
             c.index, c.ratio >= 1 ? " " : "", c.ratio.round(4),
             c.reverse ? "REVERSED" : "", c.pan, c.delay_ms, c.gain)
    end
  end
end

# ------------------------------------------------------------------------
# MidiDevices
# ------------------------------------------------------------------------

# Two devices that rearrange notes rather than process sound.
#
# Both come from ringtone.tools and both are the same kind of idea: take
# something a sequencer treats as one indivisible thing and split it in two, so
# the halves can come from different places. They are in one file because they
# share the engine's note-event contract, and a change to that contract has to
# change both or neither.
#
# THE CONTRACT. A note event here is what write_smf and the pad/lead renderers
# already pass around:
#
#   [time_seconds, velocity_0_to_1, { hz: [frequencies] }, sustain_seconds]
#
# Nothing below invents a note. Every note that comes out of these went in --
# what changes is when it sounds, or which voice it comes out of. That is the
# whole reason they are safe to add to an engine whose harmony is already
# decided elsewhere: they cannot produce a pitch the progression did not.
module MidiDevices
  # ------------------------------------------------------------------ Hocket
  #
  # One line, distributed across several destinations.
  #
  # Named for the medieval technique -- hoquetus, a hiccup -- where a single
  # melody is split between two voices that alternate note by note, so neither
  # sings the tune and both do. Ringtone's Hocket II sends incoming notes to up
  # to eight MIDI channels; the musical effect is that a line played on one
  # instrument becomes a line played BY an ensemble, and the ear reconstructs it.
  #
  # Nothing in this engine does this. There is no voice allocation anywhere: a
  # lead is a lead, a pad is a pad, and a phrase belongs to whichever renderer
  # made it start to finish. Which is why a dilla render can sound like several
  # loops playing at once rather than like several players in a room -- the parts
  # never hand anything to each other.
  module Hocket
    module_function

    # How the next note picks its voice.
    #
    #   :round_robin  1, 2, 3, 4, 1, 2, 3, 4. Even, predictable, and the one that
    #                 reads most clearly as a deliberate effect.
    #   :pendulum     1, 2, 3, 4, 3, 2, 1, 2. Turns at the ends instead of
    #                 jumping back, so the line travels across the ensemble and
    #                 returns rather than snapping. Ringtone II added this and it
    #                 is the more musical of the two by a distance.
    #   :shift_register  an analog shift register: a bit is clocked along a chain
    #                 and a new one enters at random. Voices repeat in runs and
    #                 then change, which is how a pattern that is not a pattern
    #                 sounds. This is the Buchla/Serge idea, not a random choice
    #                 with a nice name -- the state is a register and it shifts.
    #   :random       independent draws. Included because it is the honest
    #                 baseline the others should be compared against.
    MODES = %i[round_robin pendulum shift_register random].freeze

    # events:  note events, in any order (sorted here).
    # voices:  how many destinations.
    # mode:    one of MODES.
    # hold:    how many consecutive notes stay on one voice before moving on.
    #          1 is note-by-note, the classical hocket. 2 or 3 gives each voice a
    #          fragment rather than a note, which on a fast line is the
    #          difference between an effect and a mess.
    #
    # Returns an array of `voices` event arrays, index-aligned with the voice
    # number, so the caller can render each through a different patch.
    def split(events, voices: 4, mode: :pendulum, hold: 1, seed: 4242)
      n = voices.to_i.clamp(1, 8)
      return [Array(events)] if n == 1

      rng = Random.new(seed)
      out = Array.new(n) { [] }
      register = Array.new(n) { rng.rand(n) }
      cursor = 0
      direction = 1
      Array(events).sort_by { |e| e[0].to_f }.each_with_index do |event, i|
        out[cursor % n] << event
        # The voice advances only when the hold is used up. Advancing per note
        # and then dividing by hold would put the SAME note on several voices,
        # which is a doubling, not a hocket.
        next unless ((i + 1) % [hold.to_i, 1].max).zero?

        case mode.to_sym
        when :round_robin then cursor += 1
        when :pendulum
          # Turn at the ends without repeating the end voice: at the top the next
          # is n-2, not n-1 again. Repeating it makes one voice twice as busy as
          # the others and the travel stops reading as travel.
          cursor += direction
          if cursor >= n - 1
            cursor = n - 1
            direction = -1
          elsif cursor <= 0
            cursor = 0
            direction = 1
          end
        when :shift_register
          register.rotate!(-1)
          register[-1] = rng.rand(n)
          cursor = register.first
        else cursor = rng.rand(n)
        end
      end
      out
    end

    # A line and its split, as one line per voice, for `dilla hocket`.
    def describe(split_events)
      total = split_events.sum(&:length)
      split_events.each_with_index.map do |voice, i|
        share = total.zero? ? 0 : (100.0 * voice.length / total).round
        format("voice %d  %3d note(s)  %2d%%  first at %.2fs",
               i + 1, voice.length, share, voice.first ? voice.first[0].to_f : 0.0)
      end
    end
  end

  # ----------------------------------------------------------------- MIDI Bag
  #
  # Pitch from one place, rhythm from another.
  #
  # Ringtone's MIDI Bag records some notes, then switches mode: incoming MIDI
  # becomes the TIMING and the recorded notes supply the PITCHES. A note event is
  # normally an indivisible pair -- this note, at this moment -- and the device
  # simply refuses that pairing. What comes out is the melody's notes in the
  # drums' rhythm, or the bassline's pitches on the hi-hat grid.
  #
  # WHAT THIS ENGINE ALREADY HAS, and why this is still worth adding. sample_flip
  # does the same separation and does it better in one respect: it detects the
  # pitch of each slice of a record and chooses, per beat, the slice that fits
  # the chord underneath -- pitch source and time source separated AND
  # harmonically constrained. But it does it for audio slices only, and only
  # inside its own four-step pipeline. Nothing does it for note events, so a
  # melody the engine generated cannot be re-rhythmed by a pattern the engine
  # also generated. That is the gap.
  #
  # The harmonic constraint is worth keeping though, so it is offered here:
  # `chord_at` lets the caller pass the progression, and pitches that do not fit
  # the chord under their new position can be nudged to one that does. Off by
  # default, because the whole point of the device is that the pitches come from
  # somewhere else and forcing them into the chord is one way to lose that.
  module Bag
    module_function

    # How the bag hands out its stored pitches.
    #
    #   :cycle    in order, wrapping. The stored phrase's contour survives, laid
    #             onto a new rhythm.
    #   :random   drawn each time. The contour is gone; what is left is the
    #             pitch SET, which is a different and sometimes better thing.
    #   :walk     one step forward or back from the last pick. Keeps the notes
    #             adjacent, so it sounds played rather than dealt.
    ORDERS = %i[cycle random walk].freeze

    # pitches: the bag, as note events -- only their `hz` and velocity are used.
    # timing:  events whose TIMES and sustains are taken, pitches discarded.
    # order:   how pitches are drawn.
    # velocity_from: :timing keeps the rhythm source's dynamics, which is almost
    #          always what is wanted -- a drum pattern's accents are the reason
    #          to borrow its timing. :pitches keeps the melody's own.
    # rests:   fraction of timing events that produce no note at all. A bag with
    #          no rests fills every slot and reads as a sequencer running; a few
    #          rests are what makes it read as a part.
    def apply(pitches:, timing:, order: :cycle, velocity_from: :timing,
              rests: 0.0, seed: 4242, chord_at: nil)
      bag = Array(pitches).filter_map { |e| e[2] if e[2].is_a?(Hash) && Array(e[2][:hz]).any? }
      return [] if bag.empty?

      rng = Random.new(seed)
      cursor = 0
      Array(timing).sort_by { |e| e[0].to_f }.filter_map do |slot|
        next if rests.positive? && rng.rand < rests.to_f.clamp(0.0, 1.0)

        cursor = case order.to_sym
                 when :random then rng.rand(bag.length)
                 when :walk then (cursor + (rng.rand < 0.5 ? -1 : 1)) % bag.length
                 else (cursor + 1) % bag.length
                 end
        chord = bag[cursor]
        chord = fit_to_chord(chord, chord_at.call(slot[0].to_f)) if chord_at
        velocity = velocity_from.to_sym == :pitches ? source_velocity(pitches, cursor) : slot[1]
        [slot[0], velocity, chord, slot[3]]
      end
    end

    def source_velocity(pitches, index)
      event = Array(pitches)[index % Array(pitches).length]
      event ? event[1] : 0.8
    end

    # Move each pitch to the nearest note of the chord it now sits under, in
    # OCTAVE-FREE terms: the pitch keeps its register and changes its pitch
    # class. Transposing to the literal nearest chord tone would collapse a
    # two-octave phrase into whatever octave the chord was voiced in.
    def fit_to_chord(chord, target)
      return chord unless target.is_a?(Hash) && Array(target[:hz]).any?

      classes = Array(target[:hz]).map { |hz| (12.0 * Math.log2(hz / 440.0)).round % 12 }
      moved = Array(chord[:hz]).map do |hz|
        midi = 12.0 * Math.log2(hz / 440.0)
        pc = midi.round % 12
        best = classes.min_by { |c| [(c - pc) % 12, (pc - c) % 12].min }
        shift = [(best - pc) % 12, -((pc - best) % 12)].min_by(&:abs)
        440.0 * (2.0**((midi.round + shift) / 12.0))
      end
      chord.merge(hz: moved)
    end
  end
end

# ------------------------------------------------------------------------
# WavMap
# ------------------------------------------------------------------------

# A picture, read as a waveform.
#
# ringtone.tools' wav_Map treats an image as a height field -- brightness is
# elevation -- and traces a closed path across that surface. The heights along
# the path, in order, are one cycle of a waveform. Play that cycle at a pitch and
# the picture becomes a tone whose harmonic content is the picture's texture.
#
# The path is CLOSED for a reason that is not decorative: a cycle whose end does
# not meet its start has a step discontinuity at the loop point, and a step
# repeating at the fundamental is a buzz at every harmonic. Closing the path
# makes the waveform periodic by construction, which is the difference between
# an instrument and a fault.
#
# This is the one direction this engine could not go. spectral_audit.rb already
# renders audio TO an image -- showspectrumpic, for auditing -- and nothing goes
# the other way. STUDIO has three image tools sitting next to dilla (postpro,
# repligen, lora) whose output has never been able to reach the audio engine at
# all, and this is the shortest honest bridge between them: a repligen frame or
# a postpro grade becomes an oscillator.
#
# Pure Ruby on raw samples, like sample_flip and the grain cloud, with ffmpeg
# used only to decode the image. Decoding a PNG in Ruby means zlib and an
# unfilter loop and a new maintenance surface; ffmpeg already reads every format
# this repo will ever hand it and hands back a grid of bytes.
module WavMap
  module_function

  # The surface is square and this size. Larger buys nothing: the path samples
  # WAVETABLE_LEN points from it, so a 512x512 grid is already oversampled for a
  # 2048-point cycle unless the path is very long, and a 4K source would spend
  # its time being averaged away.
  GRID = 512

  # One cycle. A power of two because it is resampled by simple indexing, and
  # 2048 puts the first aliasing artefact above 20 kHz for any fundamental below
  # about 10 Hz -- which is every fundamental.
  WAVETABLE_LEN = 2048

  # Paths across the surface. Each takes t in 0...1 and returns [x, y] in 0..1,
  # and each is CLOSED: path(0) == path(1).
  #
  #   :circle     one loop. The simplest, and the one where the waveform is
  #               most obviously "a slice of the picture" -- one ring of it.
  #   :spiral     in from the edge and back out, so the whole radius is visited.
  #               Reads as a sweep, because the picture's coarse structure and
  #               its fine structure arrive at different points in the cycle.
  #   :lissajous  a closed Lissajous figure. Visits the surface densely and
  #               unevenly, which puts inharmonic partials in -- this is the one
  #               that sounds least like a filter and most like a new instrument.
  #   :rose       a rhodonea curve. Petals, so the cycle has repeating sub-shapes
  #               and therefore strong harmonics at the petal count.
  PATHS = %i[circle spiral lissajous rose].freeze

  def path_point(kind, t, lobes: 5)
    a = 2.0 * Math::PI * t
    case kind.to_sym
    when :spiral
      # Out and back within one cycle, so the path closes. A spiral that only
      # goes inward ends at the centre and starts at the edge, which is the
      # discontinuity this whole design exists to avoid.
      r = 0.48 * (1.0 - (2.0 * (t - 0.5).abs))
      turns = 4.0
      [0.5 + (r * Math.cos(a * turns)), 0.5 + (r * Math.sin(a * turns))]
    when :lissajous
      # 3:2 closes after one full cycle; 3:4 or 5:4 would too. Non-integer
      # ratios never close, which is why the ratio is not a free parameter.
      [0.5 + (0.46 * Math.sin(3.0 * a)), 0.5 + (0.46 * Math.sin(2.0 * a))]
    when :rose
      r = 0.46 * Math.cos(lobes * a).abs
      [0.5 + (r * Math.cos(a)), 0.5 + (r * Math.sin(a))]
    else
      [0.5 + (0.42 * Math.cos(a)), 0.5 + (0.42 * Math.sin(a))]
    end
  end

  # The image as a GRID x GRID array of 0..255 brightness, via ffmpeg.
  # Returns nil rather than raising: an unreadable image is a layer that cannot
  # be built, which the engine treats as a layer that is absent.
  def height_field(image_path)
    return nil unless image_path && File.file?(image_path)

    raw = IO.popen(["ffmpeg", "-v", "error", "-i", image_path,
                    "-vf", "scale=#{GRID}:#{GRID}:flags=area,format=gray",
                    "-frames:v", "1", "-f", "rawvideo", "-"],
                   "rb", err: File::NULL, &:read)
    return nil if raw.nil? || raw.bytesize < GRID * GRID

    raw.unpack("C*")
  end

  # Bilinear, not nearest. Nearest-neighbour sampling of a path across a pixel
  # grid produces stair-steps, and a stair-step in a waveform is a square edge --
  # broadband harmonics that came from the sampling and not from the picture.
  def sample(field, x, y)
    fx = (x.clamp(0.0, 1.0) * (GRID - 1))
    fy = (y.clamp(0.0, 1.0) * (GRID - 1))
    x0 = fx.floor
    y0 = fy.floor
    x1 = [x0 + 1, GRID - 1].min
    y1 = [y0 + 1, GRID - 1].min
    tx = fx - x0
    ty = fy - y0
    top = (field[(y0 * GRID) + x0] * (1 - tx)) + (field[(y0 * GRID) + x1] * tx)
    bot = (field[(y1 * GRID) + x0] * (1 - tx)) + (field[(y1 * GRID) + x1] * tx)
    (top * (1 - ty)) + (bot * ty)
  end

  # One cycle, centred and normalised to -1..1.
  #
  # The DC removal is not tidiness. A picture's average brightness becomes a DC
  # offset in the waveform, and a wavetable with DC in it thumps once per cycle
  # at the fundamental and eats headroom for the rest of the render.
  def wavetable(image_path, path: :circle, lobes: 5, len: WAVETABLE_LEN)
    field = height_field(image_path) or return nil

    points = (0...len).map do |i|
      x, y = path_point(path, i.to_f / len, lobes:)
      sample(field, x, y)
    end
    mean = points.sum / points.length
    centred = points.map { |v| v - mean }
    peak = centred.map(&:abs).max
    return nil if peak.nil? || peak < 1e-9

    centred.map { |v| (v / peak).clamp(-1.0, 1.0) }
  end

  # Play the table at a pitch, for a duration, as 16-bit stereo PCM.
  #
  # Linear interpolation between table entries rather than index rounding: at
  # 110 Hz a 2048-point table advances about 5.6 entries per sample, and rounding
  # that produces a jitter sideband on every partial.
  #
  # Bandlimiting is a lowpass at the end rather than a properly bandlimited
  # oscillator. An honest description of the compromise: a picture's fine texture
  # IS high harmonic content, and at 110 Hz a 2048-point table's top partials sit
  # well above Nyquist and fold. The lowpass removes what folded down where it is
  # audible and does not pretend the table was bandlimited. Making this right
  # needs a mip-mapped table per octave, which is a bigger piece of work than the
  # bridge this file is.
  def render!(image_path, dest, hz: 110.0, duration: 8.0, path: :circle, lobes: 5,
              rate: 44_100, drift_cents: 6.0, seed: 4242)
    table = wavetable(image_path, path:, lobes:) or return nil

    rng = Random.new(seed)
    frames = (duration * rate).to_i
    len = table.length
    phase = 0.0
    # Two voices a few cents apart, hard-ish panned. One voice of a static
    # wavetable is dead still -- there is no vibrato, no envelope, nothing
    # moving -- and reads as a test tone rather than an instrument. Two detuned
    # copies beat slowly against each other, which is the cheapest life there is.
    phase_b = 0.0
    step_a = len * hz / rate
    step_b = len * hz * (2.0**(drift_cents / 1200.0)) / rate
    left = Array.new(frames, 0)
    right = Array.new(frames, 0)
    frames.times do |i|
      a = interpolate(table, phase)
      b = interpolate(table, phase_b)
      # A short fade at both ends. A wavetable started mid-cycle at full level
      # is a click, and this file's whole argument is about discontinuities.
      env = fade(i, frames, rate)
      left[i]  = ((a * 0.62) + (b * 0.38)) * env * 26_000
      right[i] = ((a * 0.38) + (b * 0.62)) * env * 26_000
      phase = (phase + step_a) % len
      phase_b = (phase_b + step_b) % len
    end
    write_wav(dest, left, right, rate)
    dest
  end

  def interpolate(table, phase)
    i = phase.floor
    frac = phase - i
    (table[i % table.length] * (1.0 - frac)) + (table[(i + 1) % table.length] * frac)
  end

  def fade(i, frames, rate)
    edge = (0.01 * rate).to_i
    return i.to_f / edge if i < edge
    return (frames - i).to_f / edge if i > frames - edge

    1.0
  end

  def write_wav(dest, left, right, rate)
    frames = left.length
    data = Array.new(frames * 2)
    frames.times do |i|
      data[i * 2] = left[i].round.clamp(-32_768, 32_767)
      data[(i * 2) + 1] = right[i].round.clamp(-32_768, 32_767)
    end
    body = data.pack("s<*")
    File.binwrite(dest, [
      "RIFF", 36 + body.bytesize, "WAVE", "fmt ", 16, 1, 2, rate,
      rate * 4, 4, 16, "data", body.bytesize,
    ].pack("a4Va4a4VvvVVvva4V") + body)
    dest
  end

  # What a picture sounds like, before rendering it: the harmonic content of its
  # cycle, so a source can be judged without listening to eight seconds of it.
  def describe(image_path, path: :circle, lobes: 5)
    table = wavetable(image_path, path:, lobes:) or return ["unreadable: #{image_path}"]

    # A cheap DFT over the first sixteen partials. Not an FFT -- sixteen bins of
    # a 2048-point table is 32k operations, which is nothing, and writing an FFT
    # here to save it would be the wrong kind of thrift.
    n = table.length
    partials = (1..16).map do |h|
      re = im = 0.0
      table.each_with_index do |v, i|
        a = 2.0 * Math::PI * h * i / n
        re += v * Math.cos(a)
        im -= v * Math.sin(a)
      end
      Math.sqrt((re * re) + (im * im)) / (n / 2.0)
    end
    peak = partials.max
    lines = ["#{File.basename(image_path)} via #{path}: #{n}-point cycle"]
    partials.each_with_index do |v, i|
      db = v <= 0 || peak <= 0 ? -99.0 : 20 * Math.log10(v / peak)
      bar = "#" * [(40 + (db / 1.5)).round, 0].max
      lines << format("  h%-3d %6.1f dB %s", i + 1, db, bar)
    end
    lines
  end
end

# ------------------------------------------------------------------------
# LowPassGate
# ------------------------------------------------------------------------

# The Buchla low-pass gate: loudness and brightness fall together.
#
# Every dynamic stage in this engine separates the two. A VCA changes level and
# leaves the tone alone; a filter changes tone and leaves the level alone; the
# grain cloud and the tape model touch neither. So a note here decays by getting
# quieter while staying exactly as bright as it started, which is a thing no
# acoustic sound does -- strike anything and its top end dies before its
# amplitude does, because the high partials are damped hardest.
#
# An LPG is that coupling made into a module. One control opens both a gain and a
# lowpass, so a decaying note darkens as it fades. It is the single reason
# West-Coast synthesis sounds struck rather than played, and there was nothing in
# this engine that could do it.
#
# THE VACTROL IS THE INSTRUMENT. A photocell facing an LED responds fast to light
# arriving and slowly to light leaving, and the slow side is not exponential --
# it is a lag whose time constant grows as the cell darkens. That asymmetry is
# what separates an LPG from a filter and a VCA wired to the same envelope; the
# same patch with a linear envelope sounds synthetic, and the difference is
# entirely in the decay's shape.
#
# Pure Ruby on samples, for the reason tape_hysteresis.rb gives about its own
# model: this is per-sample state, output depends on history, and no ffmpeg
# filter has the behaviour. Reuses SampleFlip's decode/encode so the file paths
# are the ones the rest of the engine already uses.
module LowPassGate
  module_function

  # Attack is fast and roughly fixed. Decay is slow and gets slower as the
  # control falls, which is the vactrol's defining nonlinearity: the tail of a
  # note lasts longer than its shape predicts.
  ATTACK_MS = 3.0
  DECAY_MS = 220.0
  # How much the decay stretches as the cell darkens. At 0 this is an ordinary
  # one-pole and the whole point is lost.
  VACTROL_DROOP = 2.4

  # The cutoff at full open, and at fully closed. The floor is what makes a dying
  # note dark rather than merely quiet, and it is low on purpose -- an LPG that
  # bottoms out at 2 kHz still sounds like a filter sweep.
  OPEN_HZ = 12_000.0
  CLOSED_HZ = 180.0

  # How much of the control drives the gain versus the filter.
  #
  # A real LPG offers three modes -- gate (gain only), filter (tone only) and
  # combined -- and combined is the one people mean. `blend` at 1.0 is combined,
  # 0.0 is a plain VCA, and anything between is available because a bass part
  # usually wants less filter than a pluck does.
  def process(samples, rate: 44_100, blend: 1.0, attack_ms: ATTACK_MS,
              decay_ms: DECAY_MS, droop: VACTROL_DROOP, depth: 1.0)
    return samples if samples.empty?

    attack = Math.exp(-1.0 / ((attack_ms / 1000.0) * rate))
    decay_base = (decay_ms / 1000.0) * rate
    control = 0.0
    lp = 0.0
    peak = samples.map(&:abs).max.to_f
    return samples if peak.zero?

    samples.map do |sample|
      # Rectified envelope of the input drives the cell. A real LPG is driven by
      # a control voltage, but driving it from the signal is what makes this
      # usable on material the engine has already rendered.
      level = sample.abs / peak
      if level > control
        control = level + ((control - level) * attack)
      else
        # The droop: as the control falls, the time constant grows, so the tail
        # stretches. This is the whole vactrol.
        stretch = 1.0 + (droop * (1.0 - control))
        coeff = Math.exp(-1.0 / (decay_base * stretch))
        control *= coeff
      end
      opened = control * depth.clamp(0.0, 1.0)
      # Cutoff geometrically between closed and open: the ear hears cutoff in
      # octaves, so a linear sweep spends most of its travel where nothing is.
      hz = CLOSED_HZ * ((OPEN_HZ / CLOSED_HZ)**opened)
      a = 1.0 - Math.exp(-2.0 * Math::PI * hz / rate)
      lp += a * (sample - lp)
      gated = (lp * blend) + (sample * (1.0 - blend))
      # Floats out, floats in. SampleFlip decodes to -1..1 and encodes from
      # -1..1; rounding here silenced the whole signal, because every sample in
      # that range rounds to 0 or +-1. The one line that made a working DSP model
      # produce digital silence.
      gated * ((1.0 - blend) + (opened * blend))
    end
  end

  # Process a file in place through the gate. Returns dest, or nil when the
  # source is missing -- the engine's convention for an optional layer.
  def build!(src:, dest:, rate: 44_100, blend: 1.0, depth: 1.0,
             attack_ms: ATTACK_MS, decay_ms: DECAY_MS, droop: VACTROL_DROOP)
    return nil unless src && File.file?(src)

    left, right = SampleFlip.decode(src, rate:)
    return nil if left.nil? || left.empty?

    SampleFlip.encode!(
      process(left, rate:, blend:, depth:, attack_ms:, decay_ms:, droop:),
      process(right, rate:, blend:, depth:, attack_ms:, decay_ms:, droop:),
      dest
    )
    File.file?(dest) ? dest : nil
  end
end
