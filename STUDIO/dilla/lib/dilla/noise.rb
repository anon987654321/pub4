# frozen_string_literal: true

# ------------------------------------------------------------------- noise
# Noise and sparkle layers, each optional and kept well down. Everything here is drawn from
# a stream seeded by the render, one draw for each sample or each event in order, so a pass is
# the same however it is cut into blocks. The continuous layers are filtered noise: air above
# eight kilohertz, and a brown bed under two hundred hertz with no spikes in it. The events are
# dust, sparse pops, and sparkle, short glints of frequency modulation at three to nine
# kilohertz on the notes of the chord, which the kick ducks and which has an echo of its own.
module Noise
  # No layer is ever louder than this, whatever the data says.
  CEILING_DB = -24.0

  def self.gain(db) = 10.0**([db, CEILING_DB].min / 20.0)

  # Paul Kellet's pink filter over white noise.
  class Pink
    def initialize(rng)
      @rng = rng
      @b = Array.new(7, 0.0)
    end

    def step
      w = (@rng.rand * 2) - 1
      b = @b
      b[0] = (0.99886 * b[0]) + (w * 0.0555179)
      b[1] = (0.99332 * b[1]) + (w * 0.0750759)
      b[2] = (0.96900 * b[2]) + (w * 0.1538520)
      b[3] = (0.86650 * b[3]) + (w * 0.3104856)
      b[4] = (0.55000 * b[4]) + (w * 0.5329522)
      b[5] = (-0.7616 * b[5]) - (w * 0.0168980)
      pink = b[0] + b[1] + b[2] + b[3] + b[4] + b[5] + b[6] + (w * 0.5362)
      b[6] = w * 0.115926
      pink * 0.11
    end
  end

  # Pink noise through a highpass: the air.
  class Air
    def initialize(spec, seed)
      @pink = Pink.new(Random.new(seed))
      @high = Stream::Highpass.new(spec.fetch('hz', 8000.0))
      @gain = Noise.gain(spec.fetch('db', -54.0)) * 4.0
    end

    def block(count) = Array.new(count) { @high.step(@pink.step) * @gain }
  end

  # Brown noise (white noise, integrated and leaking) under 200 Hz: the bed of a tape.
  class Bed
    def initialize(spec, seed)
      @rng = Random.new(seed)
      @low = Stream::Lowpass.new(spec.fetch('hz', 200.0))
      @y = 0.0
      @gain = Noise.gain(spec.fetch('db', -48.0)) * 3.0
    end

    def block(count)
      Array.new(count) do
        @y = (@y * 0.998) + (((@rng.rand * 2) - 1) * 0.04)
        (@low.step(@y) * @gain).clamp(-0.05, 0.05) # no spike climbs out of it
      end
    end
  end

  # The pop of a speck of dust: a click, gone in a few milliseconds.
  def self.pop(rng, db)
    length = (SAMPLE_RATE * (0.002 + (rng.rand * 0.004))).round
    sign = rng.rand < 0.5 ? -1.0 : 1.0
    amp = gain(db) * (0.3 + rng.rand)
    k = Math.exp(-5.0 / length)
    level = amp * sign
    Array.new(length) { level.tap { level *= k } }
  end

  # A glint: two-operator frequency modulation, a carrier of three to nine kilohertz and a
  # modulator at 3.5 times it whose index dies away faster than the tone.
  def self.glint(freq, decay, db)
    length = (decay * 5 * SAMPLE_RATE).round
    amp = gain(db)
    Voices::Reader.new(length) do |i|
      t = i.to_f / SAMPLE_RATE
      index = 1.8 * Math.exp(-t / (decay * 0.4))
      Math.sin((Voices::TAU * freq * t) + (index * Math.sin(Voices::TAU * freq * 3.5 * t))) * Math.exp(-t / decay) * amp
    end
  end

  # Event times of a Poisson process, `rate` a second, over `seconds`.
  def self.poisson(rng, rate, seconds)
    times = []
    t = 0.0
    loop do
      t += -Math.log(1.0 - rng.rand) / rate
      break if t >= seconds

      times << t
    end
    times
  end

  # Bank entries for the dust of a pass, each pop at a place of its own.
  def self.dust(spec, seed, seconds)
    rng = Random.new(seed)
    poisson(rng, spec.fetch('rate', 3.0), seconds).map do |t|
      samples = pop(rng, spec.fetch('db', -42.0))
      Stream::Bank::Entry.new((t * SAMPLE_RATE).to_i, -> { Voices::Reader.of(samples) }, 1.0, nil, (rng.rand * 2) - 1)
    end
  end

  # Bank entries for the sparkle of a pass: at each event a tone of the chord sounding then, put up
  # to the octave that lies between 4 and 8 kilohertz, at a place of its own.
  def self.sparkle(spec, seed, seconds, chord_at)
    rng = Random.new(seed)
    low, high = spec.fetch('midi', [108, 119])
    poisson(rng, spec.fetch('rate', 1.6), seconds).map do |t|
      pcs = chord_at.call(t)
      pc = pcs[rng.rand(pcs.size)]
      midi = (low..high).select { |n| n % 12 == pc }.sample(random: rng) || low
      decay = 0.08 + (rng.rand * 0.25)
      freq = Chords.hz(midi)
      db = spec.fetch('db', -30.0) - (rng.rand * 6)
      pan = ((rng.rand * 2) - 1) * spec.fetch('width', 0.8)
      Stream::Bank::Entry.new((t * SAMPLE_RATE).to_i, -> { glint(freq, decay, db) }, 1.0, nil, pan)
    end
  end
end
