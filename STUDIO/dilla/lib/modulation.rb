# frozen_string_literal: true

require "json"
# The O-U walk behind the :random source. Required here rather than left to the
# caller: tape_master.rb loads this lazily inside tape_hysteresis!, so on a
# render that never touches tape the constant does not exist, and a :random
# route would fail at the moment it was read instead of at the moment it was
# built.
require_relative "tape_hysteresis"

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

    out = IO.popen(["ffmpeg", "-hide_banner", "-nostats", "-i", path.to_s,
                    "-af", "ebur128=peak=none", "-f", "null", "-"],
                   err: %i[child out], &:read)
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
  # knobs.rb makes the case for this at length and it applies unchanged: a table
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
      IO.popen(["ffmpeg", "-hide_banner", "-h", "filter=#{filter}"], err: %i[child out], &:read)
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
      # opening together is just louder.
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
# master_heuristics.rb and render_analog.rb are untouched by the move.
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
