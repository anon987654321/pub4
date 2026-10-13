# frozen_string_literal: true

# ------------------------------------------------------------------ stereo
# A block of audio is an array of channels, each an array of floats: [mono] or [left, right]. The
# pan law is constant power and unity at the centre, so a part panned to the middle sounds as
# loud in each channel as it did in mono. Panning is static, set by the voice group and by where
# a note lies in the keyboard; nothing sweeps.
module Stereo
  SQRT2 = Math.sqrt(2.0)

  # Gains [left, right] for a pan from -1 (left) to 1 (right).
  def self.gains(pan)
    angle = (pan.clamp(-1.0, 1.0) + 1.0) * Math::PI / 4.0
    [Math.cos(angle) * SQRT2, Math.sin(angle) * SQRT2]
  end

  def self.zeros(channels, count) = Array.new(channels) { Array.new(count, 0.0) }

  def self.size(frame) = frame.first.size

  # Add `part` into `frame` starting at sample `offset`.
  def self.add!(frame, part, offset = 0)
    frame.each_with_index do |channel, c|
      source = part[c]
      source.each_with_index { |v, i| channel[offset + i] += v }
    end
    frame
  end

  def self.concat!(frame, part)
    frame.each_with_index { |channel, c| channel.concat(part[c]) }
    frame
  end

  # The first `count` samples of every channel, removed from the frame.
  def self.shift!(frame, count) = frame.map { |channel| channel.shift(count) }

  # Mono from stereo: the mean of the channels.
  def self.fold(frame) = frame.size == 1 ? frame.first : frame[0].each_index.map { |i| 0.5 * (frame[0][i] + frame[1][i]) }

  # Pairs of samples, left then right, for a stereo frame; a mono frame as it is.
  def self.interleave(frame) = frame.size == 1 ? frame.first : frame[0].zip(frame[1]).flatten

  def self.mid_side(frame) = [frame[0].each_index.map { |i| 0.5 * (frame[0][i] + frame[1][i]) }, frame[0].each_index.map { |i| 0.5 * (frame[0][i] - frame[1][i]) }]

  def self.left_right(mid, side) = [mid.each_index.map { |i| mid[i] + side[i] }, mid.each_index.map { |i| mid[i] - side[i] }]
end

module Stream
  # One processor for each channel, each with a state of its own.
  class Pair
    def initialize(*processors) = @processors = processors

    def process(frame) = frame.each_with_index.map { |channel, c| @processors[c].process(channel) }
  end

  # A space echo for two channels, ping-pong: the heads read the loop at 1x, 2x and 3x the delay,
  # the odd heads sound on the left and the even heads on the right, and what is fed back is
  # all of them, so the repeats cross the room. One head alone is heard in the middle.
  class PingPongEcho
    attr_accessor :boost

    def initialize(delay:, heads: [1, 2], intensity: 0.5, volume: 0.45, lowpass: 3200, saturation: 0.35, reverb: 0.0, resets: [], send: nil)
      @intensity = intensity.to_f.clamp(0.0, EchoLine::MAX_INTENSITY)
      @d = [(delay * SAMPLE_RATE).round, 1].max
      @heads = heads
      @ring = Array.new((heads.max * @d) + 1, 0.0)
      @cutoff = lowpass ? 1.0 / ((2 * Math::PI * lowpass * (1.0 / SAMPLE_RATE)) + 1.0) : 0.0
      @drive = 1.0 + (2.0 * saturation)
      @share = 1.0 / heads.size
      @volume = volume
      @cuts = resets.to_h { |at| [at, true] }
      @send = send
      @boost = 1.0
      @rooms = reverb.to_f.positive? ? [Reverb.new(reverb), Reverb.new(reverb, side: :right)] : nil
      @y = [0.0, 0.0]
      @n = 0
      @single = heads.none?(&:odd?) || heads.all?(&:odd?) # one side only: heard in the middle
      @left = @single ? heads : heads.select(&:odd?)
      @right = @single ? heads : heads.reject(&:odd?)
    end

    # `frame` is [left, right]; the echo takes the mean of the two as its input.
    def process(frame)
      count = frame[0].size
      wet = [Array.new(count, 0.0), Array.new(count, 0.0)]
      count.times do |i|
        if @cuts[@n]
          @ring.fill(0.0)
          @y = [0.0, 0.0]
        end
        taps = [@left, @right].map { |heads| heads.sum { |h| @ring[(@n - (h * @d)) % @ring.size] } }
        @y = [0, 1].map { |c| @y[c] + ((1.0 - @cutoff) * ((Math.tanh(taps[c] * @share * @drive) / @drive) - @y[c])) }
        fed = 0.5 * (frame[0][i] + frame[1][i])
        fed *= @send.call(@n) if @send
        fed *= @boost unless @boost == 1.0
        @ring[@n % @ring.size] = fed + (@intensity * (@single ? @y[0] : @y[0] + @y[1]))
        wet[0][i] = @y[0]
        wet[1][i] = @y[1]
        @n += 1
      end
      wet = wet.each_with_index.map { |channel, c| @rooms[c].process(channel) } if @rooms
      [0, 1].map { |c| Array.new(count) { |i| frame[c][i] + (@volume * wet[c][i]) } }
    end
  end

  # Mid and side: the mid goes through untouched, so the mono sum of the result is the mono sum
  # of the input. The side is centred below `centre_hz` (so the low end is in the middle, where a
  # sub belongs), and its highs are raised by `widen`, with `width` over all.
  class Imager
    def initialize(centre_hz: 120.0, widen: 0.35, width: 1.0, air_hz: 4000.0)
      @centre = [Tape::Biquad.highpass(centre_hz), Tape::Biquad.highpass(centre_hz)] # two Butterworth sections: Linkwitz-Riley, 24 dB an octave
      @air = Highpass.new(air_hz)
      @widen = widen
      @width = width
    end

    def process(frame)
      return frame if frame.size == 1

      mid, side = Stereo.mid_side(frame)
      side = @centre[1].process(@centre[0].process(side))
      bright = @air.process(side)
      side = side.each_index.map { |i| (side[i] + (@widen * bright[i])) * @width }
      Stereo.left_right(mid, side)
    end
  end
end
