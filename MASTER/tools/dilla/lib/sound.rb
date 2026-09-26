# frozen_string_literal: true

# Instruments and signal: the mixer, the oscillators, the device rack, space
# effects, the outboard emulations, the spectral engine, the DFAM voice, tape,
# modulation and the console strip.

# Ableton-Live-shaped vocabulary for dilla's mix: named Tracks (stems) with a
# Volume/Pan/Sends, each carrying an ordered Device chain, plus a Scene
# concept (one named snapshot of per-role weights active for a given bar).
# Introduced to make the engine's actual signal path introspectable (`ruby
# dilla.rb tracks`) instead of only existing as scattered ENV reads and long
# inline ffmpeg filter strings.
module DillaMixer
  # One named, self-contained ffmpeg filter-graph segment (e.g. one
  # "[in]acompressor=...[out]" stage). `filter` is the exact string used at
  # render time -- Device exists to make WHICH stage a value belongs to
  # inspectable, not to change how filters are built or joined.
  Device = Struct.new(:name, :filter) do
    def to_s = filter
  end

  # Ordered list of Devices. `to_a` returns the plain filter-string array in
  # the shape callers already expect (Array<String>, one labeled segment per
  # element) -- existing call sites that `.concat`/iterate this are
  # unaffected by the Device wrapping.
  DeviceChain = Struct.new(:devices) do
    def to_a = devices.map(&:filter)
    def names = devices.map(&:name)
  end

  # A stem in the mix. `volume`/`pan` are the resolved numeric values for the
  # current config (not ENV variable names); `sends` maps bus name => send
  # amount (0.0 if the stem doesn't reach that bus); `device_chain` is a
  # DeviceChain when the stem's processing is Device-backed, or a plain
  # Array<Symbol> of stage names when it's described statically (see
  # dilla.rb's `dilla_print_tracks`).
  Track = Struct.new(:name, :volume, :pan, :sends, :device_chain, keyword_init: true)

  # One named arrangement snapshot for a given bar -- the closest existing
  # analog to an Ableton Scene (a snapshot that changes what plays across
  # every track at once). Wraps dilla.rb's existing `dilla_section`
  # resolution; does not change which section-source wins.
  Scene = Struct.new(:name, :bar, :weights, :active_roles, keyword_init: true)
end

require "fileutils"

# An analogue synthesiser, built rather than borrowed.
#
# Every synthetic sound in this engine has until now come from FluidSynth
# playing a General MIDI soundfont: you ask for program 89 and you get whatever
# somebody sampled into that slot years ago. It is convenient and it is a hard
# ceiling. You cannot open the filter, because there is no filter. You cannot
# detune the second oscillator, because there is no second oscillator. There is
# only a recording of a sound somebody else made, and the most you can do is
# equalise it afterwards.
#
# This is the other way: oscillators, a filter, envelopes, and the arithmetic
# between them. It is the design every analogue synthesiser from the sixties
# onward shares, and it is about two hundred lines.
#
#   OSCILLATORS   make a raw, bright, harmonically rich waveform.
#   FILTER        removes the harmonics you do not want. This is where nearly
#                 all the character lives.
#   ENVELOPES     decide how loudness and brightness change over the life of a
#                 note -- the difference between a struck piano and a bowed
#                 string, played on identical oscillators.
#
# Two details separate a synthesiser that sounds analogue from one that sounds
# like a calculator, and both are imperfections:
#
#   DETUNE. Real oscillators drift. Two sawtooths a few cents apart beat against
#   each other, slowly, and the ear hears that beating as size. Perfectly tuned
#   oscillators sum to something thinner than either one alone.
#
#   DRIFT. Real circuits wander with temperature and age. A note played twice is
#   never quite the same note. A fixed random offset per voice is enough to stop
#   a chord sounding printed.
module AnalogSynth
  RATE = 44_100

  # The wave shapes, and what each is for.
  #
  # SAW has every harmonic, falling away gently. It is the brightest and the
  # most useful: strings, brass, and almost every bass ever programmed.
  # SQUARE has only the odd harmonics, which makes it hollow -- a clarinet
  # rather than a violin. Woody, and the classic reggae bass.
  # TRIANGLE has odd harmonics too, but they fall away fast, so it is nearly a
  # sine with a little edge. Flutes and soft sub-bass.
  # SINE has no harmonics at all. Only a fundamental. Sub-bass, and the bottom
  # octave of anything that needs weight without mud.
  module_function

  # ------------------------------------------------------------- oscillators

  # One sample of a waveform at a given point in its cycle.
  #
  # `phase` runs 0 to 1 across one cycle. Everything below is that cycle drawn
  # as arithmetic rather than looked up in a table, which costs a little speed
  # and buys exactness.
  #
  # PULSE, REVERSE_SAW and TRI_SAW are the Model D's other shapes: a rectangle
  # of any width (the wide and narrow pulses), OSC 3's falling ramp, and the
  # shark tooth between a triangle and a saw that OSC 1 and 2 carry.
  def wave(shape, phase, width = 0.5)
    case shape
    when :saw then (2.0 * phase) - 1.0
    when :square then phase < 0.5 ? 1.0 : -1.0
    when :triangle then phase < 0.5 ? (4.0 * phase) - 1.0 : 3.0 - (4.0 * phase)
    when :pulse then phase < width ? 1.0 : -1.0
    when :reverse_saw then 1.0 - (2.0 * phase)
    when :tri_saw then (wave(:triangle, phase) + wave(:saw, phase)) * 0.5
    else Math.sin(2.0 * Math::PI * phase)
    end
  end

  # ------------------------------------------------------------------ filter
  #
  # A four-pole resonant low-pass -- the Moog ladder, near enough.
  #
  # Four one-pole filters in series, each removing a little more of the top.
  # Four of them gives 24 dB per octave, which is the steep, definite sound of a
  # Moog; two would give 12, which is the gentler Oberheim and Roland character.
  #
  # Resonance is feedback: some of the output is subtracted from the input, and
  # because the filter has delayed it, the subtraction cancels at most
  # frequencies but REINFORCES at the cutoff. That peak is the whole reason
  # anyone cares about filters. Turn it up far enough and the filter oscillates
  # on its own with no input at all.
  #
  # State lives in the four `z` values, which is why this is a class rather than
  # a function -- a filter is a thing with a memory.
  class Ladder
    def initialize(rate: RATE)
      @rate = rate
      @z = [0.0, 0.0, 0.0, 0.0]
    end

    # `cutoff` in hertz, `resonance` from 0 to about 1.1. Above 1 it self
    # oscillates, which is a sound in itself and also a way to lose a mix.
    #
    # A straight cascade: each stage moves a little way toward the one before
    # it, and the last stage feeds back into the input. Both parts matter and
    # the first version got the second one wrong -- it averaged each stage with
    # its own previous value, which is an extra smoothing step that shifts the
    # phase of the feedback and cancels the resonance entirely. Measured across
    # resonance 0.1 to 0.9 it moved the level at cutoff by half a decibel: the
    # knob was connected to nothing.
    # The Math.exp below is computed per sample and stays that way. Caching it
    # on the last cutoff looks obviously right -- the coefficient depends only
    # on the cutoff, and a pad's filter envelope holds at sustain for most of
    # the note -- and it is measurably wrong: interleaved A/B over three
    # patches, three rounds, identical audio both ways, 10% SLOWER cached and
    # 23% slower on prophet_pad. The cutoff moves on nearly every sample, so the
    # cache almost never hits, and a method call per sample costs more than the
    # exp it was meant to save. Inline arithmetic wins here.
    def process(sample, cutoff, resonance)
      # Two corrections, both of which the first version got wrong, and together
      # they put the cutoff an octave and a half below where it was asked for --
      # a filter set to 800 Hz whose real corner was near 150.
      #
      # First, the coefficient for a one-pole lowpass is 1 - e^(-2*pi*fc/rate),
      # not 2*fc/rate. The second is the small-angle approximation of the first
      # and is 2.6 times too small at these frequencies.
      #
      # Second, where should "cutoff" point?
      #
      # Two answers, and the textbook one is wrong here. Four one-poles in
      # series reach -3 dB well below where any single stage does, by a factor
      # of about 0.435, so correcting for that puts the composite -3 dB point
      # exactly at the number asked for. That was tried. It also moves the
      # RESONANT PEAK up to the pole frequency, 2.3 times higher -- a filter set
      # to 800 Hz that whistled at 1700.
      #
      # On a real ladder the cutoff control marks the pole, which is where the
      # thing peaks and where a player hears it. With resonance down the
      # composite is already a few decibels off at that mark, and no one minds,
      # because nobody plays a resonant filter by its -3 dB point. So the stage
      # frequency IS the cutoff, and the correction stays here only as the
      # explanation for why it is not used.
      stage_hz = cutoff.clamp(20.0, @rate * 0.45)
      f = 1.0 - Math.exp(-2.0 * Math::PI * stage_hz / @rate)
      fb = resonance * 4.0

      # Feedback from the last stage. This is the entire resonance: the delayed
      # output subtracted from the input cancels at most frequencies but adds at
      # the cutoff, because that is where the four stages have turned it around.
      input = sample - (fb * @z[3])
      input = soft(input)

      @z[0] += f * (input - @z[0])
      @z[1] += f * (@z[0] - @z[1])
      @z[2] += f * (@z[1] - @z[2])
      @z[3] += f * (@z[2] - @z[3])
      @z[3]
    end

    # The transistors in a real ladder saturate, which is why a Moog gets fatter
    # rather than louder as it is driven, and why the resonance never quite
    # tears. tanh is the standard stand-in for that curve.
    def soft(x) = Math.tanh(x)
  end

  # --------------------------------------------------------------- envelopes
  #
  # Attack, decay, sustain, release -- the four numbers behind every synthesised
  # sound since 1965. Attack is how long it takes to reach full; decay how long
  # to fall from there to the sustain level; sustain the level it holds while a
  # key is down; release how long it takes to fall silent after the key is up.
  #
  # A struck sound (piano, plucked string) has no attack to speak of and no
  # sustain. A bowed or blown sound has a slow attack and a high sustain. The
  # oscillators can be identical.
  Envelope = Struct.new(:attack, :decay, :sustain, :release, keyword_init: true) do
    # Level at `t` seconds into a note that is held for `held` seconds.
    def at(t, held)
      return 0.0 if t.negative?

      if t < attack
        attack.zero? ? 1.0 : t / attack
      elsif t < attack + decay
        decay.zero? ? sustain : 1.0 - ((1.0 - sustain) * ((t - attack) / decay))
      elsif t < held
        sustain
      else
        gone = t - held
        return 0.0 if release <= 0 || gone >= release

        # Squared, so it falls quickly and then trails. A straight line sounds
        # like someone turning a knob down.
        remaining = 1.0 - (gone / release)
        sustain * remaining * remaining
      end
    end

    def total(held) = held + release
  end

  # ------------------------------------------------------------------ patches
  #
  # Each is one instrument. The comments say what the settings are FOR, because
  # a list of numbers explains nothing.
  PATCHES = {
    # Three saws, well detuned, into a filter that shuts fast. The classic
    # Minimoog bass: the envelope closes the filter within a fifth of a second,
    # so every note begins bright and immediately darkens -- which the ear reads
    # as a plucked attack even though nothing was plucked.
    moog_bass: {
      waves: %i[saw saw saw], detune: [0.0, -7.0, 5.0], octaves: [0, 0, -1],
      cutoff: 220.0, env_amount: 2400.0, resonance: 0.62, drive: 1.25,
      amp: Envelope.new(attack: 0.004, decay: 0.30, sustain: 0.55, release: 0.20),
      filter_env: Envelope.new(attack: 0.002, decay: 0.18, sustain: 0.12, release: 0.15),
    },
    # Two saws barely apart, a filter left open, a slow swell. Strings.
    poly_strings: {
      waves: %i[saw saw], detune: [-4.0, 6.0], octaves: [0, 0],
      cutoff: 1500.0, env_amount: 1800.0, resonance: 0.22, drive: 1.0,
      amp: Envelope.new(attack: 0.28, decay: 0.6, sustain: 0.78, release: 0.9),
      filter_env: Envelope.new(attack: 0.55, decay: 1.2, sustain: 0.55, release: 0.8),
    },
    # Square waves are hollow, and hollow is what a Rhodes-ish electric key
    # sounds like once the bell has faded. Fast attack, long decay, no sustain:
    # struck, not held.
    e_piano: {
      waves: %i[triangle square], detune: [0.0, 3.0], octaves: [0, 1],
      cutoff: 900.0, env_amount: 2600.0, resonance: 0.18, drive: 1.1, lpg: 0.8,
      amp: Envelope.new(attack: 0.003, decay: 1.4, sustain: 0.0, release: 0.5),
      filter_env: Envelope.new(attack: 0.001, decay: 0.5, sustain: 0.1, release: 0.4),
    },
    # One saw, one square an octave down, resonance high enough to whistle, and
    # a filter envelope that slams. This is the acid sound, and the resonance is
    # doing all of the work.
    acid: {
      waves: %i[saw square], detune: [0.0, 0.0], octaves: [0, -1],
      cutoff: 180.0, env_amount: 3200.0, resonance: 0.92, drive: 1.6,
      amp: Envelope.new(attack: 0.002, decay: 0.24, sustain: 0.25, release: 0.10),
      filter_env: Envelope.new(attack: 0.001, decay: 0.22, sustain: 0.05, release: 0.10),
    },
    # A sine and a triangle, nothing else, filter almost shut. Weight with no
    # mud -- the note is felt rather than heard, which is what a sub is for.
    sub: {
      waves: %i[sine triangle], detune: [0.0, 0.0], octaves: [-1, -1],
      cutoff: 220.0, env_amount: 200.0, resonance: 0.1, drive: 1.0,
      amp: Envelope.new(attack: 0.01, decay: 0.4, sustain: 0.7, release: 0.25),
      filter_env: Envelope.new(attack: 0.01, decay: 0.3, sustain: 0.4, release: 0.2),
    },
    # Slow, wide, and dark: the pad. Two saws and a square, all detuned, filter
    # opening over a second and a half so the chord arrives rather than starts.
    warm_pad: {
      waves: %i[saw saw square], detune: [-8.0, 9.0, 0.0], octaves: [0, 0, -1],
      cutoff: 520.0, env_amount: 900.0, resonance: 0.18, drive: 0.88,
      amp: Envelope.new(attack: 0.35, decay: 1.0, sustain: 0.8, release: 1.2),
      filter_env: Envelope.new(attack: 1.5, decay: 1.5, sustain: 0.6, release: 1.0),
    },
    # Juno-106 chorus bed: two saws a few cents apart, filter left fairly open,
    # slow swell. Röyksopp keep a Juno in the room for this exact job.
    juno_pad: {
      waves: %i[saw saw], detune: [-11.0, 13.0], octaves: [0, 0],
      cutoff: 980.0, env_amount: 700.0, resonance: 0.14, drive: 0.82,
      amp: Envelope.new(attack: 0.55, decay: 0.8, sustain: 0.82, release: 1.6),
      filter_env: Envelope.new(attack: 1.8, decay: 1.2, sustain: 0.7, release: 1.2),
    },
    # A struck tine, which is what an electric piano is: a bell partial two octaves
    # up that is gone in a sixth of a second, over a near-sine body that holds. The
    # difference between those two decays is the whole character, and one amplitude
    # envelope for the stack cannot say it — which is why osc_decay exists. The two
    # sines a cent apart are the tine and its pickup beating, slowly, on purpose.
    #
    # e_piano was standing in for this and was a triangle under a square an octave
    # up: the square's odd harmonics land between the tones of a ninth chord and
    # fight them, and its sustain of zero killed a held chord in a second and a
    # half.
    rhodes_tine: {
      waves: %i[sine sine triangle], detune: [0.0, 1.2, 0.0], octaves: [0, 0, 2],
      osc_decay: [nil, nil, 0.16], drift_cents: 0.6, lpg: 0.85,
      cutoff: 1400.0, env_amount: 1800.0, resonance: 0.10, drive: 1.06,
      amp: Envelope.new(attack: 0.004, decay: 2.6, sustain: 0.42, release: 1.4),
      filter_env: Envelope.new(attack: 0.002, decay: 0.8, sustain: 0.30, release: 0.9),
    },
    # Two saws either side of centre with a square an octave below, into a filter
    # that opens over a quarter of a second and closes again. The detune is inside
    # the voice, where a polysynth's drift belongs, so chords stay in tune with
    # each other while each chord is wide on its own.
    prophet_five: {
      waves: %i[saw saw square], detune: [-6.0, 6.0, 0.0], octaves: [0, 0, -1],
      drift_cents: 0.9, lpg: 0.35,
      cutoff: 380.0, env_amount: 2800.0, resonance: 0.28, drive: 1.0,
      amp: Envelope.new(attack: 0.05, decay: 1.4, sustain: 0.72, release: 1.0),
      filter_env: Envelope.new(attack: 0.20, decay: 1.8, sustain: 0.35, release: 1.0),
    },
    # The string machine: a divide-down stack that does not articulate at all, held
    # wide by three layers a few cents apart rather than by a filter doing
    # anything. Nearly no envelope on purpose — these machines had one speed, and
    # the ensemble was the instrument.
    vp330_ensemble: {
      waves: %i[triangle triangle saw triangle], detune: [-8.0, 8.0, 0.0, 0.0],
      octaves: [0, 0, 0, 1], drift_cents: 0.5,
      cutoff: 1600.0, env_amount: 400.0, resonance: 0.08, drive: 0.9,
      amp: Envelope.new(attack: 0.50, decay: 1.6, sustain: 0.88, release: 2.0),
      filter_env: Envelope.new(attack: 1.4, decay: 1.6, sustain: 0.75, release: 1.4),
    },
    # Leads that are not a buzzsaw.
    #
    # A saw has every harmonic in it. That is what a lead wants in a mix with a
    # band around it, and it is exactly wrong alone in a high register over a
    # pad -- there is nothing to mask the upper partials, so what should read as
    # a voice reads as a fault. A triangle has odd harmonics that fall away
    # fast, which is nearly a sine with an edge, and that is what these are
    # built on.
    #
    # Resonance stays low for the same reason. A resonant peak in the register a
    # lead sits in is a whistle.
    glass_bell: {
      waves: %i[sine triangle sine], detune: [0.0, 4.0, -3.0], octaves: [0, 1, 0],
      cutoff: 1400.0, env_amount: 2200.0, resonance: 0.12, drive: 0.85,
      amp: Envelope.new(attack: 0.004, decay: 1.1, sustain: 0.18, release: 1.4),
      filter_env: Envelope.new(attack: 0.002, decay: 0.7, sustain: 0.2, release: 0.9),
      vibrato_hz: 4.6, vibrato_cents: 7.0,
      lpg: 0.7,
    },
    soft_reed: {
      waves: %i[triangle triangle square], detune: [-5.0, 6.0, 0.0], octaves: [0, 0, -1],
      cutoff: 780.0, env_amount: 1500.0, resonance: 0.16, drive: 0.9,
      amp: Envelope.new(attack: 0.06, decay: 0.5, sustain: 0.62, release: 0.7),
      filter_env: Envelope.new(attack: 0.12, decay: 0.6, sustain: 0.4, release: 0.5),
      vibrato_hz: 5.4, vibrato_cents: 11.0,
      filter_lfo_hz: 0.31, filter_lfo_amount: 420.0,
      lpg: 0.4,
    },
    vapor_lead: {
      waves: %i[triangle sine triangle], detune: [-9.0, 0.0, 12.0], octaves: [0, -1, 1],
      cutoff: 900.0, env_amount: 1800.0, resonance: 0.2, drive: 0.8,
      amp: Envelope.new(attack: 0.02, decay: 0.8, sustain: 0.45, release: 1.8),
      filter_env: Envelope.new(attack: 0.35, decay: 1.0, sustain: 0.35, release: 1.2),
      vibrato_hz: 3.1, vibrato_cents: 16.0,
      filter_lfo_hz: 0.19, filter_lfo_amount: 700.0,
      lpg: 0.6,
    },
    # The lead that is not a machine holding a note.
    #
    # Same fast envelope as poly_lead, because a line still has to speak before
    # the next note arrives. What is added is everything a played instrument has
    # and an oscillator does not: a slow vibrato, a filter drifting underneath
    # at a different and unrelated rate so the two never line up, and a low-pass
    # gate coupling brightness to loudness so each note darkens as it dies
    # instead of holding one tone and then stopping.
    #
    # 5.2 and 0.27 Hz share no useful factor. That is deliberate -- modulations
    # at related rates lock into a pattern the ear learns in a bar, and the
    # whole reason for two of them is that it should not be able to.
    ringtone_lead: {
      waves: %i[triangle square triangle], detune: [-7.0, 0.0, 11.0], octaves: [0, 0, 1],
      cutoff: 700.0, env_amount: 3200.0, resonance: 0.2, drive: 1.1,
      amp: Envelope.new(attack: 0.008, decay: 0.3, sustain: 0.5, release: 0.6),
      filter_env: Envelope.new(attack: 0.006, decay: 0.4, sustain: 0.3, release: 0.4),
      vibrato_hz: 5.2, vibrato_cents: 14.0,
      filter_lfo_hz: 0.27, filter_lfo_amount: 900.0,
      lpg: 0.55,
    },
    # Two octaves down, almost nothing above the fundamental, and a long tail.
    #
    # A dub bass is felt before it is heard. The filter sits at 90 Hz, so what
    # reaches the ear is the fundamental and the first partial and little
    # else -- that is the difference between a bass that rumbles and one that
    # growls. Drive is above 1 because the tanh in the ladder is standing in for
    # a valve amp being pushed, which is where the warmth in those records came
    # from; and the release is nearly a second because the note is meant to
    # still be sounding when the next one lands.
    dub_bass: {
      waves: %i[sine triangle sine], detune: [0.0, 0.0, -5.0], octaves: [-1, -1, -2],
      cutoff: 90.0, env_amount: 260.0, resonance: 0.08, drive: 1.35,
      amp: Envelope.new(attack: 0.02, decay: 0.9, sustain: 0.55, release: 0.9),
      filter_env: Envelope.new(attack: 0.05, decay: 0.6, sustain: 0.35, release: 0.6),
    },
    # Five oscillators across three octaves, detuned far enough that they beat
    # against each other slowly rather than sounding merely thick.
    #
    # Two things make it feel unreal rather than only large. The filter takes
    # two and a half seconds to open, so a chord arrives from somewhere instead
    # of starting; and the release is longer than most chords are held, so each
    # one is still sounding when the next begins. At any moment you are hearing
    # two chords, which is the whole effect -- the harmony blurs into itself.
    #
    # Detune is in cents and deliberately uneven: -22 and +17 beat at a
    # different rate than +9 and -11, so there is no single wobble to latch on
    # to. Drive sits under 1.0 because five oscillators into a saturator is mud.
    surreal_wash: {
      waves: %i[saw saw triangle saw square],
      detune: [-22.0, 17.0, 0.0, 9.0, -11.0], octaves: [0, 0, 1, -1, 0],
      cutoff: 420.0, env_amount: 1900.0, resonance: 0.24, drive: 0.8,
      amp: Envelope.new(attack: 0.9, decay: 1.6, sustain: 0.85, release: 2.8),
      filter_env: Envelope.new(attack: 2.5, decay: 2.2, sustain: 0.65, release: 2.0),
    },
    # A lead, which is a different instrument from a pad and not a brighter one.
    #
    # The envelope is the whole difference. A sixteenth-note arp at 90 BPM gives
    # each note 165 ms; warm_pad takes 350 ms to reach full, so every note
    # arrives after the next one has started and the figure smears into a held
    # chord. This speaks in six milliseconds and is gone in two hundred, which is
    # what makes a line audible as a line.
    poly_lead: {
      waves: %i[saw square saw], detune: [-6.0, 0.0, 8.0], octaves: [0, 0, 0],
      cutoff: 900.0, env_amount: 3400.0, resonance: 0.34, drive: 1.15,
      amp: Envelope.new(attack: 0.006, decay: 0.22, sustain: 0.62, release: 0.18),
      filter_env: Envelope.new(attack: 0.004, decay: 0.26, sustain: 0.35, release: 0.15),
    },
    # Prophet-6 stack: saw plus a triangle an octave up, a little resonance so
    # the filter speaks. Flying Lotus names the Prophet 6 as the versatile one.
    prophet_pad: {
      waves: %i[saw triangle saw], detune: [-5.0, 0.0, 7.0], octaves: [0, 1, 0],
      cutoff: 640.0, env_amount: 1100.0, resonance: 0.28, drive: 0.9,
      amp: Envelope.new(attack: 0.22, decay: 0.9, sustain: 0.75, release: 1.1),
      filter_env: Envelope.new(attack: 0.9, decay: 1.4, sustain: 0.5, release: 0.9),
    },
  }.freeze

  # -------------------------------------------------------------- the engine

  # Renders one note into a pair of channel buffers.
  #
  # `hz` is the pitch, `at` the time it starts, `held` how long the key is down.
  # Voices are rendered one at a time and summed, which is exactly what a
  # polyphonic synthesiser does.
  def render_note!(left, right, patch:, hz:, at:, held:, gain: 1.0, seed: 0, drift_cents: nil)
    spec = PATCHES.fetch(patch) { PATCHES.fetch(:warm_pad) }
    rng = Random.new(seed)
    # Analogue drift: this voice is a few cents off, permanently, and its
    # oscillators do not start at the same point in their cycles. Both are
    # imperfections and both are why it does not sound printed.
    #
    # How far off is the caller's business, because it depends on what is being
    # played. Every note is seeded separately, so on a chord this is not one
    # instrument drifting -- it is each chord tone pulled somewhere else, and at
    # the old flat four cents two tones could sit eight cents apart. A line does
    # not care and a ninth chord does: the beating between its own partials is
    # the sound, and detuning the tones against each other destroys it. A melodic
    # caller keeps the four it always had.
    spread = (drift_cents || spec[:drift_cents] || 4.0).to_f
    voice_drift = spread.positive? ? 2.0**(rng.rand(-spread..spread) / 1200.0) : 1.0
    phases = spec[:waves].map { rng.rand }

    ladder = Ladder.new
    start = (at * RATE).to_i
    frames = (spec[:amp].total(held) * RATE).to_i
    return if frames < 2 || start >= left.length

    # Precompute the frequency of each oscillator once rather than per sample.
    freqs = spec[:waves].each_index.map do |i|
      hz * voice_drift * (2.0**spec[:octaves][i]) * (2.0**(spec[:detune][i] / 1200.0))
    end
    level = 1.0 / spec[:waves].length

    # Per-oscillator decay, as a multiplier stepped once per sample rather than an
    # exp() per oscillator per sample: at 44.1 kHz and three oscillators that is
    # 132,300 exponentials a second of audio, and this renderer is already the
    # slow part. nil is an oscillator that does not decay on its own.
    osc_gain = Array.new(spec[:waves].length, 1.0)
    osc_step = spec[:waves].each_index.map do |k|
      tau = spec[:osc_decay] && spec[:osc_decay][k]
      tau ? Math.exp(-1.0 / (RATE * tau)) : nil
    end

    # Modulation, and all of it is off unless a patch asks. Each is guarded on a
    # positive value rather than multiplied by zero, so a patch that declares
    # none takes the identical arithmetic it always did.
    #
    #   VIBRATO      a slow sine on pitch. Every played instrument has it and no
    #                oscillator does, which is most of why an unmodulated synth
    #                line sounds like a machine holding a note.
    #   FILTER LFO   a slow sine on the cutoff. The filter is where the ear
    #                looks for movement, so this is heard as the sound being
    #                alive rather than as an effect.
    #   LOW-PASS GATE  brightness follows loudness, the way a struck object gets
    #                duller as it dies. On a Buchla this is one vactrol doing
    #                both jobs; here it is the amplitude envelope steering the
    #                cutoff instead of the filter's own.
    vib_hz = spec[:vibrato_hz].to_f
    vib_cents = spec[:vibrato_cents].to_f
    flfo_hz = spec[:filter_lfo_hz].to_f
    flfo_amount = spec[:filter_lfo_amount].to_f
    lpg = spec[:lpg].to_f
    two_pi = 2.0 * Math::PI

    i = 0
    while i < frames
      dest = start + i
      break if dest >= left.length

      t = i.to_f / RATE
      bend = vib_hz.positive? ? 2.0**((vib_cents * Math.sin(two_pi * vib_hz * t)) / 1200.0) : 1.0
      # Oscillators, summed.
      raw = 0.0
      spec[:waves].each_with_index do |shape, k|
        phases[k] = (phases[k] + (freqs[k] * bend / RATE)) % 1.0
        if osc_step[k]
          raw += wave(shape, phases[k]) * level * osc_gain[k]
          osc_gain[k] *= osc_step[k]
        else
          raw += wave(shape, phases[k]) * level
        end
      end

      # The filter envelope decides the cutoff, moment by moment. This is the
      # single most important line here: a static filter is a tone control, and
      # a moving one is an instrument.
      shape_env = if lpg.positive?
                    (spec[:filter_env].at(t, held) * (1.0 - lpg)) + (spec[:amp].at(t, held) * lpg)
                  else
                    spec[:filter_env].at(t, held)
                  end
      cutoff = spec[:cutoff] + (spec[:env_amount] * shape_env)
      cutoff += flfo_amount * Math.sin(two_pi * flfo_hz * t) if flfo_hz.positive?
      filtered = ladder.process(raw * spec[:drive], cutoff.clamp(30.0, 18_000.0), spec[:resonance])

      amp = spec[:amp].at(t, held) * gain
      # A hair of stereo, from the drift rather than from a widener: the two
      # channels are the same voice at slightly different levels, which is
      # what two channels of an analogue desk actually were.
      left[dest] += filtered * amp * 0.52
      right[dest] += filtered * amp * 0.48
      i += 1
    end
  end

  # Renders a list of notes to a file.
  #
  # Each note is {hz:, at:, held:, gain:}. Returns the path, or nil if there was
  # nothing to play.
  def render!(notes, dest:, patch:, duration:, seed: 4242)
    render_groups!([{ patch:, notes: }], dest:, duration:, seed:)
  end

  # Several patches into one performance.
  #
  # A per-chord morph is one player changing sound between chords, not several
  # instruments playing at once, so the groups have to sum into the same pair of
  # channels. Mixing N finished files afterwards is a different thing and sounds
  # like it: each file is peak-normalised on its own first, which rebalances the
  # chords against each other by however loud each one happened to be.
  #
  # Each group is {patch:, notes:}. The seed advances across every note in
  # order, so a single-group call is identical to what render! did alone.
  def render_groups!(groups, dest:, duration:, seed: 4242, drift_cents: nil)
    groups = Array(groups).reject { |g| g[:notes].nil? || g[:notes].empty? }
    return nil if groups.empty?

    frames = (duration * RATE).ceil + RATE
    left = Array.new(frames, 0.0)
    right = Array.new(frames, 0.0)

    i = 0
    groups.each do |group|
      group[:notes].each do |note|
        render_note!(left, right, patch: group[:patch], hz: note[:hz], at: note[:at],
                     held: note[:held], gain: note[:gain] || 1.0, seed: seed + i, drift_cents:)
        i += 1
      end
    end

    peak = 0.0
    left.each { |v| peak = v.abs if v.abs > peak }
    right.each { |v| peak = v.abs if v.abs > peak }
    return nil if peak.zero?

    # Leave headroom. The master chain does the levelling, and arriving there
    # already at full scale gives it nothing to work with.
    scale = 0.82 / peak
    left.map! { |v| v * scale }
    right.map! { |v| v * scale }
    write!(left, right, dest)
  end

  # The same notes as render_groups!, handed back as raw interleaved PCM rather
  # than written to a file. This is what live playback needs: a pipe wants
  # samples, and going through a wav on disk to reach one adds a write, a read
  # and a container for nothing.
  # The raw channel buffers, before anything is done to them. A caller that
  # wants to put one layer through a reverb and leave another dry needs each
  # layer on its own, which neither the file writer nor the PCM packer can hand
  # back.
  def buffers!(groups, duration:, seed: 4242, drift_cents: nil)
    groups = Array(groups).reject { |g| g[:notes].nil? || g[:notes].empty? }
    return nil if groups.empty?

    frames = (duration * RATE).ceil
    left = Array.new(frames, 0.0)
    right = Array.new(frames, 0.0)
    i = 0
    groups.each do |group|
      group[:notes].each do |note|
        render_note!(left, right, patch: group[:patch], hz: note[:hz], at: note[:at],
                     held: note[:held], gain: note[:gain] || 1.0, seed: seed + i, drift_cents:)
        i += 1
      end
    end
    [left, right]
  end

  def pcm_groups!(groups, duration:, seed: 4242)
    left, right = buffers!(groups, duration:, seed:)
    return nil unless left
    # No peak normalisation here, deliberately. A live stream is rendered in
    # chunks, and scaling each chunk to its own peak makes the quiet ones louder
    # -- the level would pump with every window. The limiter below is per sample
    # and has no memory, so it cannot do that.
    interleave(left, right)
  end

  def interleave(left, right)
    inter = Array.new(left.length * 2)
    i = 0
    while i < left.length
      l = left[i]
      r = right[i]
      l = 1.0 if l > 1.0
      l = -1.0 if l < -1.0
      r = 1.0 if r > 1.0
      r = -1.0 if r < -1.0
      inter[i * 2] = (l * 32_767.0).round
      inter[(i * 2) + 1] = (r * 32_767.0).round
      i += 1
    end
    inter.pack("s<*")
  end

  # write!'s inverse: a file back into the pair of ±1.0 buffers every device in
  # this file works on. Decoded through ffmpeg rather than by parsing RIFF here,
  # so a file that arrived as mp3, or at another rate, or with its chunks in an
  # order this would not have guessed, still comes back — and it is the same
  # decoder that wrote it.
  def read!(path)
    raw, _err, _status = ToolRun.capture3(["ffmpeg", "-v", "quiet", "-i", path, "-f", "s16le",
                                           "-ar", RATE.to_s, "-ac", "2", "-"], binmode: true)
    return [[], []] if raw.nil? || raw.empty?

    samples = raw.unpack("s<*")
    left = Array.new(samples.length / 2)
    right = Array.new(samples.length / 2)
    i = 0
    while (i * 2) + 1 < samples.length
      left[i] = samples[i * 2] / 32_767.0
      right[i] = samples[(i * 2) + 1] / 32_767.0
      i += 1
    end
    [left, right]
  end

  def write!(left, right, dest)
    FileUtils.mkdir_p(File.dirname(dest))
    inter = Array.new(left.length * 2)
    i = 0
    while i < left.length
      inter[i * 2] = (left[i] * 32_767.0).round.clamp(-32_768, 32_767)
      inter[(i * 2) + 1] = (right[i] * 32_767.0).round.clamp(-32_768, 32_767)
      i += 1
    end
    ToolRun.capture3(["ffmpeg", "-y", "-v", "quiet", "-f", "s16le", "-ar", RATE.to_s,
                      "-ac", "2", "-i", "-", "-c:a", "pcm_s16le", dest], stdin_data: inter.pack("s<*"), binmode: true)
    dest
  end
