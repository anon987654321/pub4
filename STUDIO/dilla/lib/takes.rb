# frozen_string_literal: true

# Source-preserved reference performances, kept together as one registry.
module DillaTakes
  # Frozen reference takes, kept together as one registry rather than one player
  # file per performance. Musical constants and sample generation stay pinned;
  # diagnostic logs remain beside dilla.rb after the registry moves into lib/.
  # The suite extracts each module to a scratch script and checks its samples
  # against the live engine. `ruby dilla.rb live take <name>` plays one as taken.

  module Liveset161326bb356a
    # takes/liveset_161326bb356a.rb, frozen as heard (sha256 683a88ef3edcf8fc3d2955c27af1443df7dd8ca14221c868216cb3fd337cfff3).

    # MASTER's main sound, improvising live and endless: soul-jazz harmony chosen
    # chord by chord, each voiced nearest the last, the key moving on its own.
    # The chords play only Moog presets on dilla's ladder, morphing over four
    # chords, whole and uncut, through a Juno-60 chorus, breathing on every beat
    # the way a sidechain would. Over them quiet Moog arpeggios, each note on its
    # own chance and its own point on a glide through four lead patches. Under
    # them the rolling Moog bass, an industrial grid at 128 BPM and the DFAM,
    # always changing; air on top from an exciter. Now and then a hand on the
    # record: a tape stop, a spinback, a dub throw. Kicks sit off (KICKS_ON),
    # and the turntablist's crossfader waits behind CUTS_ON.

    RATE = 32_000
    BLOCK = 1_024
    S = AnalogSynth
    P = S::PATCHES.dup

    def self.hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

    # Fm9, Bbm9, Eb13, Abmaj9, Dbmaj7#11, C7alt: soul-jazz, Dilla territory.
    CHORDS = [
      [41, [56, 60, 63, 67]], [46, [56, 61, 65, 68]], [39, [55, 60, 61, 65]],
      [44, [55, 60, 63, 70]], [37, [60, 65, 67, 72]], [36, [58, 61, 64, 68]],
    ]
    SNAP = { amp: S::Envelope.new(attack: 0.004, decay: 0.3, sustain: 0.35, release: 0.18),
             filter_env: S::Envelope.new(attack: 0.002, decay: 0.22, sustain: 0.2, release: 0.15) }.freeze
    PROPHET_LEADS = {
      prophet_five_lead: P[:prophet_five].merge(SNAP),
      prophet_pad_lead: P[:prophet_pad].merge(SNAP),
      prophet_poly: P[:poly_lead].merge(SNAP),
      prophet_bright: P[:prophet_five].merge(SNAP).merge(cutoff: 900.0, resonance: 0.42),
    }.freeze
    P.merge!(PROPHET_LEADS)
    # The Rhodes leads: dilla's two electric pianos, and each a shade brighter
    # and darker.
    MOOG_LEADS = {
      # The Minimoog lead: two saws a hair apart over a square an octave down,
      # the ladder half open and ringing.
      minimoog_lead: { waves: %i[saw saw square], detune: [0.0, 6.0, 0.0], octaves: [0, 0, -1], cutoff: 1300.0, env_amount: 2200.0, resonance: 0.48, drive: 1.15 },
      # The Voyager pluck: a triangle and a square, the envelope snapping the
      # filter shut, a glassy knock at the top of each note.
      voyager_pluck: { waves: %i[triangle square triangle], detune: [0.0, -4.0, 1200.0], octaves: [0, 0, 0], cutoff: 700.0, env_amount: 3200.0, resonance: 0.58, drive: 1.0 },
      # The Sub 37 sync lead: a bright saw and a square a fifth up, a little grit.
      sub37_lead: { waves: %i[saw square saw], detune: [0.0, 702.0, -5.0], octaves: [0, 0, 0], cutoff: 1600.0, env_amount: 1800.0, resonance: 0.4, drive: 1.3 },
      # The Prodigy flute: a lone triangle, the ladder barely open, soft.
      prodigy_flute: { waves: %i[triangle triangle saw], detune: [0.0, 3.0, -3.0], octaves: [0, 1, -1], cutoff: 900.0, env_amount: 1200.0, resonance: 0.3, drive: 0.9 },
    }.transform_values { |p| p.merge(SNAP) }.freeze
    P.merge!(MOOG_LEADS)
    # Moog chord presets, on dilla's ladder: the chords play only these, the
    # patch morphing from one to the next without a seam -- cutoff, resonance,
    # envelope depth, drive and detune all glide; the waves change at halfway.
    MOOG_ENV = { amp: P[:warm_pad][:amp], filter_env: P[:warm_pad][:filter_env] }.freeze
    MOOG_CHORDS = {
      minimoog_pad: { waves: %i[saw square triangle], detune: [0.0, -6.0, 7.0], octaves: [0, 0, -1], cutoff: 620.0, env_amount: 1400.0, resonance: 0.42, drive: 1.1 },
      memorymoog_brass: { waves: %i[saw saw saw], detune: [-9.0, 0.0, 9.0], octaves: [0, 0, 0], cutoff: 760.0, env_amount: 1900.0, resonance: 0.3, drive: 1.2 },
      polymoog_vox: { waves: %i[square square saw], detune: [-4.0, 5.0, 0.0], octaves: [0, 1, 0], cutoff: 900.0, env_amount: 700.0, resonance: 0.24, drive: 0.95 },
      moog_one_strings: { waves: %i[saw saw saw], detune: [-14.0, 0.0, 13.0], octaves: [0, 0, 1], cutoff: 1150.0, env_amount: 800.0, resonance: 0.2, drive: 0.9 },
      sub37_warm: { waves: %i[saw square saw], detune: [0.0, 4.0, -5.0], octaves: [0, -1, 0], cutoff: 480.0, env_amount: 1600.0, resonance: 0.55, drive: 1.3 },
    }.transform_values { |p| p.merge(MOOG_ENV) }.freeze
    # Four chords to travel from one preset to the next, in a fresh order each lap.
    MORPH_CHORDS = 4
    # The leads rotate continuously: every note's patch is where a glide through
    # the Moog leads stands at that moment, one patch every six seconds, so no
    # two notes in a row share a sound and no change is ever a switch.
    LEAD_GLIDE_S = 6.0
    # A fractional read from the chorus line, so the sweep glides rather than steps.
    def self.juno_read(line, pos)
      i = pos.floor
      f = pos - i
      (line[i % line.size] * (1.0 - f)) + (line[(i + 1) % line.size] * f)
    end
    def self.lead_at(order, time)
      pos = time / LEAD_GLIDE_S
      a = MOOG_LEADS.fetch(order[pos.floor % order.size])
      b = MOOG_LEADS.fetch(order[(pos.floor + 1) % order.size])
      x = pos - pos.floor
      mix = ->(k) { a[k] + ((b[k] - a[k]) * x) }
      (x < 0.5 ? a : b).merge(cutoff: mix.(:cutoff), env_amount: mix.(:env_amount), resonance: mix.(:resonance),
                               drive: mix.(:drive), detune: a[:detune].each_index.map { |i| a[:detune][i] + ((b[:detune][i] - a[:detune][i]) * x) })
    end
    def self.moog_morph(order, chord_i)
      pos = chord_i.to_f / MORPH_CHORDS
      a = MOOG_CHORDS.fetch(order[pos.floor % order.size])
      b = MOOG_CHORDS.fetch(order[(pos.floor + 1) % order.size])
      x = pos - pos.floor
      lerp = ->(k) { a[k] + ((b[k] - a[k]) * x) }
      (x < 0.5 ? a : b).merge(cutoff: lerp.(:cutoff), env_amount: lerp.(:env_amount), resonance: lerp.(:resonance),
                               drive: lerp.(:drive), detune: a[:detune].each_index.map { |i| a[:detune][i] + ((b[:detune][i] - a[:detune][i]) * x) })
    end
    PADS = %i[warm_pad poly_strings prophet_five juno_pad prophet_pad vp330_ensemble soft_reed e_piano rhodes_tine glass_bell]
    BASSES = %i[moog_bass acid sub dub_bass]
    QUALITIES = {
      m9: [3, 7, 10, 14], m11: [3, 7, 10, 17], maj9: [4, 7, 11, 14], maj7s11: [4, 7, 11, 18],
      d13: [4, 10, 14, 21], alt: [4, 10, 13, 15], m6_9: [3, 7, 9, 14], sus13: [5, 10, 14, 21],
    }.freeze
    MOVES = {
      [0, :m9] => [[5, :m9], [10, :d13], [8, :maj9], [5, :m11], [3, :maj9]],
      [0, :m11] => [[5, :m9], [8, :maj7s11], [10, :sus13]],
      [5, :m9] => [[10, :d13], [7, :alt], [3, :maj9], [0, :m6_9]],
      [5, :m11] => [[10, :d13], [7, :alt]],
      [10, :d13] => [[3, :maj9], [8, :maj9], [0, :m9]],
      [10, :sus13] => [[10, :d13], [3, :maj9]],
      [3, :maj9] => [[8, :maj9], [5, :m9], [1, :maj7s11]],
      [8, :maj9] => [[1, :maj7s11], [7, :alt], [5, :m9]],
      [8, :maj7s11] => [[7, :alt], [1, :maj7s11]],
      [1, :maj7s11] => [[7, :alt], [0, :m9], [0, :m11]],
      [7, :alt] => [[0, :m9], [0, :m11], [8, :maj9]],
      [0, :m6_9] => [[5, :m9], [10, :d13]],
    }.freeze
    NAMES = %w[C Db D Eb E F Gb G Ab A Bb B].freeze

    def self.voice_lead(pcs, previous)
      pcs.each_with_index.map do |pc, idx|
        centre = previous[idx] || previous.last
        (53..74).select { |m| m % 12 == pc }.min_by { |m| (m - centre).abs }
      end.sort.uniq
    end
    # Industrial techno, ten below the 128 BPM it started at (Attack Magazine:
    # 126-130), at the operator's word. BAR is two bars, eight beats.
    BPM = 118
    BAR = 8 * 60.0 / BPM
    CHORD_LEN = BAR

    Voice = Struct.new(:hz, :spec, :start, :held, :gain, :phases, :ladder, :bass)

    def self.voice(midi, spec, start, held, gain, bass: false)
      rng = Random.new(midi * 7 + (start * 10).to_i)
      Voice.new(hz(midi) * 2.0**(rng.rand(-0.7..0.7) / 1200.0), spec, start, held, gain,
                spec[:waves].map { rng.rand }, S::Ladder.new(rate: RATE), bass)
    end

    # The knobs: cutoff breathes over 23 s, resonance over 31 s, out of phase.
    def self.cutoff_knob(t) = 0.55 + 0.45 * Math.sin(2 * Math::PI * t / 23.0)
    def self.res_knob(t) = 0.5 + 0.5 * Math.sin(2 * Math::PI * t / 31.0 + 1.3)

    # The DFAM, as the Moog is built: an 8-step sequencer, each step its own pitch
    # and velocity, running in sixteenths; VCO 1 a triangle frequency-modulating
    # VCO 2, a square; both with a pitch envelope that falls; noise mixed in; all
    # of it through a ladder low-pass with its own decay, then the VCA's decay.
    # The pattern starts from dilla's DfamEngine and one step mutates every two
    # bars; decay and cutoff drift slowly, like the pads' knobs.
    DFAM_STEP = BAR / 32 # sixteenths
    DFAM_LEVEL = 0.16
    # Accents on the eight-step page: the downbeat and the and-of-two lean in.
    DFAM_SCENES = %i[euclid ratchet broken tribal].freeze
    # Each groove brings its own kick, as [cycle length, steps that hit].
    SCENE_KICKS = { euclid: [16, [0, 6, 10]], ratchet: [12, [0, 7]], broken: [16, [0, 3, 10, 11]], tribal: [12, [0, 5, 8]] }.freeze
    DFAM_RATES = { 1.0 => "16ths", (2.0 / 3) => "triplets", 0.5 => "32nds", 1.5 => "dotted 16ths", 2.0 => "8ths" }.freeze
    # A Euclidean rhythm: k hits spread as evenly as n steps allow.
    def self.euclid(k, n) = (@euclid ||= {})[[k, n]] ||= Array.new(n) { |i| ((i * k) % n) < k }
    # And its own lead rhythm, on sixteen steps.
    SCENE_LEAD = { euclid: euclid(5, 16), ratchet: euclid(6, 16), broken: Array.new(16) { |i| [0, 3, 6, 10, 12].include?(i) }, tribal: euclid(7, 16) }.freeze
    ACCENT = [1.35, 0.8, 1.0, 0.85, 1.25, 0.8, 1.1, 0.9].freeze
    KICK_LEVEL = 0.06
    # Off at the operator's word, and with them the rumble and the pump.
    KICKS_ON = false
    # The crossfader is off at the operator's word: the chords play whole on
    # deck A, the morphing preset, and deck B is not voiced. true brings the
    # turntablist's cuts back.
    CUTS_ON = false
    # The lead plays over every chord, at the operator's word.
    LEAD_ALWAYS = true
    # Muted at the operator's word; true brings the leads back.
    LEADS_ON = true
    # The Juno-60 chorus, after TAL-Chorus-LX, on the chords only: the mono sum
    # through two short delays swept by one slow triangle, the two sides in
    # opposite phase, blended with the dry chord.
    JUNO_LEN = 1_024
    JUNO_CENTRE = 0.0035 * RATE
    JUNO_DEPTH = 0.0017 * RATE
    JUNO_HZ = 0.5
    # The breath, after LFOTool: the chords dip on every beat and swell back,
    # as a sidechain would with the kick gone. Glided so the dip never clicks.
    BREATH_DEPTH = 0.3
    BREATH_RECOVER_S = 0.12
    BREATH_GLIDE = 1.0 - Math.exp(-1.0 / (0.004 * RATE))
    # Turntablism on the pads: a scratch DJ's sharp-curve crossfader, two decks
    # (the two Moog layers) cut hard on the thirty-second grid. Each pattern is
    # 32 steps, one bar: A is deck A open, B deck B, - the fader closed. The
    # fader moves in half a millisecond, so every cut is a cut, not a blend.
    CUTS = {
      transformer: "A-A-A-A-A-A-A-A-A-A-A-A-A-A-A-A-",
      slow_transformer: "AA--AA--AA--AA--BB--BB--BB--BB--",
      crab: "A-A-A-A-AAAAAAAAB-B-B-B-BBBBBBBB",
      chirp: "AAA-----AAA-----BBB-----BBB-----",
      orbit: "A--AA--AA--AA--AB--BB--BB--BB--B",
      flare: "AAAA-AAA-AAAAAAAAAAA-AAA-AAAAAAA",
      ab_chop: "AAAABBBBAAAABBBB--AABB--AABBAB--",
      tear: "AAAAAAAA--------A-A-AAAA--------",
    }.freeze
    # The record under the crossfader: the cut pads write into three seconds of
    # buffer and are read back at a delay d that is zero in plain play, so the
    # deck adds no latency. A hand on the record moves d: the read speed is
    # 1 - d', so a growing d drops the pitch and a shrinking one raises it.
    #   baby      d rises and falls over a sixteenth: the push and pull.
    #   tape_stop the speed falls from 1 to 0 over a beat, the level with it.
    #   spinback  the record thrown backwards at three times speed, fading.
    DECK_LEN = RATE * 3
    # The dub throw: a send, open for the bar's last eighth when it fires, into
    # a dotted-eighth echo that darkens and thins as it repeats.
    DUB_LEN = RATE
    DUB_DELAY = (3 * DFAM_STEP * RATE).round
    DUB_LP = 1.0 - Math.exp(-2 * Math::PI * 1800.0 / RATE)
    DUB_HP = 1.0 - Math.exp(-2 * Math::PI * 220.0 / RATE)
    CUT_GLIDE = 1.0 - Math.exp(-1.0 / (0.005 * RATE))
    # The Crystallizer, after Soundtoys: reversed grains of the lead, pitched up
    # an octave or a fifth, a quarter second late, fed back into themselves.
    # Two readers half a grain apart, Hann-windowed, crossfade into a shimmer.
    CRYS_LEN = RATE * 2
    CRYS_GRAIN = (RATE * 0.16).round
    CRYS_DELAY = (RATE * 0.25).round
    CRYS_FEEDBACK = 0.45
    CRYS_MIX = 0.5
    # The 909's hat: six detuned square waves, high-passed, then crushed to 12
    # bits the way an SP-1200 resample crunches it.
    HAT_HZ = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0].freeze
    HAT_LEVEL = 0.011
    # Rendered once: the squares, noise under them for grit, and the decay.
    hat_table = lambda do |len, decay|
      Array.new((len * RATE).to_i) do |i|
        th = i.to_f / RATE
        sq = HAT_HZ.sum { |f| ((th * f * 7.0) % 1.0) < 0.5 ? 1.0 : -1.0 }
        (sq + (((rand * 2.0) - 1.0) * 3.0)) * Math.exp(-th / decay)
      end.freeze
    end
    HAT_OPEN = hat_table.(0.3, 0.07)
    HAT_CLOSED = hat_table.(0.06, 0.015)
    # The shaker: noise alone, short, high-passed with the hats.
    SHAKER = Array.new((0.08 * RATE).to_i) { |i| ((rand * 2.0) - 1.0) * 2.0 * Math.exp(-i.to_f / RATE / 0.025) }.freeze
    CLAP_LEVEL = 0.08
    # The rumble: the kick sent into a dark reverb (three combs), distorted,
    # low-passed to 150 Hz, mono, and ducked by the kick itself.
    RUMBLE_LEVEL = 0.05
    COMBS = [1123, 1409, 1693].map { |len| Array.new(len, 0.0) }
    RUM_A = 1.0 - Math.exp(-2 * Math::PI * 150.0 / RATE)
    HAT_A = 1.0 - Math.exp(-2 * Math::PI * 7000.0 / RATE)
    DfamHit = Struct.new(:start, :f0, :vel, :ph1, :ph2, :ladder, :pan)
    class DfamKnob
      attr_reader :value
      def initialize(lo, hi, rng, speed:)
        @lo, @hi, @rng, @speed = lo, hi, rng, speed
        @x = 0.5
        @v = 0.0
        @push = nil
      end
      # A gesture: toward `target` (0..1) for `seconds`, then released.
      def lean(target, seconds, now) = @push = [target, now + seconds]
      def step(dt, now)
        @push = nil if @push && now > @push[1]
        pull = @push ? (@push[0] - @x) * 1.5 : (0.5 - @x) * 0.03
        @v = (@v * 0.992) + (@rng.rand(-1.0..1.0) * @speed * dt) + (pull * dt)
        @x = (@x + (@v * dt)).clamp(0.0, 1.0)
        @value = @lo + ((@hi - @lo) * @x)
      end
    end

    knob_rng = Random.new
    DFAM_KNOBS = {
      vcf_decay: DfamKnob.new(0.03, 0.22, knob_rng, speed: 0.08),
      vca_decay: DfamKnob.new(0.06, 0.28, knob_rng, speed: 0.07),
      cutoff: DfamKnob.new(500.0, 4200.0, knob_rng, speed: 0.1),
      resonance: DfamKnob.new(0.2, 0.85, knob_rng, speed: 0.06),
      fm: DfamKnob.new(0.0, 1.1, knob_rng, speed: 0.07),
      noise: DfamKnob.new(0.02, 0.45, knob_rng, speed: 0.05),
      pitch_amount: DfamKnob.new(0.6, 4.0, knob_rng, speed: 0.06),
      pitch_decay: DfamKnob.new(0.015, 0.12, knob_rng, speed: 0.05),
    }.freeze
    def self.sonitex(bits:, lo:, hi:, drive:, mix: 0.5, samples: 1)
      "volume=#{drive},acrusher=bits=#{bits}:mode=log:aa=1:mix=#{mix}:samples=#{samples}," \
        "highpass=f=#{lo},lowpass=f=#{hi},alimiter=limit=0.99"
    end

    # Level-neutral here: five stages at livesets' -7.5 dB each sank the pads 37 dB
    # under the kick. The colour stays; the loss does not.
    def self.vcs(depth:, smear:, db: 0.0)
      phaser_db = -2.6 + (10.9 * (depth - 0.26)) - (0.14 * (smear - 2.1))
      "aphaser=in_gain=0.75:out_gain=0.85:delay=#{smear}:decay=#{depth}:speed=0.5," \
        "aecho=0.9:1:#{smear.round}:0.08,volume=#{(db - phaser_db + 0.65).round(2)}dB"
    end

    MASTER = [
      vcs(depth: 0.34, smear: 2.4), sonitex(bits: 12, lo: 40, hi: 13_000, drive: 1.12),
      vcs(depth: 0.38, smear: 1.7), sonitex(bits: 13, lo: 42, hi: 15_000, drive: 1.04),
      vcs(depth: 0.26, smear: 3.6), sonitex(bits: 11, lo: 42, hi: 12_000, drive: 1.18),
      "aexciter=amount=1.2:drive=5:freq=3500:ceil=16000", "alimiter=limit=0.95"
    ].join(",")
    def self.space_echo(head_ms, decays)
      taps = [1, 2, 3].map { |k| (head_ms * k).round }.join("|")
      "highpass=f=160,aecho=0.9:0.9:#{taps}:#{decays},lowpass=f=3200,chorus=0.9:0.9:25:0.35:0.6:1.8"
    end
    HEAD = BAR / 16 * 1000
    ARP_FX = "anull"
    # Extreme analog tape on the master channel, the whole sum: the head bump near
    # 60 Hz, the drive into tanh that tape saturation is (undone after, so it
    # colours rather than raises), the capstan's wow and flutter worn deep, the top
    # the tape cannot hold, and its hiss.
    def self.tape(drive:, wow:, flutter:, top:, hiss:)
      "equalizer=f=60:t=q:w=1.1:g=4.5,volume=#{drive},asoftclip=type=tanh,volume=#{(1.0 / drive).round(3)}," \
        "vibrato=f=0.42:d=#{wow},vibrato=f=6.8:d=#{flutter},lowpass=f=#{top},highpass=f=28," \
        "aeval=exprs=val(0)+#{hiss}*(2*random(0)-1)|val(1)+#{hiss}*(2*random(1)-1):c=same"
    end
    TAPE = tape(drive: 3.2, wow: 0.22, flutter: 0.07, top: 9_500, hiss: 0.004)
    # Arps on the arps, at the operator's word: the lead is split three ways. One
    # stays dry; one goes up a fifth and comes back an eighth late, the other up
    # an octave a dotted eighth late, so the echoes arpeggiate over the arpeggio.
    # Each pitched copy feeds back through its own echo the way a crystallizer
    # does, and the sum is sharpened with ffmpeg's crystalizer. The pitch shift is
    # asetrate then atempo, a resample and a time-stretch, which grains the copies.
    def self.pitched(ratio, delay_ms, echo_ms, decay)
      "asetrate=#{(RATE * ratio).round},aresample=#{RATE},atempo=#{(1.0 / ratio).round(4)}," \
        "adelay=#{delay_ms}|#{delay_ms},aecho=0.8:0.7:#{echo_ms}:#{decay}"
    end
    EIGHTH = (BAR / 16 * 1000).round
    ARPS_ON_ARPS = "asplit=3[ad][ax][ay];[ax]#{pitched(1.5, EIGHTH, EIGHTH * 2, 0.45)}[af];" \
                   "[ay]#{pitched(2.0, (EIGHTH * 1.5).round, EIGHTH * 3, 0.4)},highpass=f=900[ao];" \
                   "[ad][af][ao]amix=inputs=3:weights=1 0.5 0.35:normalize=0,crystalizer=i=1.5"
    # The leads sit lower in the sum, at the operator's word: 0.9 against the
    # main's 1 where they were 1.5.
    GRAPH = "[0:a]pan=stereo|c0=c0|c1=c1,#{MASTER}[m];[0:a]pan=stereo|c0=c2|c1=c3,#{ARPS_ON_ARPS}[a];[m][a]amix=inputs=2:weights=1 0.9:normalize=0,#{TAPE},alimiter=limit=0.96"

    def self.run(argv = [])
      loops = (argv[0] || 2).to_i

      voices = []
      rng = Random.new
      key = 5 # F minor, where the loved progression sits
      state = [0, :m9]
      voicing = CHORDS.first.last
      chord_i = 0
      moog_order = nil
      recent = []
      next_modulation = 8
      key = rng.rand(12)
      next_chord = 0.0
      log = File.open(File.join(__dir__, "..", "moog_improv.log"), "a").tap { |f| f.sync = true }
      total = Float::INFINITY
      pattern = { pitch: [50, 30, 60, 20, 55, 35, 65, 25], velocity: [80, 60, 90, 50, 85, 65, 95, 55] }
      dfam_rng = Random.new
      dfam_hits = []
      dfam_next = 0.0
      dfam_step = 0
      pattern_b = { pitch: [78, 64, 88, 70, 92], velocity: [55, 0, 70, 45, 60] }
      dfam_scene = nil
      next_scene_at = 0.0
      grid_next = 0.0
      grid_step = 0
      # A new groove, never the kind just played: its kind, its rate, and for a
      # generated one a Euclidean pattern of 2 to n-1 hits over 5 to 16 steps.
      new_scene = lambda do |last|
        kind = (DFAM_SCENES + %i[generated generated]).reject { |k| k == last && k != :generated }.sample(random: dfam_rng)
        rate, rate_name = DFAM_RATES.to_a.sample(random: dfam_rng)
        steps = dfam_rng.rand(5..16)
        hits = dfam_rng.rand(2..(steps - 1))
        label = kind == :generated ? "E(#{hits},#{steps}) in #{rate_name}" : "#{kind} in #{rate_name}"
        { kind:, rate:, label:, hits: euclid(hits, steps).rotate(dfam_rng.rand(steps)),
          pitches: Array.new(dfam_rng.rand(3..8)) { dfam_rng.rand(5..45) } }
      end
      kicks = []
      click_lp = 0.0
      lead_order = nil
      juno = Array.new(JUNO_LEN, 0.0)
      juno_w = 0
      breath = 1.0
      cut_name = :transformer
      cut_bar = -1
      gain_a = 1.0
      gain_b = 0.0
      deck_l = Array.new(DECK_LEN, 0.0)
      deck_r = Array.new(DECK_LEN, 0.0)
      deck_w = 0
      deck_fx = nil # [kind, start]
      last_s32 = -1
      last_deck = "-"
      dub_l = Array.new(DUB_LEN, 0.0)
      dub_r = Array.new(DUB_LEN, 0.0)
      dub_w = 0
      dub_lp_l = dub_lp_r = dub_hp_l = dub_hp_r = 0.0
      dub_send = 0.0
      dub_throw = false
      crys_l = Array.new(CRYS_LEN, 0.0)
      crys_r = Array.new(CRYS_LEN, 0.0)
      crys_w = 0
      crys_p = 0
      crys_pitch = 2.0
      crys_out_l = crys_out_r = 0.0
      hats = []
      claps = []
      hat_lp = clap_lp = clap_hp = 0.0
      comb_i = [0, 0, 0]
      rum_lp1 = rum_lp2 = 0.0
      next_gesture = 8.0

      $stderr.puts "improvising: #{PADS.join(" -> ")} over moog_bass, DFAM on top"
      sox = IO.popen(["sh", "-c", "ffmpeg -loglevel error -f s16le -ar #{RATE} -ac 4 -i - -filter_complex '#{GRAPH}' -f s16le -ar #{RATE} -ac 2 - | sox -q -t raw -r #{RATE} -e signed -b 16 -c 2 - -d"], "wb")
      frame = 0
      frames = Float::INFINITY
      two_pi = 2 * Math::PI
      while frame < frames
        # The next chord, chosen a second before it sounds.
        while next_chord < (frame.to_f / RATE) + 1.0
          degree, quality = state
          voicing = voice_lead(QUALITIES[quality].map { |iv| (key + degree + iv) % 12 }, voicing)
          bass = 36 + ((key + degree) % 12)
          bass += 12 if bass < 36
          name = "#{NAMES[(key + degree) % 12]}#{quality}"
          recent << [(key + degree) % 12, quality]
          recent.shift if recent.size > 4
          options = MOVES.fetch(state).reject { |d, q| recent.include?([(key + d) % 12, q]) }
          options = MOVES.fetch(state) if options.empty?
          state = options.sample(random: rng)
          roll = rng.rand
          if roll < 0.08 # the tritone substitute: a dominant a flat fifth away
            key = (key + 6) % 12
            name += " (tritone sub next)"
          elsif roll < 0.14 # a chromatic side-step, up or down a semitone
            key = (key + [1, 11].sample(random: rng)) % 12
            name += " (side-step next)"
          end
          if chord_i >= next_modulation
            key = (key + [5, 3, 8, 10, 2, 7].sample(random: rng)) % 12
            state = [0, %i[m9 m11 m6_9].sample(random: rng)]
            next_modulation = chord_i + rng.rand(8..16)
            name += " -> #{NAMES[key]} minor"
          end
          moog_order = MOOG_CHORDS.keys.shuffle(random: rng) if (chord_i % (MORPH_CHORDS * MOOG_CHORDS.size)).zero?
          pad = moog_morph(moog_order, chord_i)
          pad_name = "#{moog_order[(chord_i / MORPH_CHORDS) % moog_order.size]} -> #{moog_order[((chord_i / MORPH_CHORDS) + 1) % moog_order.size]} #{(chord_i % MORPH_CHORDS) * 100 / MORPH_CHORDS}%"
          bass_patch = P.fetch(BASSES[(chord_i / 4) % BASSES.size])
          voicing.each { |m| voices << voice(m, pad, next_chord, CHORD_LEN - 0.1, 0.3, bass: :pad) }
          # The second layer, crossfaded against the first on a rhythm: the preset
          # two stops further round the Moog wheel, so the two never sound alike.
          pad_b = MOOG_CHORDS.fetch(moog_order[((chord_i / MORPH_CHORDS) + 2) % moog_order.size])
          voicing.each { |m| voices << voice(m, pad_b, next_chord, CHORD_LEN - 0.1, 0.3, bass: :pad_b) } if CUTS_ON
          # The rolling bass: the root on the three sixteenths after every kick,
          # short and even, the octave up on the last of each beat now and then.
          (CHORD_LEN / (BAR / 8)).round.times do |beat|
            [1, 2, 3].each do |sixteenth|
              up = sixteenth == 3 && rng.rand < 0.25 ? 12 : 0
              voices << voice(bass + up, bass_patch, next_chord + (beat * BAR / 8) + (sixteenth * DFAM_STEP), DFAM_STEP * 0.6, 0.4, bass: true)
            end
          end
          log.puts "#{Time.now.strftime("%H:%M:%S")} #{name} on #{pad_name}, bass #{BASSES[(chord_i / 4) % BASSES.size]}"
          if LEADS_ON && (LEAD_ALWAYS || rng.rand < 0.3)
            # The loved lead, dry: an arpeggio over the chord an octave up, its shape
            # drawn fresh, a new patch every four notes across every lead the synth has.
            lead_order ||= MOOG_LEADS.keys.shuffle(random: rng)
            # An octave lower than before, and always climbing: the chord, then the
            # chord an octave up, arped upward.
            order = (voicing + voicing.map { |m| m + 12 }).sort
            step = BAR / 16
            # Stochas-style probability: each step plays on its own chance, and a 5- or
            # 7-step layer running against the 16 marks the notes that always sound,
            # so the arpeggio keeps its shape but never repeats a bar.
            odd = [5, 7].sample(random: rng)
            16.times do |k|
              chance = (k % odd).zero? ? 1.0 : [0.9, 0.55, 0.75, 0.45][k % 4]
              next if rng.rand > chance
              at = next_chord + (k * step)
              voices << voice(order[k % order.size], lead_at(lead_order, at), at, step * 0.7, 0.08, bass: :arp)
            end
            log.puts "  arp over it"
          end
          chord_i += 1
          next_chord += CHORD_LEN
        end
        n = BLOCK
        left = Array.new(n, 0.0)
        arp_l = Array.new(n, 0.0)
        arp_r = Array.new(n, 0.0)
        right = Array.new(n, 0.0)
        pad_l = Array.new(n, 0.0)
        padb_l = Array.new(n, 0.0)
        padb_r = Array.new(n, 0.0)
        pad_r = Array.new(n, 0.0)
        tb = frame.to_f / RATE
        ck = cutoff_knob(tb)
        rk = res_knob(tb)
        voices.each do |v|
          spec = v.spec
          rel = spec[:amp].release
          next if tb + (n.to_f / RATE) < v.start || tb > v.start + v.held + rel
          level = 1.0 / spec[:waves].size
          freqs = spec[:waves].each_index.map { |k| v.hz * (2.0**spec[:octaves][k]) * (2.0**(spec[:detune][k] / 1200.0)) }
          base_cut = spec[:cutoff] * (v.bass == true ? 0.7 + ck * 0.8 : 0.35 + ck * 1.6)
          res = v.bass == true ? spec[:resonance] : [spec[:resonance] + rk * 0.45, 0.85].min
          # The envelopes at control rate, every 16 samples: inaudible, and half the
          # cost that had the player at 100% of a core and dropping blocks.
          waves = spec[:waves]
          nw = waves.size
          out_l, out_r = case v.bass
                         when :arp then [arp_l, arp_r]
                         when :pad then [pad_l, pad_r]
                         when :pad_b then [padb_l, padb_r]
                         else [left, right]
                         end
          cut = ampv = 0.0
          j = 0
          while j < n
            t = tb + (j.to_f / RATE) - v.start
            if t >= 0
              if (j & 15).zero?
                shape = spec[:filter_env].at(t, v.held)
                shape = (shape * (1.0 - spec[:lpg])) + (spec[:amp].at(t, v.held) * spec[:lpg]) if spec[:lpg]
                cut = (base_cut + (spec[:env_amount] * shape)).clamp(30.0, 12_000.0)
                ampv = spec[:amp].at(t, v.held) * v.gain
              end
              raw = 0.0
              k = 0
              while k < nw
                v.phases[k] = (v.phases[k] + (freqs[k] / RATE)) % 1.0
                raw += S.wave(waves[k], v.phases[k]) * level
                k += 1
              end
              out = v.ladder.process(raw * spec[:drive], cut, res) * ampv
              out_l[j] += out * 0.52
              out_r[j] += out * 0.48
            end
            j += 1
          end
        end
            
      voices.reject! { |v| tb > v.start + v.held + v.spec[:amp].release }

      # Sequence the DFAM a block ahead, on its own clock. Every two to six bars
      # a new groove is drawn: one of the four named ones or a fresh Euclidean
      # pattern, at a rate of its own against the steady kick -- sixteenths,
      # triplets, thirty-seconds, dotted sixteenths or eighths. While it plays,
      # its pitches and its rotation keep mutating.
      while dfam_next < tb + (n.to_f / RATE)
        if dfam_scene.nil? || dfam_next >= next_scene_at
          dfam_scene = new_scene.(dfam_scene && dfam_scene[:kind])
          next_scene_at = dfam_next + ((BAR / 2) * dfam_rng.rand(2..6))
          log.puts "  dfam groove -> #{dfam_scene[:label]}"
        end
        step_len = DFAM_STEP * dfam_scene[:rate]
        hz = ->(p) { 32.0 * (2.0**(p / 100.0 * 4.0)) }
        add = ->(at, p, vel, pan) { dfam_hits << DfamHit.new(at, hz.(p), vel, 0.0, 0.0, S::Ladder.new(rate: RATE), pan) }
        pitches = dfam_scene[:pitches]
        case dfam_scene[:kind]
        when :generated
          if dfam_scene[:hits][dfam_step % dfam_scene[:hits].size]
            add.(dfam_next, pitches[dfam_step % pitches.size], dfam_rng.rand < 0.25 ? 1.1 : dfam_rng.rand(0.5..0.85), dfam_rng.rand(0.25..0.75))
          end
        when :euclid
          add.(dfam_next, pitches[dfam_step % pitches.size], 1.0, 0.45) if euclid(5, 16)[dfam_step % 16]
        when :ratchet
          if (dfam_step % 6).zero? || dfam_rng.rand < 0.12
            reps = dfam_rng.rand(2..4)
            p0 = dfam_rng.rand(25..45)
            reps.times { |r| add.(dfam_next + (r * step_len / 2), p0 - (r * 12), 0.9 - (r * 0.15), 0.3 + (0.4 * (r % 2))) }
          end
        when :broken
          add.(dfam_next, pitches[6 - (dfam_step % 7)] || pitches.first, dfam_rng.rand(0.4..1.0), dfam_rng.rand(0.2..0.8)) if dfam_rng.rand < 0.6
        when :tribal
          t12 = dfam_step % 12
          add.(dfam_next, pitches[t12 % pitches.size], [0, 3, 6].include?(t12) ? 1.1 : 0.6, 0.35 + (0.3 * (t12 % 2))) if euclid(7, 12)[t12]
        end
        # The mutation: now and then a pitch redrawn, the pattern turned a step.
        pitches[dfam_rng.rand(pitches.size)] = dfam_rng.rand(5..45) if dfam_rng.rand < 0.07
        dfam_scene[:hits] = dfam_scene[:hits].rotate(1) if dfam_rng.rand < 0.03
        dfam_step += 1
        dfam_next += step_len
      end
      # The industrial grid, after Attack Magazine's dissection: the kick four
      # on the floor, a closed hat on each offbeat, a shaker on every second
      # offbeat, a noise snare on two and four. The DFAM is the syncopated low tom.
      while grid_next < tb + (n.to_f / RATE)
        s16 = grid_step % 16
        kicks << grid_next if KICKS_ON && (s16 % 4).zero?
        hats << [grid_next, HAT_CLOSED, 0.9] if s16 % 4 == 2
        hats << [grid_next + 0.004, SHAKER, 0.6] if [6, 14].include?(s16)
        claps << grid_next if [4, 12].include?(s16)
        grid_step += 1
        grid_next += DFAM_STEP
      end
      kv = DFAM_KNOBS.transform_values { |k| k.step(n.to_f / RATE, tb) }
      if tb > next_gesture
        name = DFAM_KNOBS.keys.sample(random: knob_rng)
        target = knob_rng.rand < 0.5 ? knob_rng.rand(0.0..0.15) : knob_rng.rand(0.85..1.0)
        DFAM_KNOBS[name].lean(target, BAR * knob_rng.rand(0.5..1.5), tb)
        log.puts "  dfam: #{name} -> #{target > 0.5 ? "up" : "down"}"
        next_gesture = tb + knob_rng.rand(6.0..16.0)
      end
      vcf = kv[:vcf_decay]
      vca = kv[:vca_decay]
      cut_top = kv[:cutoff]
      dfam_hits.each do |h|
        pitch_env = cut = amp = 0.0
        j = 0
        while j < n
          tt = tb + (j.to_f / RATE) - h.start
          if tt >= 0
            if (j & 15).zero?
              pitch_env = 1.0 + (kv[:pitch_amount] * Math.exp(-tt / kv[:pitch_decay]))
              cut = 120.0 + (cut_top * Math.exp(-tt / vcf))
              amp = h.vel * Math.exp(-tt / vca) * DFAM_LEVEL
            end
            h.ph1 = (h.ph1 + (h.f0 * pitch_env / RATE)) % 1.0
            tri = S.wave(:triangle, h.ph1)
            h.ph2 = (h.ph2 + (h.f0 * 1.5 * pitch_env * (1.0 + (kv[:fm] * tri)) / RATE)) % 1.0
            sq = h.ph2 < 0.5 ? 1.0 : -1.0
            mix = (0.55 * tri) + (0.3 * sq) + (kv[:noise] * (rand * 2.0 - 1.0))
            out = h.ladder.process(mix, cut, kv[:resonance]) * amp
            left[j] += out * h.pan
            right[j] += out * (1.0 - h.pan)
          end
          j += 1
        end
      end
      dfam_hits.reject! { |h| tb - h.start > vca * 8 }
        bar = (tb / (BAR / 2)).floor
      if bar != cut_bar
        cut_bar = bar
      cut_name = CUTS.keys.sample(random: rng)
      bar_start = bar * (BAR / 2)
      beat = 4 * DFAM_STEP
      if (bar % 8) == 7 && rng.rand < 0.5
        deck_fx = [:spinback, bar_start + (3 * beat)]
        log.puts "  deck: spinback"
      elsif rng.rand < 0.12
        deck_fx = [:tape_stop, bar_start + (3 * beat)]
        log.puts "  deck: tape stop"
      end
      dub_throw = rng.rand < 0.25
      log.puts "  deck: dub throw" if dub_throw
        log.puts "  pads cut -> #{cut_name}"
      end
      cut = CUTS[cut_name]
      j = 0
      while j < n
        now = tb + (j.to_f / RATE)
        bus = 0.0
        duck = 0.0
        kicks.each do |t|
          tk = now - t
          next if tk.negative? || tk > 0.5
          d = Math.exp(-tk / 0.12)
          duck = d if d > duck
          phase = (50.0 * tk) + (170.0 * 0.012 * (1.0 - Math.exp(-tk / 0.012))) + (30.0 * 0.08 * (1.0 - Math.exp(-tk / 0.08)))
          bus += Math.sin(2 * Math::PI * phase) * Math.exp(-tk / 0.34)
          if tk < 0.003
            click_lp += 0.35 * ((rand * 2.0 - 1.0) - click_lp)
            bus += (click_lp * 1.2) + (tk < 0.0008 ? 0.6 : 0.0)
          end
        end
        # Driven into hard clipping and back: the distorted industrial kick.
        k = Math.tanh(Math.tanh(bus * 7.0) * 2.5)
        k = (k * 256).round / 256.0 * KICK_LEVEL # a bitcrusher for the crisp attack
        wet = 0.0
        c = 0
        while c < 3
          buf = COMBS[c]
          y = buf[comb_i[c]]
          buf[comb_i[c]] = k + (y * 0.8)
          comb_i[c] = (comb_i[c] + 1) % buf.size
          wet += y
          c += 1
        end
        rum_lp1 += RUM_A * (Math.tanh(wet * 12.0) - rum_lp1)
        rum_lp2 += RUM_A * (rum_lp1 - rum_lp2)
        rumble = rum_lp2 * RUMBLE_LEVEL * (1.0 - (0.9 * duck))
        metal = 0.0
        hats.each do |t, open, vel|
          idx = ((now - t) * RATE).to_i
          table = open
          metal += table[idx] * vel if idx >= 0 && idx < table.size
        end
        hat_lp += HAT_A * (metal - hat_lp)
        # Crushed to 12 bits and overdriven, the SP-1200 resample.
        hat = Math.tanh(((metal - hat_lp) * 32).round / 32.0 * 0.5) * 2.0 * HAT_LEVEL
        clap = 0.0
        claps.each do |t|
          tc = now - t
          next if tc.negative? || tc > 0.35
          burst = (1.0 - Math.exp(-tc / 0.004)) * Math.exp(-tc / 0.11)
          clap += ((rand * 2.0) - 1.0) * burst
        end
        clap_lp += 0.18 * (Math.tanh(clap * 2.5) - clap_lp)
        clap_hp += 0.05 * (clap_lp - clap_hp)
        drums = k + hat + ((clap_lp - clap_hp) * CLAP_LEVEL)
        # Parallel distortion on the drum bus: grit blended under the clean hits.
        drums += Math.tanh(drums * 12.0) * 0.025
        # The pads pump against the kick.

      beat_len = 4 * DFAM_STEP
      breath += BREATH_GLIDE * ((1.0 - (BREATH_DEPTH * Math.exp(-(now % beat_len) / BREATH_RECOVER_S))) - breath)
      pump = breath
      deck = CUTS_ON ? cut[(now / (DFAM_STEP / 2)).floor % 32] : "A"
      gain_a += CUT_GLIDE * ((deck == "A" ? 1.0 : 0.0) - gain_a)
      gain_b += CUT_GLIDE * ((deck == "B" ? 1.0 : 0.0) - gain_b)
      pl = (pad_l[j] * gain_a) + (padb_l[j] * gain_b)
      pr = (pad_r[j] * gain_a) + (padb_r[j] * gain_b)
      # Baby scratches: a third of the cuts that open the fader get a hand on it.
      s32 = (now / (DFAM_STEP / 2)).floor
      if s32 != last_s32
        deck_fx = [:baby, now] if last_deck == "-" && deck != "-" && deck_fx.nil? && rng.rand < 0.12
        last_s32 = s32
        last_deck = deck
      end
      deck_l[deck_w] = pl
      deck_r[deck_w] = pr
      d = 0.0
      deck_gain = 1.0
      if deck_fx && now >= deck_fx[1]
        x = now - deck_fx[1]
        case deck_fx[0]
        when :baby
          len = DFAM_STEP
          if x < len
            d = 0.008 * (1.0 - Math.cos(2 * Math::PI * x / len)) / 2.0
          else
            deck_fx = nil
          end
        when :tape_stop
          len = 4 * DFAM_STEP
          if x < len
            d = x * x / (2.0 * len)
            deck_gain = 1.0 - (x / len)
          else
            deck_fx = nil
          end
        when :spinback
          if x < 0.5
            d = x < 0.1 ? 20.0 * x * x : 0.2 + (4.0 * (x - 0.1))
            deck_gain = 1.0 - (x / 0.5)
          else
            deck_fx = nil
          end
        end
      end
      if d.positive?
        pos = deck_w - (d * RATE)
        i0 = pos.floor
        frac = pos - i0
        a = i0 % DECK_LEN
        b = (i0 + 1) % DECK_LEN
        pl = ((deck_l[a] * (1.0 - frac)) + (deck_l[b] * frac)) * deck_gain
        pr = ((deck_r[a] * (1.0 - frac)) + (deck_r[b] * frac)) * deck_gain
      elsif deck_gain < 1.0
        pl *= deck_gain
        pr *= deck_gain
      end
      deck_w = (deck_w + 1) % DECK_LEN
      # The dub throw: the send opens for the bar's last eighth.
      bar_pos = (now % (BAR / 2)) / (BAR / 2)
      dub_send += 0.002 * ((dub_throw && bar_pos > 0.875 ? 1.0 : 0.0) - dub_send)
      el = dub_l[(dub_w - DUB_DELAY) % DUB_LEN]
      er = dub_r[(dub_w - DUB_DELAY) % DUB_LEN]
      dub_lp_l += DUB_LP * (el - dub_lp_l)
      dub_lp_r += DUB_LP * (er - dub_lp_r)
      dub_hp_l += DUB_HP * (dub_lp_l - dub_hp_l)
      dub_hp_r += DUB_HP * (dub_lp_r - dub_hp_r)
      dub_l[dub_w] = (pl * dub_send) + ((dub_lp_r - dub_hp_r) * 0.6) # crossed: the echo walks
      dub_r[dub_w] = (pr * dub_send) + ((dub_lp_l - dub_hp_l) * 0.6)
      dub_w = (dub_w + 1) % DUB_LEN
      pl += (dub_lp_l - dub_hp_l) * 0.7
      pr += (dub_lp_r - dub_hp_r) * 0.7
      mono = (pl + pr) * 0.5
      juno[juno_w] = mono
      tri = ((now * JUNO_HZ) % 1.0)
      tri = tri < 0.5 ? tri * 2 : 2 - (tri * 2)
      jl = juno_read(juno, juno_w - JUNO_CENTRE - (JUNO_DEPTH * tri))
      jr = juno_read(juno, juno_w - JUNO_CENTRE - (JUNO_DEPTH * (1.0 - tri)))
      juno_w = (juno_w + 1) % JUNO_LEN
      pl = (pl * 0.75) + (jl * 0.55)
      pr = (pr * 0.75) + (jr * 0.55)
      left[j] += (pl * pump) + drums + rumble
      right[j] += (pr * pump) + drums + rumble
      # The Crystallizer on the lead.
      cl = crys_out_l = 0.0
      cr = crys_out_r = 0.0
      2.times do |g|
        ph = (crys_p + (g * CRYS_GRAIN / 2)) % CRYS_GRAIN
        win = 0.5 - (0.5 * Math.cos(2 * Math::PI * ph / CRYS_GRAIN))
        at = (crys_w - CRYS_DELAY - ((CRYS_GRAIN - ph) * crys_pitch).to_i) % CRYS_LEN
        cl += crys_l[at] * win
        cr += crys_r[at] * win
      end
      crys_l[crys_w] = arp_l[j] + (cr * CRYS_FEEDBACK) # crossed, so the shimmer walks the field
      crys_r[crys_w] = arp_r[j] + (cl * CRYS_FEEDBACK)
      crys_w = (crys_w + 1) % CRYS_LEN
      crys_p += 1
      if crys_p >= CRYS_GRAIN * 24 # every few seconds, a fifth or an octave
        crys_p = 0
        crys_pitch = [2.0, 1.5, 2.0].sample(random: rng)
      end
      arp_l[j] += cl * CRYS_MIX
      arp_r[j] += cr * CRYS_MIX
      j += 1
      end
      kicks.reject! { |t| tb - t > 0.5 }
      hats.reject! { |t, _, _| tb - t > 0.1 }
      claps.reject! { |t| tb - t > 0.35 }
      pcm = Array.new(n * 4)
      n.times do |i|
        pcm[i * 4] = (Math.tanh(left[i]) * 29_000).round
        pcm[(i * 4) + 1] = (Math.tanh(right[i]) * 29_000).round
        pcm[(i * 4) + 2] = (Math.tanh(arp_l[i] * 1.4) * 26_000).round
        pcm[(i * 4) + 3] = (Math.tanh(arp_r[i] * 1.4) * 26_000).round
      end
      sox.write(pcm.pack("s<*"))
        frame += n
      end
      sox.close
    end
  end

  module Liveset4abbb73e
    # takes/liveset_4abbb73e.rb, frozen as heard (sha256 6b4d7f5cba19e0dbb7dd58626f4e1e0792a3fd716e76f9d25bfebc33922de3bf).

    # MASTER's main sound, improvising: the frozen default (default_sound.rb),
    # with the chords chosen live instead of looped. It opens on the loved
    # progression, then walks soul-jazz harmony, each chord voiced nearest the
    # last, a new moog patch every two chords, the DFAM on top. Endless.

    RATE = 32_000
    BLOCK = 1_024
    S = AnalogSynth
    P = S::PATCHES

    def self.hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

    # Fm9, Bbm9, Eb13, Abmaj9, Dbmaj7#11, C7alt: soul-jazz, Dilla territory.
    CHORDS = [
      [41, [56, 60, 63, 67]], [46, [56, 61, 65, 68]], [39, [55, 60, 61, 65]],
      [44, [55, 60, 63, 70]], [37, [60, 65, 67, 72]], [36, [58, 61, 64, 68]],
    ]
    PADS = %i[warm_pad poly_strings prophet_five juno_pad prophet_pad vp330_ensemble soft_reed e_piano rhodes_tine glass_bell]
    BASSES = %i[moog_bass acid sub dub_bass]
    QUALITIES = {
      m9: [3, 7, 10, 14], m11: [3, 7, 10, 17], maj9: [4, 7, 11, 14], maj7s11: [4, 7, 11, 18],
      d13: [4, 10, 14, 21], alt: [4, 10, 13, 15], m6_9: [3, 7, 9, 14], sus13: [5, 10, 14, 21],
    }.freeze
    MOVES = {
      [0, :m9] => [[5, :m9], [10, :d13], [8, :maj9], [5, :m11], [3, :maj9]],
      [0, :m11] => [[5, :m9], [8, :maj7s11], [10, :sus13]],
      [5, :m9] => [[10, :d13], [7, :alt], [3, :maj9], [0, :m6_9]],
      [5, :m11] => [[10, :d13], [7, :alt]],
      [10, :d13] => [[3, :maj9], [8, :maj9], [0, :m9]],
      [10, :sus13] => [[10, :d13], [3, :maj9]],
      [3, :maj9] => [[8, :maj9], [5, :m9], [1, :maj7s11]],
      [8, :maj9] => [[1, :maj7s11], [7, :alt], [5, :m9]],
      [8, :maj7s11] => [[7, :alt], [1, :maj7s11]],
      [1, :maj7s11] => [[7, :alt], [0, :m9], [0, :m11]],
      [7, :alt] => [[0, :m9], [0, :m11], [8, :maj9]],
      [0, :m6_9] => [[5, :m9], [10, :d13]],
    }.freeze
    NAMES = %w[C Db D Eb E F Gb G Ab A Bb B].freeze

    def self.voice_lead(pcs, previous)
      pcs.each_with_index.map do |pc, idx|
        centre = previous[idx] || previous.last
        (53..74).select { |m| m % 12 == pc }.min_by { |m| (m - centre).abs }
      end.sort.uniq
    end
    BAR = 3.9

    Voice = Struct.new(:hz, :spec, :start, :held, :gain, :phases, :ladder, :bass)

    def self.voice(midi, spec, start, held, gain, bass: false)
      rng = Random.new(midi * 7 + (start * 10).to_i)
      Voice.new(hz(midi) * 2.0**(rng.rand(-0.7..0.7) / 1200.0), spec, start, held, gain,
                spec[:waves].map { rng.rand }, S::Ladder.new(rate: RATE), bass)
    end

    # The knobs: cutoff breathes over 23 s, resonance over 31 s, out of phase.
    def self.cutoff_knob(t) = 0.55 + 0.45 * Math.sin(2 * Math::PI * t / 23.0)
    def self.res_knob(t) = 0.5 + 0.5 * Math.sin(2 * Math::PI * t / 31.0 + 1.3)

    # The DFAM, as the Moog is built: an 8-step sequencer, each step its own pitch
    # and velocity, running in sixteenths; VCO 1 a triangle frequency-modulating
    # VCO 2, a square; both with a pitch envelope that falls; noise mixed in; all
    # of it through a ladder low-pass with its own decay, then the VCA's decay.
    # The pattern starts from dilla's DfamEngine and one step mutates every two
    # bars; decay and cutoff drift slowly, like the pads' knobs.
    DFAM_STEP = BAR / 24
    DFAM_LEVEL = 0.34
    # Accents on the eight-step page: the downbeat and the and-of-two lean in.
    ACCENT = [1.35, 0.8, 1.0, 0.85, 1.25, 0.8, 1.1, 0.9].freeze
    KICK_LEVEL = 0.09
    DfamHit = Struct.new(:start, :f0, :vel, :ph1, :ph2, :ladder, :pan)
    def self.vcf_decay_knob(t) = 0.05 + 0.1 * (0.5 + 0.5 * Math.sin(2 * Math::PI * t / 37.0))
    def self.vca_decay_knob(t) = 0.09 + 0.12 * (0.5 + 0.5 * Math.sin(2 * Math::PI * t / 29.0 + 0.7))
    def self.dfam_cut_knob(t) = 900.0 + 2600.0 * (0.5 + 0.5 * Math.sin(2 * Math::PI * t / 43.0 + 2.1))
    def self.sonitex(bits:, lo:, hi:, drive:, mix: 0.5, samples: 1)
      "volume=#{drive},acrusher=bits=#{bits}:mode=log:aa=1:mix=#{mix}:samples=#{samples}," \
        "highpass=f=#{lo},lowpass=f=#{hi},alimiter=limit=0.99"
    end

    # Level-neutral here: five stages at livesets' -7.5 dB each sank the pads 37 dB
    # under the kick. The colour stays; the loss does not.
    def self.vcs(depth:, smear:, db: 0.0)
      phaser_db = -2.6 + (10.9 * (depth - 0.26)) - (0.14 * (smear - 2.1))
      "aphaser=in_gain=0.75:out_gain=0.85:delay=#{smear}:decay=#{depth}:speed=0.5," \
        "aecho=0.9:1:#{smear.round}:0.08,volume=#{(db - phaser_db + 0.65).round(2)}dB"
    end

    MASTER = [
      vcs(depth: 0.34, smear: 2.4), sonitex(bits: 12, lo: 40, hi: 13_000, drive: 1.12),
      vcs(depth: 0.3, smear: 2.8), "alimiter=limit=0.95"
    ].join(",")
    def self.space_echo(head_ms, decays)
      taps = [1, 2, 3].map { |k| (head_ms * k).round }.join("|")
      "highpass=f=160,aecho=0.9:0.9:#{taps}:#{decays},lowpass=f=3200,chorus=0.9:0.9:25:0.35:0.6:1.8"
    end
    HEAD = BAR / 16 * 1000
    ARP_FX = "anull"
    GRAPH = "[0:a]pan=stereo|c0=c0|c1=c1,#{MASTER}[m];[0:a]pan=stereo|c0=c2|c1=c3,#{ARP_FX}[a];[m][a]amix=inputs=2:weights=1 1.5:normalize=0,alimiter=limit=0.96"

    def self.run(argv = [])
      loops = (argv[0] || 2).to_i

      voices = []
      rng = Random.new
      key = 5 # F minor, where the loved progression sits
      state = [0, :m9]
      voicing = CHORDS.first.last
      chord_i = 0
      next_chord = 0.0
      log = File.open(File.join(__dir__, "..", "moog_improv.log"), "a").tap { |f| f.sync = true }
      total = Float::INFINITY
      pattern = { pitch: [50, 30, 60, 20, 55, 35, 65, 25], velocity: [80, 60, 90, 50, 85, 65, 95, 55] }
      dfam_rng = Random.new
      dfam_hits = []
      dfam_next = 0.0
      dfam_step = 0
      pattern_b = { pitch: [78, 64, 88, 70, 92], velocity: [55, 0, 70, 45, 60] }
      kicks = []

      $stderr.puts "improvising: #{PADS.join(" -> ")} over moog_bass, DFAM on top"
      sox = IO.popen(["sh", "-c", "ffmpeg -loglevel error -f s16le -ar #{RATE} -ac 4 -i - -filter_complex '#{GRAPH}' -f s16le -ar #{RATE} -ac 2 - | sox -q -t raw -r #{RATE} -e signed -b 16 -c 2 - -d"], "wb")
      frame = 0
      frames = Float::INFINITY
      two_pi = 2 * Math::PI
      while frame < frames
        # The next chord, chosen a second before it sounds.
        while next_chord < (frame.to_f / RATE) + 1.0
          if chord_i < CHORDS.size
            bass, tones = CHORDS[chord_i]
            voicing = tones
            name = "loved #{chord_i + 1}"
          else
            degree, quality = state
            voicing = voice_lead(QUALITIES[quality].map { |iv| (key + degree + iv) % 12 }, voicing)
            bass = 36 + ((key + degree) % 12)
            bass += 12 if bass < 36
            name = "#{NAMES[(key + degree) % 12]}#{quality}"
            state = MOVES.fetch(state).sample(random: rng)
            if (chord_i % 24).zero? && state.first.zero?
              key = (key + [5, 3, 8, 10].sample(random: rng)) % 12
              state = [0, %i[m9 m11].sample(random: rng)]
            end
          end
          pad = P.fetch(PADS[chord_i % PADS.size])
          bass_patch = P.fetch(BASSES[(chord_i / 4) % BASSES.size])
          voicing.each { |m| voices << voice(m, pad, next_chord, BAR - 0.1, 0.22) }
          # Moog bass: the chord root twice a bar, the second a little late.
          voices << voice(bass, bass_patch, next_chord, 1.6, 0.55, bass: true)
          voices << voice(bass, bass_patch, next_chord + (BAR * 0.534), 1.2, 0.45, bass: true)
          log.puts "#{Time.now.strftime("%H:%M:%S")} #{name} on #{PADS[chord_i % PADS.size]}, bass #{BASSES[(chord_i / 4) % BASSES.size]}"
          if rng.rand < 0.3
            # A new patch every four notes, across every lead the synth has.
            arp_patches = %i[glass_bell e_piano poly_lead vapor_lead soft_reed ringtone_lead acid rhodes_tine].shuffle(random: rng)
            notes = voicing.map { |m| m + 12 }
            order = [notes, notes.reverse, notes + notes.reverse[1..-2], notes.shuffle(random: rng)].sample(random: rng)
            step = BAR / 16
            16.times { |k| voices << voice(order[k % order.size], P.fetch(arp_patches[(k / 4) % arp_patches.size]), next_chord + (k * step), step * 0.7, 0.45, bass: :arp) }
            log.puts "  arp over it"
          end
          chord_i += 1
          next_chord += BAR
        end
        n = BLOCK
        left = Array.new(n, 0.0)
        arp_l = Array.new(n, 0.0)
        arp_r = Array.new(n, 0.0)
        right = Array.new(n, 0.0)
        tb = frame.to_f / RATE
        ck = cutoff_knob(tb)
        rk = res_knob(tb)
        voices.each do |v|
          spec = v.spec
          rel = spec[:amp].release
          next if tb + (n.to_f / RATE) < v.start || tb > v.start + v.held + rel
          level = 1.0 / spec[:waves].size
          freqs = spec[:waves].each_index.map { |k| v.hz * (2.0**spec[:octaves][k]) * (2.0**(spec[:detune][k] / 1200.0)) }
          base_cut = spec[:cutoff] * (v.bass == true ? 0.7 + ck * 0.8 : 0.35 + ck * 1.6)
          res = v.bass == true ? spec[:resonance] : [spec[:resonance] + rk * 0.45, 0.85].min
          # The envelopes at control rate, every 16 samples: inaudible, and half the
          # cost that had the player at 100% of a core and dropping blocks.
          waves = spec[:waves]
          nw = waves.size
          out_l, out_r = v.bass == :arp ? [arp_l, arp_r] : [left, right]
          cut = ampv = 0.0
          j = 0
          while j < n
            t = tb + (j.to_f / RATE) - v.start
            if t >= 0
              if (j & 15).zero?
                cut = (base_cut + (spec[:env_amount] * spec[:filter_env].at(t, v.held))).clamp(30.0, 12_000.0)
                ampv = spec[:amp].at(t, v.held) * v.gain
              end
              raw = 0.0
              k = 0
              while k < nw
                v.phases[k] = (v.phases[k] + (freqs[k] / RATE)) % 1.0
                raw += S.wave(waves[k], v.phases[k]) * level
                k += 1
              end
              out = v.ladder.process(raw * spec[:drive], cut, res) * ampv
              out_l[j] += out * 0.52
              out_r[j] += out * 0.48
            end
            j += 1
          end
        end
      voices.reject! { |v| tb > v.start + v.held + v.spec[:amp].release }

      # Sequence the DFAM a block ahead.
      while dfam_next < tb + (n.to_f / RATE)
        step = dfam_step % 8
        vel = pattern[:velocity][step] / 100.0 * ACCENT[step]
        if vel.positive?
          f0 = 40.0 * (2.0**(pattern[:pitch][step] / 100.0 * 3.0))
          dfam_hits << DfamHit.new(dfam_next, f0, vel, 0.0, 0.0, S::Ladder.new(rate: RATE), 0.35 + (0.3 * (step % 2)))
        end
      b = dfam_step % 5
      if pattern_b[:velocity][b].positive?
        fb = 40.0 * (2.0**(pattern_b[:pitch][b] / 100.0 * 3.0))
        dfam_hits << DfamHit.new(dfam_next + 0.004, fb, pattern_b[:velocity][b] / 100.0 * 0.55, 0.0, 0.0, S::Ladder.new(rate: RATE), b.even? ? 0.25 : 0.75)
      end
      # The kick on every beat: four steps of the sequencer.
      kicks << dfam_next if (dfam_step % 4).zero?
      dfam_step += 1
        if (dfam_step % 32).zero?
          k = dfam_rng.rand(8)
          pattern[:pitch][k] = (pattern[:pitch][k] + dfam_rng.rand(-18..18)).clamp(5, 95)
          pattern[:velocity][k] = dfam_rng.rand < 0.15 ? 0 : (pattern[:velocity][k] + dfam_rng.rand(-20..20)).clamp(35, 100)
        end
        dfam_next += DFAM_STEP
      end
      vcf = vcf_decay_knob(tb)
      vca = vca_decay_knob(tb)
      cut_top = dfam_cut_knob(tb)
      dfam_hits.each do |h|
        j = 0
        while j < n
          tt = tb + (j.to_f / RATE) - h.start
          if tt >= 0
            pitch_env = 1.0 + (2.2 * Math.exp(-tt / 0.045))
            h.ph1 = (h.ph1 + (h.f0 * pitch_env / RATE)) % 1.0
            tri = S.wave(:triangle, h.ph1)
            h.ph2 = (h.ph2 + (h.f0 * 1.5 * pitch_env * (1.0 + (0.45 * tri)) / RATE)) % 1.0
            sq = h.ph2 < 0.5 ? 1.0 : -1.0
            mix = (0.55 * tri) + (0.3 * sq) + (0.18 * (rand * 2.0 - 1.0))
            cut = 120.0 + (cut_top * Math.exp(-tt / vcf))
            out = h.ladder.process(mix, cut, 0.55) * h.vel * Math.exp(-tt / vca) * DFAM_LEVEL
            left[j] += out * h.pan
            right[j] += out * (1.0 - h.pan)
          end
          j += 1
        end
      end
      dfam_hits.reject! { |h| tb - h.start > vca * 8 }
      j = 0
      while j < n
        now = tb + (j.to_f / RATE)
        bus = 0.0
        kicks.each do |t|
          tk = now - t
          next if tk.negative? || tk > 0.5
          bus += Math.sin(2 * Math::PI * ((45.0 * tk) + (105.0 * 0.035 * (1.0 - Math.exp(-tk / 0.035))))) * Math.exp(-tk / 0.32)
          bus += (tk < 0.005 ? (1.0 - (tk / 0.005)) * 0.5 : 0.0)
        end
        k = Math.tanh(bus * 2.8) * KICK_LEVEL
        left[j] += k
        right[j] += k
        j += 1
      end

      kicks.reject! { |t| tb - t > 0.5 }
      pcm = Array.new(n * 4)
      n.times do |i|
        pcm[i * 4] = (Math.tanh(left[i] * 1.4) * 26_000).round
        pcm[(i * 4) + 1] = (Math.tanh(right[i] * 1.4) * 26_000).round
        pcm[(i * 4) + 2] = (Math.tanh(arp_l[i] * 1.4) * 26_000).round
        pcm[(i * 4) + 3] = (Math.tanh(arp_r[i] * 1.4) * 26_000).round
      end
      sox.write(pcm.pack("s<*"))
        frame += n
      end
      sox.close
    end
  end

  module Liveset5613fe64b642
    # takes/liveset_5613fe64b642.rb, frozen as heard (sha256 9499edf5943c811e50c8cb9caa02a388df8d10cc67580cd7336d4e07345adcd7).

    # MASTER's main sound, improvising live and endless: soul-jazz harmony chosen
    # chord by chord, each voiced nearest the last, the key moving on its own.
    # The chords play only Moog presets on dilla's ladder, morphing over four
    # chords, whole and uncut; the turntablist's crossfader waits behind
    # CUTS_ON. A hand still works the record now and then: a tape stop, a
    # spinback at the end of some phrases, a dub delay throw. Over it, quiet dry
    # Rhodes arpeggios; under it the rolling Moog bass, an industrial grid at
    # 128 BPM and the DFAM, always changing. Kicks sit off: KICKS_ON.

    RATE = 32_000
    BLOCK = 1_024
    S = AnalogSynth
    P = S::PATCHES.dup

    def self.hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

    # Fm9, Bbm9, Eb13, Abmaj9, Dbmaj7#11, C7alt: soul-jazz, Dilla territory.
    CHORDS = [
      [41, [56, 60, 63, 67]], [46, [56, 61, 65, 68]], [39, [55, 60, 61, 65]],
      [44, [55, 60, 63, 70]], [37, [60, 65, 67, 72]], [36, [58, 61, 64, 68]],
    ]
    SNAP = { amp: S::Envelope.new(attack: 0.004, decay: 0.3, sustain: 0.35, release: 0.18),
             filter_env: S::Envelope.new(attack: 0.002, decay: 0.22, sustain: 0.2, release: 0.15) }.freeze
    PROPHET_LEADS = {
      prophet_five_lead: P[:prophet_five].merge(SNAP),
      prophet_pad_lead: P[:prophet_pad].merge(SNAP),
      prophet_poly: P[:poly_lead].merge(SNAP),
      prophet_bright: P[:prophet_five].merge(SNAP).merge(cutoff: 900.0, resonance: 0.42),
    }.freeze
    P.merge!(PROPHET_LEADS)
    # The Rhodes leads: dilla's two electric pianos, and each a shade brighter
    # and darker.
    RHODES_LEADS = {
      rhodes_tine: P[:rhodes_tine], e_piano: P[:e_piano],
      rhodes_bright: P[:rhodes_tine].merge(cutoff: P[:rhodes_tine][:cutoff] * 1.6),
      e_piano_dark: P[:e_piano].merge(cutoff: P[:e_piano][:cutoff] * 0.65),
    }.freeze
    P.merge!(RHODES_LEADS)
    # Moog chord presets, on dilla's ladder: the chords play only these, the
    # patch morphing from one to the next without a seam -- cutoff, resonance,
    # envelope depth, drive and detune all glide; the waves change at halfway.
    MOOG_ENV = { amp: P[:warm_pad][:amp], filter_env: P[:warm_pad][:filter_env] }.freeze
    MOOG_CHORDS = {
      minimoog_pad: { waves: %i[saw square triangle], detune: [0.0, -6.0, 7.0], octaves: [0, 0, -1], cutoff: 620.0, env_amount: 1400.0, resonance: 0.42, drive: 1.1 },
      memorymoog_brass: { waves: %i[saw saw saw], detune: [-9.0, 0.0, 9.0], octaves: [0, 0, 0], cutoff: 760.0, env_amount: 1900.0, resonance: 0.3, drive: 1.2 },
      polymoog_vox: { waves: %i[square square saw], detune: [-4.0, 5.0, 0.0], octaves: [0, 1, 0], cutoff: 900.0, env_amount: 700.0, resonance: 0.24, drive: 0.95 },
      moog_one_strings: { waves: %i[saw saw saw], detune: [-14.0, 0.0, 13.0], octaves: [0, 0, 1], cutoff: 1150.0, env_amount: 800.0, resonance: 0.2, drive: 0.9 },
      sub37_warm: { waves: %i[saw square saw], detune: [0.0, 4.0, -5.0], octaves: [0, -1, 0], cutoff: 480.0, env_amount: 1600.0, resonance: 0.55, drive: 1.3 },
    }.transform_values { |p| p.merge(MOOG_ENV) }.freeze
    # Four chords to travel from one preset to the next, in a fresh order each lap.
    MORPH_CHORDS = 4
    def self.moog_morph(order, chord_i)
      pos = chord_i.to_f / MORPH_CHORDS
      a = MOOG_CHORDS.fetch(order[pos.floor % order.size])
      b = MOOG_CHORDS.fetch(order[(pos.floor + 1) % order.size])
      x = pos - pos.floor
      lerp = ->(k) { a[k] + ((b[k] - a[k]) * x) }
      (x < 0.5 ? a : b).merge(cutoff: lerp.(:cutoff), env_amount: lerp.(:env_amount), resonance: lerp.(:resonance),
                               drive: lerp.(:drive), detune: a[:detune].each_index.map { |i| a[:detune][i] + ((b[:detune][i] - a[:detune][i]) * x) })
    end
    PADS = %i[warm_pad poly_strings prophet_five juno_pad prophet_pad vp330_ensemble soft_reed e_piano rhodes_tine glass_bell]
    BASSES = %i[moog_bass acid sub dub_bass]
    QUALITIES = {
      m9: [3, 7, 10, 14], m11: [3, 7, 10, 17], maj9: [4, 7, 11, 14], maj7s11: [4, 7, 11, 18],
      d13: [4, 10, 14, 21], alt: [4, 10, 13, 15], m6_9: [3, 7, 9, 14], sus13: [5, 10, 14, 21],
    }.freeze
    MOVES = {
      [0, :m9] => [[5, :m9], [10, :d13], [8, :maj9], [5, :m11], [3, :maj9]],
      [0, :m11] => [[5, :m9], [8, :maj7s11], [10, :sus13]],
      [5, :m9] => [[10, :d13], [7, :alt], [3, :maj9], [0, :m6_9]],
      [5, :m11] => [[10, :d13], [7, :alt]],
      [10, :d13] => [[3, :maj9], [8, :maj9], [0, :m9]],
      [10, :sus13] => [[10, :d13], [3, :maj9]],
      [3, :maj9] => [[8, :maj9], [5, :m9], [1, :maj7s11]],
      [8, :maj9] => [[1, :maj7s11], [7, :alt], [5, :m9]],
      [8, :maj7s11] => [[7, :alt], [1, :maj7s11]],
      [1, :maj7s11] => [[7, :alt], [0, :m9], [0, :m11]],
      [7, :alt] => [[0, :m9], [0, :m11], [8, :maj9]],
      [0, :m6_9] => [[5, :m9], [10, :d13]],
    }.freeze
    NAMES = %w[C Db D Eb E F Gb G Ab A Bb B].freeze

    def self.voice_lead(pcs, previous)
      pcs.each_with_index.map do |pc, idx|
        centre = previous[idx] || previous.last
        (53..74).select { |m| m % 12 == pc }.min_by { |m| (m - centre).abs }
      end.sort.uniq
    end
    # Industrial techno, ten below the 128 BPM it started at (Attack Magazine:
    # 126-130), at the operator's word. BAR is two bars, eight beats.
    BPM = 118
    BAR = 8 * 60.0 / BPM
    CHORD_LEN = BAR

    Voice = Struct.new(:hz, :spec, :start, :held, :gain, :phases, :ladder, :bass)

    def self.voice(midi, spec, start, held, gain, bass: false)
      rng = Random.new(midi * 7 + (start * 10).to_i)
      Voice.new(hz(midi) * 2.0**(rng.rand(-0.7..0.7) / 1200.0), spec, start, held, gain,
                spec[:waves].map { rng.rand }, S::Ladder.new(rate: RATE), bass)
    end

    # The knobs: cutoff breathes over 23 s, resonance over 31 s, out of phase.
    def self.cutoff_knob(t) = 0.55 + 0.45 * Math.sin(2 * Math::PI * t / 23.0)
    def self.res_knob(t) = 0.5 + 0.5 * Math.sin(2 * Math::PI * t / 31.0 + 1.3)

    # The DFAM, as the Moog is built: an 8-step sequencer, each step its own pitch
    # and velocity, running in sixteenths; VCO 1 a triangle frequency-modulating
    # VCO 2, a square; both with a pitch envelope that falls; noise mixed in; all
    # of it through a ladder low-pass with its own decay, then the VCA's decay.
    # The pattern starts from dilla's DfamEngine and one step mutates every two
    # bars; decay and cutoff drift slowly, like the pads' knobs.
    DFAM_STEP = BAR / 32 # sixteenths
    DFAM_LEVEL = 0.16
    # Accents on the eight-step page: the downbeat and the and-of-two lean in.
    DFAM_SCENES = %i[euclid ratchet broken tribal].freeze
    # Each groove brings its own kick, as [cycle length, steps that hit].
    SCENE_KICKS = { euclid: [16, [0, 6, 10]], ratchet: [12, [0, 7]], broken: [16, [0, 3, 10, 11]], tribal: [12, [0, 5, 8]] }.freeze
    DFAM_RATES = { 1.0 => "16ths", (2.0 / 3) => "triplets", 0.5 => "32nds", 1.5 => "dotted 16ths", 2.0 => "8ths" }.freeze
    # A Euclidean rhythm: k hits spread as evenly as n steps allow.
    def self.euclid(k, n) = (@euclid ||= {})[[k, n]] ||= Array.new(n) { |i| ((i * k) % n) < k }
    # And its own lead rhythm, on sixteen steps.
    SCENE_LEAD = { euclid: euclid(5, 16), ratchet: euclid(6, 16), broken: Array.new(16) { |i| [0, 3, 6, 10, 12].include?(i) }, tribal: euclid(7, 16) }.freeze
    ACCENT = [1.35, 0.8, 1.0, 0.85, 1.25, 0.8, 1.1, 0.9].freeze
    KICK_LEVEL = 0.06
    # Off at the operator's word, and with them the rumble and the pump.
    KICKS_ON = false
    # The crossfader is off at the operator's word: the chords play whole on
    # deck A, the morphing preset, and deck B is not voiced. true brings the
    # turntablist's cuts back.
    CUTS_ON = false
    # The lead plays over every chord, at the operator's word.
    LEAD_ALWAYS = true
    # Muted at the operator's word; true brings the leads back.
    LEADS_ON = true
    # Turntablism on the pads: a scratch DJ's sharp-curve crossfader, two decks
    # (the two Moog layers) cut hard on the thirty-second grid. Each pattern is
    # 32 steps, one bar: A is deck A open, B deck B, - the fader closed. The
    # fader moves in half a millisecond, so every cut is a cut, not a blend.
    CUTS = {
      transformer: "A-A-A-A-A-A-A-A-A-A-A-A-A-A-A-A-",
      slow_transformer: "AA--AA--AA--AA--BB--BB--BB--BB--",
      crab: "A-A-A-A-AAAAAAAAB-B-B-B-BBBBBBBB",
      chirp: "AAA-----AAA-----BBB-----BBB-----",
      orbit: "A--AA--AA--AA--AB--BB--BB--BB--B",
      flare: "AAAA-AAA-AAAAAAAAAAA-AAA-AAAAAAA",
      ab_chop: "AAAABBBBAAAABBBB--AABB--AABBAB--",
      tear: "AAAAAAAA--------A-A-AAAA--------",
    }.freeze
    # The record under the crossfader: the cut pads write into three seconds of
    # buffer and are read back at a delay d that is zero in plain play, so the
    # deck adds no latency. A hand on the record moves d: the read speed is
    # 1 - d', so a growing d drops the pitch and a shrinking one raises it.
    #   baby      d rises and falls over a sixteenth: the push and pull.
    #   tape_stop the speed falls from 1 to 0 over a beat, the level with it.
    #   spinback  the record thrown backwards at three times speed, fading.
    DECK_LEN = RATE * 3
    # The dub throw: a send, open for the bar's last eighth when it fires, into
    # a dotted-eighth echo that darkens and thins as it repeats.
    DUB_LEN = RATE
    DUB_DELAY = (3 * DFAM_STEP * RATE).round
    DUB_LP = 1.0 - Math.exp(-2 * Math::PI * 1800.0 / RATE)
    DUB_HP = 1.0 - Math.exp(-2 * Math::PI * 220.0 / RATE)
    CUT_GLIDE = 1.0 - Math.exp(-1.0 / (0.005 * RATE))
    # The Crystallizer, after Soundtoys: reversed grains of the lead, pitched up
    # an octave or a fifth, a quarter second late, fed back into themselves.
    # Two readers half a grain apart, Hann-windowed, crossfade into a shimmer.
    CRYS_LEN = RATE * 2
    CRYS_GRAIN = (RATE * 0.16).round
    CRYS_DELAY = (RATE * 0.25).round
    CRYS_FEEDBACK = 0.45
    CRYS_MIX = 0.5
    # The 909's hat: six detuned square waves, high-passed, then crushed to 12
    # bits the way an SP-1200 resample crunches it.
    HAT_HZ = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0].freeze
    HAT_LEVEL = 0.011
    # Rendered once: the squares, noise under them for grit, and the decay.
    hat_table = lambda do |len, decay|
      Array.new((len * RATE).to_i) do |i|
        th = i.to_f / RATE
        sq = HAT_HZ.sum { |f| ((th * f * 7.0) % 1.0) < 0.5 ? 1.0 : -1.0 }
        (sq + (((rand * 2.0) - 1.0) * 3.0)) * Math.exp(-th / decay)
      end.freeze
    end
    HAT_OPEN = hat_table.(0.3, 0.07)
    HAT_CLOSED = hat_table.(0.06, 0.015)
    # The shaker: noise alone, short, high-passed with the hats.
    SHAKER = Array.new((0.08 * RATE).to_i) { |i| ((rand * 2.0) - 1.0) * 2.0 * Math.exp(-i.to_f / RATE / 0.025) }.freeze
    CLAP_LEVEL = 0.08
    # The rumble: the kick sent into a dark reverb (three combs), distorted,
    # low-passed to 150 Hz, mono, and ducked by the kick itself.
    RUMBLE_LEVEL = 0.05
    COMBS = [1123, 1409, 1693].map { |len| Array.new(len, 0.0) }
    RUM_A = 1.0 - Math.exp(-2 * Math::PI * 150.0 / RATE)
    HAT_A = 1.0 - Math.exp(-2 * Math::PI * 7000.0 / RATE)
    DfamHit = Struct.new(:start, :f0, :vel, :ph1, :ph2, :ladder, :pan)
    class DfamKnob
      attr_reader :value
      def initialize(lo, hi, rng, speed:)
        @lo, @hi, @rng, @speed = lo, hi, rng, speed
        @x = 0.5
        @v = 0.0
        @push = nil
      end
      # A gesture: toward `target` (0..1) for `seconds`, then released.
      def lean(target, seconds, now) = @push = [target, now + seconds]
      def step(dt, now)
        @push = nil if @push && now > @push[1]
        pull = @push ? (@push[0] - @x) * 1.5 : (0.5 - @x) * 0.03
        @v = (@v * 0.992) + (@rng.rand(-1.0..1.0) * @speed * dt) + (pull * dt)
        @x = (@x + (@v * dt)).clamp(0.0, 1.0)
        @value = @lo + ((@hi - @lo) * @x)
      end
    end

    knob_rng = Random.new
    DFAM_KNOBS = {
      vcf_decay: DfamKnob.new(0.03, 0.22, knob_rng, speed: 0.08),
      vca_decay: DfamKnob.new(0.06, 0.28, knob_rng, speed: 0.07),
      cutoff: DfamKnob.new(500.0, 4200.0, knob_rng, speed: 0.1),
      resonance: DfamKnob.new(0.2, 0.85, knob_rng, speed: 0.06),
      fm: DfamKnob.new(0.0, 1.1, knob_rng, speed: 0.07),
      noise: DfamKnob.new(0.02, 0.45, knob_rng, speed: 0.05),
      pitch_amount: DfamKnob.new(0.6, 4.0, knob_rng, speed: 0.06),
      pitch_decay: DfamKnob.new(0.015, 0.12, knob_rng, speed: 0.05),
    }.freeze
    def self.sonitex(bits:, lo:, hi:, drive:, mix: 0.5, samples: 1)
      "volume=#{drive},acrusher=bits=#{bits}:mode=log:aa=1:mix=#{mix}:samples=#{samples}," \
        "highpass=f=#{lo},lowpass=f=#{hi},alimiter=limit=0.99"
    end

    # Level-neutral here: five stages at livesets' -7.5 dB each sank the pads 37 dB
    # under the kick. The colour stays; the loss does not.
    def self.vcs(depth:, smear:, db: 0.0)
      phaser_db = -2.6 + (10.9 * (depth - 0.26)) - (0.14 * (smear - 2.1))
      "aphaser=in_gain=0.75:out_gain=0.85:delay=#{smear}:decay=#{depth}:speed=0.5," \
        "aecho=0.9:1:#{smear.round}:0.08,volume=#{(db - phaser_db + 0.65).round(2)}dB"
    end

    MASTER = [
      vcs(depth: 0.34, smear: 2.4), sonitex(bits: 12, lo: 40, hi: 13_000, drive: 1.12),
      vcs(depth: 0.38, smear: 1.7), sonitex(bits: 13, lo: 42, hi: 15_000, drive: 1.04),
      vcs(depth: 0.26, smear: 3.6), sonitex(bits: 11, lo: 42, hi: 12_000, drive: 1.18),
      "alimiter=limit=0.95"
    ].join(",")
    def self.space_echo(head_ms, decays)
      taps = [1, 2, 3].map { |k| (head_ms * k).round }.join("|")
      "highpass=f=160,aecho=0.9:0.9:#{taps}:#{decays},lowpass=f=3200,chorus=0.9:0.9:25:0.35:0.6:1.8"
    end
    HEAD = BAR / 16 * 1000
    ARP_FX = "anull"
    # Extreme analog tape on the master channel, the whole sum: the head bump near
    # 60 Hz, the drive into tanh that tape saturation is (undone after, so it
    # colours rather than raises), the capstan's wow and flutter worn deep, the top
    # the tape cannot hold, and its hiss.
    def self.tape(drive:, wow:, flutter:, top:, hiss:)
      "equalizer=f=60:t=q:w=1.1:g=4.5,volume=#{drive},asoftclip=type=tanh,volume=#{(1.0 / drive).round(3)}," \
        "vibrato=f=0.42:d=#{wow},vibrato=f=6.8:d=#{flutter},lowpass=f=#{top},highpass=f=28," \
        "aeval=exprs=val(0)+#{hiss}*(2*random(0)-1)|val(1)+#{hiss}*(2*random(1)-1):c=same"
    end
    TAPE = tape(drive: 3.2, wow: 0.22, flutter: 0.07, top: 9_500, hiss: 0.004)
    # Arps on the arps, at the operator's word: the lead is split three ways. One
    # stays dry; one goes up a fifth and comes back an eighth late, the other up
    # an octave a dotted eighth late, so the echoes arpeggiate over the arpeggio.
    # Each pitched copy feeds back through its own echo the way a crystallizer
    # does, and the sum is sharpened with ffmpeg's crystalizer. The pitch shift is
    # asetrate then atempo, a resample and a time-stretch, which grains the copies.
    def self.pitched(ratio, delay_ms, echo_ms, decay)
      "asetrate=#{(RATE * ratio).round},aresample=#{RATE},atempo=#{(1.0 / ratio).round(4)}," \
        "adelay=#{delay_ms}|#{delay_ms},aecho=0.8:0.7:#{echo_ms}:#{decay}"
    end
    EIGHTH = (BAR / 16 * 1000).round
    ARPS_ON_ARPS = "asplit=3[ad][ax][ay];[ax]#{pitched(1.5, EIGHTH, EIGHTH * 2, 0.45)}[af];" \
                   "[ay]#{pitched(2.0, (EIGHTH * 1.5).round, EIGHTH * 3, 0.4)},highpass=f=900[ao];" \
                   "[ad][af][ao]amix=inputs=3:weights=1 0.5 0.35:normalize=0,crystalizer=i=1.5"
    # The leads sit lower in the sum, at the operator's word: 0.9 against the
    # main's 1 where they were 1.5.
    GRAPH = "[0:a]pan=stereo|c0=c0|c1=c1,#{MASTER}[m];[0:a]pan=stereo|c0=c2|c1=c3,#{ARPS_ON_ARPS}[a];[m][a]amix=inputs=2:weights=1 0.9:normalize=0,#{TAPE},alimiter=limit=0.96"

    def self.run(argv = [])
      loops = (argv[0] || 2).to_i

      voices = []
      rng = Random.new
      key = 5 # F minor, where the loved progression sits
      state = [0, :m9]
      voicing = CHORDS.first.last
      chord_i = 0
      moog_order = nil
      recent = []
      next_modulation = 8
      key = rng.rand(12)
      next_chord = 0.0
      log = File.open(File.join(__dir__, "..", "moog_improv.log"), "a").tap { |f| f.sync = true }
      total = Float::INFINITY
      pattern = { pitch: [50, 30, 60, 20, 55, 35, 65, 25], velocity: [80, 60, 90, 50, 85, 65, 95, 55] }
      dfam_rng = Random.new
      dfam_hits = []
      dfam_next = 0.0
      dfam_step = 0
      pattern_b = { pitch: [78, 64, 88, 70, 92], velocity: [55, 0, 70, 45, 60] }
      dfam_scene = nil
      next_scene_at = 0.0
      grid_next = 0.0
      grid_step = 0
      # A new groove, never the kind just played: its kind, its rate, and for a
      # generated one a Euclidean pattern of 2 to n-1 hits over 5 to 16 steps.
      new_scene = lambda do |last|
        kind = (DFAM_SCENES + %i[generated generated]).reject { |k| k == last && k != :generated }.sample(random: dfam_rng)
        rate, rate_name = DFAM_RATES.to_a.sample(random: dfam_rng)
        steps = dfam_rng.rand(5..16)
        hits = dfam_rng.rand(2..(steps - 1))
        label = kind == :generated ? "E(#{hits},#{steps}) in #{rate_name}" : "#{kind} in #{rate_name}"
        { kind:, rate:, label:, hits: euclid(hits, steps).rotate(dfam_rng.rand(steps)),
          pitches: Array.new(dfam_rng.rand(3..8)) { dfam_rng.rand(5..45) } }
      end
      kicks = []
      click_lp = 0.0
      cut_name = :transformer
      cut_bar = -1
      gain_a = 1.0
      gain_b = 0.0
      deck_l = Array.new(DECK_LEN, 0.0)
      deck_r = Array.new(DECK_LEN, 0.0)
      deck_w = 0
      deck_fx = nil # [kind, start]
      last_s32 = -1
      last_deck = "-"
      dub_l = Array.new(DUB_LEN, 0.0)
      dub_r = Array.new(DUB_LEN, 0.0)
      dub_w = 0
      dub_lp_l = dub_lp_r = dub_hp_l = dub_hp_r = 0.0
      dub_send = 0.0
      dub_throw = false
      crys_l = Array.new(CRYS_LEN, 0.0)
      crys_r = Array.new(CRYS_LEN, 0.0)
      crys_w = 0
      crys_p = 0
      crys_pitch = 2.0
      crys_out_l = crys_out_r = 0.0
      hats = []
      claps = []
      hat_lp = clap_lp = clap_hp = 0.0
      comb_i = [0, 0, 0]
      rum_lp1 = rum_lp2 = 0.0
      next_gesture = 8.0

      $stderr.puts "improvising: #{PADS.join(" -> ")} over moog_bass, DFAM on top"
      sox = IO.popen(["sh", "-c", "ffmpeg -loglevel error -f s16le -ar #{RATE} -ac 4 -i - -filter_complex '#{GRAPH}' -f s16le -ar #{RATE} -ac 2 - | sox -q -t raw -r #{RATE} -e signed -b 16 -c 2 - -d"], "wb")
      frame = 0
      frames = Float::INFINITY
      two_pi = 2 * Math::PI
      while frame < frames
        # The next chord, chosen a second before it sounds.
        while next_chord < (frame.to_f / RATE) + 1.0
          degree, quality = state
          voicing = voice_lead(QUALITIES[quality].map { |iv| (key + degree + iv) % 12 }, voicing)
          bass = 36 + ((key + degree) % 12)
          bass += 12 if bass < 36
          name = "#{NAMES[(key + degree) % 12]}#{quality}"
          recent << [(key + degree) % 12, quality]
          recent.shift if recent.size > 4
          options = MOVES.fetch(state).reject { |d, q| recent.include?([(key + d) % 12, q]) }
          options = MOVES.fetch(state) if options.empty?
          state = options.sample(random: rng)
          roll = rng.rand
          if roll < 0.08 # the tritone substitute: a dominant a flat fifth away
            key = (key + 6) % 12
            name += " (tritone sub next)"
          elsif roll < 0.14 # a chromatic side-step, up or down a semitone
            key = (key + [1, 11].sample(random: rng)) % 12
            name += " (side-step next)"
          end
          if chord_i >= next_modulation
            key = (key + [5, 3, 8, 10, 2, 7].sample(random: rng)) % 12
            state = [0, %i[m9 m11 m6_9].sample(random: rng)]
            next_modulation = chord_i + rng.rand(8..16)
            name += " -> #{NAMES[key]} minor"
          end
          moog_order = MOOG_CHORDS.keys.shuffle(random: rng) if (chord_i % (MORPH_CHORDS * MOOG_CHORDS.size)).zero?
          pad = moog_morph(moog_order, chord_i)
          pad_name = "#{moog_order[(chord_i / MORPH_CHORDS) % moog_order.size]} -> #{moog_order[((chord_i / MORPH_CHORDS) + 1) % moog_order.size]} #{(chord_i % MORPH_CHORDS) * 100 / MORPH_CHORDS}%"
          bass_patch = P.fetch(BASSES[(chord_i / 4) % BASSES.size])
          voicing.each { |m| voices << voice(m, pad, next_chord, CHORD_LEN - 0.1, 0.3, bass: :pad) }
          # The second layer, crossfaded against the first on a rhythm: the preset
          # two stops further round the Moog wheel, so the two never sound alike.
          pad_b = MOOG_CHORDS.fetch(moog_order[((chord_i / MORPH_CHORDS) + 2) % moog_order.size])
          voicing.each { |m| voices << voice(m, pad_b, next_chord, CHORD_LEN - 0.1, 0.3, bass: :pad_b) } if CUTS_ON
          # The rolling bass: the root on the three sixteenths after every kick,
          # short and even, the octave up on the last of each beat now and then.
          (CHORD_LEN / (BAR / 8)).round.times do |beat|
            [1, 2, 3].each do |sixteenth|
              up = sixteenth == 3 && rng.rand < 0.25 ? 12 : 0
              voices << voice(bass + up, bass_patch, next_chord + (beat * BAR / 8) + (sixteenth * DFAM_STEP), DFAM_STEP * 0.6, 0.4, bass: true)
            end
          end
          log.puts "#{Time.now.strftime("%H:%M:%S")} #{name} on #{pad_name}, bass #{BASSES[(chord_i / 4) % BASSES.size]}"
          if LEADS_ON && (LEAD_ALWAYS || rng.rand < 0.3)
            # The loved lead, dry: an arpeggio over the chord an octave up, its shape
            # drawn fresh, a new patch every four notes across every lead the synth has.
            arp_patches = RHODES_LEADS.keys.shuffle(random: rng)
            # An octave lower than before, and always climbing: the chord, then the
            # chord an octave up, arped upward.
            order = (voicing + voicing.map { |m| m + 12 }).sort
            step = BAR / 16
            16.times { |k| voices << voice(order[k % order.size], P.fetch(arp_patches[(k / 4) % arp_patches.size]), next_chord + (k * step), step * 0.7, 0.18, bass: :arp) }
            log.puts "  arp over it"
          end
          chord_i += 1
          next_chord += CHORD_LEN
        end
        n = BLOCK
        left = Array.new(n, 0.0)
        arp_l = Array.new(n, 0.0)
        arp_r = Array.new(n, 0.0)
        right = Array.new(n, 0.0)
        pad_l = Array.new(n, 0.0)
        padb_l = Array.new(n, 0.0)
        padb_r = Array.new(n, 0.0)
        pad_r = Array.new(n, 0.0)
        tb = frame.to_f / RATE
        ck = cutoff_knob(tb)
        rk = res_knob(tb)
        voices.each do |v|
          spec = v.spec
          rel = spec[:amp].release
          next if tb + (n.to_f / RATE) < v.start || tb > v.start + v.held + rel
          level = 1.0 / spec[:waves].size
          freqs = spec[:waves].each_index.map { |k| v.hz * (2.0**spec[:octaves][k]) * (2.0**(spec[:detune][k] / 1200.0)) }
          base_cut = spec[:cutoff] * (v.bass == true ? 0.7 + ck * 0.8 : 0.35 + ck * 1.6)
          res = v.bass == true ? spec[:resonance] : [spec[:resonance] + rk * 0.45, 0.85].min
          # The envelopes at control rate, every 16 samples: inaudible, and half the
          # cost that had the player at 100% of a core and dropping blocks.
          waves = spec[:waves]
          nw = waves.size
          out_l, out_r = case v.bass
                         when :arp then [arp_l, arp_r]
                         when :pad then [pad_l, pad_r]
                         when :pad_b then [padb_l, padb_r]
                         else [left, right]
                         end
          cut = ampv = 0.0
          j = 0
          while j < n
            t = tb + (j.to_f / RATE) - v.start
            if t >= 0
              if (j & 15).zero?
                shape = spec[:filter_env].at(t, v.held)
                shape = (shape * (1.0 - spec[:lpg])) + (spec[:amp].at(t, v.held) * spec[:lpg]) if spec[:lpg]
                cut = (base_cut + (spec[:env_amount] * shape)).clamp(30.0, 12_000.0)
                ampv = spec[:amp].at(t, v.held) * v.gain
              end
              raw = 0.0
              k = 0
              while k < nw
                v.phases[k] = (v.phases[k] + (freqs[k] / RATE)) % 1.0
                raw += S.wave(waves[k], v.phases[k]) * level
                k += 1
              end
              out = v.ladder.process(raw * spec[:drive], cut, res) * ampv
              out_l[j] += out * 0.52
              out_r[j] += out * 0.48
            end
            j += 1
          end
        end
      voices.reject! { |v| tb > v.start + v.held + v.spec[:amp].release }

      # Sequence the DFAM a block ahead, on its own clock. Every two to six bars
      # a new groove is drawn: one of the four named ones or a fresh Euclidean
      # pattern, at a rate of its own against the steady kick -- sixteenths,
      # triplets, thirty-seconds, dotted sixteenths or eighths. While it plays,
      # its pitches and its rotation keep mutating.
      while dfam_next < tb + (n.to_f / RATE)
        if dfam_scene.nil? || dfam_next >= next_scene_at
          dfam_scene = new_scene.(dfam_scene && dfam_scene[:kind])
          next_scene_at = dfam_next + ((BAR / 2) * dfam_rng.rand(2..6))
          log.puts "  dfam groove -> #{dfam_scene[:label]}"
        end
        step_len = DFAM_STEP * dfam_scene[:rate]
        hz = ->(p) { 32.0 * (2.0**(p / 100.0 * 4.0)) }
        add = ->(at, p, vel, pan) { dfam_hits << DfamHit.new(at, hz.(p), vel, 0.0, 0.0, S::Ladder.new(rate: RATE), pan) }
        pitches = dfam_scene[:pitches]
        case dfam_scene[:kind]
        when :generated
          if dfam_scene[:hits][dfam_step % dfam_scene[:hits].size]
            add.(dfam_next, pitches[dfam_step % pitches.size], dfam_rng.rand < 0.25 ? 1.1 : dfam_rng.rand(0.5..0.85), dfam_rng.rand(0.25..0.75))
          end
        when :euclid
          add.(dfam_next, pitches[dfam_step % pitches.size], 1.0, 0.45) if euclid(5, 16)[dfam_step % 16]
        when :ratchet
          if (dfam_step % 6).zero? || dfam_rng.rand < 0.12
            reps = dfam_rng.rand(2..4)
            p0 = dfam_rng.rand(25..45)
            reps.times { |r| add.(dfam_next + (r * step_len / 2), p0 - (r * 12), 0.9 - (r * 0.15), 0.3 + (0.4 * (r % 2))) }
          end
        when :broken
          add.(dfam_next, pitches[6 - (dfam_step % 7)] || pitches.first, dfam_rng.rand(0.4..1.0), dfam_rng.rand(0.2..0.8)) if dfam_rng.rand < 0.6
        when :tribal
          t12 = dfam_step % 12
          add.(dfam_next, pitches[t12 % pitches.size], [0, 3, 6].include?(t12) ? 1.1 : 0.6, 0.35 + (0.3 * (t12 % 2))) if euclid(7, 12)[t12]
        end
        # The mutation: now and then a pitch redrawn, the pattern turned a step.
        pitches[dfam_rng.rand(pitches.size)] = dfam_rng.rand(5..45) if dfam_rng.rand < 0.07
        dfam_scene[:hits] = dfam_scene[:hits].rotate(1) if dfam_rng.rand < 0.03
        dfam_step += 1
        dfam_next += step_len
      end
      # The industrial grid, after Attack Magazine's dissection: the kick four
      # on the floor, a closed hat on each offbeat, a shaker on every second
      # offbeat, a noise snare on two and four. The DFAM is the syncopated low tom.
      while grid_next < tb + (n.to_f / RATE)
        s16 = grid_step % 16
        kicks << grid_next if KICKS_ON && (s16 % 4).zero?
        hats << [grid_next, HAT_CLOSED, 0.9] if s16 % 4 == 2
        hats << [grid_next + 0.004, SHAKER, 0.6] if [6, 14].include?(s16)
        claps << grid_next if [4, 12].include?(s16)
        grid_step += 1
        grid_next += DFAM_STEP
      end
      kv = DFAM_KNOBS.transform_values { |k| k.step(n.to_f / RATE, tb) }
      if tb > next_gesture
        name = DFAM_KNOBS.keys.sample(random: knob_rng)
        target = knob_rng.rand < 0.5 ? knob_rng.rand(0.0..0.15) : knob_rng.rand(0.85..1.0)
        DFAM_KNOBS[name].lean(target, BAR * knob_rng.rand(0.5..1.5), tb)
        log.puts "  dfam: #{name} -> #{target > 0.5 ? "up" : "down"}"
        next_gesture = tb + knob_rng.rand(6.0..16.0)
      end
      vcf = kv[:vcf_decay]
      vca = kv[:vca_decay]
      cut_top = kv[:cutoff]
      dfam_hits.each do |h|
        pitch_env = cut = amp = 0.0
        j = 0
        while j < n
          tt = tb + (j.to_f / RATE) - h.start
          if tt >= 0
            if (j & 15).zero?
              pitch_env = 1.0 + (kv[:pitch_amount] * Math.exp(-tt / kv[:pitch_decay]))
              cut = 120.0 + (cut_top * Math.exp(-tt / vcf))
              amp = h.vel * Math.exp(-tt / vca) * DFAM_LEVEL
            end
            h.ph1 = (h.ph1 + (h.f0 * pitch_env / RATE)) % 1.0
            tri = S.wave(:triangle, h.ph1)
            h.ph2 = (h.ph2 + (h.f0 * 1.5 * pitch_env * (1.0 + (kv[:fm] * tri)) / RATE)) % 1.0
            sq = h.ph2 < 0.5 ? 1.0 : -1.0
            mix = (0.55 * tri) + (0.3 * sq) + (kv[:noise] * (rand * 2.0 - 1.0))
            out = h.ladder.process(mix, cut, kv[:resonance]) * amp
            left[j] += out * h.pan
            right[j] += out * (1.0 - h.pan)
          end
          j += 1
        end
      end
      dfam_hits.reject! { |h| tb - h.start > vca * 8 }
        bar = (tb / (BAR / 2)).floor
      if bar != cut_bar
        cut_bar = bar
      cut_name = CUTS.keys.sample(random: rng)
      bar_start = bar * (BAR / 2)
      beat = 4 * DFAM_STEP
      if (bar % 8) == 7 && rng.rand < 0.5
        deck_fx = [:spinback, bar_start + (3 * beat)]
        log.puts "  deck: spinback"
      elsif rng.rand < 0.12
        deck_fx = [:tape_stop, bar_start + (3 * beat)]
        log.puts "  deck: tape stop"
      end
      dub_throw = rng.rand < 0.25
      log.puts "  deck: dub throw" if dub_throw
        log.puts "  pads cut -> #{cut_name}"
      end
      cut = CUTS[cut_name]
      j = 0
      while j < n
        now = tb + (j.to_f / RATE)
        bus = 0.0
        duck = 0.0
        kicks.each do |t|
          tk = now - t
          next if tk.negative? || tk > 0.5
          d = Math.exp(-tk / 0.12)
          duck = d if d > duck
          phase = (50.0 * tk) + (170.0 * 0.012 * (1.0 - Math.exp(-tk / 0.012))) + (30.0 * 0.08 * (1.0 - Math.exp(-tk / 0.08)))
          bus += Math.sin(2 * Math::PI * phase) * Math.exp(-tk / 0.34)
          if tk < 0.003
            click_lp += 0.35 * ((rand * 2.0 - 1.0) - click_lp)
            bus += (click_lp * 1.2) + (tk < 0.0008 ? 0.6 : 0.0)
          end
        end
        # Driven into hard clipping and back: the distorted industrial kick.
        k = Math.tanh(Math.tanh(bus * 7.0) * 2.5)
        k = (k * 256).round / 256.0 * KICK_LEVEL # a bitcrusher for the crisp attack
        wet = 0.0
        c = 0
        while c < 3
          buf = COMBS[c]
          y = buf[comb_i[c]]
          buf[comb_i[c]] = k + (y * 0.8)
          comb_i[c] = (comb_i[c] + 1) % buf.size
          wet += y
          c += 1
        end
        rum_lp1 += RUM_A * (Math.tanh(wet * 12.0) - rum_lp1)
        rum_lp2 += RUM_A * (rum_lp1 - rum_lp2)
        rumble = rum_lp2 * RUMBLE_LEVEL * (1.0 - (0.9 * duck))
        metal = 0.0
        hats.each do |t, open, vel|
          idx = ((now - t) * RATE).to_i
          table = open
          metal += table[idx] * vel if idx >= 0 && idx < table.size
        end
        hat_lp += HAT_A * (metal - hat_lp)
        # Crushed to 12 bits and overdriven, the SP-1200 resample.
        hat = Math.tanh(((metal - hat_lp) * 32).round / 32.0 * 0.5) * 2.0 * HAT_LEVEL
        clap = 0.0
        claps.each do |t|
          tc = now - t
          next if tc.negative? || tc > 0.35
          burst = (1.0 - Math.exp(-tc / 0.004)) * Math.exp(-tc / 0.11)
          clap += ((rand * 2.0) - 1.0) * burst
        end
        clap_lp += 0.18 * (Math.tanh(clap * 2.5) - clap_lp)
        clap_hp += 0.05 * (clap_lp - clap_hp)
        drums = k + hat + ((clap_lp - clap_hp) * CLAP_LEVEL)
        # Parallel distortion on the drum bus: grit blended under the clean hits.
        drums += Math.tanh(drums * 12.0) * 0.025
        # The pads pump against the kick.
        pump = 1.0 - (0.25 * duck)

      deck = CUTS_ON ? cut[(now / (DFAM_STEP / 2)).floor % 32] : "A"
      gain_a += CUT_GLIDE * ((deck == "A" ? 1.0 : 0.0) - gain_a)
      gain_b += CUT_GLIDE * ((deck == "B" ? 1.0 : 0.0) - gain_b)
      pl = (pad_l[j] * gain_a) + (padb_l[j] * gain_b)
      pr = (pad_r[j] * gain_a) + (padb_r[j] * gain_b)
      # Baby scratches: a third of the cuts that open the fader get a hand on it.
      s32 = (now / (DFAM_STEP / 2)).floor
      if s32 != last_s32
        deck_fx = [:baby, now] if last_deck == "-" && deck != "-" && deck_fx.nil? && rng.rand < 0.12
        last_s32 = s32
        last_deck = deck
      end
      deck_l[deck_w] = pl
      deck_r[deck_w] = pr
      d = 0.0
      deck_gain = 1.0
      if deck_fx && now >= deck_fx[1]
        x = now - deck_fx[1]
        case deck_fx[0]
        when :baby
          len = DFAM_STEP
          if x < len
            d = 0.008 * (1.0 - Math.cos(2 * Math::PI * x / len)) / 2.0
          else
            deck_fx = nil
          end
        when :tape_stop
          len = 4 * DFAM_STEP
          if x < len
            d = x * x / (2.0 * len)
            deck_gain = 1.0 - (x / len)
          else
            deck_fx = nil
          end
        when :spinback
          if x < 0.5
            d = x < 0.1 ? 20.0 * x * x : 0.2 + (4.0 * (x - 0.1))
            deck_gain = 1.0 - (x / 0.5)
          else
            deck_fx = nil
          end
        end
      end
      if d.positive?
        pos = deck_w - (d * RATE)
        i0 = pos.floor
        frac = pos - i0
        a = i0 % DECK_LEN
        b = (i0 + 1) % DECK_LEN
        pl = ((deck_l[a] * (1.0 - frac)) + (deck_l[b] * frac)) * deck_gain
        pr = ((deck_r[a] * (1.0 - frac)) + (deck_r[b] * frac)) * deck_gain
      elsif deck_gain < 1.0
        pl *= deck_gain
        pr *= deck_gain
      end
      deck_w = (deck_w + 1) % DECK_LEN
      # The dub throw: the send opens for the bar's last eighth.
      bar_pos = (now % (BAR / 2)) / (BAR / 2)
      dub_send += 0.002 * ((dub_throw && bar_pos > 0.875 ? 1.0 : 0.0) - dub_send)
      el = dub_l[(dub_w - DUB_DELAY) % DUB_LEN]
      er = dub_r[(dub_w - DUB_DELAY) % DUB_LEN]
      dub_lp_l += DUB_LP * (el - dub_lp_l)
      dub_lp_r += DUB_LP * (er - dub_lp_r)
      dub_hp_l += DUB_HP * (dub_lp_l - dub_hp_l)
      dub_hp_r += DUB_HP * (dub_lp_r - dub_hp_r)
      dub_l[dub_w] = (pl * dub_send) + ((dub_lp_r - dub_hp_r) * 0.6) # crossed: the echo walks
      dub_r[dub_w] = (pr * dub_send) + ((dub_lp_l - dub_hp_l) * 0.6)
      dub_w = (dub_w + 1) % DUB_LEN
      pl += (dub_lp_l - dub_hp_l) * 0.7
      pr += (dub_lp_r - dub_hp_r) * 0.7
      left[j] += (pl * pump) + drums + rumble
      right[j] += (pr * pump) + drums + rumble
      # The Crystallizer on the lead.
      cl = crys_out_l = 0.0
      cr = crys_out_r = 0.0
      2.times do |g|
        ph = (crys_p + (g * CRYS_GRAIN / 2)) % CRYS_GRAIN
        win = 0.5 - (0.5 * Math.cos(2 * Math::PI * ph / CRYS_GRAIN))
        at = (crys_w - CRYS_DELAY - ((CRYS_GRAIN - ph) * crys_pitch).to_i) % CRYS_LEN
        cl += crys_l[at] * win
        cr += crys_r[at] * win
      end
      crys_l[crys_w] = arp_l[j] + (cr * CRYS_FEEDBACK) # crossed, so the shimmer walks the field
      crys_r[crys_w] = arp_r[j] + (cl * CRYS_FEEDBACK)
      crys_w = (crys_w + 1) % CRYS_LEN
      crys_p += 1
      if crys_p >= CRYS_GRAIN * 24 # every few seconds, a fifth or an octave
        crys_p = 0
        crys_pitch = [2.0, 1.5, 2.0].sample(random: rng)
      end
      arp_l[j] += cl * CRYS_MIX
      arp_r[j] += cr * CRYS_MIX
      j += 1
      end
      kicks.reject! { |t| tb - t > 0.5 }
      hats.reject! { |t, _, _| tb - t > 0.1 }
      claps.reject! { |t| tb - t > 0.35 }
      pcm = Array.new(n * 4)
      n.times do |i|
        pcm[i * 4] = (Math.tanh(left[i]) * 29_000).round
        pcm[(i * 4) + 1] = (Math.tanh(right[i]) * 29_000).round
        pcm[(i * 4) + 2] = (Math.tanh(arp_l[i] * 1.4) * 26_000).round
        pcm[(i * 4) + 3] = (Math.tanh(arp_r[i] * 1.4) * 26_000).round
      end
      sox.write(pcm.pack("s<*"))
        frame += n
      end
      sox.close
    end
  end

  module Liveset5aa16356c296
    # takes/liveset_5aa16356c296.rb, frozen as heard (sha256 13eb699bf2659c71960133c847b3bf93cb9c75170050152f2655c4eeb181bff2).

    # MASTER's main sound, improvising live and endless: soul-jazz harmony chosen
    # chord by chord, each voiced nearest the last, the key moving on its own.
    # The chords play only Moog presets on dilla's ladder, morphing over four
    # chords, on two decks at once, and a turntablist's sharp-curve crossfader
    # cuts between the decks on the thirty-second grid: transformer, crab,
    # chirp, orbit, flare, tear, a new cut every bar. Under them the rolling Moog
    # bass, an industrial grid at 128 BPM and the DFAM, always changing. Kicks
    # and leads sit switched off at the operator's word: KICKS_ON and LEADS_ON.

    RATE = 32_000
    BLOCK = 1_024
    S = AnalogSynth
    P = S::PATCHES.dup

    def self.hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

    # Fm9, Bbm9, Eb13, Abmaj9, Dbmaj7#11, C7alt: soul-jazz, Dilla territory.
    CHORDS = [
      [41, [56, 60, 63, 67]], [46, [56, 61, 65, 68]], [39, [55, 60, 61, 65]],
      [44, [55, 60, 63, 70]], [37, [60, 65, 67, 72]], [36, [58, 61, 64, 68]],
    ]
    SNAP = { amp: S::Envelope.new(attack: 0.004, decay: 0.3, sustain: 0.35, release: 0.18),
             filter_env: S::Envelope.new(attack: 0.002, decay: 0.22, sustain: 0.2, release: 0.15) }.freeze
    PROPHET_LEADS = {
      prophet_five_lead: P[:prophet_five].merge(SNAP),
      prophet_pad_lead: P[:prophet_pad].merge(SNAP),
      prophet_poly: P[:poly_lead].merge(SNAP),
      prophet_bright: P[:prophet_five].merge(SNAP).merge(cutoff: 900.0, resonance: 0.42),
    }.freeze
    P.merge!(PROPHET_LEADS)
    # The Rhodes leads: dilla's two electric pianos, and each a shade brighter
    # and darker.
    RHODES_LEADS = {
      rhodes_tine: P[:rhodes_tine], e_piano: P[:e_piano],
      rhodes_bright: P[:rhodes_tine].merge(cutoff: P[:rhodes_tine][:cutoff] * 1.6),
      e_piano_dark: P[:e_piano].merge(cutoff: P[:e_piano][:cutoff] * 0.65),
    }.freeze
    P.merge!(RHODES_LEADS)
    # Moog chord presets, on dilla's ladder: the chords play only these, the
    # patch morphing from one to the next without a seam -- cutoff, resonance,
    # envelope depth, drive and detune all glide; the waves change at halfway.
    MOOG_ENV = { amp: P[:warm_pad][:amp], filter_env: P[:warm_pad][:filter_env] }.freeze
    MOOG_CHORDS = {
      minimoog_pad: { waves: %i[saw square triangle], detune: [0.0, -6.0, 7.0], octaves: [0, 0, -1], cutoff: 620.0, env_amount: 1400.0, resonance: 0.42, drive: 1.1 },
      memorymoog_brass: { waves: %i[saw saw saw], detune: [-9.0, 0.0, 9.0], octaves: [0, 0, 0], cutoff: 760.0, env_amount: 1900.0, resonance: 0.3, drive: 1.2 },
      polymoog_vox: { waves: %i[square square saw], detune: [-4.0, 5.0, 0.0], octaves: [0, 1, 0], cutoff: 900.0, env_amount: 700.0, resonance: 0.24, drive: 0.95 },
      moog_one_strings: { waves: %i[saw saw saw], detune: [-14.0, 0.0, 13.0], octaves: [0, 0, 1], cutoff: 1150.0, env_amount: 800.0, resonance: 0.2, drive: 0.9 },
      sub37_warm: { waves: %i[saw square saw], detune: [0.0, 4.0, -5.0], octaves: [0, -1, 0], cutoff: 480.0, env_amount: 1600.0, resonance: 0.55, drive: 1.3 },
    }.transform_values { |p| p.merge(MOOG_ENV) }.freeze
    # Four chords to travel from one preset to the next, in a fresh order each lap.
    MORPH_CHORDS = 4
    def self.moog_morph(order, chord_i)
      pos = chord_i.to_f / MORPH_CHORDS
      a = MOOG_CHORDS.fetch(order[pos.floor % order.size])
      b = MOOG_CHORDS.fetch(order[(pos.floor + 1) % order.size])
      x = pos - pos.floor
      lerp = ->(k) { a[k] + ((b[k] - a[k]) * x) }
      (x < 0.5 ? a : b).merge(cutoff: lerp.(:cutoff), env_amount: lerp.(:env_amount), resonance: lerp.(:resonance),
                               drive: lerp.(:drive), detune: a[:detune].each_index.map { |i| a[:detune][i] + ((b[:detune][i] - a[:detune][i]) * x) })
    end
    PADS = %i[warm_pad poly_strings prophet_five juno_pad prophet_pad vp330_ensemble soft_reed e_piano rhodes_tine glass_bell]
    BASSES = %i[moog_bass acid sub dub_bass]
    QUALITIES = {
      m9: [3, 7, 10, 14], m11: [3, 7, 10, 17], maj9: [4, 7, 11, 14], maj7s11: [4, 7, 11, 18],
      d13: [4, 10, 14, 21], alt: [4, 10, 13, 15], m6_9: [3, 7, 9, 14], sus13: [5, 10, 14, 21],
    }.freeze
    MOVES = {
      [0, :m9] => [[5, :m9], [10, :d13], [8, :maj9], [5, :m11], [3, :maj9]],
      [0, :m11] => [[5, :m9], [8, :maj7s11], [10, :sus13]],
      [5, :m9] => [[10, :d13], [7, :alt], [3, :maj9], [0, :m6_9]],
      [5, :m11] => [[10, :d13], [7, :alt]],
      [10, :d13] => [[3, :maj9], [8, :maj9], [0, :m9]],
      [10, :sus13] => [[10, :d13], [3, :maj9]],
      [3, :maj9] => [[8, :maj9], [5, :m9], [1, :maj7s11]],
      [8, :maj9] => [[1, :maj7s11], [7, :alt], [5, :m9]],
      [8, :maj7s11] => [[7, :alt], [1, :maj7s11]],
      [1, :maj7s11] => [[7, :alt], [0, :m9], [0, :m11]],
      [7, :alt] => [[0, :m9], [0, :m11], [8, :maj9]],
      [0, :m6_9] => [[5, :m9], [10, :d13]],
    }.freeze
    NAMES = %w[C Db D Eb E F Gb G Ab A Bb B].freeze

    def self.voice_lead(pcs, previous)
      pcs.each_with_index.map do |pc, idx|
        centre = previous[idx] || previous.last
        (53..74).select { |m| m % 12 == pc }.min_by { |m| (m - centre).abs }
      end.sort.uniq
    end
    # Industrial techno, ten below the 128 BPM it started at (Attack Magazine:
    # 126-130), at the operator's word. BAR is two bars, eight beats.
    BPM = 118
    BAR = 8 * 60.0 / BPM
    CHORD_LEN = BAR

    Voice = Struct.new(:hz, :spec, :start, :held, :gain, :phases, :ladder, :bass)

    def self.voice(midi, spec, start, held, gain, bass: false)
      rng = Random.new(midi * 7 + (start * 10).to_i)
      Voice.new(hz(midi) * 2.0**(rng.rand(-0.7..0.7) / 1200.0), spec, start, held, gain,
                spec[:waves].map { rng.rand }, S::Ladder.new(rate: RATE), bass)
    end

    # The knobs: cutoff breathes over 23 s, resonance over 31 s, out of phase.
    def self.cutoff_knob(t) = 0.55 + 0.45 * Math.sin(2 * Math::PI * t / 23.0)
    def self.res_knob(t) = 0.5 + 0.5 * Math.sin(2 * Math::PI * t / 31.0 + 1.3)

    # The DFAM, as the Moog is built: an 8-step sequencer, each step its own pitch
    # and velocity, running in sixteenths; VCO 1 a triangle frequency-modulating
    # VCO 2, a square; both with a pitch envelope that falls; noise mixed in; all
    # of it through a ladder low-pass with its own decay, then the VCA's decay.
    # The pattern starts from dilla's DfamEngine and one step mutates every two
    # bars; decay and cutoff drift slowly, like the pads' knobs.
    DFAM_STEP = BAR / 32 # sixteenths
    DFAM_LEVEL = 0.16
    # Accents on the eight-step page: the downbeat and the and-of-two lean in.
    DFAM_SCENES = %i[euclid ratchet broken tribal].freeze
    # Each groove brings its own kick, as [cycle length, steps that hit].
    SCENE_KICKS = { euclid: [16, [0, 6, 10]], ratchet: [12, [0, 7]], broken: [16, [0, 3, 10, 11]], tribal: [12, [0, 5, 8]] }.freeze
    DFAM_RATES = { 1.0 => "16ths", (2.0 / 3) => "triplets", 0.5 => "32nds", 1.5 => "dotted 16ths", 2.0 => "8ths" }.freeze
    # A Euclidean rhythm: k hits spread as evenly as n steps allow.
    def self.euclid(k, n) = (@euclid ||= {})[[k, n]] ||= Array.new(n) { |i| ((i * k) % n) < k }
    # And its own lead rhythm, on sixteen steps.
    SCENE_LEAD = { euclid: euclid(5, 16), ratchet: euclid(6, 16), broken: Array.new(16) { |i| [0, 3, 6, 10, 12].include?(i) }, tribal: euclid(7, 16) }.freeze
    ACCENT = [1.35, 0.8, 1.0, 0.85, 1.25, 0.8, 1.1, 0.9].freeze
    KICK_LEVEL = 0.06
    # Off at the operator's word, and with them the rumble and the pump.
    KICKS_ON = false
    # The lead plays over every chord, at the operator's word.
    LEAD_ALWAYS = true
    # Muted at the operator's word; true brings the leads back.
    LEADS_ON = false
    # Turntablism on the pads: a scratch DJ's sharp-curve crossfader, two decks
    # (the two Moog layers) cut hard on the thirty-second grid. Each pattern is
    # 32 steps, one bar: A is deck A open, B deck B, - the fader closed. The
    # fader moves in half a millisecond, so every cut is a cut, not a blend.
    CUTS = {
      transformer: "A-A-A-A-A-A-A-A-A-A-A-A-A-A-A-A-",
      slow_transformer: "AA--AA--AA--AA--BB--BB--BB--BB--",
      crab: "A-A-A-A-AAAAAAAAB-B-B-B-BBBBBBBB",
      chirp: "AAA-----AAA-----BBB-----BBB-----",
      orbit: "A--AA--AA--AA--AB--BB--BB--BB--B",
      flare: "AAAA-AAA-AAAAAAAAAAA-AAA-AAAAAAA",
      ab_chop: "AAAABBBBAAAABBBB--AABB--AABBAB--",
      tear: "AAAAAAAA--------A-A-AAAA--------",
    }.freeze
    CUT_GLIDE = 1.0 - Math.exp(-1.0 / (0.0005 * RATE))
    # The Crystallizer, after Soundtoys: reversed grains of the lead, pitched up
    # an octave or a fifth, a quarter second late, fed back into themselves.
    # Two readers half a grain apart, Hann-windowed, crossfade into a shimmer.
    CRYS_LEN = RATE * 2
    CRYS_GRAIN = (RATE * 0.16).round
    CRYS_DELAY = (RATE * 0.25).round
    CRYS_FEEDBACK = 0.45
    CRYS_MIX = 0.5
    # The 909's hat: six detuned square waves, high-passed, then crushed to 12
    # bits the way an SP-1200 resample crunches it.
    HAT_HZ = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0].freeze
    HAT_LEVEL = 0.011
    # Rendered once: the squares, noise under them for grit, and the decay.
    hat_table = lambda do |len, decay|
      Array.new((len * RATE).to_i) do |i|
        th = i.to_f / RATE
        sq = HAT_HZ.sum { |f| ((th * f * 7.0) % 1.0) < 0.5 ? 1.0 : -1.0 }
        (sq + (((rand * 2.0) - 1.0) * 3.0)) * Math.exp(-th / decay)
      end.freeze
    end
    HAT_OPEN = hat_table.(0.3, 0.07)
    HAT_CLOSED = hat_table.(0.06, 0.015)
    # The shaker: noise alone, short, high-passed with the hats.
    SHAKER = Array.new((0.08 * RATE).to_i) { |i| ((rand * 2.0) - 1.0) * 2.0 * Math.exp(-i.to_f / RATE / 0.025) }.freeze
    CLAP_LEVEL = 0.08
    # The rumble: the kick sent into a dark reverb (three combs), distorted,
    # low-passed to 150 Hz, mono, and ducked by the kick itself.
    RUMBLE_LEVEL = 0.05
    COMBS = [1123, 1409, 1693].map { |len| Array.new(len, 0.0) }
    RUM_A = 1.0 - Math.exp(-2 * Math::PI * 150.0 / RATE)
    HAT_A = 1.0 - Math.exp(-2 * Math::PI * 7000.0 / RATE)
    DfamHit = Struct.new(:start, :f0, :vel, :ph1, :ph2, :ladder, :pan)
    class DfamKnob
      attr_reader :value
      def initialize(lo, hi, rng, speed:)
        @lo, @hi, @rng, @speed = lo, hi, rng, speed
        @x = 0.5
        @v = 0.0
        @push = nil
      end
      # A gesture: toward `target` (0..1) for `seconds`, then released.
      def lean(target, seconds, now) = @push = [target, now + seconds]
      def step(dt, now)
        @push = nil if @push && now > @push[1]
        pull = @push ? (@push[0] - @x) * 1.5 : (0.5 - @x) * 0.03
        @v = (@v * 0.992) + (@rng.rand(-1.0..1.0) * @speed * dt) + (pull * dt)
        @x = (@x + (@v * dt)).clamp(0.0, 1.0)
        @value = @lo + ((@hi - @lo) * @x)
      end
    end

    knob_rng = Random.new
    DFAM_KNOBS = {
      vcf_decay: DfamKnob.new(0.03, 0.22, knob_rng, speed: 0.08),
      vca_decay: DfamKnob.new(0.06, 0.28, knob_rng, speed: 0.07),
      cutoff: DfamKnob.new(500.0, 4200.0, knob_rng, speed: 0.1),
      resonance: DfamKnob.new(0.2, 0.85, knob_rng, speed: 0.06),
      fm: DfamKnob.new(0.0, 1.1, knob_rng, speed: 0.07),
      noise: DfamKnob.new(0.02, 0.45, knob_rng, speed: 0.05),
      pitch_amount: DfamKnob.new(0.6, 4.0, knob_rng, speed: 0.06),
      pitch_decay: DfamKnob.new(0.015, 0.12, knob_rng, speed: 0.05),
    }.freeze
    def self.sonitex(bits:, lo:, hi:, drive:, mix: 0.5, samples: 1)
      "volume=#{drive},acrusher=bits=#{bits}:mode=log:aa=1:mix=#{mix}:samples=#{samples}," \
        "highpass=f=#{lo},lowpass=f=#{hi},alimiter=limit=0.99"
    end

    # Level-neutral here: five stages at livesets' -7.5 dB each sank the pads 37 dB
    # under the kick. The colour stays; the loss does not.
    def self.vcs(depth:, smear:, db: 0.0)
      phaser_db = -2.6 + (10.9 * (depth - 0.26)) - (0.14 * (smear - 2.1))
      "aphaser=in_gain=0.75:out_gain=0.85:delay=#{smear}:decay=#{depth}:speed=0.5," \
        "aecho=0.9:1:#{smear.round}:0.08,volume=#{(db - phaser_db + 0.65).round(2)}dB"
    end

    MASTER = [
      vcs(depth: 0.34, smear: 2.4), sonitex(bits: 12, lo: 40, hi: 13_000, drive: 1.12),
      vcs(depth: 0.38, smear: 1.7), sonitex(bits: 13, lo: 42, hi: 15_000, drive: 1.04),
      vcs(depth: 0.26, smear: 3.6), sonitex(bits: 11, lo: 42, hi: 12_000, drive: 1.18),
      "alimiter=limit=0.95"
    ].join(",")
    def self.space_echo(head_ms, decays)
      taps = [1, 2, 3].map { |k| (head_ms * k).round }.join("|")
      "highpass=f=160,aecho=0.9:0.9:#{taps}:#{decays},lowpass=f=3200,chorus=0.9:0.9:25:0.35:0.6:1.8"
    end
    HEAD = BAR / 16 * 1000
    ARP_FX = "anull"
    # Extreme analog tape on the master channel, the whole sum: the head bump near
    # 60 Hz, the drive into tanh that tape saturation is (undone after, so it
    # colours rather than raises), the capstan's wow and flutter worn deep, the top
    # the tape cannot hold, and its hiss.
    def self.tape(drive:, wow:, flutter:, top:, hiss:)
      "equalizer=f=60:t=q:w=1.1:g=4.5,volume=#{drive},asoftclip=type=tanh,volume=#{(1.0 / drive).round(3)}," \
        "vibrato=f=0.42:d=#{wow},vibrato=f=6.8:d=#{flutter},lowpass=f=#{top},highpass=f=28," \
        "aeval=exprs=val(0)+#{hiss}*(2*random(0)-1)|val(1)+#{hiss}*(2*random(1)-1):c=same"
    end
    TAPE = tape(drive: 3.2, wow: 0.22, flutter: 0.07, top: 9_500, hiss: 0.004)
    # Arps on the arps, at the operator's word: the lead is split three ways. One
    # stays dry; one goes up a fifth and comes back an eighth late, the other up
    # an octave a dotted eighth late, so the echoes arpeggiate over the arpeggio.
    # Each pitched copy feeds back through its own echo the way a crystallizer
    # does, and the sum is sharpened with ffmpeg's crystalizer. The pitch shift is
    # asetrate then atempo, a resample and a time-stretch, which grains the copies.
    def self.pitched(ratio, delay_ms, echo_ms, decay)
      "asetrate=#{(RATE * ratio).round},aresample=#{RATE},atempo=#{(1.0 / ratio).round(4)}," \
        "adelay=#{delay_ms}|#{delay_ms},aecho=0.8:0.7:#{echo_ms}:#{decay}"
    end
    EIGHTH = (BAR / 16 * 1000).round
    ARPS_ON_ARPS = "asplit=3[ad][ax][ay];[ax]#{pitched(1.5, EIGHTH, EIGHTH * 2, 0.45)}[af];" \
                   "[ay]#{pitched(2.0, (EIGHTH * 1.5).round, EIGHTH * 3, 0.4)},highpass=f=900[ao];" \
                   "[ad][af][ao]amix=inputs=3:weights=1 0.5 0.35:normalize=0,crystalizer=i=1.5"
    # The leads sit lower in the sum, at the operator's word: 0.9 against the
    # main's 1 where they were 1.5.
    GRAPH = "[0:a]pan=stereo|c0=c0|c1=c1,#{MASTER}[m];[0:a]pan=stereo|c0=c2|c1=c3,#{ARPS_ON_ARPS}[a];[m][a]amix=inputs=2:weights=1 0.9:normalize=0,#{TAPE},alimiter=limit=0.96"

    def self.run(argv = [])
      loops = (argv[0] || 2).to_i

      voices = []
      rng = Random.new
      key = 5 # F minor, where the loved progression sits
      state = [0, :m9]
      voicing = CHORDS.first.last
      chord_i = 0
      moog_order = nil
      recent = []
      next_modulation = 8
      key = rng.rand(12)
      next_chord = 0.0
      log = File.open(File.join(__dir__, "..", "moog_improv.log"), "a").tap { |f| f.sync = true }
      total = Float::INFINITY
      pattern = { pitch: [50, 30, 60, 20, 55, 35, 65, 25], velocity: [80, 60, 90, 50, 85, 65, 95, 55] }
      dfam_rng = Random.new
      dfam_hits = []
      dfam_next = 0.0
      dfam_step = 0
      pattern_b = { pitch: [78, 64, 88, 70, 92], velocity: [55, 0, 70, 45, 60] }
      dfam_scene = nil
      next_scene_at = 0.0
      grid_next = 0.0
      grid_step = 0
      # A new groove, never the kind just played: its kind, its rate, and for a
      # generated one a Euclidean pattern of 2 to n-1 hits over 5 to 16 steps.
      new_scene = lambda do |last|
        kind = (DFAM_SCENES + %i[generated generated]).reject { |k| k == last && k != :generated }.sample(random: dfam_rng)
        rate, rate_name = DFAM_RATES.to_a.sample(random: dfam_rng)
        steps = dfam_rng.rand(5..16)
        hits = dfam_rng.rand(2..(steps - 1))
        label = kind == :generated ? "E(#{hits},#{steps}) in #{rate_name}" : "#{kind} in #{rate_name}"
        { kind:, rate:, label:, hits: euclid(hits, steps).rotate(dfam_rng.rand(steps)),
          pitches: Array.new(dfam_rng.rand(3..8)) { dfam_rng.rand(5..45) } }
      end
      kicks = []
      click_lp = 0.0
      cut_name = :transformer
      cut_bar = -1
      gain_a = 1.0
      gain_b = 0.0
      crys_l = Array.new(CRYS_LEN, 0.0)
      crys_r = Array.new(CRYS_LEN, 0.0)
      crys_w = 0
      crys_p = 0
      crys_pitch = 2.0
      crys_out_l = crys_out_r = 0.0
      hats = []
      claps = []
      hat_lp = clap_lp = clap_hp = 0.0
      comb_i = [0, 0, 0]
      rum_lp1 = rum_lp2 = 0.0
      next_gesture = 8.0

      $stderr.puts "improvising: #{PADS.join(" -> ")} over moog_bass, DFAM on top"
      sox = IO.popen(["sh", "-c", "ffmpeg -loglevel error -f s16le -ar #{RATE} -ac 4 -i - -filter_complex '#{GRAPH}' -f s16le -ar #{RATE} -ac 2 - | sox -q -t raw -r #{RATE} -e signed -b 16 -c 2 - -d"], "wb")
      frame = 0
      frames = Float::INFINITY
      two_pi = 2 * Math::PI
      while frame < frames
        # The next chord, chosen a second before it sounds.
        while next_chord < (frame.to_f / RATE) + 1.0
          degree, quality = state
          voicing = voice_lead(QUALITIES[quality].map { |iv| (key + degree + iv) % 12 }, voicing)
          bass = 36 + ((key + degree) % 12)
          bass += 12 if bass < 36
          name = "#{NAMES[(key + degree) % 12]}#{quality}"
          recent << [(key + degree) % 12, quality]
          recent.shift if recent.size > 4
          options = MOVES.fetch(state).reject { |d, q| recent.include?([(key + d) % 12, q]) }
          options = MOVES.fetch(state) if options.empty?
          state = options.sample(random: rng)
          roll = rng.rand
          if roll < 0.08 # the tritone substitute: a dominant a flat fifth away
            key = (key + 6) % 12
            name += " (tritone sub next)"
          elsif roll < 0.14 # a chromatic side-step, up or down a semitone
            key = (key + [1, 11].sample(random: rng)) % 12
            name += " (side-step next)"
          end
          if chord_i >= next_modulation
            key = (key + [5, 3, 8, 10, 2, 7].sample(random: rng)) % 12
            state = [0, %i[m9 m11 m6_9].sample(random: rng)]
            next_modulation = chord_i + rng.rand(8..16)
            name += " -> #{NAMES[key]} minor"
          end
          moog_order = MOOG_CHORDS.keys.shuffle(random: rng) if (chord_i % (MORPH_CHORDS * MOOG_CHORDS.size)).zero?
          pad = moog_morph(moog_order, chord_i)
          pad_name = "#{moog_order[(chord_i / MORPH_CHORDS) % moog_order.size]} -> #{moog_order[((chord_i / MORPH_CHORDS) + 1) % moog_order.size]} #{(chord_i % MORPH_CHORDS) * 100 / MORPH_CHORDS}%"
          bass_patch = P.fetch(BASSES[(chord_i / 4) % BASSES.size])
          voicing.each { |m| voices << voice(m, pad, next_chord, CHORD_LEN - 0.1, 0.3, bass: :pad) }
          # The second layer, crossfaded against the first on a rhythm: the preset
          # two stops further round the Moog wheel, so the two never sound alike.
          pad_b = MOOG_CHORDS.fetch(moog_order[((chord_i / MORPH_CHORDS) + 2) % moog_order.size])
          voicing.each { |m| voices << voice(m, pad_b, next_chord, CHORD_LEN - 0.1, 0.3, bass: :pad_b) }
          # The rolling bass: the root on the three sixteenths after every kick,
          # short and even, the octave up on the last of each beat now and then.
          (CHORD_LEN / (BAR / 8)).round.times do |beat|
            [1, 2, 3].each do |sixteenth|
              up = sixteenth == 3 && rng.rand < 0.25 ? 12 : 0
              voices << voice(bass + up, bass_patch, next_chord + (beat * BAR / 8) + (sixteenth * DFAM_STEP), DFAM_STEP * 0.6, 0.4, bass: true)
            end
          end
          log.puts "#{Time.now.strftime("%H:%M:%S")} #{name} on #{pad_name}, bass #{BASSES[(chord_i / 4) % BASSES.size]}"
          if LEADS_ON && (LEAD_ALWAYS || rng.rand < 0.3)
            # The loved lead, dry: an arpeggio over the chord an octave up, its shape
            # drawn fresh, a new patch every four notes across every lead the synth has.
            arp_patches = RHODES_LEADS.keys.shuffle(random: rng)
            # An octave lower than before, and always climbing: the chord, then the
            # chord an octave up, arped upward.
            order = (voicing + voicing.map { |m| m + 12 }).sort
            step = BAR / 16
            16.times { |k| voices << voice(order[k % order.size], P.fetch(arp_patches[(k / 4) % arp_patches.size]), next_chord + (k * step), step * 0.7, 0.45, bass: :arp) }
            log.puts "  arp over it"
          end
          chord_i += 1
          next_chord += CHORD_LEN
        end
        n = BLOCK
        left = Array.new(n, 0.0)
        arp_l = Array.new(n, 0.0)
        arp_r = Array.new(n, 0.0)
        right = Array.new(n, 0.0)
        pad_l = Array.new(n, 0.0)
        padb_l = Array.new(n, 0.0)
        padb_r = Array.new(n, 0.0)
        pad_r = Array.new(n, 0.0)
        tb = frame.to_f / RATE
        ck = cutoff_knob(tb)
        rk = res_knob(tb)
        voices.each do |v|
          spec = v.spec
          rel = spec[:amp].release
          next if tb + (n.to_f / RATE) < v.start || tb > v.start + v.held + rel
          level = 1.0 / spec[:waves].size
          freqs = spec[:waves].each_index.map { |k| v.hz * (2.0**spec[:octaves][k]) * (2.0**(spec[:detune][k] / 1200.0)) }
          base_cut = spec[:cutoff] * (v.bass == true ? 0.7 + ck * 0.8 : 0.35 + ck * 1.6)
          res = v.bass == true ? spec[:resonance] : [spec[:resonance] + rk * 0.45, 0.85].min
          # The envelopes at control rate, every 16 samples: inaudible, and half the
          # cost that had the player at 100% of a core and dropping blocks.
          waves = spec[:waves]
          nw = waves.size
          out_l, out_r = case v.bass
                         when :arp then [arp_l, arp_r]
                         when :pad then [pad_l, pad_r]
                         when :pad_b then [padb_l, padb_r]
                         else [left, right]
                         end
          cut = ampv = 0.0
          j = 0
          while j < n
            t = tb + (j.to_f / RATE) - v.start
            if t >= 0
              if (j & 15).zero?
                shape = spec[:filter_env].at(t, v.held)
                shape = (shape * (1.0 - spec[:lpg])) + (spec[:amp].at(t, v.held) * spec[:lpg]) if spec[:lpg]
                cut = (base_cut + (spec[:env_amount] * shape)).clamp(30.0, 12_000.0)
                ampv = spec[:amp].at(t, v.held) * v.gain
              end
              raw = 0.0
              k = 0
              while k < nw
                v.phases[k] = (v.phases[k] + (freqs[k] / RATE)) % 1.0
                raw += S.wave(waves[k], v.phases[k]) * level
                k += 1
              end
              out = v.ladder.process(raw * spec[:drive], cut, res) * ampv
              out_l[j] += out * 0.52
              out_r[j] += out * 0.48
            end
            j += 1
          end
        end
      voices.reject! { |v| tb > v.start + v.held + v.spec[:amp].release }

      # Sequence the DFAM a block ahead, on its own clock. Every two to six bars
      # a new groove is drawn: one of the four named ones or a fresh Euclidean
      # pattern, at a rate of its own against the steady kick -- sixteenths,
      # triplets, thirty-seconds, dotted sixteenths or eighths. While it plays,
      # its pitches and its rotation keep mutating.
      while dfam_next < tb + (n.to_f / RATE)
        if dfam_scene.nil? || dfam_next >= next_scene_at
          dfam_scene = new_scene.(dfam_scene && dfam_scene[:kind])
          next_scene_at = dfam_next + ((BAR / 2) * dfam_rng.rand(2..6))
          log.puts "  dfam groove -> #{dfam_scene[:label]}"
        end
        step_len = DFAM_STEP * dfam_scene[:rate]
        hz = ->(p) { 32.0 * (2.0**(p / 100.0 * 4.0)) }
        add = ->(at, p, vel, pan) { dfam_hits << DfamHit.new(at, hz.(p), vel, 0.0, 0.0, S::Ladder.new(rate: RATE), pan) }
        pitches = dfam_scene[:pitches]
        case dfam_scene[:kind]
        when :generated
          if dfam_scene[:hits][dfam_step % dfam_scene[:hits].size]
            add.(dfam_next, pitches[dfam_step % pitches.size], dfam_rng.rand < 0.25 ? 1.1 : dfam_rng.rand(0.5..0.85), dfam_rng.rand(0.25..0.75))
          end
        when :euclid
          add.(dfam_next, pitches[dfam_step % pitches.size], 1.0, 0.45) if euclid(5, 16)[dfam_step % 16]
        when :ratchet
          if (dfam_step % 6).zero? || dfam_rng.rand < 0.12
            reps = dfam_rng.rand(2..4)
            p0 = dfam_rng.rand(25..45)
            reps.times { |r| add.(dfam_next + (r * step_len / 2), p0 - (r * 12), 0.9 - (r * 0.15), 0.3 + (0.4 * (r % 2))) }
          end
        when :broken
          add.(dfam_next, pitches[6 - (dfam_step % 7)] || pitches.first, dfam_rng.rand(0.4..1.0), dfam_rng.rand(0.2..0.8)) if dfam_rng.rand < 0.6
        when :tribal
          t12 = dfam_step % 12
          add.(dfam_next, pitches[t12 % pitches.size], [0, 3, 6].include?(t12) ? 1.1 : 0.6, 0.35 + (0.3 * (t12 % 2))) if euclid(7, 12)[t12]
        end
        # The mutation: now and then a pitch redrawn, the pattern turned a step.
        pitches[dfam_rng.rand(pitches.size)] = dfam_rng.rand(5..45) if dfam_rng.rand < 0.07
        dfam_scene[:hits] = dfam_scene[:hits].rotate(1) if dfam_rng.rand < 0.03
        dfam_step += 1
        dfam_next += step_len
      end
      # The industrial grid, after Attack Magazine's dissection: the kick four
      # on the floor, a closed hat on each offbeat, a shaker on every second
      # offbeat, a noise snare on two and four. The DFAM is the syncopated low tom.
      while grid_next < tb + (n.to_f / RATE)
        s16 = grid_step % 16
        kicks << grid_next if KICKS_ON && (s16 % 4).zero?
        hats << [grid_next, HAT_CLOSED, 0.9] if s16 % 4 == 2
        hats << [grid_next + 0.004, SHAKER, 0.6] if [6, 14].include?(s16)
        claps << grid_next if [4, 12].include?(s16)
        grid_step += 1
        grid_next += DFAM_STEP
      end
      kv = DFAM_KNOBS.transform_values { |k| k.step(n.to_f / RATE, tb) }
      if tb > next_gesture
        name = DFAM_KNOBS.keys.sample(random: knob_rng)
        target = knob_rng.rand < 0.5 ? knob_rng.rand(0.0..0.15) : knob_rng.rand(0.85..1.0)
        DFAM_KNOBS[name].lean(target, BAR * knob_rng.rand(0.5..1.5), tb)
        log.puts "  dfam: #{name} -> #{target > 0.5 ? "up" : "down"}"
        next_gesture = tb + knob_rng.rand(6.0..16.0)
      end
      vcf = kv[:vcf_decay]
      vca = kv[:vca_decay]
      cut_top = kv[:cutoff]
      dfam_hits.each do |h|
        pitch_env = cut = amp = 0.0
        j = 0
        while j < n
          tt = tb + (j.to_f / RATE) - h.start
          if tt >= 0
            if (j & 15).zero?
              pitch_env = 1.0 + (kv[:pitch_amount] * Math.exp(-tt / kv[:pitch_decay]))
              cut = 120.0 + (cut_top * Math.exp(-tt / vcf))
              amp = h.vel * Math.exp(-tt / vca) * DFAM_LEVEL
            end
            h.ph1 = (h.ph1 + (h.f0 * pitch_env / RATE)) % 1.0
            tri = S.wave(:triangle, h.ph1)
            h.ph2 = (h.ph2 + (h.f0 * 1.5 * pitch_env * (1.0 + (kv[:fm] * tri)) / RATE)) % 1.0
            sq = h.ph2 < 0.5 ? 1.0 : -1.0
            mix = (0.55 * tri) + (0.3 * sq) + (kv[:noise] * (rand * 2.0 - 1.0))
            out = h.ladder.process(mix, cut, kv[:resonance]) * amp
            left[j] += out * h.pan
            right[j] += out * (1.0 - h.pan)
          end
          j += 1
        end
      end
      dfam_hits.reject! { |h| tb - h.start > vca * 8 }
        bar = (tb / (BAR / 2)).floor
      if bar != cut_bar
        cut_bar = bar
        cut_name = CUTS.keys.sample(random: rng)
        log.puts "  pads cut -> #{cut_name}"
      end
      cut = CUTS[cut_name]
      j = 0
      while j < n
        now = tb + (j.to_f / RATE)
        bus = 0.0
        duck = 0.0
        kicks.each do |t|
          tk = now - t
          next if tk.negative? || tk > 0.5
          d = Math.exp(-tk / 0.12)
          duck = d if d > duck
          phase = (50.0 * tk) + (170.0 * 0.012 * (1.0 - Math.exp(-tk / 0.012))) + (30.0 * 0.08 * (1.0 - Math.exp(-tk / 0.08)))
          bus += Math.sin(2 * Math::PI * phase) * Math.exp(-tk / 0.34)
          if tk < 0.003
            click_lp += 0.35 * ((rand * 2.0 - 1.0) - click_lp)
            bus += (click_lp * 1.2) + (tk < 0.0008 ? 0.6 : 0.0)
          end
        end
        # Driven into hard clipping and back: the distorted industrial kick.
        k = Math.tanh(Math.tanh(bus * 7.0) * 2.5)
        k = (k * 256).round / 256.0 * KICK_LEVEL # a bitcrusher for the crisp attack
        wet = 0.0
        c = 0
        while c < 3
          buf = COMBS[c]
          y = buf[comb_i[c]]
          buf[comb_i[c]] = k + (y * 0.8)
          comb_i[c] = (comb_i[c] + 1) % buf.size
          wet += y
          c += 1
        end
        rum_lp1 += RUM_A * (Math.tanh(wet * 12.0) - rum_lp1)
        rum_lp2 += RUM_A * (rum_lp1 - rum_lp2)
        rumble = rum_lp2 * RUMBLE_LEVEL * (1.0 - (0.9 * duck))
        metal = 0.0
        hats.each do |t, open, vel|
          idx = ((now - t) * RATE).to_i
          table = open
          metal += table[idx] * vel if idx >= 0 && idx < table.size
        end
        hat_lp += HAT_A * (metal - hat_lp)
        # Crushed to 12 bits and overdriven, the SP-1200 resample.
        hat = Math.tanh(((metal - hat_lp) * 32).round / 32.0 * 0.5) * 2.0 * HAT_LEVEL
        clap = 0.0
        claps.each do |t|
          tc = now - t
          next if tc.negative? || tc > 0.35
          burst = (1.0 - Math.exp(-tc / 0.004)) * Math.exp(-tc / 0.11)
          clap += ((rand * 2.0) - 1.0) * burst
        end
        clap_lp += 0.18 * (Math.tanh(clap * 2.5) - clap_lp)
        clap_hp += 0.05 * (clap_lp - clap_hp)
        drums = k + hat + ((clap_lp - clap_hp) * CLAP_LEVEL)
        # Parallel distortion on the drum bus: grit blended under the clean hits.
        drums += Math.tanh(drums * 12.0) * 0.025
        # The pads pump against the kick.
        pump = 1.0 - (0.25 * duck)

      deck = cut[(now / (DFAM_STEP / 2)).floor % 32]
      gain_a += CUT_GLIDE * ((deck == "A" ? 1.0 : 0.0) - gain_a)
      gain_b += CUT_GLIDE * ((deck == "B" ? 1.0 : 0.0) - gain_b)
      pl = (pad_l[j] * gain_a) + (padb_l[j] * gain_b)
      pr = (pad_r[j] * gain_a) + (padb_r[j] * gain_b)
      left[j] += (pl * pump) + drums + rumble
      right[j] += (pr * pump) + drums + rumble
      # The Crystallizer on the lead.
      cl = crys_out_l = 0.0
      cr = crys_out_r = 0.0
      2.times do |g|
        ph = (crys_p + (g * CRYS_GRAIN / 2)) % CRYS_GRAIN
        win = 0.5 - (0.5 * Math.cos(2 * Math::PI * ph / CRYS_GRAIN))
        at = (crys_w - CRYS_DELAY - ((CRYS_GRAIN - ph) * crys_pitch).to_i) % CRYS_LEN
        cl += crys_l[at] * win
        cr += crys_r[at] * win
      end
      crys_l[crys_w] = arp_l[j] + (cr * CRYS_FEEDBACK) # crossed, so the shimmer walks the field
      crys_r[crys_w] = arp_r[j] + (cl * CRYS_FEEDBACK)
      crys_w = (crys_w + 1) % CRYS_LEN
      crys_p += 1
      if crys_p >= CRYS_GRAIN * 24 # every few seconds, a fifth or an octave
        crys_p = 0
        crys_pitch = [2.0, 1.5, 2.0].sample(random: rng)
      end
      arp_l[j] += cl * CRYS_MIX
      arp_r[j] += cr * CRYS_MIX
      j += 1
      end
      kicks.reject! { |t| tb - t > 0.5 }
      hats.reject! { |t, _, _| tb - t > 0.1 }
      claps.reject! { |t| tb - t > 0.35 }
      pcm = Array.new(n * 4)
      n.times do |i|
        pcm[i * 4] = (Math.tanh(left[i]) * 29_000).round
        pcm[(i * 4) + 1] = (Math.tanh(right[i]) * 29_000).round
        pcm[(i * 4) + 2] = (Math.tanh(arp_l[i] * 1.4) * 26_000).round
        pcm[(i * 4) + 3] = (Math.tanh(arp_r[i] * 1.4) * 26_000).round
      end
      sox.write(pcm.pack("s<*"))
        frame += n
      end
      sox.close
    end
  end

  module Liveset68eccd04098e
    # takes/liveset_68eccd04098e.rb, frozen as heard (sha256 fe8e97125f8e6fea11bcc00c1a6e2f819a94aeb7f5eed3c9c7483c13ce629bad).

    # MASTER's main sound, improvising live and endless: soul-jazz harmony chosen
    # chord by chord, each voiced nearest the last, the key moving on its own.
    # The chords play only Moog presets on dilla's ladder, morphing from one to
    # the next over four chords. Under them the rolling Moog bass, an industrial
    # grid at 128 BPM (offbeat hats crushed to 12 bits, a noise snare on two and
    # four) and the DFAM, drawing a new groove and rate every few bars. Kicks and
    # leads sit switched off at the operator's word: KICKS_ON and LEADS_ON.

    RATE = 32_000
    BLOCK = 1_024
    S = AnalogSynth
    P = S::PATCHES.dup

    def self.hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

    # Fm9, Bbm9, Eb13, Abmaj9, Dbmaj7#11, C7alt: soul-jazz, Dilla territory.
    CHORDS = [
      [41, [56, 60, 63, 67]], [46, [56, 61, 65, 68]], [39, [55, 60, 61, 65]],
      [44, [55, 60, 63, 70]], [37, [60, 65, 67, 72]], [36, [58, 61, 64, 68]],
    ]
    SNAP = { amp: S::Envelope.new(attack: 0.004, decay: 0.3, sustain: 0.35, release: 0.18),
             filter_env: S::Envelope.new(attack: 0.002, decay: 0.22, sustain: 0.2, release: 0.15) }.freeze
    PROPHET_LEADS = {
      prophet_five_lead: P[:prophet_five].merge(SNAP),
      prophet_pad_lead: P[:prophet_pad].merge(SNAP),
      prophet_poly: P[:poly_lead].merge(SNAP),
      prophet_bright: P[:prophet_five].merge(SNAP).merge(cutoff: 900.0, resonance: 0.42),
    }.freeze
    P.merge!(PROPHET_LEADS)
    # The Rhodes leads: dilla's two electric pianos, and each a shade brighter
    # and darker.
    RHODES_LEADS = {
      rhodes_tine: P[:rhodes_tine], e_piano: P[:e_piano],
      rhodes_bright: P[:rhodes_tine].merge(cutoff: P[:rhodes_tine][:cutoff] * 1.6),
      e_piano_dark: P[:e_piano].merge(cutoff: P[:e_piano][:cutoff] * 0.65),
    }.freeze
    P.merge!(RHODES_LEADS)
    # Moog chord presets, on dilla's ladder: the chords play only these, the
    # patch morphing from one to the next without a seam -- cutoff, resonance,
    # envelope depth, drive and detune all glide; the waves change at halfway.
    MOOG_ENV = { amp: P[:warm_pad][:amp], filter_env: P[:warm_pad][:filter_env] }.freeze
    MOOG_CHORDS = {
      minimoog_pad: { waves: %i[saw square triangle], detune: [0.0, -6.0, 7.0], octaves: [0, 0, -1], cutoff: 620.0, env_amount: 1400.0, resonance: 0.42, drive: 1.1 },
      memorymoog_brass: { waves: %i[saw saw saw], detune: [-9.0, 0.0, 9.0], octaves: [0, 0, 0], cutoff: 760.0, env_amount: 1900.0, resonance: 0.3, drive: 1.2 },
      polymoog_vox: { waves: %i[square square saw], detune: [-4.0, 5.0, 0.0], octaves: [0, 1, 0], cutoff: 900.0, env_amount: 700.0, resonance: 0.24, drive: 0.95 },
      moog_one_strings: { waves: %i[saw saw saw], detune: [-14.0, 0.0, 13.0], octaves: [0, 0, 1], cutoff: 1150.0, env_amount: 800.0, resonance: 0.2, drive: 0.9 },
      sub37_warm: { waves: %i[saw square saw], detune: [0.0, 4.0, -5.0], octaves: [0, -1, 0], cutoff: 480.0, env_amount: 1600.0, resonance: 0.55, drive: 1.3 },
    }.transform_values { |p| p.merge(MOOG_ENV) }.freeze
    # Four chords to travel from one preset to the next, in a fresh order each lap.
    MORPH_CHORDS = 4
    def self.moog_morph(order, chord_i)
      pos = chord_i.to_f / MORPH_CHORDS
      a = MOOG_CHORDS.fetch(order[pos.floor % order.size])
      b = MOOG_CHORDS.fetch(order[(pos.floor + 1) % order.size])
      x = pos - pos.floor
      lerp = ->(k) { a[k] + ((b[k] - a[k]) * x) }
      (x < 0.5 ? a : b).merge(cutoff: lerp.(:cutoff), env_amount: lerp.(:env_amount), resonance: lerp.(:resonance),
                               drive: lerp.(:drive), detune: a[:detune].each_index.map { |i| a[:detune][i] + ((b[:detune][i] - a[:detune][i]) * x) })
    end
    PADS = %i[warm_pad poly_strings prophet_five juno_pad prophet_pad vp330_ensemble soft_reed e_piano rhodes_tine glass_bell]
    BASSES = %i[moog_bass acid sub dub_bass]
    QUALITIES = {
      m9: [3, 7, 10, 14], m11: [3, 7, 10, 17], maj9: [4, 7, 11, 14], maj7s11: [4, 7, 11, 18],
      d13: [4, 10, 14, 21], alt: [4, 10, 13, 15], m6_9: [3, 7, 9, 14], sus13: [5, 10, 14, 21],
    }.freeze
    MOVES = {
      [0, :m9] => [[5, :m9], [10, :d13], [8, :maj9], [5, :m11], [3, :maj9]],
      [0, :m11] => [[5, :m9], [8, :maj7s11], [10, :sus13]],
      [5, :m9] => [[10, :d13], [7, :alt], [3, :maj9], [0, :m6_9]],
      [5, :m11] => [[10, :d13], [7, :alt]],
      [10, :d13] => [[3, :maj9], [8, :maj9], [0, :m9]],
      [10, :sus13] => [[10, :d13], [3, :maj9]],
      [3, :maj9] => [[8, :maj9], [5, :m9], [1, :maj7s11]],
      [8, :maj9] => [[1, :maj7s11], [7, :alt], [5, :m9]],
      [8, :maj7s11] => [[7, :alt], [1, :maj7s11]],
      [1, :maj7s11] => [[7, :alt], [0, :m9], [0, :m11]],
      [7, :alt] => [[0, :m9], [0, :m11], [8, :maj9]],
      [0, :m6_9] => [[5, :m9], [10, :d13]],
    }.freeze
    NAMES = %w[C Db D Eb E F Gb G Ab A Bb B].freeze

    def self.voice_lead(pcs, previous)
      pcs.each_with_index.map do |pc, idx|
        centre = previous[idx] || previous.last
        (53..74).select { |m| m % 12 == pc }.min_by { |m| (m - centre).abs }
      end.sort.uniq
    end
    # Industrial techno, ten below the 128 BPM it started at (Attack Magazine:
    # 126-130), at the operator's word. BAR is two bars, eight beats.
    BPM = 118
    BAR = 8 * 60.0 / BPM
    CHORD_LEN = BAR

    Voice = Struct.new(:hz, :spec, :start, :held, :gain, :phases, :ladder, :bass)

    def self.voice(midi, spec, start, held, gain, bass: false)
      rng = Random.new(midi * 7 + (start * 10).to_i)
      Voice.new(hz(midi) * 2.0**(rng.rand(-0.7..0.7) / 1200.0), spec, start, held, gain,
                spec[:waves].map { rng.rand }, S::Ladder.new(rate: RATE), bass)
    end

    # The knobs: cutoff breathes over 23 s, resonance over 31 s, out of phase.
    def self.cutoff_knob(t) = 0.55 + 0.45 * Math.sin(2 * Math::PI * t / 23.0)
    def self.res_knob(t) = 0.5 + 0.5 * Math.sin(2 * Math::PI * t / 31.0 + 1.3)

    # The DFAM, as the Moog is built: an 8-step sequencer, each step its own pitch
    # and velocity, running in sixteenths; VCO 1 a triangle frequency-modulating
    # VCO 2, a square; both with a pitch envelope that falls; noise mixed in; all
    # of it through a ladder low-pass with its own decay, then the VCA's decay.
    # The pattern starts from dilla's DfamEngine and one step mutates every two
    # bars; decay and cutoff drift slowly, like the pads' knobs.
    DFAM_STEP = BAR / 32 # sixteenths
    DFAM_LEVEL = 0.16
    # Accents on the eight-step page: the downbeat and the and-of-two lean in.
    DFAM_SCENES = %i[euclid ratchet broken tribal].freeze
    # Each groove brings its own kick, as [cycle length, steps that hit].
    SCENE_KICKS = { euclid: [16, [0, 6, 10]], ratchet: [12, [0, 7]], broken: [16, [0, 3, 10, 11]], tribal: [12, [0, 5, 8]] }.freeze
    DFAM_RATES = { 1.0 => "16ths", (2.0 / 3) => "triplets", 0.5 => "32nds", 1.5 => "dotted 16ths", 2.0 => "8ths" }.freeze
    # A Euclidean rhythm: k hits spread as evenly as n steps allow.
    def self.euclid(k, n) = (@euclid ||= {})[[k, n]] ||= Array.new(n) { |i| ((i * k) % n) < k }
    # And its own lead rhythm, on sixteen steps.
    SCENE_LEAD = { euclid: euclid(5, 16), ratchet: euclid(6, 16), broken: Array.new(16) { |i| [0, 3, 6, 10, 12].include?(i) }, tribal: euclid(7, 16) }.freeze
    ACCENT = [1.35, 0.8, 1.0, 0.85, 1.25, 0.8, 1.1, 0.9].freeze
    KICK_LEVEL = 0.06
    # Off at the operator's word, and with them the rumble and the pump.
    KICKS_ON = false
    # The lead plays over every chord, at the operator's word.
    LEAD_ALWAYS = true
    # Muted at the operator's word; true brings the leads back.
    LEADS_ON = false
    # The Crystallizer, after Soundtoys: reversed grains of the lead, pitched up
    # an octave or a fifth, a quarter second late, fed back into themselves.
    # Two readers half a grain apart, Hann-windowed, crossfade into a shimmer.
    CRYS_LEN = RATE * 2
    CRYS_GRAIN = (RATE * 0.16).round
    CRYS_DELAY = (RATE * 0.25).round
    CRYS_FEEDBACK = 0.45
    CRYS_MIX = 0.5
    # The 909's hat: six detuned square waves, high-passed, then crushed to 12
    # bits the way an SP-1200 resample crunches it.
    HAT_HZ = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0].freeze
    HAT_LEVEL = 0.011
    # Rendered once: the squares, noise under them for grit, and the decay.
    hat_table = lambda do |len, decay|
      Array.new((len * RATE).to_i) do |i|
        th = i.to_f / RATE
        sq = HAT_HZ.sum { |f| ((th * f * 7.0) % 1.0) < 0.5 ? 1.0 : -1.0 }
        (sq + (((rand * 2.0) - 1.0) * 3.0)) * Math.exp(-th / decay)
      end.freeze
    end
    HAT_OPEN = hat_table.(0.3, 0.07)
    HAT_CLOSED = hat_table.(0.06, 0.015)
    # The shaker: noise alone, short, high-passed with the hats.
    SHAKER = Array.new((0.08 * RATE).to_i) { |i| ((rand * 2.0) - 1.0) * 2.0 * Math.exp(-i.to_f / RATE / 0.025) }.freeze
    CLAP_LEVEL = 0.08
    # The rumble: the kick sent into a dark reverb (three combs), distorted,
    # low-passed to 150 Hz, mono, and ducked by the kick itself.
    RUMBLE_LEVEL = 0.05
    COMBS = [1123, 1409, 1693].map { |len| Array.new(len, 0.0) }
    RUM_A = 1.0 - Math.exp(-2 * Math::PI * 150.0 / RATE)
    HAT_A = 1.0 - Math.exp(-2 * Math::PI * 7000.0 / RATE)
    DfamHit = Struct.new(:start, :f0, :vel, :ph1, :ph2, :ladder, :pan)
    class DfamKnob
      attr_reader :value
      def initialize(lo, hi, rng, speed:)
        @lo, @hi, @rng, @speed = lo, hi, rng, speed
        @x = 0.5
        @v = 0.0
        @push = nil
      end
      # A gesture: toward `target` (0..1) for `seconds`, then released.
      def lean(target, seconds, now) = @push = [target, now + seconds]
      def step(dt, now)
        @push = nil if @push && now > @push[1]
        pull = @push ? (@push[0] - @x) * 1.5 : (0.5 - @x) * 0.03
        @v = (@v * 0.992) + (@rng.rand(-1.0..1.0) * @speed * dt) + (pull * dt)
        @x = (@x + (@v * dt)).clamp(0.0, 1.0)
        @value = @lo + ((@hi - @lo) * @x)
      end
    end

    knob_rng = Random.new
    DFAM_KNOBS = {
      vcf_decay: DfamKnob.new(0.03, 0.22, knob_rng, speed: 0.08),
      vca_decay: DfamKnob.new(0.06, 0.28, knob_rng, speed: 0.07),
      cutoff: DfamKnob.new(500.0, 4200.0, knob_rng, speed: 0.1),
      resonance: DfamKnob.new(0.2, 0.85, knob_rng, speed: 0.06),
      fm: DfamKnob.new(0.0, 1.1, knob_rng, speed: 0.07),
      noise: DfamKnob.new(0.02, 0.45, knob_rng, speed: 0.05),
      pitch_amount: DfamKnob.new(0.6, 4.0, knob_rng, speed: 0.06),
      pitch_decay: DfamKnob.new(0.015, 0.12, knob_rng, speed: 0.05),
    }.freeze
    def self.sonitex(bits:, lo:, hi:, drive:, mix: 0.5, samples: 1)
      "volume=#{drive},acrusher=bits=#{bits}:mode=log:aa=1:mix=#{mix}:samples=#{samples}," \
        "highpass=f=#{lo},lowpass=f=#{hi},alimiter=limit=0.99"
    end

    # Level-neutral here: five stages at livesets' -7.5 dB each sank the pads 37 dB
    # under the kick. The colour stays; the loss does not.
    def self.vcs(depth:, smear:, db: 0.0)
      phaser_db = -2.6 + (10.9 * (depth - 0.26)) - (0.14 * (smear - 2.1))
      "aphaser=in_gain=0.75:out_gain=0.85:delay=#{smear}:decay=#{depth}:speed=0.5," \
        "aecho=0.9:1:#{smear.round}:0.08,volume=#{(db - phaser_db + 0.65).round(2)}dB"
    end

    MASTER = [
      vcs(depth: 0.34, smear: 2.4), sonitex(bits: 12, lo: 40, hi: 13_000, drive: 1.12),
      vcs(depth: 0.38, smear: 1.7), sonitex(bits: 13, lo: 42, hi: 15_000, drive: 1.04),
      vcs(depth: 0.26, smear: 3.6), sonitex(bits: 11, lo: 42, hi: 12_000, drive: 1.18),
      "alimiter=limit=0.95"
    ].join(",")
    def self.space_echo(head_ms, decays)
      taps = [1, 2, 3].map { |k| (head_ms * k).round }.join("|")
      "highpass=f=160,aecho=0.9:0.9:#{taps}:#{decays},lowpass=f=3200,chorus=0.9:0.9:25:0.35:0.6:1.8"
    end
    HEAD = BAR / 16 * 1000
    ARP_FX = "anull"
    # Extreme analog tape on the master channel, the whole sum: the head bump near
    # 60 Hz, the drive into tanh that tape saturation is (undone after, so it
    # colours rather than raises), the capstan's wow and flutter worn deep, the top
    # the tape cannot hold, and its hiss.
    def self.tape(drive:, wow:, flutter:, top:, hiss:)
      "equalizer=f=60:t=q:w=1.1:g=4.5,volume=#{drive},asoftclip=type=tanh,volume=#{(1.0 / drive).round(3)}," \
        "vibrato=f=0.42:d=#{wow},vibrato=f=6.8:d=#{flutter},lowpass=f=#{top},highpass=f=28," \
        "aeval=exprs=val(0)+#{hiss}*(2*random(0)-1)|val(1)+#{hiss}*(2*random(1)-1):c=same"
    end
    TAPE = tape(drive: 3.2, wow: 0.22, flutter: 0.07, top: 9_500, hiss: 0.004)
    # Arps on the arps, at the operator's word: the lead is split three ways. One
    # stays dry; one goes up a fifth and comes back an eighth late, the other up
    # an octave a dotted eighth late, so the echoes arpeggiate over the arpeggio.
    # Each pitched copy feeds back through its own echo the way a crystallizer
    # does, and the sum is sharpened with ffmpeg's crystalizer. The pitch shift is
    # asetrate then atempo, a resample and a time-stretch, which grains the copies.
    def self.pitched(ratio, delay_ms, echo_ms, decay)
      "asetrate=#{(RATE * ratio).round},aresample=#{RATE},atempo=#{(1.0 / ratio).round(4)}," \
        "adelay=#{delay_ms}|#{delay_ms},aecho=0.8:0.7:#{echo_ms}:#{decay}"
    end
    EIGHTH = (BAR / 16 * 1000).round
    ARPS_ON_ARPS = "asplit=3[ad][ax][ay];[ax]#{pitched(1.5, EIGHTH, EIGHTH * 2, 0.45)}[af];" \
                   "[ay]#{pitched(2.0, (EIGHTH * 1.5).round, EIGHTH * 3, 0.4)},highpass=f=900[ao];" \
                   "[ad][af][ao]amix=inputs=3:weights=1 0.5 0.35:normalize=0,crystalizer=i=1.5"
    # The leads sit lower in the sum, at the operator's word: 0.9 against the
    # main's 1 where they were 1.5.
    GRAPH = "[0:a]pan=stereo|c0=c0|c1=c1,#{MASTER}[m];[0:a]pan=stereo|c0=c2|c1=c3,#{ARPS_ON_ARPS}[a];[m][a]amix=inputs=2:weights=1 0.9:normalize=0,#{TAPE},alimiter=limit=0.96"

    def self.run(argv = [])
      loops = (argv[0] || 2).to_i

      voices = []
      rng = Random.new
      key = 5 # F minor, where the loved progression sits
      state = [0, :m9]
      voicing = CHORDS.first.last
      chord_i = 0
      moog_order = nil
      recent = []
      next_modulation = 8
      key = rng.rand(12)
      next_chord = 0.0
      log = File.open(File.join(__dir__, "..", "moog_improv.log"), "a").tap { |f| f.sync = true }
      total = Float::INFINITY
      pattern = { pitch: [50, 30, 60, 20, 55, 35, 65, 25], velocity: [80, 60, 90, 50, 85, 65, 95, 55] }
      dfam_rng = Random.new
      dfam_hits = []
      dfam_next = 0.0
      dfam_step = 0
      pattern_b = { pitch: [78, 64, 88, 70, 92], velocity: [55, 0, 70, 45, 60] }
      dfam_scene = nil
      next_scene_at = 0.0
      grid_next = 0.0
      grid_step = 0
      # A new groove, never the kind just played: its kind, its rate, and for a
      # generated one a Euclidean pattern of 2 to n-1 hits over 5 to 16 steps.
      new_scene = lambda do |last|
        kind = (DFAM_SCENES + %i[generated generated]).reject { |k| k == last && k != :generated }.sample(random: dfam_rng)
        rate, rate_name = DFAM_RATES.to_a.sample(random: dfam_rng)
        steps = dfam_rng.rand(5..16)
        hits = dfam_rng.rand(2..(steps - 1))
        label = kind == :generated ? "E(#{hits},#{steps}) in #{rate_name}" : "#{kind} in #{rate_name}"
        { kind:, rate:, label:, hits: euclid(hits, steps).rotate(dfam_rng.rand(steps)),
          pitches: Array.new(dfam_rng.rand(3..8)) { dfam_rng.rand(5..45) } }
      end
      kicks = []
      click_lp = 0.0
      crys_l = Array.new(CRYS_LEN, 0.0)
      crys_r = Array.new(CRYS_LEN, 0.0)
      crys_w = 0
      crys_p = 0
      crys_pitch = 2.0
      crys_out_l = crys_out_r = 0.0
      hats = []
      claps = []
      hat_lp = clap_lp = clap_hp = 0.0
      comb_i = [0, 0, 0]
      rum_lp1 = rum_lp2 = 0.0
      next_gesture = 8.0

      $stderr.puts "improvising: #{PADS.join(" -> ")} over moog_bass, DFAM on top"
      sox = IO.popen(["sh", "-c", "ffmpeg -loglevel error -f s16le -ar #{RATE} -ac 4 -i - -filter_complex '#{GRAPH}' -f s16le -ar #{RATE} -ac 2 - | sox -q -t raw -r #{RATE} -e signed -b 16 -c 2 - -d"], "wb")
      frame = 0
      frames = Float::INFINITY
      two_pi = 2 * Math::PI
      while frame < frames
        # The next chord, chosen a second before it sounds.
        while next_chord < (frame.to_f / RATE) + 1.0
          degree, quality = state
          voicing = voice_lead(QUALITIES[quality].map { |iv| (key + degree + iv) % 12 }, voicing)
          bass = 36 + ((key + degree) % 12)
          bass += 12 if bass < 36
          name = "#{NAMES[(key + degree) % 12]}#{quality}"
          recent << [(key + degree) % 12, quality]
          recent.shift if recent.size > 4
          options = MOVES.fetch(state).reject { |d, q| recent.include?([(key + d) % 12, q]) }
          options = MOVES.fetch(state) if options.empty?
          state = options.sample(random: rng)
          roll = rng.rand
          if roll < 0.08 # the tritone substitute: a dominant a flat fifth away
            key = (key + 6) % 12
            name += " (tritone sub next)"
          elsif roll < 0.14 # a chromatic side-step, up or down a semitone
            key = (key + [1, 11].sample(random: rng)) % 12
            name += " (side-step next)"
          end
          if chord_i >= next_modulation
            key = (key + [5, 3, 8, 10, 2, 7].sample(random: rng)) % 12
            state = [0, %i[m9 m11 m6_9].sample(random: rng)]
            next_modulation = chord_i + rng.rand(8..16)
            name += " -> #{NAMES[key]} minor"
          end
          moog_order = MOOG_CHORDS.keys.shuffle(random: rng) if (chord_i % (MORPH_CHORDS * MOOG_CHORDS.size)).zero?
          pad = moog_morph(moog_order, chord_i)
          pad_name = "#{moog_order[(chord_i / MORPH_CHORDS) % moog_order.size]} -> #{moog_order[((chord_i / MORPH_CHORDS) + 1) % moog_order.size]} #{(chord_i % MORPH_CHORDS) * 100 / MORPH_CHORDS}%"
          bass_patch = P.fetch(BASSES[(chord_i / 4) % BASSES.size])
          voicing.each { |m| voices << voice(m, pad, next_chord, CHORD_LEN - 0.1, 0.3, bass: :pad) }
          # The rolling bass: the root on the three sixteenths after every kick,
          # short and even, the octave up on the last of each beat now and then.
          (CHORD_LEN / (BAR / 8)).round.times do |beat|
            [1, 2, 3].each do |sixteenth|
              up = sixteenth == 3 && rng.rand < 0.25 ? 12 : 0
              voices << voice(bass + up, bass_patch, next_chord + (beat * BAR / 8) + (sixteenth * DFAM_STEP), DFAM_STEP * 0.6, 0.4, bass: true)
            end
          end
          log.puts "#{Time.now.strftime("%H:%M:%S")} #{name} on #{pad_name}, bass #{BASSES[(chord_i / 4) % BASSES.size]}"
          if LEADS_ON && (LEAD_ALWAYS || rng.rand < 0.3)
            # The loved lead, dry: an arpeggio over the chord an octave up, its shape
            # drawn fresh, a new patch every four notes across every lead the synth has.
            arp_patches = RHODES_LEADS.keys.shuffle(random: rng)
            # An octave lower than before, and always climbing: the chord, then the
            # chord an octave up, arped upward.
            order = (voicing + voicing.map { |m| m + 12 }).sort
            step = BAR / 16
            16.times { |k| voices << voice(order[k % order.size], P.fetch(arp_patches[(k / 4) % arp_patches.size]), next_chord + (k * step), step * 0.7, 0.45, bass: :arp) }
            log.puts "  arp over it"
          end
          chord_i += 1
          next_chord += CHORD_LEN
        end
        n = BLOCK
        left = Array.new(n, 0.0)
        arp_l = Array.new(n, 0.0)
        arp_r = Array.new(n, 0.0)
        right = Array.new(n, 0.0)
        pad_l = Array.new(n, 0.0)
        pad_r = Array.new(n, 0.0)
        tb = frame.to_f / RATE
        ck = cutoff_knob(tb)
        rk = res_knob(tb)
        voices.each do |v|
          spec = v.spec
          rel = spec[:amp].release
          next if tb + (n.to_f / RATE) < v.start || tb > v.start + v.held + rel
          level = 1.0 / spec[:waves].size
          freqs = spec[:waves].each_index.map { |k| v.hz * (2.0**spec[:octaves][k]) * (2.0**(spec[:detune][k] / 1200.0)) }
          base_cut = spec[:cutoff] * (v.bass == true ? 0.7 + ck * 0.8 : 0.35 + ck * 1.6)
          res = v.bass == true ? spec[:resonance] : [spec[:resonance] + rk * 0.45, 0.85].min
          # The envelopes at control rate, every 16 samples: inaudible, and half the
          # cost that had the player at 100% of a core and dropping blocks.
          waves = spec[:waves]
          nw = waves.size
          out_l, out_r = case v.bass
                         when :arp then [arp_l, arp_r]
                         when :pad then [pad_l, pad_r]
                         else [left, right]
                         end
          cut = ampv = 0.0
          j = 0
          while j < n
            t = tb + (j.to_f / RATE) - v.start
            if t >= 0
              if (j & 15).zero?
                shape = spec[:filter_env].at(t, v.held)
                shape = (shape * (1.0 - spec[:lpg])) + (spec[:amp].at(t, v.held) * spec[:lpg]) if spec[:lpg]
                cut = (base_cut + (spec[:env_amount] * shape)).clamp(30.0, 12_000.0)
                ampv = spec[:amp].at(t, v.held) * v.gain
              end
              raw = 0.0
              k = 0
              while k < nw
                v.phases[k] = (v.phases[k] + (freqs[k] / RATE)) % 1.0
                raw += S.wave(waves[k], v.phases[k]) * level
                k += 1
              end
              out = v.ladder.process(raw * spec[:drive], cut, res) * ampv
              out_l[j] += out * 0.52
              out_r[j] += out * 0.48
            end
            j += 1
          end
        end
      voices.reject! { |v| tb > v.start + v.held + v.spec[:amp].release }

      # Sequence the DFAM a block ahead, on its own clock. Every two to six bars
      # a new groove is drawn: one of the four named ones or a fresh Euclidean
      # pattern, at a rate of its own against the steady kick -- sixteenths,
      # triplets, thirty-seconds, dotted sixteenths or eighths. While it plays,
      # its pitches and its rotation keep mutating.
      while dfam_next < tb + (n.to_f / RATE)
        if dfam_scene.nil? || dfam_next >= next_scene_at
          dfam_scene = new_scene.(dfam_scene && dfam_scene[:kind])
          next_scene_at = dfam_next + ((BAR / 2) * dfam_rng.rand(2..6))
          log.puts "  dfam groove -> #{dfam_scene[:label]}"
        end
        step_len = DFAM_STEP * dfam_scene[:rate]
        hz = ->(p) { 32.0 * (2.0**(p / 100.0 * 4.0)) }
        add = ->(at, p, vel, pan) { dfam_hits << DfamHit.new(at, hz.(p), vel, 0.0, 0.0, S::Ladder.new(rate: RATE), pan) }
        pitches = dfam_scene[:pitches]
        case dfam_scene[:kind]
        when :generated
          if dfam_scene[:hits][dfam_step % dfam_scene[:hits].size]
            add.(dfam_next, pitches[dfam_step % pitches.size], dfam_rng.rand < 0.25 ? 1.1 : dfam_rng.rand(0.5..0.85), dfam_rng.rand(0.25..0.75))
          end
        when :euclid
          add.(dfam_next, pitches[dfam_step % pitches.size], 1.0, 0.45) if euclid(5, 16)[dfam_step % 16]
        when :ratchet
          if (dfam_step % 6).zero? || dfam_rng.rand < 0.12
            reps = dfam_rng.rand(2..4)
            p0 = dfam_rng.rand(25..45)
            reps.times { |r| add.(dfam_next + (r * step_len / 2), p0 - (r * 12), 0.9 - (r * 0.15), 0.3 + (0.4 * (r % 2))) }
          end
        when :broken
          add.(dfam_next, pitches[6 - (dfam_step % 7)] || pitches.first, dfam_rng.rand(0.4..1.0), dfam_rng.rand(0.2..0.8)) if dfam_rng.rand < 0.6
        when :tribal
          t12 = dfam_step % 12
          add.(dfam_next, pitches[t12 % pitches.size], [0, 3, 6].include?(t12) ? 1.1 : 0.6, 0.35 + (0.3 * (t12 % 2))) if euclid(7, 12)[t12]
        end
        # The mutation: now and then a pitch redrawn, the pattern turned a step.
        pitches[dfam_rng.rand(pitches.size)] = dfam_rng.rand(5..45) if dfam_rng.rand < 0.07
        dfam_scene[:hits] = dfam_scene[:hits].rotate(1) if dfam_rng.rand < 0.03
        dfam_step += 1
        dfam_next += step_len
      end
      # The industrial grid, after Attack Magazine's dissection: the kick four
      # on the floor, a closed hat on each offbeat, a shaker on every second
      # offbeat, a noise snare on two and four. The DFAM is the syncopated low tom.
      while grid_next < tb + (n.to_f / RATE)
        s16 = grid_step % 16
        kicks << grid_next if KICKS_ON && (s16 % 4).zero?
        hats << [grid_next, HAT_CLOSED, 0.9] if s16 % 4 == 2
        hats << [grid_next + 0.004, SHAKER, 0.6] if [6, 14].include?(s16)
        claps << grid_next if [4, 12].include?(s16)
        grid_step += 1
        grid_next += DFAM_STEP
      end
      kv = DFAM_KNOBS.transform_values { |k| k.step(n.to_f / RATE, tb) }
      if tb > next_gesture
        name = DFAM_KNOBS.keys.sample(random: knob_rng)
        target = knob_rng.rand < 0.5 ? knob_rng.rand(0.0..0.15) : knob_rng.rand(0.85..1.0)
        DFAM_KNOBS[name].lean(target, BAR * knob_rng.rand(0.5..1.5), tb)
        log.puts "  dfam: #{name} -> #{target > 0.5 ? "up" : "down"}"
        next_gesture = tb + knob_rng.rand(6.0..16.0)
      end
      vcf = kv[:vcf_decay]
      vca = kv[:vca_decay]
      cut_top = kv[:cutoff]
      dfam_hits.each do |h|
        pitch_env = cut = amp = 0.0
        j = 0
        while j < n
          tt = tb + (j.to_f / RATE) - h.start
          if tt >= 0
            if (j & 15).zero?
              pitch_env = 1.0 + (kv[:pitch_amount] * Math.exp(-tt / kv[:pitch_decay]))
              cut = 120.0 + (cut_top * Math.exp(-tt / vcf))
              amp = h.vel * Math.exp(-tt / vca) * DFAM_LEVEL
            end
            h.ph1 = (h.ph1 + (h.f0 * pitch_env / RATE)) % 1.0
            tri = S.wave(:triangle, h.ph1)
            h.ph2 = (h.ph2 + (h.f0 * 1.5 * pitch_env * (1.0 + (kv[:fm] * tri)) / RATE)) % 1.0
            sq = h.ph2 < 0.5 ? 1.0 : -1.0
            mix = (0.55 * tri) + (0.3 * sq) + (kv[:noise] * (rand * 2.0 - 1.0))
            out = h.ladder.process(mix, cut, kv[:resonance]) * amp
            left[j] += out * h.pan
            right[j] += out * (1.0 - h.pan)
          end
          j += 1
        end
      end
      dfam_hits.reject! { |h| tb - h.start > vca * 8 }
      j = 0
      while j < n
        now = tb + (j.to_f / RATE)
        bus = 0.0
        duck = 0.0
        kicks.each do |t|
          tk = now - t
          next if tk.negative? || tk > 0.5
          d = Math.exp(-tk / 0.12)
          duck = d if d > duck
          phase = (50.0 * tk) + (170.0 * 0.012 * (1.0 - Math.exp(-tk / 0.012))) + (30.0 * 0.08 * (1.0 - Math.exp(-tk / 0.08)))
          bus += Math.sin(2 * Math::PI * phase) * Math.exp(-tk / 0.34)
          if tk < 0.003
            click_lp += 0.35 * ((rand * 2.0 - 1.0) - click_lp)
            bus += (click_lp * 1.2) + (tk < 0.0008 ? 0.6 : 0.0)
          end
        end
        # Driven into hard clipping and back: the distorted industrial kick.
        k = Math.tanh(Math.tanh(bus * 7.0) * 2.5)
        k = (k * 256).round / 256.0 * KICK_LEVEL # a bitcrusher for the crisp attack
        wet = 0.0
        c = 0
        while c < 3
          buf = COMBS[c]
          y = buf[comb_i[c]]
          buf[comb_i[c]] = k + (y * 0.8)
          comb_i[c] = (comb_i[c] + 1) % buf.size
          wet += y
          c += 1
        end
        rum_lp1 += RUM_A * (Math.tanh(wet * 12.0) - rum_lp1)
        rum_lp2 += RUM_A * (rum_lp1 - rum_lp2)
        rumble = rum_lp2 * RUMBLE_LEVEL * (1.0 - (0.9 * duck))
        metal = 0.0
        hats.each do |t, open, vel|
          idx = ((now - t) * RATE).to_i
          table = open
          metal += table[idx] * vel if idx >= 0 && idx < table.size
        end
        hat_lp += HAT_A * (metal - hat_lp)
        # Crushed to 12 bits and overdriven, the SP-1200 resample.
        hat = Math.tanh(((metal - hat_lp) * 32).round / 32.0 * 0.5) * 2.0 * HAT_LEVEL
        clap = 0.0
        claps.each do |t|
          tc = now - t
          next if tc.negative? || tc > 0.35
          burst = (1.0 - Math.exp(-tc / 0.004)) * Math.exp(-tc / 0.11)
          clap += ((rand * 2.0) - 1.0) * burst
        end
        clap_lp += 0.18 * (Math.tanh(clap * 2.5) - clap_lp)
        clap_hp += 0.05 * (clap_lp - clap_hp)
        drums = k + hat + ((clap_lp - clap_hp) * CLAP_LEVEL)
        # Parallel distortion on the drum bus: grit blended under the clean hits.
        drums += Math.tanh(drums * 12.0) * 0.025
        # The pads pump against the kick.
        pump = 1.0 - (0.25 * duck)
        left[j] += (pad_l[j] * pump) + drums + rumble

      right[j] += (pad_r[j] * pump) + drums + rumble
      # The Crystallizer on the lead.
      cl = crys_out_l = 0.0
      cr = crys_out_r = 0.0
      2.times do |g|
        ph = (crys_p + (g * CRYS_GRAIN / 2)) % CRYS_GRAIN
        win = 0.5 - (0.5 * Math.cos(2 * Math::PI * ph / CRYS_GRAIN))
        at = (crys_w - CRYS_DELAY - ((CRYS_GRAIN - ph) * crys_pitch).to_i) % CRYS_LEN
        cl += crys_l[at] * win
        cr += crys_r[at] * win
      end
      crys_l[crys_w] = arp_l[j] + (cr * CRYS_FEEDBACK) # crossed, so the shimmer walks the field
      crys_r[crys_w] = arp_r[j] + (cl * CRYS_FEEDBACK)
      crys_w = (crys_w + 1) % CRYS_LEN
      crys_p += 1
      if crys_p >= CRYS_GRAIN * 24 # every few seconds, a fifth or an octave
        crys_p = 0
        crys_pitch = [2.0, 1.5, 2.0].sample(random: rng)
      end
      arp_l[j] += cl * CRYS_MIX
      arp_r[j] += cr * CRYS_MIX
      j += 1
      end
      kicks.reject! { |t| tb - t > 0.5 }
      hats.reject! { |t, _, _| tb - t > 0.1 }
      claps.reject! { |t| tb - t > 0.35 }
      pcm = Array.new(n * 4)
      n.times do |i|
        pcm[i * 4] = (Math.tanh(left[i]) * 29_000).round
        pcm[(i * 4) + 1] = (Math.tanh(right[i]) * 29_000).round
        pcm[(i * 4) + 2] = (Math.tanh(arp_l[i] * 1.4) * 26_000).round
        pcm[(i * 4) + 3] = (Math.tanh(arp_r[i] * 1.4) * 26_000).round
      end
      sox.write(pcm.pack("s<*"))
        frame += n
      end
      sox.close
    end
  end

  module Liveset7b5069a1bf3b
    # takes/liveset_7b5069a1bf3b.rb, frozen as heard (sha256 b61cf8202ffe4f692422dac911e6655d3fe1f8c021d41eab102a110948e4e693).

    # MASTER's main sound, improvising live and endless: soul-jazz harmony chosen
    # chord by chord, each voiced nearest the last, the key moving on its own.
    # The chords play only Moog presets on dilla's ladder, morphing over four
    # chords, on two decks at once, and a turntablist's sharp-curve crossfader
    # cuts between the decks on the thirty-second grid, a new cut every bar.
    # A hand works the record too: baby scratches on opening cuts, a tape stop
    # now and then, a spinback at the end of some phrases, and dub delay throws.
    # Under it all the rolling Moog bass, an industrial grid at 128 BPM and the
    # DFAM, always changing. Kicks and leads sit switched off at the operator's
    # word: KICKS_ON and LEADS_ON.

    RATE = 32_000
    BLOCK = 1_024
    S = AnalogSynth
    P = S::PATCHES.dup

    def self.hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

    # Fm9, Bbm9, Eb13, Abmaj9, Dbmaj7#11, C7alt: soul-jazz, Dilla territory.
    CHORDS = [
      [41, [56, 60, 63, 67]], [46, [56, 61, 65, 68]], [39, [55, 60, 61, 65]],
      [44, [55, 60, 63, 70]], [37, [60, 65, 67, 72]], [36, [58, 61, 64, 68]],
    ]
    SNAP = { amp: S::Envelope.new(attack: 0.004, decay: 0.3, sustain: 0.35, release: 0.18),
             filter_env: S::Envelope.new(attack: 0.002, decay: 0.22, sustain: 0.2, release: 0.15) }.freeze
    PROPHET_LEADS = {
      prophet_five_lead: P[:prophet_five].merge(SNAP),
      prophet_pad_lead: P[:prophet_pad].merge(SNAP),
      prophet_poly: P[:poly_lead].merge(SNAP),
      prophet_bright: P[:prophet_five].merge(SNAP).merge(cutoff: 900.0, resonance: 0.42),
    }.freeze
    P.merge!(PROPHET_LEADS)
    # The Rhodes leads: dilla's two electric pianos, and each a shade brighter
    # and darker.
    RHODES_LEADS = {
      rhodes_tine: P[:rhodes_tine], e_piano: P[:e_piano],
      rhodes_bright: P[:rhodes_tine].merge(cutoff: P[:rhodes_tine][:cutoff] * 1.6),
      e_piano_dark: P[:e_piano].merge(cutoff: P[:e_piano][:cutoff] * 0.65),
    }.freeze
    P.merge!(RHODES_LEADS)
    # Moog chord presets, on dilla's ladder: the chords play only these, the
    # patch morphing from one to the next without a seam -- cutoff, resonance,
    # envelope depth, drive and detune all glide; the waves change at halfway.
    MOOG_ENV = { amp: P[:warm_pad][:amp], filter_env: P[:warm_pad][:filter_env] }.freeze
    MOOG_CHORDS = {
      minimoog_pad: { waves: %i[saw square triangle], detune: [0.0, -6.0, 7.0], octaves: [0, 0, -1], cutoff: 620.0, env_amount: 1400.0, resonance: 0.42, drive: 1.1 },
      memorymoog_brass: { waves: %i[saw saw saw], detune: [-9.0, 0.0, 9.0], octaves: [0, 0, 0], cutoff: 760.0, env_amount: 1900.0, resonance: 0.3, drive: 1.2 },
      polymoog_vox: { waves: %i[square square saw], detune: [-4.0, 5.0, 0.0], octaves: [0, 1, 0], cutoff: 900.0, env_amount: 700.0, resonance: 0.24, drive: 0.95 },
      moog_one_strings: { waves: %i[saw saw saw], detune: [-14.0, 0.0, 13.0], octaves: [0, 0, 1], cutoff: 1150.0, env_amount: 800.0, resonance: 0.2, drive: 0.9 },
      sub37_warm: { waves: %i[saw square saw], detune: [0.0, 4.0, -5.0], octaves: [0, -1, 0], cutoff: 480.0, env_amount: 1600.0, resonance: 0.55, drive: 1.3 },
    }.transform_values { |p| p.merge(MOOG_ENV) }.freeze
    # Four chords to travel from one preset to the next, in a fresh order each lap.
    MORPH_CHORDS = 4
    def self.moog_morph(order, chord_i)
      pos = chord_i.to_f / MORPH_CHORDS
      a = MOOG_CHORDS.fetch(order[pos.floor % order.size])
      b = MOOG_CHORDS.fetch(order[(pos.floor + 1) % order.size])
      x = pos - pos.floor
      lerp = ->(k) { a[k] + ((b[k] - a[k]) * x) }
      (x < 0.5 ? a : b).merge(cutoff: lerp.(:cutoff), env_amount: lerp.(:env_amount), resonance: lerp.(:resonance),
                               drive: lerp.(:drive), detune: a[:detune].each_index.map { |i| a[:detune][i] + ((b[:detune][i] - a[:detune][i]) * x) })
    end
    PADS = %i[warm_pad poly_strings prophet_five juno_pad prophet_pad vp330_ensemble soft_reed e_piano rhodes_tine glass_bell]
    BASSES = %i[moog_bass acid sub dub_bass]
    QUALITIES = {
      m9: [3, 7, 10, 14], m11: [3, 7, 10, 17], maj9: [4, 7, 11, 14], maj7s11: [4, 7, 11, 18],
      d13: [4, 10, 14, 21], alt: [4, 10, 13, 15], m6_9: [3, 7, 9, 14], sus13: [5, 10, 14, 21],
    }.freeze
    MOVES = {
      [0, :m9] => [[5, :m9], [10, :d13], [8, :maj9], [5, :m11], [3, :maj9]],
      [0, :m11] => [[5, :m9], [8, :maj7s11], [10, :sus13]],
      [5, :m9] => [[10, :d13], [7, :alt], [3, :maj9], [0, :m6_9]],
      [5, :m11] => [[10, :d13], [7, :alt]],
      [10, :d13] => [[3, :maj9], [8, :maj9], [0, :m9]],
      [10, :sus13] => [[10, :d13], [3, :maj9]],
      [3, :maj9] => [[8, :maj9], [5, :m9], [1, :maj7s11]],
      [8, :maj9] => [[1, :maj7s11], [7, :alt], [5, :m9]],
      [8, :maj7s11] => [[7, :alt], [1, :maj7s11]],
      [1, :maj7s11] => [[7, :alt], [0, :m9], [0, :m11]],
      [7, :alt] => [[0, :m9], [0, :m11], [8, :maj9]],
      [0, :m6_9] => [[5, :m9], [10, :d13]],
    }.freeze
    NAMES = %w[C Db D Eb E F Gb G Ab A Bb B].freeze

    def self.voice_lead(pcs, previous)
      pcs.each_with_index.map do |pc, idx|
        centre = previous[idx] || previous.last
        (53..74).select { |m| m % 12 == pc }.min_by { |m| (m - centre).abs }
      end.sort.uniq
    end
    # Industrial techno, ten below the 128 BPM it started at (Attack Magazine:
    # 126-130), at the operator's word. BAR is two bars, eight beats.
    BPM = 118
    BAR = 8 * 60.0 / BPM
    CHORD_LEN = BAR

    Voice = Struct.new(:hz, :spec, :start, :held, :gain, :phases, :ladder, :bass)

    def self.voice(midi, spec, start, held, gain, bass: false)
      rng = Random.new(midi * 7 + (start * 10).to_i)
      Voice.new(hz(midi) * 2.0**(rng.rand(-0.7..0.7) / 1200.0), spec, start, held, gain,
                spec[:waves].map { rng.rand }, S::Ladder.new(rate: RATE), bass)
    end

    # The knobs: cutoff breathes over 23 s, resonance over 31 s, out of phase.
    def self.cutoff_knob(t) = 0.55 + 0.45 * Math.sin(2 * Math::PI * t / 23.0)
    def self.res_knob(t) = 0.5 + 0.5 * Math.sin(2 * Math::PI * t / 31.0 + 1.3)

    # The DFAM, as the Moog is built: an 8-step sequencer, each step its own pitch
    # and velocity, running in sixteenths; VCO 1 a triangle frequency-modulating
    # VCO 2, a square; both with a pitch envelope that falls; noise mixed in; all
    # of it through a ladder low-pass with its own decay, then the VCA's decay.
    # The pattern starts from dilla's DfamEngine and one step mutates every two
    # bars; decay and cutoff drift slowly, like the pads' knobs.
    DFAM_STEP = BAR / 32 # sixteenths
    DFAM_LEVEL = 0.16
    # Accents on the eight-step page: the downbeat and the and-of-two lean in.
    DFAM_SCENES = %i[euclid ratchet broken tribal].freeze
    # Each groove brings its own kick, as [cycle length, steps that hit].
    SCENE_KICKS = { euclid: [16, [0, 6, 10]], ratchet: [12, [0, 7]], broken: [16, [0, 3, 10, 11]], tribal: [12, [0, 5, 8]] }.freeze
    DFAM_RATES = { 1.0 => "16ths", (2.0 / 3) => "triplets", 0.5 => "32nds", 1.5 => "dotted 16ths", 2.0 => "8ths" }.freeze
    # A Euclidean rhythm: k hits spread as evenly as n steps allow.
    def self.euclid(k, n) = (@euclid ||= {})[[k, n]] ||= Array.new(n) { |i| ((i * k) % n) < k }
    # And its own lead rhythm, on sixteen steps.
    SCENE_LEAD = { euclid: euclid(5, 16), ratchet: euclid(6, 16), broken: Array.new(16) { |i| [0, 3, 6, 10, 12].include?(i) }, tribal: euclid(7, 16) }.freeze
    ACCENT = [1.35, 0.8, 1.0, 0.85, 1.25, 0.8, 1.1, 0.9].freeze
    KICK_LEVEL = 0.06
    # Off at the operator's word, and with them the rumble and the pump.
    KICKS_ON = false
    # The lead plays over every chord, at the operator's word.
    LEAD_ALWAYS = true
    # Muted at the operator's word; true brings the leads back.
    LEADS_ON = false
    # Turntablism on the pads: a scratch DJ's sharp-curve crossfader, two decks
    # (the two Moog layers) cut hard on the thirty-second grid. Each pattern is
    # 32 steps, one bar: A is deck A open, B deck B, - the fader closed. The
    # fader moves in half a millisecond, so every cut is a cut, not a blend.
    CUTS = {
      transformer: "A-A-A-A-A-A-A-A-A-A-A-A-A-A-A-A-",
      slow_transformer: "AA--AA--AA--AA--BB--BB--BB--BB--",
      crab: "A-A-A-A-AAAAAAAAB-B-B-B-BBBBBBBB",
      chirp: "AAA-----AAA-----BBB-----BBB-----",
      orbit: "A--AA--AA--AA--AB--BB--BB--BB--B",
      flare: "AAAA-AAA-AAAAAAAAAAA-AAA-AAAAAAA",
      ab_chop: "AAAABBBBAAAABBBB--AABB--AABBAB--",
      tear: "AAAAAAAA--------A-A-AAAA--------",
    }.freeze
    # The record under the crossfader: the cut pads write into three seconds of
    # buffer and are read back at a delay d that is zero in plain play, so the
    # deck adds no latency. A hand on the record moves d: the read speed is
    # 1 - d', so a growing d drops the pitch and a shrinking one raises it.
    #   baby      d rises and falls over a sixteenth: the push and pull.
    #   tape_stop the speed falls from 1 to 0 over a beat, the level with it.
    #   spinback  the record thrown backwards at three times speed, fading.
    DECK_LEN = RATE * 3
    # The dub throw: a send, open for the bar's last eighth when it fires, into
    # a dotted-eighth echo that darkens and thins as it repeats.
    DUB_LEN = RATE
    DUB_DELAY = (3 * DFAM_STEP * RATE).round
    DUB_LP = 1.0 - Math.exp(-2 * Math::PI * 1800.0 / RATE)
    DUB_HP = 1.0 - Math.exp(-2 * Math::PI * 220.0 / RATE)
    CUT_GLIDE = 1.0 - Math.exp(-1.0 / (0.0005 * RATE))
    # The Crystallizer, after Soundtoys: reversed grains of the lead, pitched up
    # an octave or a fifth, a quarter second late, fed back into themselves.
    # Two readers half a grain apart, Hann-windowed, crossfade into a shimmer.
    CRYS_LEN = RATE * 2
    CRYS_GRAIN = (RATE * 0.16).round
    CRYS_DELAY = (RATE * 0.25).round
    CRYS_FEEDBACK = 0.45
    CRYS_MIX = 0.5
    # The 909's hat: six detuned square waves, high-passed, then crushed to 12
    # bits the way an SP-1200 resample crunches it.
    HAT_HZ = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0].freeze
    HAT_LEVEL = 0.011
    # Rendered once: the squares, noise under them for grit, and the decay.
    hat_table = lambda do |len, decay|
      Array.new((len * RATE).to_i) do |i|
        th = i.to_f / RATE
        sq = HAT_HZ.sum { |f| ((th * f * 7.0) % 1.0) < 0.5 ? 1.0 : -1.0 }
        (sq + (((rand * 2.0) - 1.0) * 3.0)) * Math.exp(-th / decay)
      end.freeze
    end
    HAT_OPEN = hat_table.(0.3, 0.07)
    HAT_CLOSED = hat_table.(0.06, 0.015)
    # The shaker: noise alone, short, high-passed with the hats.
    SHAKER = Array.new((0.08 * RATE).to_i) { |i| ((rand * 2.0) - 1.0) * 2.0 * Math.exp(-i.to_f / RATE / 0.025) }.freeze
    CLAP_LEVEL = 0.08
    # The rumble: the kick sent into a dark reverb (three combs), distorted,
    # low-passed to 150 Hz, mono, and ducked by the kick itself.
    RUMBLE_LEVEL = 0.05
    COMBS = [1123, 1409, 1693].map { |len| Array.new(len, 0.0) }
    RUM_A = 1.0 - Math.exp(-2 * Math::PI * 150.0 / RATE)
    HAT_A = 1.0 - Math.exp(-2 * Math::PI * 7000.0 / RATE)
    DfamHit = Struct.new(:start, :f0, :vel, :ph1, :ph2, :ladder, :pan)
    class DfamKnob
      attr_reader :value
      def initialize(lo, hi, rng, speed:)
        @lo, @hi, @rng, @speed = lo, hi, rng, speed
        @x = 0.5
        @v = 0.0
        @push = nil
      end
      # A gesture: toward `target` (0..1) for `seconds`, then released.
      def lean(target, seconds, now) = @push = [target, now + seconds]
      def step(dt, now)
        @push = nil if @push && now > @push[1]
        pull = @push ? (@push[0] - @x) * 1.5 : (0.5 - @x) * 0.03
        @v = (@v * 0.992) + (@rng.rand(-1.0..1.0) * @speed * dt) + (pull * dt)
        @x = (@x + (@v * dt)).clamp(0.0, 1.0)
        @value = @lo + ((@hi - @lo) * @x)
      end
    end

    knob_rng = Random.new
    DFAM_KNOBS = {
      vcf_decay: DfamKnob.new(0.03, 0.22, knob_rng, speed: 0.08),
      vca_decay: DfamKnob.new(0.06, 0.28, knob_rng, speed: 0.07),
      cutoff: DfamKnob.new(500.0, 4200.0, knob_rng, speed: 0.1),
      resonance: DfamKnob.new(0.2, 0.85, knob_rng, speed: 0.06),
      fm: DfamKnob.new(0.0, 1.1, knob_rng, speed: 0.07),
      noise: DfamKnob.new(0.02, 0.45, knob_rng, speed: 0.05),
      pitch_amount: DfamKnob.new(0.6, 4.0, knob_rng, speed: 0.06),
      pitch_decay: DfamKnob.new(0.015, 0.12, knob_rng, speed: 0.05),
    }.freeze
    def self.sonitex(bits:, lo:, hi:, drive:, mix: 0.5, samples: 1)
      "volume=#{drive},acrusher=bits=#{bits}:mode=log:aa=1:mix=#{mix}:samples=#{samples}," \
        "highpass=f=#{lo},lowpass=f=#{hi},alimiter=limit=0.99"
    end

    # Level-neutral here: five stages at livesets' -7.5 dB each sank the pads 37 dB
    # under the kick. The colour stays; the loss does not.
    def self.vcs(depth:, smear:, db: 0.0)
      phaser_db = -2.6 + (10.9 * (depth - 0.26)) - (0.14 * (smear - 2.1))
      "aphaser=in_gain=0.75:out_gain=0.85:delay=#{smear}:decay=#{depth}:speed=0.5," \
        "aecho=0.9:1:#{smear.round}:0.08,volume=#{(db - phaser_db + 0.65).round(2)}dB"
    end

    MASTER = [
      vcs(depth: 0.34, smear: 2.4), sonitex(bits: 12, lo: 40, hi: 13_000, drive: 1.12),
      vcs(depth: 0.38, smear: 1.7), sonitex(bits: 13, lo: 42, hi: 15_000, drive: 1.04),
      vcs(depth: 0.26, smear: 3.6), sonitex(bits: 11, lo: 42, hi: 12_000, drive: 1.18),
      "alimiter=limit=0.95"
    ].join(",")
    def self.space_echo(head_ms, decays)
      taps = [1, 2, 3].map { |k| (head_ms * k).round }.join("|")
      "highpass=f=160,aecho=0.9:0.9:#{taps}:#{decays},lowpass=f=3200,chorus=0.9:0.9:25:0.35:0.6:1.8"
    end
    HEAD = BAR / 16 * 1000
    ARP_FX = "anull"
    # Extreme analog tape on the master channel, the whole sum: the head bump near
    # 60 Hz, the drive into tanh that tape saturation is (undone after, so it
    # colours rather than raises), the capstan's wow and flutter worn deep, the top
    # the tape cannot hold, and its hiss.
    def self.tape(drive:, wow:, flutter:, top:, hiss:)
      "equalizer=f=60:t=q:w=1.1:g=4.5,volume=#{drive},asoftclip=type=tanh,volume=#{(1.0 / drive).round(3)}," \
        "vibrato=f=0.42:d=#{wow},vibrato=f=6.8:d=#{flutter},lowpass=f=#{top},highpass=f=28," \
        "aeval=exprs=val(0)+#{hiss}*(2*random(0)-1)|val(1)+#{hiss}*(2*random(1)-1):c=same"
    end
    TAPE = tape(drive: 3.2, wow: 0.22, flutter: 0.07, top: 9_500, hiss: 0.004)
    # Arps on the arps, at the operator's word: the lead is split three ways. One
    # stays dry; one goes up a fifth and comes back an eighth late, the other up
    # an octave a dotted eighth late, so the echoes arpeggiate over the arpeggio.
    # Each pitched copy feeds back through its own echo the way a crystallizer
    # does, and the sum is sharpened with ffmpeg's crystalizer. The pitch shift is
    # asetrate then atempo, a resample and a time-stretch, which grains the copies.
    def self.pitched(ratio, delay_ms, echo_ms, decay)
      "asetrate=#{(RATE * ratio).round},aresample=#{RATE},atempo=#{(1.0 / ratio).round(4)}," \
        "adelay=#{delay_ms}|#{delay_ms},aecho=0.8:0.7:#{echo_ms}:#{decay}"
    end
    EIGHTH = (BAR / 16 * 1000).round
    ARPS_ON_ARPS = "asplit=3[ad][ax][ay];[ax]#{pitched(1.5, EIGHTH, EIGHTH * 2, 0.45)}[af];" \
                   "[ay]#{pitched(2.0, (EIGHTH * 1.5).round, EIGHTH * 3, 0.4)},highpass=f=900[ao];" \
                   "[ad][af][ao]amix=inputs=3:weights=1 0.5 0.35:normalize=0,crystalizer=i=1.5"
    # The leads sit lower in the sum, at the operator's word: 0.9 against the
    # main's 1 where they were 1.5.
    GRAPH = "[0:a]pan=stereo|c0=c0|c1=c1,#{MASTER}[m];[0:a]pan=stereo|c0=c2|c1=c3,#{ARPS_ON_ARPS}[a];[m][a]amix=inputs=2:weights=1 0.9:normalize=0,#{TAPE},alimiter=limit=0.96"

    def self.run(argv = [])
      loops = (argv[0] || 2).to_i

      voices = []
      rng = Random.new
      key = 5 # F minor, where the loved progression sits
      state = [0, :m9]
      voicing = CHORDS.first.last
      chord_i = 0
      moog_order = nil
      recent = []
      next_modulation = 8
      key = rng.rand(12)
      next_chord = 0.0
      log = File.open(File.join(__dir__, "..", "moog_improv.log"), "a").tap { |f| f.sync = true }
      total = Float::INFINITY
      pattern = { pitch: [50, 30, 60, 20, 55, 35, 65, 25], velocity: [80, 60, 90, 50, 85, 65, 95, 55] }
      dfam_rng = Random.new
      dfam_hits = []
      dfam_next = 0.0
      dfam_step = 0
      pattern_b = { pitch: [78, 64, 88, 70, 92], velocity: [55, 0, 70, 45, 60] }
      dfam_scene = nil
      next_scene_at = 0.0
      grid_next = 0.0
      grid_step = 0
      # A new groove, never the kind just played: its kind, its rate, and for a
      # generated one a Euclidean pattern of 2 to n-1 hits over 5 to 16 steps.
      new_scene = lambda do |last|
        kind = (DFAM_SCENES + %i[generated generated]).reject { |k| k == last && k != :generated }.sample(random: dfam_rng)
        rate, rate_name = DFAM_RATES.to_a.sample(random: dfam_rng)
        steps = dfam_rng.rand(5..16)
        hits = dfam_rng.rand(2..(steps - 1))
        label = kind == :generated ? "E(#{hits},#{steps}) in #{rate_name}" : "#{kind} in #{rate_name}"
        { kind:, rate:, label:, hits: euclid(hits, steps).rotate(dfam_rng.rand(steps)),
          pitches: Array.new(dfam_rng.rand(3..8)) { dfam_rng.rand(5..45) } }
      end
      kicks = []
      click_lp = 0.0
      cut_name = :transformer
      cut_bar = -1
      gain_a = 1.0
      gain_b = 0.0
      deck_l = Array.new(DECK_LEN, 0.0)
      deck_r = Array.new(DECK_LEN, 0.0)
      deck_w = 0
      deck_fx = nil # [kind, start]
      last_s32 = -1
      last_deck = "-"
      dub_l = Array.new(DUB_LEN, 0.0)
      dub_r = Array.new(DUB_LEN, 0.0)
      dub_w = 0
      dub_lp_l = dub_lp_r = dub_hp_l = dub_hp_r = 0.0
      dub_send = 0.0
      dub_throw = false
      crys_l = Array.new(CRYS_LEN, 0.0)
      crys_r = Array.new(CRYS_LEN, 0.0)
      crys_w = 0
      crys_p = 0
      crys_pitch = 2.0
      crys_out_l = crys_out_r = 0.0
      hats = []
      claps = []
      hat_lp = clap_lp = clap_hp = 0.0
      comb_i = [0, 0, 0]
      rum_lp1 = rum_lp2 = 0.0
      next_gesture = 8.0

      $stderr.puts "improvising: #{PADS.join(" -> ")} over moog_bass, DFAM on top"
      sox = IO.popen(["sh", "-c", "ffmpeg -loglevel error -f s16le -ar #{RATE} -ac 4 -i - -filter_complex '#{GRAPH}' -f s16le -ar #{RATE} -ac 2 - | sox -q -t raw -r #{RATE} -e signed -b 16 -c 2 - -d"], "wb")
      frame = 0
      frames = Float::INFINITY
      two_pi = 2 * Math::PI
      while frame < frames
        # The next chord, chosen a second before it sounds.
        while next_chord < (frame.to_f / RATE) + 1.0
          degree, quality = state
          voicing = voice_lead(QUALITIES[quality].map { |iv| (key + degree + iv) % 12 }, voicing)
          bass = 36 + ((key + degree) % 12)
          bass += 12 if bass < 36
          name = "#{NAMES[(key + degree) % 12]}#{quality}"
          recent << [(key + degree) % 12, quality]
          recent.shift if recent.size > 4
          options = MOVES.fetch(state).reject { |d, q| recent.include?([(key + d) % 12, q]) }
          options = MOVES.fetch(state) if options.empty?
          state = options.sample(random: rng)
          roll = rng.rand
          if roll < 0.08 # the tritone substitute: a dominant a flat fifth away
            key = (key + 6) % 12
            name += " (tritone sub next)"
          elsif roll < 0.14 # a chromatic side-step, up or down a semitone
            key = (key + [1, 11].sample(random: rng)) % 12
            name += " (side-step next)"
          end
          if chord_i >= next_modulation
            key = (key + [5, 3, 8, 10, 2, 7].sample(random: rng)) % 12
            state = [0, %i[m9 m11 m6_9].sample(random: rng)]
            next_modulation = chord_i + rng.rand(8..16)
            name += " -> #{NAMES[key]} minor"
          end
          moog_order = MOOG_CHORDS.keys.shuffle(random: rng) if (chord_i % (MORPH_CHORDS * MOOG_CHORDS.size)).zero?
          pad = moog_morph(moog_order, chord_i)
          pad_name = "#{moog_order[(chord_i / MORPH_CHORDS) % moog_order.size]} -> #{moog_order[((chord_i / MORPH_CHORDS) + 1) % moog_order.size]} #{(chord_i % MORPH_CHORDS) * 100 / MORPH_CHORDS}%"
          bass_patch = P.fetch(BASSES[(chord_i / 4) % BASSES.size])
          voicing.each { |m| voices << voice(m, pad, next_chord, CHORD_LEN - 0.1, 0.3, bass: :pad) }
          # The second layer, crossfaded against the first on a rhythm: the preset
          # two stops further round the Moog wheel, so the two never sound alike.
          pad_b = MOOG_CHORDS.fetch(moog_order[((chord_i / MORPH_CHORDS) + 2) % moog_order.size])
          voicing.each { |m| voices << voice(m, pad_b, next_chord, CHORD_LEN - 0.1, 0.3, bass: :pad_b) }
          # The rolling bass: the root on the three sixteenths after every kick,
          # short and even, the octave up on the last of each beat now and then.
          (CHORD_LEN / (BAR / 8)).round.times do |beat|
            [1, 2, 3].each do |sixteenth|
              up = sixteenth == 3 && rng.rand < 0.25 ? 12 : 0
              voices << voice(bass + up, bass_patch, next_chord + (beat * BAR / 8) + (sixteenth * DFAM_STEP), DFAM_STEP * 0.6, 0.4, bass: true)
            end
          end
          log.puts "#{Time.now.strftime("%H:%M:%S")} #{name} on #{pad_name}, bass #{BASSES[(chord_i / 4) % BASSES.size]}"
          if LEADS_ON && (LEAD_ALWAYS || rng.rand < 0.3)
            # The loved lead, dry: an arpeggio over the chord an octave up, its shape
            # drawn fresh, a new patch every four notes across every lead the synth has.
            arp_patches = RHODES_LEADS.keys.shuffle(random: rng)
            # An octave lower than before, and always climbing: the chord, then the
            # chord an octave up, arped upward.
            order = (voicing + voicing.map { |m| m + 12 }).sort
            step = BAR / 16
            16.times { |k| voices << voice(order[k % order.size], P.fetch(arp_patches[(k / 4) % arp_patches.size]), next_chord + (k * step), step * 0.7, 0.45, bass: :arp) }
            log.puts "  arp over it"
          end
          chord_i += 1
          next_chord += CHORD_LEN
        end
        n = BLOCK
        left = Array.new(n, 0.0)
        arp_l = Array.new(n, 0.0)
        arp_r = Array.new(n, 0.0)
        right = Array.new(n, 0.0)
        pad_l = Array.new(n, 0.0)
        padb_l = Array.new(n, 0.0)
        padb_r = Array.new(n, 0.0)
        pad_r = Array.new(n, 0.0)
        tb = frame.to_f / RATE
        ck = cutoff_knob(tb)
        rk = res_knob(tb)
        voices.each do |v|
          spec = v.spec
          rel = spec[:amp].release
          next if tb + (n.to_f / RATE) < v.start || tb > v.start + v.held + rel
          level = 1.0 / spec[:waves].size
          freqs = spec[:waves].each_index.map { |k| v.hz * (2.0**spec[:octaves][k]) * (2.0**(spec[:detune][k] / 1200.0)) }
          base_cut = spec[:cutoff] * (v.bass == true ? 0.7 + ck * 0.8 : 0.35 + ck * 1.6)
          res = v.bass == true ? spec[:resonance] : [spec[:resonance] + rk * 0.45, 0.85].min
          # The envelopes at control rate, every 16 samples: inaudible, and half the
          # cost that had the player at 100% of a core and dropping blocks.
          waves = spec[:waves]
          nw = waves.size
          out_l, out_r = case v.bass
                         when :arp then [arp_l, arp_r]
                         when :pad then [pad_l, pad_r]
                         when :pad_b then [padb_l, padb_r]
                         else [left, right]
                         end
          cut = ampv = 0.0
          j = 0
          while j < n
            t = tb + (j.to_f / RATE) - v.start
            if t >= 0
              if (j & 15).zero?
                shape = spec[:filter_env].at(t, v.held)
                shape = (shape * (1.0 - spec[:lpg])) + (spec[:amp].at(t, v.held) * spec[:lpg]) if spec[:lpg]
                cut = (base_cut + (spec[:env_amount] * shape)).clamp(30.0, 12_000.0)
                ampv = spec[:amp].at(t, v.held) * v.gain
              end
              raw = 0.0
              k = 0
              while k < nw
                v.phases[k] = (v.phases[k] + (freqs[k] / RATE)) % 1.0
                raw += S.wave(waves[k], v.phases[k]) * level
                k += 1
              end
              out = v.ladder.process(raw * spec[:drive], cut, res) * ampv
              out_l[j] += out * 0.52
              out_r[j] += out * 0.48
            end
            j += 1
          end
        end
      voices.reject! { |v| tb > v.start + v.held + v.spec[:amp].release }

      # Sequence the DFAM a block ahead, on its own clock. Every two to six bars
      # a new groove is drawn: one of the four named ones or a fresh Euclidean
      # pattern, at a rate of its own against the steady kick -- sixteenths,
      # triplets, thirty-seconds, dotted sixteenths or eighths. While it plays,
      # its pitches and its rotation keep mutating.
      while dfam_next < tb + (n.to_f / RATE)
        if dfam_scene.nil? || dfam_next >= next_scene_at
          dfam_scene = new_scene.(dfam_scene && dfam_scene[:kind])
          next_scene_at = dfam_next + ((BAR / 2) * dfam_rng.rand(2..6))
          log.puts "  dfam groove -> #{dfam_scene[:label]}"
        end
        step_len = DFAM_STEP * dfam_scene[:rate]
        hz = ->(p) { 32.0 * (2.0**(p / 100.0 * 4.0)) }
        add = ->(at, p, vel, pan) { dfam_hits << DfamHit.new(at, hz.(p), vel, 0.0, 0.0, S::Ladder.new(rate: RATE), pan) }
        pitches = dfam_scene[:pitches]
        case dfam_scene[:kind]
        when :generated
          if dfam_scene[:hits][dfam_step % dfam_scene[:hits].size]
            add.(dfam_next, pitches[dfam_step % pitches.size], dfam_rng.rand < 0.25 ? 1.1 : dfam_rng.rand(0.5..0.85), dfam_rng.rand(0.25..0.75))
          end
        when :euclid
          add.(dfam_next, pitches[dfam_step % pitches.size], 1.0, 0.45) if euclid(5, 16)[dfam_step % 16]
        when :ratchet
          if (dfam_step % 6).zero? || dfam_rng.rand < 0.12
            reps = dfam_rng.rand(2..4)
            p0 = dfam_rng.rand(25..45)
            reps.times { |r| add.(dfam_next + (r * step_len / 2), p0 - (r * 12), 0.9 - (r * 0.15), 0.3 + (0.4 * (r % 2))) }
          end
        when :broken
          add.(dfam_next, pitches[6 - (dfam_step % 7)] || pitches.first, dfam_rng.rand(0.4..1.0), dfam_rng.rand(0.2..0.8)) if dfam_rng.rand < 0.6
        when :tribal
          t12 = dfam_step % 12
          add.(dfam_next, pitches[t12 % pitches.size], [0, 3, 6].include?(t12) ? 1.1 : 0.6, 0.35 + (0.3 * (t12 % 2))) if euclid(7, 12)[t12]
        end
        # The mutation: now and then a pitch redrawn, the pattern turned a step.
        pitches[dfam_rng.rand(pitches.size)] = dfam_rng.rand(5..45) if dfam_rng.rand < 0.07
        dfam_scene[:hits] = dfam_scene[:hits].rotate(1) if dfam_rng.rand < 0.03
        dfam_step += 1
        dfam_next += step_len
      end
      # The industrial grid, after Attack Magazine's dissection: the kick four
      # on the floor, a closed hat on each offbeat, a shaker on every second
      # offbeat, a noise snare on two and four. The DFAM is the syncopated low tom.
      while grid_next < tb + (n.to_f / RATE)
        s16 = grid_step % 16
        kicks << grid_next if KICKS_ON && (s16 % 4).zero?
        hats << [grid_next, HAT_CLOSED, 0.9] if s16 % 4 == 2
        hats << [grid_next + 0.004, SHAKER, 0.6] if [6, 14].include?(s16)
        claps << grid_next if [4, 12].include?(s16)
        grid_step += 1
        grid_next += DFAM_STEP
      end
      kv = DFAM_KNOBS.transform_values { |k| k.step(n.to_f / RATE, tb) }
      if tb > next_gesture
        name = DFAM_KNOBS.keys.sample(random: knob_rng)
        target = knob_rng.rand < 0.5 ? knob_rng.rand(0.0..0.15) : knob_rng.rand(0.85..1.0)
        DFAM_KNOBS[name].lean(target, BAR * knob_rng.rand(0.5..1.5), tb)
        log.puts "  dfam: #{name} -> #{target > 0.5 ? "up" : "down"}"
        next_gesture = tb + knob_rng.rand(6.0..16.0)
      end
      vcf = kv[:vcf_decay]
      vca = kv[:vca_decay]
      cut_top = kv[:cutoff]
      dfam_hits.each do |h|
        pitch_env = cut = amp = 0.0
        j = 0
        while j < n
          tt = tb + (j.to_f / RATE) - h.start
          if tt >= 0
            if (j & 15).zero?
              pitch_env = 1.0 + (kv[:pitch_amount] * Math.exp(-tt / kv[:pitch_decay]))
              cut = 120.0 + (cut_top * Math.exp(-tt / vcf))
              amp = h.vel * Math.exp(-tt / vca) * DFAM_LEVEL
            end
            h.ph1 = (h.ph1 + (h.f0 * pitch_env / RATE)) % 1.0
            tri = S.wave(:triangle, h.ph1)
            h.ph2 = (h.ph2 + (h.f0 * 1.5 * pitch_env * (1.0 + (kv[:fm] * tri)) / RATE)) % 1.0
            sq = h.ph2 < 0.5 ? 1.0 : -1.0
            mix = (0.55 * tri) + (0.3 * sq) + (kv[:noise] * (rand * 2.0 - 1.0))
            out = h.ladder.process(mix, cut, kv[:resonance]) * amp
            left[j] += out * h.pan
            right[j] += out * (1.0 - h.pan)
          end
          j += 1
        end
      end
      dfam_hits.reject! { |h| tb - h.start > vca * 8 }
        bar = (tb / (BAR / 2)).floor
      if bar != cut_bar
        cut_bar = bar
      cut_name = CUTS.keys.sample(random: rng)
      bar_start = bar * (BAR / 2)
      beat = 4 * DFAM_STEP
      if (bar % 8) == 7 && rng.rand < 0.5
        deck_fx = [:spinback, bar_start + (3 * beat)]
        log.puts "  deck: spinback"
      elsif rng.rand < 0.12
        deck_fx = [:tape_stop, bar_start + (3 * beat)]
        log.puts "  deck: tape stop"
      end
      dub_throw = rng.rand < 0.25
      log.puts "  deck: dub throw" if dub_throw
        log.puts "  pads cut -> #{cut_name}"
      end
      cut = CUTS[cut_name]
      j = 0
      while j < n
        now = tb + (j.to_f / RATE)
        bus = 0.0
        duck = 0.0
        kicks.each do |t|
          tk = now - t
          next if tk.negative? || tk > 0.5
          d = Math.exp(-tk / 0.12)
          duck = d if d > duck
          phase = (50.0 * tk) + (170.0 * 0.012 * (1.0 - Math.exp(-tk / 0.012))) + (30.0 * 0.08 * (1.0 - Math.exp(-tk / 0.08)))
          bus += Math.sin(2 * Math::PI * phase) * Math.exp(-tk / 0.34)
          if tk < 0.003
            click_lp += 0.35 * ((rand * 2.0 - 1.0) - click_lp)
            bus += (click_lp * 1.2) + (tk < 0.0008 ? 0.6 : 0.0)
          end
        end
        # Driven into hard clipping and back: the distorted industrial kick.
        k = Math.tanh(Math.tanh(bus * 7.0) * 2.5)
        k = (k * 256).round / 256.0 * KICK_LEVEL # a bitcrusher for the crisp attack
        wet = 0.0
        c = 0
        while c < 3
          buf = COMBS[c]
          y = buf[comb_i[c]]
          buf[comb_i[c]] = k + (y * 0.8)
          comb_i[c] = (comb_i[c] + 1) % buf.size
          wet += y
          c += 1
        end
        rum_lp1 += RUM_A * (Math.tanh(wet * 12.0) - rum_lp1)
        rum_lp2 += RUM_A * (rum_lp1 - rum_lp2)
        rumble = rum_lp2 * RUMBLE_LEVEL * (1.0 - (0.9 * duck))
        metal = 0.0
        hats.each do |t, open, vel|
          idx = ((now - t) * RATE).to_i
          table = open
          metal += table[idx] * vel if idx >= 0 && idx < table.size
        end
        hat_lp += HAT_A * (metal - hat_lp)
        # Crushed to 12 bits and overdriven, the SP-1200 resample.
        hat = Math.tanh(((metal - hat_lp) * 32).round / 32.0 * 0.5) * 2.0 * HAT_LEVEL
        clap = 0.0
        claps.each do |t|
          tc = now - t
          next if tc.negative? || tc > 0.35
          burst = (1.0 - Math.exp(-tc / 0.004)) * Math.exp(-tc / 0.11)
          clap += ((rand * 2.0) - 1.0) * burst
        end
        clap_lp += 0.18 * (Math.tanh(clap * 2.5) - clap_lp)
        clap_hp += 0.05 * (clap_lp - clap_hp)
        drums = k + hat + ((clap_lp - clap_hp) * CLAP_LEVEL)
        # Parallel distortion on the drum bus: grit blended under the clean hits.
        drums += Math.tanh(drums * 12.0) * 0.025
        # The pads pump against the kick.
        pump = 1.0 - (0.25 * duck)

      deck = cut[(now / (DFAM_STEP / 2)).floor % 32]
      gain_a += CUT_GLIDE * ((deck == "A" ? 1.0 : 0.0) - gain_a)
      gain_b += CUT_GLIDE * ((deck == "B" ? 1.0 : 0.0) - gain_b)
      pl = (pad_l[j] * gain_a) + (padb_l[j] * gain_b)
      pr = (pad_r[j] * gain_a) + (padb_r[j] * gain_b)
      # Baby scratches: a third of the cuts that open the fader get a hand on it.
      s32 = (now / (DFAM_STEP / 2)).floor
      if s32 != last_s32
        deck_fx = [:baby, now] if last_deck == "-" && deck != "-" && deck_fx.nil? && rng.rand < 0.35
        last_s32 = s32
        last_deck = deck
      end
      deck_l[deck_w] = pl
      deck_r[deck_w] = pr
      d = 0.0
      deck_gain = 1.0
      if deck_fx && now >= deck_fx[1]
        x = now - deck_fx[1]
        case deck_fx[0]
        when :baby
          len = DFAM_STEP
          if x < len
            d = 0.018 * (1.0 - Math.cos(2 * Math::PI * x / len)) / 2.0
          else
            deck_fx = nil
          end
        when :tape_stop
          len = 4 * DFAM_STEP
          if x < len
            d = x * x / (2.0 * len)
            deck_gain = 1.0 - (x / len)
          else
            deck_fx = nil
          end
        when :spinback
          if x < 0.5
            d = x < 0.1 ? 20.0 * x * x : 0.2 + (4.0 * (x - 0.1))
            deck_gain = 1.0 - (x / 0.5)
          else
            deck_fx = nil
          end
        end
      end
      if d.positive?
        pos = deck_w - (d * RATE)
        i0 = pos.floor
        frac = pos - i0
        a = i0 % DECK_LEN
        b = (i0 + 1) % DECK_LEN
        pl = ((deck_l[a] * (1.0 - frac)) + (deck_l[b] * frac)) * deck_gain
        pr = ((deck_r[a] * (1.0 - frac)) + (deck_r[b] * frac)) * deck_gain
      elsif deck_gain < 1.0
        pl *= deck_gain
        pr *= deck_gain
      end
      deck_w = (deck_w + 1) % DECK_LEN
      # The dub throw: the send opens for the bar's last eighth.
      bar_pos = (now % (BAR / 2)) / (BAR / 2)
      dub_send += 0.002 * ((dub_throw && bar_pos > 0.875 ? 1.0 : 0.0) - dub_send)
      el = dub_l[(dub_w - DUB_DELAY) % DUB_LEN]
      er = dub_r[(dub_w - DUB_DELAY) % DUB_LEN]
      dub_lp_l += DUB_LP * (el - dub_lp_l)
      dub_lp_r += DUB_LP * (er - dub_lp_r)
      dub_hp_l += DUB_HP * (dub_lp_l - dub_hp_l)
      dub_hp_r += DUB_HP * (dub_lp_r - dub_hp_r)
      dub_l[dub_w] = (pl * dub_send) + ((dub_lp_r - dub_hp_r) * 0.6) # crossed: the echo walks
      dub_r[dub_w] = (pr * dub_send) + ((dub_lp_l - dub_hp_l) * 0.6)
      dub_w = (dub_w + 1) % DUB_LEN
      pl += (dub_lp_l - dub_hp_l) * 0.7
      pr += (dub_lp_r - dub_hp_r) * 0.7
      left[j] += (pl * pump) + drums + rumble
      right[j] += (pr * pump) + drums + rumble
      # The Crystallizer on the lead.
      cl = crys_out_l = 0.0
      cr = crys_out_r = 0.0
      2.times do |g|
        ph = (crys_p + (g * CRYS_GRAIN / 2)) % CRYS_GRAIN
        win = 0.5 - (0.5 * Math.cos(2 * Math::PI * ph / CRYS_GRAIN))
        at = (crys_w - CRYS_DELAY - ((CRYS_GRAIN - ph) * crys_pitch).to_i) % CRYS_LEN
        cl += crys_l[at] * win
        cr += crys_r[at] * win
      end
      crys_l[crys_w] = arp_l[j] + (cr * CRYS_FEEDBACK) # crossed, so the shimmer walks the field
      crys_r[crys_w] = arp_r[j] + (cl * CRYS_FEEDBACK)
      crys_w = (crys_w + 1) % CRYS_LEN
      crys_p += 1
      if crys_p >= CRYS_GRAIN * 24 # every few seconds, a fifth or an octave
        crys_p = 0
        crys_pitch = [2.0, 1.5, 2.0].sample(random: rng)
      end
      arp_l[j] += cl * CRYS_MIX
      arp_r[j] += cr * CRYS_MIX
      j += 1
      end
      kicks.reject! { |t| tb - t > 0.5 }
      hats.reject! { |t, _, _| tb - t > 0.1 }
      claps.reject! { |t| tb - t > 0.35 }
      pcm = Array.new(n * 4)
      n.times do |i|
        pcm[i * 4] = (Math.tanh(left[i]) * 29_000).round
        pcm[(i * 4) + 1] = (Math.tanh(right[i]) * 29_000).round
        pcm[(i * 4) + 2] = (Math.tanh(arp_l[i] * 1.4) * 26_000).round
        pcm[(i * 4) + 3] = (Math.tanh(arp_r[i] * 1.4) * 26_000).round
      end
      sox.write(pcm.pack("s<*"))
        frame += n
      end
      sox.close
    end
  end

  module Liveset864969335d0f
    # takes/liveset_864969335d0f.rb, frozen as heard (sha256 e616cc3bdd531da9d6236d0e70a1e4bddf970a85fe2b3fa2af29bc99874bde23).

    # MASTER's main sound, improvising: the frozen default (default_sound.rb),
    # with the chords chosen live instead of looped. It opens on the loved
    # progression, then walks soul-jazz harmony, each chord voiced nearest the
    # last, a new moog patch every two chords, the DFAM on top. Endless.

    RATE = 32_000
    BLOCK = 1_024
    S = AnalogSynth
    P = S::PATCHES.dup

    def self.hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

    # Fm9, Bbm9, Eb13, Abmaj9, Dbmaj7#11, C7alt: soul-jazz, Dilla territory.
    CHORDS = [
      [41, [56, 60, 63, 67]], [46, [56, 61, 65, 68]], [39, [55, 60, 61, 65]],
      [44, [55, 60, 63, 70]], [37, [60, 65, 67, 72]], [36, [58, 61, 64, 68]],
    ]
    SNAP = { amp: S::Envelope.new(attack: 0.004, decay: 0.3, sustain: 0.35, release: 0.18),
             filter_env: S::Envelope.new(attack: 0.002, decay: 0.22, sustain: 0.2, release: 0.15) }.freeze
    PROPHET_LEADS = {
      prophet_five_lead: P[:prophet_five].merge(SNAP),
      prophet_pad_lead: P[:prophet_pad].merge(SNAP),
      prophet_poly: P[:poly_lead].merge(SNAP),
      prophet_bright: P[:prophet_five].merge(SNAP).merge(cutoff: 900.0, resonance: 0.42),
    }.freeze
    P.merge!(PROPHET_LEADS)
    PADS = %i[warm_pad poly_strings prophet_five juno_pad prophet_pad vp330_ensemble soft_reed e_piano rhodes_tine glass_bell]
    BASSES = %i[moog_bass acid sub dub_bass]
    QUALITIES = {
      m9: [3, 7, 10, 14], m11: [3, 7, 10, 17], maj9: [4, 7, 11, 14], maj7s11: [4, 7, 11, 18],
      d13: [4, 10, 14, 21], alt: [4, 10, 13, 15], m6_9: [3, 7, 9, 14], sus13: [5, 10, 14, 21],
    }.freeze
    MOVES = {
      [0, :m9] => [[5, :m9], [10, :d13], [8, :maj9], [5, :m11], [3, :maj9]],
      [0, :m11] => [[5, :m9], [8, :maj7s11], [10, :sus13]],
      [5, :m9] => [[10, :d13], [7, :alt], [3, :maj9], [0, :m6_9]],
      [5, :m11] => [[10, :d13], [7, :alt]],
      [10, :d13] => [[3, :maj9], [8, :maj9], [0, :m9]],
      [10, :sus13] => [[10, :d13], [3, :maj9]],
      [3, :maj9] => [[8, :maj9], [5, :m9], [1, :maj7s11]],
      [8, :maj9] => [[1, :maj7s11], [7, :alt], [5, :m9]],
      [8, :maj7s11] => [[7, :alt], [1, :maj7s11]],
      [1, :maj7s11] => [[7, :alt], [0, :m9], [0, :m11]],
      [7, :alt] => [[0, :m9], [0, :m11], [8, :maj9]],
      [0, :m6_9] => [[5, :m9], [10, :d13]],
    }.freeze
    NAMES = %w[C Db D Eb E F Gb G Ab A Bb B].freeze

    def self.voice_lead(pcs, previous)
      pcs.each_with_index.map do |pc, idx|
        centre = previous[idx] || previous.last
        (53..74).select { |m| m % 12 == pc }.min_by { |m| (m - centre).abs }
      end.sort.uniq
    end
    BAR = 3.9

    Voice = Struct.new(:hz, :spec, :start, :held, :gain, :phases, :ladder, :bass)

    def self.voice(midi, spec, start, held, gain, bass: false)
      rng = Random.new(midi * 7 + (start * 10).to_i)
      Voice.new(hz(midi) * 2.0**(rng.rand(-0.7..0.7) / 1200.0), spec, start, held, gain,
                spec[:waves].map { rng.rand }, S::Ladder.new(rate: RATE), bass)
    end

    # The knobs: cutoff breathes over 23 s, resonance over 31 s, out of phase.
    def self.cutoff_knob(t) = 0.55 + 0.45 * Math.sin(2 * Math::PI * t / 23.0)
    def self.res_knob(t) = 0.5 + 0.5 * Math.sin(2 * Math::PI * t / 31.0 + 1.3)

    # The DFAM, as the Moog is built: an 8-step sequencer, each step its own pitch
    # and velocity, running in sixteenths; VCO 1 a triangle frequency-modulating
    # VCO 2, a square; both with a pitch envelope that falls; noise mixed in; all
    # of it through a ladder low-pass with its own decay, then the VCA's decay.
    # The pattern starts from dilla's DfamEngine and one step mutates every two
    # bars; decay and cutoff drift slowly, like the pads' knobs.
    DFAM_STEP = BAR / 24
    DFAM_LEVEL = 0.34
    # Accents on the eight-step page: the downbeat and the and-of-two lean in.
    ACCENT = [1.35, 0.8, 1.0, 0.85, 1.25, 0.8, 1.1, 0.9].freeze
    KICK_LEVEL = 0.09
    # The lead plays over every chord, at the operator's word.
    LEAD_ALWAYS = true
    DfamHit = Struct.new(:start, :f0, :vel, :ph1, :ph2, :ladder, :pan)
    class DfamKnob
      attr_reader :value
      def initialize(lo, hi, rng, speed:)
        @lo, @hi, @rng, @speed = lo, hi, rng, speed
        @x = 0.5
        @v = 0.0
        @push = nil
      end
      # A gesture: toward `target` (0..1) for `seconds`, then released.
      def lean(target, seconds, now) = @push = [target, now + seconds]
      def step(dt, now)
        @push = nil if @push && now > @push[1]
        pull = @push ? (@push[0] - @x) * 1.5 : (0.5 - @x) * 0.03
        @v = (@v * 0.992) + (@rng.rand(-1.0..1.0) * @speed * dt) + (pull * dt)
        @x = (@x + (@v * dt)).clamp(0.0, 1.0)
        @value = @lo + ((@hi - @lo) * @x)
      end
    end

    knob_rng = Random.new
    DFAM_KNOBS = {
      vcf_decay: DfamKnob.new(0.03, 0.22, knob_rng, speed: 0.08),
      vca_decay: DfamKnob.new(0.06, 0.28, knob_rng, speed: 0.07),
      cutoff: DfamKnob.new(500.0, 4200.0, knob_rng, speed: 0.1),
      resonance: DfamKnob.new(0.2, 0.85, knob_rng, speed: 0.06),
      fm: DfamKnob.new(0.0, 1.1, knob_rng, speed: 0.07),
      noise: DfamKnob.new(0.02, 0.45, knob_rng, speed: 0.05),
      pitch_amount: DfamKnob.new(0.6, 4.0, knob_rng, speed: 0.06),
      pitch_decay: DfamKnob.new(0.015, 0.12, knob_rng, speed: 0.05),
    }.freeze
    def self.sonitex(bits:, lo:, hi:, drive:, mix: 0.5, samples: 1)
      "volume=#{drive},acrusher=bits=#{bits}:mode=log:aa=1:mix=#{mix}:samples=#{samples}," \
        "highpass=f=#{lo},lowpass=f=#{hi},alimiter=limit=0.99"
    end

    # Level-neutral here: five stages at livesets' -7.5 dB each sank the pads 37 dB
    # under the kick. The colour stays; the loss does not.
    def self.vcs(depth:, smear:, db: 0.0)
      phaser_db = -2.6 + (10.9 * (depth - 0.26)) - (0.14 * (smear - 2.1))
      "aphaser=in_gain=0.75:out_gain=0.85:delay=#{smear}:decay=#{depth}:speed=0.5," \
        "aecho=0.9:1:#{smear.round}:0.08,volume=#{(db - phaser_db + 0.65).round(2)}dB"
    end

    MASTER = [
      vcs(depth: 0.34, smear: 2.4), sonitex(bits: 12, lo: 40, hi: 13_000, drive: 1.12),
      vcs(depth: 0.38, smear: 1.7), sonitex(bits: 13, lo: 42, hi: 15_000, drive: 1.04),
      vcs(depth: 0.26, smear: 3.6), sonitex(bits: 11, lo: 42, hi: 12_000, drive: 1.18),
      "alimiter=limit=0.95"
    ].join(",")
    def self.space_echo(head_ms, decays)
      taps = [1, 2, 3].map { |k| (head_ms * k).round }.join("|")
      "highpass=f=160,aecho=0.9:0.9:#{taps}:#{decays},lowpass=f=3200,chorus=0.9:0.9:25:0.35:0.6:1.8"
    end
    HEAD = BAR / 16 * 1000
    ARP_FX = "afreqshift=shift=6:level=1,flanger=delay=3:depth=6:regen=35:speed=0.13:width=80,vibrato=f=4.8:d=0.18,acrusher=bits=9:mix=0.22:mode=log:aa=1,apulsator=hz=0.21:amount=0.7"
    GRAPH = "[0:a]pan=stereo|c0=c0|c1=c1,#{MASTER}[m];[0:a]pan=stereo|c0=c2|c1=c3,#{ARP_FX}[a];[m][a]amix=inputs=2:weights=1 1:normalize=0,alimiter=limit=0.96"

    def self.run(argv = [])
      loops = (argv[0] || 2).to_i

      voices = []
      rng = Random.new
      key = 5 # F minor, where the loved progression sits
      state = [0, :m9]
      voicing = CHORDS.first.last
      chord_i = 0
      recent = []
      next_modulation = 8
      key = rng.rand(12)
      next_chord = 0.0
      log = File.open(File.join(__dir__, "..", "moog_improv.log"), "a").tap { |f| f.sync = true }
      total = Float::INFINITY
      pattern = { pitch: [50, 30, 60, 20, 55, 35, 65, 25], velocity: [80, 60, 90, 50, 85, 65, 95, 55] }
      dfam_rng = Random.new
      dfam_hits = []
      dfam_next = 0.0
      dfam_step = 0
      pattern_b = { pitch: [78, 64, 88, 70, 92], velocity: [55, 0, 70, 45, 60] }
      kicks = []
      click_lp = 0.0
      next_gesture = 8.0

      $stderr.puts "improvising: #{PADS.join(" -> ")} over moog_bass, DFAM on top"
      sox = IO.popen(["sh", "-c", "ffmpeg -loglevel error -f s16le -ar #{RATE} -ac 4 -i - -filter_complex '#{GRAPH}' -f s16le -ar #{RATE} -ac 2 - | sox -q -t raw -r #{RATE} -e signed -b 16 -c 2 - -d"], "wb")
      frame = 0
      frames = Float::INFINITY
      two_pi = 2 * Math::PI
      while frame < frames
        # The next chord, chosen a second before it sounds.
        while next_chord < (frame.to_f / RATE) + 1.0
          degree, quality = state
          voicing = voice_lead(QUALITIES[quality].map { |iv| (key + degree + iv) % 12 }, voicing)
          bass = 36 + ((key + degree) % 12)
          bass += 12 if bass < 36
          name = "#{NAMES[(key + degree) % 12]}#{quality}"
          recent << [(key + degree) % 12, quality]
          recent.shift if recent.size > 4
          options = MOVES.fetch(state).reject { |d, q| recent.include?([(key + d) % 12, q]) }
          options = MOVES.fetch(state) if options.empty?
          state = options.sample(random: rng)
          roll = rng.rand
          if roll < 0.08 # the tritone substitute: a dominant a flat fifth away
            key = (key + 6) % 12
            name += " (tritone sub next)"
          elsif roll < 0.14 # a chromatic side-step, up or down a semitone
            key = (key + [1, 11].sample(random: rng)) % 12
            name += " (side-step next)"
          end
          if chord_i >= next_modulation
            key = (key + [5, 3, 8, 10, 2, 7].sample(random: rng)) % 12
            state = [0, %i[m9 m11 m6_9].sample(random: rng)]
            next_modulation = chord_i + rng.rand(8..16)
            name += " -> #{NAMES[key]} minor"
          end
          pad = P.fetch(PADS[chord_i % PADS.size])
          bass_patch = P.fetch(BASSES[(chord_i / 4) % BASSES.size])
          voicing.each { |m| voices << voice(m, pad, next_chord, BAR - 0.1, 0.22) }
          # Moog bass: the chord root twice a bar, the second a little late.
          voices << voice(bass, bass_patch, next_chord, 1.6, 0.55, bass: true)
          voices << voice(bass, bass_patch, next_chord + (BAR * 0.534), 1.2, 0.45, bass: true)
          log.puts "#{Time.now.strftime("%H:%M:%S")} #{name} on #{PADS[chord_i % PADS.size]}, bass #{BASSES[(chord_i / 4) % BASSES.size]}"
          if LEAD_ALWAYS || rng.rand < 0.3
      ensemble = PROPHET_LEADS.keys.shuffle(random: rng)
      pendulum = [0, 1, 2, 3, 2, 1]
      bag = (voicing + voicing.map { |m| m + 12 }).sort.map { |m| m + 12 }
      pick = rng.rand(bag.size)
      step = BAR / 16
      16.times do |k|
        next if pattern[:velocity][k % 8].zero? # the bag rests where the DFAM does
        pick = (pick + [-1, 1].sample(random: rng)).clamp(0, bag.size - 1)
        spec = P.fetch(ensemble[pendulum[k % pendulum.size]]).merge(lpg: 0.8)
        vel = pattern[:velocity][k % 8] / 100.0
        voices << voice(bag[pick], spec, next_chord + (k * step), step * 0.7, 0.28 * vel.clamp(0.5, 1.0), bass: :arp)
      end
            log.puts "  arp: bag over the dfam rhythm, hocket across #{ensemble.join(" ")}"
          end
          chord_i += 1
          next_chord += BAR
        end
        n = BLOCK
        left = Array.new(n, 0.0)
        arp_l = Array.new(n, 0.0)
        arp_r = Array.new(n, 0.0)
        right = Array.new(n, 0.0)
        tb = frame.to_f / RATE
        ck = cutoff_knob(tb)
        rk = res_knob(tb)
        voices.each do |v|
          spec = v.spec
          rel = spec[:amp].release
          next if tb + (n.to_f / RATE) < v.start || tb > v.start + v.held + rel
          level = 1.0 / spec[:waves].size
          freqs = spec[:waves].each_index.map { |k| v.hz * (2.0**spec[:octaves][k]) * (2.0**(spec[:detune][k] / 1200.0)) }
          base_cut = spec[:cutoff] * (v.bass == true ? 0.7 + ck * 0.8 : 0.35 + ck * 1.6)
          res = v.bass == true ? spec[:resonance] : [spec[:resonance] + rk * 0.45, 0.85].min
          # The envelopes at control rate, every 16 samples: inaudible, and half the
          # cost that had the player at 100% of a core and dropping blocks.
          waves = spec[:waves]
          nw = waves.size
          out_l, out_r = v.bass == :arp ? [arp_l, arp_r] : [left, right]
          cut = ampv = 0.0
          j = 0
          while j < n
            t = tb + (j.to_f / RATE) - v.start
            if t >= 0
              if (j & 15).zero?
                shape = spec[:filter_env].at(t, v.held)
                shape = (shape * (1.0 - spec[:lpg])) + (spec[:amp].at(t, v.held) * spec[:lpg]) if spec[:lpg]
                cut = (base_cut + (spec[:env_amount] * shape)).clamp(30.0, 12_000.0)
                ampv = spec[:amp].at(t, v.held) * v.gain
              end
              raw = 0.0
              k = 0
              while k < nw
                v.phases[k] = (v.phases[k] + (freqs[k] / RATE)) % 1.0
                raw += S.wave(waves[k], v.phases[k]) * level
                k += 1
              end
              out = v.ladder.process(raw * spec[:drive], cut, res) * ampv
              out_l[j] += out * 0.52
              out_r[j] += out * 0.48
            end
            j += 1
          end
        end

      voices.reject! { |v| tb > v.start + v.held + v.spec[:amp].release }

      # Sequence the DFAM a block ahead.
      while dfam_next < tb + (n.to_f / RATE)
        step = dfam_step % 8
        vel = pattern[:velocity][step] / 100.0 * ACCENT[step]
        if vel.positive?
          f0 = 40.0 * (2.0**(pattern[:pitch][step] / 100.0 * 3.0))
          dfam_hits << DfamHit.new(dfam_next, f0, vel, 0.0, 0.0, S::Ladder.new(rate: RATE), 0.35 + (0.3 * (step % 2)))
        end
      b = dfam_step % 5
      if pattern_b[:velocity][b].positive?
        fb = 40.0 * (2.0**(pattern_b[:pitch][b] / 100.0 * 3.0))
        dfam_hits << DfamHit.new(dfam_next + 0.004, fb, pattern_b[:velocity][b] / 100.0 * 0.55, 0.0, 0.0, S::Ladder.new(rate: RATE), b.even? ? 0.25 : 0.75)
      end
      # The kick on every beat: four steps of the sequencer.
      kicks << dfam_next if (dfam_step % 4).zero?
      dfam_step += 1
        if (dfam_step % 32).zero?
          k = dfam_rng.rand(8)
          pattern[:pitch][k] = (pattern[:pitch][k] + dfam_rng.rand(-18..18)).clamp(5, 95)
          pattern[:velocity][k] = dfam_rng.rand < 0.15 ? 0 : (pattern[:velocity][k] + dfam_rng.rand(-20..20)).clamp(35, 100)
        end
        dfam_next += DFAM_STEP
      end
      kv = DFAM_KNOBS.transform_values { |k| k.step(n.to_f / RATE, tb) }
      if tb > next_gesture
        name = DFAM_KNOBS.keys.sample(random: knob_rng)
        target = knob_rng.rand < 0.5 ? knob_rng.rand(0.0..0.15) : knob_rng.rand(0.85..1.0)
        DFAM_KNOBS[name].lean(target, BAR * knob_rng.rand(0.5..1.5), tb)
        log.puts "  dfam: #{name} -> #{target > 0.5 ? "up" : "down"}"
        next_gesture = tb + knob_rng.rand(6.0..16.0)
      end
      vcf = kv[:vcf_decay]
      vca = kv[:vca_decay]
      cut_top = kv[:cutoff]
      dfam_hits.each do |h|
        pitch_env = cut = amp = 0.0
        j = 0
        while j < n
          tt = tb + (j.to_f / RATE) - h.start
          if tt >= 0
            if (j & 15).zero?
              pitch_env = 1.0 + (kv[:pitch_amount] * Math.exp(-tt / kv[:pitch_decay]))
              cut = 120.0 + (cut_top * Math.exp(-tt / vcf))
              amp = h.vel * Math.exp(-tt / vca) * DFAM_LEVEL
            end
            h.ph1 = (h.ph1 + (h.f0 * pitch_env / RATE)) % 1.0
            tri = S.wave(:triangle, h.ph1)
            h.ph2 = (h.ph2 + (h.f0 * 1.5 * pitch_env * (1.0 + (kv[:fm] * tri)) / RATE)) % 1.0
            sq = h.ph2 < 0.5 ? 1.0 : -1.0
            mix = (0.55 * tri) + (0.3 * sq) + (kv[:noise] * (rand * 2.0 - 1.0))
            out = h.ladder.process(mix, cut, kv[:resonance]) * amp
            left[j] += out * h.pan
            right[j] += out * (1.0 - h.pan)
          end
          j += 1
        end
      end
      dfam_hits.reject! { |h| tb - h.start > vca * 8 }
      j = 0
      while j < n
        now = tb + (j.to_f / RATE)
        bus = 0.0
        kicks.each do |t|
          tk = now - t
          next if tk.negative? || tk > 0.5
          phase = (50.0 * tk) + (170.0 * 0.012 * (1.0 - Math.exp(-tk / 0.012))) + (30.0 * 0.08 * (1.0 - Math.exp(-tk / 0.08)))
          bus += Math.sin(2 * Math::PI * phase) * Math.exp(-tk / 0.34)
          if tk < 0.003
            click_lp += 0.35 * ((rand * 2.0 - 1.0) - click_lp)
            bus += (click_lp * 1.2) + (tk < 0.0008 ? 0.6 : 0.0)
          end
        end
        k = Math.tanh(bus * 1.8) * KICK_LEVEL
        left[j] += k
        right[j] += k
        j += 1
      end

      kicks.reject! { |t| tb - t > 0.5 }
      pcm = Array.new(n * 4)
      n.times do |i|
        pcm[i * 4] = (Math.tanh(left[i] * 1.4) * 26_000).round
        pcm[(i * 4) + 1] = (Math.tanh(right[i] * 1.4) * 26_000).round
        pcm[(i * 4) + 2] = (Math.tanh(arp_l[i] * 1.4) * 26_000).round
        pcm[(i * 4) + 3] = (Math.tanh(arp_r[i] * 1.4) * 26_000).round
      end
      sox.write(pcm.pack("s<*"))
        frame += n
      end
      sox.close
    end
  end

  module LivesetDb4ddf1a
    # takes/liveset_db4ddf1a.rb, frozen as heard (sha256 eefa23e337dd760700a5ebcaa11b833b2b2820ba55db46f0030e15afa41f6f8d).

    # MASTER's main sound, improvising: the frozen default (default_sound.rb),
    # with the chords chosen live instead of looped. It opens on the loved
    # progression, then walks soul-jazz harmony, each chord voiced nearest the
    # last, a new moog patch every two chords, the DFAM on top. Endless.

    RATE = 32_000
    BLOCK = 1_024
    S = AnalogSynth
    P = S::PATCHES

    def self.hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

    # Fm9, Bbm9, Eb13, Abmaj9, Dbmaj7#11, C7alt: soul-jazz, Dilla territory.
    CHORDS = [
      [41, [56, 60, 63, 67]], [46, [56, 61, 65, 68]], [39, [55, 60, 61, 65]],
      [44, [55, 60, 63, 70]], [37, [60, 65, 67, 72]], [36, [58, 61, 64, 68]],
    ]
    PADS = %i[warm_pad poly_strings prophet_five juno_pad prophet_pad vp330_ensemble soft_reed e_piano rhodes_tine glass_bell]
    BASSES = %i[moog_bass acid sub dub_bass]
    QUALITIES = {
      m9: [3, 7, 10, 14], m11: [3, 7, 10, 17], maj9: [4, 7, 11, 14], maj7s11: [4, 7, 11, 18],
      d13: [4, 10, 14, 21], alt: [4, 10, 13, 15], m6_9: [3, 7, 9, 14], sus13: [5, 10, 14, 21],
    }.freeze
    MOVES = {
      [0, :m9] => [[5, :m9], [10, :d13], [8, :maj9], [5, :m11], [3, :maj9]],
      [0, :m11] => [[5, :m9], [8, :maj7s11], [10, :sus13]],
      [5, :m9] => [[10, :d13], [7, :alt], [3, :maj9], [0, :m6_9]],
      [5, :m11] => [[10, :d13], [7, :alt]],
      [10, :d13] => [[3, :maj9], [8, :maj9], [0, :m9]],
      [10, :sus13] => [[10, :d13], [3, :maj9]],
      [3, :maj9] => [[8, :maj9], [5, :m9], [1, :maj7s11]],
      [8, :maj9] => [[1, :maj7s11], [7, :alt], [5, :m9]],
      [8, :maj7s11] => [[7, :alt], [1, :maj7s11]],
      [1, :maj7s11] => [[7, :alt], [0, :m9], [0, :m11]],
      [7, :alt] => [[0, :m9], [0, :m11], [8, :maj9]],
      [0, :m6_9] => [[5, :m9], [10, :d13]],
    }.freeze
    NAMES = %w[C Db D Eb E F Gb G Ab A Bb B].freeze

    def self.voice_lead(pcs, previous)
      pcs.each_with_index.map do |pc, idx|
        centre = previous[idx] || previous.last
        (53..74).select { |m| m % 12 == pc }.min_by { |m| (m - centre).abs }
      end.sort.uniq
    end
    BAR = 4.4

    Voice = Struct.new(:hz, :spec, :start, :held, :gain, :phases, :ladder, :bass)

    def self.voice(midi, spec, start, held, gain, bass: false)
      rng = Random.new(midi * 7 + (start * 10).to_i)
      Voice.new(hz(midi) * 2.0**(rng.rand(-0.7..0.7) / 1200.0), spec, start, held, gain,
                spec[:waves].map { rng.rand }, S::Ladder.new(rate: RATE), bass)
    end

    # The knobs: cutoff breathes over 23 s, resonance over 31 s, out of phase.
    def self.cutoff_knob(t) = 0.55 + 0.45 * Math.sin(2 * Math::PI * t / 23.0)
    def self.res_knob(t) = 0.5 + 0.5 * Math.sin(2 * Math::PI * t / 31.0 + 1.3)

    # The DFAM, as the Moog is built: an 8-step sequencer, each step its own pitch
    # and velocity, running in sixteenths; VCO 1 a triangle frequency-modulating
    # VCO 2, a square; both with a pitch envelope that falls; noise mixed in; all
    # of it through a ladder low-pass with its own decay, then the VCA's decay.
    # The pattern starts from dilla's DfamEngine and one step mutates every two
    # bars; decay and cutoff drift slowly, like the pads' knobs.
    DFAM_STEP = BAR / 24
    DFAM_LEVEL = 0.34
    # Accents on the eight-step page: the downbeat and the and-of-two lean in.
    ACCENT = [1.35, 0.8, 1.0, 0.85, 1.25, 0.8, 1.1, 0.9].freeze
    KICK_LEVEL = 0.34
    DfamHit = Struct.new(:start, :f0, :vel, :ph1, :ph2, :ladder, :pan)
    def self.vcf_decay_knob(t) = 0.05 + 0.1 * (0.5 + 0.5 * Math.sin(2 * Math::PI * t / 37.0))
    def self.vca_decay_knob(t) = 0.09 + 0.12 * (0.5 + 0.5 * Math.sin(2 * Math::PI * t / 29.0 + 0.7))
    def self.dfam_cut_knob(t) = 900.0 + 2600.0 * (0.5 + 0.5 * Math.sin(2 * Math::PI * t / 43.0 + 2.1))
    def self.sonitex(bits:, lo:, hi:, drive:, mix: 0.5, samples: 1)
      "volume=#{drive},acrusher=bits=#{bits}:mode=log:aa=1:mix=#{mix}:samples=#{samples}," \
        "highpass=f=#{lo},lowpass=f=#{hi},alimiter=limit=0.99"
    end

    # Level-neutral here: five stages at livesets' -7.5 dB each sank the pads 37 dB
    # under the kick. The colour stays; the loss does not.
    def self.vcs(depth:, smear:, db: 0.0)
      phaser_db = -2.6 + (10.9 * (depth - 0.26)) - (0.14 * (smear - 2.1))
      "aphaser=in_gain=0.75:out_gain=0.85:delay=#{smear}:decay=#{depth}:speed=0.5," \
        "aecho=0.9:1:#{smear.round}:0.08,volume=#{(db - phaser_db + 0.65).round(2)}dB"
    end

    MASTER = [
      vcs(depth: 0.34, smear: 2.4), sonitex(bits: 12, lo: 40, hi: 13_000, drive: 1.12),
      vcs(depth: 0.3, smear: 2.8), "alimiter=limit=0.95"
    ].join(",")

    def self.run(argv = [])
      loops = (argv[0] || 2).to_i

      voices = []
      rng = Random.new
      key = 5 # F minor, where the loved progression sits
      state = [0, :m9]
      voicing = CHORDS.first.last
      chord_i = 0
      next_chord = 0.0
      log = File.open(File.join(__dir__, "..", "moog_improv.log"), "a").tap { |f| f.sync = true }
      total = Float::INFINITY
      pattern = { pitch: [50, 30, 60, 20, 55, 35, 65, 25], velocity: [80, 60, 90, 50, 85, 65, 95, 55] }
      dfam_rng = Random.new
      dfam_hits = []
      dfam_next = 0.0
      dfam_step = 0
      pattern_b = { pitch: [78, 64, 88, 70, 92], velocity: [55, 0, 70, 45, 60] }
      kicks = []

      $stderr.puts "improvising: #{PADS.join(" -> ")} over moog_bass, DFAM on top"
      sox = IO.popen(["sh", "-c", "ffmpeg -loglevel error -f s16le -ar #{RATE} -ac 2 -i - -af '#{MASTER}' -f s16le -ar #{RATE} -ac 2 - | sox -q -t raw -r #{RATE} -e signed -b 16 -c 2 - -d"], "wb")
      frame = 0
      frames = Float::INFINITY
      two_pi = 2 * Math::PI
      while frame < frames
        # The next chord, chosen a second before it sounds.
        while next_chord < (frame.to_f / RATE) + 1.0
          if chord_i < CHORDS.size
            bass, tones = CHORDS[chord_i]
            voicing = tones
            name = "loved #{chord_i + 1}"
          else
            degree, quality = state
            voicing = voice_lead(QUALITIES[quality].map { |iv| (key + degree + iv) % 12 }, voicing)
            bass = 36 + ((key + degree) % 12)
            bass += 12 if bass < 36
            name = "#{NAMES[(key + degree) % 12]}#{quality}"
            state = MOVES.fetch(state).sample(random: rng)
            if (chord_i % 24).zero? && state.first.zero?
              key = (key + [5, 3, 8, 10].sample(random: rng)) % 12
              state = [0, %i[m9 m11].sample(random: rng)]
            end
          end
          pad = P.fetch(PADS[chord_i % PADS.size])
          bass_patch = P.fetch(BASSES[(chord_i / 4) % BASSES.size])
          voicing.each { |m| voices << voice(m, pad, next_chord, BAR - 0.1, 0.22) }
          # Moog bass: the chord root twice a bar, the second a little late.
          voices << voice(bass, bass_patch, next_chord, 1.6, 0.55, bass: true)
          voices << voice(bass, bass_patch, next_chord + 2.35, 1.2, 0.45, bass: true)
          log.puts "#{Time.now.strftime("%H:%M:%S")} #{name} on #{PADS[chord_i % PADS.size]}, bass #{BASSES[(chord_i / 4) % BASSES.size]}"
          if rng.rand < 0.3
            arp_patch = P.fetch(%i[glass_bell e_piano poly_lead vapor_lead].sample(random: rng))
            notes = voicing.map { |m| m + 12 }
            order = [notes, notes.reverse, notes + notes.reverse[1..-2], notes.shuffle(random: rng)].sample(random: rng)
            step = BAR / 16
            16.times { |k| voices << voice(order[k % order.size], arp_patch, next_chord + (k * step), step * 0.7, 0.1) }
            log.puts "  arp over it"
          end
          chord_i += 1
          next_chord += BAR
        end
        n = BLOCK
        left = Array.new(n, 0.0)
        right = Array.new(n, 0.0)
        tb = frame.to_f / RATE
        ck = cutoff_knob(tb)
        rk = res_knob(tb)
        voices.each do |v|
          spec = v.spec
          rel = spec[:amp].release
          next if tb + (n.to_f / RATE) < v.start || tb > v.start + v.held + rel
          level = 1.0 / spec[:waves].size
          freqs = spec[:waves].each_index.map { |k| v.hz * (2.0**spec[:octaves][k]) * (2.0**(spec[:detune][k] / 1200.0)) }
          base_cut = spec[:cutoff] * (v.bass ? 0.7 + ck * 0.8 : 0.35 + ck * 1.6)
          res = v.bass ? spec[:resonance] : [spec[:resonance] + rk * 0.45, 0.85].min
          j = 0
          while j < n
            t = tb + (j.to_f / RATE) - v.start
            if t >= 0
              raw = 0.0
              spec[:waves].each_with_index do |shape, k|
                v.phases[k] = (v.phases[k] + (freqs[k] / RATE)) % 1.0
                raw += S.wave(shape, v.phases[k]) * level
              end
              cut = base_cut + (spec[:env_amount] * spec[:filter_env].at(t, v.held))
              out = v.ladder.process(raw * spec[:drive], cut.clamp(30.0, 12_000.0), res) * spec[:amp].at(t, v.held) * v.gain
              left[j] += out * 0.52
              right[j] += out * 0.48
            end
            j += 1
          end
        end
      voices.reject! { |v| tb > v.start + v.held + v.spec[:amp].release }

      # Sequence the DFAM a block ahead.
      while dfam_next < tb + (n.to_f / RATE)
        step = dfam_step % 8
        vel = pattern[:velocity][step] / 100.0 * ACCENT[step]
        if vel.positive?
          f0 = 40.0 * (2.0**(pattern[:pitch][step] / 100.0 * 3.0))
          dfam_hits << DfamHit.new(dfam_next, f0, vel, 0.0, 0.0, S::Ladder.new(rate: RATE), 0.35 + (0.3 * (step % 2)))
        end
      b = dfam_step % 5
      if pattern_b[:velocity][b].positive?
        fb = 40.0 * (2.0**(pattern_b[:pitch][b] / 100.0 * 3.0))
        dfam_hits << DfamHit.new(dfam_next + 0.004, fb, pattern_b[:velocity][b] / 100.0 * 0.55, 0.0, 0.0, S::Ladder.new(rate: RATE), b.even? ? 0.25 : 0.75)
      end
      # The kick on every beat: four steps of the sequencer.
      kicks << dfam_next if (dfam_step % 4).zero?
      dfam_step += 1
        if (dfam_step % 32).zero?
          k = dfam_rng.rand(8)
          pattern[:pitch][k] = (pattern[:pitch][k] + dfam_rng.rand(-18..18)).clamp(5, 95)
          pattern[:velocity][k] = dfam_rng.rand < 0.15 ? 0 : (pattern[:velocity][k] + dfam_rng.rand(-20..20)).clamp(35, 100)
        end
        dfam_next += DFAM_STEP
      end
      vcf = vcf_decay_knob(tb)
      vca = vca_decay_knob(tb)
      cut_top = dfam_cut_knob(tb)
      dfam_hits.each do |h|
        j = 0
        while j < n
          tt = tb + (j.to_f / RATE) - h.start
          if tt >= 0
            pitch_env = 1.0 + (2.2 * Math.exp(-tt / 0.045))
            h.ph1 = (h.ph1 + (h.f0 * pitch_env / RATE)) % 1.0
            tri = S.wave(:triangle, h.ph1)
            h.ph2 = (h.ph2 + (h.f0 * 1.5 * pitch_env * (1.0 + (0.45 * tri)) / RATE)) % 1.0
            sq = h.ph2 < 0.5 ? 1.0 : -1.0
            mix = (0.55 * tri) + (0.3 * sq) + (0.18 * (rand * 2.0 - 1.0))
            cut = 120.0 + (cut_top * Math.exp(-tt / vcf))
            out = h.ladder.process(mix, cut, 0.55) * h.vel * Math.exp(-tt / vca) * DFAM_LEVEL
            left[j] += out * h.pan
            right[j] += out * (1.0 - h.pan)
          end
          j += 1
        end
      end
      dfam_hits.reject! { |h| tb - h.start > vca * 8 }
      j = 0
      while j < n
        now = tb + (j.to_f / RATE)
        bus = 0.0
        kicks.each do |t|
          tk = now - t
          next if tk.negative? || tk > 0.5
          bus += Math.sin(2 * Math::PI * ((45.0 * tk) + (105.0 * 0.035 * (1.0 - Math.exp(-tk / 0.035))))) * Math.exp(-tk / 0.32)
          bus += (tk < 0.005 ? (1.0 - (tk / 0.005)) * 0.5 : 0.0)
        end
        k = Math.tanh(bus * 2.8) * KICK_LEVEL
        left[j] += k
        right[j] += k
        j += 1
      end

      kicks.reject! { |t| tb - t > 0.5 }
        sox.write(left.zip(right).flatten.map { |s| (Math.tanh(s * 1.4) * 26_000).round }.pack("s<*"))
        frame += n
      end
      sox.close
    end
  end

  module LovedMoogLoop
    # takes/loved_moog_loop.rb, frozen as heard (sha256 08c384cd563a89aa8261fe1647cf5eb19dce1e18abd499dcd71e91b6ddff8291).

    # Live: a progression through dilla's own oscillators and Moog ladder, a
    # different moog patch every two chords, cutoff and resonance swept slowly while
    # it plays. Streams raw PCM to sox, so nothing is written to disk.

    RATE = 32_000
    BLOCK = 1_024
    S = AnalogSynth
    P = S::PATCHES

    def self.hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

    # Fm9, Bbm9, Eb13, Abmaj9, Dbmaj7#11, C7alt: soul-jazz, Dilla territory.
    CHORDS = [
      [41, [56, 60, 63, 67]], [46, [56, 61, 65, 68]], [39, [55, 60, 61, 65]],
      [44, [55, 60, 63, 70]], [37, [60, 65, 67, 72]], [36, [58, 61, 64, 68]],
    ]
    PADS = %i[warm_pad poly_strings prophet_five juno_pad]
    BAR = 4.4

    Voice = Struct.new(:hz, :spec, :start, :held, :gain, :phases, :ladder, :bass)

    def self.voice(midi, spec, start, held, gain, bass: false)
      rng = Random.new(midi * 7 + (start * 10).to_i)
      Voice.new(hz(midi) * 2.0**(rng.rand(-0.7..0.7) / 1200.0), spec, start, held, gain,
                spec[:waves].map { rng.rand }, S::Ladder.new(rate: RATE), bass)
    end

    # The knobs: cutoff breathes over 23 s, resonance over 31 s, out of phase.
    def self.cutoff_knob(t) = 0.55 + 0.45 * Math.sin(2 * Math::PI * t / 23.0)
    def self.res_knob(t) = 0.5 + 0.5 * Math.sin(2 * Math::PI * t / 31.0 + 1.3)

    def self.run(argv = [])
      loops = (argv[0] || 2).to_i

      voices = []
      t0 = 0.0
      loops.times do |loop_i|
        CHORDS.each_with_index do |(bass, tones), i|
          pad = P.fetch(PADS[((loop_i * CHORDS.size) + i) / 2 % PADS.size])
          tones.each { |m| voices << voice(m, pad, t0, BAR - 0.1, 0.22) }
          # Moog bass: the chord root twice a bar, the second a little late.
          voices << voice(bass, P[:moog_bass], t0, 1.6, 0.55, bass: true)
          voices << voice(bass, P[:moog_bass], t0 + 2.35, 1.2, 0.45, bass: true)
          t0 += BAR
        end
      end
      total = t0 + 2.5

      $stderr.puts "live: #{CHORDS.size * loops} chords, #{PADS.join(" -> ")} over moog_bass, #{total.round}s"
      sox = IO.popen(%W[sox -q -t raw -r #{RATE} -e signed -b 16 -c 2 - -d], "wb")
      frame = 0
      frames = (total * RATE).to_i
      two_pi = 2 * Math::PI
      while frame < frames
        n = [BLOCK, frames - frame].min
        left = Array.new(n, 0.0)
        right = Array.new(n, 0.0)
        tb = frame.to_f / RATE
        ck = cutoff_knob(tb)
        rk = res_knob(tb)
        voices.each do |v|
          spec = v.spec
          rel = spec[:amp].release
          next if tb + (n.to_f / RATE) < v.start || tb > v.start + v.held + rel
          level = 1.0 / spec[:waves].size
          freqs = spec[:waves].each_index.map { |k| v.hz * (2.0**spec[:octaves][k]) * (2.0**(spec[:detune][k] / 1200.0)) }
          base_cut = spec[:cutoff] * (v.bass ? 0.7 + ck * 0.8 : 0.35 + ck * 1.6)
          res = v.bass ? spec[:resonance] : [spec[:resonance] + rk * 0.45, 0.85].min
          j = 0
          while j < n
            t = tb + (j.to_f / RATE) - v.start
            if t >= 0
              raw = 0.0
              spec[:waves].each_with_index do |shape, k|
                v.phases[k] = (v.phases[k] + (freqs[k] / RATE)) % 1.0
                raw += S.wave(shape, v.phases[k]) * level
              end
              cut = base_cut + (spec[:env_amount] * spec[:filter_env].at(t, v.held))
              out = v.ladder.process(raw * spec[:drive], cut.clamp(30.0, 12_000.0), res) * spec[:amp].at(t, v.held) * v.gain
              left[j] += out * 0.52
              right[j] += out * 0.48
            end
            j += 1
          end
        end
        voices.reject! { |v| tb > v.start + v.held + v.spec[:amp].release }
        sox.write(left.zip(right).flatten.map { |s| (Math.tanh(s * 1.4) * 26_000).round }.pack("s<*"))
        frame += n
      end
      sox.close
    end
  end

  module MoogDfamLoop
    # takes/moog_dfam_loop.rb, frozen as heard (sha256 542c589044c4197d3484b589b21cb637ba0daf4be37e5fb522073aa983c8faa7).

    # Live: a progression through dilla's own oscillators and Moog ladder, a
    # different moog patch every two chords, cutoff and resonance swept slowly while
    # it plays. Streams raw PCM to sox, so nothing is written to disk.

    RATE = 32_000
    BLOCK = 1_024
    S = AnalogSynth
    P = S::PATCHES

    def self.hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

    # Fm9, Bbm9, Eb13, Abmaj9, Dbmaj7#11, C7alt: soul-jazz, Dilla territory.
    CHORDS = [
      [41, [56, 60, 63, 67]], [46, [56, 61, 65, 68]], [39, [55, 60, 61, 65]],
      [44, [55, 60, 63, 70]], [37, [60, 65, 67, 72]], [36, [58, 61, 64, 68]],
    ]
    PADS = %i[warm_pad poly_strings prophet_five juno_pad]
    BAR = 4.4

    Voice = Struct.new(:hz, :spec, :start, :held, :gain, :phases, :ladder, :bass)

    def self.voice(midi, spec, start, held, gain, bass: false)
      rng = Random.new(midi * 7 + (start * 10).to_i)
      Voice.new(hz(midi) * 2.0**(rng.rand(-0.7..0.7) / 1200.0), spec, start, held, gain,
                spec[:waves].map { rng.rand }, S::Ladder.new(rate: RATE), bass)
    end

    # The knobs: cutoff breathes over 23 s, resonance over 31 s, out of phase.
    def self.cutoff_knob(t) = 0.55 + 0.45 * Math.sin(2 * Math::PI * t / 23.0)
    def self.res_knob(t) = 0.5 + 0.5 * Math.sin(2 * Math::PI * t / 31.0 + 1.3)

    # The DFAM, as the Moog is built: an 8-step sequencer, each step its own pitch
    # and velocity, running in sixteenths; VCO 1 a triangle frequency-modulating
    # VCO 2, a square; both with a pitch envelope that falls; noise mixed in; all
    # of it through a ladder low-pass with its own decay, then the VCA's decay.
    # The pattern starts from dilla's DfamEngine and one step mutates every two
    # bars; decay and cutoff drift slowly, like the pads' knobs.
    DFAM_STEP = BAR / 16
    DFAM_LEVEL = 0.34
    DfamHit = Struct.new(:start, :f0, :vel, :ph1, :ph2, :ladder, :pan)
    def self.vcf_decay_knob(t) = 0.05 + 0.1 * (0.5 + 0.5 * Math.sin(2 * Math::PI * t / 37.0))
    def self.vca_decay_knob(t) = 0.09 + 0.12 * (0.5 + 0.5 * Math.sin(2 * Math::PI * t / 29.0 + 0.7))
    def self.dfam_cut_knob(t) = 900.0 + 2600.0 * (0.5 + 0.5 * Math.sin(2 * Math::PI * t / 43.0 + 2.1))

    def self.run(argv = [])
      loops = (argv[0] || 2).to_i

      voices = []
      t0 = 0.0
      loops.times do |loop_i|
        CHORDS.each_with_index do |(bass, tones), i|
          pad = P.fetch(PADS[((loop_i * CHORDS.size) + i) / 2 % PADS.size])
          tones.each { |m| voices << voice(m, pad, t0, BAR - 0.1, 0.22) }
          # Moog bass: the chord root twice a bar, the second a little late.
          voices << voice(bass, P[:moog_bass], t0, 1.6, 0.55, bass: true)
          voices << voice(bass, P[:moog_bass], t0 + 2.35, 1.2, 0.45, bass: true)
          t0 += BAR
        end
      end
      total = t0 + 2.5
      pattern = { pitch: [50, 30, 60, 20, 55, 35, 65, 25], velocity: [80, 60, 90, 50, 85, 65, 95, 55] }
      dfam_rng = Random.new
      dfam_hits = []
      dfam_next = 0.0
      dfam_step = 0

      $stderr.puts "live: #{CHORDS.size * loops} chords, #{PADS.join(" -> ")} over moog_bass, #{total.round}s"
      sox = IO.popen(%W[sox -q -t raw -r #{RATE} -e signed -b 16 -c 2 - -d], "wb")
      frame = 0
      frames = (total * RATE).to_i
      two_pi = 2 * Math::PI
      while frame < frames
        n = [BLOCK, frames - frame].min
        left = Array.new(n, 0.0)
        right = Array.new(n, 0.0)
        tb = frame.to_f / RATE
        ck = cutoff_knob(tb)
        rk = res_knob(tb)
        voices.each do |v|
          spec = v.spec
          rel = spec[:amp].release
          next if tb + (n.to_f / RATE) < v.start || tb > v.start + v.held + rel
          level = 1.0 / spec[:waves].size
          freqs = spec[:waves].each_index.map { |k| v.hz * (2.0**spec[:octaves][k]) * (2.0**(spec[:detune][k] / 1200.0)) }
          base_cut = spec[:cutoff] * (v.bass ? 0.7 + ck * 0.8 : 0.35 + ck * 1.6)
          res = v.bass ? spec[:resonance] : [spec[:resonance] + rk * 0.45, 0.85].min
          j = 0
          while j < n
            t = tb + (j.to_f / RATE) - v.start
            if t >= 0
              raw = 0.0
              spec[:waves].each_with_index do |shape, k|
                v.phases[k] = (v.phases[k] + (freqs[k] / RATE)) % 1.0
                raw += S.wave(shape, v.phases[k]) * level
              end
              cut = base_cut + (spec[:env_amount] * spec[:filter_env].at(t, v.held))
              out = v.ladder.process(raw * spec[:drive], cut.clamp(30.0, 12_000.0), res) * spec[:amp].at(t, v.held) * v.gain
              left[j] += out * 0.52
              right[j] += out * 0.48
            end
            j += 1
          end
        end
      voices.reject! { |v| tb > v.start + v.held + v.spec[:amp].release }

      # Sequence the DFAM a block ahead.
      while dfam_next < tb + (n.to_f / RATE)
        step = dfam_step % 8
        vel = pattern[:velocity][step] / 100.0
        if vel.positive?
          f0 = 40.0 * (2.0**(pattern[:pitch][step] / 100.0 * 3.0))
          dfam_hits << DfamHit.new(dfam_next, f0, vel, 0.0, 0.0, S::Ladder.new(rate: RATE), 0.35 + (0.3 * (step % 2)))
        end
        dfam_step += 1
        if (dfam_step % 32).zero?
          k = dfam_rng.rand(8)
          pattern[:pitch][k] = (pattern[:pitch][k] + dfam_rng.rand(-18..18)).clamp(5, 95)
          pattern[:velocity][k] = dfam_rng.rand < 0.15 ? 0 : (pattern[:velocity][k] + dfam_rng.rand(-20..20)).clamp(35, 100)
        end
        dfam_next += DFAM_STEP
      end
      vcf = vcf_decay_knob(tb)
      vca = vca_decay_knob(tb)
      cut_top = dfam_cut_knob(tb)
      dfam_hits.each do |h|
        j = 0
        while j < n
          tt = tb + (j.to_f / RATE) - h.start
          if tt >= 0
            pitch_env = 1.0 + (2.2 * Math.exp(-tt / 0.045))
            h.ph1 = (h.ph1 + (h.f0 * pitch_env / RATE)) % 1.0
            tri = S.wave(:triangle, h.ph1)
            h.ph2 = (h.ph2 + (h.f0 * 1.5 * pitch_env * (1.0 + (0.45 * tri)) / RATE)) % 1.0
            sq = h.ph2 < 0.5 ? 1.0 : -1.0
            mix = (0.55 * tri) + (0.3 * sq) + (0.18 * (rand * 2.0 - 1.0))
            cut = 120.0 + (cut_top * Math.exp(-tt / vcf))
            out = h.ladder.process(mix, cut, 0.55) * h.vel * Math.exp(-tt / vca) * DFAM_LEVEL
            left[j] += out * h.pan
            right[j] += out * (1.0 - h.pan)
          end
          j += 1
        end
      end
      dfam_hits.reject! { |h| tb - h.start > vca * 8 }
        sox.write(left.zip(right).flatten.map { |s| (Math.tanh(s * 1.4) * 26_000).round }.pack("s<*"))
        frame += n
      end
      sox.close
    end
  end
  TOC = {
    "liveset_161326bb356a" => Liveset161326bb356a,
    "liveset_4abbb73e" => Liveset4abbb73e,
    "liveset_5613fe64b642" => Liveset5613fe64b642,
    "liveset_5aa16356c296" => Liveset5aa16356c296,
    "liveset_68eccd04098e" => Liveset68eccd04098e,
    "liveset_7b5069a1bf3b" => Liveset7b5069a1bf3b,
    "liveset_864969335d0f" => Liveset864969335d0f,
    "liveset_db4ddf1a" => LivesetDb4ddf1a,
    "loved_moog_loop" => LovedMoogLoop,
    "moog_dfam_loop" => MoogDfamLoop,
  }.freeze

  def self.play(name)
    take = TOC.fetch(name) do
      abort "usage: ruby dilla.rb live take <#{TOC.keys.sort.join('|')}>"
    end
    warn "take #{name}, as it was heard -- ctrl-c to end"
    take.run([])
  end
end