end

require "yaml"

# The Minimoog Model D, and the voice that plays AnalogSynth live.
#
# render_note! renders a whole note into a buffer that is finished before
# anybody hears it, so a patch is fixed for the note's life. Playing live, the
# knobs turn while notes sound: LiveVoice renders one block at a time and takes
# its cutoff, resonance and detune fresh on every block. It plays the same
# PATCHES through the same Ladder and the same Envelope, so a patch sounds the
# same live as rendered.
module AnalogSynth
  # The Model D front panel, read into a patch this engine plays. Patches are
  # written as knob positions (data/model_d.yml) because that is how the sound
  # charts write them; every conversion from a dial to hertz, seconds, octaves
  # or gain happens in this module and nowhere else. What comes out is a
  # PATCHES-shaped hash with the Model D's extra controls beside it, and
  # LiveVoice plays those extras only when a patch carries them.
  module ModelD
    DATA_FILE = File.expand_path("../data/model_d.yml", __dir__)
    # Footage to octaves from 8'. LO is sub-audio: the oscillator becomes a
    # sweep, which is how OSC 3 serves as the Model D's only LFO.
    RANGES = { "LO" => nil, "32'" => -2, "16'" => -1, "8'" => 0, "4'" => 1, "2'" => 2 }.freeze
    OSC_WAVES = %i[triangle tri_saw saw square wide_pulse narrow_pulse].freeze
    OSC3_WAVES = %i[triangle reverse_saw saw square wide_pulse narrow_pulse].freeze
    WIDTHS = { square: 0.5, wide_pulse: 0.3, narrow_pulse: 0.15 }.freeze
    # OSC 3 in LO sits at 2 Hz with its dial centred, and in LO the dial reaches
    # three and a half octaves either way (0.18 to 22 Hz); in an audio range the
    # same dial moves seven semitones.
    LO_HZ = 2.0
    LO_OCTAVES_PER_DIAL = 3.5 / 7.0
    # A keyboard-off oscillator in an audio range holds the pitch middle C gives.
    MIDDLE_C_HZ = 261.63
    # The cutoff dial reads -5..+5, one octave a unit, with 0 at C5: its ends
    # are 16 Hz and 16.7 kHz.
    CUTOFF_CENTRE_HZ = 523.25
    # Emphasis 10 is past the ladder's self-oscillation at 1.0, as on the
    # instrument: the top of the dial sings.
    EMPHASIS_FULL = 1.08
    # Contour amount 10 opens the filter five octaves above its cutoff.
    CONTOUR_OCTAVES = 5.0
    # Contour dials are logarithmic: attack 1 ms to 10 s, decay 4 ms to 35 s.
    ATTACK_RANGE = [0.001, 10.0].freeze
    DECAY_RANGE = [0.004, 35.0].freeze
    GLIDE_RANGE = [0.002, 10.0].freeze
    # With the decay switch off, a released key stops this fast: short, and long
    # enough not to click.
    SWITCH_OFF_RELEASE = 0.008
    # Mixer dials are audio taper. At 5 a source sits inside the filter; three
    # at 10 drive its input hard, which is the fat Moog sound.
    MIXER_FULL = 1.4
    # The output patched back into the external input: past 5 it growls.
    FEEDBACK_FULL = 1.6
    KEYBOARD_CONTROL = { "keyboard_control_1" => 1.0 / 3.0, "keyboard_control_2" => 2.0 / 3.0 }.freeze
    # The mod wheel's reach at 10, squared on the way so the first half of its
    # travel is vibrato and the second half is a siren.
    WHEEL_PITCH_SEMITONES = 12.0
    WHEEL_CUTOFF_OCTAVES = 3.0
    DIAL_MAX = 10.0

    module_function

    def panels = @panels ||= YAML.load_file(DATA_FILE).fetch("patches").freeze

    def names = panels.keys

    def panel(name) = panels.fetch(name.to_s) { raise ArgumentError, "no Model D patch #{name} (#{names.join(', ')})" }

    def patch(name)
      (@patches ||= {})[name.to_s] ||= build(name.to_s, panel(name)).freeze
    end

    def build(name, panel)
      controls = panel.fetch("controllers", {})
      voices = oscillators(name, panel.fetch("oscillators"), panel.fetch("mixer"))
      {
        name:, model_d: true, legato: panel.fetch("legato", false), voices: panel.fetch("voices", 1),
        **voices, drive: 1.0, **filter(panel.fetch("filter")), **mixer(panel.fetch("mixer")),
        filter_env: contour(panel.fetch("filter"), controls), amp: contour(panel.fetch("loudness"), controls),
        glide: controls.fetch("glide", 0).to_f.positive? ? taper(controls["glide"], GLIDE_RANGE) : 0.0,
        mod: modulation(panel.fetch("oscillators").fetch("osc3"), controls),
        drift_cents: panel.dig("condition", "drift_cents"), volume: dial(panel.fetch("volume", 8)),
      }
    end

    # The audible oscillators, as PATCHES spells them. A source the mixer has
    # at zero is left out rather than computed and multiplied by nothing.
    def oscillators(name, oscs, mixer)
      audible = %w[osc1 osc2 osc3].filter_map do |key|
        level = mixer_gain(mixer.fetch(key, 0))
        [oscillator(name, key, oscs.fetch(key)), level] if level.positive?
      end
      raise ArgumentError, "Model D patch #{name}: every oscillator is off in the mixer" if audible.empty?

      shapes = audible.map(&:first)
      { waves: shapes.map { _1[:wave] }, widths: shapes.map { _1[:width] }, octaves: shapes.map { _1[:octave] },
        detune: shapes.map { _1[:cents] }, fixed_hz: shapes.map { _1[:fixed_hz] }, levels: audible.map(&:last) }
    end

    def oscillator(name, key, osc)
      shape = osc.fetch("wave").to_sym
      allowed = key == "osc3" ? OSC3_WAVES : OSC_WAVES
      raise ArgumentError, "Model D patch #{name}: #{key} has no #{shape}" unless allowed.include?(shape)

      range = RANGES.fetch(osc.fetch("range").to_s) { raise ArgumentError, "Model D patch #{name}: #{key} range #{osc['range']}" }
      frequency = osc.fetch("frequency", 0).to_f
      free = osc.fetch("keyboard_control", true) == false || range.nil?
      { wave: WIDTHS.key?(shape) ? :pulse : shape, width: WIDTHS.fetch(shape, 0.5), octave: range.to_f,
        cents: frequency * 100.0, fixed_hz: free ? fixed_hz(range, frequency) : nil, }
    end

    def fixed_hz(range, frequency)
      return LO_HZ * (2.0**(frequency * LO_OCTAVES_PER_DIAL)) if range.nil?

      MIDDLE_C_HZ * (2.0**(range + (frequency / 12.0)))
    end

    # PATCHES add their envelope to the cutoff in hertz. The Model D's contour
    # is in octaves over the cutoff, so it arrives here as the hertz that reach
    # the same peak.
    def filter(filter)
      cutoff = CUTOFF_CENTRE_HZ * (2.0**filter.fetch("cutoff", 0).to_f)
      octaves = dial(filter.fetch("contour_amount", 0)) * CONTOUR_OCTAVES
      { cutoff:, env_amount: cutoff * ((2.0**octaves) - 1.0),
        resonance: dial(filter.fetch("emphasis", 0)) * EMPHASIS_FULL,
        keytrack: KEYBOARD_CONTROL.sum { |switch, share| filter.fetch(switch, false) == true ? share : 0.0 }, }
    end

    def mixer(mixer)
      { noise: mixer_gain(mixer.fetch("noise", 0)), noise_color: mixer.fetch("noise_color", "white").to_sym,
        feedback: (dial(mixer.fetch("external", 0))**2) * FEEDBACK_FULL, }
    end

    # One decay switch serves both contours: on, a released key falls at the
    # decay rate; off, it stops.
    def contour(dials, controls)
      decay = taper(dials.fetch("decay", 0), DECAY_RANGE)
      Envelope.new(attack: taper(dials.fetch("attack", 0), ATTACK_RANGE), decay:,
                   sustain: dial(dials.fetch("sustain", 10)),
                   release: controls.fetch("decay_switch", false) == true ? decay : SWITCH_OFF_RELEASE)
    end

    # OSC 3 and noise on the mod wheel, mixed by the mod mix dial, each route
    # behind its own switch. Nil when the wheel reaches nothing.
    def modulation(osc3, controls)
      wheel = dial(controls.fetch("wheel", 0))**2
      pitch = controls.fetch("osc_mod", false) == true ? wheel * WHEEL_PITCH_SEMITONES : 0.0
      cutoff = controls.fetch("filter_mod", false) == true ? wheel * WHEEL_CUTOFF_OCTAVES : 0.0
      return nil if pitch.zero? && cutoff.zero?

      shape = osc3.fetch("wave").to_sym
      range = RANGES.fetch(osc3.fetch("range").to_s)
      { hz: fixed_hz(range, osc3.fetch("frequency", 0).to_f), wave: WIDTHS.key?(shape) ? :pulse : shape,
        width: WIDTHS.fetch(shape, 0.5), noise_mix: dial(controls.fetch("mod_mix", 0)),
        pitch_semitones: pitch, cutoff_octaves: cutoff, }
    end

    # Where Ladder starts to sing, as a multiple of resonance 1.0: it rises
    # with the cutoff, because the unit delay in the feedback adds phase the
    # higher the cutoff sits (measured at 32 and 44.1 kHz: 1.02 at 100 Hz, 1.18
    # at 800, 1.54 at 2 kHz, within 0.03 of 1 + f + 2f^2 for the stage
    # coefficient f). The Model D's threshold does not move, so its emphasis is
    # read against this: 10 sings from the bass through 2 kHz, as the
    # instrument's does. Near 5 kHz at 32 kHz nothing makes this ladder ring.
    def self_oscillation(cutoff, rate)
      f = 1.0 - Math.exp(-2.0 * Math::PI * cutoff.clamp(20.0, rate * 0.45) / rate)
      1.0 + f + (2.0 * f * f)
    end

    def mixer_gain(value) = (dial(value)**2) * MIXER_FULL

    def dial(value) = (value.to_f / DIAL_MAX).clamp(0.0, 1.0)

    # A logarithmic pot: 0 is the short end of the range, 10 the long end.
    def taper(value, range)
      low, high = range
      low * ((high / low)**dial(value))
    end
  end

  # One note, rendered a block at a time.
  #
  # The per-sample arithmetic for a PATCHES entry is render_note!'s: the same
  # oscillators summed at 1/n, the same Ladder, the same Envelope. What changes
  # per block is what the caller hands in -- cutoff, resonance, detune spread,
  # pan -- which is what lets the knobs turn under a held chord. A Model D
  # patch adds pulse widths, mixer levels, noise, feedback, keyboard tracking,
  # glide and the mod wheel, and takes the longer loop that computes them.
  class LiveVoice
    # Glide and the mod wheel move every this many frames, not every sample: at
    # 32 kHz that is 2 ms, below what the ear resolves as a step.
    SUBSTEP = 64
    # An RC glide covers 95% of the interval in three time constants.
    GLIDE_TAUS = 3.0
    REFERENCE_HZ = 261.63
    TWO_PI = 2.0 * Math::PI

    attr_reader :spec, :start, :held, :role, :hz

    def self.midi_hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

    # The draws from rng come in the order render_note! has always taken them:
    # the note's drift, then each oscillator's starting phase.
    #
    # A Model D line played legato is one voice: `path` holds the later notes
    # as [seconds into the voice, midi], and the voice glides to each without
    # retriggering its contours, which is the Minimoog's single trigger.
    # from_midi is where the first note glides in from.
    def initialize(midi:, spec:, start:, held:, gain:, role:, rng:, rate:, drift_cents: 0.7, from_midi: nil, path: [])
      # A PATCHES entry's own drift_cents belongs to render_note!'s lines; live,
      # every note takes the stream's, as the approved takes did. A Model D
      # panel's condition is its own and wins.
      spread = ((spec[:model_d] && spec[:drift_cents]) || drift_cents).to_f
      @hz = self.class.midi_hz(midi) * (2.0**(rng.rand(-spread..spread) / 1200.0))
      @spec = spec
      @start = start
      @held = held
      @gain = gain * (spec[:volume] || 1.0)
      @role = role
      @rate = rate.to_f
      @freqs = spec[:waves].each_index.map { |k| (spec[:fixed_hz]&.[](k)) || osc_hz(k) }
      @phases = spec[:waves].map { rng.rand }
      @ladder = Ladder.new(rate:)
      return unless spec[:model_d]

      @path = pitch_path(midi, from_midi, path)
      @segment = 0
      @noise_rng = Random.new(rng.rand(1 << 30))
      @pink = [0.0, 0.0, 0.0]
      @last = 0.0
    end

    def silent_at = @start + @held + @spec[:amp].release

    def done?(time) = time > silent_at

    # Adds this note's share of the block into left and right. cutoff is the
    # patch's cutoff after the knobs; spread multiplies every odd oscillator,
    # which is the detune knob; contour scales the filter envelope.
    #
    # Past its release window a note is silent by definition, even where its
    # envelope is not: a sustain of zero under a decay longer than the note
    # (e_piano) is still falling when the window closes, and the approved
    # takes cut it there.
    def render!(left, right, block_start, cutoff:, resonance:, spread:, pan:, contour: 1.0)
      return if block_start + (left.length / @rate) < @start || block_start > silent_at

      freqs = spread == 1.0 ? @freqs : @freqs.each_with_index.map { |f, k| k.odd? ? f * spread : f }
      if @spec[:model_d]
        render_model_d!(left, right, block_start, freqs, cutoff, resonance, pan, contour)
      else
        render_patch!(left, right, block_start, freqs, cutoff, resonance, pan, contour)
      end
    end

    private

    def osc_hz(k) = @hz * (2.0**@spec[:octaves][k]) * (2.0**(@spec[:detune][k] / 1200.0))

    # [seconds, pitch it glides from, pitch it glides to], each as a ratio to
    # the first note. Every glide starts where the one before it was headed.
    def pitch_path(midi, from_midi, notes)
      ratio = ->(other) { self.class.midi_hz(other) / self.class.midi_hz(midi) }
      path = [[0.0, from_midi ? ratio.call(from_midi) : 1.0, 1.0]]
      notes.each { |at, other| path << [at.to_f, path.last[2], ratio.call(other)] }
      path
    end

    def render_patch!(left, right, block_start, freqs, cutoff, resonance, pan, contour)
      spec = @spec
      waves = spec[:waves]
      level = 1.0 / waves.size
      env_amount = spec[:env_amount] * contour
      drive = spec[:drive]
      n = left.length
      j = 0
      while j < n
        t = block_start + (j.to_f / @rate) - @start
        if t >= 0
          raw = 0.0
          k = 0
          while k < freqs.size
            @phases[k] = (@phases[k] + (freqs[k] / @rate)) % 1.0
            raw += AnalogSynth.wave(waves[k], @phases[k]) * level
            k += 1
          end
          cut = cutoff + (env_amount * spec[:filter_env].at(t, @held))
          out = @ladder.process(raw * drive, cut.clamp(30.0, 12_000.0), resonance) * spec[:amp].at(t, @held) * @gain
          left[j] += out * pan
          right[j] += out * (1.0 - pan)
        end
        j += 1
      end
    end

    def render_model_d!(left, right, block_start, freqs, cutoff, resonance, pan, contour)
      spec = @spec
      env_amount = spec[:env_amount] * contour
      key = (@hz / REFERENCE_HZ)**spec[:keytrack]
      n = left.length
      bend = 1.0
      lift = 1.0
      emphasis = resonance
      j = 0
      while j < n
        t = block_start + (j.to_f / @rate) - @start
        if t >= 0
          substep = (j % SUBSTEP).zero?
          bend, lift = controls(t, block_start + (j.to_f / @rate)) if substep
          raw = oscillators(freqs, bend) + noise + (spec[:feedback] * @last)
          cut = ((cutoff + (env_amount * spec[:filter_env].at(t, @held))) * key * lift).clamp(30.0, 12_000.0)
          emphasis = resonance * ModelD.self_oscillation(cut, @rate) if substep
          @last = @ladder.process(raw, cut, emphasis) * spec[:amp].at(t, @held) * @gain
          left[j] += @last * pan
          right[j] += @last * (1.0 - pan)
        end
        j += 1
      end
    end

    def oscillators(freqs, bend)
      spec = @spec
      raw = 0.0
      k = 0
      while k < freqs.size
        step = spec[:fixed_hz][k] ? freqs[k] : freqs[k] * bend
        @phases[k] = (@phases[k] + (step / @rate)) % 1.0
        raw += AnalogSynth.wave(spec[:waves][k], @phases[k], spec[:widths][k]) * spec[:levels][k]
        k += 1
      end
      raw
    end

    # Pitch multiplier (glide, then the wheel) and cutoff multiplier (the wheel)
    # at note time t. OSC 3 runs free on the clock, not from the key, as the
    # instrument's does.
    def controls(t, clock)
      @segment += 1 while @path[@segment + 1] && @path[@segment + 1][0] <= t
      at, from, to = @path[@segment]
      glide = @spec[:glide]
      bend = glide.positive? ? to * ((from / to)**Math.exp(-(t - at) * GLIDE_TAUS / glide)) : to
      mod = @spec[:mod] or return [bend, 1.0]

      sweep = AnalogSynth.wave(mod[:wave], (mod[:hz] * clock) % 1.0, mod[:width])
      value = (sweep * (1.0 - mod[:noise_mix])) + (((@noise_rng.rand * 2.0) - 1.0) * mod[:noise_mix])
      [bend * (2.0**(value * mod[:pitch_semitones] / 12.0)), 2.0**(value * mod[:cutoff_octaves])]
    end

    # White, or pink through Paul Kellet's three-pole economy filter, which is
    # within a decibel of -3 dB per octave across the audio band.
    def noise
      level = @spec[:noise]
      return 0.0 unless level.positive?

      white = (@noise_rng.rand * 2.0) - 1.0
      return white * level unless @spec[:noise_color] == :pink

      @pink[0] = (0.99765 * @pink[0]) + (white * 0.0990460)
      @pink[1] = (0.96300 * @pink[1]) + (white * 0.2965164)
      @pink[2] = (0.57000 * @pink[2]) + (white * 1.0526913)
      (@pink[0] + @pink[1] + @pink[2] + (white * 0.1848)) * 0.25 * level
    end
  end

  # Two-operator FM, for leads that are not a filtered oscillator: a sine
  # carrier at the note, a sine modulator at an inharmonic ratio of it with
  # feedback into itself, and a modulation index that sweeps down as the note
  # speaks. Each note nudges its preset's ratio and index, so no two land on
  # the same spectrum. The cutoff knob opens the index and the resonance knob
  # feeds the modulator back harder: the same two knobs, bending FM instead.
  class FmVoice
    TWO_PI = 2.0 * Math::PI
    # A held note closes over this long once its key is up.
    RELEASE_SECONDS = 0.08
    # How long past its held time the voice stays in the stage.
    TAIL_SECONDS = 0.5

    attr_reader :start, :held, :role

    def initialize(midi:, preset:, start:, held:, gain:, rng:, rate:)
      @fm = preset.merge(ratio: preset[:ratio] * (1.0 + rng.rand(-0.03..0.03)), index: preset[:index] * rng.rand(0.6..1.4))
      @hz = LiveVoice.midi_hz(midi)
      @start = start
      @held = held + @fm[:decay]
      @gain = gain
      @phases = [rng.rand, rng.rand, 0.0]
      @pan = rng.rand(0.2..0.8)
      @rate = rate
      @role = :lead
    end

    def done?(time) = time > @start + @held + TAIL_SECONDS

    def render!(left, right, block_start, knobs:)
      return if block_start + (left.length.to_f / @rate) < @start

      fm = @fm
      open = knobs["cutoff"]
      feed = fm[:fb] * (0.5 + knobs["resonance"])
      j = 0
      while j < left.length
        t = block_start + (j.to_f / @rate) - @start
        if t >= 0
          env = (t < fm[:attack] ? t / fm[:attack] : Math.exp(-(t - fm[:attack]) / (fm[:decay] * 0.5)))
          env *= t > @held ? Math.exp(-(t - @held) / RELEASE_SECONDS) : 1.0
          index = (fm[:index] * Math.exp(-t / fm[:index_decay])) + (fm[:index] * 0.25 * open)
          @phases[1] = (@phases[1] + (@hz * fm[:ratio] / @rate)) % 1.0
          mod = Math.sin((TWO_PI * @phases[1]) + (feed * @phases[2]))
          @phases[2] = mod
          @phases[0] = (@phases[0] + (@hz / @rate)) % 1.0
          out = Math.sin((TWO_PI * @phases[0]) + (index * mod)) * env * @gain
          left[j] += out * @pan
          right[j] += out * (1.0 - @pan)
        end
        j += 1
      end
    end
  end

  # A patch change played as knobs turning: `to` with its cutoff, envelope
  # amount, resonance, drive and both envelopes part of the way back toward
  # `from`. The oscillators are `to`'s -- a new chord starts new notes, and
  # the ear hears the change there as the filter and the contours travel.
  def self.blend(from, to, weight)
    return to if weight >= 1.0 || from.equal?(to)

    mix = ->(a, b) { a + ((b - a) * weight) }
    envelope = lambda do |a, b|
      Envelope.new(attack: mix.call(a.attack, b.attack), decay: mix.call(a.decay, b.decay),
                   sustain: mix.call(a.sustain, b.sustain), release: mix.call(a.release, b.release))
    end
    to.merge(cutoff: from[:cutoff] * ((to[:cutoff] / from[:cutoff])**weight),
             env_amount: mix.call(from[:env_amount], to[:env_amount]), resonance: mix.call(from[:resonance], to[:resonance]),
             drive: mix.call(from[:drive], to[:drive]), amp: envelope.call(from[:amp], to[:amp]),
             filter_env: envelope.call(from[:filter_env], to[:filter_env]))
  end

  # A block of stereo floats to 16-bit PCM through the tanh master the live
  # sound was approved with: tanh(s * drive) scaled under full scale.
  def self.live_pcm(left, right, drive:, scale:)
    out = Array.new(left.length * 2)
    i = 0
    while i < left.length
      out[i * 2] = (Math.tanh(left[i] * drive) * scale).round
      out[(i * 2) + 1] = (Math.tanh(right[i] * drive) * scale).round
      i += 1
    end
    out.pack("s<*")
  end
end

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
# about knobs and lives with ledger.rb. Grouping by "things I added" rather than
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
  #
  #   :machine    the curve the original device picks for you: dense near unity
  #               (quarter- and half-tone neighbours first), sparse at the
  #               extremes. A few copies are a chorus; sixteen reach the octaves
  #               and fifths. Opt-in through COPY_MACHINE_FAMILY=machine.
  RATIOS = {
    harmonic: [1.0, 2.0, 0.5, 1.5, 0.6667, 3.0, 0.3333, 1.3333,
               0.75, 4.0, 0.25, 2.5, 0.4, 1.25, 0.8, 5.0].freeze,
    chromatic: (-8..7).map { |s| (2.0**(s / 12.0)).round(6) }.freeze,
    spray: [1.0, 1.4142, 0.7071, 1.7321, 0.5774, 2.2361, 0.4472, 1.2599,
            0.7937, 2.6458, 0.3780, 1.5874, 0.6300, 3.3166, 0.3015, 1.9129].freeze,
    machine: [1.0, 1.0293, 0.9715, 1.0595, 0.9439, 1.1225, 0.8909, 1.2599,
              0.7937, 1.5, 0.6667, 2.0, 0.5, 3.0, 0.3333, 4.0].freeze,
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
    #   :reverse      4, 3, 2, 1, 4, 3, 2, 1 after the first note. Round robin
    #                 walking the other way, so the line enters on voice 1 and
    #                 travels down the ensemble. Hocket II names it; cheap and
    #                 audibly different from round robin once voices are patches.
    #   :random       independent draws. Included because it is the honest
    #                 baseline the others should be compared against.
    MODES = %i[round_robin pendulum shift_register reverse random].freeze

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
        when :reverse then cursor = (cursor - 1) % n
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
  # refuses that pairing. What comes out is the melody's notes in the
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
# This is the one direction this engine could not go. listen.rb already
# renders audio TO an image -- showspectrumpic, for auditing -- and nothing goes
# the other way. MASTER/tools contains three image tools beside dilla (postpro, preprompt,
# lora). Their output has not been a live input to the audio engine, and this is
# the shortest honest bridge between them: a preprompt frame or
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
  # 2048-point cycle unless the path is long, and a 4K source would spend
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

    raw = ToolRun.capture3(["ffmpeg", "-v", "error", "-i", image_path,
                            "-vf", "scale=#{GRID}:#{GRID}:flags=area,format=gray",
                            "-frames:v", "1", "-f", "rawvideo", "-"], binmode: true).first
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
      left[i] = ((a * 0.62) + (b * 0.38)) * env * 26_000
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
# Pure Ruby on samples, for the reason sound.rb gives about its own
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

# ------------------------------------------------------------------------
# VoiceStack
# ------------------------------------------------------------------------

# One part, several voices, and one knob that makes them differ.
#
# ringtone.tools' P_4L II is seven Plaits oscillators behind a small interface,
# and its cleverest move is not the oscillator count -- it is that ONE macro
# produces a DIFFERENT value per voice. Timbre 50 with variation 20 gives 42, 61,
# 47, 56 rather than 50, 50, 50, 50. The interface stays small and the machine
# underneath does not, which is what makes it playable.
#
# dilla could already render a part several times; what it could not do was make
# the copies differ in a controlled way. Hocket splits notes BETWEEN voices --
# each voice plays some of the line. This is the other thing: every voice plays
# ALL of it, and they differ in tuning and timbre. One is an ensemble passing a
# melody around; this is an ensemble playing it together, which is a section
# rather than a hocket.
#
# DillaMacros.spread has computed exactly this arithmetic since it was written
# and nothing has ever called it. This is what it was for.
module VoiceStack
  module_function

  # How the voices relate in pitch.
  #
  #   :unison   all at the written pitch, differing only in the cents drift
  #             below. The thickest and the least harmonic decision.
  #   :octaves  spread across octaves around the written pitch. Reads as one
  #             instrument with a wide register rather than as several.
  #   :fifths   octaves and fifths, in the organ-stop tradition -- a 2 2/3 rank
  #             sitting above an 8. Historically how one keypress became a
  #             timbre, which is exactly what this module is for.
  #   :spread   voices fan outward by whole tones. Deliberately not a chord: it
  #             blurs the pitch instead of harmonising it, which is the cluster
  #             sound rather than the choir sound.
  #
  # Four more are spacing LAWS rather than intervals, after P_4L II: every voice
  # sits at the written pitch and the drift in cents follows the law, measured
  # outward from voice 0 in pairs (one sharp, one flat).
  #
  #   :equal    each pair the same step further out. The even chorus.
  #   :prog     each step wider than the last, so the outer pair is far out while
  #             the inner voices stay close. Sounds like a section.
  #   :power    square-law: tight around the centre, only the edge pair reaching
  #             full drift. Sounds like one thick instrument.
  #   :drift    a seeded random walk outward. Seven slightly different
  #             instruments, reproducible from the seed.
  SPACING_LAWS = %i[equal prog power drift].freeze
  DETUNE_MODES = (%i[unison octaves fifths spread] + SPACING_LAWS).freeze

  SEMITONE_PLAN = {
    unison: [0, 0, 0, 0, 0, 0, 0],
    octaves: [0, 12, -12, 24, -24, 12, -12],
    fifths: [0, 12, 7, 19, -12, 24, 7],
    spread: [0, 2, -2, 4, -4, 6, -6],
  }.freeze

  # A voice, as data. Everything the renderer needs and nothing it does not, so
  # a plan can be printed and pinned in a test without rendering a sample.
  Voice = Struct.new(:index, :semitones, :cents, :gain, :macro, :cutoff_scale, keyword_init: true)

  # voices:    how many. Seven is P_4L's count and the plan tables above hold it.
  # macro:     the shared position, 0..1, of whatever the caller is varying.
  # variation: how far the voices depart from it. 0 makes them identical, which
  #            is the degenerate case worth being able to ask for.
  # drift:     detune in cents, spread across the voices. Small numbers only --
  #            past about 25 cents the stack stops being one instrument and
  #            becomes several out of tune with each other.
  # key_track: how hard each voice's filter follows its own pitch, 0..1. An
  #            octave up moves the cutoff an octave up at 1.0. Without it the top
  #            of a stack goes dull, because a fixed cutoff removes a larger
  #            share of a higher note's harmonics.
  def plan(voices: 4, macro: 0.5, variation: 0.25, detune_mode: :fifths,
           drift: 9.0, key_track: 0.5, tilt: 0.4, seed: 4242)
    n = voices.to_i.clamp(1, 7)
    law = SPACING_LAWS.include?(detune_mode.to_sym) ? detune_mode.to_sym : nil
    steps = law ? SEMITONE_PLAN[:unison] : SEMITONE_PLAN.fetch(detune_mode.to_sym) { SEMITONE_PLAN[:fifths] }
    law_cents = law ? spacing_cents(law, n, drift.to_f, seed) : nil
    # The P_4L move, and the reason DillaMacros.spread exists: one position
    # becomes n positions centred on it.
    positions = DillaMacros.spread(macro, amount: variation, count: n, seed:)
    rng = Random.new(seed)
    (0...n).map do |i|
      semis = steps[i]
      # Alternating sign so the drift does not all pull one way, which would be a
      # tuning offset rather than a chorus.
      cents = if i.zero? then 0.0
              elsif law_cents then law_cents[i]
              else ((i.odd? ? 1 : -1) * drift.to_f * (0.4 + (0.6 * rng.rand))).round(2)
              end
      Voice.new(
        index: i,
        semitones: semis,
        cents:,
        # Voices far from the written pitch sit back, or the stack reads as an
        # octave doubling rather than as one instrument.
        gain: (1.0 / (1.0 + (tilt.to_f * (semis.abs / 12.0)))).round(4),
        macro: positions[i].round(4),
        # Key tracking, as a multiplier on whatever cutoff the caller uses.
        cutoff_scale: (2.0**((semis / 12.0) * key_track.to_f.clamp(0.0, 1.0))).round(4)
      )
    end
  end

  # Cents per voice under a spacing law. Voice 0 is the anchor at 0; voices
  # 1 and 2 are the first pair, 3 and 4 the second, and the outermost pair reaches
  # the full drift. Its own Random, so the interval modes keep their draw order.
  def spacing_cents(law, count, drift, seed)
    pairs = count / 2
    return Array.new(count, 0.0) if pairs.zero?

    walk = [0.0]
    walker = Random.new(seed ^ 0x5eed)
    pairs.times { walk << walk.last + 0.5 + walker.rand }
    (0...count).map do |i|
      next 0.0 if i.zero?

      k = (i + 1) / 2
      share = case law
              when :equal then k.to_f / pairs
              when :prog then (k * (k + 1)) / (pairs * (pairs + 1)).to_f
              when :power then (k.to_f / pairs)**2
              else walk[k] / walk[pairs]
              end
      ((i.odd? ? 1 : -1) * drift * share).round(2)
    end
  end

# The models: named characters, over the patches this engine already has.
#
# P_4L offers sixteen Plaits models and picking one is how a voice gets its
# character. dilla has 212 synth patches tagged by role -- 36 electric pianos,
# 50 warm pads, 85 leads -- so the useful thing here is NOT a second synthesis
# engine. It is a small vocabulary of characters that resolve to patches the
# catalogue already holds, which is the difference between naming what is here
# and building a parallel one beside it.
#
# Each model is a role plus a preference: substrings that pick a family within
# that role. A model that matches nothing falls back to its role, so adding a
# model cannot break a render -- the worst case is that it is less specific
# than intended.
MODELS = {
  tine:   { role: :ep,         prefer: %w[rhodes wurli tine] },
  glass:  { role: :ep,         prefer: %w[dx fm bell glass] },
  analog: { role: :warm,       prefer: %w[moog prophet juno voyager] },
  string: { role: :warm,       prefer: %w[string strings orchestra] },
  reed:   { role: :texture,    prefer: %w[organ flute reed] },
  choir:  { role: :texture,    prefer: %w[vox choir voice] },
  blade:  { role: :lead,       prefer: %w[lead saw acid] },
  figure: { role: :scale_lead, prefer: %w[arp] },
}.freeze

def model_names = MODELS.keys

# The model a macro position lands on. One control, several characters, which
# is the P_4L idea applied to the voices this engine actually has.
def model_for(position)
  names = MODELS.keys
  names[(position.to_f.clamp(0.0, 1.0) * (names.length - 1)).round]
end

# Resolve a model to a patch from a catalogue the CALLER supplies.
#
# Passed in rather than reached for: sound.rb loads before the engine parts,
# so referring to SYNTH_PATCH_CATALOG here would be a dependency pointing the
# wrong way -- a device reaching up into the renderer that uses it.
def patch_for(model, catalog, seed: 4242)
  spec = MODELS.fetch(model.to_sym) { MODELS[:tine] }
  in_role = catalog.select { |patch| patch[:role] == spec[:role] }
  return nil if in_role.empty?

  preferred = in_role.select do |patch|
    id = patch[:id].to_s
    spec[:prefer].any? { |word| id.include?(word) }
  end
  pool = preferred.empty? ? in_role : preferred
  pool[Random.new(seed).rand(pool.length)]
end

  # The same note events, transposed for one voice. Cents and semitones together,
  # because a stack wants both -- semitones for the register, cents for the
  # thickness.
  def transpose(events, voice)
    ratio = 2.0**((voice.semitones + (voice.cents / 100.0)) / 12.0)
    Array(events).map do |time, velocity, chord, sustain|
      next [time, velocity, chord, sustain] unless chord.is_a?(Hash) && Array(chord[:hz]).any?

      [time, velocity * voice.gain, chord.merge(hz: chord[:hz].map { |hz| hz * ratio }), sustain]
    end
  end

  # What a plan is, one line per voice.
  def describe(plan)
    plan.map do |v|
      format("voice %d  %+3d st  %+6.2f cents  gain %.3f  macro %.3f  cutoff x%.3f",
             v.index, v.semitones, v.cents, v.gain, v.macro, v.cutoff_scale)
    end
  end
end

# Room and echo, computed rather than sampled.
#
# The engine's other effects are ffmpeg filter graphs, which is right for a
# render: ffmpeg is fast, it is already a dependency, and a graph can be printed
# and argued with. It is wrong for live playback, where the audio never becomes
# a file and there is nothing to hand ffmpeg. So this is the same two ideas
# written as arithmetic over a buffer.
#
# Both are the textbook constructions and neither is novel, which is the point:
# a reverb is a solved problem and an invented one sounds like a mistake.
module SpaceFx
  RATE = 44_100

  module_function

  # A chain, drawn rather than written down.
  #
  # The order matters more than the choice. Distortion before a filter sounds
  # like an instrument and after it sounds like a broken speaker; a room goes
  # last, because everything before it is the sound and the room is where the
  # sound happens. So the palette is drawn from freely and then SORTED into
  # that order, which is the difference between a chain and a pile.
  #
  # Reverb is always present and always last. Everything else is a coin toss,
  # and the coin is seeded, so a chain you liked can be played again.
  # Ordered by what each stage costs, cheapest first, because that is the order
  # a live chain has to be trimmed in. Every one of these is a per-sample Ruby
  # loop over both channels; the reverb is six passes of one and is on its own
  # about half of any chain it appears in.
  STAGE_COST = { tremolo: 1, fold: 1, crush: 1, chorus: 2, space_echo: 3, phaser: 4, reverb: 6 }.freeze

  STAGE_ORDER = %i[fold crush phaser chorus tremolo space_echo reverb].freeze

  # max_stages trims a drawn chain to fit a budget.
  #
  # Live has a deadline that a render does not: the samples must exist before
  # the speaker wants them, and a chain that misses it produces a gap, which is
  # worse than any effect it was going to add. Cheapest stages are dropped last
  # -- they buy the most character per millisecond -- and the reverb is kept
  # whatever else goes, because a dry line over a wet pad sounds like a mistake
  # rather than like a choice.
  def random_plan(rng, wet: 1.0, max_stages: nil)
    picked = {}
    picked[:fold] = { amount: rng.rand(1.4..2.6).round(2), mix: rng.rand(0.2..0.45).round(2) } if rng.rand < 0.35
    picked[:crush] = { bits: rng.rand(7..12), hold: rng.rand(1..4), mix: rng.rand(0.2..0.5).round(2) } if rng.rand < 0.3
    if rng.rand < 0.55
      picked[:phaser] = { rate_hz: rng.rand(0.12..0.9).round(3), depth: rng.rand(0.4..0.95).round(2),
                          stages: [4, 6, 8].sample(random: rng), feedback: rng.rand(0.2..0.6).round(2),
                          mix: rng.rand(0.3..0.6).round(2) }
    end
    if rng.rand < 0.7
      picked[:chorus] = { rate_hz: rng.rand(0.2..1.1).round(3), depth_ms: rng.rand(2.0..7.0).round(2),
                          mix: rng.rand(0.2..0.45).round(2) }
    end
    if rng.rand < 0.4
      picked[:tremolo] = { rate_hz: rng.rand(2.0..7.5).round(2), depth: rng.rand(0.2..0.6).round(2),
                           shape: rng.rand < 0.25 ? :square : :sine }
    end
    if rng.rand < 0.8
      picked[:space_echo] = { time: rng.rand(0.12..0.62).round(3), feedback: rng.rand(0.25..0.62).round(2),
                              mix: (rng.rand(0.2..0.45) * wet).round(2),
                              wow_hz: rng.rand(0.3..1.4).round(2), wow_ms: rng.rand(0.6..3.0).round(2) }
    end
    picked[:reverb] = { mix: (rng.rand(0.25..0.55) * wet).round(2), decay: rng.rand(0.72..0.9).round(2),
                        damping: rng.rand(0.2..0.5).round(2) }

    if max_stages && picked.length > max_stages
      # Sorted by cost descending, reverb exempt, and dropped until it fits.
      droppable = picked.keys.reject { |s| s == :reverb }
                        .sort_by { |s| -STAGE_COST.fetch(s, 2) }
      droppable.first(picked.length - max_stages).each { |s| picked.delete(s) }
    end

    STAGE_ORDER.filter_map { |stage| [stage, picked[stage]] if picked[stage] }
  end

  # Applies a plan to one channel. `spread` offsets the reverb's comb lengths so
  # the two sides of a stereo pair are not the same room played twice.
  def apply!(samples, plan, spread: 0)
    plan.each do |stage, options|
      options = options.merge(spread:) if stage == :reverb
      send(stage, samples, **options)
    end
    samples
  end

  def describe(plan)
    plan.map { |stage, options| "#{stage}(#{options.map { |k, v| "#{k}=#{v}" }.join(' ')})" }.join(" → ")
  end

  # Schroeder's reverberator, 1962, and still the shape of nearly every digital
  # reverb since.
  #
  # PARALLEL COMBS make the density. A comb filter is a delay fed back into
  # itself: one produces a rhythmic flutter, four at lengths sharing no common
  # factor produce a wash, because their repeats never coincide. The lengths
  # below are primes for exactly that reason -- round numbers would line up and
  # the tail would ring on a pitch.
  #
  # SERIES ALLPASSES then smear it. An allpass passes every frequency at full
  # level and only disturbs their phase, so it adds echo density without adding
  # colour, which is what turns four distinct repeats into one continuous room.
  #
  # DAMPING is the part that makes it a room rather than a machine: air and soft
  # surfaces absorb treble faster than bass, so each repeat is duller than the
  # last. A one-pole lowpass inside the feedback loop is the whole model.
  COMB_LENGTHS = [1557, 1617, 1491, 1422].freeze
  ALLPASS_LENGTHS = [225, 556].freeze

  def reverb(samples, mix: 0.3, decay: 0.84, damping: 0.34, spread: 0)
    return samples if mix <= 0.0 || samples.empty?

    wet = Array.new(samples.length, 0.0)
    COMB_LENGTHS.each do |base|
      length = base + spread
      buffer = Array.new(length, 0.0)
      index = 0
      store = 0.0
      i = 0
      while i < samples.length
        out = buffer[index]
        wet[i] += out
        # The damping lowpass lives inside the loop, so it compounds: the tenth
        # repeat has been filtered ten times, which is what an actual room does.
        store = (out * (1.0 - damping)) + (store * damping)
        buffer[index] = samples[i] + (store * decay)
        index += 1
        index = 0 if index >= length
        i += 1
      end
    end

    scale = 1.0 / COMB_LENGTHS.length
    i = 0
    while i < wet.length
      wet[i] *= scale
      i += 1
    end

    ALLPASS_LENGTHS.each do |length|
      buffer = Array.new(length, 0.0)
      index = 0
      i = 0
      while i < wet.length
        buffered = buffer[index]
        out = -wet[i] + buffered
        buffer[index] = wet[i] + (buffered * 0.5)
        wet[i] = out
        index += 1
        index = 0 if index >= length
        i += 1
      end
    end

    dry = 1.0 - mix
    i = 0
    while i < samples.length
      samples[i] = (samples[i] * dry) + (wet[i] * mix)
      i += 1
    end
    samples
  end

  # The Space Echo, which is a tape loop and behaves like one.
  #
  # Three things separate it from a digital delay, and all three are the tape.
  #
  # WOW. The capstan is never perfectly steady, so the playback head reads at a
  # slightly wrong speed and every repeat is fractionally out of tune with the
  # one before. The read position here is modulated by a slow sine and the
  # sample is interpolated between neighbours, which is what produces that
  # pitch smear rather than a clean copy.
  #
  # LOSS. Tape and the record/playback heads roll off the top, and the signal
  # goes round the loop again and again, so each repeat is duller. The one-pole
  # in the feedback path is that.
  #
  # SATURATION. The tape is being driven, so loud repeats compress rather than
  # clip. tanh is the standard stand-in and is what keeps a long feedback tail
  # from turning into a scream.
  def space_echo(samples, time: 0.28, feedback: 0.42, mix: 0.32, damping: 0.28,
                 wow_hz: 0.7, wow_ms: 1.6)
    return samples if mix <= 0.0 || samples.empty?

    base = (time * RATE).to_i.clamp(64, RATE * 2)
    depth = (wow_ms / 1000.0) * RATE
    length = base + depth.ceil + 4
    buffer = Array.new(length, 0.0)
    write = 0
    store = 0.0
    two_pi = 2.0 * Math::PI

    i = 0
    while i < samples.length
      offset = base + (depth * Math.sin(two_pi * wow_hz * i / RATE))
      read = write - offset
      read += length while read.negative?
      lower = read.floor
      frac = read - lower
      a = buffer[lower % length]
      b = buffer[(lower + 1) % length]
      echo = a + ((b - a) * frac)

      store = (echo * (1.0 - damping)) + (store * damping)
      buffer[write] = Math.tanh(samples[i] + (store * feedback))
      samples[i] += echo * mix

      write += 1
      write = 0 if write >= length
      i += 1
    end
    samples
  end

  # A phaser is a stack of allpass filters whose corner frequency is moving.
  #
  # Each allpass leaves the level alone and shifts the phase, and phase shift
  # varies with frequency -- so mixing the output back with the input cancels
  # wherever the two are opposed and reinforces where they agree. Those notches
  # sweep as the LFO moves them, and the sound is the notches, not the filters.
  # An even number of stages, because each pair makes one notch.
  def phaser(samples, rate_hz: 0.35, depth: 0.7, stages: 6, feedback: 0.4, mix: 0.5)
    return samples if mix <= 0.0 || samples.empty?

    z = Array.new(stages, 0.0)
    last = 0.0
    two_pi = 2.0 * Math::PI
    i = 0
    while i < samples.length
      sweep = 0.5 + (0.5 * Math.sin(two_pi * rate_hz * i / RATE))
      # 200 Hz to about 1.6 kHz, which is where a phaser is audible as movement
      # rather than as a tone change.
      corner = 200.0 * (8.0**(sweep * depth))
      coefficient = (1.0 - (corner / (RATE / 2.0))) / (1.0 + (corner / (RATE / 2.0)))

      value = samples[i] + (last * feedback)
      s = 0
      while s < stages
        out = (coefficient * value) + z[s]
        z[s] = value - (coefficient * out)
        value = out
        s += 1
      end
      last = value
      samples[i] += value * mix
      i += 1
    end
    samples
  end

  # Amplitude moving under a slow LFO. The oldest effect there is -- it is what
  # a Rhodes' tremolo does and what a rotating speaker does to level -- and the
  # one that most reliably stops a held note sounding dead.
  def tremolo(samples, rate_hz: 4.2, depth: 0.4, shape: :sine)
    return samples if depth <= 0.0 || samples.empty?

    two_pi = 2.0 * Math::PI
    i = 0
    while i < samples.length
      phase = (rate_hz * i / RATE) % 1.0
      lfo = shape == :square ? (phase < 0.5 ? 1.0 : -1.0) : Math.sin(two_pi * phase)
      samples[i] *= 1.0 - (depth * 0.5 * (1.0 - lfo))
      i += 1
    end
    samples
  end

  # Bit depth and sample rate thrown away on purpose.
  #
  # Quantising to fewer bits adds distortion that tracks the signal, and holding
  # each sample for several periods folds everything above the new Nyquist back
  # down as inharmonic aliasing. Both are faults, and both are the sound of
  # every sampler made before about 1990.
  def crush(samples, bits: 10, hold: 3, mix: 0.6)
    return samples if mix <= 0.0 || samples.empty?

    levels = (2**bits.clamp(2, 16)).to_f
    held = 0.0
    i = 0
    while i < samples.length
      held = samples[i] if (i % hold).zero?
      crushed = ((held * levels).round / levels)
      samples[i] = (samples[i] * (1.0 - mix)) + (crushed * mix)
      i += 1
    end
    samples
  end

  # A wave folder, which is not a clipper: where a clipper flattens a peak, this
  # turns it back on itself, so the harmonics it adds keep growing with the
  # input instead of settling. West-coast synthesis used this instead of a
  # filter and it is why a Buchla sounds nothing like a Moog.
  def fold(samples, amount: 1.8, mix: 0.5)
    return samples if mix <= 0.0 || samples.empty?

    i = 0
    while i < samples.length
      x = samples[i] * amount
      x = (x - 4.0 * ((x / 4.0 + 0.5).floor)).abs * 2.0 - 1.0 if x.abs > 1.0
      samples[i] = (samples[i] * (1.0 - mix)) + (x * mix)
      i += 1
    end
    samples
  end

  # A chorus is a delay short enough that the ear hears it as one voice rather
  # than two, with its delay time moving. What arrives is the sound plus a copy
  # of itself a few milliseconds and a few cents away, which is the whole of
  # what makes one oscillator sound like several players.
  def chorus(samples, rate_hz: 0.6, depth_ms: 4.5, mix: 0.35, centre_ms: 12.0)
    return samples if mix <= 0.0 || samples.empty?

    centre = (centre_ms / 1000.0) * RATE
    depth = (depth_ms / 1000.0) * RATE
    length = (centre + depth).ceil + 4
    buffer = Array.new(length, 0.0)
    write = 0
    two_pi = 2.0 * Math::PI

    i = 0
    while i < samples.length
      buffer[write] = samples[i]
      offset = centre + (depth * Math.sin(two_pi * rate_hz * i / RATE))
      read = write - offset
      read += length while read.negative?
      lower = read.floor
      frac = read - lower
      a = buffer[lower % length]
      b = buffer[(lower + 1) % length]
      samples[i] += (a + ((b - a) * frac)) * mix

      write += 1
      write = 0 if write >= length
      i += 1
    end
    samples
  end
end

# The rack: named emulations of specific studio hardware.
#
# Each entry below is one real machine, and each is described by what it
# measurably does rather than by how it is supposed to feel. That distinction
# matters. "Warmth" is not a specification; second-harmonic distortion at a
# stated level is. Where a manufacturer or an engineer has said in print what
# a box does, the comment says so and the settings follow it.
#
# The units compose. A signal path of neve_80 into stc8 into gml_matte is three
# entries joined with commas, which is also how the equipment would have been
# patched together.
#
# What is honest about this and what is not: these reproduce the documented
# BEHAVIOUR of each machine -- its harmonic bias, its frequency response, its
# time constants. They do not reproduce its circuit. An emulation built this way
# gets you most of the way to the character and none of the way to the myth,
# which is the correct trade for a pure-Ruby engine with no plugin host.
module Outboard
  module_function

  # --------------------------------------------------------- Crane Song HEDD
  #
  # The Harmonically Enhanced Digital Device, designed by Dave Hill. Its whole
  # premise is that you choose your distortion rather than avoid it, and it
  # offers three kinds by name.
  #
  # Dave Cooley mastered Donuts, and Crane Song boxes are what he reached for.

  # A note on how these were built, because it decides whether they are worth
  # anything.
  #
  # Each was measured, not guessed. A one-kilohertz tone goes in, and the energy
  # at two and three kilohertz comes out -- the second and third harmonic -- as a
  # level below the tone itself. The figures quoted per unit are those readings.
  # The first attempt at these used aexciter, which produced nothing at all: its
  # `freq` is a SCOPE, so it ignores everything below five kilohertz, and a one
  # kilohertz tone passed through untouched. It measured -93 dB, the noise floor.
  # Had nobody measured, four units would have shipped doing nothing.
  #
  # Note also that asoftclip's `param` runs the opposite way to the intuition:
  # higher is more distortion, not less.

  # TRIODE. Per Crane Song: the even-order harmonics of a single-ended valve
  # stage. Even harmonics are octaves of the note being played, so the ear files
  # them as tone rather than as distortion -- this is what "warm" means when the
  # word is used carefully.
  #
  # Even harmonics require an ASYMMETRIC transfer curve: a shape that treats the
  # top half of the waveform differently from the bottom. A symmetric one, no
  # matter how hard it is driven, produces only odd harmonics. So the signal is
  # pushed off centre, clipped, and pulled back -- which is, near enough, what a
  # valve stage biased to one side does.
  #
  # Measured: 2nd harmonic -37.5 dB, 3rd -60.7 dB. Twenty-three decibels of
  # even-order bias, which is the triode signature.
  def hedd_triode(drive: 12, offset: 0.35, param: 2.4)
    "volume=#{drive}dB,dcshift=shift=#{offset}," \
      "asoftclip=type=tanh:param=#{param}:oversample=4," \
      "dcshift=shift=-#{offset},highpass=f=20,volume=-#{drive}dB"
  end

  # PENTODE. Per Crane Song: mostly third harmonic, and brighter -- they note it
  # sounds like a high-end boost without the drawbacks of one, because it works
  # across the spectrum rather than lifting a band.
  #
  # Odd harmonics are not octaves. The third above a note is a twelfth -- a fifth
  # in the next octave up -- which is why pentode reads as edge and presence
  # where triode reads as body. A symmetric clipper gives odd harmonics and
  # nothing else, so this is the simpler of the two.
  #
  # Measured: 3rd harmonic -35.3 dB, 2nd -91.8 dB. The bias is total.
  def hedd_pentode(drive: 24, param: 2.4)
    "volume=#{drive}dB,asoftclip=type=tanh:param=#{param}:oversample=4,volume=-#{drive}dB"
  end

  # TAPE. Per Crane Song: the compressed sound of driving an analogue recorder
  # into overload. Two things at once, and both are needed -- the soft clipping
  # of the tape itself, and the gentle levelling that comes with it.
  #
  # An arctangent curve rather than a hyperbolic tangent: it leaves the knee
  # earlier and rounds more gradually, which is closer to how tape approaches
  # saturation than to how a transistor does.
  #
  # Measured: 3rd harmonic -56.2 dB. Gentler than the pentode by design; the
  # compressor after it carries as much of the character as the clipping does.
  def hedd_tape(drive: 14, param: 2.2)
    "volume=#{drive}dB,asoftclip=type=atan:param=#{param}:oversample=4,volume=-#{drive}dB," \
      "acompressor=threshold=-16dB:ratio=2.5:attack=8:release=180:makeup=1.1"
  end

  # ------------------------------------------------------- Crane Song STC-8
  #
  # The compressor Cooley put Donuts through, and the specific thing he did with
  # it: he timed the release to each track's tempo. His words were that he did it
  # to preserve the disorienting compression pump -- to take the intensity
  # further rather than smooth it away.
  #
  # That is the opposite of the usual advice, which is to set a release that
  # makes compression inaudible. Here the compression is meant to be heard, and
  # tying it to the tempo makes it part of the rhythm instead of a fault in it.
  #
  # Release is one eighth note, so the bus has recovered exactly as the next
  # offbeat lands.
  def stc8(bpm:, threshold: -14, ratio: 2.0)
    release = bpm.to_f.positive? ? (60_000.0 / bpm / 2.0).round : 300
    "acompressor=threshold=#{threshold}dB:ratio=#{ratio}:attack=15:" \
      "release=#{release.clamp(50, 1000)}:makeup=1.08:detection=rms"
  end

  # ------------------------------------------------------------- GML 8200
  #
  # George Massenburg's parametric, and the other half of what Cooley described:
  # he used it for top end, and said he was not after a slick top at the time --
  # he called the result matte.
  #
  # A matte top is a WIDE, shallow shelf placed high. It lifts air across the
  # whole top octave without putting an edge on any one frequency. A narrow
  # boost is the slick sound he was avoiding, and the difference between the two
  # is entirely the width.
  def gml_matte(gain: 2.0, hz: 11_000)
    "equalizer=f=#{hz}:t=h:w=0.5:g=#{gain}"
  end

  # ------------------------------------------------- Neve 80-series console
  #
  # The 8028 and 8078, the desks the seventies are recorded on.
  #
  # Two documented properties. First, transformers: the signal leaves at close
  # to microphone level and is brought back up through output transformers,
  # which are not flat -- the core lifts the low bass slightly and the top rolls
  # away early. Second, the discrete class-A stages depart from linear as they
  # are pushed, and the sum of many small departures across a mix is what people
  # mean by the sound of the desk.
  #
  # Both are small. The temptation to make them large is what makes an emulation
  # sound like an emulation.
  #
  # The nonlinearity is asymmetric, like the triode and for the same reason:
  # transformer cores saturate asymmetrically, and a desk full of them reads as
  # warm rather than as harsh. Measured: 2nd harmonic -54.1 dB, 3rd -75.4 dB.
  # A sixth of the triode's distortion -- audible across a whole mix, inaudible
  # on any one sound, which is what a console does. 3.2 dB of pre-clip gain is
  # the transformer still speaking: silk, not grit.
  def neve_80(drive: 3.2, offset: 0.12, param: 1.4, lf_db: 0.8)
    "equalizer=f=55:t=q:w=0.8:g=#{lf_db}," \
      "volume=#{drive}dB,dcshift=shift=#{offset}," \
      "asoftclip=type=tanh:param=#{param}:oversample=4," \
      "dcshift=shift=-#{offset},highpass=f=20,volume=-#{drive}dB," \
      "lowpass=f=18500"
  end

  # ------------------------------------------------------------- API console
  #
  # The other transformer desk, and the counterweight to the Neve: where the
  # Neve is round, the API is forward. Its reputation rests on speed -- fast
  # amplifiers, a lift through the presence region where a snare's crack lives.
  #
  # Faster and brighter than neve_80, deliberately. Reach for this one on a
  # drum-led track and the Neve on a sample-led one.
  #
  # Symmetric where the Neve is asymmetric: more third harmonic, less second,
  # which is the edge people describe when they call an API aggressive and a
  # Neve round. Comparable amount of distortion, different flavour of it.
  #
  # Measured: 3rd harmonic -58.8 dB, 2nd below the floor. Set against the Neve's
  # -54 dB of SECOND, the two desks distort about equally and sound nothing
  # alike, which is the whole point of having both.
  #
  # The cubic curve was tried first, as the more obviously "different" shape,
  # and abandoned: it barely saturates at any setting this side of unusable.
  # It reached only -61 dB at twenty-two decibels of drive.
  def api_console(drive: 12, param: 2.4)
    "equalizer=f=75:t=q:w=1.0:g=1.0," \
      "equalizer=f=3200:t=q:w=1.4:g=1.4," \
      "volume=#{drive}dB,asoftclip=type=tanh:param=#{param}:oversample=4,volume=-#{drive}dB," \
      "lowpass=f=19500"
  end

  # ------------------------------------------------------- Tape machine
  #
  # A reel-to-reel, modelled the way CHOW Tape models one: as a machine with
  # parts, not as an effect. Four things happen to audio on tape and all four
  # are here.
  #
  #   HEAD BUMP.  A low resonance around fifty hertz, from the geometry of the
  #               playback head. It is why tape sounds big at the bottom.
  #   HF LOSS.    The top falls away, earlier at slower tape speeds.
  #   WOW.        Slow pitch drift, under a hertz, from an eccentric reel.
  #   FLUTTER.    Fast pitch drift, a few hertz, from the capstan.
  #
  # Wow and flutter are pitch modulation, which is what the vibrato filter does.
  #
  # Its depth turns out to map one-to-one onto percent of pitch deviation --
  # measured by tracking a five-kilohertz tone, where a depth of 0.08 gave
  # exactly plus or minus 0.08 percent. The first version of this unit asked for
  # 0.0022, which is twenty-eight times below what a machine actually does and
  # measured as a dead flat line: no wow at all. A published specification for a
  # studio deck is under 0.05 percent combined; a tired one, or a turntable,
  # reaches 0.1 to 0.3. These sit just above the good machine, which is where a
  # record that has been played a few hundred times sits.
  def tape_machine(speed: :ips15, wow: 0.08, flutter: 0.03)
    hf = speed == :ips7 ? 12_500 : 16_500
    bump = speed == :ips7 ? 2.2 : 1.5
    "equalizer=f=50:t=q:w=1.2:g=#{bump}," \
      "vibrato=f=0.7:d=#{wow}," \
      "vibrato=f=6.3:d=#{flutter}," \
      "lowpass=f=#{hf}"
  end

  # ---------------------------------------------------------- Pultec EQP-1A
  #
  # A passive tube equaliser from the 1950s, and the one piece of outboard whose
  # most famous use is a thing its own manual warns against.
  #
  # Its low band has separate boost and attenuate knobs at the same selected
  # frequency, and turning up both should cancel. It does not, because the two
  # circuits are not mirror images: the BOOST is a broad, gentle shelf that
  # starts below the frequency, while the CUT is narrower and starts slightly
  # above it. Use both at 100 Hz and what you get is a lift underneath and a dip
  # at 200 to 400 -- weight added exactly where a kick lives, and mud removed
  # exactly where mud lives.
  #
  # No single control does this, which is why engineers still reach for it
  # seventy years on. It is also precisely the shape a hip-hop low end wants.
  # Dub weight: lower centre, nearly twice the boost, adjacent cut pulled back.
  #
  # The standard setting is a mastering move -- weight without mud, the boost
  # and cut overlapping so the gap between them does the work. Dub wants some
  # of the mud, because the bass is the lead instrument and 80 Hz is where it
  # lives. Measured before adding this: the dub rack with the standard unit came
  # out 6.2 dB DOWN in the low band against its own source, which is the exact
  # opposite of the style.
  def pultec_low_dub
    pultec_low(hz: 80, boost: 7.5, cut: 1.5)
  end

  # A top shelf for the dub rack. It does NOT make the rack net-darker, and the
  # measurements are here so the next person does not repeat the attempt.
  #
  # Gain-matched at -18 LUFS against the dry source, the dub rack measures:
  #
  #   no shelf         low -0.4  mid -0.8  8-13k +1.0
  #   -4 dB @ 7k       low -0.4  mid -0.7  8-13k +1.0
  #   -9 dB @ 6k, LP11 low -0.3  mid -0.7  8-13k +0.6
  #
  # Nine decibels of shelf and an 11 kHz lowpass move the top by four tenths of
  # a decibel. The rack generates top faster than a filter after it can remove
  # it: neve_80 and console_sum are both asymmetric clippers, and the harmonics
  # they add land above the shelf and are regenerated by every stage downstream
  # of wherever the shelf sits.
  #
  # So dub darkness is not a mastering-chain problem. It comes from the source --
  # a rhythm track cut dark, or a lowpass early in the signal path before the
  # saturation rather than after it. Left in at a mild setting because the shelf
  # is still doing something audible on the echo tails, but the comment that
  # claimed this rack was dark was wrong and is now this note instead.
  def dub_darken(hz: 6_000, cut: 9.0)
    "equalizer=f=#{hz}:t=h:w=0.7:g=-#{cut},lowpass=f=11000"
  end

  def pultec_low(hz: 100, boost: 4.0, cut: 3.0)
    "equalizer=f=#{hz}:t=q:w=0.7:g=#{boost}," \
      "equalizer=f=#{(hz * 2.8).round}:t=q:w=1.1:g=-#{cut}"
  end

  # The matching high band: a broad lift with a small dip below it, which is how
  # the Pultec adds air without the boost sounding like a boost.
  def pultec_air(hz: 12_000, boost: 2.5)
    "equalizer=f=#{hz}:t=h:w=0.6:g=#{boost}," \
      "equalizer=f=#{(hz * 0.35).round}:t=q:w=1.4:g=-1.0"
  end

  # ------------------------------------------------------------- compressors
  #
  # Three ways of turning a signal down, which sound nothing alike because of
  # what does the turning.

  # TELETRONIX LA-2A. An optical compressor: the signal drives a small lamp, and
  # a light-sensitive resistor beside it does the gain reduction. The lamp and
  # the cell both take time to respond and neither is linear, so the release is
  # in two stages -- a fast part and a long slow tail -- and it depends on how
  # hard and how long the unit has been working.
  #
  # This is why an LA-2A is described as transparent while compressing heavily:
  # it never grabs, and it lets go slowly enough that you hear the level change
  # as an arrangement decision rather than as an effect. No attack control,
  # because the lamp decides.
  def la2a(threshold: -18, ratio: 3.0)
    "acompressor=threshold=#{threshold}dB:ratio=#{ratio}:attack=10:release=600:" \
      "knee=8:detection=rms:makeup=1.15"
  end

  # UREI 1176. A field-effect transistor does the gain reduction, and it does it
  # in microseconds -- the fastest attack here by two orders of magnitude. Fast
  # enough to catch the very front of a snare, which is why it grabs a drum bus
  # and makes it sound like a record.
  #
  # The famous setting is all four ratio buttons pushed in at once, which the
  # unit was never designed to allow: it produces a high ratio with a
  # distorted, lagging knee. That is what the aggressive figures below are.
  def fet1176(threshold: -16, ratio: 12.0)
    "acompressor=threshold=#{threshold}dB:ratio=#{ratio}:attack=0.4:release=90:" \
      "knee=2:detection=peak:makeup=1.25"
  end

  # FAIRCHILD 670. A variable-mu limiter -- the gain reduction happens inside
  # the valves themselves, whose amplification falls as the signal drives them.
  # Twenty valves, a hundred and fifty pounds, and on most of the Beatles
  # catalogue.
  #
  # Variable-mu units are slow and gentle and the ratio rises with how hard they
  # are hit, so they flatter a mix rather than control it. Used here as glue,
  # never as a limiter.
  # knee maxes at 8 in this build, not 12. A rejected value fails the WHOLE
  # chain, so the glue rack rendered nothing at all until this was clamped.
  def fairchild670(threshold: -20, ratio: 1.8)
    "acompressor=threshold=#{threshold}dB:ratio=#{ratio}:attack=25:release=400:" \
      "knee=8:detection=rms:makeup=1.1"
  end

  # ------------------------------------------------- Roland RE-201 Space Echo
  #
  # A tape loop running past three playback heads, with a spring reverb bolted
  # on. Two photographs of one sit in Flying Lotus's studio, and it is on a great
  # deal of what he has made.
  #
  # What makes it sound like itself is not the delay times -- any box can do
  # taps. It is that the tape is a physical loop being re-recorded on every pass,
  # so each repeat is a generation further from the original:
  #
  #   DARKER. The tape loses top end every time round. By the fourth repeat
  #   there is little above a few kilohertz, which is why a Space Echo tail
  #   fades into the track instead of cluttering it. A digital delay repeating a
  #   bright sound stays bright and quickly becomes a mess.
  #
  #   UNSTEADY. The transport wows, and the wow accumulates -- the fifth repeat
  #   has been through it five times. The tail drifts in pitch, which is the
  #   sound people mean by "tape delay" and the reason a clean one sounds wrong.
  #
  #   THREE HEADS. Fixed positions on the loop, not free times, so the taps are
  #   in a fixed ratio to each other. Modelled here at roughly 1 : 1.9 : 2.8,
  #   which is where the real heads sit.
  #
  # The darkening is done by putting the lowpass BETWEEN two echo stages rather
  # than after them, so the second stage's repeats are filtered copies of the
  # first stage's -- which is what a feedback loop through tape actually does,
  # and what a single filtered send does not.
  def space_echo(time_ms: 240, feedback: 0.55, mix: 0.4, wow: 0.12)
    short = time_ms.round
    medium = (time_ms * 1.9).round
    long = (time_ms * 2.8).round
    "asplit=2[se_dry][se_wet];" \
      "[se_wet]aecho=0.9:#{feedback}:#{short}|#{medium}|#{long}:0.6|0.45|0.3," \
      "lowpass=f=3200,vibrato=f=0.9:d=#{wow}," \
      "aecho=0.85:#{(feedback * 0.8).round(2)}:#{(time_ms * 3.6).round}|#{(time_ms * 5.1).round}:0.4|0.25," \
      "lowpass=f=2200,highpass=f=180,volume=#{mix}[se_verb];" \
      "[se_dry][se_verb]amix=inputs=2:weights=1 1:normalize=0"
  end

  # ------------------------------------------------------- the dub effects
  #
  # Dub is not a genre applied to a mix, it is a performance played on the desk.
  # King Tubby and Scientist were engineers reworking rhythm tracks other people
  # had recorded, and the record is what the room's outboard did to them. So
  # these are the boxes that were physically in those rooms, not a mood.

  # SPRING REVERB. The Fisher/Accutronics tank in every console and guitar amp,
  # and nothing like a plate or a hall.
  #
  # Three properties, all of which are usually treated as faults:
  #
  # DISPERSION. A spring is not a delay line -- high frequencies travel through
  # it faster than low ones, so a single hit arrives smeared into a descending
  # chirp. That is the "boing", and cascaded allpass filters are exactly the
  # tool: they delay by frequency without changing amplitude.
  #
  # RESONANCE. A physical spring has strong modes at particular frequencies. A
  # flat decay is a plate; the peaks are what makes a spring identifiable.
  #
  # BANDWIDTH. A tank passes roughly 150 Hz to 4 kHz and nothing outside it,
  # which is why spring reverb sits in a mix without needing to be carved out.
  def spring_reverb(mix: 0.42, decay: 0.55)
    "asplit=2[sp_dry][sp_wet];" \
      "[sp_wet]highpass=f=150,lowpass=f=4000," \
      "allpass=f=380:width_type=q:w=0.6,allpass=f=1250:width_type=q:w=0.5," \
      "allpass=f=2600:width_type=q:w=0.4," \
      "aecho=0.9:#{decay}:29|37|53|71:0.7|0.55|0.4|0.3," \
      "equalizer=f=1800:t=q:w=2.2:g=4,equalizer=f=3400:t=q:w=3.0:g=2.5," \
      "lowpass=f=3600,volume=#{mix}[sp_verb];" \
      "[sp_dry][sp_verb]amix=inputs=2:weights=1 1:normalize=0"
  end

  # PHASER. The Mutron Bi-Phase, and after it the Small Stone -- the sweep under
  # half of Lee Perry's Black Ark output.
  #
  # Slow and deep. A fast phaser is a seventies funk guitar; a dub phaser takes
  # ten or fifteen seconds to cross, so it reads as the whole track breathing
  # rather than as an effect on one part.
  #
  # 0.1 Hz is aphaser's floor -- it silently refuses anything slower, and a
  # refused filter kills the entire graph rather than degrading, so this clamps
  # rather than trusting the argument.
  def dub_phaser(speed: 0.12, decay: 0.55, delay: 3.4)
    "aphaser=in_gain=0.6:out_gain=0.9:delay=#{delay}:decay=#{decay}:" \
      "speed=#{[speed, 0.1].max}:type=t"
  end

  # DELAY THROW. The engineer's hand on the send: one phrase pushed into the
  # echo while everything else stays dry.
  #
  # A constant delay is a texture; a throw is an event, and the difference is
  # the whole style. `enable` gates the wet path so the echo opens for a two
  # second window every eight bars and is closed the rest of the time.
  #
  # Period comes from the tempo rather than a fixed number of seconds, so the
  # throws land on bar lines instead of drifting across them.
  def delay_throw(bpm: 76, bars: 8, window: 2.0, time_ms: 320, feedback: 0.62)
    bar = 4.0 * 60.0 / bpm.to_f
    period = (bar * bars).round(3)
    # The volume gate mutes OUTSIDE the window, not inside it. enable makes a
    # filter active while its expression is true, so gating on lt() would have
    # silenced the throw and passed echo the rest of the time -- the inverse.
    #
    # This note lives above the literal rather than inside it. A comment between
    # two backslash-continued fragments ends the literal, so the method used to
    # return only its last two lines: [dt_dry] was never defined and every
    # RACK=dub render died on an undefined filter label.
    "asplit=2[dt_dry][dt_wet];" \
      "[dt_wet]aecho=0.9:#{feedback}:#{time_ms.round}|#{(time_ms * 2).round}|#{(time_ms * 3).round}:" \
      "0.7|0.5|0.35,lowpass=f=2600,highpass=f=200," \
      "volume=0:enable='gte(mod(t\\,#{period})\\,#{window})'[dt_throw];" \
      "[dt_dry][dt_throw]amix=inputs=2:weights=1 1:normalize=0"
  end

  # ------------------------------------------------------------ liquid
  #
  # Water, not the genre label. "Liquid" in liquid drum and bass names the
  # harmony, but the word also describes a set of real, nameable effects, and
  # this is those: what a sound does when it is under, on, or moving through
  # water.
  #
  # Four mechanisms, because each one is a different physical thing:
  #
  # SUBMERSION is a lowpass. Water absorbs high frequencies far faster than air,
  # which is why everything underwater is muffled -- and the cutoff MOVES,
  # because your depth does.
  #
  # SURFACE is chorus. A rippling surface is many slightly different path
  # lengths at once, which is exactly a set of short modulated delays.
  #
  # FLOW is a phaser. Notches sweeping through the spectrum are what a moving
  # boundary between two media sounds like.
  #
  # WOBBLE is vibrato. Sound travels faster in water than air, so a moving
  # medium bends pitch -- small amounts read as wet, large amounts as seasick.
  #
  # Kept subtle by default. Every one of these is an effect people reach for and
  # overuse, and the difference between "underwater" and "broken tape" is
  # entirely the depth setting.
  def liquid_submerge(hz: 2_600, depth: 0.55, rate: 0.07)
    # A moving cutoff, approximated with two fixed bands crossfaded by an LFO --
    # ffmpeg has no LFO-driven lowpass, and apulsator on a filtered split is the
    # cheapest honest way to get one.
    "asplit=2[lq_open][lq_deep];" \
      "[lq_deep]lowpass=f=#{hz}:width_type=q:width=0.7,volume=#{depth.round(2)}[lq_d];" \
      "[lq_open]apulsator=hz=#{rate}:amount=#{(depth * 0.5).round(2)}:mode=sine[lq_o];" \
      "[lq_o][lq_d]amix=inputs=2:weights=1 1:duration=first:normalize=0"
  end

  def liquid_surface(depth_ms: 3.2, rate: 0.35)
    "chorus=0.85:0.9:22|34|48:0.4|0.34|0.28:" \
      "#{depth_ms}|#{(depth_ms * 0.7).round(2)}|#{(depth_ms * 1.3).round(2)}:" \
      "#{rate}|#{(rate * 1.7).round(2)}|#{(rate * 0.6).round(2)}"
  end

  def liquid_flow(speed: 0.18, decay: 0.6)
    "aphaser=in_gain=0.55:out_gain=0.95:delay=4.2:decay=#{decay}:" \
      "speed=#{[speed, 0.1].max}:type=t"
  end

  # vibrato's depth is a fraction, not a percentage, and 0.08 is already
  # noticeable. Above about 0.2 it stops sounding like water and starts sounding
  # like a tape machine with a failing capstan.
  def liquid_wobble(rate: 0.6, depth: 0.06)
    "vibrato=f=#{rate}:d=#{depth.clamp(0.0, 0.2)}"
  end

  # ------------------------------------------------------------- mono bass
  #
  # Everything below the crossover collapsed to the centre.
  #
  # This is a cutting-lathe rule that outlived the lathe. Bass energy that
  # differs between the two channels moves the cutting stylus vertically, and
  # enough of it lifts the needle out of the groove -- so records were always cut
  # with a mono bottom. It survives because it turns out to be right for other
  # reasons: a club system's subwoofer is one speaker fed from both channels, so
  # stereo bass partly cancels before anyone hears it, and low frequencies carry
  # no directional information to a listener anyway. The ear locates sound below
  # about 150 Hz by which side is louder, not by anything in the waveform.
  #
  # What it buys is loudness. Two channels of bass in phase are 6 dB louder than
  # two fighting, so the limiter downstream has less to do and the track hits
  # harder at the same measured level.
  def mono_bass(hz: 120)
    "asplit=2[mb_lo][mb_hi];" \
      "[mb_lo]lowpass=f=#{hz},pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1[mb_mono];" \
      "[mb_hi]highpass=f=#{hz}[mb_wide];" \
      "[mb_mono][mb_wide]amix=inputs=2:weights=1 1:normalize=0"
  end

  # ------------------------------------------------- Console summing bus
  #
  # The stage every other unit here skips. A desk does not only colour each
  # channel on the way in -- the channels then MEET, on a summing bus with its
  # own transformer, its own coupling capacitors, and its own phase behaviour.
  # That bus is why a mix printed through a console does not sound like the same
  # mix summed in software, and it is the last analog thing to touch the audio.
  #
  # Three parts, and only one of them is distortion.
  #
  #   PHASE ROTATION. Two allpass sections, at 90 Hz and 1.8 kHz. An allpass
  #                   changes phase and NOTHING else, which is exactly what a
  #                   chain of transformers and coupling caps does to a signal.
  #                   Measured: 0.00 dB change at 60, 200, 1k, 4k and 12k Hz,
  #                   while phase moves 226, 61, 261, 100 and 28 degrees at those
  #                   same frequencies. That is the "phasy" character, and it is
  #                   real phase rather than an effect pretending to be one.
  #
  #   MOVEMENT.       A slow phaser, 0.1 Hz -- one sweep every ten seconds.
  #                   Not an audible whoosh; a bus that will not sit perfectly
  #                   still, which is the difference between analog and a plugin
  #                   bypassed.
  #
  #   TRANSFORMER.    Gentle asymmetric saturation. Measured 2nd -61.3 dB, 3rd
  #                   -73.8 dB on the same rig that reads neve_80 at 2nd -48.1
  #                   and api_console at 3rd -46.6 -- so roughly 13 dB gentler
  #                   than a channel strip, which is right. A summing bus is not
  #                   a drive stage; if you can hear it working it is wrong.
  #
  # Note the rig: those three figures are comparable to each other because they
  # were taken together. They read 6-12 dB hotter than the older per-unit figures
  # quoted above, which were measured with a different setup -- compare within a
  # set, not across them.
  #
  # TWO NUMBERS ARE NOT FREE CHOICES, and both were found by measurement:
  #
  #   aphaser speed has a hard floor of 0.1 in ffmpeg. Below it the filter is
  #   REFUSED, and a refused filter does not degrade -- it takes the entire chain
  #   with it and the render dies. 0.1 is the slowest legal sweep, which is also
  #   the one wanted here.
  #
  #   aphaser attenuates hard and silently: in_gain 0.5 with the default out_gain
  #   0.72 measured -8.56 dB mean across the band. out_gain 1.9 brings it to
  #   -0.13 dB. With the saturator's own loss on top, the closing makeup is -1.0
  #   dB rather than the -5.0 dB that symmetry with the drive would suggest;
  #   measured net for the whole unit is -0.08 dB. An uncompensated version of
  #   this cost 4 dB and would have read as "the phasy racks are quieter".
  def console_sum(drive: 5, offset: 0.10, param: 1.2, makeup: -1.0, speed: 0.1)
    "allpass=f=90:width_type=q:w=0.6:order=2," \
      "allpass=f=1800:width_type=q:w=0.5:order=2," \
      "aphaser=in_gain=0.5:out_gain=1.9:delay=3.2:decay=0.15:speed=#{speed}:type=t," \
      "volume=#{drive}dB,dcshift=shift=#{offset}," \
      "asoftclip=type=tanh:param=#{param}:oversample=4," \
      "dcshift=shift=-#{offset},highpass=f=18,volume=#{makeup}dB"
  end

  # The same bus, several times over.
  #
  # Engineers stack three or four instances of a virtual console strip at the end
  # of the mix bus rather than running one hard, and report it does something a
  # single instance does not. That is a claim about harmonics, so it was measured
  # rather than believed -- on the rig this file uses everywhere: a 1 kHz tone in,
  # Goertzel out, every row matched to the SAME total distortion so the question
  # is which harmonics carry it rather than how much there is.
  #
  #   matched to 1.5% THD      drive      2nd       3rd     even over odd
  #   1 stage                  14.4 dB    -36.6    -51.9        15.3 dB
  #   2 stages                  9.4 dB    -36.5    -60.8        24.3 dB
  #   3 stages                  7.7 dB    -36.5    -74.7        38.2 dB
  #
  # The second harmonic does not move -- the THD match holds it there, since it
  # is most of the THD. What changes is the THIRD, which falls 23 dB across the
  # three rows. Same amount of distortion, progressively less of it odd.
  #
  # That is the whole effect, and it is worth stating in musical terms because
  # the numbers are otherwise numbers: the second harmonic is an octave, so
  # the ear files it as tone. The third is a twelfth -- a fifth, in the next
  # octave up -- and it is what "harsh" means on a mix bus. Driving one stage
  # hard buys both. Driving three gently buys the octave and leaves the fifth
  # behind. Nobody stacking these is imagining it.
  #
  # Why it happens: each stage's asymmetric curve is nearly linear at low drive,
  # where a tanh's expansion is dominated by its quadratic term -- the even one.
  # The cubic term, which makes the third harmonic, grows far faster with drive
  # than the quadratic does, so splitting the same total distortion across more
  # stages at lower drive each keeps the quadratic and starves the cubic.
  #
  # The drives below come from that measurement: they are what put each stack at
  # roughly the distortion one console_sum produces alone, so raising the count
  # changes the CHARACTER without changing the amount. Stacking without dropping
  # the per-stage drive is a different and much louder decision, and it is not
  # this one.
  STACK_DRIVE = { 1 => 5.0, 2 => 3.2, 3 => 2.5, 4 => 2.1 }.freeze

  # And the makeup each depth needs to come out where it went in.
  #
  # This is not arithmetic and it could not be guessed. asoftclip's oversample=4
  # is NOT gain-compensated in ffmpeg 8.1.1: measured against the identical
  # clipper without it, the oversampled one reads -4.2 dB where the plain one
  # reads +1.5 dB. Nearly six decibels, per stage, invisible in the parameters.
  #
  # A first attempt at this stack carried console_sum's own -1.0 dB makeup and
  # measured -0.2, -3.0, -6.6 and -10.3 dB at one through four instances. That is
  # the failure console_sum's header already warns about, in the same file, one
  # method up: "an uncompensated version of this cost 4 dB and would have read as
  # 'the phasy racks are quieter'". A stack that gets quieter as you add
  # instances would be compared against a bypass and lose every time -- and the
  # comparison would be measuring the makeup, not the stacking.
  #
  # So each depth was measured against the same 87-second render and the loss
  # written down. Net after compensation is 0.0 dB at every depth, which is what
  # makes A/B-ing the count a test of the sound rather than of the level.
  STACK_MAKEUP = { 1 => -0.6, 2 => 2.2, 3 => 5.4, 4 => 8.7 }.freeze

  def console_stack(instances: 3, offset: 0.10, param: 1.2, speed: 0.1)
    n = instances.to_i.clamp(1, 4)
    drive = STACK_DRIVE.fetch(n)
    # Only the first stage sweeps. Four phasers at one speed either beat against
    # each other or, when they do not, multiply one 0.1 Hz sweep into a
    # four-times-deeper one -- and the whole point of the movement is that it
    # stays below notice. The rest are phase rotation and transformer alone.
    #
    # The makeup rides on the LAST stage rather than being spread across them.
    # Spread, each stage would be driven by its own share of it and the drive is
    # what the THD match above fixes; the compensation has to happen after all
    # the saturation, not between it.
    stages = Array.new(n) do |i|
      if i.zero?
        console_sum(drive:, offset:, param:, speed:, makeup: 0.0)
      else
        "allpass=f=90:width_type=q:w=0.6:order=2," \
          "allpass=f=1800:width_type=q:w=0.5:order=2," \
          "volume=#{drive}dB,dcshift=shift=#{offset}," \
          "asoftclip=type=tanh:param=#{param}:oversample=4," \
          "dcshift=shift=-#{offset},highpass=f=18"
      end
    end
    "#{stages.join(',')},volume=#{STACK_MAKEUP.fetch(n)}dB"
  end

  # ------------------------------------------- Bode frequency shifter
  #
  # Not a pitch shifter, and the difference is the whole unit.
  #
  # A pitch shift multiplies every partial by the same ratio, so a harmonic
  # series stays a harmonic series and the sound keeps its identity an octave up.
  # A FREQUENCY shift adds the same number of hertz to every partial, so 100,
  # 200, 300 becomes 200, 300, 400 -- ratios of 1:1.5:2 instead of 1:2:3. The
  # result is inharmonic by construction, which is why the Bode shifter is a
  # klangumwandler and not a transposer, and why small shifts read as metallic
  # rather than as a wrong note.
  #
  # Measured: a 1 kHz tone shifted +100 arrives at 1100 Hz, -100 at 900, +300 at
  # 1300. Exactly the stated hertz, which is the one thing worth checking about a
  # filter nothing in this engine had ever called.
  #
  # Small values are the musical ones. Past about 50 Hz the source stops being
  # recognisable, which is the same boundary sample_morph draws for FM depth and
  # for the same reason: the ear tracks a pitch until the partials stop agreeing
  # about what it is.
  def freq_shift(hz: 12, level: 1.0)
    "afreqshift=shift=#{hz}:level=#{level}"
  end

  # ------------------------------------------------- broadband phase rotation
  #
  # Phase, and nothing else. Measured against a 1 kHz tone the spectrum is
  # unchanged to the noise floor -- identical to bypass at every bin.
  #
  # So on its own it is inaudible, and that is not a fault: it is the same
  # property that makes console_sum's allpass stages worth having. It becomes
  # audible the moment it meets a copy of itself, which is how it is used. Summed
  # against the dry signal at 1 kHz:
  #
  #   shift 0.1   -6.5 dB    near cancellation
  #   shift 0.25  -0.8 dB
  #   shift 0.5   +3.7 dB
  #   shift 1.0   +6.0 dB    fully in phase, so the sum doubles
  #
  # Which makes it a comb filter whose notches do not move with frequency the way
  # a delay's do -- a delay's comb is periodic in hertz, this one is flat across
  # the spectrum. That is the difference between a flanger and a phase rotator,
  # and it is why this one thickens without the sweep being obvious.
  def phase_rotate(shift: 0.35, mix: 0.5)
    "asplit=2[prdry][prwet];[prwet]aphaseshift=shift=#{shift}[prsh];" \
      "[prdry][prsh]amix=inputs=2:weights=#{(1.0 - mix).round(3)} #{mix}:normalize=0"
  end

  # ------------------------------------------------------------------ racks
  #
  # Signal paths, in patch order. A rack is a list of unit names; `chain` turns
  # one into the filter string.
  RACKS = {
    # What Donuts went through, as closely as this can be said: a console, then
    # the Crane Song compressor timed to the track, then the GML for the top.
    #
    # The triode is NOT in this rack, and the reason is worth keeping.
    #
    # On one instrument, second-harmonic distortion at -37 dB is warmth -- the
    # octave above every note, which the ear files as tone. On a finished mix it
    # is overdrive, because a mix is not one note: every pair of frequencies in
    # it intermodulates through the same nonlinearity and produces sums and
    # differences that belong to no note at all. Measured, this rack with the
    # triode in it put 1.3 percent distortion on the master, on top of the
    # SP-1200 and vinyl emulation already in the path, and the samples came back
    # sounding like guitars through an overdriven amp. Without it: 0.2 percent,
    # which is where a mastering chain belongs.
    #
    # The unit is still here and still measured. It belongs on a single voice.
    donuts: %i[neve_80 stc8 gml_matte mono_bass],
    # Warmer and slower. The tape machine ahead of everything, so the console
    # colours what the tape already did.
    # Same reasoning: hedd_tape is a saturator too, and two on a master is one
    # too many. The tape machine ahead of the console carries the character.
    tape_first: %i[tape_machine neve_80 stc8 console_sum gml_matte mono_bass],
    # Forward and bright, for tracks the drums lead.
    forward: %i[api_console stc8 gml_matte mono_bass],
    # The console alone, for when the material arrives already finished.
    light: %i[neve_80 stc8],

    # SUMMED. The stack at the end rather than a channel strip at the front.
    #
    # The order is the argument. Every other rack here colours on the way IN and
    # then compresses -- which is what a channel strip does, and it means the
    # last thing to touch the mix is a compressor. This one puts the summing
    # stack last, because on a desk the bus IS last: the channels are already
    # coloured and compressed when they meet, and the transformer they meet on is
    # the final analog stage before the recorder.
    #
    # CONSOLE_STACK sets how many instances (1-4, default 3). Per the measurement
    # on console_stack, raising it holds the distortion where it is and takes the
    # third harmonic out of it, so this is a warmth control rather than a drive
    # control -- which is the opposite of what a number that high usually means.
    summed: %i[neve_80 stc8 gml_matte mono_bass console_stack],

    # Three racks that exist so the compressors are reachable. They were built
    # and measured and then put in no rack and given no other caller, which is
    # this codebase's most repeated defect and was worth fixing on its own terms.
    #
    # GLUE. A variable-mu limiter flatters a mix rather than controlling it --
    # slow, gentle, and its ratio rises with how hard it is hit. The Fairchild
    # before the console rather than after, so the desk colours something already
    # sitting together.
    glue: %i[fairchild670 neve_80 console_sum gml_matte mono_bass],

    # SMOOTH. The LA-2A has no attack control because a light bulb decides its
    # timing, and the result is heavy compression you do not hear working. For
    # material with a wide dynamic range, where the STC-8's tempo pump would be
    # the wrong kind of audible.
    smooth: %i[neve_80 la2a pultec_air console_sum gml_matte mono_bass],

    # SNAP. The 1176 catches the front of a transient in microseconds, which is
    # what makes a drum bus sound like a record. Paired with the API, since both
    # are the fast, forward end of the collection.
    snap: %i[api_console fet1176 hedd_pentode gml_matte mono_bass],

    # BEAUTY. The chain you would reach for if the brief were "make it lovely"
    # rather than "make it loud", and the only rack that reaches pultec_low --
    # which was built, measured, and then put in no rack and given no caller.
    # That is the same unreferenced-unit defect the note above this block
    # describes, still true one unit later.
    #
    # Order is the reason it works. Tape first, so everything after colours
    # something that already has the medium on it. Then the Pultec low, whose
    # boost and cut overlap on purpose -- the shelf lifts 60 Hz while the
    # adjacent cut pulls 168 Hz down, and the gap between them is the trick:
    # weight without the mud that a plain low boost adds. Then the console for
    # harmonics, the Fairchild to glue, the LA-2A to level what the Fairchild
    # left, and the Pultec air last so the top opens after the compressors have
    # stopped moving rather than being squashed by them.
    #
    # Two compressors is deliberate and is not two saturators: the Fairchild is
    # variable-mu glue and the LA-2A is optical levelling, and they hear
    # different things. Two saturators on a master is the mistake the donuts
    # comment documents, and this rack has one -- the tape.
    beauty: %i[tape_machine pultec_low neve_80 fairchild670 la2a pultec_air console_sum gml_matte mono_bass],

    # DUB. The mix as the instrument, which is the whole idea of the style --
    # King Tubby and Scientist were engineers, and the record is what the desk
    # did to a rhythm track somebody else had already played.
    #
    # space_echo first, not last. Everything downstream then compresses and
    # colours the repeats along with the source, which is what a tape delay
    # patched into a channel actually does. Put it at the end and the echoes
    # arrive clean and sit outside the track instead of inside it.
    #
    # pultec_low after the delay, so the weight lands on the summed thing. The
    # LA-2A after that, because an optical compressor riding echo tails is the
    # sound -- repeats breathe up as they decay rather than fading evenly.
    #
    # dub_darken last, and it is a subtraction rather than an omission. Leaving
    # pultec_air out was the first attempt and measured +1.0 dB at the top --
    # the neve drive and console sum both add harmonics up there, so declining
    # to add an air shelf does not make anything darker.
    # LIQUID. The water chain ahead of a clean console, so the console glues
    # something already moving rather than colouring it into stillness.
    liquid: %i[liquid_surface liquid_submerge liquid_flow liquid_wobble neve_80 la2a pultec_air console_sum gml_matte mono_bass],

    dub: %i[delay_throw spring_reverb space_echo pultec_low_dub dub_phaser neve_80 la2a console_sum dub_darken mono_bass],

    # FOUNDRY. The three units nothing named: hedd_triode, freq_shift and
    # phase_rotate were built, given live `when` arms in chain, and left in no
    # rack -- so the arms were dead and the most unusual processing in this file
    # was unreachable. A new rack rather than an edit to an existing one,
    # because naming them inside donuts or dub would change a sound someone
    # already chose.
    #
    # Order is the argument. hedd_triode first: tube drive belongs on the source,
    # before anything smears it. freq_shift second and small -- afreqshift moves
    # every partial by the same NUMBER of Hz rather than the same ratio, so it
    # breaks the harmonic series instead of transposing it, and at 12 Hz that
    # reads as metal rather than as a wrong note. phase_rotate after, because
    # rotating phase on an already-inharmonic signal is what widens it without
    # a chorus. Then the ordinary console: neve, optical compression, sum. And
    # mono_bass last and non-negotiable, since everything above it moves phase
    # and a club system folds the bottom to mono anyway.
    foundry: %i[hedd_triode freq_shift phase_rotate neve_80 la2a console_sum mono_bass],

    # The joined catalogue only. Tape and a mild triode on a finished mix is
    # the dirt the demo is supposed to carry; putting either in donuts would
    # change the bed under MASTER's speech.
    catalogue_grit: %i[tape_machine hedd_tape hedd_triode_mix],
  }.freeze

  DEFAULT_RACK = :donuts

  # Builds one rack into a filter chain.
  #
  # Unknown names are dropped rather than raised on, and the drop is reported by
  # the caller: a misspelt unit that silently disappears is exactly the kind of
  # dead configuration this codebase keeps finding.
  def chain(rack = DEFAULT_RACK, bpm:, missing: nil)
    units = RACKS.fetch(rack.to_sym) { RACKS.fetch(DEFAULT_RACK) }
    units.filter_map do |unit|
      case unit
      when :hedd_triode then hedd_triode
      when :hedd_triode_mix then hedd_triode(drive: 6, offset: 0.22, param: 2.0)
      when :hedd_pentode then hedd_pentode
      when :hedd_tape then hedd_tape
      when :stc8 then stc8(bpm:)
      when :gml_matte then gml_matte
      when :neve_80 then neve_80
      when :api_console then api_console
      when :tape_machine then tape_machine
      when :mono_bass then mono_bass
      when :la2a then la2a
      when :fet1176 then fet1176
      when :fairchild670 then fairchild670
      when :pultec_air then pultec_air
      when :pultec_low then pultec_low
      when :pultec_low_dub then pultec_low_dub
      when :liquid_wobble then liquid_wobble
      when :liquid_flow then liquid_flow
      when :liquid_surface then liquid_surface
      when :liquid_submerge then liquid_submerge
      when :delay_throw then delay_throw(bpm: bpm)
      when :dub_phaser then dub_phaser
      when :spring_reverb then spring_reverb
      when :dub_darken then dub_darken
      when :freq_shift then freq_shift(hz: ENV.fetch("FREQ_SHIFT_HZ", "12").to_f)
      when :phase_rotate then phase_rotate(shift: ENV.fetch("PHASE_ROTATE", "0.35").to_f)
      when :console_sum then console_sum
      # How many instances, as an operator knob, because the whole point of the
      # measurement above is that the count is the character control. Clamped in
      # console_stack; the drives past four were never measured and inventing
      # them here would be exactly the kind of unmeasured number this file
      # refuses to carry.
      when :console_stack then console_stack(instances: ENV.fetch("CONSOLE_STACK", "3").to_i)
      when :space_echo then space_echo
      else
        missing&.call(unit)
        nil
      end
    end.join(",")
  end

end

# Spectral chop, arpeggiator, octave/partial stacks.
#
# Removed here: darkness_filter_chain, darkness_iterations, ir_transient_boost,
# phase_stretch_filter and spectral_reorder_paths, none of which had a caller
# anywhere in the engine. INDUSTRIAL_DARK, DARKNESS_ITERS, IR_TRANSIENT,
# PHASE_STRETCH and SPECTRAL_CHOP were read only by those five, so the
# --industrial-dark flag set an environment variable that nothing downstream
# ever looked at. The acrusher/afftfilt chain it described is in git history if
# it should be wired into render_industrial rather than dropped.
module DillaSpectral
  module_function

  def enabled?
    ENV["SPECTRAL_ENGINE"] != "0"
  end

  def chop_hz(chord, t = 0.0)
    hz = DillaHarmony.chop_tones(chord)[:hz]
    return hz if hz.empty?
    return spectral_arpeggiate(hz, t) if ENV["SPECTRAL_ARP"] == "1"
    return stack_hz(hz.min, t) if ENV["HARMONIC_STACK"] == "1"
    hz
  end

  def spectral_arpeggiate(hz, t)
    sorted = hz.sort
    band = ((t * 8).to_i) % sorted.length
    [sorted[band]]
  end

  # What HARMONIC_STACK has always produced, and NOT a harmonic series despite
  # the flag's name: successive OCTAVES of the fundamental. At 130.81 Hz that
  # is 130.8 / 261.6 / 523.2 / 1046.5 / 2093.0 / 4185.9 Hz -- five octaves of
  # reach, which is where the stack gets its top end. Keeping the name it has
  # been called by, with the behaviour stated.
  def octave_stack_hz(fundamental, _t = 0.0, count: 6)
    base_midi = DillaHarmony.hz_to_midi(fundamental)
    (1..count).map { |h| DillaHarmony.midi_to_hz(base_midi + (h - 1) * 12) }
  end

  # Fletcher stiff-string partials: f_n = n * f0 * sqrt(1 + B*n^2), from the
  # wave equation for a string with bending stiffness (Fletcher, Blackham &
  # Stratton 1962). Higher partials are progressively sharp, which is the
  # physical origin of the Railsback stretch in piano tuning. Measured B runs
  # ~1e-5..5e-5 on piano treble, ~1e-4..1e-3 on wound bass strings; 2.5e-4 puts
  # the sixth partial 7.8 cents sharp -- present, not a detune effect.
  #
  # This is a different series from octave_stack_hz, not a coloured version of
  # it: six partials of 130.81 Hz top out at 788 Hz where six octaves reach
  # 4186 Hz. Swapping it in as the default would take 2.4 octaves off the top
  # of every HARMONIC_STACK render, and RENDER_MODE=warp sets that flag, so it
  # is opt-in under INHARMONIC=1 like every other flag here.
  #
  # No drift term on B. A slow +-0.15% wobble on B moves the sixth partial by
  # 0.023 cents against a discrimination limit around 5 cents, so it would be
  # arithmetic nobody can hear; the f0 drift is what carries the movement, and
  # at +-0.08% it is worth 2.8 cents peak to peak.
  INHARMONIC_B = 0.00025
  INHARMONIC_DRIFT = 0.0008

  def inharmonic_stack_hz(fundamental, t = 0.0, count: 6, b: nil)
    f0 = fundamental.to_f
    return [] unless f0.positive?

    b = (b || ENV.fetch("INHARMONIC_B", INHARMONIC_B)).to_f.clamp(0.0, 0.01)
    f0 *= 1.0 + (INHARMONIC_DRIFT * Math.sin((t * 0.37) + (f0 * 0.0011))) if ENV["INHARMONIC_DRIFT"] != "0"
    (1..count).map { |n| (n * f0 * Math.sqrt(1.0 + (b * n * n))).round(4) }
  end

  def stack_hz(fundamental, t = 0.0, count: 6)
    return inharmonic_stack_hz(fundamental, t, count:) if ENV["INHARMONIC"] == "1"

    octave_stack_hz(fundamental, t, count:)
  end

  def breath_perc_hz
    [180.0, 220.0, 280.0, 340.0]
  end

  def breath_mode?
    ENV["BREATH_PERC"] == "1"
  end
end

# Moog DFAM semantics from the RG-69 lo-fi drum machine reference:
# dual-osc FM percussion, 8-step pitch/velocity sequencer, resonant LP decay.
module DfamEngine
  DEFAULT_PATCH = {
    osc1_hz: 80, osc2_hz: 120, fm_pct: 30, noise_pct: 20,
    filter_hz: 2000, res_pct: 40, decay_ms: 200,
  }.freeze

  DEFAULT_PATTERN = {
    pitch: [50, 30, 60, 20, 55, 35, 65, 25],
    velocity: [80, 60, 90, 50, 85, 65, 95, 55],
  }.freeze

  STEPS = 8
  STEPS_PER_BAR = 16

  module_function

  def enabled?
    ENV["DFAM"] != "0"
  end

  def resolve_patch
    patch = DEFAULT_PATCH.dup
    patch[:osc1_hz] = env_i("DFAM_OSC1", patch[:osc1_hz])
    patch[:osc2_hz] = env_i("DFAM_OSC2", patch[:osc2_hz])
    patch[:fm_pct] = env_i("DFAM_FM", patch[:fm_pct])
    patch[:noise_pct] = env_i("DFAM_NOISE", patch[:noise_pct])
    patch[:filter_hz] = env_i("DFAM_FILTER", patch[:filter_hz])
    patch[:res_pct] = env_i("DFAM_RES", patch[:res_pct])
    patch[:decay_ms] = env_i("DFAM_DECAY", patch[:decay_ms])
    patch
  end

  def resolve_pattern(seed: nil)
    base = DEFAULT_PATTERN.transform_values(&:dup)
    rng = Random.new(seed || pattern_seed)
    base[:pitch] = base[:pitch].map { |p| (p + rng.rand(-8..8)).clamp(10, 95) }
    base[:velocity] = base[:velocity].map { |v| (v + rng.rand(-10..10)).clamp(35, 100) }
    if (raw = ENV["DFAM_PATTERN"])
      parts = raw.split(",").map(&:strip)
      if parts.length == STEPS * 2
        base[:pitch] = parts.first(STEPS).map { |x| x.to_i.clamp(0, 100) }
        base[:velocity] = parts.drop(STEPS).map { |x| x.to_i.clamp(0, 100) }
      end
    end
    base
  end

  # djb2, not String#hash.
  #
  # Ruby randomises String#hash per process -- SipHash with a key drawn at
  # startup -- so this seeded the pattern from a different number on every run
  # and the eight-step sequence was never the same twice. It reads as
  # deterministic, keyed on the track name, and is not. Twenty-six sites in
  # dilla.rb had the same fault and were corrected; this one is in a lib file
  # and was missed.
  def stable_hash(text)
    text.to_s.each_byte.reduce(5381) { |a, b| ((a * 33) + b) % 4_294_967_296 }
  end

  def pattern_seed
    track = (ENV["TRACK"] || "minor_iv_loop").to_s.downcase.tr("-", "_")
    stable_hash(track) + (@render_seed || 0)
  end

  def mix_events!(left, right, events, chunk_start, chunk_frames, sample_rate: 44_100)
    events.each do |hit|
      t, vel, pitch, _idx, patch = hit.length == 5 ? hit : (hit + [resolve_patch])
      event_frame = (t * sample_rate).round
      dur_frames = [(patch[:decay_ms] / 1000.0 * sample_rate).round, 1].max
      window = overlap_window(event_frame, dur_frames, chunk_start, chunk_frames)
      next unless window
      local_start, source_offset, count = window
      f1 = patch[:osc1_hz] + pitch * 1000.0
      f2 = patch[:osc2_hz] + pitch * 1000.0
      fm_depth = patch[:fm_pct] / 100.0
      noise_amt = (patch[:noise_pct] / 100.0) * vel
      amp = vel * 0.20
      decay = patch[:decay_ms] / 1000.0
      decay_rate = 4.5 / [decay, 0.05].max
      filter_progress = 200.0 / [patch[:filter_hz], 200.0].max
      count.times do |i|
        tt = (source_offset + i).to_f / sample_rate
        env = amp * Math.exp(-tt * decay_rate)
        filter_env = Math.exp(-tt * decay_rate * (1.0 + filter_progress))
        fm = fm_depth * f2 * 0.012 * Math.sin(2 * Math::PI * f1 * tt)
        tri = (2.0 / Math::PI) * Math.asin([[-1.0, Math.sin(2 * Math::PI * f1 * tt)].max, 1.0].min)
        sq = Math.sin(2 * Math::PI * (f2 + fm) * tt).positive? ? 1.0 : -1.0
        noise = deterministic_noise(tt, t, pitch) * noise_amt
        sample = env * filter_env * (0.42 * tri + 0.38 * sq * 0.55 + 0.20 * noise)
        left[local_start + i] += sample * 0.52
        right[local_start + i] += sample * 0.48
      end
    end
  end

  def deterministic_noise(tt, t0, pitch)
    Math.sin(tt * 9_973.7 + t0 * 131.0) * Math.sin(tt * 5_731.2 + pitch * 97.0)
  end

  def overlap_window(event_frame, total_frames, chunk_start, chunk_frames)
    return if total_frames <= 0
    chunk_end = chunk_start + chunk_frames
    event_end = event_frame + total_frames
    return if event_end <= chunk_start || event_frame >= chunk_end
    local_start = [event_frame - chunk_start, 0].max
    source_offset = [chunk_start - event_frame, 0].max
    count = [total_frames - source_offset, chunk_end - (event_frame + source_offset)].min
    count = [count, chunk_frames - local_start].min
    return if count <= 0
    [local_start, source_offset, count]
  end

  def env_i(key, default)
    v = ENV[key]
    return default if v.nil? || v.empty?
    v.to_i
  end
end

# Jiles-Atherton tape hysteresis, plus Ornstein-Uhlenbeck wow and flutter.
#
# Why this exists when the engine already has saturation. Everything else here
# is memoryless: asoftclip, alimiter, a waveshaper -- output is a function of
# the current sample alone, so the same input value always gives the same output
# value and the transfer curve is a single line. Real tape is not like that. The
# magnetisation of the medium depends on its history, so the curve is a LOOP:
# the output at a given input differs depending on whether the signal is rising
# or falling into it. That path-dependence is why tape compresses a transient
# differently from a sustained tone, and it is the part a waveshaper cannot
# reach however carefully its curve is drawn.
#
# The model is Jiles-Atherton, solved with RK4, which is the standard treatment
# for ferromagnetic hysteresis and what open tape emulations use.
#
# Wow and flutter use an Ornstein-Uhlenbeck process rather than summed sines. A
# capstan does not wander freely and it does not follow a fixed cycle -- it
# drifts and is pulled back toward centre. O-U is exactly that: a random walk
# with a restoring force. Summed sines never repeat either, but they are
# deterministic underneath, and the ear eventually finds the pattern.
module TapeHysteresis
  module_function

  # Langevin function, the anhysteretic magnetisation curve. Series expansion
  # near zero: coth(x) - 1/x is 0/0 there and loses all precision in floating
  # point well before it reaches it.
  def langevin(x)
    return x / 3.0 if x.abs < 1e-4

    (1.0 / Math.tanh(x)) - (1.0 / x)
  end

  def langevin_prime(x)
    return 1.0 / 3.0 if x.abs < 1e-4

    s = Math.sinh(x)
    (1.0 / (x * x)) - (1.0 / (s * s))
  end

  # dM/dH at one point. `delta` carries the direction of travel, and it is the
  # only reason this differs from a memoryless curve.
  def dmdh(m, h, dh, p)
    q = (h + (p[:alpha] * m)) / p[:a]
    m_an = p[:ms] * langevin(q)
    dm = m_an - m
    delta = dh.negative? ? -1.0 : 1.0
    # Guard the denominator: at a turning point dm approaches zero along with
    # the drive, and the quotient is 0/0.
    denom = (p[:k] * delta) - (p[:alpha] * dm)
    denom = (p[:k] * delta) if denom.abs < 1e-9
    irr = dm / denom
    rev = (p[:ms] / p[:a]) * langevin_prime(q)
    ((1.0 - p[:c]) * irr) + (p[:c] * rev)
  end

  DEFAULTS = { ms: 1.0, a: 0.22, alpha: 1.6e-3, k: 0.47, c: 1.7e-1 }.freeze

  # Bias current. 1.0 is this file's original loop (more bias, tighter).
  # 0.0 widens k and a — ChowTape's "less bias" dead zone at low level —
  # so quiet material and loud material stop sharing one saturator at two gains.
  # Default 1.0 so an unset TAPE_BIAS is the loop every existing render heard.
  def params_for_bias(bias)
    b = bias.to_f.clamp(0.0, 1.0)
    open = 1.0 - b
    DEFAULTS.merge(k: 0.47 + (0.38 * open), a: 0.22 + (0.10 * open))
  end

  # RK4 over the input as the driving field.
  def process(samples, drive: 1.0, params: DEFAULTS)
    m = 0.0
    prev_h = 0.0
    out = Array.new(samples.length)
    samples.each_with_index do |s, i|
      h = s * drive
      dh = h - prev_h
      k1 = dmdh(m, prev_h, dh, params)
      k2 = dmdh(m + (0.5 * k1 * dh), prev_h + (0.5 * dh), dh, params)
      k3 = dmdh(m + (0.5 * k2 * dh), prev_h + (0.5 * dh), dh, params)
      k4 = dmdh(m + (k3 * dh), h, dh, params)
      m += (dh / 6.0) * (k1 + (2.0 * k2) + (2.0 * k3) + k4)
      out[i] = m
      prev_h = h
    end
    out
  end

  # Ornstein-Uhlenbeck: dx = theta*(0 - x)*dt + sigma*dW. theta is how hard it
  # is pulled back, sigma how far it wanders. Seeded, because a flutter you
  # cannot reproduce is not a character.
  def ou_series(length, rate:, theta: 0.55, sigma: 0.9, seed: 7)
    rng = Random.new(seed)
    dt = 1.0 / rate
    x = 0.0
    sqrt_dt = Math.sqrt(dt)
    Array.new(length) do
      # Box-Muller for a normal deviate; rand alone is uniform and gives the
      # walk the wrong distribution of step sizes.
      u1 = [rng.rand, 1e-12].max
      u2 = rng.rand
      g = Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2)
      x += (-theta * x * dt) + (sigma * sqrt_dt * g)
      x
    end
  end

  # Fractional-delay read, linear interpolation. depth_ms is the peak excursion.
  def apply_wow(samples, rate:, depth_ms: 1.2, seed: 7)
    return samples if depth_ms <= 0.0

    ctrl = ou_series(samples.length, rate:, seed:)
    peak = ctrl.map(&:abs).max
    return samples if peak.zero?

    scale = (depth_ms / 1000.0 * rate) / peak
    max_delay = (depth_ms / 1000.0 * rate).ceil + 2
    out = Array.new(samples.length, 0.0)
    samples.each_index do |i|
      pos = i - max_delay + (ctrl[i] * scale)
      j = pos.floor
      next if j <= 0 || j + 1 >= samples.length

      frac = pos - j
      out[i] = (samples[j] * (1.0 - frac)) + (samples[j + 1] * frac)
    end
    out
  end
end

# The voices DillaSemantics asks for, synthesised sample by sample.
#
# Pure Ruby rather than aevalsrc, for the reason render_hate_techno's comments
# measured twice: every hit is another term in one ffmpeg expression, and
# sixteenth hats over eight bars made ffmpeg refuse the layer for memory. Here a
# hit is an array, built once and added where it lands, so a kick can carry a
# pitch envelope, a click and a tail as parameters instead of as a literal.
module TechnoVoices
  RATE = 44_100
  TWO_PI = 2.0 * Math::PI

  module_function

  # KICK. A note that happens four times a bar, designed as an instrument:
  # a body whose pitch falls from body+sweep to body, an amplitude decay, and a
  # click. Returned as [transient, body] so the two are processed apart -- the
  # body is driven into harmonics and the click stays clean, because a dirty
  # body under a clean attack is a comparison the ear can make, and a kick
  # distorted whole is only louder.
  def kick(voice, velocity: 1.0, decay_scale: 1.0, tail: 1.0)
    length = (0.5 * tail * RATE).to_i
    amp_decay = voice[:amp_decay] / (decay_scale * tail)
    phase = 0.0
    body = Array.new(length) do |i|
      t = i.to_f / RATE
      phase += TWO_PI * (voice[:body_hz] + (voice[:sweep_hz] * Math.exp(-t * voice[:sweep_decay]))) / RATE
      Math.sin(phase) * Math.exp(-t * amp_decay) * velocity
    end
    [click(voice[:click_ms], velocity * 0.5), dirt!(body, voice[:drive])]
  end

  def click(ms, velocity)
    rng = Random.new((ms * 1000).round)
    length = (ms / 1000.0 * RATE * 4).to_i.clamp(8, RATE)
    burst = Array.new(length) { |i| ((rng.rand * 2.0) - 1.0) * Math.exp(-i * 4.0 / length) * velocity }
    highpass!(burst, 1800.0)
  end

  # FM BURST. The modulation index decays much faster than the note, so the hit
  # opens as a spray of sidebands and settles into a near-sine: the transient
  # evolution FM percussion is used for, and the DFAM patch's two oscillators.
  def fm_burst(hz:, ratio:, index:, velocity:, decay_scale: 1.0, length: 0.3)
    frames = (length * RATE).to_i
    amp_decay = 14.0 / decay_scale
    Array.new(frames) do |i|
      t = i.to_f / RATE
      mod = index * Math.exp(-t * 60.0) * Math.sin(TWO_PI * hz * ratio * t)
      Math.sin((TWO_PI * hz * t) + mod) * Math.exp(-t * amp_decay) * velocity
    end
  end

  # RESONATOR. A few milliseconds of noise struck into tuned bandpasses at
  # inharmonic partials: metal, pipe, glass -- percussion that is not a drum.
  def resonator(partials:, velocity:, seed:, q: 18.0, decay_scale: 1.0, length: 0.4)
    rng = Random.new(seed)
    frames = (length * RATE).to_i
    strike = (0.004 * RATE).to_i
    excite = Array.new(frames) { |i| i < strike ? (rng.rand * 2.0) - 1.0 : 0.0 }
    rung = partials.map { |hz| bandpass(excite, hz, q) }
    decay = 9.0 / decay_scale
    Array.new(frames) { |i| rung.sum { |r| r[i] } * Math.exp(-i * decay / RATE) * velocity * 2.5 }
  end

  # RBJ constant-peak bandpass. Kept to one form because the resonator is its
  # only reader and a second filter family would be a second place to tune.
  def bandpass(input, hz, q)
    w0 = TWO_PI * hz.clamp(20.0, (RATE / 2.0) - 100.0) / RATE
    alpha = Math.sin(w0) / (2.0 * q)
    a0 = 1.0 + alpha
    b0 = alpha / a0
    a1 = -2.0 * Math.cos(w0) / a0
    a2 = (1.0 - alpha) / a0
    x1 = x2 = y1 = y2 = 0.0
    input.map do |x|
      y = (b0 * x) - (b0 * x2) - (a1 * y1) - (a2 * y2)
      x2 = x1
      x1 = x
      y2 = y1
      y1 = y
    end
  end

  # HAT. Noise above 7 kHz. Its decay is the parameter that moves: the shorter
  # the hats, the faster a track feels at the same tempo.
  def hat(velocity:, seed:, decay: 0.05)
    rng = Random.new(seed)
    frames = (decay * 5.0 * RATE).to_i.clamp(64, RATE)
    noise = Array.new(frames) { |i| ((rng.rand * 2.0) - 1.0) * Math.exp(-i / (decay * RATE)) * velocity }
    highpass!(highpass!(noise, 7000.0), 7000.0)
  end

  # A sine with a falling pitch: a bass note when `drop` is small, a tom moving
  # the sub when it is large.
  def tone(hz:, velocity:, length: 0.3, drop: 0.0, decay: 6.0)
    phase = 0.0
    Array.new((length * RATE).to_i) do |i|
      t = i.to_f / RATE
      phase += TWO_PI * hz * (1.0 + (drop * Math.exp(-t * 18.0))) / RATE
      (Math.sin(phase) + (0.18 * Math.sin(2.0 * phase))) * Math.exp(-t * decay) * velocity
    end
  end

  # STAB. A minor seventh on detuned saws through a lowpass whose cutoff is the
  # stab's moving parameter -- the dub chord, and Detroit's.
  def stab(root_hz:, velocity:, cutoff:, length: 0.45)
    chord = [1.0, 1.1892, 1.4983, 1.7818].flat_map { |r| [root_hz * r * 0.997, root_hz * r * 1.003] }
    frames = (length * RATE).to_i
    out = Array.new(frames) do |i|
      t = i.to_f / RATE
      saw = chord.sum { |hz| (((hz * t) % 1.0) * 2.0) - 1.0 } / chord.length
      saw * [t * 200.0, 1.0].min * Math.exp(-t * 7.0) * velocity
    end
    lowpass!(lowpass!(out, cutoff), cutoff)
  end

  # Drive into tanh, then a fold past 0.6, level-matched by the curve's own
  # ceiling. Harmonics are generated rather than borrowed from volume.
  def dirt!(samples, amount)
    return samples if amount <= 0.0

    drive = 1.0 + (amount * 6.0)
    ceiling = Math.tanh(drive)
    samples.map! { |x| Math.tanh(x * drive) / ceiling }
    SpaceFx.fold(samples, amount: 1.2 + amount, mix: amount - 0.6) if amount > 0.6
    samples
  end

  def lowpass!(samples, hz)
    k = 1.0 - Math.exp(-TWO_PI * hz / RATE)
    y = 0.0
    samples.map! { |x| y += k * (x - y) }
  end

  def highpass!(samples, hz)
    k = 1.0 - Math.exp(-TWO_PI * hz / RATE)
    low = 0.0
    samples.map! do |x|
      low += k * (x - low)
      x - low
    end
  end

  # RUMBLE, derived rather than added. The kick bus goes into a long room, the
  # room into a lowpass, the lowpass into drive and another lowpass: the attack
  # stays the kick's and the sustain becomes the environment around it. Ducked
  # by the kick afterwards, so the two are one low end taking turns.
  def rumble(kick_bus, feedback:, dirt:)
    tail = kick_bus.dup
    SpaceFx.reverb(tail, mix: 1.0, decay: (0.8 + (feedback * 0.15)).clamp(0.0, 0.95), damping: 0.55)
    lowpass!(tail, 180.0)
    dirt!(tail, 0.4 + (dirt * 0.5))
    lowpass!(lowpass!(tail, 110.0), 110.0)
    normalize!(tail, 0.6)
  end

  # Sidechain as arithmetic: the gain dips at every kick and recovers.
  def duck!(samples, kick_frames, depth:, release: 0.18)
    marks = kick_frames.sort
    last = -RATE * 10
    pointer = 0
    samples.each_index do |i|
      while pointer < marks.length && marks[pointer] <= i
        last = marks[pointer]
        pointer += 1
      end
      samples[i] *= 1.0 - (depth * Math.exp(-(i - last) / (release * RATE)))
    end
    samples
  end

  def normalize!(samples, peak)
    top = samples.map(&:abs).max.to_f
    return samples if top < 1e-9

    scale = peak / top
    samples.map! { |x| x * scale }
  end

  # RESAMPLING. The track's own audio, recorded and cut again: slice it, and per
  # slice reverse it, play it at double or half speed, or stutter its first
  # half, then "record" the pass -- darker and more driven each generation, as
  # a bounce to tape is -- and cut that at a different slice length. What comes
  # out is sculpted audio no oscillator in the engine would produce.
  def resample(samples, passes:, slice:, rng:)
    (0...passes).reduce(samples) do |source, pass|
      size = pass.even? ? slice : slice * 2
      cut = source.each_slice(size).flat_map { |chunk| rework(chunk, rng.rand(6)) }
      record!(cut, pass)
    end
  end

  def rework(chunk, move)
    case move
    when 0 then chunk.reverse
    when 1 then varispeed(chunk, 2.0)
    when 2 then varispeed(chunk, 0.5)
    when 3 then chunk.first(chunk.length / 2).then { |half| (half + half).first(chunk.length) }
    else chunk
    end
  end

  # Read at `rate` and wrap to the slice's length, so the grid survives a speed
  # change. Linear interpolation between neighbours.
  def varispeed(chunk, rate)
    n = chunk.length
    Array.new(n) do |i|
      pos = (i * rate) % n
      low = pos.floor
      chunk[low] + ((chunk[(low + 1) % n] - chunk[low]) * (pos - low))
    end
  end

  def record!(samples, pass)
    lowpass!(samples, 9000.0 - (pass * 1800.0))
    dirt!(samples, 0.15 + (pass * 0.1))
  end

  def place!(bus, hit, frame, gain)
    return if frame.negative?

    last = [hit.length, bus.length - frame].min
    i = 0
    while i < last
      bus[frame + i] += hit[i] * gain
      i += 1
    end
  end
end

# One render of a DillaSemantics profile, from plan to stereo buffers.
#
# The order is the log's: the busiest state defines the track and every section
# is that state reduced or transformed; the kick is a voice; the low end is the
# profile's choice, with rumble grown from the processed kick; the percussion is
# one family struck three ways; delay and feedback write rhythm of their own; and
# the texture is this render's audio, resampled.
class SemanticTechno
  RATE = TechnoVoices::RATE
  V = TechnoVoices

  attr_reader :profile, :bars, :seed, :bpm, :beat, :frames

  def self.render(profile, bars:, seed:, roots: nil) = new(profile, bars:, seed:, roots:).render

  def initialize(profile, bars:, seed:, roots: nil)
    @profile = profile
    @bars = bars
    @seed = seed
    @bpm = profile.fetch(:bpm).to_f
    @beat = 60.0 / @bpm
    @frames = (((bars * 4 * @beat) + 1.5) * RATE).to_i
    @root = (Array(roots).first || 55.0).to_f
    @root /= 2.0 while @root > 65.0
  end

  def render
    kick = kick_bus
    drums = [bus, bus]
    space = [bus, bus]
    events.each { |event| strike(event, event[:element] == :perc_b || event[:element] == :stab ? space : drums) }
    echo!(space)
    master = mix(kick, drums, space)
    add_low!(master, kick)
    add_texture!(master, drums, space)
    master.each { |side| V.normalize!(side, 0.9) }
  end

  # Every hit of the render, as data: element, time, velocity, envelope scale,
  # the section's gain and transform. Built before any sound, so the plan can be
  # read and tested apart from the synthesis.
  def events
    @events ||= (0...bars).flat_map { |bar| bar_events(bar) }
  end

  def bar_events(bar)
    state = DillaSemantics.section_state(profile, section_at(bar))
    drop = DillaSemantics.dropout_bar?(profile, bar, seed)
    state.flat_map do |element, s|
      next [] if element == :low && low_end == :kick_tail

      DillaSemantics.figure(profile, element, bar, seed:).filter_map do |step, velocity, decay|
        next if drop && %i[kick low].include?(element) && step >= 8

        at = (bar * 4 * beat) + (step * beat / 4.0) + DillaSemantics.timing_offset(profile, element, step, beat)
        { element:, bar:, step:, at: [at, 0.0].max, velocity:, decay:, gain: s[:gain], transform: s[:transform] }
      end
    end
  end

  def section_at(bar)
    DillaSemantics.sections(bars).fetch(bar / DillaSemantics::SECTION_BARS)
  end

  def low_end = profile.fetch(:low_end)

  private

  def bus = Array.new(frames, 0.0)

  def frame(at) = (at * RATE).round

  # A moving parameter at time `at`, on the element's own period, -1..1.
  def motion(element, at)
    DillaModulation.morphed(:curved, 0.33, (at * motion_hz(element)) % 1.0)
  end

  def motion_hz(element)
    @motion_hz ||= {}
    @motion_hz[element] ||= DillaModulation.sync_hz("#{DillaSemantics::ELEMENTS.fetch(element).fetch(:motion_beats) / 4.0}bar", bpm)
  end

  def axis(name) = DillaSemantics.axis(profile, name)

  def kick_bus
    out = bus
    tail = low_end == :kick_tail ? 1.8 : 1.0
    events.select { |e| e[:element] == :kick }.each do |e|
      transient, body = V.kick(profile.fetch(:kick), velocity: e[:velocity], decay_scale: e[:decay], tail:)
      V.place!(out, transient, frame(e[:at]), e[:gain])
      V.place!(out, body, frame(e[:at]), e[:gain])
    end
    out
  end

  def strike(event, stereo)
    return if event[:element] == :kick || event[:element] == :low || event[:element] == :texture

    hit = voice(event)
    hit = V.dirt!(hit, 0.5 + (0.5 * axis(:contrast))) if event[:transform] == :dirty
    pan = pan_for(event)
    left = Math.cos((pan + 1.0) * Math::PI / 4.0)
    right = Math.sin((pan + 1.0) * Math::PI / 4.0)
    V.place!(stereo[0], hit, frame(event[:at]), event[:gain] * left)
    V.place!(stereo[1], hit, frame(event[:at]), event[:gain] * right)
  end

  def pan_for(event)
    case event[:element]
    when :perc_b then 0.7 * axis(:spatial_motion) * motion(:perc_b, event[:at])
    when :open then 0.25
    when :perc_a then -0.2
    else 0.0
    end
  end

  # One percussion family. The DFAM patch's two oscillators set the base and the
  # ratio, so hats, metal and FM hits are related sounds rather than three picks.
  def voice(event)
    base = family_hz
    move = motion(event[:element], event[:at])
    hit_seed = seed + frame(event[:at])
    case event[:element]
    when :hat then V.hat(velocity: event[:velocity] * 1.4, seed: hit_seed, decay: hat_decay(event, move))
    when :open then V.hat(velocity: event[:velocity] * 1.0, seed: hit_seed, decay: 0.22 * event[:decay])
    when :clap then clap(event, hit_seed)
    when :perc_a then metal(event, base, move, hit_seed)
    when :perc_b then V.fm_burst(hz: base * 6.0, ratio: family_ratio, index: fm_index, velocity: event[:velocity] * 0.5,
                                 decay_scale: event[:decay])
    else stab(event, move)
    end
  end

  def hat_decay(event, move)
    base = 0.05 * event[:decay] * (1.0 + (0.35 * axis(:spectral_motion) * move))
    event[:transform] == :filtered ? base * 0.5 : base
  end

  def clap(event, hit_seed)
    V.resonator(partials: [1100.0, 1600.0, 2400.0], q: 3.0, velocity: event[:velocity] * 0.6, seed: hit_seed,
                decay_scale: event[:decay] * 0.6, length: 0.25)
  end

  def metal(event, base, move, hit_seed)
    shift = 1.0 + (0.08 * axis(:spectral_motion) * move)
    V.resonator(partials: [base * 16.0, base * 23.5, base * 33.4].map { |hz| hz * shift },
                velocity: event[:velocity] * 0.45, seed: hit_seed, decay_scale: event[:decay])
  end

  def stab(event, move)
    cutoff = 700.0 + (2400.0 * (0.5 + (0.5 * axis(:spectral_motion) * move)))
    cutoff *= 1.0 - (0.7 * axis(:contrast)) if event[:transform] == :filtered
    V.stab(root_hz: @root * 4.0, velocity: event[:velocity] * 0.35, cutoff:)
  end

  def dfam = @dfam ||= DfamEngine.resolve_patch

  def family_hz = dfam[:osc1_hz].to_f.clamp(40.0, 400.0)

  def family_ratio = (dfam[:osc2_hz].to_f / [dfam[:osc1_hz].to_f, 1.0].max).clamp(0.25, 8.0)

  def fm_index = dfam[:fm_pct] / 100.0 * 6.0

  # Delay as composition. Left repeats on the dotted eighth and right on the
  # quarter, so one hit becomes two figures in counterpoint; the feedback axis
  # is how many generations each figure survives, and the damping inside
  # SpaceFx's loop makes every generation darker than the one before -- the
  # recursion is in the loop, not approximated after it.
  def echo!(space)
    feedback = (0.2 + (axis(:feedback) * 0.7)).clamp(0.0, 0.9)
    SpaceFx.space_echo(space[0], time: beat * 0.75, feedback:, mix: 0.5, damping: 0.35)
    SpaceFx.space_echo(space[1], time: beat, feedback:, mix: 0.5, damping: 0.35)
    space.each_with_index { |side, i| SpaceFx.reverb(side, mix: 0.15 + (0.3 * axis(:spatial_motion)), spread: i * 23) }
  end

  def mix(kick, drums, space)
    Array.new(2) do |side|
      Array.new(frames) { |i| kick[i] + drums[side][i] + (space[side][i] * 0.8) }
    end
  end

  def add_low!(master, kick)
    low = low_bus(kick)
    return unless low

    kicks = events.select { |e| e[:element] == :kick }.map { |e| frame(e[:at]) }
    V.duck!(low, kicks, depth: 0.85)
    master.each { |side| frames.times { |i| side[i] += low[i] * 0.8 } }
  end

  def low_bus(kick)
    case low_end
    when :kick_tail then nil
    when :rumble then gated_rumble(kick)
    when :bass then notes(0.0)
    when :tom_sub then notes(1.6)
    else hybrid(kick)
    end
  end

  def gated_rumble(kick)
    rumble = V.rumble(kick, feedback: axis(:feedback), dirt: axis(:harmonic_density))
    bar_frames = (4 * beat * RATE).round
    gains = Array.new(bars + 2) { |bar| low_gain(bar) }
    rumble.each_index { |i| rumble[i] *= gains[i / bar_frames] }
    rumble
  end

  def hybrid(kick)
    rumble = gated_rumble(kick)
    bass = notes(0.0)
    Array.new(frames) { |i| (rumble[i] * 0.45) + (bass[i] * 0.4) }
  end

  def low_gain(bar)
    return 0.0 if bar >= bars

    DillaSemantics.section_state(profile, section_at(bar)).fetch(:low, { gain: 0.0 })[:gain]
  end

  # Bass notes on the low figure; toms move a step late and fall in pitch.
  def notes(drop)
    out = bus
    events.select { |e| e[:element] == :low }.each do |e|
      at = e[:at] + (drop.positive? || e[:transform] == :varied ? beat / 4.0 : 0.0)
      hz = e[:transform] == :varied && e[:step] % 8 == 6 ? @root * 2.0 : @root
      note = V.tone(hz:, velocity: e[:velocity] * 0.7, drop:, length: drop.positive? ? 0.4 : 0.22)
      note = V.lowpass!(note, 90.0) if e[:transform] == :filtered
      V.place!(out, V.dirt!(note, axis(:harmonic_density) * 0.5), frame(at), e[:gain])
    end
    out
  end

  # The texture is not synthesised. It is the first cycle of this render's own
  # drums and space, resampled, looped under the section gains, and panned on the
  # atmosphere's sixty-four-bar period.
  def add_texture!(master, drums, space)
    return unless profile[:elements].include?(:texture)

    loop = resampled_cycle(drums, space)
    bar_frames = (4 * beat * RATE).round
    frames.times.each_slice(2048) do |block|
      bar = block.first / bar_frames
      gain = bar < bars ? texture_gain(bar) * 0.35 : 0.0
      pan = 0.6 * axis(:spatial_motion) * motion(:texture, block.first.to_f / RATE)
      block.each do |i|
        master[0][i] += loop[i % loop.length] * gain * (1.0 - pan)
        master[1][i] += loop[i % loop.length] * gain * (1.0 + pan)
      end
    end
  end

  def resampled_cycle(drums, space)
    cycle = [(4 * 4 * beat * RATE).round, frames].min
    source = Array.new(cycle) { |i| drums[0][i] + drums[1][i] + space[0][i] + space[1][i] }
    passes = 1 + (axis(:resampling) * 3).round
    step = (beat / 4.0 * RATE).round
    V.normalize!(V.resample(source, passes:, slice: step * 2, rng: Random.new(seed)), 0.8)
  end

  def texture_gain(bar)
    @texture_gain ||= {}
    @texture_gain[bar] ||= DillaSemantics.section_state(profile, section_at(bar)).fetch(:texture)[:gain]
  end
end

require "json"
# The O-U walk behind the :random source. Required here rather than left to the
# caller: tape_master.rb loads this lazily inside tape_hysteresis!, so on a
# render that never touches tape the constant does not exist, and a :random
# route would fail at the moment it was read instead of at the moment it was
# built.

# Parameters that move.
#
# Everything in this engine is set once. A render picks a lowpass cutoff, a
# compressor threshold, a phaser speed, and that number holds from bar one to
# the end. That is why a dilla render reads as a loop with sections rather than
# as a performance: nothing on the signal path is being played while it runs.
#
# automation_lane.rb is the one exception and it is a narrow one. It builds a
# right-nested `if(lt(t,X),A,B)` ladder for `volume`, which works because volume
# takes an EXPRESSION re-evaluated per frame. Its own header records the wall it
# hit: lowpass and highpass reject that syntax, so everything except gain was
# out of reach, and it says the fix would be "asendcmd with a timed command
# file, which is a different, heavier mechanism not implemented here".
#
# This is that mechanism, and the wall was lower than it looked. ffmpeg marks
# every runtime-settable option with T in its flags column, and the list is
# large -- measured against the ffmpeg this repo actually runs (8.1.1):
#
#   lowpass/highpass     frequency width mix
#   equalizer/bass/treble frequency width gain mix
#   acompressor          threshold ratio attack release makeup knee mix level_sc
#   alimiter             limit level_in level_out attack release
#   acrusher             bits mix mode dc aa samples lfo lforange lforate
#   stereotools          balance_in balance_out slev sbal mlev mpan delay phase
#   asubboost            dry wet boost decay feedback cutoff
#   aexciter             amount drive blend freq ceil
#   afreqshift/aphaseshift  shift level
#   asoftclip            threshold output param
#   atempo               tempo
#
# Proved end to end before any of this was written: white noise through
# `asendcmd=f=cmds,lowpass@m1=f=400` with the cutoff stepped 400 -> 15000 moved
# the energy above 6 kHz from -66.7 dB to -16.9 dB. A 50 dB sweep, on a filter
# the previous note called unautomatable.
#
# The one detail that decides whether any of this works: asendcmd's TARGET is
# the filter's INSTANCE name, `lowpass@m1`, not the instance id `m1` and not the
# class `lowpass`. Targeting `m1` sends the command nowhere and reports nothing
# -- the first sweep measured dead flat for exactly that reason. Every instance
# this module emits is named, and the name it writes into the command file is
# the name it wrote into the graph.
#
# What this deliberately is NOT:
#
#   - audio rate. Commands land on frame boundaries, so this is a control-rate
#     mechanism: musical movement over bars and beats, not FM. Anything that
#     has to move per sample belongs in Ruby with the grain cloud and the
#     hysteresis model, or in an expression on `volume`.
#   - a new sound by default. Nothing here is reached unless a caller builds a
#     matrix. The engine's existing renders are unchanged, which is the only
#     honest way to add a mechanism this wide to a tool whose output nobody can
#     re-audition.
module DillaModulation
  # Ableton's LFO offers eight destinations. That is not a technical ceiling and
  # neither is this, but a matrix nobody can read is a matrix nobody will debug.
  MAX_ROUTES = 32

  # How often a command is emitted. Commands take effect on the frame that
  # carries them, so this is the real resolution of every movement here.
  #
  # 48 per second: fast enough that a filter sweep over a bar reads as a sweep
  # rather than as steps, slow enough that a four-minute render with six routes
  # writes about 70k command lines rather than a million. Raising it past a
  # couple of hundred buys nothing -- ffmpeg's audio frame is 1024 samples, so
  # above ~43 Hz at 44.1k some commands land on the same frame as the last.
  DEFAULT_RATE_HZ = (ENV["MOD_RATE_HZ"] || "48").to_f.clamp(4.0, 200.0)

  module_function

  # ------------------------------------------------------------------ shapes
  #
  # Two families, each a continuum rather than a menu.
  #
  # ringtone.tools' LFO is the clearest statement of the idea: instead of thirty
  # waveform buttons, one control moves through a space of shapes, and the
  # straight-edged and the curved families are offered as separate continua so
  # "sharper" and "rounder" are different gestures. That is worth stealing
  # outright. A morph knob is playable in a way a shape menu is not, and it is
  # automatable, which a menu is not at all.
  #
  # Every shape takes phase in 0...1 and returns -1..1.

  # Straight family, in morph order: square -> trapezoid -> triangle -> ramp.
  def square(phase) = phase < 0.5 ? 1.0 : -1.0

  # A trapezoid is a square with its edges given a slope; at slope 0 it IS a
  # square and at slope 0.5 it is a triangle, which is why it sits between them.
  def trapezoid(phase, slope: 0.25)
    s = slope.clamp(0.001, 0.5)
    p = phase % 1.0
    if p < s then (p / s * 2.0) - 1.0
    elsif p < 0.5 then 1.0
    elsif p < 0.5 + s then 1.0 - ((p - 0.5) / s * 2.0)
    else -1.0
    end
  end

  def triangle(phase)
    p = phase % 1.0
    p < 0.5 ? (p * 4.0) - 1.0 : 3.0 - (p * 4.0)
  end

  def ramp(phase) = (2.0 * (phase % 1.0)) - 1.0

  # Curved family: parabola -> sine -> sharkfin -> exponential.

  # Rounder than a sine at the peaks and steeper through zero.
  def parabola(phase)
    t = triangle(phase)
    t.negative? ? -(t * t) : t * t
  end

  def sine(phase) = Math.sin(2.0 * Math::PI * (phase % 1.0))

  # Slow curved rise, near-instant fall. The shape a plucked string's envelope
  # has backwards, and the one that makes a filter breathe rather than pulse.
  def sharkfin(phase)
    p = phase % 1.0
    return 1.0 - (((p - 0.92) / 0.08) * 2.0) if p >= 0.92

    (2.0 * Math.sqrt(p / 0.92)) - 1.0
  end

  # Instant attack, exponential decay -- an envelope in LFO clothing, and the
  # shape that makes a repeated modulation read as a hit rather than a wave.
  def exponential(phase, curve: 5.0)
    p = phase % 1.0
    (2.0 * Math.exp(-curve * p)) - 1.0
  end

  # Stepped family: staircase -> sample-and-hold -> pendulum -> random walk.
  #
  # Neither family above can hold still. Both are continuous by construction, so
  # every value between two points is visited on the way, and a modulation that
  # JUMPS -- the oldest gesture in modular synthesis -- was not expressible.
  #
  # The four are ordered by how predictable the next step is, so the morph knob
  # runs from "counts" to "wanders" rather than between unrelated behaviours.
  STEPS = 8

  # An even staircase up and back. Predictable, and the one that reads as a
  # sequence rather than as an effect.
  def staircase(phase)
    p = phase % 1.0
    step = (p * STEPS).floor
    up = step < STEPS / 2
    idx = up ? step : STEPS - 1 - step
    ((idx.to_f / ((STEPS / 2) - 1)) * 2.0) - 1.0
  end

  # Sample and hold: a new value each step, held flat until the next.
  #
  # Deterministic from the step index rather than from a stateful RNG, so the
  # same phase always gives the same value. A source read by three routes has to
  # give all three the same number, and a generator that advanced per call would
  # give each of them a different one -- which would be three sources wearing
  # one name.
  def sample_hold(phase, seed: 7)
    step = ((phase % 1.0) * STEPS).floor
    h = ((step * 2_654_435_761) ^ (seed * 40_503)) & 0x7fffffff
    ((h % 2001) / 1000.0) - 1.0
  end

  # A pendulum over the same steps: 0, 2, 4, 6, 7, 5, 3, 1. Visits every value
  # exactly once per cycle in an order that is neither scalar nor random, which
  # is the analog shift register's musical trick.
  PENDULUM_ORDER = [0, 2, 4, 6, 7, 5, 3, 1].freeze

  def pendulum(phase)
    idx = PENDULUM_ORDER[((phase % 1.0) * STEPS).floor % STEPS]
    ((idx.to_f / (STEPS - 1)) * 2.0) - 1.0
  end

  # A random walk: each step moves up or down from the last rather than jumping
  # anywhere, so consecutive values are related and the line wanders instead of
  # scattering.
  #
  # The last step is forced to return the walk to where it started, so the cycle
  # does not DRIFT -- repeated cycles cover the same ground rather than climbing
  # away. That is not the same as closing smoothly: this is a stepped shape and
  # the wrap is a step like any other, sometimes a larger one. WavMap's paths
  # close because a waveform's loop point is heard as a click; a control-rate
  # modulation has no such constraint, and jumps are the point of this family.
  def random_walk(phase, seed: 7)
    steps = (0...STEPS).map { |i| ((((i * 2_246_822_519) ^ (seed * 668_265_263)) >> 8) & 1).zero? ? -1 : 1 }
    # Force the walk back to zero across the cycle so it closes.
    steps[-1] = -steps[0...-1].sum
    walk = steps.each_with_object([0]) { |d, acc| acc << acc.last + d }
    span = [walk.map(&:abs).max, 1].max
    walk[((phase % 1.0) * STEPS).floor % STEPS].to_f / span
  end

  STRAIGHT = %i[square trapezoid triangle ramp].freeze
  CURVED = %i[parabola sine sharkfin exponential].freeze
  STEPPED = %i[staircase sample_hold pendulum random_walk].freeze
  FAMILIES = { straight: STRAIGHT, curved: CURVED, stepped: STEPPED }.freeze

  # Continuous position through a family. morph 0 is the first shape, 1 is the
  # last, and everything between is a crossfade of the two it falls between.
  #
  # Crossfading the OUTPUTS rather than interpolating the shapes' parameters is
  # deliberate: it needs no shape to know about any other, so a family can grow
  # by appending to the list, and every intermediate is a real waveform rather
  # than a shape with a wrong parameter.
  def morphed(family, morph, phase)
    shapes = FAMILIES.fetch(family.to_sym) { STRAIGHT }
    return send(shapes.first, phase) if shapes.one?

    pos = morph.to_f.clamp(0.0, 1.0) * (shapes.length - 1)
    low = pos.floor.clamp(0, shapes.length - 2)
    blend = pos - low
    a = send(shapes[low], phase)
    b = send(shapes[low + 1], phase)
    (a * (1.0 - blend)) + (b * blend)
  end

  # --------------------------------------------------------------- rate sync
  #
  # A modulation rate in bars and beats rather than hertz.
  #
  # Every rate this engine wants is musical: a filter that opens once a bar, a
  # tremolo on eighths, a swell across four bars. Expressing those in hertz means
  # doing 88/240 in your head and redoing it whenever the tempo moves -- and a
  # rate that does not move with the tempo is the one modulation that always
  # sounds wrong, because it drifts against everything else in the render.
  #
  # Accepts what a musician would write:
  #
  #   "1/4"    one cycle per quarter note        "4bar"   one cycle per 4 bars
  #   "1/8T"   triplet eighth                    "2b"     same, abbreviated
  #   "1/16."  dotted sixteenth                  0.25     hertz, unchanged
  #
  # T shortens the value to two thirds, so the rate goes UP by half. A dot
  # lengthens it by half, so the rate goes DOWN to two thirds. Getting those two
  # backwards is the classic error and the reason they are spelled out here.
  #
  # 4/4 is assumed, which is what every grid in this engine is.
  BAR_BEATS = 4.0

  def sync_hz(rate, bpm)
    return rate.to_f if rate.is_a?(Numeric)

    text = rate.to_s.strip.downcase
    return text.to_f if text.match?(/\A[\d.]+\z/)

    beat_sec = 60.0 / bpm.to_f
    seconds =
      if (bars = text[/\A([\d.]+)\s*b(?:ar)?s?\z/, 1])
        bars.to_f * BAR_BEATS * beat_sec
      elsif (denom = text[/\A1\/([\d.]+)/, 1])
        # 1/4 is a quarter note; 1/1 is a whole note, which is one bar in 4/4.
        (BAR_BEATS / denom.to_f) * beat_sec
      else
        raise ArgumentError, "cannot read #{rate.inspect} as a rate — try 1/4, 1/8T, 2bar or a number in Hz"
      end
    seconds *= 2.0 / 3.0 if text.end_with?("t")
    seconds *= 1.5 if text.end_with?(".")
    raise ArgumentError, "#{rate.inspect} at #{bpm} BPM is not a positive rate" unless seconds.positive?

    1.0 / seconds
  end

  # ----------------------------------------------------------------- sources
  #
  # A source is a function of time returning -1..1. Nothing here knows what it
  # is modulating; a source is worth having only because it is worth pointing
  # at more than one thing.
  #
  # kind:
  #   :lfo       family/morph/rate_hz/phase -- the shapes above.
  #   :envelope  points as [[time_sec, value], ...], linear between, held at
  #              the ends. The one-shot to an LFO's cycle.
  #   :random    Ornstein-Uhlenbeck: a random walk with a restoring force, so
  #              it wanders without leaving. Reuses TapeHysteresis.ou_series
  #              rather than growing a second O-U in this tree -- wow/flutter
  #              and a random modulator are the same process with different
  #              time constants, and having two would let them disagree.
  #   :steps     an explicit sequence, one value per step, held. A sequencer
  #              lane; the thing an LFO cannot do because its shape repeats.
  Source = Struct.new(:id, :kind, :rate_hz, :family, :morph, :phase, :points,
                      :values, :theta, :sigma, :seed, keyword_init: true) do
    def initialize(*)
      super
      self.kind = (kind || :lfo).to_sym
      self.rate_hz = (rate_hz || 1.0).to_f
      self.family ||= :curved
      self.morph = (morph || 0.33).to_f
      self.phase = (phase || 0.0).to_f
      self.seed = (seed || 7).to_i
    end

    def value_at(time)
      case kind
      when :lfo then DillaModulation.morphed(family, morph, (time * rate_hz) + phase)
      when :envelope then DillaModulation.envelope_at(points, time)
      when :random then random_at(time)
      when :steps then step_at(time)
      else 0.0
      end
    end

    # The walk is generated once, at the source's own rate, and read by index.
    # Generating per query would draw a different number for every route
    # pointing here, which would make one source behave as several.
    def random_at(time)
      @walk ||= DillaModulation.ou_walk(length: 4096, theta: theta || 0.55,
                                        sigma: sigma || 0.9, seed:)
      idx = (time * rate_hz).floor
      @walk[idx % @walk.length]
    end

    def step_at(time)
      seq = Array(values)
      return 0.0 if seq.empty?

      seq[(time * rate_hz).floor % seq.length].to_f.clamp(-1.0, 1.0)
    end
  end

  # ------------------------------------------------------ envelope follower
  #
  # A modulation source that is a real audio file's loudness over time.
  #
  # The engine already builds this shape and throws it away: render_dilla taps
  # the kit three ways and lowpasses one to 120 Hz as a sidechain KEY, which is
  # an envelope follower whose only permitted destination is a compressor. This
  # makes the same signal available to anything -- so a filter can open on the
  # kick, a pad can brighten with the bass, the vinyl can duck under the snare.
  #
  # Measured from ffmpeg's ebur128 momentary loudness rather than a peak meter:
  # 400 ms is what "how loud is it right now" means to a listener, and a sample
  # meter would track individual transients and make every route stutter.
  #
  # Returned as an :envelope source, so it is interchangeable with an LFO and
  # inherits its interpolation. The follower is a measurement, not a new kind of
  # thing.
  def follow(path, floor: -50.0, ceiling: -8.0)
    return nil unless path && File.file?(path)

    out = ToolRun.capture2e(["ffmpeg", "-hide_banner", "-nostats", "-i", path.to_s,
                             "-af", "ebur128=peak=none", "-f", "null", "-"]).first
    points = out.scan(/t:\s*([\d.]+)\s+.*?M:\s*(-?[\d.inf]+)/).filter_map do |t, m|
      next if m.include?("inf")

      # Normalised to -1..1 across a stated dynamic window. Without a fixed
      # window the same beat would drive a route differently depending on how
      # loud the file happened to be mastered, which is a modulation that
      # depends on the mix rather than on the performance.
      level = m.to_f.clamp(floor, ceiling)
      [t.to_f, (((level - floor) / (ceiling - floor)) * 2.0) - 1.0]
    end
    points.empty? ? nil : points
  end

  # Linear between breakpoints, held at both ends. Same contract as
  # DillaAutomation.volume_expr, which builds the ffmpeg-expression form of this
  # for `volume` -- the two agree deliberately, so moving a gain lane between
  # the expression path and the command path does not change its shape.
  def envelope_at(points, time)
    pts = Array(points).sort_by(&:first)
    return 0.0 if pts.empty?
    return pts.first.last.to_f if time <= pts.first.first
    return pts.last.last.to_f if time >= pts.last.first

    after = pts.index { |(t, _)| t > time }
    t0, v0 = pts[after - 1]
    t1, v1 = pts[after]
    span = (t1 - t0).to_f
    return v0.to_f if span.zero?

    v0.to_f + (((time - t0) / span) * (v1.to_f - v0.to_f))
  end

  # Normalised to -1..1 so a source is interchangeable with an LFO. The raw O-U
  # series is unbounded in principle and merely unlikely to be large; a route
  # that clipped only on an unlucky seed would be the worst kind of bug here.
  def ou_walk(length:, theta:, sigma:, seed:)
    series = TapeHysteresis.ou_series(length, rate: 1.0, theta:, sigma:, seed:)
    peak = series.map(&:abs).max
    return Array.new(length, 0.0) if peak.nil? || peak.zero?

    series.map { |v| (v / peak).clamp(-1.0, 1.0) }
  end

  # ------------------------------------------------------------- parameters
  #
  # What a parameter is, asked of ffmpeg rather than written down here.
  #
  # ledger.rb makes the case for this at length and it applies unchanged: a table
  # of ranges maintained beside the code goes stale against the code, and here
  # it would go stale against a DIFFERENT program -- the ffmpeg on the box, which
  # is not the ffmpeg on mine and is not the ffmpeg on vm23. So the hard limits
  # come from `ffmpeg -h filter=NAME`, parsed out of the AVOption table, on the
  # binary that is about to run.
  #
  # The T flag in the option's flag column is ffmpeg's own statement that the
  # option can be set at runtime. A route to an option without it is refused
  # rather than emitted, because ffmpeg accepts such a command silently and
  # does nothing with it -- which is a modulation that measures as a flat line
  # and reports as a success.
  Param = Struct.new(:filter, :name, :min, :max, :type, :runtime, keyword_init: true) do
    def runtime? = !!runtime
    def span = max - min
  end

  # A parameter's hard limits are not its useful ones. lowpass frequency runs to
  # INT_MAX and is musical over maybe eight octaves; acompressor ratio goes to
  # 20 and is a different effect above about 8. A route with no explicit range
  # gets these, and a caller that knows better passes its own.
  #
  # Ranges only. Nothing here sets a value, and nothing here is a default for a
  # render -- these bound a movement the operator has already asked for.
  MUSICAL = {
    %w[lowpass frequency] => [60.0, 18_000.0, :log],
    %w[highpass frequency] => [20.0, 4_000.0, :log],
    %w[equalizer frequency] => [40.0, 16_000.0, :log],
    %w[equalizer gain] => [-12.0, 12.0, :linear],
    %w[bass gain] => [-12.0, 12.0, :linear],
    %w[treble gain] => [-12.0, 12.0, :linear],
    %w[acompressor threshold] => [0.01, 1.0, :log],
    %w[acompressor ratio] => [1.5, 8.0, :linear],
    %w[acompressor makeup] => [1.0, 4.0, :linear],
    %w[acrusher bits] => [4.0, 16.0, :linear],
    %w[acrusher mix] => [0.0, 1.0, :linear],
    %w[aexciter amount] => [0.0, 6.0, :linear],
    %w[aexciter blend] => [-10.0, 10.0, :linear],
    %w[afreqshift shift] => [-400.0, 400.0, :linear],
    %w[aphaseshift shift] => [-1.0, 1.0, :linear],
    %w[stereotools balance_out] => [-0.8, 0.8, :linear],
    %w[stereotools slev] => [0.0, 2.0, :linear],
    %w[stereotools mlev] => [0.0, 2.0, :linear],
    %w[asubboost boost] => [1.0, 8.0, :linear],
    %w[asubboost wet] => [0.0, 1.0, :linear],
    %w[volume volume] => [0.0, 2.0, :linear],
    %w[atempo tempo] => [0.85, 1.15, :linear],
    %w[asoftclip threshold] => [0.1, 1.0, :linear],
  }.freeze

  FLAG_COLUMN = /^\s{3}(\S+)\s+<(\S+)>\s+([.A-Z]{11})\s+(.*)$/
  RANGE_IN_HELP = /\(from (-?[\d.e+]+|INT_MIN|-?FLT_MAX) to ([\d.e+]+|INT_MAX|FLT_MAX)\)/

  # Memoised per filter, per process. One probe is ~30 ms and only filters a
  # matrix actually targets are ever probed.
  def params_for(filter)
    @params ||= {}
    @params[filter.to_s] ||= probe_params(filter.to_s)
  end

  def probe_params(filter)
    help = begin
      ToolRun.capture2e(["ffmpeg", "-hide_banner", "-h", "filter=#{filter}"]).first
    rescue StandardError
      ""
    end
    found = {}
    help.each_line do |line|
      m = FLAG_COLUMN.match(line) or next
      name, type, flags, tail = m.captures
      lo, hi = RANGE_IN_HELP.match(tail)&.captures
      found[name] = Param.new(filter:, name:, type: type.to_sym, runtime: flags.include?("T"),
                              min: numeric(lo, -1.0e9), max: numeric(hi, 1.0e9))
    end
    found
  end

  def numeric(text, fallback)
    return fallback if text.nil?
    return 1.0e9 if text.include?("MAX")
    return -1.0e9 if text.include?("MIN")

    Float(text)
  rescue ArgumentError
    fallback
  end

  # ---------------------------------------------------------------- routes
  #
  # mode, and the distinction is the single most useful thing Live's device
  # model has to teach here.
  #
  #   :modulate  the parameter stays the operator's. base is what they set; the
  #              source adds a relative offset around it. Turning the knob still
  #              works while the modulation runs, because the knob is the centre
  #              the modulation moves around.
  #   :remote    the source IS the parameter. base is ignored and the value
  #              sweeps the full declared range.
  #
  # Every existing "moving" thing in this engine is effectively :remote -- the
  # value is computed and the operator's number is gone. :modulate is what makes
  # a modulated render still tunable, and it is the default for that reason.
  Route = Struct.new(:source, :instance, :filter, :param, :base, :depth,
                     :mode, :polarity, :min, :max, :scale, keyword_init: true) do
    def initialize(*)
      super
      self.mode = (mode || :modulate).to_sym
      self.polarity = (polarity || :bipolar).to_sym
      # -1..1, not 0..1. A negative depth is an ATTENUVERTER: the same source,
      # inverted, so one destination rises while another falls.
      #
      # Clamping this to zero made every fan-out a chorus -- every parameter
      # moving the same way at the same moment, which is one modulation applied N
      # times. One inverted route is the difference between that and counterpoint,
      # and it is the single cheapest thing a modular patch does that this engine
      # could not say. A filter opening as a gain falls is a crossfade; both
      # opening together is louder.
      self.depth = (depth || 1.0).to_f.clamp(-1.0, 1.0)
    end

    # -1..1 from the source becomes a number in the parameter's units.
    #
    # Log-scaled parameters move in octaves, not in hertz. A cutoff modulated
    # +-2000 Hz around 400 is a different effect from the same modulation around
    # 8000 -- the first is drastic and the second inaudible -- and the ear hears
    # cutoff geometrically. So depth on a log parameter is a factor and the
    # movement is symmetric to the ear rather than to the number.
    def value_at(time)
      raw = source.value_at(time)
      raw = (raw + 1.0) / 2.0 if polarity == :unipolar

      if mode == :remote
        pos = polarity == :unipolar ? raw : (raw + 1.0) / 2.0
        return from_position(pos)
      end

      if scale == :log
        octaves = Math.log2((max / min).clamp(1.0001, Float::INFINITY))
        (base * (2.0**(raw * depth * octaves * 0.5))).clamp(min, max)
      else
        (base + (raw * depth * (max - min) * 0.5)).clamp(min, max)
      end
    end

    def from_position(pos)
      pos = pos.clamp(0.0, 1.0)
      scale == :log ? min * ((max / min)**pos) : min + (pos * (max - min))
    end
  end

  # ---------------------------------------------------------------- matrix
  #
  # The whole thing: sources, routes, and the two artefacts a render needs --
  # the command file, and the `asendcmd` clause that reads it.
  class Matrix
    attr_reader :sources, :routes

    def initialize(rate_hz: DEFAULT_RATE_HZ)
      @rate_hz = rate_hz.to_f
      @sources = {}
      @routes = []
    end

    def source(id, **opts)
      id = id.to_sym
      raise ArgumentError, "duplicate source #{id}" if @sources.key?(id)

      @sources[id] = Source.new(id:, **opts)
      self
    end

    # rate: accepts a musical division as well as hertz. `lfo(:x, rate: "1/8T",
    # bpm: 88)` is a triplet-eighth cycle; `rate_hz:` still takes a number.
    def synced_lfo(id, rate:, bpm:, family: :curved, morph: 0.33, phase: 0.0)
      lfo(id, rate_hz: DillaModulation.sync_hz(rate, bpm), family:, morph:, phase:)
    end

    def lfo(id, rate_hz:, family: :curved, morph: 0.33, phase: 0.0)
      source(id, kind: :lfo, rate_hz:, family:, morph:, phase:)
    end

# One source, several destinations -- Ableton's LFO maps eight.
#
# The matrix has always been able to hold thirty-two routes from one source;
# what it could not do was say so in one call, so every fan-out was four
# near-identical route lines that had to be kept in step by hand. Each
# destination keeps its own depth, because a fan-out where everything moves
# by the same amount is one modulation applied four times rather than four
# parameters moving together.
#
# targets: [{ instance:, filter:, param:, depth:, base:, mode: }, ...]
def fan(source_id, targets)
  targets.each do |t|
    route(source_id, **{ depth: 1.0 }.merge(t))
  end
  self
end

    def envelope(id, points) = source(id, kind: :envelope, points:)
    def random(id, rate_hz: 2.0, theta: 0.55, sigma: 0.9, seed: 7)
      source(id, kind: :random, rate_hz:, theta:, sigma:, seed:)
    end

    def steps(id, values, rate_hz: 2.0) = source(id, kind: :steps, values:, rate_hz:)

    # instance: the name this filter carries in the graph, WITHOUT the class --
    # `route(:lfo1, instance: "warp", filter: "lowpass", param: "frequency")`
    # modulates the filter written as `lowpass@warp`. The two spellings are
    # produced from the same pair of strings, by #instance_name and by
    # #command_lines, so they cannot drift apart.
    def route(source_id, instance:, filter:, param:, base: nil, depth: 1.0,
              mode: :modulate, polarity: :bipolar, min: nil, max: nil, scale: nil)
      src = @sources.fetch(source_id.to_sym) { raise ArgumentError, "no source #{source_id}" }
      raise ArgumentError, "matrix is full at #{MAX_ROUTES} routes" if @routes.length >= MAX_ROUTES

      spec = DillaModulation.params_for(filter)[param.to_s]
      raise ArgumentError, "#{filter} has no parameter #{param}" if spec.nil?

      # ffmpeg accepts a command for a non-T option and does nothing. A route
      # that silently does nothing is worse than one that will not build.
      unless spec.runtime?
        raise ArgumentError,
              "#{filter}.#{param} is not runtime-settable in this ffmpeg " \
              "(no T flag) — it can be set once in the graph but not modulated"
      end

      musical = MUSICAL[[filter.to_s, param.to_s]]
      lo = min || musical&.first || spec.min
      hi = max || musical&.[](1) || spec.max
      @routes << Route.new(source: src, instance: instance.to_s, filter: filter.to_s,
                           param: param.to_s, base: (base || ((lo + hi) / 2.0)).to_f,
                           depth:, mode:, polarity:,
                           min: lo.to_f.clamp(spec.min, spec.max),
                           max: hi.to_f.clamp(spec.min, spec.max),
                           scale: (scale || musical&.[](2) || :linear).to_sym)
      self
    end

    def empty? = @routes.empty?

    # The name a routed filter must carry in the filtergraph. Written as
    # `lowpass@warp=f=400` -- the class, an @, and the instance.
    def instance_name(route) = "#{route.filter}@#{route.instance}"

    # Every route's own initial value, so the graph can be built with the filter
    # already sitting where the modulation is about to move it from. Without
    # this the first command lands a frame or two in and the parameter jumps.
    def initial(route) = format_value(route, route.value_at(0.0))

    # The command file.
    #
    # One line per route per step, deduplicated per route: a parameter told to
    # become the number it already is costs a command and changes nothing, and
    # a slow LFO on a coarse parameter repeats for hundreds of steps at a time.
    # On a 240 s render with six routes that dropped 69k lines to about 21k.
    def command_lines(duration:)
      steps = (duration.to_f * @rate_hz).ceil
      last = {}
      lines = []
      (0..steps).each do |i|
        t = i / @rate_hz
        @routes.each_with_index do |route, r|
          value = format_value(route, route.value_at(t))
          next if last[r] == value

          last[r] = value
          lines << "#{format('%.4f', t)} [enter] #{instance_name(route)} #{route.param} #{value};"
        end
      end
      lines
    end

    # ffmpeg parses these as floats; six figures is past any parameter's
    # audible resolution and keeps the file from doubling in size for nothing.
    def format_value(route, value)
      route.scale == :log || value.abs >= 100 ? format("%.2f", value) : format("%.5f", value)
    end

    def write_commands(path, duration:)
      body = command_lines(duration:).join("\n")
      File.write(path, "#{body}\n")
      path
    end

    # The clause that reads the file. Goes FIRST in the chain it belongs to:
    # commands travel with the frames, so a filter placed before asendcmd is a
    # filter whose commands arrive after it has already run.
    #
    # The path is escaped because ffmpeg's filter parser splits on : and , and a
    # scratch directory containing either turns one clause into three.
    def send_clause(path) = "asendcmd=f=#{DillaModulation.escape(path)}"

    # What this matrix is doing, in one line per route, for the manifest and for
    # anyone reading a dmesg wondering why the filter is moving.
    def describe
      @routes.map do |r|
        "#{r.source.id}(#{r.source.kind}#{r.source.kind == :lfo ? " #{r.source.family}/#{r.source.morph.round(2)}@#{r.source.rate_hz.round(2)}Hz" : ''})" \
          " -> #{instance_name(r)}.#{r.param} #{r.mode} depth #{r.depth.round(2)} " \
          "[#{r.min.round(2)}..#{r.max.round(2)}#{r.scale == :log ? ' log' : ''}]"
      end
    end

    def to_h
      { rate_hz: @rate_hz, routes: describe }
    end
  end

  # ffmpeg's filter-argument parser treats : as a separator and \ as an escape,
  # and a Windows-style or space-bearing path has broken graphs here before.
  def escape(path) = path.to_s.gsub("\\", "\\\\\\\\").gsub(":", "\\:").gsub(",", "\\,").gsub("'", "\\\\'")

  # ------------------------------------------------------------------ sugar
  #
  # The common case, as one call: build a matrix, write its file, hand back the
  # clause and the named filters to put after it.
  #
  # Returns nil when the matrix is empty, so a caller can splat the result into
  # a chain without testing for it first.
  def prefix_for(matrix, path:, duration:)
    return nil if matrix.nil? || matrix.empty?

    matrix.write_commands(path, duration:)
    matrix.send_clause(path)
  end
end

# ---------------------------------------------------------- volume expressions
#
# The expression form of the same idea, absorbed from automation_lane.rb.
#
# It was a 21-code-line file, under FILE_SPRAWL's own "absorb files smaller than
# 25 lines into their closest owner" threshold, and its closest owner is this
# one: its header described the wall this module climbs, and this module's
# header cites it back. Two files for one subject, one of them too small to
# stand on its own.
#
# Both forms stay, because they are not interchangeable. `volume` takes an
# EXPRESSION re-evaluated per frame, which is exact and costs no command file;
# everything else needs asendcmd. Kept under its original module name so
# listen.rb and render_analog.rb are untouched by the move.
# Generic "any parameter can vary over time" helper — the ffmpeg-expression
# equivalent of a DAW automation lane. Several places in dilla.rb hand-build
# a one-off `if(lt(t,X),A,B)':eval=frame` volume expression (radio_club_morph
# being the clearest example); this replaces the ad-hoc string-building with
# one function so a third breakpoint, or a new automated parameter, is a data
# change instead of a new hand-rolled expression.
#
# Only proven against ffmpeg's `volume` filter (`eval=frame` + `t` variable).
# `lowpass`/`highpass` do NOT accept this syntax (confirmed empirically) —
# automating those needs `asendcmd` with a timed command file instead, which
# is a different, heavier mechanism not implemented here.
module DillaAutomation
  module_function

  # points: [[time_sec, value], ...] sorted ascending by time. Value before
  # the first point's time is the first point's value; after the last
  # point's time, the last point's value. Builds a right-nested if-ladder.
  def volume_expr(points)
    raise ArgumentError, "need at least one point" if points.empty?
    return points.first.last.to_s if points.length == 1

    sorted = points.sort_by(&:first)
    ladder = sorted.last.last.to_s
    (sorted.length - 1).downto(1) do |i|
      threshold_time = sorted[i].first
      value_before = sorted[i - 1].last
      ladder = "if(lt(t,#{threshold_time}),#{value_before},#{ladder})"
    end
    ladder
  end

  def volume_filter(points)
    "volume='#{volume_expr(points)}':eval=frame"
  end

  # The "analog pad" character effect (lowpass + phaser) was hand-duplicated
  # across three render-mode pad-bus chains with slightly drifted numbers —
  # this is the shared definition; call sites keep their own tuned params
  # (real per-mode differences, not drift) but the string shape lives once.
  def pad_character_filter(cutoff_hz:, phaser_speed: 0.11, phaser_decay: 0.4)
    "lowpass=f=#{cutoff_hz},aphaser=speed=#{phaser_speed}:decay=#{phaser_decay}"
  end
end

# Reopened so the patch bay is DillaModulation::PatchBay rather than a
# top-level constant. Appending to a file puts the text after the module's end;
# the bay refers to Matrix, SOURCES and DEFAULT_RATE_HZ by their bare names, so
# it has to be lexically inside.
module DillaModulation
# ---------------------------------------------------------------- patch bay
#
# Sources and destinations as data, so a patch is a table rather than code.
#
# Everything above can already build any patch; what it could not do was let
# anything OTHER than a programmer build one. A route needs a filter name, a
# parameter name, a base, a range and a scale, and getting any of them wrong is
# either an exception or -- worse -- a route that ffmpeg accepts and ignores.
# That is a fine interface for a caller and a hopeless one for a rotation, a
# macro, or a random patcher.
#
# So the bay names a small set of things worth modulating, in musical terms, and
# resolves each to the filter and parameter underneath. `cutoff` rather than
# `lowpass.frequency`; `bite` rather than `acrusher.bits`. Two consequences that
# matter more than the convenience: a patch can be written by something that
# knows nothing about ffmpeg, and every destination here is one that has been
# checked to be runtime-settable, so a patch cannot silently do nothing.
module PatchBay
  module_function

  # The destinations, in the order a patch is most likely to want them.
  #
  # Each is a filter, a parameter, and the base value a route centres on when the
  # caller does not name one. The ranges come from MUSICAL above -- this table
  # deliberately does not restate them, because two tables of ranges is the
  # defect ledger.rb was written to stop.
  DESTINATIONS = {
    cutoff: { filter: "lowpass", param: "frequency", base: 3000.0 },
    rumble: { filter: "highpass", param: "frequency", base: 120.0 },
    tone: { filter: "equalizer", param: "gain", base: 0.0 },
    bite: { filter: "acrusher", param: "bits", base: 12.0 },
    crush: { filter: "acrusher", param: "mix", base: 0.3 },
    width: { filter: "stereotools", param: "balance_out", base: 0.0 },
    squeeze: { filter: "acompressor", param: "threshold", base: 0.2 },
    push: { filter: "acompressor", param: "ratio", base: 3.0 },
    air: { filter: "aexciter", param: "amount", base: 1.5 },
    weight: { filter: "asubboost", param: "boost", base: 3.0 },
    strange: { filter: "afreqshift", param: "shift", base: 0.0 },
  }.freeze

  # The sources, as recipes rather than instances, so a patch can ask for "a slow
  # LFO" without deciding its rate.
  #
  # Rates are musical divisions, resolved against the render's tempo -- a random
  # patch in hertz would drift against the track, which is the one way to make a
  # generated patch sound accidental rather than deliberate.
  SOURCES = {
    slow: { kind: :lfo, rate: "4bar", family: :curved, morph: 0.33 },
    breathing: { kind: :lfo, rate: "2bar", family: :curved, morph: 0.66 },
    pulse: { kind: :lfo, rate: "1/4", family: :straight, morph: 0.25 },
    stutter: { kind: :lfo, rate: "1/8", family: :stepped, morph: 0.33 },
    stepping: { kind: :lfo, rate: "1/4", family: :stepped, morph: 0.0 },
    wander: { kind: :random, rate_hz: 0.6 },
  }.freeze

  def source_names = SOURCES.keys
  def destination_names = DESTINATIONS.keys

  # Build a matrix from a patch written as { source => [destination, ...] } or
  # { source => { destination => depth } }. Unknown names raise rather than being
  # skipped: a patch with a typo in it should not half-apply.
  def build(patch, bpm:, rate_hz: DEFAULT_RATE_HZ)
    matrix = Matrix.new(rate_hz:)
    patch.each do |source_name, targets|
      spec = SOURCES.fetch(source_name.to_sym) do
        raise ArgumentError, "no source #{source_name} — #{source_names.join(', ')}"
      end
      add_source(matrix, source_name, spec, bpm)
      pairs = targets.is_a?(Hash) ? targets : targets.to_h { |t| [t, 1.0] }
      pairs.each do |dest_name, depth|
        dest = DESTINATIONS.fetch(dest_name.to_sym) do
          raise ArgumentError, "no destination #{dest_name} — #{destination_names.join(', ')}"
        end
        matrix.route(source_name, instance: "#{source_name}_#{dest_name}",
                                  filter: dest[:filter], param: dest[:param],
                                  base: dest[:base], depth:)
      end
    end
    matrix
  end

  def add_source(matrix, name, spec, bpm)
    return matrix.random(name, rate_hz: spec[:rate_hz]) if spec[:kind] == :random

    matrix.synced_lfo(name, rate: spec[:rate], bpm:,
                            family: spec[:family], morph: spec[:morph])
  end

  # A random patch that is valid by construction and musical by restraint.
  #
  # P_4L's most-used control is the one that patches itself, and the reason it is
  # used is that its output is worth listening to more often than not. A uniform
  # draw over every source and destination at full depth is not -- it produces a
  # patch where everything moves at once, which sounds like a fault rather than
  # like a decision.
  #
  # Three restraints, and each is the difference between a generator and a toy:
  #
  #   ONE source per destination. Two LFOs on one cutoff is not richer, it is
  #   two filters fighting, and the result is neither of them.
  #
  #   Depths biased low. Drawn from a squared uniform, so most routes are subtle
  #   and the occasional one is not. A patch of six routes at full depth is six
  #   things shouting.
  #
  #   At least one route inverted, when there is more than one route. That is the
  #   attenuverter earning its place: without a negative depth every destination
  #   rises together and the patch is one gesture wearing several hats.
  def random(bpm:, routes: 4, seed: 4242, rate_hz: DEFAULT_RATE_HZ)
    rng = Random.new(seed)
    dests = DESTINATIONS.keys.shuffle(random: rng).first(routes.clamp(1, DESTINATIONS.length))
    sources = SOURCES.keys.shuffle(random: rng)
    patch = Hash.new { |h, k| h[k] = {} }
    dests.each_with_index do |dest, i|
      source = sources[i % sources.length]
      depth = (rng.rand**2).clamp(0.08, 1.0).round(3)
      # The inversion: guaranteed on the second route so a two-route patch has
      # one, rather than left to a coin toss that fails half the time.
      depth = -depth if i == 1 || (i > 1 && rng.rand < 0.3)
      patch[source][dest] = depth
    end
    [build(patch, bpm:, rate_hz:), patch]
  end
end
end

# A console channel strip, applied per channel rather than across the mix.
#
# The engine already has analog processing -- sonitex tape filters, an analog
# emulation chain, bus_analog_filter, Jiles-Atherton hysteresis. All of it runs
# on the master or on a bus, which is the one place a real console does NOT put
# its character. On a desk every channel passes its own preamp and its own
# transformer first, and the sound people mean by "console" is the SUM of thirty
# of those, each slightly different from the next because no two are built to
# the same tolerance. One instance on the master is a different effect: it is
# the same curve applied to everything at once, after the summing that was
# supposed to accumulate the differences.
#
# Two things follow, and they are the whole design:
#
# 1. EVEN harmonics, not odd. A symmetric curve -- plain tanh, asoftclip, any
#    odd-symmetric shaper -- can only produce odd harmonics: 3rd, 5th, 7th. The
#    3rd is a twelfth, musically dissonant against the fundamental, and it is
#    what makes cheap saturation read as harsh or edgy. The 2nd harmonic is an
#    OCTAVE, consonant by definition, and it is what "warm" and "soothing"
#    actually describe. Getting it requires an ASYMMETRIC curve, because a
#    symmetric one cancels every even term exactly. Transformers and tubes are
#    asymmetric; that is why they sound the way they do and why a symmetric
#    digital clipper never gets there however it is tuned.
#
# 2. Per-instance variation. Each strip draws its own drive, bias, headroom and
#    HF corner from a seeded RNG, so channels differ from one another the way
#    real ones do. Seeded rather than random: a console whose character changes
#    every render is not a character, and it also makes any A/B meaningless.
#
# The sub is deliberately excluded from the saturation. Harmonics generated from
# a 50 Hz fundamental land at 100 and 150 Hz, directly in the range that has
# repeatedly been this mix's problem, and they arrive as ADDED energy the
# metering does not attribute to the kick. Saturating only above the crossover
# is why this can be pushed for warmth without the low end thickening.
module ConsoleStrip
  module_function

  # Asymmetric transfer curve. The bias is the entire reason this generates even
  # harmonics: it moves the signal off the symmetric point of the curve, so the
  # positive and negative halves are compressed by different amounts. The DC the
  # offset introduces is subtracted back out -- tanh(drive*bias) is exactly the
  # curve's output at silence, and leaving it in would put a step in the signal.
  def shape(x, drive, bias)
    Math.tanh(drive * (x + bias)) - Math.tanh(drive * bias)
  end

  # One-pole coefficient for a given corner frequency.
  def pole(hz, rate)
    return 1.0 if hz >= rate / 2.0

    c = 1.0 - Math.exp(-2.0 * Math::PI * hz / rate)
    c.clamp(0.0, 1.0)
  end

  # Split at the crossover, saturate only the upper band, recombine.
  #
  # Complementary first-order: the low band is a one-pole lowpass and the high
  # band is whatever is left (x - low), so the two sum back to flat by
  # construction. A pair of independent filters would not -- they would sum with
  # a dip or a bump at the crossover, and the strip would colour the response
  # before any saturation happened.
  def saturate_band(samples, rate:, xover_hz: 120.0, drive: 1.6, bias: 0.08, hf_hz: 12_000.0)
    a = pole(xover_hz, rate)
    h = pole(hf_hz, rate)
    low = 0.0
    hf = 0.0
    norm = shape(1.0, drive, bias).abs
    norm = 1.0 if norm < 1e-9
    samples.map do |x|
      low += a * (x - low)
      high = x - low
      # Transformer HF loss: real iron does not pass the top octave intact, and
      # the gentle rolloff is a large part of why the result reads as soothing
      # rather than merely distorted.
      hf += h * (high - hf)
      low + (shape(hf, drive, bias) / norm)
    end
  end

  # Gentle level-dependent gain, the strip's own compressor.
  #
  # A soft knee and a low ratio: this exists to take the edge off transients on
  # the way in, not to control dynamics. Anything heavier belongs on the bus,
  # and stacking a real compressor on every channel is how a mix loses the
  # loudness range this engine has repeatedly had to claw back.
  def soften(samples, rate:, threshold: 0.35, ratio: 1.6, attack_ms: 12.0, release_ms: 160.0)
    at = Math.exp(-1.0 / ((attack_ms / 1000.0) * rate))
    rt = Math.exp(-1.0 / ((release_ms / 1000.0) * rate))
    env = 0.0
    samples.map do |x|
      level = x.abs
      env = level > env ? (at * env) + ((1.0 - at) * level) : (rt * env) + ((1.0 - rt) * level)
      gain =
        if env <= threshold
          1.0
        else
          over = env - threshold
          (threshold + (over / ratio)) / env
        end
      x * gain
    end
  end

  # Per-instance character. Every channel on a desk is built to the same design
  # and none of them measures the same; these are the tolerances.
  def instance(seed)
    rng = Random.new(seed)
    {
      drive: 1.15 + (rng.rand * 0.45),
      # Bias sets the even-to-odd ratio, and the first values here were chosen by
      # eye at 0.05-0.11, which measurement then showed to be the harsh zone
      # rather than the warm one. Sweeping a 220 Hz sine, 2nd-minus-3rd is:
      #
      #   bias 0.05   -3.5 dB   3rd DOMINATES -- the edge this exists to avoid
      #   bias 0.10   +2.7 dB   marginal
      #   bias 0.18   +8.6 dB   2nd clearly leads
      #   bias 0.28  +14.4 dB   strongly even
      #   bias 0.40  +22.0 dB   even-dominant but heavy
      #
      # So the original defaults produced almost exactly the opposite of the
      # stated intent: at 0.05 the curve is asymmetric enough to be measured and
      # not asymmetric enough to matter, leaving the odd harmonics on top. 0.16
      # to 0.30 is the range where the octave actually leads, and it is the only
      # part of this module that could not have been reasoned to without the
      # measurement.
      #
      # Sign varies per instance: transformers are not all asymmetric in the
      # same direction, and alternating it means the even harmonics of different
      # channels do not all stack in phase into a single audible octave-up.
      bias: (0.16 + (rng.rand * 0.14)) * (rng.rand < 0.5 ? -1.0 : 1.0),
      xover_hz: 105.0 + (rng.rand * 35.0),
      hf_hz: 9_000.0 + (rng.rand * 6_000.0),
      threshold: 0.32 + (rng.rand * 0.10),
    }
  end

  # One channel through one strip.
  def process(samples, rate:, seed: 1, amount: 1.0)
    return samples if amount <= 0.0

    p = instance(seed)
    wet = saturate_band(samples, rate:,
                        xover_hz: p[:xover_hz], drive: p[:drive],
                        bias: p[:bias], hf_hz: p[:hf_hz])
    wet = soften(wet, rate:, threshold: p[:threshold])
    return wet if amount >= 1.0

    samples.each_with_index.map { |x, i| (x * (1.0 - amount)) + (wet[i] * amount) }
  end

  # Harmonic content of a processed signal, for verifying the thing actually
  # does what the comments claim. Goertzel at the fundamental and its multiples,
  # returned in dB relative to the fundamental.
  #
  # This exists because a previous saturation stage in this engine was committed
  # with a description of the harmonics it added and measured, later, as doing
  # nothing at all. A saturator is trivially testable -- feed it a sine, look at
  # what appears above it -- and anything claiming to add harmonics should carry
  # the measurement rather than the adjective.
  def harmonics(samples, rate:, fundamental:, count: 5)
    mags = (1..count).map do |n|
      f = fundamental * n
      next 0.0 if f >= rate / 2.0

      w = 2.0 * Math::PI * f / rate
      coeff = 2.0 * Math.cos(w)
      s1 = 0.0
      s2 = 0.0
      samples.each do |x|
        s0 = x + (coeff * s1) - s2
        s2 = s1
        s1 = s0
      end
      Math.sqrt((s1 * s1) + (s2 * s2) - (coeff * s1 * s2)) / samples.length
    end
    base = mags[0]
    return mags.map { 0.0 } if base <= 1e-12

    mags.map { |m| m <= 1e-12 ? -120.0 : (20.0 * Math.log10(m / base)).round(2) }
  end
end
