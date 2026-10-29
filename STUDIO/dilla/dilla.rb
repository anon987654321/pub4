#!/usr/bin/env ruby
# frozen_string_literal: true
# Dilla's complete musical and audio runtime. The JSON files beside this script are data,
# not alternate implementations. Generic STUDIO output/process policies remain shared services.

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "shellwords"
require "tempfile"
require "timeout"
require "time"
require "tmpdir"
require "uri"
require "yaml"
require "zlib"
require_relative "../output_paths"
require_relative "../subprocess"
require_relative "../source_map"

SAMPLE_RATE = 44_100
MAX_OFFSET = 0.035
NYQUIST_SHARE = 0.45
MAX_DETUNE = 0.0035
AUDIBLE_TOP_HZ = 14_000.0

# --- wav.rb ---
# ---------------------------------------------------------------- WAV writer

module WAV
  # Samples are mono or channel arrays; generated takes are immutable unless the
  # caller explicitly opts in to replacement.
  def self.write(path, samples, bits: 16, replace: false)
    channels = samples.first.is_a?(Array) ? samples.size : 1
    flat = samples.first.is_a?(Array) ? Stereo.interleave(samples) : samples
    data = bits == 24 ? pack24(flat) : flat.map { |s| (s * 32_767).round.clamp(-32_768, 32_767) }.pack("s<*")
    width = bits / 8

    header  = +"RIFF"
    header << [36 + data.bytesize].pack("V")
    header << "WAVE"
    header << "fmt "
    header << [16].pack("V")
    header << [1].pack("v")                    # PCM
    header << [channels].pack("v")
    header << [SAMPLE_RATE].pack("V")
    header << [SAMPLE_RATE * width * channels].pack("V") # byte rate
    header << [width * channels].pack("v")     # block align
    header << [bits].pack("v")                 # bits per sample
    header << "data"
    header << [data.bytesize].pack("V")

    write_bytes(path, header + data, replace:)
  end

  # Stage in the destination directory and publish atomically. A hard link is
  # create-if-absent, unlike File.binwrite's silent truncation; rename is used
  # only for an explicit replace request. Failed writes leave the prior take intact.
  def self.write_bytes(path, bytes, replace: false)
    directory = File.dirname(path)
    FileUtils.mkdir_p(directory)
    previous_mode = File.file?(path) ? File.stat(path).mode & 0o7777 : nil
    mode = replace && previous_mode ? previous_mode : 0o666 & ~File.umask

    Tempfile.create(["studio-output-", ".tmp"], directory, binmode: true) do |tmp|
      tmp.write(bytes)
      File.chmod(mode, tmp.path)
      tmp.flush
      tmp.fsync
      tmp.close
      replace ? File.rename(tmp.path, path) : File.link(tmp.path, path)
      fsync_directory(directory) if RUBY_PLATFORM !~ /win32|mingw/
    end
    path
  rescue Errno::EEXIST
    raise ArgumentError, "refusing to overwrite existing take: #{path}; choose a new path or pass --replace"
  end

  # Bounded-memory output for long renders. The final path appears only after
  # every block and the RIFF sizes have been written and synced; a crash or an
  # invalid block can leave a temporary file only, never a plausible partial WAV.
  def self.write_stream(path, frames:, channels:, bits: 16, block_size: 8192, replace: false)
    raise ArgumentError, "frames must be positive" unless frames.is_a?(Integer) && frames.positive?
    raise ArgumentError, "channels must be one or two" unless [1, 2].include?(channels)
    raise ArgumentError, "bits must be 16 or 24" unless [16, 24].include?(bits)
    raise ArgumentError, "block size must be positive" unless block_size.is_a?(Integer) && block_size.positive?

    destination = File.expand_path(path.to_s)
    directory = File.dirname(destination)
    FileUtils.mkdir_p(directory)

    previous_mode = File.file?(destination) ? File.stat(destination).mode & 0o7777 : nil
    mode = replace && previous_mode ? previous_mode : 0o666 & ~File.umask
    width = bits / 8
    header = +"RIFF" + [0].pack("V") + "WAVEfmt " + [16].pack("V") + [1].pack("v")
    header << [channels, SAMPLE_RATE, SAMPLE_RATE * width * channels, width * channels, bits].pack("vVVvv")
    header << "data" << [0].pack("V")

    Tempfile.create(["studio-output-", ".tmp"], directory, binmode: true) do |file|
      file.write(header)
      offset = 0
      while offset < frames
        count = [block_size, frames - offset].min
        channel_data = yield(offset, count)
        unless channel_data.is_a?(Array) && channel_data.length == channels &&
               channel_data.all? { |values| values.is_a?(Array) && values.length == count }
          raise ArgumentError, "audio block must contain #{channels} channels by #{count} frames"
        end

        flat = channels == 1 ? channel_data.fetch(0) : Stereo.interleave(channel_data)
        bytes = bits == 24 ? pack24(flat) : flat.map { |sample| (sample * 32_767).round.clamp(-32_768, 32_767) }.pack("s<*")
        file.write(bytes)
        offset += count
      end

      data_size = file.size - 44
      raise ArgumentError, "WAV exceeds RIFF size limit" if data_size > 0xffff_ffff - 36
      file.seek(4)
      file.write([36 + data_size].pack("V"))
      file.seek(40)
      file.write([data_size].pack("V"))
      File.chmod(mode, file.path)
      file.flush
      file.fsync
      file.close

      # Publish only after the complete header and payload are durable. A hard
      # link refuses an existing take; rename is atomic when replacement was explicit.
      replace ? File.rename(file.path, destination) : File.link(file.path, destination)
      fsync_directory(directory) if RUBY_PLATFORM !~ /win32|mingw/
    end
    path
  end

  # Three bytes a sample, least significant first.
  def self.pack24(flat)
    flat.map do |s|
      v = (s * 8_388_607).round.clamp(-8_388_608, 8_388_607)
      [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff].pack("C3")
    end.join
  end

  # File bytes and the directory entry are separate durability boundaries.
  def self.fsync_directory(directory)
    descriptor = IO.sysopen(directory, File::RDONLY)
    dir_io = IO.new(descriptor)
    dir_io.fsync
  ensure
    dir_io&.close
  end
  private_class_method :fsync_directory
end

# --- stream.rb ---
# ------------------------------------------------------------- processors
# Every filter and effect of the engine as an object that keeps its state between calls. A signal
# cut into blocks and handed to one of these comes out as it would from a single call, so the whole
# render and the streamed render are the same arithmetic. Each has `process(block)` returning a block
# of the same length (the echo, which rings on, is told to run on).
module Stream
  TAU = 2 * Math::PI

  def self.db(x) = 10.0**(x / 20.0)

  # One pole: the signal follows itself at a rate set by the cutoff. nil cutoff passes everything.
  class Lowpass
    def initialize(cutoff)
      @a = cutoff && (1.0 / SAMPLE_RATE / ((1.0 / (TAU * cutoff)) + (1.0 / SAMPLE_RATE)))
      @y = 0.0
    end

    def step(x)
      @y += @a * (x - @y)
    end

    def process(buf)
      return buf unless @a

      buf.map { |x| step(x) }
    end
  end

  # A DC-blocking highpass.
  class Highpass
    def initialize(cutoff)
      @a = 1.0 / (1.0 + (TAU * cutoff / SAMPLE_RATE))
      @y = @prev = 0.0
    end

    def step(x)
      @y = @a * (@y + x - @prev)
      @prev = x
      @y
    end

    def process(buf) = buf.map { |x| step(x) }
  end

  # A feed-forward compressor: the level follows the signal, over the threshold the gain falls.
  class Compressor
    def initialize(threshold, ratio, attack_ms, release_ms, makeup)
      @up = 1.0 - Math.exp(-1.0 / (attack_ms / 1000.0 * SAMPLE_RATE))
      @down = 1.0 - Math.exp(-1.0 / (release_ms / 1000.0 * SAMPLE_RATE))
      @limit = Stream.db(threshold)
      @slope = 1.0 - (1.0 / ratio)
      @gain = Stream.db(makeup)
      @level = 0.0
    end

    def step(x)
      a = x.abs
      @level += (a > @level ? @up : @down) * (a - @level)
      over = @level > @limit ? (@limit / @level)**@slope : 1.0
      x * over * @gain
    end

    def process(buf) = buf.map { |x| step(x) }
  end

  # Sample-rate reduction by `factor` (hold each value) and rounding to `bits` of resolution.
  class Crush
    def initialize(bits, factor)
      @levels = 2.0**(bits - 1)
      @factor = factor
      @held = 0.0
      @clock = factor
    end

    def step(x)
      if @clock >= @factor
        @held = (x * @levels).round / @levels
        @clock -= @factor
      end
      @clock += 1.0
      @held
    end

    def process(buf) = buf.map { |x| step(x) }
  end

  # The summing colour: a soft knee that bends only the peaks over a touch of low warmth.
  class Vcs
    def initialize(amount)
      @amount = amount.clamp(0.0, 1.0)
      @drive = 1.0 + (2.0 * @amount)
      @warm = Lowpass.new(180.0)
    end

    def step(x) = Math.tanh((x + (0.12 * @amount * @warm.step(x))) * @drive) / @drive

    def process(buf) = @amount.positive? ? buf.map { |x| step(x) } : buf
  end

  # Four feedback combs in series, the room of FX.reverb. Nothing is normalised, so the result
  # does not depend on how much of the signal has arrived.
  class Reverb
    DELAYS = [0.0297, 0.0371, 0.0411, 0.0437].freeze
    RIGHT_DELAYS = [0.0317, 0.0383, 0.0429, 0.0463].freeze # other primes of milliseconds, so the right is not the left
    GAINS = [0.70, 0.65, 0.60, 0.55].freeze

    def initialize(amount, side: :left)
      @amount = amount
      @lines = (side == :right ? RIGHT_DELAYS : DELAYS).map { |d| Array.new((d * SAMPLE_RATE).to_i, 0.0) }
      @at = 0
    end

    def process(buf)
      return buf if @amount.nil? || @amount <= 0

      buf.map do |x|
        v = x
        @lines.each_with_index do |line, k|
          slot = @at % line.size
          v += line[slot] * GAINS[k] * @amount
          line[slot] = v
        end
        @at += 1
        v
      end
    end
  end

  # A spring tank: the signal, band limited to what a spring passes, goes round a short loop
  # through a chain of allpass sections. The sections delay the highs more than the lows, which is
  # the chirp of a spring, and the loop turns it into a splashing tail. Static: no modulation.
  class Spring
    LOOP = (0.037 * SAMPLE_RATE).round
    RIGHT_LOOP = (0.041 * SAMPLE_RATE).round
    COEFF = 0.62

    def initialize(amount, side: :left)
      @amount = amount
      @loop = side == :right ? RIGHT_LOOP : LOOP
      @low = Lowpass.new(3800)
      @high = Highpass.new(160.0)
      @ring = Array.new(@loop, 0.0)
      @states = Array.new(8, 0.0)
      @smooth = 0.0
      @at = 0
    end

    def process(buf)
      return buf if @amount.nil? || @amount <= 0 || buf.empty?

      buf.map do |x|
        v = @high.step(@low.step(x)) + (0.6 * @ring[@at % @loop])
        @states.each_index do |k|
          y = (COEFF * v) + @states[k]
          @states[k] = v - (COEFF * y)
          v = y
        end
        @smooth += 0.45 * (v - @smooth)
        @ring[@at % @loop] = @smooth
        @at += 1
        x + (@amount * @smooth)
      end
    end
  end

  # A space echo: playback heads read one loop at 1x, 2x and 3x the base delay, summed, darkened
  # by a lowpass and a mild saturation, and fed back. `process` takes a block of input and returns
  # the dry plus echo for it; ask for blocks of silence to let the repeats ring on. `resets` are
  # absolute sample indices where the heads are cleared, `send` the hand on the send knob.
  class EchoLine
    MAX_INTENSITY = 0.9

    # How much of the input reaches the tape, on top of `send`: a throw turns it up for a bar.
    attr_accessor :boost

    def initialize(delay:, heads: [1, 2], intensity: 0.5, volume: 0.45, lowpass: 3200, saturation: 0.35, reverb: 0.0, resets: [], send: nil)
      @boost = 1.0
      @intensity = intensity.to_f.clamp(0.0, MAX_INTENSITY)
      @d = [(delay * SAMPLE_RATE).round, 1].max
      @heads = heads
      @ring = Array.new((heads.max * @d) + 1, 0.0)
      @cutoff = lowpass ? 1.0 / ((2 * Math::PI * lowpass * (1.0 / SAMPLE_RATE)) + 1.0) : 0.0
      @drive = 1.0 + (2.0 * saturation)
      @share = 1.0 / heads.size
      @volume = volume
      @cuts = resets.to_h { |at| [at, true] }
      @send = send
      @room = reverb.to_f.positive? ? Reverb.new(reverb) : nil
      @y = 0.0
      @n = 0
    end

    # What the heads give back for a block of input, before any room is put on it.
    def wet(block)
      Array.new(block.size) do |i|
        if @cuts[@n] # a chord changes: what the heads still hold belongs to the old chord and goes quiet
          @ring.fill(0.0)
          @y = 0.0
        end
        taps = 0.0
        @heads.each { |h| taps += @ring[(@n - (h * @d)) % @ring.size] }
        @y += (1.0 - @cutoff) * ((Math.tanh(taps * @share * @drive) / @drive) - @y)
        fed = block[i]
        fed *= @send.call(@n) if @send
        fed *= @boost unless @boost == 1.0
        @ring[@n % @ring.size] = fed + (@intensity * @y)
        @n += 1
        @y
      end
    end

    def process(block)
      heard = wet(block)
      heard = @room.process(heard) if @room
      Array.new(block.size) { |i| block[i] + (@volume * heard[i]) }
    end
  end

  # The 12-bit sampler colour: a drive into a hard band limit, bit and rate reduction, a little
  # hiss and dust, a compressor and a limiter. One instance of it; the engine runs one to three.
  class Sonitex
    def initialize(preset, seed)
      @p = preset
      @rng = seed.is_a?(Random) ? seed : Random.new(seed)
      @pre = Lowpass.new(preset.fetch("dist_pre_lp"))
      @bump_low = Lowpass.new(preset.fetch("head_bump_hz"))
      @bump = Stream.db(preset.fetch("head_bump_db")) - 1.0
      @crush = Crush.new(preset.fetch("crush_bits"), preset.fetch("crush_sr"))
      @post = Lowpass.new(preset.fetch("crush_post_lp"))
      @hf = [Lowpass.new(preset.fetch("hf_rolloff")), Lowpass.new(preset.fetch("hf_rolloff"))]
      @lf = Highpass.new(preset.fetch("lf_rolloff"))
      @comp = Compressor.new(preset.fetch("out_comp_threshold"), preset.fetch("out_comp_ratio"), 12.0, 120.0, preset.fetch("out_comp_makeup") - 1.0)
      @pop = 0.0
    end

    def process(buf)
      p = @p
      drive = p.fetch("dist_drive")
      mix = p.fetch("dist_mix")
      dc = p.fetch("dist_dc")
      tail = Math.tanh(dc)
      crush_mix = p.fetch("crush_mix")
      hiss = p.fetch("hiss_amp")
      pops = p.fetch("pop_rate")
      pop_amp = p.fetch("pop_amp")
      limit = p.fetch("limit")
      level = p.fetch("level_out")
      buf.map do |x|
        wet = Math.tanh((@pre.step(x) * drive) + dc) - tail
        out = (x * (1.0 - mix)) + (wet * mix / [drive, 1.0].max * 1.2)
        out += @bump * @bump_low.step(out)
        crushed = @post.step(@crush.step(out))
        out = (out * (1.0 - crush_mix)) + (crushed * crush_mix)
        out = @lf.step(@hf[1].step(@hf[0].step(out)))
        @pop = (@rng.rand < pops ? (@rng.rand < 0.5 ? -pop_amp : pop_amp) : @pop) * 0.985
        out = out + (((@rng.rand * 2) - 1) * hiss) + (@pop * 0.4)
        limit * Math.tanh(@comp.step(out) / limit) * level
      end
    end
  end
  # Up to three Sonitex passes in series, each with a random stream of its own.
  class SonitexStack
    def initialize(preset, instances, seed)
      @passes = Array.new(instances.clamp(1, 3)) { |k| Sonitex.new(preset, Random.new(seed + (k * 7919))) }
    end

    def process(buf) = @passes.inject(buf) { |out, pass| pass.process(out) }
  end

  # The lowpass the kit voices use, k = 1 - exp(-2 pi f / rate).
  class SmoothLowpass
    def initialize(hz)
      @k = 1.0 - Math.exp(-TAU * hz / SAMPLE_RATE)
      @y = 0.0
    end

    def process(buf) = buf.map { |x| @y += @k * (x - @y) }
  end

  # The chords duck on every kick: the gain at an absolute sample is the deepest dip any kick
  # within four releases before it still makes, so it needs no state and no block size.
  class Duck
    def initialize(kick_times, amount, release_seconds)
      @starts = kick_times.map { |t| (t * SAMPLE_RATE).to_i }.sort
      @amount = amount
      @release = release_seconds * SAMPLE_RATE
      @reach = (@release * 4).to_i
    end

    def apply(block, from)
      return block if @starts.empty? || @amount.zero?

      stop = from + block.size
      near = @starts.select { |s| s < stop && s + @reach > from }
      return block if near.empty?

      block.each_with_index.map do |v, i|
        at = from + i
        dip = 1.0
        near.each do |s|
          n = at - s
          g = n.negative? || n >= @reach ? 1.0 : 1.0 - (@amount * Math.exp(-n / @release))
          dip = g if g < dip
        end
        v * dip
      end
    end
  end

  # A one pole whose cutoff moves in a straight line across each block, so a sweep driven by
  # an event steps no faster than the block and clicks nowhere.
  class SweepLowpass
    def initialize = @y = 0.0

    def process(buf, from_hz, to_hz)
      last = [buf.size - 1, 1].max
      buf.each_with_index.map do |x, i|
        hz = from_hz + ((to_hz - from_hz) * i / last)
        a = 1.0 - Math.exp(-TAU * hz / SAMPLE_RATE)
        @y += a * (x - @y)
      end
    end
  end

  # Sonitex passes of which only the first `active` run.
  class SonitexClimb
    def initialize(preset, seed) = @stack = Array.new(3) { |k| Sonitex.new(preset, Random.new(seed + (k * 104_729))) }

    def process(buf, active) = @stack.first(active.clamp(1, 3)).inject(buf) { |out, pass| pass.process(out) }
  end

  # The room of a reverb swell: the wet signal added at a level that moves across the block.
  class RoomSend
    def initialize(amount = 0.8, side: :left) = @room = Reverb.new(amount, side:)

    def process(buf, from, to)
      wet = @room.process(buf)
      last = [buf.size - 1, 1].max
      buf.each_with_index.map { |x, i| x + (wet[i] * (from + ((to - from) * i / last))) }
    end
  end

  # Notes and hits that start at absolute samples, read out a block at a time. An entry is
  # [start, make, gain, swell, pan]: `make` gives a Reader when its sample comes up, `gain` scales it,
  # `swell` (or nil) is a proc from an absolute sample to a further gain, and `pan` (or nil for the
  # middle) places it between the channels of a stereo block.
  class Bank
    Entry = Struct.new(:start, :make, :gain, :swell, :pan)

    def initialize(entries)
      @pending = entries.sort_by(&:start)
      @active = []
    end

    def finished? = @pending.empty? && @active.empty?

    # The sample at which the last pending note will have started.
    def last_start = @pending.last&.start || 0

    # A frame of `channels` channels: one, or [left, right] with each entry at its pan.
    def block(from, count, channels = 1)
      out = Stereo.zeros(channels, count)
      stop = from + count
      @active.concat(@pending.shift(@pending.index { |e| e.start >= stop } || @pending.size).map { |e| [e, e.make.call] })
      @active.reject! do |entry, reader|
        offset = [entry.start - from, 0].max
        samples = reader.read(count - offset)
        gains = channels == 1 ? [entry.gain] : Stereo.gains(entry.pan || 0.0).map { |g| g * entry.gain }
        samples.each_with_index do |v, j|
          v *= entry.swell.call(from + offset + j) if entry.swell
          gains.each_with_index { |g, c| out[c][offset + j] += v * g }
        end
        reader.done?
      end
      out
    end
  end
end

# --- stereo.rb ---
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
  def self.interleave(frame)
    return frame.first if frame.size == 1

    left, right = frame
    interleaved = Array.new(left.size * 2)
    left.each_index do |index|
      interleaved[index * 2] = left[index]
      interleaved[(index * 2) + 1] = right[index]
    end
    interleaved
  end

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

# --- stages.rb ---
# ------------------------------------------------------------------ stages
# The optional effects a profile lists in its `chain`. Each is a processor for one channel with
# memory of its own, `process(block, from)`, where `from` is the block's first sample in the pass; the
# builder runs one for each channel with a seed of its own, so the two channels are not copies.
# They sit after the colour and before the echo: tone, then dynamics, then colour, then space.
# None of them uses a low-frequency oscillator to move a pitch, a delay or a level; the
# shimmer's pitch shifter and the ring modulator's carrier are what they are, a read pointer and a
# fixed frequency, and the sweeps and swells are events with a start and a length. The cost of
# each, in seconds of work for a second of audio on this Mac, with YJIT, is in the data beside it.
module Stages
  TAU = 2 * Math::PI

  # Dry and wet, the way most of them end.
  def self.blend(dry, wet, mix) = dry.each_index.map { |i| dry[i] + (mix * (wet[i] - dry[i])) }

  # ------------------------------------------------------------ pitch shifter
  # Two read pointers move through a short delay line at a different rate than the write pointer,
  # each faded in and out by a Hann window half a cycle apart, so the sum is steady. Ratio 2 is an octave up.
  class Pitch
    def initialize(ratio, window: 0.06)
      @ratio = ratio
      @size = (window * SAMPLE_RATE).round
      @line = Array.new((@size * 2) + 4, 0.0)
      @n = 0
      @phase = 0.0
      @rate = (1.0 - ratio).to_f / @size
    end

    def step(x)
      len = @line.size
      @line[@n % len] = x
      sum = 0.0
      [0.0, 0.5].each do |offset|
        p = (@phase + offset) % 1.0
        delay = (@size * p) + 1.0
        pos = @n - delay
        base = pos.floor
        frac = pos - base
        a = @line[base % len]
        b = @line[(base + 1) % len]
        sum += (a + ((b - a) * frac)) * (0.5 - (0.5 * Math.cos(TAU * p)))
      end
      @phase = (@phase + @rate) % 1.0
      @n += 1
      sum
    end
  end

  # ------------------------------------------------------------ the room
  # The Freeverb: four combs with damping in the loop, in parallel, then two allpass. `side` moves
  # the delays a little so the right channel is another room.
  class Room
    COMBS = [1116, 1188, 1277, 1356].freeze
    ALLPASS = [556, 441].freeze

    def initialize(decay: 0.84, damp: 0.35, side: 0)
      @combs = COMBS.map { |d| [Array.new(d + (side * 23), 0.0), 0, 0.0] }
      @allpass = ALLPASS.map { |d| [Array.new(d + (side * 23), 0.0), 0] }
      @feedback = decay
      @damp = damp
    end

    def step(x)
      sum = 0.0
      @combs.each do |c|
        line, at, held = c
        out = line[at]
        held = (out * (1.0 - @damp)) + (held * @damp)
        line[at] = (x * 0.015) + (held * @feedback)
        c[1] = (at + 1) % line.size
        c[2] = held
        sum += out
      end
      @allpass.each do |a|
        line, at = a
        buffered = line[at]
        out = buffered - sum
        line[at] = sum + (buffered * 0.5)
        a[1] = (at + 1) % line.size
        sum = out
      end
      sum
    end
  end

  # A plate or a room, after the Freeverb.
  class Plate
    def initialize(spec, _seed, side)
      @room = Room.new(decay: spec.fetch("decay", 0.84), damp: spec.fetch("damp", 0.35), side:)
      @mix = spec.fetch("mix", 0.25)
      @gain = spec.fetch("gain", 30.0)
    end

    def process(block, _from = 0) = block.map { |x| x + (@mix * @room.step(x) * @gain) }
  end

  # The room with an octave-up feedback: what rings in the room is shifted up an octave and fed
  # into the room again, so each round of the tail is higher and quieter.
  class Shimmer
    def initialize(spec, _seed, side)
      @room = Room.new(decay: spec.fetch("decay", 0.88), damp: spec.fetch("damp", 0.45), side:)
      @pitch = Pitch.new(spec.fetch("ratio", 2.0))
      @feedback = spec.fetch("feedback", 0.45)
      @mix = spec.fetch("mix", 0.3)
      @gain = spec.fetch("gain", 30.0)
      @shifted = 0.0
    end

    def process(block, _from = 0)
      block.map do |x|
        wet = @room.step(x + (@feedback * @shifted))
        @shifted = @pitch.step(wet)
        x + (@mix * (wet + (0.5 * @shifted)) * @gain)
      end
    end
  end

  # ------------------------------------------------------------ granular
  # A cloud of Hann-windowed grains from the last couple of seconds of the signal: each grain
  # starts a random way back (the spray), lasts sixty to two hundred milliseconds, and may be an
  # octave up, an octave down, or played backwards. The draws come from a stream seeded for the
  # channel, one per grain, so the cloud is the same however the signal is cut into blocks.
  class Granular
    HISTORY = (2.5 * SAMPLE_RATE).round

    def initialize(spec, seed, _side)
      @rng = Random.new(seed)
      @line = Array.new(HISTORY, 0.0)
      @n = 0
      @density = spec.fetch("density", 9.0)
      @min = (spec.fetch("min_ms", 60) * SAMPLE_RATE / 1000.0).round
      @max = (spec.fetch("max_ms", 200) * SAMPLE_RATE / 1000.0).round
      @spray = spec.fetch("spray", 1.4)
      @up = spec.fetch("up", 0.18)
      @down = spec.fetch("down", 0.10)
      @reverse = spec.fetch("reverse", 0.25)
      @mix = spec.fetch("mix", 0.35)
      @grains = []
      @next_grain = 0
    end

    def process(block, _from = 0)
      block.map do |x|
        @line[@n % HISTORY] = x
        spawn if @n >= @next_grain
        sum = 0.0
        @grains.reject! do |g|
          sum += grain_sample(g)
          g[:age] >= g[:length]
        end
        @n += 1
        x + (@mix * sum)
      end
    end

    private

    def spawn
      @next_grain = @n + ((SAMPLE_RATE / @density) * (0.5 + @rng.rand)).round
      length = @min + @rng.rand(@max - @min + 1)
      roll = @rng.rand
      rate = roll < @up ? 2.0 : (roll < @up + @down ? 0.5 : 1.0)
      backward = @rng.rand < @reverse
      reach = (length * rate).ceil + 8
      back = reach + (@rng.rand * @spray * SAMPLE_RATE).round
      back = [back, HISTORY - 8].min
      start = backward ? @n - back + reach : @n - back
      @grains << { pos: start.to_f, rate: backward ? -rate : rate, age: 0, length:, gain: 0.5 / Math.sqrt([@density * length / SAMPLE_RATE, 1.0].max) }
    end

    def grain_sample(g)
      pos = g[:pos]
      base = pos.floor
      frac = pos - base
      a = @line[base % HISTORY]
      b = @line[(base + 1) % HISTORY]
      window = 0.5 - (0.5 * Math.cos(TAU * g[:age] / g[:length]))
      g[:pos] = pos + g[:rate]
      g[:age] += 1
      (a + ((b - a) * frac)) * window * g[:gain]
    end
  end

  # ------------------------------------------------------------ the simple ones
  class Crush
    def initialize(spec, _seed, _side)
      @crush = Stream::Crush.new(spec.fetch("bits", 10), spec.fetch("factor", 2.0))
      @mix = spec.fetch("mix", 0.5)
    end

    def process(block, _from = 0) = Stages.blend(block, @crush.process(block), @mix)
  end

  # A triangle fold: past one the signal turns back, and again, so a larger input grows more harmonics.
  class Folder
    def initialize(spec, _seed, _side)
      @gain = spec.fetch("gain", 2.4)
      @mix = spec.fetch("mix", 0.3)
    end

    def process(block, _from = 0)
      block.map do |x|
        y = x * @gain
        folded = (4.0 * ((0.25 * y) + 0.25 - ((0.25 * y) + 0.25).round).abs) - 1.0
        x + (@mix * ((folded / @gain) - x))
      end
    end
  end

  # A ring modulator at one fixed frequency.
  class RingMod
    def initialize(spec, _seed, _side)
      @step = TAU * spec.fetch("hz", 140.0) / SAMPLE_RATE
      @mix = spec.fetch("mix", 0.2)
    end

    def process(block, from = 0)
      block.each_with_index.map { |x, i| x + (@mix * ((x * Math.sin(@step * (from + i))) - x)) }
    end
  end

  # A frequency shifter: the signal and its quadrature twin, from two chains of allpass sections
  # whose phases are ninety degrees apart, are multiplied by a cosine and a sine of the shift and
  # subtracted, which moves every partial by the same number of hertz and breaks the harmonic series.
  class FreqShift
    ONE = [0.6923878, 0.9360654322959, 0.9882295226860, 0.9987488452737].freeze
    TWO = [0.4021921162426, 0.8561710882420, 0.9722909545651, 0.9952884791278].freeze

    def initialize(spec, _seed, _side)
      @step = TAU * spec.fetch("hz", 7.0) / SAMPLE_RATE
      @mix = spec.fetch("mix", 0.5)
      @a = ONE.map { |c| c * c }
      @b = TWO.map { |c| c * c }
      @sa = Array.new(@a.size) { [0.0, 0.0, 0.0, 0.0] }
      @sb = Array.new(@b.size) { [0.0, 0.0, 0.0, 0.0] }
      @held = 0.0
    end

    def process(block, from = 0)
      block.each_with_index.map do |x, i|
        ahead = chain(@a, @sa, x)
        imag = chain(@b, @sb, x)
        real = @held # the first branch runs one sample late: that is what puts the two ninety degrees apart
        @held = ahead
        phase = @step * (from + i)
        shifted = (real * Math.cos(phase)) + (imag * Math.sin(phase))
        x + (@mix * (shifted - x))
      end
    end

    private

    # Allpass sections in z^-2, (a - z^-2) / (1 - a z^-2): y = a*x - x[n-2] + a*y[n-2]. A section keeps
    # [x[n-1], x[n-2], y[n-1], y[n-2]].
    def chain(coeffs, states, x)
      coeffs.each_index do |k|
        a = coeffs[k]
        s = states[k]
        y = (a * x) - s[1] + (a * s[3])
        s[1] = s[0]
        s[0] = x
        s[3] = s[2]
        s[2] = y
        x = y
      end
      x
    end
  end

  # The last stretch of each segment, reversed and swelling in beneath the next: the signal of
  # one segment is kept, and played back backwards through the next, rising from nothing.
  class ReverseEcho
    def initialize(spec, _seed, _side)
      @length = (spec.fetch("seconds", 1.0) * SAMPLE_RATE).round
      @mix = spec.fetch("mix", 0.4)
      @kept = Array.new(@length, 0.0)
      @played = Array.new(@length, 0.0)
      @n = 0
    end

    def process(block, _from = 0)
      block.map do |x|
        at = @n % @length
        @kept[at] = x
        swell = (at.to_f / @length)**2
        out = x + (@mix * @played[@length - 1 - at] * swell)
        if at == @length - 1
          @played, @kept = @kept, @played
        end
        @n += 1
        out
      end
    end
  end

  # The tape stops: in the last `seconds` before the pass ends the read pointer slows to nothing,
  # the pitch falling with it, and the sound is gone.
  class TapeStop
    def initialize(spec, _seed, _side, end_sample: 0)
      @length = (spec.fetch("seconds", 0.8) * SAMPLE_RATE).round
      @end = end_sample
      @line = Array.new(@length + 8192, 0.0)
      @n = 0
      @pos = nil
      @speed = 1.0
    end

    def process(block, from = 0)
      return block if @end <= 0

      len = @line.size
      block.each_with_index.map do |x, i|
        at = from + i
        @line[@n % len] = x
        @n += 1
        out = x
        if at >= @end - @length
          @pos ||= @n - 1.0
          progress = [(at - (@end - @length)).to_f / @length, 1.0].min
          @speed = (1.0 - progress)**1.5
          base = @pos.floor
          frac = @pos - base
          a = @line[base % len]
          b = @line[(base + 1) % len]
          out = (a + ((b - a) * frac)) * (1.0 - (progress**3))
          @pos += @speed
        end
        out
      end
    end
  end

  # A filter sweep that is an event, not an oscillator: every `every_bars` bars the cutoff falls
  # from the top to `low_hz` over `bars` bars and comes back over the same. The cutoff is a function
  # of the sample's place in the pass, set afresh every 64 samples, so how the pass is cut into
  # blocks makes no difference.
  class Sweep
    STEP = 64

    def initialize(spec, _seed, _side, bar_samples: 1)
      @bar = bar_samples
      @every = spec.fetch("every_bars", 8)
      @bars = spec.fetch("bars", 2)
      @low = spec.fetch("low_hz", 500.0)
      @top = spec.fetch("top_hz", 16_000.0)
      @y = 0.0
      @a = 1.0
    end

    def process(block, from = 0)
      block.each_with_index.map do |x, i|
        at = from + i
        @a = 1.0 - Math.exp(-TAU * cutoff(at) / SAMPLE_RATE) if (at % STEP).zero?
        @y += @a * (x - @y)
      end
    end

    private

    def cutoff(at)
      into = (at.to_f / @bar) % @every
      return @top if into >= @bars * 2

      half = into < @bars ? into / @bars : ((@bars * 2) - into) / @bars
      @top * ((@low / @top)**half)
    end
  end

  # Attack and sustain: a fast and a slow follower, and the difference between them lifts the front of
  # a note or lowers what is left after it.
  class Transient
    def initialize(spec, _seed, _side)
      @attack = 10.0**(spec.fetch("attack_db", 4.0) / 20.0)
      @sustain = 10.0**(spec.fetch("sustain_db", -2.0) / 20.0)
      @fast = 0.0
      @slow = 0.0
      @up_fast = 1.0 - Math.exp(-1.0 / (0.001 * SAMPLE_RATE))
      @down_fast = 1.0 - Math.exp(-1.0 / (0.02 * SAMPLE_RATE))
      @up_slow = 1.0 - Math.exp(-1.0 / (0.03 * SAMPLE_RATE))
      @down_slow = 1.0 - Math.exp(-1.0 / (0.3 * SAMPLE_RATE))
    end

    def process(block, _from = 0)
      block.map do |x|
        a = x.abs
        @fast += (a > @fast ? @up_fast : @down_fast) * (a - @fast)
        @slow += (a > @slow ? @up_slow : @down_slow) * (a - @slow)
        lean = ((@fast - @slow) / (@slow + 1e-3)).clamp(-1.0, 1.0)
        x * (lean.positive? ? 1.0 + (lean * (@attack - 1.0)) : 1.0 + (-lean * (@sustain - 1.0)))
      end
    end
  end

  # The band above six kilohertz driven into a soft clip and added back: the harmonics it makes
  # are air that was never in the recording.
  class Exciter
    def initialize(spec, _seed, _side)
      @high = Stream::Highpass.new(spec.fetch("hz", 6000.0))
      @drive = spec.fetch("drive", 3.0)
      @mix = spec.fetch("mix", 0.25)
    end

    def process(block, _from = 0)
      block.map { |x| x + (@mix * Math.tanh(@high.step(x) * @drive) / @drive * 2.0) }
    end
  end

  # Bandpass resonators at inharmonic partials with a high Q, the colour of a mouth without its
  # vowels. The bank rings on what is put into it and is added to the dry signal.
  class CombBank
    RATIOS = [1.0, 2.76, 5.40, 8.93, 13.34].freeze

    def initialize(spec, _seed, _side)
      base = spec.fetch("hz", 220.0)
      q = spec.fetch("q", 18.0)
      @bands = RATIOS.map { |r| Tape::Biquad.bandpass([base * r, SAMPLE_RATE * 0.45].min, q) }
      @mix = spec.fetch("mix", 0.35)
    end

    def process(block, _from = 0)
      rung = @bands.map { |band| band.process(block) }
      block.each_index.map { |i| block[i] + (@mix * rung.sum { |r| r[i] } / @bands.size * 2.0) }
    end
  end

  KINDS = {
    "plate" => Plate, "shimmer" => Shimmer, "granular" => Granular, "crush" => Crush, "folder" => Folder, "ringmod" => RingMod,
    "freqshift" => FreqShift, "reverse_echo" => ReverseEcho, "tapestop" => TapeStop, "sweep" => Sweep, "transient" => Transient,
    "exciter" => Exciter, "comb_bank" => CombBank
  }.freeze

  # One stage of a profile's chain, as a Pair of processors for `channels` channels. A row of the
  # chain is a name, or { 'stage' => name, ...overrides } laid over the stage's defaults.
  def self.build(row, defaults, channels:, seed:, end_sample: 0, bar_samples: 1)
    row = { "stage" => row } if row.is_a?(String)
    name = row.fetch("stage")
    spec = defaults.fetch(name) { raise ArgumentError, "no stage #{name.inspect}" }.merge(row.reject { |k, _| k == "stage" })
    klass = KINDS.fetch(name)
    parts = Array.new(channels) do |c|
      channel_seed = Zlib.crc32("#{seed}:#{name}:#{c}")
      case name
      when "tapestop" then klass.new(spec, channel_seed, c, end_sample:)
      when "sweep" then klass.new(spec, channel_seed, c, bar_samples:)
      else klass.new(spec, channel_seed, c)
      end
    end
    Chained.new(parts)
  end

  # A stage on each channel; a block is a frame.
  class Chained
    def initialize(parts) = @parts = parts

    def process(frame, from = 0) = frame.each_with_index.map { |channel, c| @parts[c].process(channel, from) }
  end
end

# --- noise.rb ---
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
      @high = Stream::Highpass.new(spec.fetch("hz", 8000.0))
      @gain = Noise.gain(spec.fetch("db", -54.0)) * 4.0
    end

    def block(count) = Array.new(count) { @high.step(@pink.step) * @gain }
  end

  # Brown noise (white noise, integrated and leaking) under 200 Hz: the bed of a tape.
  class Bed
    def initialize(spec, seed)
      @rng = Random.new(seed)
      @low = Stream::Lowpass.new(spec.fetch("hz", 200.0))
      @y = 0.0
      @gain = Noise.gain(spec.fetch("db", -48.0)) * 3.0
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
    poisson(rng, spec.fetch("rate", 3.0), seconds).map do |t|
      samples = pop(rng, spec.fetch("db", -42.0))
      Stream::Bank::Entry.new((t * SAMPLE_RATE).to_i, -> { Voices::Reader.of(samples) }, 1.0, nil, (rng.rand * 2) - 1)
    end
  end

  # Bank entries for the sparkle of a pass: at each event a tone of the chord sounding then, put up
  # to the octave that lies between 4 and 8 kilohertz, at a place of its own.
  def self.sparkle(spec, seed, seconds, chord_at)
    rng = Random.new(seed)
    low, high = spec.fetch("midi", [108, 119])
    poisson(rng, spec.fetch("rate", 1.6), seconds).map do |t|
      pcs = chord_at.call(t)
      pc = pcs[rng.rand(pcs.size)]
      midi = (low..high).select { |n| n % 12 == pc }.sample(random: rng) || low
      decay = 0.08 + (rng.rand * 0.25)
      freq = Chords.hz(midi)
      db = spec.fetch("db", -30.0) - (rng.rand * 6)
      pan = ((rng.rand * 2) - 1) * spec.fetch("width", 0.8)
      Stream::Bank::Entry.new((t * SAMPLE_RATE).to_i, -> { glint(freq, decay, db) }, 1.0, nil, pan)
    end
  end
end

# --- chords.rb ---
# ------------------------------------------------------------------- chords
# A chord name becomes notes here and nowhere else: the root or slash bass in the low octave,
# then the upper structure. Each upper note starts as near as it can be to the last chord, and
# a search over octave shifts then picks the voicing that moves least, keeps the top line
# smooth and leaves no neighbours closer than a whole tone. No chord tone is ever dropped
# for spacing; only the fifth, then the root when the bass plays it, give way to the voice cap.
module Chords
  NOTE_PC = { "C" => 0, "D" => 2, "E" => 4, "F" => 5, "G" => 7, "A" => 9, "B" => 11 }.freeze
  ACCIDENTAL = { "b" => -1, "#" => 1, "" => 0 }.freeze

  # "Dbmaj7#11" => root pitch class, tones in semitones above the root, slash bass or nil.
  def self.parse(name)
    m = name.to_s.sub("6/9", "69").match(%r{\A([A-G])([b#]?)([^/]*)(?:/([A-G])([b#]?))?\z}) or
      raise ArgumentError, "chord #{name.inspect}: no root"
    bass = m[4] && (NOTE_PC.fetch(m[4]) + ACCIDENTAL.fetch(m[5])) % 12
    { pc: (NOTE_PC.fetch(m[1]) + ACCIDENTAL.fetch(m[2])) % 12, tones: tones(m[3], name), bass: }
  end

  # Triads, sixths, sevenths, ninths, elevenths, thirteenths, add9/11/13, sus2/sus4 and
  # the alterations b5 #5 b9 #9 #11 b13. Anything left over is an error, named.
  def self.tones(quality, name)
    s = quality.delete("(),")
    third = 4
    fifth = 7
    seventh = sixth = nil
    extensions = []
    third = 3 if s.sub!(/\A(?:min|mi|-|m(?!aj))/, "")
    if s.sub!(/\Adim/, "")
      third = 3
      fifth = 6
      seventh = 9 if s.start_with?("7")
    end
    fifth = 8 if s.sub!(/\A(?:aug|\+)/, "")
    third = 2 if s.sub!(/sus2/, "")
    third = 5 if s.sub!(/sus4|sus/, "")
    level = 0
    if s.sub!(/\A(?:maj|M)(7|9|11|13)?/, "")
      level = Regexp.last_match(1).to_i
      seventh = 11 if level.positive?
    elsif (digits = s[/\A(?:7|9|11|13)/])
      level = digits.to_i
      seventh ||= 10
      s.sub!(/\A(?:7|9|11|13)/, "")
    elsif s.sub!(/\A69/, "")
      sixth = 9
      extensions << 14
    elsif s.sub!(/\A6/, "")
      sixth = 9
    end
    extensions << 14 if level >= 9
    extensions << 17 if level == 11
    extensions << 21 if level >= 13
    extensions << 14 if s.sub!(/add9/, "")
    extensions << 17 if s.sub!(/add11/, "")
    extensions << 21 if s.sub!(/add13/, "")
    sixth = 9 if s.sub!(/add6/, "")
    if s.sub!(/alt/, "")
      seventh ||= 10
      fifth = nil
      extensions = [13, 20]
    end
    while (alteration = s.slice!(/[b#](?:5|9|11|13)/))
      case alteration
      when "b5" then fifth = 6
      when "#5" then fifth = 8
      when "b9" then extensions = extensions.reject { |e| e == 14 } + [13]
      when "#9" then extensions = extensions.reject { |e| e == 14 } + [15]
      when "#11" then extensions = extensions.reject { |e| e == 17 } + [18]
      when "b13" then extensions = extensions.reject { |e| e == 21 } + [20]
      end
    end
    raise ArgumentError, "chord #{name.inspect}: cannot read #{s.inspect}" unless s.empty?

    ([0, third, fifth, sixth, seventh] + extensions).compact.uniq.sort
  end

  MAX_VOICES = 5   # the bass and four above it
  LOW = 52         # the upper structure sits between these two notes
  HIGH = 84
  MIN_GAP = 2      # neighbours are at least a whole tone apart: no minor second rubs
  CENTRE = 66      # the middle of that register, which the search is gently pulled toward
  PULL = 0.1       # semitones of cost per semitone the voicing sits from the centre

  # The tones above the bass, as pitch classes. The root stays out when the bass already
  # plays it and the chord has more than a triad; when the chord is over the voice cap the
  # perfect fifth goes first, then an altered fifth, then the root. The third or sus tone,
  # the sixth or seventh and every named extension are never dropped.
  def self.upper_pcs(chord)
    bass_pc = chord[:bass] || chord[:pc]
    tones = chord[:tones].dup
    tones -= [0] if tones.size > 3 && bass_pc == chord[:pc]
    [[7], [6, 8], [0]].each do |drop|
      tones -= drop if tones.size > MAX_VOICES - 1
    end
    tones.map { |semi| (chord[:pc] + semi) % 12 }.uniq
  end

  # The note for a pitch class nearest any of the reference notes, inside the register.
  def self.nearest(pc, reference)
    options = (LOW..HIGH).select { |n| n % 12 == pc }
    options.min_by { |n| [reference.map { |r| (n - r).abs }.min, n] }
  end

  def self.valid?(upper)
    upper.first >= LOW && upper.last <= HIGH && upper.each_cons(2).all? { |a, b| b - a >= MIN_GAP }
  end

  # Mean distance each new note moves from its nearest old one, plus the top line's own
  # movement at full weight, plus a small pull toward the middle of the register.
  def self.cost(upper, before)
    pull = PULL * (upper.sum.to_f / upper.size - CENTRE).abs
    return pull if before.empty?

    mean = upper.sum { |n| before.map { |b| (n - b).abs }.min }.to_f / upper.size
    mean + (upper.last - before.last).abs + pull
  end

  # One voicing as MIDI notes, lowest first. Each upper note starts at the one nearest the
  # last chord, then the search tries every octave shift (down, none, up) on every voice and
  # keeps the cheapest set that has no duplicate pitch and no neighbours closer than MIN_GAP.
  def self.voice(name, previous = nil, search: true, style: self.style)
    chord = parse(name)
    bass = 36 + (((chord[:bass] || chord[:pc]) - 36) % 12)
    before = previous ? previous.drop(1) : []
    reference = before.empty? ? [CENTRE] : before
    start = upper_pcs(chord).map { |pc| nearest(pc, reference) }.sort
    return [bass] + restyle(apart(start), style) unless search

    best = nil
    [-12, 0, 12].repeated_permutation(start.size) do |shifts|
      upper = start.zip(shifts).map { |n, s| n + s }.sort
      next unless valid?(upper)

      score = cost(upper, before)
      best = [score, upper] if best.nil? || score < best.first - 1e-9
    end
    [bass] + restyle(best ? best.last : apart(start), style)
  end

  # The ways a player can lay the same chord out. nil keeps the voice-led default above. drop2 and
  # drop3 take the second or third voice from the top down an octave; spread lifts every other voice
  # an octave; cluster packs the tones into one close position. quartal and so_what rebuild the upper
  # structure as stacked fourths (so_what ends on a major third) and so name no mode: the pitch classes
  # of the chord are not kept, only its register and its lowest upper note.
  STYLES = %w[drop2 drop3 spread cluster quartal so_what].freeze

  @style = nil

  def self.style = @style

  def self.check_style(name)
    return if name.nil? || STYLES.include?(name.to_s)

    raise ArgumentError, "voicing #{name.inspect}: expected one of #{STYLES.join(', ')}"
  end

  # Runs the block with every voicing laid out in `name` (nil for the default), then puts the last one back.
  def self.styled(name)
    check_style(name)

    before = @style
    @style = name&.to_s
    yield
  ensure
    @style = before
  end

  # Lays every later voicing out in `name` for the rest of the run (nil returns to the default).
  def self.use(name)
    check_style(name)

    @style = name&.to_s
  end

  LAYOUTS = {
    "drop2" => ->(upper) { drop(upper, 2) },
    "drop3" => ->(upper) { drop(upper, 3) },
    "spread" => ->(upper) { upper.each_with_index.map { |n, i| i.odd? && n + 12 <= HIGH ? n + 12 : n } },
    "cluster" => ->(upper) { close_position(upper) },
    "quartal" => ->(upper) { stack(upper, [0, 5, 10, 15, 20]) },
    "so_what" => ->(upper) { stack(upper, [0, 5, 10, 15, 20].first(upper.size).tap { |s| s[-1] = s[-2].to_i + 4 if s.size > 1 }) },
  }.freeze

  def self.restyle(upper, style)
    layout = LAYOUTS[style] or return upper
    seat(layout.call(upper).sort.uniq)
  end

  # The nth voice from the top, an octave lower, when four voices are there to take it from.
  def self.drop(upper, nth)
    return upper if upper.size < 4

    out = upper.dup
    lowered = out[-nth] - 12
    out[-nth] = lowered if lowered >= LOW
    out
  end

  # Every pitch class once, each the nearest note above the one before, from the lowest voice up.
  def self.close_position(upper)
note = upper.min
others = upper.map { |n| n % 12 }.uniq.reject { |pc| pc == note % 12 }.sort_by { |pc| (pc - note) % 12 }
[note] + others.map { |pc| note += (pc - note) % 12 }
  end

  def self.stack(upper, steps)
    steps.first(upper.size).map { |step| upper.min + step }
  end

  # Moves a whole voicing by octaves into the register, then opens any minor second.
  def self.seat(notes)
    notes = notes.map { |n| n - 12 } while notes.last > HIGH && notes.first - 12 >= LOW
    notes = notes.map { |n| n + 12 } while notes.first < LOW
    apart(notes)
  end

  # A minor second between neighbours is a rub: the upper one goes up an octave, or when
  # that leaves the register the lower one goes down.
  def self.apart(notes)
    out = notes.sort
    12.times do
      i = (1...out.size).find { |k| out[k] - out[k - 1] < MIN_GAP } or break
      out[i] + 12 <= HIGH ? out[i] += 12 : out[i - 1] -= 12
      out.sort!
    end
    out
  end

  def self.hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

  # One voicing per chord of a progression, as MIDI notes; each leads from the one before.
  # `transpose` moves every note by that many semitones after voicing (no resampling, the
  # timing is untouched); `wrap` then folds any note still above the audible top down by octaves.
  def self.midi_notes(names, search: true, transpose: 0, wrap: false)
    previous = nil
    names.map do |name|
      previous = voice(name, previous, search:)
      notes = previous.map { |n| n + transpose }
      wrap ? notes.map { |n| fold(n) } : notes
    end
  end

  def self.fold(note)
    note -= 12 while hz(note) > AUDIBLE_TOP_HZ
    note
  end

  def self.freqs(names, search: true, transpose: 0, wrap: false)
    midi_notes(names, search:, transpose:, wrap:).map { |notes| notes.map { |n| hz(n) } }
  end
end

# Twelve progressions the engine writes from rules rather than from records. Each language is a
# constraint on harmonic motion, a list of [root offset in semitones, quality] against a tonic:
# Fifths moves by descending fifths and prepared suspensions, the pedal languages sit a pedal under
# borrowed mixture, planing moves one quality as a shape (or holds a slash pedal), the quartal
# languages stack fourths and refuse to resolve, and the static one keeps the bass still under
# suspended chords. The tonic is Bb, the
# centre the rest of the catalogue is locked to, so every language shares a key with the curated rotation.
module Languages
  # Quality => chord-name suffix the Chords parser reads. q4 and q4b have no name of their own:
  # the eleventh and thirteenth chords carry the same stacked-fourth colour.
  SUFFIX = {
    "maj" => "", "min" => "m", "dim" => "dim", "maj7" => "maj7", "maj9" => "maj9", "m7" => "m7",
    "m9" => "m9", "m11" => "m11", "7" => "7", "sus2" => "sus2", "sus4" => "sus4", "sus9" => "9sus4",
    "add9" => "add9", "q4" => "m11", "q4b" => "m13", "maj7#11" => "maj7#11", "13" => "13",
    "7alt" => "7alt", "m6/9" => "m69", "13sus" => "13sus4"
  }.freeze

  ROOTS = %w[C Db D Eb E F Gb G Ab A Bb B].freeze
  TONIC = 10 # Bb

  SPECS = {
    "falling_fifths" => [[0, "min"], [5, "min"], [10, "maj"], [3, "maj7"], [8, "maj"], [1, "dim"], [7, "sus4"], [0, "min"]],
    "suspension_chain" => [[0, "min"], [7, "sus4"], [7, "maj"], [5, "min"], [0, "sus4"], [0, "min"], [10, "maj7"], [0, "min"]],
    "pedal_mixture" => [[0, "m9"], [10, "add9"], [8, "maj7"], [0, "m9"], [0, "m9"], [11, "maj"], [7, "min"], [0, "m9"]],
    "motif_fall" => [[0, "min"], [10, "maj"], [5, "min"], [0, "min"], [0, "min"], [11, "min"], [7, "maj7"], [0, "m9"]],
    "planing_m9" => [[0, "m9"], [-2, "m9"], [-3, "m9"], [-5, "m9"], [0, "m9"], [-2, "m9"], [-4, "m9"], [-5, "m9"]],
    "maj9_walk" => [[0, "maj9"], [-1, "maj9"], [-3, "maj9"], [-4, "maj9"], [0, "maj9"], [-1, "maj9"], [2, "maj9"], [0, "maj9"]],
    "slash_pedal" => [[0, "m11"], [5, "m9"], [3, "maj9"], [10, "m9"], [0, "m11"], [5, "m9"], [8, "maj9"], [0, "m11"]],
    "chromatic_drop" => [[0, "m9"], [-1, "m9"], [-2, "m9"], [-3, "m9"], [-4, "m9"], [-3, "m9"], [-1, "m9"], [0, "m9"]],
    "quartal_mediants" => [[0, "q4"], [4, "q4"], [8, "q4b"], [4, "q4"], [-4, "q4"], [-8, "q4b"], [3, "q4"], [8, "q4"]],
    "unresolved_stack" => [[0, "q4b"], [6, "q4"], [1, "q4"], [8, "q4b"], [3, "q4"], [-2, "q4"], [7, "q4b"], [6, "q4"]],
    "static_suspensions" => [[0, "sus2"], [0, "sus4"], [0, "m9"], [0, "sus2"], [5, "sus2"], [0, "sus4"], [10, "sus2"], [0, "m9"]],
    "dorian_lift" => [[0, "m9"], [5, "maj"], [10, "sus2"], [0, "m9"], [2, "min"], [5, "maj"], [10, "add9"], [0, "m9"]],
  }.freeze

  def self.names = SPECS.keys

  # The chord names of one language in `tonic` (a pitch class, Bb by default).
  def self.progression(language, tonic: TONIC)
    SPECS.fetch(language) { raise ArgumentError, "language #{language.inspect}: expected one of #{names.join(', ')}" }
         .map { |offset, quality| "#{ROOTS[(tonic + offset) % 12]}#{SUFFIX.fetch(quality)}" }
  end

  def self.all(tonic: TONIC) = SPECS.keys.to_h { |language| [language, progression(language, tonic:)] }
end

# One tonal centre across a rotation. Progressions come from records in different keys, and a
# stream that alternates a Bb piece with an E piece (a tritone apart, the furthest there is) has
# no centre at all. KeyLock moves a progression's roots, and its slash basses, so it rests on the
# chosen tonic: chord quality, extensions and voicing intent are untouched, so this is
# transposition and not reharmonisation.
module KeyLock
  PITCH = { "C" => 0, "D" => 2, "E" => 4, "F" => 5, "G" => 7, "A" => 9, "B" => 11 }.freeze
  NAMES = %w[C Db D Eb E F Gb G Ab A Bb B].freeze
  SYMBOL = %r{\A([A-G][b#]?)([^/]*)(?:/([A-G][b#]?))?\z}
  # When this share of chords stand over one bass note, that bass is the tonic: a chromatic
  # descent over a standing pedal rests on the pedal, not on its last chord.
  PEDAL_SHARE = 0.6
  # Bb: half the catalogue's curated progressions already rest there.
  DEFAULT = "Bb"

  def self.pitch_class(name)
    match = name.to_s.match(/\A([A-G])([b#]?)\z/) or raise ArgumentError, "note #{name.inspect}"
    letter, accidental = match.captures
    (PITCH.fetch(letter) + Chords::ACCIDENTAL.fetch(accidental)) % 12
  end

  def self.parts(chord)
    SYMBOL.match(chord.to_s.sub("6/9", "69")) or raise ArgumentError, "chord #{chord.inspect}: no root"
  end

  def self.tonic(names)
    parsed = names.map { |chord| parts(chord) }
    basses = parsed.filter_map { |m| m[3] }
    if basses.size >= parsed.size * PEDAL_SHARE
      pedal, count = basses.tally.max_by { |_note, n| n }
      return pedal if count >= basses.size * PEDAL_SHARE
    end
    parsed.last[1]
  end

  # The fewest semitones, up or down, that bring `from` to `to`; never more than six.
  def self.interval(from, to)
    delta = (pitch_class(to) - pitch_class(from)) % 12
    delta > 6 ? delta - 12 : delta
  end

  def self.shift(chord, semitones)
    m = parts(chord)
    bass = m[3] && "/#{NAMES[(pitch_class(m[3]) + semitones) % 12]}"
    "#{NAMES[(pitch_class(m[1]) + semitones) % 12]}#{m[2]}#{bass}"
  end

  def self.lock(names, target = DEFAULT)
    semitones = interval(tonic(names), target)
    semitones.zero? ? names : names.map { |chord| shift(chord, semitones) }
  end
end

# Which locked progressions share a scale, not only a root. The collection is Bb Dorian/Aeolian
# with the major third (the bittersweet soul region and its parallel major); a progression's fit
# is the share of its roots, after the lock, that lie inside it. Roots and not every tone, because
# an extension may borrow from outside the key for one chord without leaving it.
module ModalFamily
  DEGREES = %w[Bb C Db D Eb F Gb G Ab].freeze
  # 0.80 keeps every progression Dilla himself produced and still excludes the ones that modulate.
  THRESHOLD = 0.80

  def self.collection = @collection ||= DEGREES.map { |note| KeyLock.pitch_class(note) }

  def self.fit(names, target = KeyLock::DEFAULT)
    roots = KeyLock.lock(names, target).map { |chord| KeyLock.pitch_class(KeyLock.parts(chord)[1]) }
    roots.count { |pc| collection.include?(pc) }.fdiv(roots.size)
  end

  def self.compatible?(names, target = KeyLock::DEFAULT) = fit(names, target) >= THRESHOLD
end

# A lead and a bass worked out from the chords instead of written down. A voicing fills the
# harmony; a line moves against it, which is what a player adds. Both return melody events
# ([beat, midi, length in beats, gain]) the sequencer already plays, and both are seeded, so a take
# can be played again.
module Lines
  # Semitones above the chord root. First match wins. A minor seventh takes Dorian, whose raised sixth
  # keeps a line from turning mournful; a major seventh takes Lydian, whose raised fourth sounds chosen.
  SCALES = [
    [[4, 11], [0, 2, 4, 6, 7, 9, 11]],
    [[3, 10], [0, 2, 3, 5, 7, 9, 10]],
    [[4, 10], [0, 2, 4, 5, 7, 9, 10]],
    [[3, 7], [0, 2, 3, 5, 7, 8, 10]],
    [[4, 7], [0, 2, 4, 5, 7, 9, 11]],
  ].freeze
  PENTATONIC = [0, 3, 5, 7, 10].freeze
  LEAD_BASE = 60 # the lowest root the line sits on: guide tones then top out near Bb5, over the pad and under the ceiling
  BASS_LOW = 28
  BASS_HIGH = 40
  DENSITY = 0.35 # the chance of a passing tone between the target and the approach

  def self.scale_for(chord)
    tones = chord[:tones].map { |t| t % 12 }
    (SCALES.find { |required, _| required.all? { |i| tones.include?(i) } } || [nil, PENTATONIC]).last
  end

  # The two notes that say which chord this is. Root and fifth are the same in a major, a minor and a
  # dominant; the third and the seventh differ, so a line states them first.
  def self.guide_tones(chord)
    tones = chord[:tones].map { |t| t % 12 }
    guides = (tones & [3, 4]) + (tones & [10, 11])
    guides.empty? ? (tones & [2, 5, 7]).first(1) : guides
  end

  def self.root_note(chord, floor) = floor + ((chord[:pc] - floor) % 12)

  # Three notes over a chord, into the next: a guide tone on the downbeat, a chromatic approach a
  # semitone from the next target on the offbeat before it, and the next chord's guide tone as the
  # landing, so the line crosses the change instead of stopping at it.
  def self.lead(names, beats:, seed:, density: DENSITY)
    rng = Random.new(seed)
    chords = names.map { |name| Chords.parse(name) }
    step = beats / 8.0
    chords.each_with_index.flat_map do |chord, i|
      guides = guide_tones(chord)
      next [] if guides.empty?

      scale = scale_for(chord)
      root = root_note(chord, LEAD_BASE)
      target = guides.sample(random: rng)
      at = i * beats
      events = [[at, root + target, step * 2.2, 0.34]]
      if rng.rand < density
        degree = (scale.index(target) || 0) + [-2, -1, 1, 2].sample(random: rng)
        octave, index = degree.clamp(-7, 13).divmod(scale.size)
        events << [at + (step * 3), root + (12 * octave) + scale[index], step, 0.26]
      end
      following = chords[(i + 1) % chords.size]
      next_guides = guide_tones(following)
      unless next_guides.empty?
        landing = root_note(following, LEAD_BASE) + next_guides.sample(random: rng)
        landing -= 12 while landing - (root + target) > 7
        landing += 12 while (root + target) - landing > 7
        events << [at + (step * 6.5), landing + (rng.rand < 0.5 ? -1 : 1), step * 0.5, 0.24]
        events << [at + (step * 7), landing, step * 1.4, 0.32]
      end
      events
    end
  end

  # The root where the harmony changes, an octave answer in the gap, and a step toward the next root,
  # long enough to still sound when the next arrives (rests on the one, lands just after it).
  def self.bass(names, beats:, seed:)
    rng = Random.new(seed + 1)
    chords = names.map { |name| Chords.parse(name) }
    chords.each_with_index.flat_map do |chord, i|
      root = bass_root(chord[:bass] || chord[:pc])
      at = i * beats
      events = [[at + (beats * 0.12), root, beats * 0.55, 0.85]]
      events << [at + (beats * 0.5), root + 12, beats * 0.2, 0.5] if rng.rand < 0.6
      target = bass_root(chords[(i + 1) % chords.size][:pc])
      gap = target - root
      if gap != 0 && gap.abs <= 7
        events << [at + (beats * 0.82), root + (gap.positive? ? [1, 2] : [-1, -2]).sample(random: rng), beats * 0.16, 0.6]
      end
      events
    end
  end

  def self.bass_root(pc) = BASS_LOW + ((pc - BASS_LOW) % 12)
end

# --- synthesis.rb ---
# --------------------------------------------------------------- synthesis
module Synth
  def self.env(t, dur, attack: 0.01, release: 0.3)
    if t < attack
      t / attack
    elsif t > dur - release
      [(dur - t) / release, 0.0].max
    else
      1.0
    end
  end

  # A true single-frequency oscillator: no upper harmonics, detune, chorus or modulation.
  # Release begins after the gate, so short notes remain at full level until they end.
  def self.pure_note(freq, dur, amp: 0.2, release: 0.12, attack: 0.008)
    return [] unless freq.positive? && freq <= SAMPLE_RATE * NYQUIST_SHARE

    release = [release.to_f, 0.001].max
    n = ((dur + release) * SAMPLE_RATE).to_i
    phase = 0.0
    step = 2.0 * Math::PI * freq / SAMPLE_RATE
    Array.new(n) do |i|
      t = i.to_f / SAMPLE_RATE
      envelope =
        if t < attack
          t / attack
        elsif t < dur
          1.0
        else
          [1.0 - ((t - dur) / release), 0.0].max
        end
      sample = Math.sin(phase) * envelope * amp
      phase += step
      sample
    end
  end

  # One note = sum of four harmonics with optional per-note detune.
  def self.note(freq, dur, detune: 0.0, amp: 0.2, release: 0.3)
    n = (dur * SAMPLE_RATE).to_i
    out = Array.new(n, 0.0)
    partials = [[1.0, 1.0], [2.0, 0.35], [3.0, 0.15], [4.0, 0.08]]

    partials.each do |mult, pamp|
      f = freq * mult * (1.0 + detune)
      next if f > SAMPLE_RATE * NYQUIST_SHARE # a partial past the limit would fold back down: skip it
      phase = 0.0
      step = 2 * Math::PI * f / SAMPLE_RATE
      n.times do |i|
        t = i.to_f / SAMPLE_RATE
        out[i] += Math.sin(phase) * pamp * env(t, dur, release:)
        phase += step
      end
    end
    out.map { |s| s * amp }
  end

  # One chord = sum of its notes, each with alternating detune for warmth.
  def self.chord(freqs, dur, detune: 0.0, strum: 0.0)
    n = (dur * SAMPLE_RATE).to_i
    buf = Array.new(n, 0.0)
    freqs.each_with_index do |f, idx|
      d = detune * (idx.even? ? 1 : -1)
      note_buf = note(f, dur, detune: d, amp: 1.0 / freqs.size)
      late = (strum * idx * SAMPLE_RATE).to_i # each voice a little after the one below
      note_buf.each_with_index { |s, i| buf[i + late] += s if i + late < n }
    end
    buf
  end
end

# --- voices.rb ---
# ------------------------------------------------------------------ voices
# Every voice turns a note (a frequency, a length and a level) into samples. The sine voice
# above is the plain one; these are the others, each described by a row of dilla.json.
# Nothing here resamples: a note is synthesised at its own pitch, and a fundamental above
# NYQUIST_SHARE of the sample rate is dropped, never folded back down.
module Voices
  TAU = 2 * Math::PI

  def self.audible?(freq) = freq.positive? && freq <= SAMPLE_RATE * NYQUIST_SHARE

  # A held level 0..1 for an [attack, decay, sustain, release] envelope, linear segments.
  def self.adsr(env, t, gate)
    a, d, s, r = env
    return adsr_level(a, d, s, t) if t <= gate

    [adsr_level(a, d, s, gate) * (1.0 - ((t - gate) / (r > 1e-4 ? r : 1e-4))), 0.0].max
  end

  def self.adsr_level(a, d, s, x)
    if x < a then x / (a > 1e-4 ? a : 1e-4)
    elsif x < a + d then 1.0 - ((1.0 - s) * (x - a) / (d > 1e-4 ? d : 1e-4))
    else s
    end
  end

  # A note read a block at a time. The block makes sample i from state it closes over, so a note
  # can be begun, left, and taken up again where it stopped, as a streamed note must.
  class Reader
    attr_reader :size

    def self.empty = new(0) { 0.0 }

    def self.of(samples) = new(samples.size) { |i| samples[i] }

    def initialize(size, &sample)
      @size = size
      @sample = sample
      @at = 0
    end

    def done? = @at >= @size

    def remaining = @size - @at

    # Up to `count` of the next samples; fewer at the end, none after it.
    def read(count)
      take = [count, remaining].min
      i = @at
      out = Array.new(take) do
        v = @sample.call(i)
        i += 1
        v
      end
      @at = i
      out
    end

    def drain = read(@size)
  end

  WAVES = {
    "saw" => ->(p) { (2.0 * p) - 1.0 },
    "pulse" => ->(p) { p < 0.5 ? 1.0 : -1.0 },
    "triangle" => ->(p) { p < 0.5 ? (4.0 * p) - 1.0 : 3.0 - (4.0 * p) },
    "sine" => ->(p) { Math.sin(TAU * p) },
  }.freeze

  # The polynomial band-limited step: the correction that rounds each jump of a saw or a pulse
  # over two samples, so the shape keeps no harmonic past the Nyquist to fold back down as the
  # inharmonic whistle a naive saw leaves. `phase` runs 0 to 1; `step` is how far it moves a sample.
  def self.blep(phase, step)
    rising = phase / step
    falling = (phase - 1.0) / step
    return (rising + rising) - (rising * rising) - 1.0 if phase < step

    return (falling * falling) + (falling + falling) + 1.0 if phase > 1.0 - step

    0.0
  end

  # A four-pole ladder lowpass: each pole moves toward the one before, the last feeds back.
  # The pole coefficient is x / (1 + x), which needs no exponential in the sample loop.
  class Ladder
    LIMIT = SAMPLE_RATE * 0.45

    def initialize
      @z0 = @z1 = @z2 = @z3 = 0.0
    end

    def process(sample, cutoff, resonance)
      cutoff = 20.0 if cutoff < 20.0
      cutoff = LIMIT if cutoff > LIMIT
      x = TAU * cutoff / SAMPLE_RATE
      g = x / (1.0 + x)
      input = sample - (resonance * 4.0 * @z3)
      input /= (1.0 + (input.abs * 0.5)) # soft limit on the way in, so the resonance rounds off
      @z0 += g * (input - @z0)
      @z1 += g * (@z0 - @z1)
      @z2 += g * (@z1 - @z2)
      @z3 += g * (@z2 - @z3)
    end
  end

  # Detuned saw and pulse oscillators on phase accumulators, a ladder with its own envelope
  # sweeping the cutoff, and an amplitude envelope. Detune is in cents, octaves are integers.
  def self.moog_reader(patch, freq, dur, amp)
    return Reader.empty unless audible?(freq)

    amp_env = patch.fetch("amp")
    filter_env = patch.fetch("filter_env")
    base = patch.fetch("cutoff")
    sweep = patch.fetch("env_amount")
    resonance = patch.fetch("resonance")
    n = ((dur + amp_env[3]) * SAMPLE_RATE).to_i
    waves = patch.fetch("waves").map { |w| WAVES.keys.index(w) or raise KeyError, "no wave #{w}" } # an index into WAVES, whose shapes the loop below writes out
    incs = patch.fetch("waves").each_index.map do |k|
      freq * (2.0**(patch.fetch("octaves")[k] + (patch.fetch("detune")[k] / 1200.0))) / SAMPLE_RATE
    end
    phases = Array.new(waves.size) { |k| k * 0.13 }
    wave_count = waves.size
    ladder = Ladder.new
    drive = patch.fetch("drive", 1.0)
    scale = amp * 2.0 / waves.size
    Reader.new(n) do |i|
      t = i.to_f / SAMPLE_RATE
      sum = 0.0
      k = 0
      while k < wave_count
        p = phases[k]
        dt = incs[k]
        sum += case waves[k]
               when 0 then (2.0 * p) - 1.0 - blep(p, dt)
               when 1 then (p < 0.5 ? 1.0 : -1.0) + blep(p, dt) - blep((p + 0.5) % 1.0, dt)
               when 2 then p < 0.5 ? (4.0 * p) - 1.0 : 3.0 - (4.0 * p)
               else Math.sin(TAU * p)
               end
        phases[k] = (p + incs[k]) % 1.0
        k += 1
      end
      ladder.process(sum * drive * 0.5, base + (sweep * adsr(filter_env, t, dur)), resonance) * adsr(amp_env, t, dur) * scale
    end
  end

  # An electric piano by frequency modulation: a body pair near 1:1 for the mellow tine, a
  # bell pair at 14:1 whose index falls away in a few tenths of a second, a soft hammer click,
  # and a velocity that brightens it. No tremolo and no chorus: nothing moves but the decay.
  def self.rhodes_reader(patch, freq, dur, amp, velocity)
    return Reader.empty unless audible?(freq)

    release = patch.fetch("release")
    n = ((dur + release) * SAMPLE_RATE).to_i
    bright = 0.5 + (patch.fetch("velocity_bright") * velocity)
    body = patch.fetch("body_index") * bright
    bell = patch.fetch("bell_index") * bright
    bell_ratio = patch.fetch("bell_ratio")
    bell_k = Math.exp(-1.0 / (patch.fetch("bell_decay") * SAMPLE_RATE))
    body_k = Math.exp(-1.0 / (patch.fetch("body_decay") * SAMPLE_RATE))
    amp_k = Math.exp(-1.0 / (patch.fetch("decay") * SAMPLE_RATE))
    click_k = Math.exp(-1.0 / (0.003 * SAMPLE_RATE))
    rng = Random.new(freq.to_i)
    out_k = Math.exp(-1.0 / (release * SAMPLE_RATE / 4.0))
    carrier = modulator = bell_c = bell_m = 0.0
    body_env = bell_env = amp_env = click_env = hold = 1.0
    cinc = freq / SAMPLE_RATE
    gate_n = (dur * SAMPLE_RATE).to_i
    Reader.new(n) do |i|
      m = Math.sin(TAU * modulator)
      b = Math.sin(TAU * bell_m)
      s = Math.sin(TAU * (carrier + (body * body_env * m / TAU))) * 0.8
      s += Math.sin(TAU * (bell_c + (bell * bell_env * b / TAU))) * 0.12 * bell_env
      s += ((rng.rand * 2) - 1) * click_env * patch.fetch("click")
      carrier = (carrier + cinc) % 1.0
      modulator = (modulator + cinc) % 1.0
      bell_c = (bell_c + cinc) % 1.0
      bell_m = (bell_m + (cinc * bell_ratio)) % 1.0
      body_env *= body_k
      bell_env *= bell_k
      click_env *= click_k
      amp_env *= amp_k
      hold *= out_k if i >= gate_n
      s * amp_env * hold * amp * 1.4
    end
  end

  # One hit of a drum-synth voice: a triangle oscillator frequency-modulates a square, both
  # fall in pitch, noise is mixed in, a ladder lowpass and the amplifier each decay. The
  # exponentials are running products, one multiply a sample.
  def self.dfam(patch, freq, dur, amp, decay)
    return [] unless audible?(freq)

    n = [(decay * 4 * SAMPLE_RATE).to_i, (dur * SAMPLE_RATE).to_i].max
    env = patch.fetch("pitch_env")
    pe_k = Math.exp(-1.0 / (env.fetch("seconds") * SAMPLE_RATE))
    ve_k = Math.exp(-1.0 / (decay * SAMPLE_RATE))
    fe_k = Math.exp(-1.0 / (patch.fetch("vcf_decay") * SAMPLE_RATE))
    mix = patch.fetch("mix")
    rng = Random.new(freq.to_i)
    ladder = Ladder.new
    p1 = p2 = 0.0
    pe = ve = fe = 1.0
    Array.new(n) do
      f1 = freq * (1.0 + (env.fetch("depth") * pe))
      tri = WAVES["triangle"].call(p1)
      f2 = f1 * patch.fetch("vco2_ratio") * (1.0 + (patch.fetch("fm") * tri))
      sq = p2 < 0.5 ? 1.0 : -1.0
      p1 = (p1 + (f1 / SAMPLE_RATE)) % 1.0
      p2 = (p2 + (f2 / SAMPLE_RATE)) % 1.0
      src = (tri * mix.fetch("triangle")) + (sq * mix.fetch("square")) + (((rng.rand * 2) - 1) * mix.fetch("noise"))
      cutoff = patch.fetch("cutoff_floor") + (patch.fetch("cutoff") * fe)
      out = ladder.process(src, cutoff, patch.fetch("resonance")) * ve * amp * 2.0
      pe *= pe_k
      ve *= ve_k
      fe *= fe_k
      out
    end
  end

  # A bank of sine partials on a pattern gate, the bubbling organ of dub. The gate is a row of
  # steps, each one cell long, switched by the grid and not by an oscillator: a cell is `x` for
  # open and anything else for shut, and a one-pole slew of a few milliseconds keeps the
  # edges from clicking. `step` is a sixteenth of the tempo in seconds.
  def self.gated_reader(patch, freq, dur, amp, step)
    return Reader.empty unless audible?(freq)

    envelope = patch.fetch("amp")
    pattern = patch.fetch("pattern")
    cell = (step || 0.125) * patch.fetch("cell_steps", 1)
    slew = 1.0 - Math.exp(-1.0 / (patch.fetch("slew", 0.004) * SAMPLE_RATE))
    parts = patch.fetch("partials").filter_map { |ratio, weight| [freq * ratio / SAMPLE_RATE, weight] if audible?(freq * ratio) }
    phases = Array.new(parts.size, 0.0)
    total = parts.sum { |_, weight| weight }
    n = ((dur + envelope[3]) * SAMPLE_RATE).to_i
    open = 0.0
    Reader.new(n) do |i|
      t = i.to_f / SAMPLE_RATE
      open += slew * ((pattern[(t / cell).floor % pattern.size] == "x" ? 1.0 : 0.0) - open)
      sum = 0.0
      parts.each_index do |k|
        sum += parts[k][1] * Math.sin(TAU * phases[k])
        phases[k] = (phases[k] + parts[k][0]) % 1.0
      end
      sum / total * open * adsr(envelope, t, dur) * amp
    end
  end

  # A pipe organ by addition: one sine for each rank of the registration, at the rank's ratio to
  # the played pitch (sixteen foot 0.5, eight foot 1, four foot 2, two and two thirds 3, two 4,
  # the mixture's ranks 6 and 8), and a chiff of about fifteen milliseconds, a burst of noise
  # that dies away as the pipe speaks. Nothing moves afterwards: there is no tremulant. The
  # `registration` is a row of weights for the ratios, else the voice's first.
  def self.organ_reader(patch, freq, dur, amp, registration)
    return Reader.empty unless audible?(freq)

    ratios = patch.fetch("ratios")
    weights = registration || patch.fetch("registrations").values.first
    ranks = ratios.each_index.filter_map { |k| [freq * ratios[k] / SAMPLE_RATE, weights[k]] if weights[k].to_f.positive? && audible?(freq * ratios[k]) }
    envelope = patch.fetch("amp")
    total = ranks.sum { |_, weight| weight }
    phases = Array.new(ranks.size, 0.0)
    n = ((dur + envelope[3]) * SAMPLE_RATE).to_i
    chiff = patch.fetch("chiff")
    chiff_k = Math.exp(-1.0 / (chiff.fetch("seconds") * SAMPLE_RATE / 3.0))
    chiff_env = chiff.fetch("level")
    rng = Random.new(freq.to_i)
    soft = 0.0
    Reader.new(n) do |i|
      t = i.to_f / SAMPLE_RATE
      sum = 0.0
      ranks.each_index do |k|
        sum += ranks[k][1] * Math.sin(TAU * phases[k])
        phases[k] = (phases[k] + ranks[k][0]) % 1.0
      end
      soft += 0.35 * (((rng.rand * 2) - 1) - soft)
      sample = ((sum / total) + (soft * chiff_env)) * adsr(envelope, t, dur) * amp
      chiff_env *= chiff_k
      sample
    end
  end

  # A plucked string, by Karplus-Strong: a burst of noise circulates in a delay line the length of one
  # period, and each trip round the loop averages neighbouring samples, so the highs die first, as on
  # a real string. `pick` is how bright the burst is (a nail against a thumb), `sustain` the
  # seconds the note takes to fall 60 dB, and `tone` a lowpass
  # standing in for the body and the pickup. A first-order allpass tunes the loop to the fraction of a
  # sample the averaging would otherwise leave flat. The burst is seeded from the pitch, so a note is
  # the same note each time it is struck.
  def self.string(patch, freq, dur, amp)
    return [] unless audible?(freq)

    release = patch.fetch("release", 0.12)
    n = ((dur + release) * SAMPLE_RATE).to_i
    # The two-point average reads the newest sample too, so it delays by half a sample less than the line is long.
    delay = (SAMPLE_RATE / freq) + 0.5
    whole = delay.floor
    return [] if whole < 2

    frac = delay - whole
    coef = (1.0 - frac) / (1.0 + frac)
    loop_gain = 10.0**(-3.0 / (freq * patch.fetch("sustain", 2.0)))
    rng = Random.new(freq.round)
    pick = patch.fetch("pick", 0.7).clamp(0.05, 1.0)
    previous = 0.0
    line = Array.new(whole) { previous += pick * (((rng.rand * 2.0) - 1.0) - previous) }
    mean = line.sum / line.size
    line.map! { |x| x - mean }
    pos = 0
    ap_in = ap_out = 0.0
    low = 0.0
    k = 1.0 - Math.exp(-TAU * patch.fetch("tone", 5000.0) / SAMPLE_RATE)
    tail = (release * SAMPLE_RATE).to_i
    Array.new(n) do |i|
      head = line[pos]
      averaged = loop_gain * 0.5 * (head + line[(pos + 1) % whole])
      tuned = (coef * (averaged - ap_out)) + ap_in
      ap_in = averaged
      ap_out = tuned
      line[pos] = tuned
      pos = (pos + 1) % whole
      low += k * (head - low)
      fade = i < n - tail ? 1.0 : (n - i).fdiv(tail)
      low * amp * 1.5 * fade
    end
  end

  # One note of the named voice as a Reader. `decay` is the drum voice's own, per step; `step` is
  # a sixteenth of the tempo in seconds and `registration` the organ's weights. The voices that
  # cost the most (moog, rhodes, gated, organ) are read a block at a time; the rest are cheap and
  # are made whole and handed out in blocks.
  def self.reader(spec, midi, dur, amp, velocity: 1.0, detune: 0.0, decay: nil, step: nil, registration: nil)
    freq = Chords.hz(midi)
    amp *= 10.0**(spec.fetch("gain", 0.0) / 20.0)
    case spec.fetch("family")
    when "pure" then Reader.of(Synth.pure_note(freq, dur, amp:, release: spec.fetch("release", 0.12), attack: spec.fetch("attack", 0.008)))
    when "sine" then Reader.of(audible?(freq) ? Synth.note(freq, dur, detune:, amp:, release: dur * 0.5) : [])
    when "moog" then moog_reader(spec, freq, dur, amp)
    when "rhodes" then rhodes_reader(spec, freq, dur, amp, velocity)
    when "dfam" then Reader.of(dfam(spec, freq, dur, amp, decay || spec.fetch("decay", 0.12)))
    when "string" then Reader.of(string(spec, freq, dur, amp))
    when "gated" then gated_reader(spec, freq, dur, amp, step)
    when "organ" then organ_reader(spec, freq, dur, amp, registration)
    when "fluid" then raise ArgumentError, "voice #{spec['name'].inspect} is a soundfont voice: the sequencer mixes it, a single note cannot"
    else raise ArgumentError, "no voice family #{spec['family'].inspect}"
    end
  end

  # The samples for one note, whole.
  def self.note(spec, midi, dur, amp, **) = reader(spec, midi, dur, amp, **).drain

  CACHE_BELOW = 0.9 # seconds: a short note is made once and handed out again
  CACHE_LIMIT = 600
  @cache = {}

  # A note as a Reader, from the cache when the same note has sounded before. An arpeggio or a
  # chord repeated strikes the same few notes over and over, and a voice is deterministic, so the
  # samples are the same each time; a long note is read as it goes and not kept.
  def self.cached_reader(spec, midi, dur, amp, **options)
    return reader(spec, midi, dur, amp, **options) if dur >= CACHE_BELOW

    key = [spec, midi, dur, amp, options]
    samples = @cache[key] ||= begin
      @cache.shift if @cache.size >= CACHE_LIMIT
      reader(spec, midi, dur, amp, **options).drain
    end
    Reader.of(samples)
  end
end

# --- colour.rb ---
# ------------------------------------------------------------- colour chains
# Sonitex and nasty_vcs, as chains rather than plugins. Sonitex is the 12-bit sampler
# lineage: a drive into a hard band limit, bit and rate reduction, a little hiss and dust,
# a compressor and a limiter. One instance is a colour and three are a sound. nasty_vcs is a
# summing colour, applied wherever things are added, which is what a console does and why
# summed material glues. Both are off unless asked for, and then they only colour.
module Colour
  def self.db(x) = 10.0**(x / 20.0)

  def self.highpass(buf, cutoff) = Stream::Highpass.new(cutoff).process(buf)

  # A feed-forward compressor: the level follows the signal, over the threshold the gain falls.
  def self.compress(buf, threshold, ratio, attack_ms, release_ms, makeup) = Stream::Compressor.new(threshold, ratio, attack_ms, release_ms, makeup).process(buf)

  # Sample-rate reduction by `factor` (hold each value) and rounding to `bits` of resolution.
  def self.crush(buf, bits, factor) = Stream::Crush.new(bits, factor).process(buf)

  # Samples under 0.7 pass untouched; above it the level bends toward 1 and never reaches it,
  # so a loud kick stays loud instead of pulling the whole mix down.
  def self.soft_limit(v)
    a = v.abs
    return v if a <= 0.7

    (0.7 + (0.3 * Math.tanh((a - 0.7) / 0.3))) * (v.negative? ? -1 : 1)
  end

  # The passes share one random stream, one after another over the whole signal; the streamed
  # render gives each its own so that blocks of a signal cannot change the draws.
  def self.sonitex(buf, preset, instances, seed)
    rng = Random.new(seed)
    instances.clamp(1, 3).times.inject(buf) { |out, _| Stream::Sonitex.new(preset, rng).process(out) }
  end

  # A heavy but static tape stage for drum buses: input bandwidth, a restrained head bump,
  # saturation and compression. No wow, flutter, tremolo, chorus or other pitch modulation.
  def self.tape(buf, amount: 1.0)
    amount = amount.to_f.clamp(0.0, 1.0)
    return buf if amount.zero? || buf.empty?

    pre = FX.lowpass(buf, 14_000.0)
    low = FX.lowpass(pre, 82.0)
    drive = 1.0 + (3.2 * amount)
    wet_share = 0.72 * amount
    curve = Math.tanh(drive)
    out = pre.each_index.map do |i|
      pushed = pre[i] + (low[i] * 0.10 * amount)
      saturated = Math.tanh(pushed * drive) / curve
      (pre[i] * (1.0 - wet_share)) + (saturated * wet_share)
    end
    out = highpass(out, 26.0)
    compress(out, -15.0, 2.8, 7.0, 85.0, 0.0)
  end

  # The summing colour: a soft knee that bends only the peaks, a touch of low warmth, and
  # unity gain for small signals, so summed material glues without getting louder.
  def self.vcs(buf, amount) = amount.to_f <= 0.0 ? buf : Stream::Vcs.new(amount).process(buf)
end

# --- tape.rb ---
# ------------------------------------------------------------------- tape
# The last colour before the file. One instance is a tape machine reduced to what is static in
# it: a Jiles-Atherton hysteresis loop for the medium (the output depends on whether the signal
# is rising or falling into a level, which a waveshaper cannot reproduce), a head bump near fifty
# hertz and the loss at the top. Nothing moves: no wow, no flutter, no hiss. Further instances
# use an arctangent curve in place of the loop, which costs a fraction of it, and each is level
# matched against its own measurement of a reference signal, so a stack changes colour and not
# loudness. Every stage keeps its state between calls, so a signal cut into chunks leaves the
# stack exactly as one long call does.
module Tape
  TAU = 2 * Math::PI
  REFERENCE_TONES = [110.0, 440.0, 1760.0].freeze # whole cycles in 0.2 s: Goertzel bins land exactly

  # Amplitude of one frequency in a signal, by the Goertzel recurrence.
  def self.goertzel(samples, freq)
    coeff = 2.0 * Math.cos(TAU * freq / SAMPLE_RATE)
    s1 = s2 = 0.0
    samples.each do |x|
      s0 = x + (coeff * s1) - s2
      s2 = s1
      s1 = s0
    end
    power = (s1 * s1) + (s2 * s2) - (coeff * s1 * s2)
    2.0 * Math.sqrt([power, 0.0].max) / samples.size
  end

  def self.rms(samples) = samples.empty? ? 0.0 : Math.sqrt(samples.sum { |x| x * x } / samples.size)

  def self.db(ratio) = 20.0 * Math.log10([ratio, 1e-12].max)

  # A second-order section in transposed direct form II (the RBJ cookbook shapes).
  class Biquad
    def self.peaking(hz, q, gain_db)
      a = 10.0**(gain_db / 40.0)
      w = TAU * hz / SAMPLE_RATE
      alpha = Math.sin(w) / (2.0 * q)
      cos = Math.cos(w)
      new([1 + (alpha * a), -2 * cos, 1 - (alpha * a)], [1 + (alpha / a), -2 * cos, 1 - (alpha / a)])
    end

    def self.lowpass(hz, q = Math.sqrt(0.5))
      w = TAU * hz / SAMPLE_RATE
      alpha = Math.sin(w) / (2.0 * q)
      cos = Math.cos(w)
      new([(1 - cos) / 2, 1 - cos, (1 - cos) / 2], [1 + alpha, -2 * cos, 1 - alpha])
    end

    # A shelf that lifts everything above `hz` by `gain_db` (RBJ, slope 1).
    def self.highshelf(hz, gain_db, slope = 1.0)
      a = 10.0**(gain_db / 40.0)
      w = TAU * hz / SAMPLE_RATE
      cos = Math.cos(w)
      alpha = Math.sin(w) / 2.0 * Math.sqrt(((a + (1.0 / a)) * ((1.0 / slope) - 1.0)) + 2.0)
      root = 2.0 * Math.sqrt(a) * alpha
      new([a * ((a + 1) + ((a - 1) * cos) + root), -2.0 * a * ((a - 1) + ((a + 1) * cos)), a * ((a + 1) + ((a - 1) * cos) - root)],
          [(a + 1) - ((a - 1) * cos) + root, 2.0 * ((a - 1) - ((a + 1) * cos)), (a + 1) - ((a - 1) * cos) - root])
    end

    # A resonator with unity gain at its centre (the constant peak form).
    def self.bandpass(hz, q)
      w = TAU * hz / SAMPLE_RATE
      alpha = Math.sin(w) / (2.0 * q)
      cos = Math.cos(w)
      new([alpha, 0.0, -alpha], [1 + alpha, -2 * cos, 1 - alpha])
    end

    def self.highpass(hz, q = Math.sqrt(0.5))
      w = TAU * hz / SAMPLE_RATE
      alpha = Math.sin(w) / (2.0 * q)
      cos = Math.cos(w)
      new([(1 + cos) / 2, -(1 + cos), (1 + cos) / 2], [1 + alpha, -2 * cos, 1 - alpha])
    end

    def initialize(b, a)
      @b0 = b[0] / a[0]
      @b1 = b[1] / a[0]
      @b2 = b[2] / a[0]
      @a1 = a[1] / a[0]
      @a2 = a[2] / a[0]
      @z1 = @z2 = 0.0
    end

    def step(x)
      y = (@b0 * x) + @z1
      @z1 = (@b1 * x) - (@a1 * y) + @z2
      @z2 = (@b2 * x) - (@a2 * y)
      y
    end

    def reset
      @z1 = @z2 = 0.0
    end

    def process(buf) = buf.map { |x| step(x) }
  end

  # The magnetisation of the medium as the signal drives it. Ms is the saturation level, a the
  # shape of the anhysteretic curve, alpha the coupling between domains, k the width of the
  # loop and c the share that bends back without loss. Solved with Runge-Kutta over each sample.
  class Hysteresis
    DEFAULTS = { "ms" => 1.0, "a" => 0.22, "alpha" => 1.6e-3, "k" => 0.47, "c" => 0.17 }.freeze

    def initialize(params = {})
      p = DEFAULTS.merge(params)
      @ms = p["ms"].to_f
      @a = p["a"].to_f
      @alpha = p["alpha"].to_f
      @k = p["k"].to_f
      @c = p["c"].to_f
      @m = 0.0
      @h = 0.0
    end

# dM/dH at one point; the sign of dh is the direction of travel. The Langevin function and
# its slope share one exponential: coth(x) - 1/x and 1/x^2 - 1/sinh(x)^2, which near zero
# lose all their digits and are taken from their series instead.
def slope(m, h, dh)
  q = (h + (@alpha * m)) / @a
  if q.abs < 1e-4
    langevin = q / 3.0
    prime = 1.0 / 3.0
  else
    q = q.clamp(-40.0, 40.0)
    e = Math.exp(q)
    inv = 1.0 / e
    sinh2 = e - inv
    langevin = ((e + inv) / sinh2) - (1.0 / q)
    prime = (1.0 / (q * q)) - (4.0 / (sinh2 * sinh2))
  end
  dm = (@ms * langevin) - m
  reach = dh.negative? ? -@k : @k
  denom = reach - (@alpha * dm)
  denom = reach if denom.abs < 1e-9
  ((1.0 - @c) * (dm / denom)) + (@c * (@ms / @a) * prime)
end

    def step(field)
      dh = field - @h
      k1 = slope(@m, @h, dh)
      k2 = slope(@m + (0.5 * k1 * dh), @h + (0.5 * dh), dh)
      k3 = slope(@m + (0.5 * k2 * dh), @h + (0.5 * dh), dh)
      k4 = slope(@m + (k3 * dh), field, dh)
      @m += (dh / 6.0) * (k1 + (2.0 * k2) + (2.0 * k3) + k4)
      @h = field
      @m
    end
  end

  # One machine: the medium, then the playback head's bump and the loss at the top.
  class Machine
    attr_reader :makeup
    attr_accessor :scale # a live move on the drive, 1.0 when at rest

    # `curve` is :loop for the hysteresis model or :atan for the cheap curve; `reference` is the
    # RMS of the signal the makeup gain is measured at.
    def initialize(drive:, curve:, config:, rng:, reference:, sample: nil)
      @drive = drive
      @scale = 1.0
      @curve = curve
      jitter = ->(share) { 1.0 + (share * ((rng.rand * 2) - 1)) } # each instance is a slightly different machine
      loop_params = (config["hysteresis"] || {}).dup
      loop_params["k"] = loop_params.fetch("k", Hysteresis::DEFAULTS["k"]) * jitter.call(0.04)
      @params = loop_params
      @field = curve == :loop ? config.fetch("field_scale", 0.4) : config.fetch("cheap_field", 1.2)
      @bump = Biquad.peaking(config.fetch("bump_hz", 50.0) * jitter.call(0.06), config.fetch("bump_q", 1.1), config.fetch("bump_db", 1.5))
      @top = Biquad.lowpass(config.fetch("hf_hz", 16_500.0) * jitter.call(0.03))
      @block = Biquad.highpass(config.fetch("block_hz", 18.0))
      @loop = Hysteresis.new(@params) if curve == :loop
      @makeup = 1.0
      @makeup = sample ? calibrate_on(sample) : calibrate(reference)
      reset
    end

    def reset
      @loop = Hysteresis.new(@params) if @curve == :loop
      [@bump, @top, @block].each(&:reset)
    end

    def process(buf)
      gain = @drive * @scale * @field
      if @curve == :loop
        buf.map { |x| @block.step(@top.step(@bump.step(@loop.step(x * gain)))) * @makeup }
      else
        norm = 1.0 / gain
        buf.map { |x| @block.step(@top.step(@bump.step(Math.atan(x * gain) * norm))) * @makeup }
      end
    end

    private

    # Gain that returns a stretch of the programme itself to its own RMS, measured after the
    # loop has settled. The tones below suit a stack with no programme to hand.
    def calibrate_on(sample)
      settle = (0.1 * SAMPLE_RATE).round
      heard = Tape.rms(process(sample).drop(settle))
      reset
      heard.positive? ? Tape.rms(sample.drop(settle)) / heard : 1.0
    end

    # Gain that returns a reference signal (three tones at the given RMS) to its own level,
    # measured by Goertzel on the fundamentals after the loop has settled.
    def calibrate(reference)
      amp = reference * Math.sqrt(2.0 / REFERENCE_TONES.size)
      total = (0.3 * SAMPLE_RATE).round
      signal = Array.new(total) { |i| REFERENCE_TONES.sum { |f| amp * Math.sin(TAU * f * i / SAMPLE_RATE) } }
      out = process(signal).last((0.2 * SAMPLE_RATE).round)
      heard = Math.sqrt(REFERENCE_TONES.sum { |f| Tape.goertzel(out, f)**2 })
      reset
      heard.positive? ? (amp * Math.sqrt(REFERENCE_TONES.size)) / heard : 1.0
    end
  end

  # N machines in series, the first with the loop and the rest on the cheap curve, each driven a
  # step harder than the one before.
  class Stack
    attr_reader :machines

    # `sample` is a stretch of the programme to level match against; without one the stack is
    # matched on three reference tones at `config['reference']` RMS.
    def initialize(instances:, drive: 1.0, seed: 0, config: {}, sample: nil, cheap: false)
      heard = sample
      @machines = Array.new(instances) do |i|
        step = 1.0 + (config.fetch("drive_step", 0.15) * i)
        machine = Machine.new(drive: drive * step, curve: i.zero? && !cheap ? :loop : :atan, config:, sample: heard,
                              rng: Random.new(Zlib.crc32("#{seed}:tape:#{i}")), reference: config.fetch("reference", 0.12))
        heard = machine.process(heard) if heard
        machine.reset
        machine
      end
    end

    def process(buf) = @machines.reduce(buf) { |signal, machine| machine.process(signal) }

    # Push every machine's drive by a factor (a live move), 1.0 putting it back.
    def drive_scale=(factor)
      @machines.each { |machine| machine.scale = factor }
    end
  end

  # A soft ceiling, the last thing the signal meets: below the knee nothing changes, above it
  # the level bends toward the ceiling and never reaches it.
  def self.ceiling(buf, knee: 0.8, top: 0.97)
    room = top - knee
    buf.map do |v|
      a = v.abs
      a <= knee ? v : (knee + (room * Math.tanh((a - knee) / room))) * (v.negative? ? -1.0 : 1.0)
    end
  end

  # Up to three stretches of the programme, from its start, middle and end, for the level match.
  def self.excerpt(buf, seconds: 0.8)
    len = (seconds * SAMPLE_RATE).round
    return buf if buf.size <= len * 3

    [0, (buf.size - len) / 2, buf.size - len].flat_map { |from| buf[from, len] }
  end

  # The whole stage on a finished signal. Zero instances is the signal itself, untouched.
  def self.apply(buf, instances:, drive: 1.0, seed: 0, config: {})
    return buf if instances.to_i <= 0 || buf.empty?

    ceiling(Stack.new(instances: instances.to_i, drive:, seed:, config:, sample: excerpt(buf)).process(buf),
            top: config.fetch("ceiling", 0.97))
  end
end

# --- mastering.rb ---
# --------------------------------------------------------------- mastering
# The last stages before the tape stack, in the order a console has them: tone, then dynamics,
# then level, with the limiter after the tape. Every stage works on a frame, [mono] or
# [left, right], keeps its state between blocks, and gives the same samples however the signal is cut.
#
#   EQ              a cut in the low mids and a shelf of air, and a dynamic cut that deepens when
#                   the low mids build up
#   multiband       three bands split by Linkwitz-Riley crossovers, each compressed, the detector
#                   linked between the channels
#   parallel        a hard compressed copy mixed under the dry signal, the New York way
#   glue            a gentle bus compressor whose release is half a beat of the tempo
#   loudness        a gain to the target level in LUFS, measured with K-weighting and gating
#   soft clip       the peaks bent before the limiter sees them
#   (the tape stack)
#   limiter         look-ahead, with the peak found on a four times oversampled signal, so the
#                   ceiling holds in dB true peak and not only in samples
module Mastering
  def self.db(x) = 10.0**(x / 20.0)

  def self.to_db(ratio) = 20.0 * Math.log10([ratio, 1e-12].max)

  # ------------------------------------------------------------------ loudness
  module Loudness
    HOP = (0.1 * SAMPLE_RATE).round # a 400 ms block every 100 ms

    # The K-weighting of ITU-R BS.1770: a high shelf of +4 dB near 1.7 kHz, then a highpass at 38 Hz.
    def self.k_weighting
      shelf = begin
        k = Math.tan(Math::PI * 1681.974450955533 / SAMPLE_RATE)
        q = 0.7071752369554196
        vh = 10.0**(3.999843853973347 / 20.0)
        vb = vh**0.4996667741545416
        a0 = 1.0 + (k / q) + (k * k)
        Tape::Biquad.new([(vh + (vb * k / q) + (k * k)) / a0, 2.0 * ((k * k) - vh) / a0, (vh - (vb * k / q) + (k * k)) / a0],
                         [1.0, 2.0 * ((k * k) - 1.0) / a0, (1.0 - (k / q) + (k * k)) / a0])
      end
      high = begin
        k = Math.tan(Math::PI * 38.13547087602444 / SAMPLE_RATE)
        q = 0.5003270373238773
        a0 = 1.0 + (k / q) + (k * k)
        Tape::Biquad.new([1.0, -2.0, 1.0], [a0, 2.0 * ((k * k) - 1.0), 1.0 - (k / q) + (k * k)])
      end
      [shelf, high]
    end

    # A running meter: feed it frames, ask for the momentary or integrated loudness.
    class Meter
      def initialize(channels)
        @filters = Array.new(channels) { Loudness.k_weighting }
        @sums = Array.new(channels, 0.0)
        @held = 0
        @hops = [] # mean square summed over the channels, for each hop
      end

      # The mean square of every hundred milliseconds, closed exactly on the hop, whatever the size of the frame.
      def feed(frame)
        count = frame.first.size
        at = 0
        while at < count
          take = [HOP - @held, count - at].min
          frame.each_with_index do |channel, c|
            shelf, high = @filters[c]
            sum = @sums[c]
            channel[at, take].each { |x| y = high.step(shelf.step(x)); sum += y * y }
            @sums[c] = sum
          end
          @held += take
          at += take
          next if @held < HOP

          @hops << (@sums.sum / HOP)
          @sums.fill(0.0)
          @held = 0
        end
      end

      def blocks = @hops.each_cons(4).map { |four| four.sum / 4.0 }

      def self.lufs(energy) = energy.positive? ? -0.691 + (10.0 * Math.log10(energy)) : -Float::INFINITY

      def momentary = blocks.last ? Meter.lufs(blocks.last) : -Float::INFINITY

      # Integrated loudness: blocks above -70 LUFS, then above ten below the mean of those.
      def integrated
        loud = blocks.select { |e| Meter.lufs(e) > -70.0 }
        return -Float::INFINITY if loud.empty?

        floor = Meter.lufs(loud.sum / loud.size) - 10.0
        kept = loud.select { |e| Meter.lufs(e) > floor }
        kept.empty? ? -Float::INFINITY : Meter.lufs(kept.sum / kept.size)
      end
    end

    # The integrated loudness of a whole frame.
    def self.integrated(frame)
      meter = Meter.new(frame.size)
      meter.feed(frame)
      meter.integrated
    end
  end

  # ----------------------------------------------------------------- true peak
  module TruePeak
    HALF = 8

    # Windowed-sinc weights for the point `offset` of a sample step past a sample.
    def self.weights(offset)
      (-HALF + 1..HALF).map do |k|
        x = k - offset
        sinc = x.zero? ? 1.0 : Math.sin(Math::PI * x) / (Math::PI * x)
        sinc * (0.5 + (0.5 * Math.cos(Math::PI * x / (HALF + 1))))
      end
    end

    PHASES = [0.25, 0.5, 0.75].map { |o| weights(o) }.freeze

    # The highest value the signal reaches between samples, found on a four times oversampled
    # signal, looking only near the samples that are already high.
    def self.peak(samples)
      top = samples.map(&:abs).max.to_f
      return top if top.zero?

      limit = top * 0.5
      best = top
      # the ends of the array are left out: past them the signal is taken to be zero, and a sinc rings on the edge
      (HALF...(samples.size - HALF)).each do |i|
        next if samples[i].abs < limit && samples[i + 1].abs < limit

        PHASES.each do |weights|
          sum = 0.0
          weights.each_with_index { |w, j| sum += w * samples[i + j - HALF + 1] }
          best = sum.abs if sum.abs > best
        end
      end
      best
    end

    def self.db(frame) = Mastering.to_db(frame.map { |channel| peak(channel) }.max)
  end

  # --------------------------------------------------------------- the limiter
  # Look-ahead, linked between the channels. The peak of each sample is the highest of the sample
  # and of three points between it and the next, found with an eight-tap windowed sinc, which is the
  # signal as a converter will draw it. The gain that needs is spread over the look-ahead by taking
  # the lowest need in the window and averaging that over the window, so the gain is already down when
  # the peak arrives and never steps. It comes back up at the release time.
  class Limiter
    TAPS = 8
    LEAD = 4 # samples of the signal ahead of the one whose peak is being found
    PHASES = [0.25, 0.5, 0.75].map do |offset|
      Array.new(TAPS) do |j|
        x = (j - (LEAD - 1)) - offset
        sinc = x.zero? ? 1.0 : Math.sin(Math::PI * x) / (Math::PI * x)
        sinc * (0.5 + (0.5 * Math.cos(Math::PI * x / (LEAD + 1))))
      end
    end.freeze

    attr_reader :latency

    def initialize(ceiling_db: -1.0, lookahead: 64, release_ms: 120.0, channels: 2)
      @ceiling = Mastering.db(ceiling_db) * 0.995 # a margin for what eight taps miss
      @look = lookahead
      @channels = channels
      @latency = lookahead - 1 + LEAD
      @history = Array.new(channels) { Array.new(TAPS, 0.0) }
      @delay = Array.new(channels) { Array.new(@latency + 1, 0.0) }
      @deque = []
      @mins = Array.new(lookahead, 1.0)
      @mins_sum = lookahead.to_f
      @release = 1.0 - Math.exp(-1.0 / (release_ms / 1000.0 * SAMPLE_RATE))
      @env = 1.0
      @n = 0
    end

    def process(frame)
      count = frame.first.size
      out = Array.new(@channels) { Array.new(count, 0.0) }
      size = @delay.first.size
      count.times do |i|
        peak = 0.0
        @channels.times do |c|
          h = @history[c]
          h.shift
          h << frame[c][i]
          @delay[c][@n % size] = h[LEAD - 1]
          here = h[LEAD - 1].abs
          there = h[LEAD].abs
          peak = here if here > peak
          peak = [peak, between(h)].max if (here > @ceiling * 0.5 || there > @ceiling * 0.5) && (here + there) > 0.0
        end
        need = peak > @ceiling ? @ceiling / peak : 1.0
        slot = @n % @look
        # the lowest need of the last `look` samples, by a deque of the ones that could still be the lowest
        @deque.pop while !@deque.empty? && @deque.last[0] >= need
        @deque << [need, @n]
        @deque.shift while @deque.first[1] <= @n - @look
        window_min = @deque.first[0]
        @mins_sum += window_min - @mins[slot]
        @mins[slot] = window_min
        smooth = @mins_sum / @look
        @env = smooth < @env ? smooth : @env + ((smooth - @env) * @release)
        gain = [@env, smooth].min
        back = (@n - (@look - 1)) % size
        @channels.times { |c| out[c][i] = @delay[c][back] * gain }
        @n += 1
      end
      out
    end

    private

    # The highest of the three points between h[LEAD - 1] and the next sample.
    def between(h)
      best = 0.0
      PHASES.each do |weights|
        sum = 0.0
        TAPS.times { |j| sum += weights[j] * h[j] }
        best = sum.abs if sum.abs > best
      end
      best
    end
  end

  # ----------------------------------------------------------------- dynamics
  # A compressor whose detector is the highest level of any channel, so both are turned down by the
  # same amount and the image stays where it is. `apply` returns the frame and leaves the
  # state for the next block.
  class Compressor
    def initialize(threshold_db:, ratio:, attack_ms:, release_ms:, makeup_db: 0.0)
      @limit = Mastering.db(threshold_db)
      @slope = 1.0 - (1.0 / ratio)
      @up = 1.0 - Math.exp(-1.0 / (attack_ms / 1000.0 * SAMPLE_RATE))
      @down = 1.0 - Math.exp(-1.0 / (release_ms / 1000.0 * SAMPLE_RATE))
      @makeup = Mastering.db(makeup_db)
      @level = 0.0
    end

    def release_ms=(ms)
      @down = 1.0 - Math.exp(-1.0 / (ms / 1000.0 * SAMPLE_RATE))
    end

    def apply(frame)
      count = frame.first.size
      gains = Array.new(count) do |i|
        a = 0.0
        frame.each { |channel| v = channel[i].abs; a = v if v > a }
        @level += (a > @level ? @up : @down) * (a - @level)
        (@level > @limit ? (@limit / @level)**@slope : 1.0) * @makeup
      end
      frame.map { |channel| Array.new(count) { |i| channel[i] * gains[i] } }
    end
  end

  # Two Butterworth sections of one kind in series, which is a Linkwitz-Riley filter (24 dB an
  # octave), run in one loop.
  class Cascade
    def initialize(kind, hz)
      @first = Tape::Biquad.public_send(kind, hz)
      @second = Tape::Biquad.public_send(kind, hz)
    end

    def process(buf)
      a = @first
      b = @second
      buf.map { |x| b.step(a.step(x)) }
    end
  end

  # Three bands from two crossovers: a Linkwitz-Riley lowpass takes the lows and what is left
  # (the input less the lows) goes on to the second, which takes the mids from the highs the same
  # way. The three add back to the input exactly. Each band is compressed on its own.
  class Multiband
    def initialize(spec, channels)
      low_hz, high_hz = spec.fetch("crossovers")
      @cuts = Array.new(channels) { [Cascade.new(:lowpass, low_hz), Cascade.new(:lowpass, high_hz)] }
      @bands = spec.fetch("bands").map do |band|
        Compressor.new(threshold_db: band.fetch("threshold_db"), ratio: band.fetch("ratio"), attack_ms: band.fetch("attack_ms"),
                       release_ms: band.fetch("release_ms"), makeup_db: band.fetch("makeup_db", 0.0))
      end
    end

    def process(frame)
      split = frame.each_with_index.map do |channel, c|
        low = @cuts[c][0].process(channel)
        rest = channel.each_index.map { |i| channel[i] - low[i] }
        mid = @cuts[c][1].process(rest)
        [low, mid, rest.each_index.map { |i| rest[i] - mid[i] }]
      end
      bands = Array.new(3) { |b| @bands[b].apply(split.map { |s| s[b] }) }
      frame.each_index.map { |c| Array.new(frame.first.size) { |i| bands[0][c][i] + bands[1][c][i] + bands[2][c][i] } }
    end
  end

  # A cut in the low mids and a shelf of air, both static, and a dynamic cut that follows what the
  # low mids are doing: the more there is, the more of that band is taken out.
  class Equalizer
    def initialize(spec, channels)
      lm = spec.fetch("low_mid")
      air = spec.fetch("air")
      dyn = spec.fetch("dynamic")
      @lowcut = spec["lowcut_hz"]
      @weight_db = spec.dig("low_shelf", "db")
      @weight_hz = spec.dig("low_shelf", "hz")
      @weight_gain = 10.0**(@weight_db / 20.0) if @weight_db
      @chains = Array.new(channels) do
        { cut: Tape::Biquad.peaking(lm.fetch("hz"), lm.fetch("q"), lm.fetch("db")),
          air: Tape::Biquad.highshelf(air.fetch("hz"), air.fetch("db")),
          band: Tape::Biquad.bandpass(lm.fetch("hz"), lm.fetch("q")), **bottom_end }
      end
      @threshold = Mastering.db(dyn.fetch("threshold_db"))
      @range = dyn.fetch("range")
      @level = 0.0
      @up = 1.0 - Math.exp(-1.0 / (0.01 * SAMPLE_RATE))
      @down = 1.0 - Math.exp(-1.0 / (0.15 * SAMPLE_RATE))
    end

    def process(frame)
      count = frame.first.size
      statics = frame.each_with_index.map { |channel, c| channel.map { |x| shape(@chains[c], x) } }
      bands = frame.each_with_index.map { |channel, c| channel.map { |x| @chains[c][:band].step(x) } }
      Array.new(frame.size) do |c|
        Array.new(count) do |i|
          if c.zero?
            a = bands.map { |b| b[i].abs }.max
            @level += (a > @level ? @up : @down) * (a - @level)
          end
          depth = ((@level / @threshold) - 1.0).clamp(0.0, 1.0) * @range
          statics[c][i] - (depth * bands[c][i])
        end
      end
    end

    private

    # What each chain does to a sample before the dynamic cut: the rumble cut, the weight of the
    # bottom octaves, the low-mid cut, the air.
    def shape(chain, sample)
      sample = chain[:rumble].reduce(sample) { |value, section| section.step(value) } if chain[:rumble]
      sample = chain[:weight].step(sample) * @weight_gain if chain[:weight]
      chain[:air].step(chain[:cut].step(sample))
    end

    # Two Butterworth sections, 24 dB an octave: rumble under the lowest note is never music.
    # The weight is a low shelf of `low_shelf.db` at `low_shelf.hz`, built as the same shelf
    # turned over (a high shelf of the opposite sign) and a gain, so one shelf shape serves both.
    def bottom_end
      {
        rumble: @lowcut && Array.new(2) { Tape::Biquad.highpass(@lowcut) },

        weight: @weight_db && Tape::Biquad.highshelf(@weight_hz, -@weight_db),
      }
    end
  end

  # ---------------------------------------------------------------- the chain
  class Chain
    attr_reader :meter, :gain_db

    def initialize(spec, channels:, bpm: 88.0, whole: false)
      @spec = spec
      @channels = channels
      @whole = whole
      @eq = Equalizer.new(spec.fetch("eq"), channels)
      @multiband = Multiband.new(spec.fetch("multiband"), channels)
      par = spec.fetch("parallel")
      @parallel = Compressor.new(threshold_db: par.fetch("threshold_db"), ratio: par.fetch("ratio"), attack_ms: par.fetch("attack_ms"),
                                 release_ms: par.fetch("release_ms"), makeup_db: par.fetch("makeup_db"))
      @parallel_mix = par.fetch("mix")
      glue = spec.fetch("glue")
      @glue = Compressor.new(threshold_db: glue.fetch("threshold_db"), ratio: glue.fetch("ratio"), attack_ms: glue.fetch("attack_ms"),
                             release_ms: 60_000.0 / bpm * glue.fetch("release_beats"), makeup_db: glue.fetch("makeup_db"))
      @glue_beats = glue.fetch("release_beats")
      @target = spec.fetch("target_lufs")
      @meter = Loudness::Meter.new(channels)
      @gain_db = 0.0
      @limiter = Limiter.new(ceiling_db: spec.fetch("ceiling_dbtp"), lookahead: spec.dig("limiter", "lookahead") || 64,
                             release_ms: spec.dig("limiter", "release_ms") || 120.0, channels:)
      @knee = spec.dig("clip", "knee") || 0.7
    end

    def target=(lufs)
      @target = lufs
    end

    # The multiband and the parallel compressor are the dear stages. A show that cannot keep up with
    # the clock drops them and says so; what is left is the EQ, the glue, the level and the limiter.
    def lighten!
      @light = true
    end

    def light? = @light == true

    # The tempo the glue compressor's release follows.
    def bpm=(bpm)
      @glue.release_ms = 60_000.0 / bpm * @glue_beats
    end

    # Tone and dynamics, then the level.
    def process(frame)
      frame = @eq.process(frame)
      unless @light
        frame = @multiband.process(frame)
        dry = frame
        squashed = @parallel.apply(frame)
        frame = dry.each_index.map { |c| Array.new(dry.first.size) { |i| dry[c][i] + (@parallel_mix * squashed[c][i]) } }
      end
      frame = @glue.apply(frame)
      level(frame)
    end

    # The final stage, after the tape: the true-peak limiter.
    def limit(frame) = @limiter.process(frame)

    # The delay of the limiter in samples.
    def latency = @limiter.latency

    # Whole signals are brought to the target at once; a stream creeps toward it, a little every
    # block, from what it has heard so far.
    def level(frame)
      @meter.feed(frame)
      loud = @meter.integrated
      return clip(frame) unless loud.finite?

      want = (@target - loud).clamp(-15.0, 15.0)
      if @whole
        @gain_db = want
      else
        step = frame.first.size.to_f / SAMPLE_RATE * 2.0 # up to 2 dB a second
        @gain_db += (want - @gain_db).clamp(-step, step)
      end
      gain = Mastering.db(@gain_db)
      clip(frame.map { |channel| channel.map { |v| v * gain } })
    end

    private

    def clip(frame) = frame.map { |channel| channel.map { |v| Colour.soft_limit(v) } }
  end

  # ------------------------------------------------------------------- dither
  # TPDF dither of one least significant bit, from a seeded stream, for export to sixteen bits.
  class Dither
    def initialize(seed, bits = 16)
      @rng = Random.new(seed)
      @lsb = 1.0 / (2**(bits - 1))
    end

    def process(frame) = frame.map { |channel| channel.map { |v| v + ((@rng.rand - @rng.rand) * @lsb) } }
  end

  # ------------------------------------------------------------------- report
  # What was made: integrated loudness, true peak, crest factor, and how alike the channels are.
  def self.report(frame)
    mono = Stereo.fold(frame)
    peak = frame.map { |channel| channel.map(&:abs).max }.max
    rms = Math.sqrt(mono.sum { |x| x * x } / mono.size)
    correlation =
      if frame.size == 2
        l, r = frame
        num = l.each_index.sum { |i| l[i] * r[i] }
        den = Math.sqrt(l.sum { |x| x * x } * r.sum { |x| x * x })
        den.zero? ? 1.0 : num / den
      else
        1.0
      end
    { lufs: Loudness.integrated(frame), true_peak_db: TruePeak.db(frame), crest_db: to_db(peak / [rms, 1e-12].max), correlation: }
  end

  def self.report_line(report)
    format("  loudness: %<lufs>.1f LUFS-I, true peak %<tp>.2f dBTP, crest %<crest>.1f dB, correlation %<corr>.2f",
           lufs: report[:lufs], tp: report[:true_peak_db], crest: report[:crest_db], corr: report[:correlation])
  end
end

# A listening pass in numbers, so a take can be chosen by something other than the first draw.
# It scores what a producer hears before anything else: whether the spectrum falls away
# the way warm music does (tape and vinyl roll the top off, about 4.5 dB an octave), whether any
# octave pokes out of that line (mud near 300 Hz, a harsh edge near 4 kHz), whether the dynamics
# breathe and nothing is clipped. Every term is a deviation in decibels, so the score is a number of
# decibels off the target and lower is better. 0 is the target; the terms are printed so the
# reason for a score can be read.
module Critic
  CENTRES = [50, 100, 200, 400, 800, 1600, 3200, 6400].freeze
  SLOPE_DB_PER_OCTAVE = -4.5
  CREST_DB = (9.0..16.0)
  TRUE_PEAK_CEILING_DB = -1.0
  WINDOW_SECONDS = 24 # the middle of a long take; a filter bank over five minutes is minutes of Ruby

  def self.band_levels(mono)
    CENTRES.map do |hz|
      filter = Tape::Biquad.bandpass(hz, Math.sqrt(2.0))
      energy = mono.sum { |x| (y = filter.step(x)) * y } / mono.size
      Mastering.to_db(Math.sqrt([energy, 1e-18].max))
    end
  end

  def self.middle(frame)
    size = frame.first.size
    limit = WINDOW_SECONDS * SAMPLE_RATE
    return frame if size <= limit

    from = (size - limit) / 2
    frame.map { |channel| channel[from, limit] }
  end

  # Slope of the band levels against octave number, by least squares, and the rms of what is left.
  def self.fit(levels)
    xs = levels.each_index.to_a
    mx = xs.sum.fdiv(xs.size)
    my = levels.sum / levels.size
    slope = xs.sum { |x| (x - mx) * (levels[x] - my) } / xs.sum { |x| (x - mx)**2 }
    residual = xs.map { |x| levels[x] - (my + (slope * (x - mx))) }
    [slope, Math.sqrt(residual.sum { |r| r * r } / residual.size), residual]
  end

  def self.measure(frame)
    window = middle(frame)
    levels = band_levels(Stereo.fold(window))
    slope, bumpiness, residual = fit(levels)
    report = Mastering.report(window)
    mud = residual[CENTRES.index(400)] - ((residual[CENTRES.index(200)] + residual[CENTRES.index(800)]) / 2.0)
    edge = residual[CENTRES.index(3200)] - ((residual[CENTRES.index(1600)] + residual[CENTRES.index(6400)]) / 2.0)
    {
      tilt: (slope - SLOPE_DB_PER_OCTAVE).abs,
      bumpiness:,
      mud: [mud, 0.0].max,
      edge: [edge, 0.0].max,
      crest: [CREST_DB.begin - report[:crest_db], report[:crest_db] - CREST_DB.end, 0.0].max,
      peak: [report[:true_peak_db] - TRUE_PEAK_CEILING_DB, 0.0].max,
      slope:,
    }
  end

  def self.score(measures) = measures.except(:slope).values.sum

  def self.line(measures)
    format("  critic: %<score>.1f dB off (tilt %<slope>.1f dB/oct, bumpy %<bump>.1f, mud %<mud>.1f, edge %<edge>.1f, crest %<crest>.1f, peak %<peak>.1f)",
           score: score(measures), slope: measures[:slope], bump: measures[:bumpiness], mud: measures[:mud],
           edge: measures[:edge], crest: measures[:crest], peak: measures[:peak])
  end
end

# --- drums.rb ---
# Deterministic, synthesised drum voices. Each hit has a shaped transient, a musical body
# and a noise/metal layer; the seeded generator makes a render repeatable.
class Drums
  def initialize(seed)
    @rng = Random.new(seed)
  end

  def kick(dur = 0.28)
    n = [(dur * SAMPLE_RATE).to_i, 1].max
    phase = 0.0
    Array.new(n) do |i|
      t = i.to_f / SAMPLE_RATE
      envelope = Math.exp(-t * 13.5)
      frequency = 43.0 + 112.0 * Math.exp(-t * 34.0)
      phase += 2.0 * Math::PI * frequency / SAMPLE_RATE
      body = Math.sin(phase) * envelope
      click = (Math.sin(2.0 * Math::PI * 1850.0 * t) * Math.exp(-t * 180.0)) * 0.12
      sub = Math.sin(2.0 * Math::PI * 48.0 * t) * Math.exp(-t * 8.0) * 0.18
      soft_clip((body * 0.82) + click + sub)
    end
  end

  def snare(dur = 0.22)
    n = [(dur * SAMPLE_RATE).to_i, 1].max
    previous = 0.0
    Array.new(n) do |i|
      t = i.to_f / SAMPLE_RATE
      noise = (@rng.rand * 2.0) - 1.0
      high_noise = noise - previous
      previous = noise
      snap = high_noise * Math.exp(-t * 72.0) * 0.34
      wire = noise * Math.exp(-t * 23.0) * 0.36
      body_env = Math.exp(-t * 24.0)
      body = (Math.sin(2.0 * Math::PI * 188.0 * t) * 0.48 +
              Math.sin(2.0 * Math::PI * 312.0 * t) * 0.16) * body_env
      soft_clip(body + wire + snap)
    end
  end

  # A cymbal lives in noisy, inharmonic upper partials. Low pitched ringing here
  # made the old hat sound like a little gong, so keep the body out of the midrange.
  def hat(dur = 0.075)
    n = [(dur * SAMPLE_RATE).to_i, 1].max
    previous = 0.0
    partials = [3477.0, 4789.0, 6121.0, 7919.0, 10_103.0, 12_791.0]
    phases = partials.map { @rng.rand * 2.0 * Math::PI }
    weights = partials.map { 0.45 + (@rng.rand * 0.55) }
    Array.new(n) do |i|
      t = i.to_f / SAMPLE_RATE
      noise = (@rng.rand * 2.0) - 1.0
      high = noise - previous
      previous = noise
      metal = partials.each_with_index.sum do |f, j|
        Math.sin(2.0 * Math::PI * f * t + phases[j]) * weights[j]
      end / weights.sum
      envelope = Math.exp(-t * 72.0)
      soft_clip((high * 0.39 + metal * 0.07) * envelope)
    end
  end

  # The pattern grid supplies timing; the seeded hit renderer supplies modest human variation
  # in pitch, decay and noise, so a bar does not sound like one sample copied on every beat.
  # Three voices only: a pattern that also asks for open, clap, rim, tom or perc gets silence for those
  # roles from this fallback rather than a KeyError that ends the render.
  def sounds
    {
      "kick" => kick(0.24 + (@rng.rand * 0.05)),
      "snare" => snare(0.18 + (@rng.rand * 0.08)),
      "hat" => hat(0.045 + (@rng.rand * 0.04)),
    }
  end

  private

  def soft_clip(value)
    Math.tanh(value * 1.35) / Math.tanh(1.35)
  end
end

# --- percussion.rb ---
# --------------------------------------------------------------------- kits
# Drum voices synthesised in plain Ruby, each a row of dilla.json. A kit maps the roles a
# pattern uses (kick, snare, clap, hat, open, rim, tom, perc) to voices with their tunings.
# Every voice is built once per render from a seed, so a seed names a kit as it names a take,
# and is scaled to a peak, so the mix levels in the data are the only loudness knob.
module Percussion
  TAU = 2 * Math::PI
  PEAKS = { "kick" => 0.9, "snare" => 0.7, "clap" => 0.7, "hat" => 0.3, "open" => 0.3, "rim" => 0.5, "tom" => 0.7, "perc" => 0.5 }.freeze

  def self.n(seconds) = (seconds * SAMPLE_RATE).to_i

  def self.lowpass(buf, hz)
    k = 1.0 - Math.exp(-TAU * hz / SAMPLE_RATE)
    y = 0.0
    buf.map { |x| y += k * (x - y) }
  end

  def self.highpass(buf, hz)
    k = 1.0 - Math.exp(-TAU * hz / SAMPLE_RATE)
    low = 0.0
    buf.map { |x| low += k * (x - low); x - low }
  end

  def self.bandpass(buf, lo, hi) = lowpass(highpass(buf, lo), hi)

  def self.noise(rng, count) = Array.new(count) { (rng.rand * 2) - 1 }

  def self.mix(*bufs)
    Array.new(bufs.map(&:size).max) { |i| bufs.sum { |b| b[i] || 0.0 } }
  end

  def self.scale_to(buf, peak)
    top = buf.map(&:abs).max
    top.to_f.zero? ? buf : buf.map { |x| x * peak / top }
  end

  # Drive into tanh, level-matched by the curve's own ceiling, and a fold past 0.6 for the
  # hardest settings: harmonics generated rather than borrowed from volume.
  def self.dirt(buf, amount)
    return buf if amount <= 0.0

    drive = 1.0 + (amount * 6.0)
    ceiling = Math.tanh(drive)
    out = buf.map { |x| Math.tanh(x * drive) / ceiling }
    return out if amount <= 0.6

    fold = 1.2 + amount
    out.map { |x| x + ((amount - 0.6) * Math.sin(x * fold * Math::PI)) * 0.5 }
  end

  # Short noise, highpassed: the beater.
  def self.click(rng, ms, hz = 1800.0) = highpass(noise(rng, [n(ms / 1000.0), 1].max), hz)

  # A sine whose pitch falls exponentially from body+sweep to body, a decaying amplitude, a click.
  def self.techno_kick(spec, rng, scale = 1.0)
    length = n(0.5 * scale)
    phase = 0.0
    body = Array.new(length) do |i|
      t = i.to_f / SAMPLE_RATE
      phase += TAU * (spec["body"] + (spec["sweep"] * Math.exp(-t * spec["sweep_decay"]))) / SAMPLE_RATE
      Math.sin(phase) * Math.exp(-t * spec["amp_decay"] / scale)
    end
    body = dirt(body, spec["drive"])
    click = click(rng, spec["click_ms"]).map { |x| x * 0.5 }
    mix(click, body)
  end

  def self.fm_kick(_spec, _rng)
    raw = Array.new(n(0.5)) do |i|
      t = i.to_f / SAMPLE_RATE
      (0.85 * Math.exp(-6 * t) * Math.sin((TAU * 55 * t) + (6 * Math.exp(-30 * t) * Math.sin(TAU * 58 * t)))) +
        (0.35 * Math.exp(-9 * t) * Math.sin(TAU * 42 * t))
    end
    lowpass(raw.map { |x| Math.tanh(1.8 * x) }, 240.0)
  end

  def self.fm_pair(carrier, modulator, index, decay, length, index_decay = 30.0)
    Array.new(n(length)) do |i|
      t = i.to_f / SAMPLE_RATE
      Math.sin((TAU * carrier * t) + (index * Math.exp(-t * index_decay) * Math.sin(TAU * modulator * t))) * Math.exp(-t * decay)
    end
  end

  def self.fm_snare(_spec, rng)
    body = fm_pair(200, 330, 7, 18, 0.25)
    crack = highpass(noise(rng, n(0.25)), 1500.0).each_with_index.map { |x, i| x * Math.exp(-25.0 * i / SAMPLE_RATE) }
    mix(body, crack.map { |x| x * 0.6 })
  end

  def self.fm_hat(spec, _rng)
    highpass(fm_pair(spec.fetch("carrier", 900), spec.fetch("modulator", 3150), 5, spec.fetch("decay", 90), 0.12, 20.0), 4000.0)
  end

  def self.kick_808(_spec, rng)
    phase = 0.0
    body = Array.new(n(1.6)) do |i|
      t = i.to_f / SAMPLE_RATE
      phase += TAU * (43 + (67 * Math.exp(-26 * t))) / SAMPLE_RATE
      Math.sin(phase) * Math.exp(-t * 3.0)
    end
    mix(body, click(rng, 8, 1800.0).map { |x| x * 0.3 })
  end

  # A short, layered boom: a sub that falls fast, a click, and a body near 150 Hz.
  def self.boom_808(_spec, rng)
    sub_phase = 0.0
    sub = Array.new(n(0.6)) do |i|
      t = i.to_f / SAMPLE_RATE
      sub_phase += TAU * (42 + (108 * Math.exp(-55 * t))) / SAMPLE_RATE
      Math.sin(sub_phase) * Math.exp(-t * 4.5)
    end
    body = Array.new(n(0.2)) { |i| t = i.to_f / SAMPLE_RATE; Math.sin(TAU * 150 * t) * Math.exp(-t * 20) * 0.4 }
    mix(sub, body, click(rng, 9, 1800.0).map { |x| x * 0.3 })
  end

  # Six detuned square oscillators at metallic ratios, crushed to 12 bits, highpassed.
  def self.hat_909(spec, rng)
    freqs = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0]
    length = n(spec["open"] ? 0.4 : 0.07)
    decay = spec["open"] ? 7.0 : 45.0
    raw = Array.new(length) do |i|
      t = i.to_f / SAMPLE_RATE
      freqs.each_with_index.sum { |f, k| (((t * f * (1.0 + (0.01 * (k - 2)))) % 1.0) < 0.5 ? 1.0 : -1.0) } / 6.0 * Math.exp(-t * decay)
    end
    levels = 2.0**11
    crushed = raw.map { |x| (x * levels).round / levels }
    highpass(crushed, spec.fetch("highpass", 7000.0)).map { |x| x + ((rng.rand * 2 - 1) * 0.0) }
  end

  # Four short noise bursts a few milliseconds apart, bandpassed, then a longer room tail.
  def self.clap_909(_spec, rng)
    out = Array.new(n(0.28), 0.0)
    [[0.0, 1750], [0.017, 1650], [0.036, 1500], [0.058, 1400]].each_with_index do |(at, fc), k|
      burst = bandpass(noise(rng, n(0.012)), fc * 0.6, fc * 1.5)
      burst.each_with_index { |x, i| out[n(at) + i] += x * Math.exp(-i * 400.0 / SAMPLE_RATE) * (k == 3 ? 0.8 : 0.9) if n(at) + i < out.size }
    end
    tail = bandpass(noise(rng, out.size), 800.0, 1150.0).each_with_index.map { |x, i| x * Math.exp(-i * 22.0 / SAMPLE_RATE) * 0.5 }
    start = n(0.058)
    tail.each_with_index { |x, i| out[start + i] += x if start + i < out.size }
    out
  end

  # Two detuned bodies and highpassed noise with a snappy envelope.
  def self.snare_909(spec, rng)
    tone = Array.new(n(0.2)) do |i|
      t = i.to_f / SAMPLE_RATE
      ((Math.sin(TAU * spec.fetch("body", 185) * t) + (0.8 * Math.sin(TAU * spec.fetch("body", 185) * 1.78 * t))) * Math.exp(-t * 22))
    end
    snap = highpass(noise(rng, n(0.2)), 1800.0).each_with_index.map { |x, i| x * Math.exp(-i * 18.0 / SAMPLE_RATE) }
    mix(tone.map { |x| x * 0.5 }, snap)
  end

  def self.rim(_spec, rng)
    modes = [1.0, 2.61, 4.19]
    ring = Array.new(n(0.06)) do |i|
      t = i.to_f / SAMPLE_RATE
      modes.each_with_index.sum { |m, k| Math.sin(TAU * 430 * m * t) / (k + 1.0) } * Math.exp(-t * 90)
    end
    mix(ring, click(rng, 3, 2600.0))
  end

  def self.tom(spec, _rng)
    phase = 0.0
    Array.new(n(0.35)) do |i|
      t = i.to_f / SAMPLE_RATE
      phase += TAU * (spec.fetch("to", 90) + ((spec.fetch("from", 160) - spec.fetch("to", 90)) * Math.exp(-t * 14))) / SAMPLE_RATE
      Math.sin(phase) * Math.exp(-t * 9)
    end
  end

  # Decaying inharmonic partials plus a bandpassed noise strike. modes are [ratio, decay].
  def self.modal(spec, rng)
    hz = spec.fetch("hz")
    length = n(spec.fetch("length", 0.4))
    bend = spec.fetch("bend", 0.0)
    ring = Array.new(length) do |i|
      t = i.to_f / SAMPLE_RATE
      spec.fetch("modes").sum { |ratio, decay| Math.sin(TAU * hz * ratio * (1.0 + (bend * Math.exp(-t * 30))) * t) * Math.exp(-t * decay) }
    end
    strike = bandpass(noise(rng, n(0.01)), hz * 0.5, hz * 3.0).map { |x| x * 0.4 }
    mix(ring, strike)
  end

  def self.shaker(spec, rng)
    highpass(noise(rng, n(spec.fetch("length", 0.07))), 6000.0).each_with_index.map { |x, i| x * Math.exp(-i * 50.0 / SAMPLE_RATE) }
  end

  # Struck sheet metal: five decaying modes, rung hard and driven.
  def self.metal(_spec, rng)
    modes = [[211, 9], [568, 16], [903, 24], [1371, 38], [1836, 52]]
    strike = click(rng, 6, 1500.0)
    Array.new(n(0.5)) do |i|
      t = i.to_f / SAMPLE_RATE
      ring = modes.sum { |hz, d| Math.sin(TAU * hz * t) * Math.exp(-t * (d / 8.0)) } / 3.0
      Math.tanh(2.6 * ((1.9 * ring) + (strike[i] || 0.0)))
    end
  end

  # The samples for one kit voice.
  def self.voice(spec, data, rng)
    raw =
      case spec.fetch("voice")
      when "techno_kick" then techno_kick(data.fetch("kick_styles").fetch(spec.fetch("style")), rng, spec.fetch("tail", 1.0))
      when "fm_kick" then fm_kick(spec, rng)
      when "fm_snare" then fm_snare(spec, rng)
      when "fm_hat" then fm_hat(spec, rng)
      when "kick_808" then kick_808(spec, rng)
      when "boom_808" then boom_808(spec, rng)
      when "hat_909" then hat_909(spec, rng)
      when "clap_909" then clap_909(spec, rng)
      when "snare_909" then snare_909(spec, rng)
      when "rim" then rim(spec, rng)
      when "tom" then tom(spec, rng)
      when "modal" then modal(data.fetch("modal_patches").fetch(spec.fetch("patch")).merge(spec), rng)
      when "shaker" then shaker(spec, rng)
      when "metal" then metal(spec, rng)
      else raise ArgumentError, "no kit voice #{spec['voice'].inspect}"
      end
    raw = lowpass(raw, spec["lowpass"]) if spec["lowpass"]
    scale_to(raw, spec.fetch("peak", PEAKS.fetch(spec.fetch("role", "perc"), 0.5)))
  end

  # A kit's voices by role. The seed gives each role its own noise.
  def self.kit(name, data, seed)
    data.fetch("kits").fetch(name) { abort "No kit: #{name}" }.each_with_object({}) do |(role, spec), out|
      next unless spec.is_a?(Hash) && spec.key?("voice")

      out[role] = voice(spec.merge("role" => role), data, Random.new(Zlib.crc32("#{seed}:#{role}")))
    end
  end

  # The low end grown from the kicks themselves: a long room, a lowpass, drive, two more lowpasses.
  def self.rumble(kick_bus)
    tail = lowpass(FX.reverb(kick_bus, 0.8), 180.0)
    tail = lowpass(lowpass(dirt(tail, 0.55), 110.0), 110.0)
    scale_to(tail, 0.6)
  end
end

# --- effects.rb ---
# ---------------------------------------------------------------------- FX
module FX
  def self.lowpass(buf, cutoff) = Stream::Lowpass.new(cutoff).process(buf)

  def self.reverb(buf, amount)
    return buf if amount.nil? || amount <= 0

    out = Stream::Reverb.new(amount).process(buf)
    peak = out.map(&:abs).max
    peak > 1.0 ? out.map { |s| s / peak } : out
  end

  # A spring tank (see Stream::Spring), added to the signal at `amount`.
  def self.spring(buf, amount) = Stream::Spring.new(amount).process(buf)

  # A dub send built on the existing multi-head echo: saturated, band-limited repeats
  # with feedback, but deliberately no reverb or time-varying modulation.
  def self.dub_echo(buf, settings)
    return buf unless settings

    Echo.process(
      buf,
      delay: settings.fetch("delay_ms").to_f / 1000.0,
      heads: settings.fetch("heads", [1, 2, 3]),
      intensity: settings.fetch("intensity", 0.6),
      volume: settings.fetch("volume", 0.6),
      lowpass: settings.fetch("lowpass", 4800),
      saturation: settings.fetch("saturation", 0.8),
      reverb: settings.fetch("reverb", 0.0),
      tail: settings.fetch("tail", 1.0),
      resets: [],
    )
  end

  # A crystallizer-style pitch-shifted delay. Short, Hann-windowed grains overlap to shift
  # the pitch by a fixed interval. Feedback moves each later repeat up another interval;
  # no LFO, vibrato, chorus or reverb is used.
  def self.crystallizer(buf, settings)
    return buf unless settings
    return buf if buf.empty?

    delay = settings.fetch("delay_ms", 350).to_f.clamp(20.0, 2000.0) / 1000.0
    semitones = settings.fetch("semitones", 12).to_f.clamp(-24.0, 24.0)
    feedback = settings.fetch("feedback", 0.35).to_f.clamp(0.0, 0.85)
    mix = settings.fetch("mix", 0.35).to_f.clamp(0.0, 1.0)
    repeats = settings.fetch("repeats", 3).to_i.clamp(1, 8)
    tail = settings.fetch("tail", 1.0).to_f.clamp(0.0, 5.0)
    grain = [(settings.fetch("grain_ms", 80).to_f.clamp(20.0, 200.0) * SAMPLE_RATE / 1000.0).round, 32].max
    delay_samples = [(delay * SAMPLE_RATE).round, 1].max
    extra = [(tail * SAMPLE_RATE).round, delay_samples * repeats].max
    out = Array.new(buf.size + extra, 0.0)
    buf.each_with_index { |sample, i| out[i] = sample }
    ratio = 2.0**(semitones / 12.0)
    shifted = crystal_shift(buf, ratio, grain)

    repeats.times do |repeat|
      start = delay_samples * (repeat + 1)
      gain = mix * (feedback**repeat)
      shifted.each_with_index do |sample, i|
        index = start + i
        break if index >= out.size

        out[index] += sample * gain
      end
      shifted = crystal_shift(shifted, ratio, grain) if repeat + 1 < repeats
    end
    out
  end

  def self.crystal_shift(buf, ratio, grain)
    return buf.dup if buf.empty?

    hop = [grain / 2, 1].max
    window = Array.new(grain) do |j|
      0.5 - (0.5 * Math.cos(2.0 * Math::PI * j / [grain - 1, 1].max))
    end
    source_offsets = Array.new(grain) { |j| (j * ratio).floor % grain }
    out = Array.new(buf.size, 0.0)
    weights = Array.new(buf.size, 0.0)
    (0...buf.size).step(hop) do |base|
      grain.times do |j|
        target = base + j
        break if target >= buf.size

        source = base + source_offsets[j]
        next if source >= buf.size

        weight = window[j]
        out[target] += buf[source] * weight
        weights[target] += weight
      end
    end
    out.each_index { |i| out[i] /= weights[i] if weights[i] > 1e-9 }
    out
  end

  # The profile's texture: lowpass, then reverb.
  def self.apply(buf, profile)
    t = profile["texture"] || {}
    spring(reverb(lowpass(buf, t["lowpass"]), t["reverb"]), t["spring"])
  end
end

# --- echo.rb ---
# -------------------------------------------------------------- tape echo
# A space echo: three playback heads read one loop at 1x, 2x and 3x the base delay. The
# heads in use are summed, darkened by a lowpass and a mild saturation, and fed back, so each
# repeat is quieter and duller than the last. No modulation: the tape runs true.
module Echo
  MAX_INTENSITY = 0.9 # feedback never reaches one, so the loop cannot run away

  # `send`, when given, is a proc from a sample index to how much of the input reaches the tape
  # at that moment: the hand on the send knob, which a throw turns up for a bar.
  def self.process(buf, delay:, heads: [1, 2], intensity: 0.5, volume: 0.45, lowpass: 3200, saturation: 0.35, reverb: 0.0, tail: 4.0, resets: [], send: nil)
    line = Stream::EchoLine.new(delay:, heads:, intensity:, volume:, lowpass:, saturation:, resets:, send:)
    wet = line.wet(buf + Array.new((tail * SAMPLE_RATE).to_i, 0.0)) # the repeats ring on after the last note and die away of themselves
    wet = FX.reverb(wet, reverb) if reverb.to_f.positive?
    Array.new(wet.size) { |n| (n < buf.size ? buf[n] : 0.0) + (volume * wet[n]) }
  end
end

# --- arp.rb ---
# --------------------------------------------------------------------- arp
# A chord's voicing played one note at a time, lowest voice first. Pure ordering: the
# patterns say which voice sounds on which step, the sequencer says when.
module Arp
  # The voices to cycle through: the voicing, repeated an octave up for each extra octave.
  def self.pool(voices, octaves)
    (0...octaves.clamp(1, 2)).flat_map { |o| voices.map { |n| n + 12 * o } }.uniq.sort
  end

  # `count` notes in the named pattern; nil is a rest. random_seeded draws from the seed, so a
  # seed repeats. broken_pairs alternates a low note with one two places up, thumb_pattern
  # returns to the lowest note between the others, pedal_arp holds it on every fourth step,
  # spread_roll plays the voices once, quickly, and leaves them ringing.
  def self.sequence(pattern, pool, count, seed)
    n = pool.size
    case pattern
    when "up" then Array.new(count) { |k| pool[k % n] }
    when "down" then Array.new(count) { |k| pool.reverse[k % n] }
    when "updown" then cycle(pool + pool[1...-1].to_a.reverse, count)
    when "converge" then cycle((0...n).map { |i| i.even? ? pool[i / 2] : pool[-1 - (i / 2)] }, count)
    when "broken_pairs" then Array.new(count) { |k| pool[((k / 2) + (k.odd? ? 2 : 0)) % n] }
    when "thumb_pattern" then Array.new(count) { |k| k.even? ? pool[0] : pool[1 + ((k / 2) % [n - 1, 1].max)] }
    when "pedal_arp" then Array.new(count) { |k| (k % 4).zero? ? pool[0] : pool[1 + ((k - (k / 4) - 1) % [n - 1, 1].max)] }
    when "spread_roll" then Array.new(count) { |k| k < n ? pool[k] : nil }
    when "spiral" then cycle(spiral(n).map { |i| pool[i] }, count)
    when "pendulum" then cycle(pendulum(n).map { |i| pool[i] }, count)
    when "fibonacci" then cycle(fibonacci(n, 64).map { |i| pool[i] }, count)
    when "prime_walk" then cycle(prime_walk(n).map { |i| pool[i] }, count)
    when "call_response" then Array.new(count) { |k| call_response(pool, k) }
    when "pedal_point" then Array.new(count) { |k| k.even? ? pool[0] : pool[1 + (((k / 2)) % [n - 1, 1].max)] }
    when "random_seeded"
      rng = Random.new(seed)
      Array.new(count) { pool[rng.rand(n)] }
    else raise ArgumentError, "no arp pattern #{pattern.inspect}"
    end
  end

  def self.cycle(list, count) = Array.new(count) { |k| list[k % list.size] }

  # From the middle outward, one either side in turn, and back in again.
  def self.spiral(n)
    centre = n / 2
    out = [centre] + (1...n).flat_map { |d| [centre + d, centre - d] }.select { |i| i.between?(0, n - 1) }
    out + out[1...-1].to_a.reverse
  end

  # Up two, back one, to the top, and the same down again.
  def self.pendulum(n)
    up = [0]
    i = 0
    while i < n - 1
      up << [i + 2, n - 1].min
      up << i + 1
      i += 1
    end
    up + up[1...-1].to_a.reverse
  end

  # The Fibonacci numbers taken round the pool: 1, 1, 2, 3, 5, 8, ... modulo its size.
  def self.fibonacci(n, count)
    a, b = 1, 1
    Array.new(count) { a.tap { a, b = b, a + b } % n }
  end

  # Strides of the first primes round the pool, so the walk takes a long time to come back.
  def self.prime_walk(n)
    primes = [2, 3, 5, 7, 11, 13]
    i = 0
    Array.new(primes.size * 4) { |k| (i = (i + primes[k % primes.size]) % n) }
  end

  # Four notes rising, then three falling from higher up, then a rest.
  def self.call_response(pool, k)
    n = pool.size
    case k % 8
    when 0..3 then pool[(k % 8) % n]
    when 4..6 then pool[[n - 1, 4].min - ((k % 8) - 4) % n]
    end
  end
end

# One arpeggio note: `base` is where its step falls on the grid, `off` how far it leans from
# there (swing and humanize, clamped to MAX_OFFSET), the rest as they sound.
Pluck = Struct.new(:base, :off, :midi, :dur, :gain) # midi is one note, or a chord's notes

module Arp
  # The small modifiers that shape the note stream, applied in the order the arp lists them.
  # `slot` is the length of one arp step in seconds; `peak` the strongest accent gain.
  def self.modify(plucks, name, params, rng, slot:, peak:)
    case name
    when "euclidean"
      steps = params.fetch("steps", 8)
      pulses = params.fetch("pulses", 5).clamp(1, steps)
      plucks.each_with_index.select { |_, i| ((i * pulses) % steps) < pulses }.map(&:first)
    when "probability"
      plucks.select { |_| rng.rand <= params.fetch("probability", 1.0) }
    when "note_repeat"
      count = params.fetch("count", 1).clamp(1, 6)
      plucks.flat_map { |p| split(p, count, slot, 0.72, 0.06) }
    when "ratchet"
      max = params.fetch("max", 3).clamp(1, 4)
      plucks.flat_map do |p|
        accented = p.gain >= peak * 0.99 && rng.rand < params.fetch("chance", 0.5)
        accented && max > 1 ? split(p, rng.rand(2..max), slot, 0.86, 0.11) : [p]
      end
    when "humanize"
      ms = params.fetch("ms", 4.0) / 1000.0
      g = params.fetch("gain", 0.06)
      plucks.each do |p|
        p.off += rng.rand(-ms..ms)
        p.gain = (p.gain + rng.rand(-g..g)).clamp(0.0, 1.0)
      end
    when "grace"
      tones = params.fetch("tones", []).sort # a grace note is the next chord tone below, never a chromatic neighbour
      plucks.flat_map do |p|
        below = Array(p.midi).map { |m| tones.reverse.find { |t| t < m } || m }
        grace = Pluck.new(p.base - [p.dur * 0.18, 0.035].max, p.off, p.midi.is_a?(Array) ? below : below.first, [p.dur * 0.12, 0.018].max, p.gain * params.fetch("gain", 0.3))
        [grace, p]
      end
    else raise ArgumentError, "no arp modifier #{name.inspect}"
    end
  end

  # `count` evenly spaced copies of a note within its slot, each `fade` quieter than the last.
  def self.split(pluck, count, slot, held, fade)
    return [pluck] if count <= 1

    each = slot / count
    Array.new(count) do |i|
      Pluck.new(pluck.base + (each * i), pluck.off, pluck.midi, [each * held, 0.018].max, pluck.gain * (1.0 - (fade * i)))
    end
  end
end

# --- flow.rb ---
# -------------------------------------------------------------------- flow
# A fluid arpeggio. A random walk called energy, 0 to 1, drifts from beat to beat along an arch
# over each chord, and everything that makes an arpeggio busy follows it: the rate breathes
# from quarters through eighths and triplets to sixteenths, rests thin out, the velocity
# rises, and the octave span opens. The order of the notes is a seeded Markov chain over the
# chord's tones that prefers to move by a step and to keep its direction. A run swells toward
# its top note and the notes passed on the way are ghosted. The phrase leans a little inside the
# clamp, early in the body of a chord and late at its end. Every note is a tone of the chord.
module Flow
  # Energy up to which each rate holds, in sixteenths a note: a quarter, an eighth, a triplet
  # eighth (three to the beat), a sixteenth.
  RATES = [[0.25, 4.0], [0.5, 2.0], [0.75, 4.0 / 3.0], [1.01, 1.0]].freeze

  def self.rate(energy) = RATES.find { |limit, _| energy < limit }.last

  # The energy walk: small seeded steps pulled toward a target, held inside 0..1.
  class Walk
    attr_reader :value

    def initialize(seed, start: 0.5)
      @rng = Random.new(seed)
      @value = start
    end

    def step(target)
      @value = (@value + ((@rng.rand - 0.5) * 0.36) + (0.18 * (target - @value))).clamp(0.02, 0.98)
    end
  end

  # One chord of the arpeggio. Returns [plucks, energies], the energies one for each beat, for
  # the swell of a pad beneath.
  def self.chord_events(voices, index:, chord_steps:, step:, seed:, walk:, settings:, gate: 0.8)
    rng = Random.new(Zlib.crc32("#{seed}:flow:#{index}"))
    beats = (chord_steps / 4.0).ceil
    arch = ->(beat) { 0.25 + (0.6 * Math.sin(Math::PI * (beat + 0.5) / beats)) }
    energies = []
    picks = []
    pos = 0.0
    last = nil
    direction = 1
    beat = -1
    energy = walk.value
    while pos < chord_steps - 1e-6
      if (pos / 4).floor > beat
        beat = (pos / 4).floor
        energy = walk.step(arch.call(beat))
        energies << energy
      end
      pool = Arp.pool(voices, energy > 0.55 ? 2 : 1)
      length = rate(energy)
      rest = !picks.empty? && rng.rand < (1.0 - energy) * 0.3
      unless rest
        near = last && pool.each_index.min_by { |j| (pool[j] - last).abs } # the pool grows and shrinks with the energy; the note held in mind does not
        i = next_index(pool, near, direction, rng)
        direction = i <=> near if near && i != near
        last = pool[i]
        picks << [pos, pool[i], energy, i, pool.size]
      end
      pos += length
    end
    [pluck_stream(picks, index, chord_steps, step, gate, settings), energies.empty? ? [walk.value] : energies]
  end

  # The next index into the pool: near the last, away from standing still, keeping the way it was going.
  def self.next_index(pool, last, direction, rng)
    return rng.rand(pool.size) if last.nil? || last >= pool.size

    weights = pool.each_index.map do |j|
      pull = Math.exp(-(j - last).abs / 1.3)
      pull *= 0.25 if j == last
      pull *= 1.6 if j != last && (j <=> last) == direction
      pull
    end
    roll = rng.rand * weights.sum
    weights.each_with_index { |w, j| return j if (roll -= w).negative? }
    pool.size - 1
  end

  # Plucks from the picks: velocity from the energy and the height in the pool, the notes between a
  # lower and a higher neighbour ghosted, and the lean of the phrase.
  def self.pluck_stream(picks, index, chord_steps, step, gate, settings)
    accent = settings.fetch("flow_ghost", 0.45)
    picks.each_with_index.map do |(pos, midi, energy, i, size), k|
      before = k.positive? ? picks[k - 1][3] : nil
      after = picks[k + 1]&.fetch(3)
      passing = before && after && ((before < i && i < after) || (before > i && i > after))
      height = size > 1 ? i.to_f / (size - 1) : 0.5
      gain = (0.4 + (0.55 * energy)) * (0.75 + (0.25 * height)) * (passing ? accent : 1.0)
      until_next = (picks[k + 1]&.first || chord_steps) - pos
      u = pos / chord_steps
      lean = ((-0.4 * 0.02 * Math.sin(Math::PI * u)) + (u > 0.8 ? 0.02 * (((u - 0.8) / 0.2)**2) : 0.0)).clamp(-MAX_OFFSET, MAX_OFFSET)
      Pluck.new(((index * chord_steps) + pos) * step, lean, midi, until_next * step * gate, gain.clamp(0.05, 1.0))
    end
  end

  # A pad that swells with the energy: linear between the beats' levels, from a quarter to full.
  def self.swell(pad, energies, beat_samples)
    return pad if energies.empty?

    pad.each_with_index.map do |v, i|
      pos = i.to_f / beat_samples
      a = energies[[pos.floor, energies.size - 1].min]
      b = energies[[pos.floor + 1, energies.size - 1].min]
      v * (0.25 + (0.75 * (a + ((b - a) * (pos - pos.floor)))))
    end
  end
end

# --- organ.rb ---
# ------------------------------------------------------------------ organ
# A generative improvisation for organ in the manner of the baroque: a pedal line, inner voices
# that hold and resolve suspensions, and a right hand that runs, turns and trills over them, in
# phrases of two to four bars that end on cadences. Everything is a step of one declared scale,
# counted as an integer index into it, so no note can leave the scale; the harmony is the scale's
# own triads. The same seed plays the same piece. Time is in sixteenths, sixteen to the bar, and
# the sound is the organ voice with a registration for each line, the right hand's rotating from
# phrase to phrase.
module Organ
  BAR = 16
  FLATS = %w[C Db D Eb E F Gb G Ab A Bb B].freeze
  TRIAD = { [3, 7] => "m", [4, 7] => "", [3, 6] => "dim", [4, 8] => "aug" }.freeze
  CADENCE = { "authentic" => [4, 0], "half" => [3, 4], "deceptive" => [4, 5], "plagal" => [3, 0] }.freeze
  MOVES = { 0 => [3, 5, 1], 1 => [4, 3], 2 => [5, 3], 3 => [1, 4, 0], 4 => [0, 5], 5 => [1, 3, 4], 6 => [0] }.freeze
  # A suspension holds a note of the chord before into the next, where it is a dissonance over the
  # bass, and lets it fall a step on the third beat. 4-3 and 9-8 sit over the root, 7-6 over the
  # chord's third. The numbers are scale steps above the chord's root.
  SUSPENSION = { "4-3" => { held: 3, resolved: 2, bass: 0 }, "9-8" => { held: 8, resolved: 7, bass: 0 },
                 "7-6" => { held: 8, resolved: 7, bass: 2 } }.freeze

  Note = Struct.new(:step, :length, :midi, :gain, :phrase)
  Phrase = Struct.new(:first_bar, :bars, :cadence, :registration) do
    def last_bar = first_bar + bars - 1
  end
  Suspension = Struct.new(:type, :held, :resolved, :bass)
  Piece = Struct.new(:key, :scale, :pcs, :names, :phrases, :lines, :suspensions, keyword_init: true) do
    def steps = names.size * BAR
  end

  # The scale as an infinite ladder: index 0 is the tonic in the lowest octave, 7 the tonic an
  # octave above. Triads, neighbours and runs are arithmetic on the index.
  class Ladder
    def initialize(tonic, intervals)
      @tonic = tonic
      @intervals = intervals
    end

    def midi(idx) = 24 + @tonic + (12 * idx.div(7)) + @intervals[idx % 7]

    def pcs = @intervals.map { |i| (@tonic + i) % 12 }

    def pc(idx) = midi(idx) % 12

    # Every index whose note lies in a midi range, lowest first.
    def within(range) = (-7..28).select { |i| range.cover?(midi(i)) }

    def chord_tone?(idx, degree) = [0, 2, 4].include?((idx - degree) % 7)

    # The name of the triad on a degree, as Chords reads it.
    def chord_name(degree)
      root = pc(degree)
      quality = TRIAD.fetch([(pc(degree + 2) - root) % 12, (pc(degree + 4) - root) % 12]) { raise ArgumentError, "no triad on degree #{degree}" }
      "#{FLATS[root]}#{quality}"
    end

    # The index in the range, of the given degree (or of a tone of the chord on it) nearest to `near`.
    def nearest(degree, near, range) = within(range).select { |i| i % 7 == degree % 7 }.min_by { |i| [(i - near).abs, i] }

    def nearest_tone(degree, near, range) = within(range).select { |i| chord_tone?(i, degree) }.min_by { |i| [(i - near).abs, i] }

    def closest_to_midi(midi, range) = within(range).min_by { |i| [(self.midi(i) - midi).abs, i] }
  end

  def self.rng(seed, label) = Random.new(Zlib.crc32("#{seed}:organ:#{label}"))

  def self.pick(table, rng)
    roll = rng.rand * table.values.sum
    table.each { |name, weight| return name if (roll -= weight).negative? }
    table.keys.last
  end

  # ------------------------------------------------------------ the whole piece
  def self.compose(seed:, config:, bars: nil, key: nil, scale: nil)
    bars = (bars || config.fetch("bars")).clamp(4, 96)
    ladder, key_name, scale_name = tonality(seed, config, key, scale)
    phrases = plan_phrases(seed, config, bars)
    degrees = harmony(seed, phrases)
    ranges = config.fetch("ranges").transform_values { |lo, hi| (lo..hi) }
    suspensions = plan_suspensions(seed, config, ladder, degrees, phrases, ranges.fetch("left"))
    lines = { "pedal" => pedal(seed, config, ladder, degrees, phrases, suspensions, ranges.fetch("pedal")),
              "left" => left(seed, ladder, degrees, phrases, suspensions, ranges.fetch("left")),
              "right" => right(seed, config, ladder, degrees, phrases, ranges.fetch("right")) }
    piece = Piece.new(key: key_name, scale: scale_name, pcs: ladder.pcs, names: degrees.map { |d| ladder.chord_name(d) },
                      phrases:, lines:, suspensions: suspensions.compact.size)
    check(piece, ranges)
    piece
  end

  def self.tonality(seed, config, key, scale)
    rng = rng(seed, "key")
    scale ||= pick(config.fetch("scale_weights"), rng)
    drawn = rng.rand(12)
    tonic = key ? key_pc(key) : drawn
    [Ladder.new(tonic, config.fetch("scales").fetch(scale) { raise ArgumentError, "no scale #{scale.inspect}" }), FLATS[tonic], scale]
  end

  def self.key_pc(key)
    named = key.to_s.match(/\A([A-G])([b#]?)\z/) or raise ArgumentError, "no key #{key.inspect}"
    (Chords::NOTE_PC.fetch(named[1]) + Chords::ACCIDENTAL.fetch(named[2])) % 12
  end

  # Phrase lengths from two to four bars that add up to the piece; the last ends on an
  # authentic cadence, the others on a half, authentic, deceptive or plagal one.
  def self.plan_phrases(seed, config, bars)
    rng = rng(seed, "phrases")
    out = []
    first = 0
    while first < bars
      left = bars - first
      options = config.fetch("phrase_bars").select { |n| n <= left && left - n != 1 }
      out << Phrase.new(first, options.sample(random: rng) || left, nil, nil)
      first += out.last.bars
    end
    rotation = config.fetch("rotation")
    out.each_with_index do |phrase, i|
      phrase.cadence = i == out.size - 1 ? "authentic" : pick(config.fetch("cadences"), rng)
      phrase.registration = rotation[i % rotation.size]
    end
    out
  end

  # One degree for each bar: lead chords that move by the usual roots, then the cadence.
  def self.harmony(seed, phrases)
    rng = rng(seed, "harmony")
    phrases.each_with_index.flat_map do |phrase, i|
      cadence = CADENCE.fetch(phrase.cadence).dup
      cadence[0] = [1, 3].sample(random: rng) if phrase.cadence == "half"
      current = i.zero? || rng.rand < 0.7 ? 0 : [5, 3].sample(random: rng)
      lead = Array.new(phrase.bars - cadence.size) do
        chord = current
        current = (MOVES.fetch(current) - [cadence.first]).sample(random: rng) || 0
        chord
      end
      lead + cadence
    end
  end

  # ---------------------------------------------------------------- suspensions
  # A Suspension or nil for each bar. The held note must belong to the chord before it and, when
  # that bar also resolves a suspension, be the very note it resolved to.
  def self.plan_suspensions(seed, config, ladder, degrees, phrases, range)
    rng = rng(seed, "suspensions")
    spec = config.fetch("suspensions")
    penultimate = phrases.map { |ph| ph.last_bar - 1 }
    plan = Array.new(degrees.size)
    (1...(degrees.size - 1)).each do |bar| # the last bar is the piece's rest and keeps its root
      next unless rng.rand < (penultimate.include?(bar) ? spec.fetch("cadence_chance") : spec.fetch("chance"))

      type = spec.fetch("types").shuffle(random: rng).find do |t|
        held = degrees[bar] + SUSPENSION.fetch(t)[:held]
        ladder.chord_tone?(held, degrees[bar - 1]) && (plan[bar - 1].nil? || plan[bar - 1].resolved % 7 == held % 7)
      end
      next unless type

      row = SUSPENSION.fetch(type)
      near = plan[bar - 1]&.resolved || ladder.closest_to_midi(63, range)
      held = ladder.nearest(degrees[bar] + row[:held], near, (range.first + 5)..range.last)
      plan[bar] = Suspension.new(type, held, held - 1, degrees[bar] + row[:bass])
    end
    plan
  end

  # ---------------------------------------------------------------------- pedal
  # The root on the strong beats: whole bars of half notes, or a walk of quarters with a
  # neighbour on the second and an approach to the next root on the fourth; a tonic held through the
  # lead bars of some phrases; the last bar of a phrase a long root.
  def self.pedal(seed, config, ladder, degrees, phrases, suspensions, range)
    rng = rng(seed, "pedal")
    notes = []
    last = 42
    lows = ladder.within(range)
    root_near = lambda do |degree|
      lows.select { |i| i % 7 == degree % 7 }.min_by { |i| [(ladder.midi(i) - last).abs, i] }
    end
    put = lambda do |bar, offset, length, idx, phrase|
      last = ladder.midi(idx)
      notes << Note.new((bar * BAR) + offset, length, last, 0.9, phrase)
    end
    phrases.each_with_index do |phrase, p|
      lead = phrase.bars - 2
      point = lead >= 1 && rng.rand < config.fetch("pedal_point_chance")
      put.call(phrase.first_bar, 0, lead * BAR, root_near.call(0), p) if point
      (phrase.first_bar..phrase.last_bar).each do |bar|
        next if point && bar < phrase.first_bar + lead

        sus = suspensions[bar]
        root = root_near.call(sus && sus.bass % 7 != degrees[bar] ? sus.bass : degrees[bar])
        if bar == phrase.last_bar
          put.call(bar, 0, bar == degrees.size - 1 ? BAR : 12, root, p)
        elsif sus || pick(config.fetch("pedal_styles"), rng) == "half"
          put.call(bar, 0, 8, root, p)
          put.call(bar, 8, 8, root, p)
        else
          neighbour = lows.include?(root + 1) ? root + 1 : root - 1
          follow = lows.select { |i| i % 7 == degrees[bar + 1] % 7 }.min_by { |i| [(ladder.midi(i) - ladder.midi(root)).abs, i] }
          approach = follow + (root > follow ? 1 : -1)
          put.call(bar, 0, 4, root, p)
          put.call(bar, 4, 4, neighbour, p)
          put.call(bar, 8, 4, root, p)
          put.call(bar, 12, 4, lows.include?(approach) && approach != root ? approach : neighbour, p)
        end
      end
    end
    notes
  end

  # ------------------------------------------------------------------- left hand
  # Two inner voices. The alto goes by half bars, quarters or the off-beat eighths of a continuo;
  # where a suspension is planned it holds the note tied from the bar before and falls a step on the
  # third beat. The tenor sounds another tone of the chord, clear of the suspended note.
  def self.left(seed, ladder, degrees, phrases, suspensions, range)
    rng = rng(seed, "left")
    upper = ((range.first + 9)..range.last)
    lower = (range.first..(range.first + 8))
    alto = []
    tenor = []
    a_last = ladder.closest_to_midi(63, upper)
    t_last = ladder.closest_to_midi(55, lower)
    style = nil
    degrees.each_index do |bar|
      p = phrases.index { |ph| bar <= ph.last_bar }
      style = %w[sustained quarters continuo].sample(random: rng) if bar == phrases[p].first_bar
      sus = suspensions[bar]
      after = suspensions[bar + 1]
      degree = degrees[bar]
      base = bar * BAR
      clash = lambda do |idx|
        sus && ((ladder.midi(idx) - ladder.midi(sus.held)).abs <= 1 || idx % 7 == sus.held % 7)
      end
      tone = lambda do |near, band|
        pool = ladder.within(band).select { |i| ladder.chord_tone?(i, degree) }
        clear = pool.reject { |i| clash.call(i) }
        (clear.empty? ? pool : clear).min_by { |i| [(i - near).abs, i] }
      end
      low = tone.call(t_last, lower)
      if sus
        alto.last.length += 8
        alto << Note.new(base + 8, 8, ladder.midi(sus.resolved), 0.7, p)
        a_last = sus.resolved
      elsif bar == degrees.size - 1
        alto << Note.new(base, BAR, ladder.midi(tone.call(a_last, upper)), 0.7, p)
      else
        first = tone.call(a_last, upper)
        second = after ? after.held : tone.call(first + (rng.rand < 0.5 ? 1 : -1), upper)
        alto.concat(style_notes(style, base, first, second, p, ladder))
        a_last = second
      end
      if bar == degrees.size - 1
        tenor << Note.new(base, BAR, ladder.midi(low), 0.7, p)
      else
        tenor.concat(style_notes(style, base, low, tone.call(low + (rng.rand < 0.5 ? 1 : -1), lower), p, ladder))
      end
      t_last = low
    end
    (alto + tenor).sort_by { |n| [n.step, n.midi] }
  end

  # One bar of an inner voice: held half bars, quarters, or the off-beat eighths of a continuo.
  # Every style ends on `second`, which is what a tied suspension takes up.
  def self.style_notes(style, base, first, second, phrase, ladder)
    case style
    when "quarters"
      [first, second, first, second].each_with_index.map { |idx, k| Note.new(base + (k * 4), 4, ladder.midi(idx), 0.7, phrase) }
    when "continuo"
      [Note.new(base, 2, ladder.midi(first), 0.7, phrase)] +
        [[2, first], [6, first], [10, second], [14, second]].map { |off, idx| Note.new(base + off, 2, ladder.midi(idx), 0.55, phrase) }
    else
      [Note.new(base, 8, ladder.midi(first), 0.7, phrase), Note.new(base + 8, 8, ladder.midi(second), 0.7, phrase)]
    end
  end

  # ------------------------------------------------------------------ right hand
  # Built from arrivals, a chord tone at the start of every half bar, drawn along an arch that
  # climbs through the phrase and comes down onto the cadence. Between two arrivals one figure
  # decorates the step: a run, a turn, a neighbour, an appoggiatura, a dotted walk, the phrase's
  # motif or the motif a step along, or a trill on the way into the cadence. The last bar of a
  # phrase is its landing note and a breath.
  def self.right(seed, config, ladder, degrees, phrases, range)
    rng = rng(seed, "right")
    motifs = Array.new(2) { motif(rng, config.fetch("motifs")) }
    lows = ladder.within(range)
    notes = []
    cursor = ladder.nearest(0, ladder.closest_to_midi(72, range), range)
    previous = nil
    phrases.each_with_index do |phrase, p|
      arrivals = arrivals(ladder, degrees, phrase, cursor, lows, range, rng)
      (phrase.first_bar...phrase.last_bar).each do |bar|
        2.times do |half|
          here = arrivals.fetch([bar, half])
          upcoming = half.zero? ? arrivals.fetch([bar, 1]) : arrivals.fetch([bar + 1, 0])
          landing = arrivals.fetch([phrase.last_bar, 0])
          figure = if half == 1 && bar == phrase.last_bar - 1 && ladder.chord_tone?(here, degrees[bar]) && (here - landing).abs == 1 then :trill
                   else choose(config, rng, here, upcoming, ladder, degrees[bar], previous)
                   end
          built = figure_notes(figure, here, upcoming, ladder, degrees[bar], rng, motifs, previous, lows)
          previous = [figure, built]
          built.inject((bar * BAR) + (half * 8)) do |at, (idx, len)|
            notes << Note.new(at, len, ladder.midi(idx.clamp(lows.min, lows.max)), (at % 4).zero? ? 1.0 : 0.8, p)
            at + len
          end
        end
      end
      landing = arrivals.fetch([phrase.last_bar, 0])
      notes << Note.new(phrase.last_bar * BAR, p == phrases.size - 1 ? BAR : 12, ladder.midi(landing), 1.0, p)
      cursor = landing
    end
    notes
  end

  # The chord tone to land on at the start of each half bar of a phrase, along an arch that peaks
  # about two thirds through; the last is the tonic for the closing cadences and a tone of the
  # chord for the half cadence.
  def self.arrivals(ladder, degrees, phrase, cursor, lows, range, rng)
    slots = (phrase.bars - 1) * 2
    peak = lows.min + 6 + rng.rand([lows.size - 7, 1].max)
    landing = phrase.cadence == "half" ? ladder.nearest_tone(degrees[phrase.last_bar], cursor, range) : ladder.nearest(0, cursor, range)
    turn = (slots * 0.65).round
    out = {}
    slots.times do |s|
      bar = phrase.first_bar + (s / 2)
      target = s <= turn ? cursor + (((peak - cursor) * (s.to_f / [turn, 1].max)).round) : peak + (((landing - peak) * ((s - turn).to_f / [slots - turn, 1].max)).round)
      out[[bar, s % 2]] = ladder.nearest_tone(degrees[bar], target, range)
    end
    out[[phrase.last_bar, 0]] = landing
    out
  end

  def self.choose(config, rng, here, upcoming, ladder, degree, previous)
    table = config.fetch("figures").dup
    distance = (upcoming - here).abs
    table.delete("run8") if distance > 3
    table.delete("run16") if distance > 7
    table.delete("appoggiatura") if ladder.chord_tone?(here + 1, degree)
    table.delete("sequence") unless previous && previous.first == :motif
    table.delete(previous.first.to_s) if previous && previous.first != :motif && rng.rand < 0.6
    table.empty? ? :run8 : pick(table, rng).to_sym
  end

  # [index, length] pairs for one half bar, eight sixteenths in all.
  def self.figure_notes(figure, here, upcoming, _ladder, degree, rng, motifs, previous, lows)
    side = (upcoming <=> here).nonzero? || 1
    case figure
    when :run16 then lens_path([1] * 8, here, upcoming, rng, lows)
    when :run8 then lens_path([2] * 4, here, upcoming, rng, lows)
    when :dotted then lens_path([3, 1, 3, 1], here, upcoming, rng, lows)
    when :neighbor then [[here, 2], [here + side, 2], [here, 2], [upcoming - side, 2]]
    when :turn then [[here + 1, 1], [here, 1], [here - 1, 1], [here, 1], [upcoming - side, 4]]
    when :appoggiatura then [[here + 1, 3], [here, 1]] + lens_path([2, 2], here, upcoming, rng, lows)
    when :held then [[here, 4]] + lens_path([2, 2], here, upcoming, rng, lows)
    when :motif then land_motif(motifs.sample(random: rng).map { |off, len| [here + off, len] }, upcoming)
    when :sequence
      shift = rng.rand < 0.5 ? 1 : -1
      land_motif(previous.last.map { |idx, len| [idx + shift, len] }, upcoming)
    when :trill then [[here, 1], [here + 1, 1], [here, 1], [here + 1, 1], [here, 1], [here + 1, 1], [here, 2]]
    else raise ArgumentError, "no figure #{figure.inspect} for degree #{degree}"
    end
  end

  # Unit steps from `start` to a note beside `goal`, in as many notes as `lens` has. A run shorter
  # than the way is a run; a longer one wanders by neighbour notes first.
  def self.lens_path(lens, start, goal, rng, lows)
    moves = lens.size - 1
    reach = ->(e) { (e - start).abs <= moves && (moves - (e - start).abs).even? && lows.include?(e) }
    finish = [goal - 1, goal + 1, goal].select(&reach).min_by { |e| [(e - goal).abs == 1 ? 0 : 1, (e - goal).abs, rng.rand] } || start
    direction = finish <=> start
    wander = (moves - (finish - start).abs) / 2
    steps = ([direction.zero? ? 1 : direction] * (finish - start).abs) + ([1, -1] * wander)
    steps = steps.shuffle(random: rng) unless wander.zero?
    idx = start
    path = [idx] + steps.map { |m| idx += m }
    path = path.map { |i| i.clamp(lows.min, lows.max) }
    path << path.last while path.size < lens.size
    path.first(lens.size).zip(lens)
  end

  # Draw a motif's last note to a step beside the next arrival, from the side it came.
  def self.land_motif(shape, upcoming)
    came = (shape[-2]&.first || shape.last.first) <=> upcoming
    shape[-1] = [upcoming + (came.zero? ? 1 : came), shape.last.last]
    shape
  end

  def self.motif(rng, spec)
    lens = spec.fetch("rhythms").sample(random: rng)
    offsets = lens.each_index.inject([0]) { |acc, _| acc + [acc.last + spec.fetch("steps").sample(random: rng)] }.first(lens.size)
    offsets.zip(lens)
  end

  # --------------------------------------------------------------------- checks
  # The piece answers for itself: every note in the scale and inside its line's range, the pedal
  # and the right hand never sounding two notes at once, no phrase outside two to four bars.
  def self.check(piece, ranges)
    piece.lines.each do |name, notes|
      range = ranges.fetch(name)
      notes.each do |n|
        raise "organ #{name}: #{n.midi} is outside the scale" unless piece.pcs.include?(n.midi % 12)
        raise "organ #{name}: #{n.midi} is outside #{range}" unless range.cover?(n.midi)
        raise "organ #{name}: a note of length #{n.length}" unless n.length.to_i.positive?
      end
      next if name == "left"

      notes.sort_by(&:step).each_cons(2) { |a, b| raise "organ #{name}: a note at step #{a.step} runs into the next" if a.step + a.length > b.step }
    end
    raise "organ: a phrase outside two to four bars" unless piece.phrases.all? { |ph| ph.bars.between?(2, 4) }
  end
end

# --- sequencer.rb ---
# ---------------------------------------------------------------- sequencer
# One groove profile says how the render is played. Everything is in seconds or in
# fractions, all of it scaled by pd_amount (0 is the grid, 1 is the profile, up to 1.5).
#
#   swing         where the second chord of a pair lands (0.5 straight, 0.54 a little late)
#   drum_swing    the same for the off-beat sixteenths, per role: kick, snare, hat
#   offsets       seconds a role sits from the grid: kick, snare, hat, and kick_first
#   pocket        leans in fractions of a sixteenth step, so they follow the tempo: per role
#                 { shift_steps, anchor (steps that lean 0), drift_steps (seeded, per voice and
#                 step in the bar, so every bar leans as the first did) }; a snare off the
#                 backbeat steps takes the ghost entry. A role with no entry keeps its offsets.
#   drunk_amount  0..1, a seeded random nudge on every hit, never past MAX_OFFSET
#   sidechain     { amount, release }: the chords dip on every kick (default: none)
#   texture       { detune, lowpass, reverb }
#   arp, echo     present means on; each overrides the defaults of the same name in the data
class Sequencer
  attr_reader :seed, :pd_amount
  attr_writer :tempo # beats a minute; voices that play on the grid need it
  # With a list here the sequencer keeps what `sound` is asked to play, as Part rows, and makes no audio:
  # the streamer plays the notes itself, block by block.
  attr_accessor :capture

  Part = Struct.new(:plucks, :voice, :gain, :swell)

  # Parts made inside the block carry this gain and, for a pad that swells, [energies, beat_samples].
  def with_part(gain: 1.0, swell: nil)
    saved = [@part_gain, @part_swell]
    @part_gain = gain
    @part_swell = swell
    yield
  ensure
    @part_gain, @part_swell = saved
  end

  def initialize(data, profile_name:, pd_amount: nil, seed: nil, transpose: 0, wrap: false, kit: nil)
    @kit = kit
    @data = data
    @transpose = transpose
    @wrap = wrap
    @profile = data["groove_profiles"].fetch(profile_name) { abort "No groove profile: #{profile_name}" }
    @seed = seed || Random.new_seed % 1_000_000
    @pd_amount = (pd_amount || @profile.fetch("pd_amount", 1.0)).to_f.clamp(0.0, 1.5)
  end

  # Unison detune, kept to six cents (a frequency ratio of 0.0035) so the layers stay in tune.
  def detune = [(@profile["texture"] || {}).fetch("detune", 0.0), MAX_DETUNE].min

  # The tempo the profile plays at unless --bpm says otherwise.
  def bpm = @profile.fetch("bpm", 88.0)

  # Beats each chord holds unless --beats says otherwise: two bars of four.
  def beats = @profile.fetch("beats", 8.0)

  # Chords, each the same length, the odd ones swung late. A voice other than the plain sine, or
  # a list of voices (one for each chord, round and round), plays them through Voices instead.
  def render_chords(names, bpm, beats, search: true, strum: 0.0, voice: nil, voices: nil)
    voices ||= [voice] if voice && (voice["family"] != "sine" || @capture)
    return render_voiced_chords(names, bpm, beats, search:, strum:, voices:) if voices

    beat = 60.0 / bpm
    swing = @profile.fetch("swing", 0.5)
    buf = []
    Chords.freqs(names, search:, transpose: @transpose, wrap: @wrap).each_with_index do |freqs, idx|
      delay = [(idx.even? ? 0.0 : (swing - 0.5) * beat * @pd_amount) + chord_lean(idx, beat), 0.0].max
      pad = (delay * SAMPLE_RATE).to_i
      buf.concat(Array.new(pad, 0.0)) if pad > 0
      buf.concat(Synth.chord(freqs, beats * beat, detune:, strum:))
    end
    buf
  end

  # Held chords played by named voices: each note starts on its chord, the odd chords late by the
  # swing, and rings its full length with the voice's own release after it.
  def render_voiced_chords(names, bpm, beats, search:, strum:, voices:)
    beat = 60.0 / bpm
    swing = @profile.fetch("swing", 0.5)
    buf = Array.new((((names.size * beats * beat) + 1.5) * SAMPLE_RATE).to_i, 0.0)
    Chords.midi_notes(names, search:, transpose: @transpose, wrap: @wrap).each_with_index do |notes, idx|
      swung = idx.even? ? 0.0 : (swing - 0.5) * beat * @pd_amount
      start = [(idx * beats * beat) + swung + chord_lean(idx, beat), 0.0].max
      plucks = notes.each_with_index.map { |midi, k| Pluck.new(start + (k * strum), 0.0, midi, beats * beat, 1.0 / Math.sqrt(notes.size)) }
      sound(buf, plucks, voices[idx % voices.size])
    end
    buf
  end

  # An organ piece played by the organ voice: each line has its registration (the right hand's
  # changes with the phrase), its level and its gate, and every note leans from the grid by the
  # phrase's rubato, which pushes ahead through a phrase and relaxes into its cadence, never
  # past the clamp.
  def render_organ(piece, bpm, voice)
    config = @data.fetch("organ")
    step = 60.0 / bpm / 4.0
    buf = Array.new((((piece.steps * step) + 3.0) * SAMPLE_RATE).to_i, 0.0)
    piece.lines.each do |line, notes|
      notes.group_by(&:phrase).each do |index, group|
        phrase = piece.phrases.fetch(index)
        registration = voice.fetch("registrations").fetch(line == "right" ? phrase.registration : config.fetch("lines").fetch(line))
        plucks = group.map do |n|
          held = n.length * step * (n.length == 1 ? 0.8 : config.fetch("gates").fetch(line))
          Pluck.new(n.step * step, rubato(n.step, phrase, config), n.midi, held, n.gain * config.fetch("levels").fetch(line))
        end
        sound(buf, plucks, voice.merge("registration" => registration))
      end
    end
    buf
  end

  # How far a note at a step leans from the grid in seconds: early through the body of the
  # phrase, late as it closes.
  def rubato(step, phrase, config)
    limit = config.fetch("rubato_ms") / 1000.0
    u = ((step.to_f / Organ::BAR) - phrase.first_bar) / phrase.bars
    ((-0.4 * limit * Math.sin(Math::PI * u.clamp(0.0, 1.0))) + (u > 0.75 ? limit * (((u - 0.75) / 0.25)**2) : 0.0)).clamp(-MAX_OFFSET, MAX_OFFSET)
  end

  # The voice specs for a list of voice names, as the sequencer plays them.
  def voice_specs(flags) = flags.map { |flag| voice_spec(flag) }

  # The arp settings, or nil when neither a flag nor the profile asks for one. A style names a
  # row of arp.styles (a pattern, a rate in sixteenths, a gate, an octave span); the profile's
  # own keys and then the flags are laid over it.
  def arp_settings(flag, style: nil, rate: nil)
    spec = @profile["arp"]
    return unless flag || spec || style

    base = (@data["arp"] || {}).reject { |k, _| k == "styles" }
    name = style || spec&.fetch("style", nil)
    row = name ? (@data.dig("arp", "styles") || {}).fetch(name) { abort "No arp style: #{name}" } : {}
    settings = base.merge(row).merge((spec || {}).reject { |k, _| k == "style" })
    settings["style"] = name
    settings["pattern"] = flag if flag.is_a?(String)
    settings["pattern"] ||= settings.fetch("default_pattern")
    settings["rate"] = rate if rate
    abort "No arp pattern: #{settings['pattern']}" unless settings.fetch("patterns").include?(settings["pattern"])
    settings
  end

  # The chord-repeat settings: the whole voicing struck again on the steps of a style from
  # comp.styles. nil unless a flag or the profile asks.
  def comp_settings(flag)
    spec = @profile["repeat"]
    return unless flag || spec

    base = (@data["comp"] || {}).reject { |k, _| k == "styles" }
    name = flag.is_a?(String) ? flag : (spec&.fetch("style", nil) || base.fetch("default_style"))
    row = (@data.dig("comp", "styles") || {}).fetch(name) { abort "No repeat style: #{name}" }
    base.merge(row).merge((spec || {}).reject { |k, _| k == "style" }).merge("style" => name)
  end

  # The layers the profile plays beneath the part: nil when it names none.
  # A named [] keeps a deliberately sparse/specialist patch untouched; otherwise
  # profiles inherit the one shared accompaniment, so bare passes don't feel skeletal.
  def profile_layers = @profile.fetch("layers", @data.fetch("default_layers", nil))

  # The voice that plays the notes: the flag's, else the profile's, else the plain sine stack.
  def voice_spec(flag)
    name = flag || @profile["voice"] || "sine"
    row = @data.fetch("voices").fetch(name) { abort "No voice: #{name}" }
    return row.merge("name" => name) unless row["family"] == "fluid" && !Fluid.available?(row)

    fallback = row.fetch("fallback")
    @warned ||= {}
    warn "#{name}: #{Fluid.missing(row)}; playing #{fallback} instead" unless @warned[name]
    @warned[name] = true
    @data.fetch("voices").fetch(fallback).merge("name" => fallback)
  end

  # The Sonitex preset and instance count, or nil when neither a flag nor the profile asks.
  def sonitex_settings(flag, instances: nil)
    spec = @profile["sonitex"]
    return unless flag || spec

    table = @data.fetch("sonitex")
    name = flag.is_a?(String) ? flag : (spec&.fetch("preset", nil) || table.fetch("default"))
    { "name" => name, "preset" => table.fetch("presets").fetch(name) { abort "No sonitex preset: #{name}" },
      "instances" => instances || spec&.fetch("instances", nil) || table.fetch("instances", 1) }
  end

  # The nasty_vcs summing amount, or 0 when off.
  def vcs_amount(flag)
    return flag.to_f if flag.is_a?(Float)

    on = flag || @profile.key?("vcs")
    on ? (@profile["vcs"] || @data.fetch("nasty_vcs").fetch("amount")).to_f : 0.0
  end

  # The colour on the voice bus: Sonitex, then the summing colour.
  def colour(buf, sonitex, vcs)
    buf = Colour.sonitex(buf, sonitex.fetch("preset"), sonitex.fetch("instances"), @seed) if sonitex
    Colour.vcs(buf, vcs)
  end

  # Seconds each voice of a chord waits for the one below it: the flag's milliseconds, the data's when bare.
  def strum(flag)
    return 0.0 unless flag

    (flag == true ? @data.fetch("strum").fetch("ms") : flag) / 1000.0
  end

  # The echo settings with the flags laid over them, or nil when nothing asks for one.
  def echo_settings(flag: nil, mix: nil, feedback: nil, time_ms: nil)
    spec = @profile["echo"]
    return unless flag || spec

    settings = (@data["echo"] || {}).merge(spec || {})
    settings["heads"] = flag.split(",").map(&:to_i) if flag.is_a?(String)
    abort "No echo heads: #{settings['heads']}" unless settings.fetch("modes").include?(settings["heads"])
    settings["echo_volume"] = mix if mix
    settings["intensity"] = feedback if feedback
    settings["time_ms"] = time_ms if time_ms
    settings
  end

  # The chords one note at a time. Each note starts on its step, late by the profile's swing
  # on the off-beat steps, never moved past MAX_OFFSET; an optional soft pad plays beneath.
  # The notes of every chord as events, before any audio: the arp's one-note steps, or the
  # whole voicing struck on each 'x' of a 16-step pattern. Returns one pluck list per chord.
  def note_events(names, bpm, beats, settings, mode, search: true)
    step = 60.0 / bpm / 4.0
    accent = settings.fetch("accent", [1.0])
    chord_steps = (beats * 4).round
    Chords.midi_notes(names, search:, transpose: @transpose, wrap: @wrap).each_with_index.map do |voices, idx|
if mode == "arp" && settings["pattern"] == "flow"
  @walk = Flow::Walk.new(Zlib.crc32("#{@seed}:walk")) if idx.zero?
  @energies = [] if idx.zero?
  plucks, energies = Flow.chord_events(voices, index: idx, chord_steps:, step:, seed: @seed, walk: @walk, settings:,
                                               gate: settings.fetch("gate", 0.8))
  @energies.concat(energies)
  next modify(plucks, settings, idx, step * 2, 1.0, voices)
end
if mode == "arp"
  rate = settings.fetch("rate", 2).to_f
        pool = Arp.pool(voices, settings.fetch("octaves", 1))
        notes = Arp.sequence(settings.fetch("pattern"), pool, (chord_steps / rate).floor, Zlib.crc32("#{@seed}:#{idx}"))
        plucks = notes.each_with_index.filter_map do |midi, k|
          place((idx * chord_steps) + (k * rate), step, midi, rate * step * settings.fetch("gate", 0.8), accent[k % accent.size]) if midi
        end
        modify(plucks, settings, idx, rate * step, accent.max, pool)
      else
        pattern = settings.fetch("pattern")
        marks = (0...pattern.size).select { |i| pattern[i] == "x" }
        plucks = []
        (0...chord_steps).step(pattern.size) do |bar|
          marks.each_with_index do |m, j|
            next if bar + m >= chord_steps

            gap = (marks[j + 1] || (pattern.size + marks[0])) - m
            plucks << place((idx * chord_steps) + bar + m, step, voices, gap * step * settings.fetch("gate", 0.5), accent[plucks.size % accent.size])
          end
        end
        modify(plucks, settings, idx, step * 2, accent.max, voices)
      end
    end
  end

  def render_arp(names, bpm, beats, arp, search: true, pad: false, voice: nil)
    buf = Array.new(((((names.size * (beats * 4).round * 60.0 / bpm / 4.0)) + 1.0) * SAMPLE_RATE).to_i, 0.0)
    sound(buf, note_events(names, bpm, beats, arp, "arp", search:).flatten(1), voice || voice_spec(nil))
    if (pad || arp["pad_swell"]) && @capture
      swell = arp["pattern"] == "flow" ? [@energies, 60.0 / bpm * SAMPLE_RATE] : nil
      with_part(gain: arp.fetch("pad", 0.3), swell:) { render_chords(names, bpm, beats, search:, voice: voice_spec("sine")) }
    elsif pad || arp["pad_swell"]
      under = render_chords(names, bpm, beats, search:)
      under = Flow.swell(under, @energies, 60.0 / bpm * SAMPLE_RATE) if arp["pattern"] == "flow"
      under.each_with_index { |v, i| buf[i] += v * arp.fetch("pad", 0.3) if i < buf.size }
    end
    buf
  end

  # The whole voicing struck again on the steps of a style; a hit lasts the gate share of the
  # distance to the next one.
  def render_repeat(names, bpm, beats, comp, search: true, voice: nil)
    buf = Array.new(((((names.size * (beats * 4).round * 60.0 / bpm / 4.0)) + 1.0) * SAMPLE_RATE).to_i, 0.0)
    sound(buf, note_events(names, bpm, beats, comp, "repeat", search:).flatten(1), voice || voice_spec(nil))
    buf
  end

  # A note on its step: the profile's swing leans the off-beat steps late.
  def place(s, step, midi, dur, gain)
    pair = s.round % 4 == 2 ? 2 * step : (s.round.odd? ? step : 0.0)
    Pluck.new(s * step, (@profile.fetch("swing", 0.5) - 0.5) * 2 * pair * @pd_amount, midi, dur, gain)
  end

  def modify(plucks, settings, idx, slot, peak, tones)
    rng = Random.new(Zlib.crc32("#{@seed}:modifiers:#{idx}"))
    settings.fetch("modifiers", []).each do |name|
      plucks = Arp.modify(plucks, name, settings.fetch(name, {}).merge("tones" => tones), rng, slot:, peak:)
    end
    plucks
  end

  # Mix each pluck into the buffer through the voice; a chord's level is shared among its notes.
  def sound(buf, plucks, voice)
    return @capture << Part.new(plucks, voice, @part_gain || 1.0, @part_swell) if @capture
    return sound_soundfont(buf, plucks, voice) if voice["family"] == "fluid"

    step = @tempo && 15.0 / @tempo
    plucks.each do |p|
      notes = Array(p.midi)
      notes.each do |midi|
        samples = Voices.note(voice, midi, p.dur, 0.22 * p.gain / Math.sqrt(notes.size), velocity: p.gain, detune:,
                                                                                         step:, registration: voice["registration"])
        start = [((p.base + p.off.clamp(-MAX_OFFSET, MAX_OFFSET)) * SAMPLE_RATE).to_i, 0].max
        samples.each_with_index { |v, j| buf[start + j] += v if start + j < buf.size }
      end
    end
  end

  # The plucks played by a soundfont in one pass, its level set by the voice's gain.
  def sound_soundfont(buf, plucks, voice)
    level = 10.0**(voice.fetch("gain", 0.0) / 20.0)
    Fluid.render(plucks, voice).each_with_index { |v, i| buf[i] += v * level if i < buf.size }
  end

  # Echo on a buffer, the delay from the settings: milliseconds if given, else a number of beats.
  def echo(buf, settings, bpm, resets: [])
    delay = settings["time_ms"] ? settings["time_ms"] / 1000.0 : settings.fetch("time_beats") * 60.0 / bpm
    out = Echo.process(buf, delay:, heads: settings.fetch("heads"), intensity: settings.fetch("intensity"),
                            volume: settings.fetch("echo_volume"), lowpass: settings["lowpass"],
                            saturation: settings.fetch("saturation", 0.0), reverb: settings.fetch("reverb", 0.0),
                            tail: settings.fetch("tail", 4.0), resets:, send: throws(settings["throws"], bpm))
    peak = out.map(&:abs).max
    peak > 1.0 ? out.map { |v| v / peak } : out
  end

  # The send knob of a dub echo: a low `base` level, and in each phrase of `every_bars` bars one
  # bar (never the first, which the seed picks) turned up to `gain`, so a few stabs are thrown into
  # the tape and ring on over the quiet that follows. nil when the profile throws nothing.
  def throws(spec, bpm)
    return unless spec

    bar = (4 * 60.0 / bpm * SAMPLE_RATE).round
    every = spec.fetch("every_bars", 4)
    picked = Hash.new do |hash, phrase|
      hash[phrase] = (phrase * every) + 1 + Random.new(Zlib.crc32("#{@seed}:throw:#{phrase}")).rand([every - 1, 1].max)
    end
    ->(n) { picked[(n / bar) / every] == n / bar ? spec.fetch("gain", 2.0) : spec.fetch("base", 0.4) }
  end

  # Pattern names for each 4-bar phrase: one name, or a rotation that never plays the same
  # pattern twice running, drawn from the seed.
  def phrase_patterns(names, phrases)
    names = Array(names)
    rng = Random.new(Zlib.crc32("#{@seed}:phrases"))
    last = nil
    Array.new(phrases) do
      pick = names.size == 1 ? names.first : (names - [last]).sample(random: rng)
      last = pick
    end
  end

  # The rows of one bar: the pattern's, the phrase's variant over them, a fill on the last bar
  # of every fourth and eighth bar, then the seeded mutations and the snare density.
  def bar_rows(pattern, phrase, bar)
    rows = pattern.select { |k, v| v.is_a?(Array) && !%w[variants layers].include?(k) }.transform_values(&:dup)
    variants = pattern["variants"]
    if variants && !variants.empty?
      pick = Zlib.crc32("#{@seed}:variant:#{phrase}") % (variants.size + 1)
      rows.merge!(variants[pick - 1].transform_values(&:dup)) if pick.positive?
    end
    rows.merge!(pattern["fill"].transform_values(&:dup)) if pattern["fill"] && bar % 4 == 3
    rows.merge!(pattern["fill8"].transform_values(&:dup)) if pattern["fill8"] && bar % 8 == 7
    rng = Random.new(Zlib.crc32("#{@seed}:bar:#{bar}"))
    mutate(rows, rng) if bar.positive? && rng.rand < @profile.fetch("mutate", pattern.fetch("mutate", 0.0))
    thin(rows, pattern["odds"], rng) if pattern["odds"]
    kick_one = pattern["kick_on_one"]
    rows["kick"][0] = (rng.rand < kick_one ? 1.0 : 0.0) if kick_one && rows["kick"]
    add_snares(rows, @profile.fetch("snare_density", pattern.fetch("snare_density", 1.0)), rng)
    rows
  end

  # One change to a bar: swap two hits, shift one a sixteenth, add or drop a ghost, double a
  # kick, or rotate the hats. The kick on the downbeat stays where it is.
  def mutate(rows, rng)
    role = rows.keys.sample(random: rng)
    row = rows[role]
    hits = row.each_index.select { |i| hit?(row[i]) && !(role == "kick" && i.zero?) }
    case rng.rand(6)
    when 0
      a, b = hits.sample(2, random: rng)
      row[a], row[b] = row[b], row[a] if a && b && !(role == "kick" && (a.zero? || b.zero?))
    when 1
      i = hits.sample(random: rng)
      j = (i + (rng.rand < 0.5 ? 1 : -1)) % row.size if i
      (row[j] = row[i]; row[i] = 0) if i && !hit?(row[j]) && !(role == "kick" && j.zero?)
    when 2
      snare = rows["snare"] or return
      i = (0...snare.size).select { |k| !hit?(snare[k]) && k.odd? }.sample(random: rng)
      snare[i] = 0.4 if i
    when 3
      snare = rows["snare"] or return
      i = (0...snare.size).select { |k| hit?(snare[k]) && vel(snare[k]) < 0.7 }.sample(random: rng)
      snare[i] = 0 if i
    when 4
      kick = rows["kick"] or return
      i = (0...kick.size).select { |k| hit?(kick[k]) && !hit?(kick[(k + 1) % kick.size]) }.sample(random: rng)
      kick[(i + 1) % kick.size] = 0.6 if i
    else
      hat = rows["hat"] or return
      hat.rotate!(rng.rand < 0.5 ? 1 : 2)
    end
  end

  def hit?(cell) = vel(cell).positive?

  def vel(cell) = (cell.is_a?(Array) ? cell[0] : cell).to_f

  # Keep each hit of a role with the chance the pattern gives it.
  def thin(rows, odds, rng)
    odds.each do |role, chance|
      row = rows[role] or next
      row.each_index { |i| row[i] = 0 if hit?(row[i]) && rng.rand >= chance }
    end
  end

  # More back-beat snare: a density above one adds ghosts on steps nothing else uses.
  def add_snares(rows, density, rng)
    return unless density > 1.0 && rows["snare"]

    snare = rows["snare"]
    size = snare.size
    taken = rows.slice("kick", "snare", "clap").values.flat_map { |row| row.each_index.select { |i| hit?(row[i]) } }.uniq
    free = [3, 7, 10, 11, 14, 15, 2, 6].map { |i| i * size / 16 }.reject { |i| taken.include?(i) }.shuffle(random: rng)
    free.first(((density - 1.0) * 4).round).each { |i| snare[i] = 0.6 }
  end

  # Where every hit lands, in seconds: each 4-bar phrase plays a pattern (or the next of a
  # rotation), bar after bar until the chords end. Returns [[role, time, velocity]], earliest
  # first. A cell is a velocity from 0 to 1, or [velocity, count] for a ratchet; a layer is a
  # row of its own length that runs across the bars, so its alignment drifts against the grid.
  def drum_hits(pattern_name, bpm, seconds)
    names = Array(pattern_name)
    patterns = names.to_h { |n| [n, @data["drum_patterns"].fetch(n) { abort "No drum pattern: #{n}" }] }
    rng = Random.new(@seed)
    step = 60.0 / bpm / 4.0
    offsets = @profile["offsets"] || {}
    pocket = @profile["pocket"]
    swings = @profile["drum_swing"] || {}
    hits = []
    first_kick = true
    chosen = phrase_patterns(names, (seconds / (step * 64)).ceil)
    chosen.each_with_index do |name, phrase|
      pattern = patterns.fetch(name)
      size = pattern.fetch("steps", 16)
      drunk = pattern.fetch("drunk", @profile.fetch("drunk_amount", 0.0))
      cache = {}
      64.times do |g|
        abs = (phrase * 64) + g
        bar = abs / 16
        i = g % 16
        rows = (cache[bar] ||= bar_rows(pattern, phrase, bar))
        cells = rows.filter_map { |role, row| [role, row[g % size]] if hit?(row[g % size]) }
        (pattern["layers"] || []).each do |layer|
          cell = layer["hits"][abs % layer["length"]]
          cells << [layer["role"], cell] if hit?(cell)
        end
        cells.each do |role, cell|
          vel, count = cell.is_a?(Array) ? cell : [cell.to_f, 1]
          nudge = offsets.fetch(role, 0.0)
          nudge = pocket_lean(pocket, role:, step_in_bar: i, bar:) * step if pocket&.key?(role)
          if role == "kick" && first_kick
            nudge = offsets.fetch("kick_first", nudge) unless pocket&.key?(role)
            first_kick = false
          end
          amount = drunk.is_a?(Hash) ? drunk.fetch(role, 0.0) : drunk.to_f
          nudge += (rng.rand * 2 - 1) * MAX_OFFSET * amount
          # the off-beat eighth (step 2 of 4) and the odd sixteenths take the swing
          pair = i % 4 == 2 ? 2 * step : (i.odd? ? step : 0.0)
          late = (swings.fetch(role, 0.5) - 0.5) * 2 * pair
          # offset, swing and drunk together never move a hit more than MAX_OFFSET
          moved = ((nudge + late) * @pd_amount).clamp(-MAX_OFFSET, MAX_OFFSET)
          count.to_i.clamp(1, 6).times do |k|
            t = (abs * step) + moved + (k * step / count)
            hits << [role, [t, 0.0].max, vel * (1.0 - (0.12 * k))] if t < seconds
          end
        end
      end
    end
    hits.sort_by { |h| h[1] }
  end

  # How far a hit leans from its step, in sixteenths (before --groove). The draw belongs to
  # the render seed, the voice and the step in the bar, never the bar, so bars repeat.
  def pocket_lean(pocket, role:, step_in_bar:, bar: 0)
    spec = pocket.fetch(role)
    ghost = pocket["ghost"]
    spec = ghost if ghost && role == "snare" && !pocket.fetch("backbeat", []).include?(step_in_bar)
    return 0.0 if spec.fetch("anchor", []).include?(step_in_bar)

    draw = Random.new(Zlib.crc32("#{@seed}:#{role}:#{step_in_bar}")).rand * 2 - 1
    lean = spec.fetch("shift_steps", 0.0) + (spec.fetch("drift_steps", 0.0) * draw)
    lean + bar_drift(spec:, role:, step: step_in_bar, bar:)
  end

  # A hand that does not repeat: with `bar_drift_steps` the same hit leans a little differently every bar,
  # which a player's does and a pattern's does not. Absent, bars repeat as the first did.
  def bar_drift(spec:, role:, step:, bar:)
    amount = spec.fetch("bar_drift_steps", 0.0)
    return 0.0 if amount.zero?

    (Random.new(Zlib.crc32("#{@seed}:#{role}:#{step}:bar#{bar}")).rand * 2 - 1) * amount
  end

  # The chords sit on a grid of their own: `pocket.chord` { shift_steps, drift_steps } leans each chord from the
  # drums, in sixteenths of a beat's quarter, seeded per chord, never past MAX_OFFSET. Absent, they sit on the beat.
  def chord_lean(index, beat)
    spec = @profile.dig("pocket", "chord")
    return 0.0 unless spec

    draw = Random.new(Zlib.crc32("#{@seed}:chord:#{index}")).rand * 2 - 1
    lean = (spec.fetch("shift_steps", 0.0) + (spec.fetch("drift_steps", 0.0) * draw)) * beat / 4.0
    (lean * @pd_amount).clamp(-MAX_OFFSET, MAX_OFFSET)
  end

  # The mix levels in dB: the data's, the profile's over them, the flags over those.
  def mix(flags)
    (@data["mix"] || {}).merge(@profile["mix"] || {}).merge(flags || {}).tap do |levels|
      %w[kick snare clap hat perc chords echo].each { |k| levels[k] ||= 0.0 }
    end
  end

  def scale(buf, db)
    gain = 10.0**(db / 20.0)
    buf.map { |v| v * gain }
  end

  # The drums laid over the chords, each role at its mix level; the kick is added after the
  # duck, so the pump never touches it. With a summing colour the drums are a bus of their
  # own and the sum is coloured again; the sum never exceeds full scale.
  # The voices of the kit in use: the --kit flag's, else the profile's, else nil, which keeps
  # the three plain seeded voices.
  def kit_sounds
    name = @kit || @profile["kit"]
    name ? Percussion.kit(name, @data, @seed) : nil
  end

  def overlay_drums(chord_buf, hits, levels = {}, vcs = 0.0, sonitex: nil, tape: nil,
                    dub_echo: nil, crystallizer: nil, drum_vcs: nil)
    drum_vcs_amount = drum_vcs.nil? ? vcs : drum_vcs.to_f.clamp(0.0, 1.0)
    effects_on = sonitex || tape || dub_echo || crystallizer || drum_vcs_amount.positive? || vcs.positive? ||
                 @profile["drum_crush"] || @profile.dig("rumble", "amount")
    drum_bus = effects_on ? Array.new(chord_buf.size, 0.0) : nil
    out = drum_bus || chord_buf.dup
    kit = kit_sounds
    closers = hits.select { |r, *| r == "hat" }.map { |_, t, *| t }
    hits.each_with_index do |(role, time, strength), hit_index|
      # A fresh seeded voice per strike gives ghost notes and hats their own transient/noise;
      # a kit builds each role once.
      sample = kit ? kit[role] : Drums.new(@seed + ((hit_index + 1) * 104_729)).sounds[role]
      next unless sample

      # An open hat is choked by the next closed one.
      if kit && role == "open" && (nxt = closers.find { |t| t > time })
        sample = sample.first(((nxt - time) * SAMPLE_RATE).to_i)
        fade = [130, sample.size].min
        fade.times { |k| sample[sample.size - 1 - k] *= k / fade.to_f }
      end
      accent = strength.nil? ? 1.0 : strength.to_f.clamp(0.0, 1.0)
      gain = 0.8 * (10.0**(levels.fetch(role, 0.0) / 20.0)) * accent
      variation = case role
                  when "hat" then [0.68, 0.92, 0.76, 0.84][hit_index % 4]
                  when "snare" then hit_index.odd? ? 0.92 : 1.0
                  else hit_index.odd? ? 0.94 : 1.0
                  end
      sample.each_with_index do |value, j|
        idx = (time * SAMPLE_RATE).to_i + j
        break if idx >= out.size
        out[idx] += value * gain * variation
      end
    end
    if drum_bus && kit && @profile.dig("rumble", "amount")
      kicks = Array.new(out.size, 0.0)
      hits.each do |r, t, v|
        next unless r == "kick"

        kit["kick"].each_with_index do |x, j|
          i = (t * SAMPLE_RATE).to_i + j
          kicks[i] += x * (v || 1.0) if i < kicks.size
        end
      end
      Percussion.rumble(kicks).each_with_index { |x, i| out[i] += x * @profile.dig("rumble", "amount") }
    end
    if drum_bus && (crush = @profile["drum_crush"])
      out = Colour.crush(out, crush.fetch("bits"), 1.0 / crush.fetch("rate"))
      drum_bus = out
    end
    if drum_bus
      drums = if sonitex
                Colour.sonitex(drum_bus, sonitex.fetch("preset"), sonitex.fetch("instances"), @seed + 1)
              else
                drum_bus
              end
      tape_amount = case tape
                    when "heavy" then 1.0
                    when "medium" then 0.65
                    when "light" then 0.35
                    else tape.nil? ? 0.0 : tape.to_f
                    end
      drums = Colour.tape(drums, amount: tape_amount) if tape_amount.positive?
      drums = FX.dub_echo(drums, dub_echo) if dub_echo
      drums = FX.crystallizer(drums, crystallizer) if crystallizer
      drums = Colour.vcs(drums, drum_vcs_amount) if drum_vcs_amount.positive?

      # Wet buses can outlive the chord buffer; retain the full dub/crystal tail in the mix.
      length = [chord_buf.size, drums.size].max
      out = Array.new(length, 0.0)
      chord_buf.each_with_index { |sample, i| out[i] += sample }
      drums.each_with_index { |sample, i| out[i] += sample }
      out = Colour.vcs(out, vcs * 0.5) if vcs.positive?
    end
    peak = out.map(&:abs).max || 0.0
    peak > 1.0 ? out.map { |v| Colour.soft_limit(v) } : out
  end

  # The chords duck on every kick: a gain envelope keyed to the hits, not an oscillator.
  def duck(chord_buf, hits)
    sc = @profile["sidechain"] or return chord_buf
    amount = sc.fetch("amount", 0.0) * @pd_amount
    release = sc.fetch("release", 0.15) * SAMPLE_RATE
    return chord_buf if amount.zero?

    gain = Array.new(chord_buf.size, 1.0)
    hits.each do |role, time|
      next unless role == "kick"

      start = (time * SAMPLE_RATE).to_i
      (0...(release * 4).to_i).each do |n|
        idx = start + n
        break if idx >= gain.size
        g = 1.0 - amount * Math.exp(-n / release)
        gain[idx] = g if g < gain[idx]
      end
    end
    chord_buf.each_with_index.map { |s, i| s * gain[i] }
  end
end

# --- midi.rb ---
# ------------------------------------------------------------------- MIDI
# A Standard MIDI File, format 0: the chords on channel 1 and the drums on channel 10
# (kick 36, snare 38, hat 42). Times are the same ones the WAV uses.
module MIDI
  PPQN = 480
  DRUM_NOTES = { "kick" => 36, "snare" => 38, "hat" => 42 }.freeze

  def self.vlq(number)
    bytes = [number & 0x7f]
    while (number >>= 7).positive?
      bytes.unshift((number & 0x7f) | 0x80)
    end
    bytes.pack("C*")
  end

  # A Standard MIDI File of notes on one channel, for a soundfont to play: each note is
  # [start seconds, length seconds, midi note, velocity]. The file runs at 120 beats a minute,
  # so a second is 960 ticks, and ends `tail` seconds after the last note so the soundfont's
  # releases are rendered before it stops.
  def self.write_notes(path, notes, program:, bank: 0, tail: 2.5, replace: false)
    ticks = ->(seconds) { (seconds * 2 * PPQN).round }
    events = notes.flat_map do |start, length, midi, velocity|
      [[ticks.call(start), 0x90, midi, velocity.clamp(1, 127)], [ticks.call(start + length), 0x80, midi, 0]]
    end
    ending = events.map(&:first).max.to_i + ticks.call(tail)
    track = "\x00\xFF\x51\x03".b + [500_000].pack("N")[1, 3]
    track << "\x00\xB0\x00".b << [bank].pack("C") << "\x00\xC0".b << [program].pack("C")
    last = 0
    events.sort_by { |tick, status, *| [tick, status & 0xf0 == 0x80 ? 0 : 1] }.each do |tick, status, note, vel|
      track << vlq(tick - last) << [status, note, vel].pack("C3")
      last = tick
    end
    track << vlq(ending - last) << "\xFF\x2F\x00".b
    WAV.write_bytes(path, "MThd".b + [6, 0, 1, PPQN].pack("Nnnn") + "MTrk".b + [track.bytesize].pack("N") + track, replace:)
  end

  def self.write(path, names, bpm, beats, hits, search: true, replace: false)
    ticks = ->(seconds) { (seconds * bpm / 60.0 * PPQN).round }
    chord_len = (beats * PPQN).round
    events = []
    Chords.midi_notes(names, search:).each_with_index do |notes, idx|
      notes.each do |n|
        events << [idx * chord_len, 0x90, n, 80]
        events << [(idx + 1) * chord_len, 0x80, n, 0]
      end
    end
    hits.each do |role, time|
      on = ticks.call(time)
      events << [on, 0x99, DRUM_NOTES.fetch(role), 100]
      events << [on + 30, 0x89, DRUM_NOTES.fetch(role), 0]
    end
    track = "\x00\xFF\x51\x03".b + [(60_000_000 / bpm).round].pack("N")[1, 3]
    last = 0
    events.sort_by { |tick, status, *| [tick, status & 0xf0 == 0x80 ? 0 : 1] }.each do |tick, status, note, vel|
      track << vlq(tick - last) << [status, note, vel].pack("C3")
      last = tick
    end
    track << "\x00\xFF\x2F\x00".b
    header = "MThd".b + [6, 0, 1, PPQN].pack("Nnnn")
    WAV.write_bytes(path, header + "MTrk".b + [track.bytesize].pack("N") + track, replace:)
  end
end

# --- fluid.rb ---
# ----------------------------------------------------------------- soundfont
# Strings, choir and warm pads that Ruby does not synthesise are played by the fluidsynth binary
# from a soundfont: the notes of a part are written as a Standard MIDI File, fluidsynth renders
# it with its own reverb and chorus off (the chorus is a modulation), and the wav is read back to
# be mixed in before the effects. Where the binary or the soundfont is missing the voice says so
# and the voice named as its fallback plays instead, and the rotation leaves it out.
module Fluid
  BINARIES = ["/opt/homebrew/bin/fluidsynth", "/usr/local/bin/fluidsynth", "/usr/bin/fluidsynth"].freeze
  FONT_GLOB = "Downloads/pub3-main*/multimedia/dilla/tools/instruments/soundfonts"
  CACHE_DIR = ".cache/dilla-soundfonts"
  DEFAULT_FONTS = %w[FluidR3_GM.sf2 GeneralUser-GS.sf2].freeze # the first is the one the folder was meant to hold
  GAIN = 0.6
  TIMEOUT = 180

  def self.binary
    ENV.fetch("DILLA_FLUIDSYNTH", nil)&.then { |path| return path if File.executable?(path) }
    BINARIES.find { |path| File.executable?(path) } ||
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, "fluidsynth") }.find { |path| File.executable?(path) }
  end

  # A soundfont is a RIFF file that says how long it is; a download cut short says so too, and
  # fluidsynth only fails on it at render time.
  def self.whole?(path)
    return false unless File.file?(path)

    head = File.binread(path, 12).to_s
    head.byteslice(8, 4) == "sfbk" && head.byteslice(4, 4).unpack1("V") + 8 == File.size(path)
  end

  # DILLA_SOUNDFONT names one file for the default voices; otherwise the first whole file of the
  # names, looked for in the soundfont folder of the download, then in the cache folder.
  def self.soundfont(names = DEFAULT_FONTS)
    names = Array(names)
    given = ENV.fetch("DILLA_SOUNDFONT", nil)
    return (whole?(given) ? given : nil) if given && names == DEFAULT_FONTS

    folders = Dir.glob(File.join(Dir.home, FONT_GLOB)).sort + [File.join(Dir.home, CACHE_DIR)]
    folders.product(names).map { |folder, name| File.join(folder, name) }.find { |path| whole?(path) }
  end

  def self.available?(spec = {}) = !binary.nil? && !soundfont(spec.fetch("soundfont", DEFAULT_FONTS)).nil?

  # Why a fluid voice cannot play, in words, or nil when it can.
  def self.missing(spec = {})
    return "the fluidsynth binary was not found" unless binary

    names = Array(spec.fetch("soundfont", DEFAULT_FONTS))
    soundfont(names) ? nil : "no whole soundfont among #{names.join(', ')} (DILLA_SOUNDFONT names one)"
  end

  # The argv for one render: no shell sees it.
  def self.command(wav, font, midi) = [binary, "-ni", "-F", wav, "-r", SAMPLE_RATE.to_s, "-g", GAIN.to_s, "-R", "0", "-C", "0", font, midi]

  # Mono samples of the plucks played by the voice's program, from time zero, with the
  # soundfont's releases after the last note. A chord pluck sounds every note it holds.
  def self.render(plucks, spec)
    font = soundfont(spec.fetch("soundfont", DEFAULT_FONTS)) or raise ArgumentError, missing(spec)
    notes = plucks.flat_map do |p|
      start = [p.base + p.off.clamp(-MAX_OFFSET, MAX_OFFSET), 0.0].max
      Array(p.midi).map { |midi| [start, p.dur, midi, (30 + (97 * p.gain.clamp(0.0, 1.0))).round] }
    end
    return [] if notes.empty?

    Dir.mktmpdir("dilla-fluid") do |dir|
      midi = File.join(dir, "part.mid")
      wav = File.join(dir, "part.wav")
      MIDI.write_notes(midi, notes, program: spec.fetch("program"), bank: spec.fetch("bank", 0))
      run(command(wav, font, midi), dir)
      read(wav)
    end
  end

  def self.run(argv, dir)
    log = File.join(dir, "fluidsynth.log")
    pid = Process.spawn(*argv, in: File::NULL, out: log, err: [:child, :out])
    status = Timeout.timeout(TIMEOUT) { Process.wait2(pid).last }
    raise "fluidsynth failed: #{File.read(log).lines.last(3).join.strip}" unless status.success?
  rescue Timeout::Error
    Process.kill("KILL", pid)
    Process.wait(pid)
    raise "fluidsynth timed out"
  end

  # A 16-bit PCM wav of one or two channels, mixed down to mono.
  def self.read(path)
    bytes = File.binread(path)
    raise "fluidsynth wrote no wav" unless bytes.byteslice(0, 4) == "RIFF" && bytes.byteslice(8, 4) == "WAVE"

    channels = bits = rate = nil
    pos = 12
    while pos + 8 <= bytes.bytesize
      id = bytes.byteslice(pos, 4)
      size = bytes.byteslice(pos + 4, 4).unpack1("V")
      body = pos + 8
      if id == "fmt "
        _format, channels, rate, _byte_rate, _align, bits = bytes.byteslice(body, 16).unpack("vvVVvv")
      elsif id == "data"
        raise "fluidsynth wrote #{bits}-bit audio" unless bits == 16
        raise "fluidsynth wrote #{rate} Hz, not #{SAMPLE_RATE}" unless rate == SAMPLE_RATE

        frames = bytes.byteslice(body, [size, bytes.bytesize - body].min).unpack("s<*")
        return frames.each_slice(channels).map { |frame| frame.sum / (32_768.0 * channels) }
      end
      pos = body + size + (size.odd? ? 1 : 0)
    end
    raise "fluidsynth wrote no audio"
  end
end

# --- playlist.rb ---
class Bag
  def initialize(items, rng, state = nil)
    @items = items
    @rng = rng
    @remaining = (state&.fetch("remaining", nil) || []).select { |i| items.include?(i) }
    @last = state&.fetch("last", nil)
  end

  def draw
    if @remaining.empty?
      @remaining = @items.shuffle(random: @rng)
      @remaining.rotate! if @remaining.size > 1 && @remaining.first == @last
    end
    @last = @remaining.shift
  end

  def position = "#{@items.size - @remaining.size}/#{@items.size}"

  def to_h = { "remaining" => @remaining, "last" => @last }
end

# A bag whose neighbours never share a key: the order of each cycle is a shuffle in which no two
# items side by side, and not the first after the last of the cycle before, have the same key.
# The state keeps the last item, so a restart goes on from it.
class SpacedBag < Bag
  TRIES = 200

  def initialize(items, rng, state = nil, key:)
    super(items, rng, state)
    @key = key
  end

  def draw
    @remaining = arrangement if @remaining.empty?
    @last = @remaining.shift
  end

  private

  def arrangement
    before = @last && @key.call(@last)
    TRIES.times do
      order = @items.shuffle(random: @rng)
      return order if spaced?(order, before)
    end
    greedy(before)
  end

  def spaced?(order, before) = order.first.then { |first| @key.call(first) != before } && order.each_cons(2).none? { |a, b| @key.call(a) == @key.call(b) }

  # When a shuffle never works (one key holds more than half the items) the key with the most
  # left goes next, so the repeats come as far apart as they can.
  def greedy(before)
    pool = @items.shuffle(random: @rng).group_by(&@key)
    order = []
    until pool.empty?
      pick = pool.reject { |key, _| key == before }.max_by { |_, rows| rows.size } || pool.first
      before = pick.first
      order << pick.last.shift
      pool.delete(before) if pick.last.empty?
    end
    order
  end
end

# What each pass draws, every kind from its own bag: the progression from the whole array, the
# mode, the arp or repeat style, the patch, the treatment.
class Playlist
  MODES = %w[arp repeat pad organ].freeze

  def initialize(data, rng, state = {}, pool: "essential")
    @data = data
    @pool = pool
    @rng = rng
    @state = state
    @bags = {}
  end

  def bag(key, items, spaced_by: nil)
    @bags[key] ||= spaced_by ? SpacedBag.new(items, @rng, @state[key], key: spaced_by) : Bag.new(items, @rng, @state[key])
  end

  # The progressions --play draws from: the essential staples, or the whole array.
  def progression_pool
    @pool == "all" ? (0...@data.fetch("progressions").size).to_a : @data.fetch("essential")
  end

  # The voices the rotation may play: every row, except a soundfont voice on a machine that
  # has no soundfont, which would only be its fallback sounding under another name.
  def voice_names = @data.fetch("voices").reject { |_, row| row["family"] == "fluid" && !Fluid.available?(row) }.keys.sort

  def voices_by_group = voice_names.group_by { |name| group_of(name) }

  # The group of a patch is what the ear calls its kind: the moogs, the polysynth pads, the strings.
  def group_of(voice) = @data.fetch("voices").fetch(voice).fetch("group")

  # The next voice from the one bag that holds every patch: a patch comes back only after all the
  # others have played, and a group never follows itself.
  def next_voice = bag("voices", voice_names, spaced_by: method(:group_of)).draw

  # `count` voices in a row, one for each chord of a pad, from the same bag.
  def voices_for(count) = Array.new(count) { next_voice }

  def draw(fixed = {})
    index = bag("progressions", progression_pool).draw
    position = @bags["progressions"].position
    mode = fixed[:mode] || bag("modes", MODES).draw
    style = case mode
            when "arp" then bag("styles:arp", @data.dig("arp", "play_styles")).draw
            when "repeat" then bag("styles:repeat", @data.fetch("comp").fetch("styles").keys).draw
            end
    voices = fixed[:patch_per_chord] && mode == "pad" && !fixed[:voice] ? voices_for(@data.fetch("progressions").fetch(index).size) : nil
    organ = mode == "organ" && !fixed[:voice]
    voice = fixed[:voice] || voices&.first || (organ ? "organ" : next_voice)
    profile = fixed[:profile] || bag("profiles", @data.fetch("play_profiles")).draw
    kit = bag("kits", @data.fetch("kits").keys).draw
    drums = bag("drums", @data.fetch("drum_patterns").keys).draw
    { prog: index, position:, mode:, style:, voice:, voices:, bag: (organ || fixed[:voice] ? nil : bag_position("voices")), profile:, kit:, drums: }
  end

  def bag_position(key) = @bags[key]&.position

  def to_h = @bags.transform_values(&:to_h)
end

# Never stops: each pass draws from the playlist, renders while the one before plays, and
# plays it when that ends. Two files alternate, so the one being played is never the one being
# written; the bags are saved beside them, so a restart goes on with the cycle.

# --- streamer.rb ---
# ----------------------------------------------------------------- streamer
# One pass rendered a block at a time instead of whole. The plan is the same one a whole render
# makes, with the notes kept and not yet sounded; the streamer sounds each note when its block comes
# up, reading it a block at a time so that its oscillators and filters carry on where they stopped,
# and sends the sum through the effects as stateful processors, in this order: colour, echo, the
# chords' level, the kick's duck, the texture, then the drums over them. A pass cut into blocks of
# any size gives the same samples, within float rounding, as one block.
#
# Stereo by default: each note is panned by its voice's group and by where it lies on the
# keyboard, each drum by its role, the colour and the room run once for each channel with
# decorrelated delays on the right, and the echo is ping-pong. `mono: true` runs one channel and
# gives a flat array.
#
# The source fades out over its last beats and in over its first, equal power, so one pass can
# begin under the end of another; the echo and the room keep ringing after the source stops, up to
# the echo's tail.
class Streamer
  attr_reader :plan, :position, :total, :source_end, :fade_out, :beat, :channels, :hits
  # Live moves: the drums' level (0 for a dropout) and the echo's send boost.
  attr_accessor :drums_gain

  # `fade_in` is a number of samples, `fade_out_beats` a number of this pass's beats.
  # `ring` lets the last notes ring out after the pass's end, for a render that stands alone.
  def initialize(data, options, fade_in: 0, fade_out_beats: 0, play_tail: true, ring: false)
    @data = data
    @options = options
    @channels = options[:mono] ? 1 : 2
    @plan = plan_pass(data, options, capture: true)
    @seq = @plan.seq
    @bpm = @plan.bpm
    @position = 0
    @drums_gain = 1.0
    @ahead = Stereo.zeros(@channels, 0)
    @beat = (60.0 / @bpm * SAMPLE_RATE).round
    @source_end = (@plan.names.size * @plan.beats * @beat).round # whole beats of whole samples, so a join falls on a bar line
    @fade_in = fade_in
    @fade_out = (fade_out_beats * @beat).round
    @ring = ring
    build_source
    build_chain
    build_drums
    build_noise
    @total = @source_end + (play_tail ? @tail : 0)
    @total = [@total, @source_end + (1.5 * SAMPLE_RATE).round].max if ring # the longest release of a voice
  end

  def silent_after_source? = @position >= @source_end

  # Seconds the pass plays before its tail.
  def seconds = @source_end / SAMPLE_RATE.to_f

  # The next `count` samples, fewer at the end of the pass: an array for one channel, [left, right]
  # for two.
  def next_block(count)
    frame = take(count)
    @channels == 1 ? frame.first : frame
  end

  # Render the first `count` samples now and hand them out when asked: a deck prepared while
  # the other one plays.
  def prefetch(count)
    Stereo.concat!(@ahead, render_block([count, @total - @position].min)) unless @position >= @total
  end

  def echo_boost=(factor)
    @echo&.boost = factor
  end

  def echo_boost = @echo ? @echo.boost : 1.0

  # Whether anything of the pass is rendered and not yet handed out.
  def finished? = @position >= @total && @ahead.first.empty?

  private

  def take(count)
    have = @ahead.first.size
    return Stereo.shift!(@ahead, count) if have >= count

    frame = Stereo.shift!(@ahead, have)
    count -= have
    return frame if count <= 0 || @position >= @total

    Stereo.concat!(frame, render_block(count))
  end

  def render_block(count)
    count = [count, @total - @position].min
    return Stereo.zeros(@channels, 0) if count <= 0

    from = @position
    dry = fade(@bank.block(from, count, @channels), from)
    wet = add_noise(chain(dry, from), from)
    @position += count
    wet
  end

  # One processor for each channel; the block receives the channel number.
  def pair
    Stream::Pair.new(*Array.new(@channels) { |c| yield c })
  end

  # ------------------------------------------------------------- the source
  def build_source
    entries = []
    stems = []
    pans = @data.fetch("stereo")
    @plan.parts.each do |part|
      group = part.voice["group"] || "sine"
      centre = pans.fetch("groups").fetch(group, 0.0)
      if part.voice["family"] == "fluid"
        level = 10.0**(part.voice.fetch("gain", 0.0) / 20.0)
        stems << [Fluid.render(part.plucks, part.voice), level * part.gain, centre]
        next
      end
      swell = part.swell && swell_proc(*part.swell)
      step = 15.0 / @bpm
      part.plucks.each do |p|
        notes = Array(p.midi)
        notes.each do |midi|
          start = [((p.base + p.off.clamp(-MAX_OFFSET, MAX_OFFSET)) * SAMPLE_RATE).to_i, 0].max
          make = lambda do
            Voices.cached_reader(part.voice, midi, p.dur, 0.22 * p.gain / Math.sqrt(notes.size), velocity: p.gain, detune: @seq.detune,
                                                                                           step:, registration: part.voice["registration"])
          end
          entries << Stream::Bank::Entry.new(start, make, part.gain, swell, note_pan(centre, midi, pans))
        end
      end
    end
    stems.each { |samples, level, centre| entries << Stream::Bank::Entry.new(0, -> { Voices::Reader.of(samples) }, level, nil, centre) }
    @bank = Stream::Bank.new(entries)
  end

  # A voice group's place, and a spread of the notes across it by pitch: the low notes stay near
  # the middle, the high ones go out. Static, so a note keeps its place for its whole life.
  def note_pan(centre, midi, pans)
    reach = ((midi - 60) / 24.0).clamp(-1.0, 1.0)
    reach *= pans.fetch("low_reach") if midi < pans.fetch("low_below")
    (centre + (pans.fetch("spread") * reach)).clamp(-1.0, 1.0)
  end

  # The pad that swells with the energy: linear between the beats' levels, from a quarter to full.
  def swell_proc(energies, beat_samples)
    return ->(_at) { 1.0 } if energies.nil? || energies.empty?

    lambda do |at|
      pos = at.to_f / beat_samples
      a = energies[[pos.floor, energies.size - 1].min]
      b = energies[[pos.floor + 1, energies.size - 1].min]
      0.25 + (0.75 * (a + ((b - a) * (pos - pos.floor))))
    end
  end

  # Equal-power fades at the ends of the source, and silence after its end.
  def fade(frame, from)
    return frame if @fade_in.zero? && @fade_out.zero? && (@ring || from + frame.first.size <= @source_end)

    frame.map do |channel|
      channel.each_with_index.map do |v, i|
        at = from + i
        gain = 1.0
        gain = Math.sin(Math::PI / 2 * at / @fade_in) if at < @fade_in
        if at >= @source_end then gain = @ring ? gain : 0.0
        elsif @fade_out.positive? && at >= @source_end - @fade_out then gain *= Math.cos(Math::PI / 2 * (at - (@source_end - @fade_out)) / @fade_out)
        end
        v * gain
      end
    end
  end

  # ------------------------------------------------------------- the effects
  def build_chain
    options = @options
    seq = @seq
    seed = @plan.seed
    @vcs = seq.vcs_amount(options[:vcs])
    sonitex = seq.sonitex_settings(options[:sonitex], instances: options[:sonitex_instances])
    @sonitex = sonitex && pair { |c| Stream::SonitexStack.new(sonitex.fetch("preset"), sonitex.fetch("instances"), seed + (c * 104_729)) }
    @drum_sonitex_settings = seq.sonitex_settings(options[:drum_sonitex], instances: options[:drum_sonitex_instances]) || sonitex
    @colour_vcs = pair { Stream::Vcs.new(@vcs) }
    echo = seq.echo_settings(flag: options[:echo], mix: options[:echo_mix], feedback: options[:echo_feedback], time_ms: options[:echo_time])
    echo["tail"] = options[:echo_tail] if echo && options[:echo_tail]
    echo["reverb"] = options[:echo_reverb] unless !echo || options[:echo_reverb].nil?
    @echo = echo && echo_line(echo)
    @tail = echo ? (echo.fetch("tail", 4.0) * SAMPLE_RATE).to_i : 0
    texture = @plan.profile_row["texture"] || {}
    @texture = [pair { Stream::Lowpass.new(texture["lowpass"]) },
                pair { |c| Stream::Reverb.new(texture["reverb"], side: c.zero? ? :left : :right) },
                pair { |c| Stream::Spring.new(texture["spring"], side: c.zero? ? :left : :right) }]
    @stages = Array(@plan.profile_row["chain"]).map do |row|
      Stages.build(row, @data.fetch("stages"), channels: @channels, seed:, end_sample: @source_end, bar_samples: @beat * 4)
    end
  end

  def echo_line(settings)
    delay = settings["time_ms"] ? settings["time_ms"] / 1000.0 : settings.fetch("time_beats") * 60.0 / @bpm
    resets = (1...@plan.names.size).map { |i| (i * @plan.beats * 60.0 / @bpm * SAMPLE_RATE).round }
    args = { delay:, heads: settings.fetch("heads"), intensity: settings.fetch("intensity"), volume: settings.fetch("echo_volume"),
             lowpass: settings["lowpass"], saturation: settings.fetch("saturation", 0.0), reverb: settings.fetch("reverb", 0.0),
             resets:, send: @seq.throws(settings["throws"], @bpm) }
    @channels == 1 ? Stream::EchoLine.new(**args) : Stream::PingPongEcho.new(**args)
  end

  def chain(dry, from)
    out = @sonitex ? @sonitex.process(dry) : dry
    out = @colour_vcs.process(out)
    out = @stages.inject(out) { |frame, stage| stage.process(frame, from) }
    out = echoed(out) if @echo
    out = out.map { |channel| channel.map { |v| v * @chords_gain } } if @chords_gain
    out = out.map { |channel| @duck.apply(channel, from) } if @duck
    out = @texture.inject(out) { |frame, stage| stage.process(frame) }
    @hits.empty? ? out : mix_drums(out, from)
  end

  def echoed(frame) = @channels == 1 ? [@echo.process(frame.first)] : @echo.process(frame)

  # ------------------------------------------------------------- noise and sparkle
  # The layers a profile names under `noise`, over the defaults in the data: air, the bed, dust,
  # and the sparkle with its own echo, ducked by the kick.
  def build_noise
    rows = @plan.profile_row["noise"] || {}
    defaults = @data.fetch("noise")
    seed = @plan.seed
    wanted = lambda do |name|
      row = rows[name]
      row ? defaults.fetch(name).merge(row.is_a?(Hash) ? row : {}) : nil
    end
    seconds = (@source_end + @tail) / SAMPLE_RATE.to_f
    air = wanted.call("air")
    bed = wanted.call("bed")
    @air = air && Array.new(@channels) { |c| Noise::Air.new(air, Zlib.crc32("#{seed}:air:#{c}")) }
    @bed = bed && Array.new(@channels) { |c| Noise::Bed.new(bed, Zlib.crc32("#{seed}:bed:#{c}")) }
    dust = wanted.call("dust")
    @dust_bank = dust && Stream::Bank.new(Noise.dust(dust, Zlib.crc32("#{seed}:dust"), seconds))
    sparkle = wanted.call("sparkle")
    return unless sparkle

    pcs = Chords.midi_notes(@plan.names, search: @plan.search).map { |notes| notes.map { |n| n % 12 }.uniq }
    chord_seconds = @plan.beats * 60.0 / @bpm
    chord_at = ->(t) { pcs[[(t / chord_seconds).floor, pcs.size - 1].min] }
    @sparkle_bank = Stream::Bank.new(Noise.sparkle(sparkle, Zlib.crc32("#{seed}:sparkle"), seconds, chord_at))
    kicks = @hits.select { |r, _| r == "kick" }.map { |_, t| t }
    @sparkle_duck = kicks.empty? ? nil : Stream::Duck.new(kicks, sparkle.fetch("duck", 0.85), 0.12)
    echo = sparkle["echo"]
    return unless echo

    args = { delay: echo.fetch("beats", 0.75) * 60.0 / @bpm, heads: echo.fetch("heads", [1, 2]), intensity: echo.fetch("intensity", 0.55), volume: echo.fetch("volume", 0.7),
             lowpass: echo.fetch("lowpass", 5000), saturation: 0.1 }
    @sparkle_echo = @channels == 1 ? Stream::EchoLine.new(**args) : Stream::PingPongEcho.new(**args)
  end

  def add_noise(frame, from)
    return frame unless @air || @bed || @dust_bank || @sparkle_bank

    count = frame.first.size
    layers = []
    layers << Array.new(@channels) { |c| @air[c].block(count) } if @air
    layers << Array.new(@channels) { |c| @bed[c].block(count) } if @bed
    layers << @dust_bank.block(from, count, @channels) if @dust_bank
    if @sparkle_bank
      glints = @sparkle_bank.block(from, count, @channels)
      glints = glints.map { |channel| @sparkle_duck.apply(channel, from) } if @sparkle_duck
      glints = @channels == 1 ? [@sparkle_echo.process(glints.first)] : @sparkle_echo.process(glints) if @sparkle_echo
      layers << glints
    end
    layers.each { |layer| Stereo.add!(frame, layer) }
    frame
  end

  # ------------------------------------------------------------- the drums
  def build_drums
    seq = @seq
    options = @options
    drums = @plan.drums
    rotation = drums == "rotate" ? @data.fetch("drum_patterns").keys : drums
    @hits = drums ? seq.drum_hits(rotation, @bpm, @source_end / SAMPLE_RATE.to_f) : []
    @levels = seq.mix(options[:mix])
    @chords_gain = @hits.empty? ? nil : 10.0**(@levels.fetch("chords") / 20.0)
    # a profile's own pump, else the master's light duck: the instruments give way to the kick
    sidechain = @plan.profile_row["sidechain"] || (options[:master] == false ? nil : @data.dig("master", "duck"))
    amount = sidechain ? sidechain.fetch("amount", 0.0) * seq.pd_amount : 0.0
    @duck = sidechain && !amount.zero? ? Stream::Duck.new(@hits.select { |r, _| r == "kick" }.map { |_, t| t }, amount, sidechain.fetch("release", 0.15)) : nil
    return if @hits.empty?

    kit = seq.kit_sounds
    @drum_bank = Stream::Bank.new(drum_entries(kit))
    crush = @plan.profile_row["drum_crush"]
    @drum_crush = crush && pair { Stream::Crush.new(crush.fetch("bits"), 1.0 / crush.fetch("rate")) }
    @rumble_amount = kit && @plan.profile_row.dig("rumble", "amount")
    @rumble = rumble_chain(kit) if @rumble_amount
    drum_sonitex = @drum_sonitex_settings
    @drum_sonitex = drum_sonitex && pair { |c| Stream::SonitexStack.new(drum_sonitex.fetch("preset"), drum_sonitex.fetch("instances"), @plan.seed + 1 + (c * 104_729)) }
    drum_vcs = options[:drum_vcs].nil? ? @vcs : options[:drum_vcs].to_f.clamp(0.0, 1.0)
    @drum_vcs = pair { Stream::Vcs.new(drum_vcs) }
    @master_vcs = pair { Stream::Vcs.new(@vcs * 0.5) }
    @separate_bus = @drum_sonitex || @vcs.positive? || @drum_crush || @rumble
  end

  def drum_entries(kit)
    closers = @hits.select { |r, *| r == "hat" }.map { |_, t, *| t }
    drum_pans = @data.fetch("stereo").fetch("drums")
    @hits.each_with_index.filter_map do |(role, time, strength), hit_index|
      make = lambda do
        sample = kit ? kit[role] : Drums.new(@plan.seed + ((hit_index + 1) * 104_729)).sounds[role]
        if sample && kit && role == "open" && (nxt = closers.find { |t| t > time })
          sample = sample.first(((nxt - time) * SAMPLE_RATE).to_i)
          fade = [130, sample.size].min
          fade.times { |k| sample[sample.size - 1 - k] *= k / fade.to_f }
        end
        Voices::Reader.of(sample || [])
      end
      next if kit && kit[role].nil?

      accent = strength.nil? ? 1.0 : strength.to_f.clamp(0.0, 1.0)
      variation = case role
                  when "hat" then [0.68, 0.92, 0.76, 0.84][hit_index % 4]
                  when "snare" then hit_index.odd? ? 0.92 : 1.0
                  else hit_index.odd? ? 0.94 : 1.0
                  end
      gain = 0.8 * (10.0**(@levels.fetch(role, 0.0) / 20.0)) * accent * variation
      lean = %w[hat open perc shaker].include?(role) && hit_index.odd? ? -0.12 : 0.0 # the hats alternate a little
      Stream::Bank::Entry.new((time * SAMPLE_RATE).to_i, make, gain, nil, drum_pans.fetch(role, 0.0) + lean)
    end
  end

  # The drums enter at equal power over the crossfade, and a dropout holds them at nothing, with
  # ten milliseconds to get there and back so it does not click.
  def drum_level(frame, from)
    ramp = (0.01 * SAMPLE_RATE).round
    target = @drums_gain
    previous = @drums_applied || target
    @drums_applied = target
    return frame if @fade_in.zero? && target == 1.0 && previous == 1.0 && from >= @fade_in

    frame.map do |channel|
      channel.each_with_index.map do |v, i|
        at = from + i
        gain = at < @fade_in ? Math.sin(Math::PI / 2 * at / @fade_in) : 1.0
        level = i < ramp ? previous + ((target - previous) * i / ramp) : target
        v * gain * level
      end
    end
  end

  # The low end grown from the kicks: a room, a lowpass, drive, two more lowpasses, scaled by a
  # fixed gain found once from a single kick, where a whole render scales by its own peak. It is
  # mono, the same in both channels.
  def rumble_chain(kit)
    build = -> { [Stream::Reverb.new(0.8), Stream::SmoothLowpass.new(180.0), Stream::SmoothLowpass.new(110.0), Stream::SmoothLowpass.new(110.0)] }
    run = lambda do |stages, block|
      room, first, second, third = stages
      third.process(second.process(Percussion.dirt(first.process(room.process(block)), 0.55)))
    end
    one = kit["kick"] + Array.new(SAMPLE_RATE * 2, 0.0)
    peak = run.call(build.call, one).map(&:abs).max.to_f
    @rumble_scale = peak.zero? ? 1.0 : 0.6 / peak
    @rumble_run = run
    @rumble_stages = build.call
    kicks = @hits.each_with_object([]) { |(role, t, v), list| list << [(t * SAMPLE_RATE).to_i, kit["kick"], v || 1.0] if role == "kick" }
    @kick_bank = Stream::Bank.new(kicks.map { |start, sample, v| Stream::Bank::Entry.new(start, -> { Voices::Reader.of(sample) }, v, nil, nil) })
  end

  def mix_drums(chords, from)
    count = chords.first.size
    drums = drum_level(@drum_bank.block(from, count, @channels), from)
    if @separate_bus
      if @rumble
        grown = @rumble_run.call(@rumble_stages, @kick_bank.block(from, count, 1).first)
        drums = drums.map { |channel| channel.each_with_index.map { |v, i| v + (grown[i] * @rumble_scale * @rumble_amount) } }
      end
      drums = @drum_crush.process(drums) if @drum_crush
      drums = @drum_sonitex.process(drums) if @drum_sonitex
      drums = @drum_vcs.process(drums)
      out = chords.each_with_index.map { |channel, c| channel.each_with_index.map { |v, i| v + drums[c][i] } }
      out = @master_vcs.process(out)
    else
      out = chords.each_with_index.map { |channel, c| channel.each_with_index.map { |v, i| v + drums[c][i] } }
    end
    out.map { |channel| channel.map { |v| Colour.soft_limit(v) } }
  end
end

# --- player.rb ---
# ------------------------------------------------------------------ player
# Raw 16-bit mono PCM written to the stdin of a player. The player is an argv, never a shell
# string; a pipe that closes under us (the listener quit the player) ends the show quietly and
# does not raise.
class Player
  FFPLAY = ["/opt/homebrew/bin/ffplay", "/usr/local/bin/ffplay", "/usr/bin/ffplay"].freeze
  SOX = ["/opt/homebrew/bin/play", "/usr/local/bin/play", "/usr/bin/play"].freeze

  # The player: --player's command split into words, else ffplay, else sox's play.
  def self.command(options, rate = SAMPLE_RATE)
    channels = options[:mono] ? 1 : 2
    return Shellwords.split(options[:player]) if options[:player]

    ffplay = FFPLAY.find { |path| File.executable?(path) } || which("ffplay")
    # -ch_layout, not -ac: ffplay 8 refuses -ac on raw input ("Option not found"), the
    # player exits at launch, and -loglevel quiet leaves the show ending with no reason.
    layout = channels == 1 ? "mono" : "stereo"
    return [ffplay, "-nodisp", "-autoexit", "-loglevel", "quiet", "-f", "s16le", "-ar", rate.to_s, "-ch_layout", layout, "-i", "-"] if ffplay

    play = SOX.find { |path| File.executable?(path) } || which("play")
    return [play, "-q", "-t", "raw", "-r", rate.to_s, "-e", "signed", "-b", "16", "-c", channels.to_s, "-"] if play

    abort "No player: install ffplay or sox, or name one with --player (it reads raw 16-bit mono PCM on stdin)"
  end

  def self.which(name) = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }.find { |path| File.executable?(path) }

  # 16-bit little-endian samples, clipped; a stereo frame ([left, right]) is interleaved.
  def self.pcm(samples)
    samples = Stereo.interleave(samples) if samples.first.is_a?(Array)
    samples.map { |s| (s * 32_767).round.clamp(-32_768, 32_767) }.pack("s<*")
  end

  attr_reader :bytes

  def initialize(argv)
    @io = IO.popen(argv, "wb")
    @pid = @io.pid
    @open = true
    @bytes = 0
  end

  def open? = @open

  # Hand over a block; false when the player has gone.
  def write(samples)
    return false unless @open

    data = Player.pcm(samples)
    @io.write(data)
    @io.flush
    @bytes += data.bytesize
    true
  rescue Errno::EPIPE, IOError
    @open = false
  end

  # End the input, give the player a moment to play out what it holds, then stop it.
  def finish(grace: 5.0)
    @io.close unless @io.closed?
  rescue Errno::EPIPE, IOError
    nil
  ensure
    @open = false
    wait(grace)
  end

  # Tell the player to stop, from a signal handler: nothing is waited for, and a write that is
  # blocked on a full pipe fails with EPIPE and so comes back.
  def interrupt
    Process.kill("TERM", @pid)
  rescue Errno::ESRCH
    nil
  end

  # Stop now.
  def kill
    @open = false
    Process.kill("TERM", @pid)
  rescue Errno::ESRCH
    nil
  ensure
    begin
      @io.close unless @io.closed?
    rescue Errno::EPIPE, IOError
      nil
    end
    wait(2.0)
  end

  private

  def wait(grace)
    Timeout.timeout(grace) { Process.wait(@pid) }
  rescue Timeout::Error
    begin
      Process.kill("KILL", @pid)
      Process.wait(@pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
  rescue Errno::ECHILD
    nil
  end
end

# --- moves.rb ---
# ------------------------------------------------------------------ moves
# The hand on the desk. A few times a minute, at a bar, one live move is made: the echo is thrown,
# a filter sweeps down and back, the tape is driven harder, the Sonitex climbs from one pass to
# three and down, the room swells, or the drums drop out for a bar. A move is an event with
# a start and a length in bars, not an oscillator; it is drawn from its own seeded stream so
# that it never disturbs the draws of the passes, it is logged, and when it ends the
# parameter it moved is put back exactly.
module Moves
  NAMES = %w[echo_throw filter_sweep tape_ramp sonitex_climb reverb_swell drum_dropout].freeze
  BARS = { "echo_throw" => 1, "filter_sweep" => 3, "tape_ramp" => 3, "sonitex_climb" => 5, "reverb_swell" => 3, "drum_dropout" => 1 }.freeze
  GAP_SECONDS = 6 # at least this long between the end of one move and the start of the next
  THROW = 3.5
  TOP_HZ = 16_000.0
  LOW_HZ = 700.0
  TAPE_PUSH = 1.0
  ROOM_LEVEL = 0.5

  # The master stage after the decks are summed. A frame is [mono] or [left, right]. In order:
  # the moves (sweep, Sonitex, room), the stereo imager (the low end centred, the highs widened, the
  # mid untouched), the mastering chain (EQ, multiband, parallel, glue, level, soft clip), the tape
  # stack on the mid with a light one on the side, and last the true-peak limiter. Nothing of the
  # moves is in the path unless a move asks for it. With no chain the old ceiling stands in for the
  # limiter. `tape` is a stack, or a proc that makes one from a stretch of the programme.
  class Master
    attr_reader :chain

    def initialize(tape:, ceiling:, preset:, seed:, instances: 0, tape_args: {}, imager: {}, chain: nil)
      @tape = tape
      @tape_args = tape_args
      @instances = instances
      @side_tape = nil
      @ceiling = ceiling
      @preset = preset
      @seed = seed
      @imager = imager
      @chain = chain
      @built = nil
    end

    def bpm=(bpm)
      @chain&.bpm = bpm
    end

    # `params`: cutoff [from, to], sonitex n, room [from, to], tape factor.
    def process(frame, params = {})
      build(frame.size)
      frame = frame.each_with_index.map { |channel, c| @sweeps[c].process(channel, *params[:cutoff]) } if params[:cutoff]
      if params[:sonitex]
        @climbs ||= Array.new(frame.size) { |c| Stream::SonitexClimb.new(@preset, @seed + (c * 7)) }
        frame = frame.each_with_index.map { |channel, c| @climbs[c].process(channel, params[:sonitex]) }
      end
      if params[:room]
        @rooms ||= Array.new(frame.size) { |c| Stream::RoomSend.new(0.8, side: c.zero? ? :left : :right) }
        frame = frame.each_with_index.map { |channel, c| @rooms[c].process(channel, *params[:room]) }
      else
        @rooms = nil
      end
      frame = @imaging.process(frame) if @imaging
      frame = @chain.process(frame) if @chain
      frame = colour(frame, params.fetch(:tape, 1.0))
      @chain ? @chain.limit(frame) : frame.map { |channel| Tape.ceiling(channel, top: @ceiling) }
    end

    # What the limiter is still holding when the signal ends.
    def flush
      return unless @chain && @built

      @chain.limit(Stereo.zeros(@built, @chain.latency + 2))
    end

    private

    def build(channels)
      return if @built == channels

      @built = channels
      @sweeps = Array.new(channels) { Stream::SweepLowpass.new }
      @climbs = nil
      @imaging = channels == 2 && @imager ? Stream::Imager.new(**@imager.transform_keys(&:to_sym)) : nil
    end

    def colour(frame, factor)
      return frame unless @tape || @instances.positive?

      if @tape.respond_to?(:call)
        @tape = @tape.call(Tape.excerpt(Stereo.fold(frame)))
      end
      @tape.drive_scale = factor
      if frame.size == 1
        [@tape.process(frame.first)]
      else
        @side_tape ||= Tape::Stack.new(instances: 1, seed: @seed + 1, cheap: true, **@tape_args)
        mid, side = Stereo.mid_side(frame)
        @side_tape.drive_scale = factor
        Stereo.left_right(@tape.process(mid), @side_tape.process(side))
      end
    end
  end

  # Decides when a move starts and what it does to the decks and the master for each block.
  class Hand
    attr_reader :log, :current

    # `per_minute` moves on average; 0 never moves.
    def initialize(seed, per_minute:, out: nil)
      @rng = Random.new(Zlib.crc32("#{seed}:moves"))
      @per_minute = per_minute.to_f
      @out = out
      @log = []
      @current = nil
      @last = nil
      @quiet_until = 0
      @saved = {}
    end

    # Called for each block before it is rendered. `decks` are the streamers sounding, `overlap` is
    # true while two passes are being crossed. Returns the master's parameters for this block.
    def advance(global, size, bar, decks, overlap: false)
      finish(decks, global) if @current && global >= @current[:start] + @current[:length]
      begin_move(global, size, bar, decks) if @current.nil? && !overlap && global >= @quiet_until
      return {} unless @current

      at = ->(g) { ((g - @current[:start]).to_f / @current[:length]).clamp(0.0, 1.0) }
      params(at.call(global), at.call(global + size), decks)
    end

    # End a move in progress and put everything back (the show is over, or a test is done).
    def stop(decks, global = 0)
      finish(decks, global) if @current
    end

    private

    def begin_move(global, size, bar, decks)
      return if @per_minute <= 0

      return unless @rng.rand < @per_minute * (size.to_f / SAMPLE_RATE) / 60.0

      name = (NAMES - [@last]).sample(random: @rng)
      bars = BARS.fetch(name)
      @current = { name:, start: global, length: bars * bar, bars: }
      @last = name
      @log << [name, global, bars]
      @out&.puts("move: #{name} for #{bars} bar#{'s' unless bars == 1} at #{(global.to_f / SAMPLE_RATE).round(1)}s")
      case name
      when "echo_throw"
        decks.each { |d| (@saved[d.object_id] ||= {})[:boost] = d.echo_boost; d.echo_boost = THROW }
      when "drum_dropout"
        decks.each { |d| (@saved[d.object_id] ||= {})[:drums] = d.drums_gain; d.drums_gain = 0.0 }
      end
    end

    def finish(decks, global)
      decks.each do |d|
        saved = @saved.delete(d.object_id) or next
        d.echo_boost = saved[:boost] if saved.key?(:boost)
        d.drums_gain = saved[:drums] if saved.key?(:drums)
      end
      @saved.clear
      @quiet_until = global + (GAP_SECONDS * SAMPLE_RATE)
      @current = nil
    end

    # The shape of a move over its length: 0 at the ends, 1 in the middle, held there a while.
    def tent(p) = p < 1.0 / 3 ? p * 3 : (p < 2.0 / 3 ? 1.0 : (1.0 - p) * 3)

    def params(p0, p1, _decks)
      case @current[:name]
      when "filter_sweep"
        cutoff = ->(p) { TOP_HZ * ((LOW_HZ / TOP_HZ)**tent(p)) }
        { cutoff: [cutoff.call(p0), cutoff.call(p1)] }
      when "tape_ramp" then { tape: 1.0 + (TAPE_PUSH * tent((p0 + p1) / 2)) }
      when "sonitex_climb" then { sonitex: [1, 2, 3, 2, 1][([(p0 + p1) / 2 * 5, 4.999].min).floor] }
      when "reverb_swell" then { room: [ROOM_LEVEL * tent(p0), ROOM_LEVEL * tent(p1)] }
      else {}
      end
    end
  end
end

# --- show.rb ---
# -------------------------------------------------------------------- show
# --play: passes drawn from the bags, each streamed block by block into the player. With two
# decks, deck B is built, and its first bars rendered, while deck A plays; when A has played its
# eight to sixteen bars B comes in under it, equal power, over two to four bars that begin on A's bar
# line, B's tempo within six beats of A's. The drums keep running: A's go on to the end of its last bar
# and B's come in with the crossfade. With one deck the crossfade is a single beat and every pass is
# its own length. A few times a minute a live move is made (see Moves). The master stage runs
# once over the sum, so a join does not restart it.
class Show
  Slot = Struct.new(:streamer, :start)

  FIRST_BLOCK_BEATS = 1 # the first block is one beat, so the music starts before a bar is ready
  SECOND_BLOCK_BEATS = 3 # the rest of the first bar, so the blocks after it fall on bar lines
  BLOCK_BEATS = 4        # then one bar at a time
  LOOKAHEAD = 2          # blocks rendered ahead of the one being played
  TEMPO_WINDOW = 6.0     # beats a minute either side of the deck that plays
  PASS_BARS = (8..16)
  CROSSFADE_BARS = (2..4)
  MOVES_PER_MINUTE = 3.0

  attr_reader :stats, :joins, :streamers, :hand, :crossfades

  def initialize(data, options, player:, out: $stdout)
    @data = data
    @options = options
    @player = player
    @out = out
    @decks = options.fetch(:decks, 2)
    @rng = Random.new(options[:seed] || Random.new_seed)
    @mix_rng = Random.new(Zlib.crc32("#{options[:seed]}:mix"))
    @dir = options[:out] ? File.dirname(options[:out]) : "out/play"
    FileUtils.mkdir_p(@dir)
    @state_path = File.join(@dir, "play_state.json")
    state = (JSON.parse(File.read(@state_path)) rescue {})
    @playlist = Playlist.new(data, @rng, state, pool: options[:pool] || "essential")
    @passes = options[:passes] || Float::INFINITY
    @made = 0
    @stop = false
    @joins = [0]
    @crossfades = []
    @streamers = []
    @last_bpm = nil
    @stats = { blocks: 0, audio: 0.0, render: 0.0, underruns: 0 }
    tape = data.fetch("tape")
    instances = options.fetch(:tape, tape.fetch("instances"))
    stack = instances.positive? ? Tape::Stack.new(instances:, drive: options[:tape_drive] || tape.fetch("drive"), seed: options[:seed] || 0, config: tape) : nil
    preset = data.dig("sonitex", "presets").fetch(data.dig("sonitex", "default"))
    channels = options[:mono] ? 1 : 2
    chain = options[:master] == false ? nil : Mastering::Chain.new(data.fetch("master"), channels:)
    chain&.target = options[:lufs] if options[:lufs]
    @master = Moves::Master.new(tape: stack, ceiling: tape.fetch("ceiling", 0.97), preset:, seed: options[:seed] || 0, instances:,
                                tape_args: { drive: options[:tape_drive] || tape.fetch("drive"), config: tape },
                                imager: options[:mono] ? nil : data.dig("stereo", "imager"), chain:)
    @dither = Mastering::Dither.new(options[:seed] || 0)
    per_minute = options.fetch(:moves, @decks > 1 ? MOVES_PER_MINUTE : 0.0)
    @hand = Moves::Hand.new(options[:seed] || 0, per_minute:, out:)
  end

  # Ask the show to end after the block in hand, and the player to stop so that a write
  # blocked on a full pipe comes back.
  def stop!
    @stop = true
    @player.interrupt
  end

  def run
    queue = SizedQueue.new(LOOKAHEAD)
    producer = Thread.new { produce(queue) }
    producer.report_on_exception = false
    interrupted = false
    began = nil
    written = 0
    loop do
      starved = queue.empty?
      block = queue.pop(timeout: 0.25)
      if block.nil?
        (interrupted = true) && break if @stop
        next
      end
      break if block == :done

      began ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
      # late: the player had played everything we gave it and we had nothing more
      @stats[:underruns] += 1 if starved && written.positive? && Process.clock_gettime(Process::CLOCK_MONOTONIC) - began > written.to_f / SAMPLE_RATE
      break unless @player.write(block)

      written += block.size
    end
    interrupted ||= @stop
    @stop = true
    queue.clear
    producer.join(10)
    interrupted ? @player.kill : @player.finish
  ensure
    producer&.kill
  end

  private

  # A pass drawn from the bags. `fade_in` samples, and `fade_out_beats` of this pass's own beats.
  def build_pass(fade_in, fade_out_beats, prefetch: 0)
    @made += 1
    pick = @playlist.draw(mode: @options[:mode], voice: @options[:voice], profile: @options[:profile], patch_per_chord: @options[:patch_per_chord])
    pass = pass_options(pick, @made)
    @out.puts pass_line(pick, pass, @made)
    File.write(@state_path, JSON.generate(@playlist.to_h))
    Streamer.new(@data, pass, fade_in:, fade_out_beats:).tap do |streamer|
      @last_bpm = streamer.plan.bpm
      streamer.prefetch(prefetch) if prefetch.positive?
      @streamers << streamer
    end
  end

  def pass_options(pick, number)
    data = @data
    options = @options
    pass = options.merge(prog: pick[:prog], seed: @rng.rand(1_000_000), profile: pick[:profile], voice: pick[:voice],
                         mode: pick[:mode], random: false, quick: false, play: false)
    pass[:chord_voices] = pick[:voices] if pick[:voices]
    pass[:arp_style] = options[:arp_style] || pick[:style] if pick[:mode] == "arp"
    pass[:repeat] = options[:repeat] || pick[:style] if pick[:mode] == "repeat"
    profile_row = data["groove_profiles"].fetch(pick[:profile])
    pass[:drums] = options[:drums] == "rotate" ? pick[:drums] : (options[:drums] || profile_row["drums"])
    pass[:kit] = options[:kit] || (options[:drums] == "rotate" ? pick[:kit] : profile_row["kit"])
    pass[:pass] = number
    fit_to_deck(pass, pick) if @decks > 1
    pass
  end

  # A deck's pass lasts eight to sixteen bars, whatever the progression's length, and keeps its
  # tempo within the window of the deck before it.
  def fit_to_deck(pass, pick)
    profile = @data["groove_profiles"].fetch(pick[:profile])
    bars = @mix_rng.rand(PASS_BARS)
    beats = pass[:beats] || profile.fetch("beats", 8.0)
    pass[:bars] = bars
    chords = (bars * 4.0 / beats).round.clamp(2, 16)
    progression = @data.fetch("progressions").fetch(pick[:prog])
    pass[:names] = Array.new(chords) { |i| progression[i % progression.size] }
    bpm = pass[:bpm] || profile.fetch("bpm", 88.0)
    pass[:bpm] = bpm.clamp(@last_bpm - TEMPO_WINDOW, @last_bpm + TEMPO_WINDOW) if @last_bpm
  end

  def pass_line(pick, pass, number)
    "pass #{number}: progression #{pick[:prog]} (#{pick[:position]}) mode=#{pick[:mode]} style=#{pick[:style] || '-'} " \
      "voice=#{pick[:voices]&.join('>') || pick[:voice]} (patch #{pick[:bag] || 'fixed'}) profile=#{pick[:profile]} " \
      "drums=#{Array(pass[:drums]).join(',').then { |d| d.empty? ? '-' : d }} kit=#{pass[:kit] || '-'}" \
      "#{" bpm=#{pass[:bpm]}" if pass[:bpm]}"
  end

  # Beats the crossfade after a pass lasts: whole bars of two to four with two decks, one beat with one.
  def crossfade_beats = @decks > 1 ? @mix_rng.rand(CROSSFADE_BARS) * 4 : 1

  def produce(queue)
    channels = @options[:mono] ? 1 : 2
    first_fade = crossfade_beats
    slots = [Slot.new(build_pass(0, first_fade), 0)]
    @crossfades << first_fade
    upcoming = prepare(slots.last, first_fade)
    global = 0
    openers = [slots.first.streamer.beat * FIRST_BLOCK_BEATS, slots.first.streamer.beat * SECOND_BLOCK_BEATS]
    until @stop || slots.empty?
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      slots, upcoming = admit(slots, upcoming, global, join_at(slots))
      bar = slots.last.streamer.beat * BLOCK_BEATS
      size = openers.shift || bar
      due = join_at(slots)
      size = [size, due - global].min if upcoming && due > global

      params = @hand.advance(global, size, bar, slots.map(&:streamer), overlap: slots.size > 1)
      mixed = Stereo.zeros(channels, size)
      slots.each do |slot|
        offset = [slot.start - global, 0].max
        next if offset >= size

        part = slot.streamer.next_block(size - offset)
        Stereo.add!(mixed, channels == 1 ? [part] : part, offset)
      end
      @master.bpm = slots.last.streamer.plan.bpm
      slots.reject! { |slot| slot.streamer.finished? }
      mixed = @dither.process(@master.process(mixed, params))
      mixed = mixed.first if channels == 1
      spent = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      @stats[:render] += spent
      keep_up(spent / (size.to_f / SAMPLE_RATE))
      @stats[:audio] += size.to_f / SAMPLE_RATE
      @stats[:blocks] += 1
      queue << mixed
      global += size
    end
    @hand.stop(slots.map(&:streamer), global)
    queue << :done
  rescue StandardError => e
    @out.puts "show: #{e.class}: #{e.message}"
    queue << :done
  end

  # The cost of a block against its length, smoothed: past nine tenths the master's dear stages go and the show says so.
  def keep_up(ratio)
    @pace = @pace ? (@pace * 0.8) + (ratio * 0.2) : ratio
    chain = @master.chain
    return unless chain && !chain.light? && @pace > @options.fetch(:pace, 0.9) && @stats[:blocks] > 4

    chain.lighten!
    @out.puts format("master: lightened, the show was rendering at %.2fx real time", @pace)
  end

  # Build the next pass on a thread while this one plays, its first bars rendered ahead so that a
  # crossfade costs no more than a pass alone.
  def prepare(slot, fade_beats)
    return if @made >= @passes

    fade_in = fade_beats * slot.streamer.beat
    next_fade = crossfade_beats
    Thread.new do
      streamer = build_pass(fade_in, next_fade, prefetch: fade_in + (slot.streamer.beat * BLOCK_BEATS))
      [streamer, next_fade]
    end
  end

  # The sample at which the next pass begins: where the pass in hand starts its fade-out.
  def join_at(slots)
    last = slots.last
    last.start + last.streamer.source_end - last.streamer.fade_out
  end

  def admit(slots, upcoming, global, due)
    return [slots, upcoming] unless upcoming && due <= global

    streamer, next_fade = upcoming.value
    @joins << due
    @crossfades << next_fade
    fresh = Slot.new(streamer, due)
    [slots + [fresh], prepare(fresh, next_fade)]
  end
end

# --- video.rb ---
module Dilla
  # Offline MP4 export. The waveform is drawn over an architectural grid and
  # the canonical Postpro video recipe adds the shared film treatment.
  module Video
    class Error < StandardError; end

    WIDTH = 1280
    HEIGHT = 720
    FPS = 30
    ENCODER_TIMEOUT = 900
    PROBE_TIMEOUT = 15
    VIDEO_RECIPE = File.expand_path("../postpro/video.yml", __dir__).freeze
    FILTER_VALUE = /\A[a-zA-Z0-9_=@.,: +()\/'-]+\z/.freeze

    module_function

    # The short command renders one fixed pair beside dilla.rb and replaces it on
    # every run: a render is replaceable, and no new file or folder appears.
    def default_paths(root:, output_dir: ENV["DILLA_OUTPUT_DIR"])
      base = File.expand_path(output_dir.to_s.empty? ? root : output_dir)
      { audio: File.join(base, "dilla.wav"), video: File.join(base, "dilla.mp4") }.freeze
    end

    def paired_path(audio)
      path = File.expand_path(audio.to_s)
      return path.sub(/\.(?:wav|wave)\z/i, ".mp4") if path.match?(/\.(?:wav|wave)\z/i)

      "#{path}.mp4"
    end

    def available? = !executable("ffmpeg").nil?

    def encoder_available?
      binary = executable("ffmpeg")
      return false unless binary

      stdout, _stderr, status = Studio::Subprocess.capture3(
        binary, "-hide_banner", "-encoders", timeout: [command_timeout, PROBE_TIMEOUT].min
      )
      status.success? && stdout.include?("libx264")
    rescue StandardError
      false
    end

    def render(audio:, output:, preset: "dilla_heavy", replace: false)
      source = File.expand_path(audio.to_s)
      target = File.expand_path(output.to_s)
      raise Error, "WAV source is missing or empty: #{source}" unless File.file?(source) && File.size(source).positive?
      raise Error, "refusing to overwrite existing MP4 #{target}" if occupied?(target) && !replace

      binary = executable("ffmpeg")
      raise Error, "ffmpeg unavailable; WAV is safe, MP4 was not produced" unless binary

      filters = postpro_filters(preset)
      FileUtils.mkdir_p(File.dirname(target))
      temporary = File.join(
        File.dirname(target),
        ".#{File.basename(target, ".mp4")}.#{Process.pid}.#{Thread.current.object_id}.tmp.mp4",
      )
      command = [
        binary, "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
        "-i", source,
        "-filter_complex", filter_graph(filters),
        "-map", "[v]", "-map", "0:a:0",
        "-c:v", "libx264", "-preset", "medium", "-crf", "19",
        "-pix_fmt", "yuv420p", "-r", FPS.to_s,
        "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart",
        "-shortest", temporary
      ]
      _stdout, stderr, status = Studio::Subprocess.capture3(*command, timeout: command_timeout)
      unless status.success? && File.file?(temporary) && File.size(temporary).positive?
        detail = stderr.to_s.lines.last(5).join.strip
        raise Error, "ffmpeg exit=#{status.exitstatus}: #{detail.empty? ? "no diagnostic output" : detail}"
      end

      # link() is atomic and refuses an occupied destination. Replacing an existing
      # take is possible only when the operator explicitly passed --replace.
      if replace
        File.rename(temporary, target)
      else
        File.link(temporary, target)
        File.delete(temporary)
      end
      puts format("studio0: wrote %s (1280x720, %d fps, %s)", target, FPS, preset)
      target
    rescue Error
      raise
    rescue StandardError => e
      raise Error, "#{e.class}: #{e.message}"
    ensure
      begin
        File.delete(temporary) if temporary && File.exist?(temporary)
      rescue SystemCallError
        nil
      end
    end

    def command_timeout
      value = Integer(ENV.fetch("DILLA_FFMPEG_TIMEOUT", ENCODER_TIMEOUT.to_s), 10)
      raise Error, "DILLA_FFMPEG_TIMEOUT must be 1..3600 seconds" unless value.between?(1, 3600)

      value
    rescue ArgumentError, TypeError
      raise Error, "DILLA_FFMPEG_TIMEOUT must be an integer from 1 to 3600"
    end

    def postpro_filters(preset)
      return [] if ENV["DILLA_VIDEO_POSTPRO"] == "0"

      data = YAML.safe_load(File.read(VIDEO_RECIPE), permitted_classes: [], aliases: false)
      filters = data.fetch("presets").fetch(preset.to_s) do
        raise Error, "unknown video preset #{preset.inspect} in #{VIDEO_RECIPE}"
      end.fetch("filters")
      filters.map do |value|
        filter = value.to_s
        raise Error, "unsafe character in Postpro filter #{filter.inspect}" unless FILTER_VALUE.match?(filter)

        # FFmpeg's filter-graph grammar requires quoting the space-separated tmix weights.
        filter.gsub(/weights=([0-9]+(?:\s+[0-9]+)+)/) { "weights='#{$1}'" }
      end
    rescue KeyError => e
      raise Error, "video recipe is incomplete: #{e.message}"
    end

    def filter_graph(postpro = [])
      background = [
        "color=c=0x07101b:s=#{WIDTH}x#{HEIGHT}:r=#{FPS}",
        "drawgrid=width=80:height=80:thickness=1:color=0x203b56@0.55",
        "drawbox=x=52:y=48:w=1176:h=624:color=0x7298bd@0.65:t=1",
        "drawbox=x=116:y=108:w=1048:h=504:color=0x203b56@0.95:t=1[base]",
      ].join(",")
      wave = "[0:a]showwaves=s=#{WIDTH}x390:mode=cline:rate=#{FPS}:colors=0x8de1ff," \
             "format=rgba,colorkey=black:0.05:0.02[wave]"
      composite = "[base][wave]overlay=0:165:shortest=1:format=auto"
      composite += ",#{postpro.join(",")}" unless postpro.empty?
      "#{background};#{wave};#{composite},format=yuv420p[v]"
    end

    def occupied?(path) = File.exist?(path) || File.symlink?(path)

    def executable(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
        path = File.join(directory, name)
        return path if File.file?(path) && File.executable?(path)
      end
      nil
    end
    private_class_method :occupied?, :executable
  end
end

# --- reference.rb ---
# Import and inspect the audio stream of a reference. Video frames are never read.
module Dilla
  module Reference
    ROOT = File.expand_path("..", __dir__).freeze
    REFERENCE_ROOT = Studio::OutputPaths.reference_root.freeze
    MAX_DURATION = 7_200
    DEFAULT_DURATION = 900
    # libsonare decodes full files into memory, so keep this optional pass short.
    LIBSONARE_MAX_DURATION_SECONDS = 900
    VIDEO_ID = /\A[A-Za-z0-9_-]{11}\z/.freeze
    class Error < StandardError; end
    module_function

    def run(argv)
      options = { stems: true, model: "htdemucs", max_duration: DEFAULT_DURATION, style: "general", libsonare: true }
      OptionParser.new do |parser|
        parser.banner = "Usage: ruby dilla.rb reference YOUTUBE_URL_OR_AUDIO [options]"
        parser.on("--out DIR") { |value| options[:out] = value }
        parser.on("--no-stems") { options[:stems] = false }
        parser.on("--no-libsonare", "Skip optional libsonare analysis") { options[:libsonare] = false }
        parser.on("--model NAME") { |value| options[:model] = value }
        parser.on("--style NAME") { |value| options[:style] = style_key(value) }
        parser.on("--max-duration SECONDS", Integer) do |value|
          raise OptionParser::InvalidArgument, "duration must be 1..#{MAX_DURATION}" unless value.between?(1, MAX_DURATION)
          options[:max_duration] = value
        end
        parser.on("-h", "--help") { puts parser; return 0 }
      end.parse!(argv)
      source = argv.shift
      raise Error, "provide one YouTube video URL or a local audio file" if source.to_s.empty?
      raise Error, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?
      source.start_with?("http://", "https://") ? download_audio(source, options) : analyze(File.expand_path(source), nil, options)
    rescue OptionParser::ParseError, Error => error
      warn "reference0: #{error.message}"
      2
    rescue StandardError => error
      warn "reference0: failed safely (#{error.class}: #{error.message})"
      1
    end

    def parse_url(value)
      uri = URI.parse(value)
      raise Error, "only direct YouTube URLs are supported" unless %w[http https].include?(uri.scheme)
      host = uri.host.to_s.downcase
      parts = uri.path.to_s.split("/").reject(&:empty?)
      id = if %w[youtu.be www.youtu.be].include?(host)
             parts.first
           elsif %w[youtube.com www.youtube.com m.youtube.com music.youtube.com].include?(host)
             parts == ["watch"] ? URI.decode_www_form(uri.query.to_s).to_h["v"] : (parts[1] if %w[shorts embed live v].include?(parts.first))
           end
      raise Error, "expected a single YouTube video URL" unless VIDEO_ID.match?(id.to_s)
      { id:, url: "https://www.youtube.com/watch?v=#{id}" }
    rescue URI::InvalidURIError, ArgumentError => error
      raise Error, "invalid YouTube URL: #{error.message}"
    end

    def download_audio(url, options)
      video = parse_url(url)
      ytdlp = executable("YT_DLP_BIN", "yt-dlp") or raise Error, "yt-dlp unavailable"
      out, = capture!("yt-dlp metadata", ytdlp, "--no-playlist", "--skip-download", "--dump-single-json", video[:url])
      metadata = JSON.parse(out)
      seconds = metadata["duration"].to_f
      raise Error, "source exceeds #{options[:max_duration]}s" if seconds.positive? && seconds > options[:max_duration]
      dir = options[:out] ? File.expand_path(options[:out]) : File.join(REFERENCE_ROOT, "#{video[:id]}-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}")
      prepare_dir(dir)
      File.write(File.join(dir, "metadata.json"), JSON.pretty_generate({
        "source_type" => "youtube_audio", "id" => video[:id], "title" => metadata["title"],
        "channel" => metadata["channel"] || metadata["uploader"], "url" => video[:url],
        "duration_seconds" => seconds, "license" => metadata["license"],
        "style_key" => style_key(options[:style])
      }.compact) + "\n")
      capture!("yt-dlp audio-only download", ytdlp, "--no-playlist", "--no-overwrites", "-f", "bestaudio/best",
               "-x", "--audio-format", "wav", "-o", File.join(dir, "source.%(ext)s"), video[:url],
               timeout: [[seconds.ceil + 300, 900].max, 57_600].min)
      audio = File.join(dir, "source.wav")
      raise Error, "download did not produce source.wav" unless File.file?(audio)
      analyze(audio, dir, options)
    end

    def analyze(audio, directory = nil, options = {})
      raise Error, "audio file does not exist: #{audio}" unless File.file?(audio) && File.readable?(audio)
      options = { stems: true, model: "htdemucs", max_duration: DEFAULT_DURATION, style: "general", libsonare: true }.merge(options)
      ffmpeg = executable("FFMPEG_BIN", "ffmpeg") or raise Error, "ffmpeg unavailable"
      ffprobe = executable("FFPROBE_BIN", "ffprobe") or raise Error, "ffprobe unavailable"
      duration = probe_duration(audio, ffprobe)
      raise Error, "source exceeds #{options[:max_duration]}s" if duration && duration > options[:max_duration]
      unless directory
        digest = Digest::SHA256.file(audio).hexdigest[0, 10]
        directory = options[:out] ? File.expand_path(options[:out]) :
          File.join(REFERENCE_ROOT, "#{File.basename(audio, File.extname(audio))}-#{digest}-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}")
        prepare_dir(directory)
      end
      puts "reference0: analyzing audio only"
      source = source_metadata(directory, audio)
      mix = metrics(audio, ffmpeg:, ffprobe:, max_duration: options[:max_duration], bands: true)
      stems, separation = separate(audio, directory, options, duration)
      tracks = { "mix" => mix }
      stems.each do |path|
        name = File.basename(path, ".wav")
        # Measure broad low/high energy in the drums stem as well as the mix.
        # Demucs roles are not isolated kick/snare/hat tracks.
        tracks[name] = metrics(path, ffmpeg:, ffprobe:, max_duration: options[:max_duration], bands: name == "drums")
      end
      mix["tempo"] = tempo(audio, ffmpeg:, max_duration: options[:max_duration])
      temporal_energy = temporal_energy_map(audio, ffmpeg:, max_duration: options[:max_duration])
      essentia_result = essentia(audio, directory, max_duration: options[:max_duration])
      libsonare_result = if options[:libsonare]
                           libsonare(audio, directory, max_duration: options[:max_duration], source_duration: duration)
                         else
                           { "status" => "disabled" }
                         end
      tempo_check = tempo_crosscheck(mix["tempo"], essentia_result.fetch("summary", {}))
      libsonare_tempo_check = tempo_crosscheck(
        mix["tempo"], libsonare_result.fetch("summary", {}), engine: "libsonare"
      )
      drum_source, rhythm_source_kind = rhythm_source_for(stems, audio)
      rhythm = rhythm_features(
        drum_source, ffmpeg:, max_duration: options[:max_duration],
        bpm: mix.dig("tempo", "bpm"), tempo_segments: mix.dig("tempo", "segments") || []
      )
      rhythm_zoom_windows = rhythm.delete("rhythm_zoom_windows") || []
      rhythm_window_count = rhythm.delete("rhythm_window_count")
      rhythm_analysis = { "source" => rhythm_source_kind,
                          "window_count" => rhythm_window_count,
                          "features" => rhythm.dup,
                          "zoom_windows" => rhythm_zoom_windows }
      # Grid vectors are evidence for the report, not stable style-profile knobs.
      profile_rhythm = rhythm.reject do |name, _value|
        name.start_with?("sixteenth_grid_") || %w[sixteenth_cell_ms grid_measurement].include?(name)
      end
      profile = profile_for(mix, style: options[:style])
      profile.fetch("features").merge!(profile_rhythm)
      energy_summary = temporal_energy.fetch("summary", {})
      if numeric_value(energy_summary["rms_range_p95_p05_db"])
        profile.fetch("features")["energy_window_range_db"] = energy_summary["rms_range_p95_p05_db"]
      end
      if numeric_value(energy_summary["rms_stddev_db"])
        profile.fetch("features")["energy_window_stddev_db"] = energy_summary["rms_stddev_db"]
      end
      apply_rhythm_balance(profile, rhythm)
      stem_features = stem_energy_features(tracks)
      profile.fetch("features").merge!(stem_features)
      apply_stem_balance(profile, stem_features)
      profile.merge!(
        "source_duration_seconds" => mix["duration_seconds"],
        "reference_fingerprint" => Digest::SHA256.file(audio).hexdigest[0, 16],
      )
      profile.compact!
      File.write(File.join(directory, "profile.json"), JSON.pretty_generate(profile) + "\n")
      FileUtils.mkdir_p(REFERENCE_ROOT)
      catalog = catalog_path(profile)
      FileUtils.mkdir_p(File.dirname(catalog))
      File.write(catalog, JSON.pretty_generate(profile) + "\n")
      learned = aggregate_saved_profiles(profile.fetch("style_key"), including: profile)
      report = { "schema_version" => 1, "source" => source, "tracks" => tracks, "separation" => separation,
                 "essentia" => essentia_result, "libsonare" => libsonare_result,
                 "tempo_crosscheck" => tempo_check, "libsonare_tempo_crosscheck" => libsonare_tempo_check,
                 "temporal_energy" => temporal_energy, "rhythm_analysis" => rhythm_analysis,
                 "production_profile" => profile,
                 "learned_profile" => learned,
                 "limitations" => ["Tempo is estimated; half-time and double-time can both fit.",
                                   "An independent tempo estimator may disagree or choose half/double time.",
                                   "Demucs stems can bleed and are not discrete kick/snare/hat multitracks.",
                                   "Temporal energy is a coarse arrangement contour, not a transcription.",
                                   "Spectral levels describe the mix, not isolated instruments.",
                                   "The style label is the user-provided hint, not an automatic genre classification.",
                                   "libsonare is optional and only analyzes references no longer than 15 minutes.",
                                   "Only broad production traits guide new music; source audio and composition are not copied."] }
      File.write(File.join(directory, "analysis.json"), JSON.pretty_generate(report) + "\n")
      File.write(File.join(REFERENCE_ROOT, "latest_profile.json"), JSON.pretty_generate(learned) + "\n")
      scoped_profile = profile_path(profile.fetch("style_key"))
      FileUtils.mkdir_p(File.dirname(scoped_profile))
      File.write(scoped_profile, JSON.pretty_generate(learned) + "\n")
      write_active_style(profile.fetch("style_key"))
      write_report(File.join(directory, "report.md"), tracks, separation, profile, learned,
                   temporal_energy:, essentia: essentia_result, libsonare: libsonare_result,
                   tempo_crosscheck: tempo_check, libsonare_tempo_crosscheck: libsonare_tempo_check,
                   rhythm_analysis:, source:)
      puts "reference0: style_hint=#{profile.fetch('style_key')}; learned references=#{learned.fetch('reference_count', 1)}; separation=#{separation['status']}; analyzed #{tracks.size - 1} stems"
      puts "reference0: estimated tempo=#{mix.dig('tempo', 'bpm') || 'unknown'} BPM"
      puts "reference0: learned target_bpm=#{learned['target_bpm'] || 'unknown'} groove=#{learned['groove_profile'] || 'unspecified'} features=#{JSON.generate(learned.fetch('features', {}))}"
      puts "reference0: parameters=#{JSON.generate(learned.fetch('parameters', {}))}" unless learned.fetch("parameters", {}).empty?
      puts "reference0: report=#{File.join(directory, 'report.md')}"
      0
    end

    # Include identifying metadata in analysis outputs so the operator can verify
    # that the intended recording was analyzed. Never persist an absolute local path.
    def source_metadata(directory, audio)
      path = File.join(directory, "metadata.json")
      if File.file?(path)
        metadata = JSON.parse(File.read(path))
        keys = %w[source_type id title channel url duration_seconds license style_key]
        return metadata.select { |key, _value| keys.include?(key) }
      end

      { "source_type" => "local_audio", "filename" => File.basename(audio) }
    rescue JSON::ParserError => error
      { "source_type" => "unknown", "metadata_status" => "invalid",
        "filename" => File.basename(audio), "message" => error.message }
    end

    def prepare_dir(path)
      raise Error, "refusing non-empty output directory: #{path}" if Dir.exist?(path) && !Dir.empty?(path)
      FileUtils.mkdir_p(path)
    end

    def metrics(path, ffmpeg:, ffprobe:, max_duration:, bands:)
      out, = capture!("ffprobe", ffprobe, "-v", "error", "-show_format", "-show_streams", "-of", "json", path)
      probe = JSON.parse(out)
      fmt = probe["format"] || {}
      stream = (probe["streams"] || []).find { |row| row["codec_type"] == "audio" } || {}
      _stdout, logs = capture!("FFmpeg audio stats", ffmpeg, "-hide_banner", "-nostats", "-i", path,
                               "-t", max_duration.to_s, "-af", "astats=metadata=0:reset=0,ebur128=peak=true",
                               "-f", "null", "-", timeout: analysis_timeout(max_duration))
      result = { "duration_seconds" => fmt["duration"]&.to_f, "codec" => stream["codec_name"],
                 "sample_rate_hz" => stream["sample_rate"]&.to_i, "channels" => stream["channels"]&.to_i,
                 "rms_db" => number(logs, /RMS level dB:\s*(-?[\d.]+)/),
                 "peak_db" => number(logs, /Peak level dB:\s*(-?[\d.]+)/),
                 "integrated_lufs" => number(logs, /I:\s*(-?[\d.]+)\s+LUFS/) }.compact
      result["spectral_bands_db"] = band_levels(path, ffmpeg:, max_duration:) if bands
      result
    end

    def band_levels(path, ffmpeg:, max_duration:)
      filters = { "sub_25_120_hz" => "highpass=f=25,lowpass=f=120,volumedetect",
                  "low_mid_120_500_hz" => "highpass=f=120,lowpass=f=500,volumedetect",
                  "mid_500_4000_hz" => "highpass=f=500,lowpass=f=4000,volumedetect",
                  "high_4000_plus_hz" => "highpass=f=4000,volumedetect" }
      filters.to_h do |name, filter|
        _out, logs = capture!("FFmpeg #{name}", ffmpeg, "-hide_banner", "-nostats", "-i", path,
                              "-t", max_duration.to_s, "-af", filter, "-f", "null", "-",
                              timeout: analysis_timeout(max_duration))
        [name, number(logs, /mean_volume:\s*(-?[\d.]+)\s+dB/)]
      rescue Error
        [name, nil]
      end
    end

    # Estimate a global tempo and local 60-second windows from one FFmpeg pass.
    # Keep real tempos below 80 BPM; half/double ambiguity is reported elsewhere
    # instead of silently forcing a laid-back groove into a faster bracket.
    def tempo(path, ffmpeg:, max_duration:, sample_rate: 40, segment_seconds: 60, min_segment_seconds: 30)
      bytes, = capture!("tempo envelope", ffmpeg, "-hide_banner", "-v", "error", "-i", path,
                        "-t", max_duration.to_s, "-vn", "-ac", "1", "-af",
                        "aeval=exprs=val(0)*val(0),lowpass=f=12", "-ar", sample_rate.to_s,
                        "-f", "f32le", "pipe:1", timeout: analysis_timeout(max_duration))
      samples = bytes.force_encoding(Encoding::BINARY).unpack("e*")
      overall = estimate_tempo_samples(samples, sample_rate:)
      return unless overall

      segment_size = sample_rate * segment_seconds
      minimum_size = sample_rate * min_segment_seconds
      segments = samples.each_slice(segment_size).with_index.filter_map do |slice, index|
        next if slice.size < minimum_size

        estimate = estimate_tempo_samples(slice, sample_rate:)
        next unless estimate

        start_seconds = index * segment_seconds
        { "start_seconds" => start_seconds,
          "end_seconds" => (start_seconds + slice.size.to_f / sample_rate).round(2) }.merge(estimate)
      end
      overall.merge("segments" => segments).merge(tempo_segment_summary(segments))
    rescue Error
      nil
    end

    def estimate_tempo_samples(samples, sample_rate: 40)
      return if samples.size < sample_rate * 12

      mean = samples.sum / samples.size
      centred = samples.map { |sample| sample - mean }
      energy = centred.sum { |sample| sample * sample }
      return if energy < 1e-12

      minimum_lag = [(sample_rate * 60.0 / 200).floor, 1].max
      maximum_lag = (sample_rate * 60.0 / 50).ceil
      final_lag = [maximum_lag, samples.size / 4].min
      return if final_lag < minimum_lag

      score, lag = (minimum_lag..final_lag).map do |candidate|
        total = 0.0
        limit = centred.size - candidate
        index = 0
        while index < limit
          total += centred[index] * centred[index + candidate]
          index += 1
        end
        [total / ([limit, 1].max * energy / centred.size), candidate]
      end.max_by(&:first)
      { "bpm" => (sample_rate * 60.0 / lag).round(1), "confidence" => score.round(3) }
    end

    def tempo_segment_summary(segments)
      values = segments.filter_map { |segment| numeric_value(segment["bpm"]) }.sort
      return {} if values.empty?

      { "segment_count" => values.length,
        "segment_median_bpm" => median_value(values).round(1),
        "segment_bpm_range" => (values.max - values.min).round(1) }
    end

    def separate(audio, directory, options, duration)
      return [[], { "status" => "not_requested", "files" => [] }] unless options[:stems]
      command = executable("DEMUCS_BIN", "demucs")
      return [[], { "status" => "unavailable", "files" => [] }] unless command
      target = File.join(directory, "stems")
      prepare_dir(target)
      _out, logs = capture!("Demucs separation", command, "--name", options[:model], "--out", target, audio,
                            timeout: [[duration.to_f.ceil * 8, 1800].max, 57_600].min)
      files = Dir.glob(File.join(target, "**", "*.wav")).sort
      [files, { "status" => files.empty? ? "no_stems_found" : "separated",
                "model" => options[:model], "files" => files.map { |path| path.delete_prefix(directory + File::SEPARATOR) },
                "log_tail" => logs.lines.last(4).join.strip }]
    rescue Error => error
      [[], { "status" => "failed", "files" => [], "message" => error.message }]
    end

    # Optional C++-backed music analysis through libsonare's Python CLI.
    # Use argv rather than a shell and never make this a rendering dependency.
    # Its Python binding loads the file into memory, so sources are capped at 15 minutes.
    def libsonare(audio, directory, max_duration: DEFAULT_DURATION, source_duration: nil)
      unless source_duration && source_duration.to_f.finite?
        return { "status" => "skipped_unknown_duration",
                 "max_duration_seconds" => LIBSONARE_MAX_DURATION_SECONDS }
      end
      if source_duration.to_f > LIBSONARE_MAX_DURATION_SECONDS
        return { "status" => "skipped_duration",
                 "max_duration_seconds" => LIBSONARE_MAX_DURATION_SECONDS }
      end

      exe = executable("LIBSONARE_BIN", "sonare")
      return { "status" => "unavailable" } unless exe

      timeout = analysis_timeout([source_duration.to_f.ceil, max_duration.to_i].min)
      input = audio
      temporary = nil
      unless %w[.wav .mp3].include?(File.extname(audio).downcase)
        ffmpeg = executable("FFMPEG_BIN", "ffmpeg")
        return { "status" => "unavailable", "message" => "ffmpeg unavailable for libsonare format conversion" } unless ffmpeg

        temporary = Tempfile.new(["libsonare-input-", ".wav"], directory)
        input = temporary.path
        temporary.close
        capture!("libsonare input conversion", ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error",
                 "-y", "-i", audio, "-t", source_duration.to_s, "-vn", "-ac", "1", "-ar", "22050",
                 "-c:a", "pcm_s16le", input, timeout:)
        unless File.file?(input) && File.size(input).positive?
          return { "status" => "failed", "message" => "libsonare input conversion produced no audio" }
        end
      end

      stdout, = capture!("libsonare analysis", exe, "analyze", input, "--json", timeout:)
      descriptors = JSON.parse(stdout)
      return { "status" => "failed", "message" => "invalid libsonare output: expected a JSON object" } unless descriptors.is_a?(Hash)

      name = File.join(directory, "libsonare_features.json")
      File.write(name, JSON.pretty_generate(descriptors) + "\n")
      { "status" => "analyzed", "file" => File.basename(name),
        "summary" => libsonare_descriptor_summary(descriptors) }
    rescue Error => error
      { "status" => "failed", "message" => error.message }
    rescue JSON::ParserError => error
      { "status" => "failed", "message" => "invalid libsonare output: #{error.message}" }
    rescue Errno::ENOENT, Errno::EACCES, Errno::EIO => error
      { "status" => "failed", "message" => "libsonare analysis failed: #{error.message}" }
    ensure
      temporary&.close!
    end

    # Keep compact measurements for style learning. Full timelines remain in a raw
    # JSON sidecar; exact chord names do not steer a future composition.
    def libsonare_descriptor_summary(document)
      return {} unless document.is_a?(Hash)

      summary = {}
      bpm = numeric_value(document["bpm"])
      summary["bpm"] = bpm.round(2) if bpm&.between?(20.0, 400.0)
      confidence = numeric_value(document["bpm_confidence"])
      summary["bpm_confidence"] = confidence.round(3) if confidence&.between?(0.0, 1.0)

      key = document["key"]
      if key.is_a?(Hash)
        name = key["name"]
        summary["key"] = name.strip if name.is_a?(String) && !name.strip.empty?
        value = numeric_value(key["confidence"])
        summary["key_confidence"] = value.round(3) if value&.between?(0.0, 1.0)
      end

      meter = document["time_signature"]
      if meter.is_a?(Hash)
        numerator = numeric_value(meter["numerator"])
        denominator = numeric_value(meter["denominator"])
        if numerator&.between?(1, 32) && denominator&.between?(1, 32) &&
           numerator == numerator.to_i && denominator == denominator.to_i
          summary["time_signature"] = "#{numerator.to_i}/#{denominator.to_i}"
        end
      end

      beats = document["beats"]
      if beats.is_a?(Array)
        summary["beats_count"] = beats.size
        times = beats.filter_map do |beat|
          value = numeric_value(beat["time"]) if beat.is_a?(Hash)
          value if value && value >= 0
        end
        intervals = times.each_cons(2).map { |first, last| last - first }.select(&:positive?)
        if intervals.size >= 2
          median_interval = median_value(intervals)
          mean_interval = intervals.sum / intervals.size.to_f
          variance = intervals.sum { |value| (value - mean_interval)**2 } / intervals.size
          summary["beat_interval_median_ms"] = (median_interval * 1_000).round(2)
          summary["beat_interval_cv_pct"] = (Math.sqrt(variance) / mean_interval * 100).round(2) if mean_interval.positive?
        end
      end
      summary["downbeats_count"] = document["downbeat_indices"].size if document["downbeat_indices"].is_a?(Array)
      summary["chord_count"] = document["chords"].size if document["chords"].is_a?(Array)
      if document["sections"].is_a?(Array)
        sections = document["sections"].select { |section| section.is_a?(Hash) }
        summary["section_count"] = sections.size
        types = sections.filter_map do |section|
          type = section["type"]
          type.strip if type.is_a?(String) && !type.strip.empty?
        end.uniq.sort.first(16)
        summary["section_types"] = types unless types.empty?
      end

      { "timbre" => "timbre", "dynamics" => "dynamics", "rhythm" => "rhythm" }.each do |source, prefix|
        values = document[source]
        next unless values.is_a?(Hash)

        values.each do |name, value|
          if name == "groove_type" && value.is_a?(String) && !value.strip.empty?
            summary["#{prefix}_#{name}"] = value.strip
          elsif name == "is_compressed" && (value == true || value == false)
            summary["#{prefix}_#{name}"] = value
          else
            number = numeric_value(value)
            summary["#{prefix}_#{name}"] = number.round(3) if number
          end
        end
      end
      form = document["form"]
      summary["form"] = form.strip if form.is_a?(String) && !form.strip.empty?
      summary
    end

    def essentia(audio, directory, max_duration: DEFAULT_DURATION)
      exe = executable("ESSENTIA_EXTRACTOR", "streaming_extractor_music")
      return { "status" => "unavailable" } unless exe

      name = File.join(directory, "essentia_features.json")
      capture!("Essentia", exe, audio, name, timeout: analysis_timeout(max_duration))
      descriptors = JSON.parse(File.read(name))
      { "status" => "analyzed", "file" => File.basename(name),
        "summary" => essentia_descriptor_summary(descriptors) }
    rescue Error => error
      { "status" => "failed", "message" => error.message }
    rescue Errno::ENOENT, JSON::ParserError => error
      { "status" => "failed", "message" => "invalid Essentia output: #{error.message}" }
    end

    # Keep the raw extractor output for research, but surface a small, stable
    # set of independent measurements in the report. Never use exact chord
    # progressions to steer generation.
    def essentia_descriptor_summary(document)
      paths = {
        "bpm" => %w[rhythm bpm],
        "bpm_histogram_first_peak_bpm" => %w[rhythm bpm_histogram_first_peak_bpm],
        "bpm_histogram_second_peak_bpm" => %w[rhythm bpm_histogram_second_peak_bpm],
        "beats_count" => %w[rhythm beats_count],
        "onset_rate_per_second" => %w[rhythm onset_rate],
        "key" => %w[tonal key_key],
        "scale" => %w[tonal key_scale],
        "spectral_centroid_mean_hz" => %w[lowlevel spectral_centroid mean],
        "spectral_entropy_mean" => %w[lowlevel spectral_entropy mean],
      }
      paths.each_with_object({}) do |(name, path), summary|
        value = path.reduce(document) { |node, part| node.is_a?(Hash) ? node[part] : nil }
        if %w[key scale].include?(name)
          summary[name] = value if value.is_a?(String) && !value.strip.empty?
        else
          number = numeric_value(value)
          summary[name] = number.round(3) if number
        end
      end
    end

    # The FFmpeg envelope estimate and Essentia beat tracker are deliberately
    # independent. Report close agreement versus half/double-time ambiguity;
    # do not silently average contradictory estimators into a false precision.
    def tempo_crosscheck(tempo, independent_summary, engine: "essentia")
      primary = numeric_value(tempo.is_a?(Hash) ? tempo["segment_median_bpm"] : nil)
      global = numeric_value(tempo.is_a?(Hash) ? tempo["bpm"] : nil)
      primary ||= global
      engine_name = engine.to_s == "libsonare" ? "libsonare" : "essentia"
      field = "#{engine_name}_bpm"
      independent = numeric_value(independent_summary.is_a?(Hash) ? independent_summary["bpm"] : nil)
      if !independent && independent_summary.is_a?(Hash) && engine_name == "essentia"
        independent = numeric_value(independent_summary["bpm_histogram_first_peak_bpm"])
      end
      return { "status" => "insufficient_evidence", "ffmpeg_bpm" => primary,
               "ffmpeg_global_bpm" => global, field => independent }.compact unless primary && independent

      direct_delta = (primary - independent).abs
      half_delta = (primary - independent * 2.0).abs
      double_delta = (primary * 2.0 - independent).abs
      status = if direct_delta <= 3.0
                 "agreement"
               elsif [half_delta, double_delta].min <= 4.0
                 "half_double_ambiguity"
               else
                 "disagreement"
               end
      { "status" => status, "ffmpeg_bpm" => primary.round(2),
        "ffmpeg_global_bpm" => global&.round(2),
        field => independent.round(2), "absolute_delta_bpm" => direct_delta.round(2) }.compact
    end

    # Summarize the mix's energy in short windows, independently of the rhythm
    # detector. Four low-rate samples per second are enough for arrangement-scale
    # dynamics and keep even a two-hour album small in memory and in the report.
    def temporal_energy_map(path, ffmpeg:, max_duration:, window_seconds: 15, sample_rate: 4)
      bytes, = capture!("temporal energy envelope", ffmpeg, "-hide_banner", "-v", "error", "-i", path,
                        "-t", max_duration.to_s, "-vn", "-ac", "1", "-af",
                        "aeval=exprs=val(0)*val(0),lowpass=f=1.5", "-ar", sample_rate.to_s,
                        "-f", "f32le", "pipe:1", timeout: analysis_timeout(max_duration))
      samples = bytes.force_encoding(Encoding::BINARY).unpack("e*")
      summarize_energy_envelope(samples, sample_rate:, window_seconds:).merge("status" => "analyzed")
    rescue Error => error
      { "status" => "unavailable", "message" => error.message }
    end

    def summarize_energy_envelope(samples, sample_rate:, window_seconds: 15)
      per_window = [(sample_rate.to_f * window_seconds).round, 1].max
      windows = samples.each_slice(per_window).with_index.filter_map do |slice, index|
        next if slice.empty?

        energy = slice.sum / slice.size
        rms_db = 10.0 * Math.log10([energy, 1e-12].max)
        { "start_seconds" => index * window_seconds,
          "end_seconds" => (index * window_seconds) + slice.size.to_f / sample_rate,
          "rms_db" => rms_db.round(2) }
      end
      levels = windows.map { |window| window.fetch("rms_db") }
      summary = {}
      if levels.size >= 3
        sorted = levels.sort
        p05 = sorted[((sorted.size - 1) * 0.05).round]
        p95 = sorted[((sorted.size - 1) * 0.95).round]
        mean = levels.sum / levels.size
        variance = levels.sum { |level| (level - mean)**2 } / levels.size
        summary = {
          "rms_p05_db" => p05,
          "rms_p95_db" => p95,
          "rms_range_p95_p05_db" => (p95 - p05).round(2),
          "rms_median_db" => sorted[(sorted.size - 1) / 2],
          "rms_stddev_db" => Math.sqrt(variance).round(2),
        }
      end
      { "window_seconds" => window_seconds, "window_count" => windows.size,
        "windows" => windows, "summary" => summary }
    end

    # Normalize only the broad styles MASTER explicitly identifies. The acoustic
    # measurements remain measurements; the style hint is not claimed as detected.
    def style_key(value)
      hint = value.to_s.downcase.tr("_", " ").gsub(/[^a-z0-9]+/, " ").strip
      return "industrial_techno" if hint.match?(/\bindustrial techno\b|\btechno\b/)
      return "j_dilla" if hint.match?(/\bdilla\b|\bboom bap\b|\bhip hop\b/)
      "general"
    end

    def profile_path(style)
      key = style_key(style)
      File.join(REFERENCE_ROOT, "profiles", key, "latest_profile.json")
    end

    def catalog_path(profile)
      key = style_key(profile.fetch("style_key"))
      fingerprint = profile.fetch("reference_fingerprint").to_s
      raise Error, "reference fingerprint must be hexadecimal" unless fingerprint.match?(/\A[0-9a-f]{16}\z/i)

      File.join(REFERENCE_ROOT, "records", "#{key}-#{fingerprint.downcase}.json")
    end

    # Keep one compact measurement record per audio source and style. Learned
    # profiles average measurements across references, retaining the newest
    # source duration for planning a take of a suitable length.
    def aggregate_saved_profiles(style, including: nil)
      key = style_key(style)
      paths = Dir.glob(File.join(REFERENCE_ROOT, "records", "#{key}-*.json")).sort
      rows = paths.filter_map { |path| read_profile_record(path, key) }
      if including
        rows.reject! { |row| row["reference_fingerprint"] == including["reference_fingerprint"] }
        rows << including
      end
      aggregate_profiles(key, rows)
    end

    def read_profile_record(path, style)
      value = JSON.parse(File.read(path))
      value if value.is_a?(Hash) && style_key(value["style_key"]) == style
    rescue Errno::ENOENT, JSON::ParserError, TypeError
      nil
    end

    def aggregate_profiles(style, profiles)
      key = style_key(style)
      rows = profiles.select { |row| row.is_a?(Hash) && style_key(row["style_key"]) == key }
                     .uniq { |row| row["reference_fingerprint"] || row.object_id }
      return { "style_key" => key, "genre" => key == "j_dilla" ? "hip_hop" : key,
               "reference_count" => 0 } if rows.empty?

      learned = rows.last.dup
      learned["reference_count"] = rows.size
      learned["reference_fingerprints"] = rows.filter_map { |row| row["reference_fingerprint"] }.uniq
      %w[target_bpm measured_bpm].each do |field|
        average = numeric_mean(rows.filter_map { |row| numeric_value(row[field]) })
        next unless average

        learned[field] = field == "target_bpm" ? average.round : average.round(1)
      end
      %w[features parameters].each do |section|
        keys = rows.flat_map { |row| row.fetch(section, {}).is_a?(Hash) ? row.fetch(section, {}).keys : [] }.uniq
        merged = {}
        keys.each do |field|
          average = numeric_mean(rows.filter_map do |row|
            values = row.fetch(section, {})
            numeric_value(values[field]) if values.is_a?(Hash)
          end)
          merged[field] = average.round(3) if average
        end
        learned[section] = merged unless merged.empty?
      end
      learned
    end

    def numeric_value(value)
      number = Float(value)
      number.finite? ? number : nil
    rescue ArgumentError, TypeError
      nil
    end

    # Use observed rhythmic density to make small bounded changes to techno
    # ornament density. The renderer remains straight 4/4; this never imports notes.
    def apply_rhythm_balance(profile, features)
      return profile unless profile["style_key"] == "industrial_techno"

      parameters = profile["parameters"]
      return profile unless parameters.is_a?(Hash)

      density = numeric_value(features["onset_density_per_bar"])
      return profile unless density

      hat = numeric_value(parameters["hat_probability"])
      metal = numeric_value(parameters["metal_probability"])
      parameters["hat_probability"] = (hat + ((density - 16.0) / 16.0) * 0.08).clamp(0.1, 0.98).round(3) if hat
      parameters["metal_probability"] = (metal + ((density - 16.0) / 16.0) * 0.06).clamp(0.02, 0.45).round(3) if metal
      profile
    end

    # Let the separated bass and drum energy gently steer industrial rumble.
    # These are bounded mix decisions, not claims that stems are clean multitracks.
    def apply_stem_balance(profile, features)
      parameters = profile["parameters"]
      return profile unless parameters.is_a?(Hash)

      bass_share = numeric_value(features["bass_energy_share"])
      drum_share = numeric_value(features["drums_energy_share"])
      rumble = numeric_value(parameters["rumble_level"])
      duck = numeric_value(parameters["rumble_duck_depth"])
      parameters["rumble_level"] = (rumble + (bass_share - 0.25) * 0.12).clamp(0.05, 0.35).round(3) if bass_share && rumble
      parameters["rumble_duck_depth"] = (duck + (drum_share - 0.25) * 0.22).clamp(0.3, 0.95).round(3) if drum_share && duck
      profile
    end

    # State exactly where the rhythm proxy came from. Demucs stems remain broad,
    # artifact-prone source roles, not isolated kick/snare/hat multitracks.
    def rhythm_source_for(stems, audio)
      drum_stem = stems.find { |path| File.basename(path, ".wav") == "drums" }
      [drum_stem || audio, drum_stem ? "demucs_drums_stem" : "full_mix_proxy"]
    end

    # Measure broad rhythmic traits from a low-rate energy envelope. When Demucs
    # supplies a drums stem we prefer it; otherwise this is explicitly a mix-level
    # estimate. No claims are made about individual kick/snare timing.
    def rhythm_features(path, ffmpeg:, max_duration:, bpm:, sample_rate: 100, tempo_segments: [])
      tempo = numeric_value(bpm)
      return {} unless tempo&.between?(50.0, 200.0)

      bytes, = capture!("rhythm energy envelope", ffmpeg, "-hide_banner", "-v", "error", "-i", path,
                        "-t", max_duration.to_s, "-vn", "-ac", "1", "-af",
                        "aeval=exprs=val(0)*val(0),lowpass=f=18", "-ar", sample_rate.to_s,
                        "-f", "f32le", "pipe:1", timeout: analysis_timeout(max_duration))
      samples = bytes.force_encoding(Encoding::BINARY).unpack("e*")
      valid_segments = tempo_segments.select do |segment|
        next false unless segment.is_a?(Hash)
        next false unless numeric_value(segment["bpm"])&.between?(50.0, 200.0)

        numeric_value(segment["start_seconds"]) && numeric_value(segment["end_seconds"])
      end
      zoom_windows = []
      if valid_segments.empty?
        summary = summarize_rhythm_envelope(samples, bpm: tempo, sample_rate:).merge("rhythm_window_count" => 1)
        zoom_windows = rhythm_zoom_summaries(samples, bpm: tempo, sample_rate:)
      else
        features = valid_segments.filter_map do |segment|
          start_seconds = numeric_value(segment["start_seconds"])
          end_seconds = numeric_value(segment["end_seconds"])
          start_index = [(start_seconds * sample_rate).round, 0].max
          end_index = [(end_seconds * sample_rate).round, start_index].max
          slice = samples[start_index, end_index - start_index] || []
          segment_bpm = numeric_value(segment["bpm"])
          zoom_windows.concat(
            rhythm_zoom_summaries(slice, bpm: segment_bpm, sample_rate:, time_offset: start_seconds),
          )
          local = summarize_rhythm_envelope(slice, bpm: segment_bpm, sample_rate:)
          local unless local.empty?
        end
        summary = if features.empty?
                    summarize_rhythm_envelope(samples, bpm: tempo, sample_rate:).merge("rhythm_window_count" => 1)
                  else
                    summarize_rhythm_segments(features)
                  end
        zoom_windows = rhythm_zoom_summaries(samples, bpm: tempo, sample_rate:) if features.empty?
      end
      summary["rhythm_zoom_windows"] = zoom_windows
      summary
    rescue Error
      {}
    end

    # Prefer local tempo windows for long references so track-to-track tempo
    # changes do not masquerade as microtiming or swing.
    def summarize_rhythm_segments(segments)
      return {} if segments.empty?

      summary = { "rhythm_window_count" => segments.length }
      {
        "timing_spread_ms" => 1,
        "onset_density_per_bar" => 2,
        "offbeat_onset_share" => 3,
        "sixteenth_cell_ms" => 2,
      }.each do |field, precision|
        values = segments.filter_map { |features| numeric_value(features[field]) }.sort
        next if values.empty?

        summary[field] = median_value(values).round(precision)
      end
      %w[sixteenth_grid_hits_per_bar sixteenth_grid_strength_share].each do |field|
        vectors = segments.filter_map do |features|
          values = features[field]
          values if values.is_a?(Array) && values.length == 16 && values.all? { |value| numeric_value(value) }
        end
        next if vectors.empty?

        summary[field] = 16.times.map do |index|
          median_value(vectors.filter_map { |values| numeric_value(values[index]) }).round(field.end_with?("share") ? 4 : 2)
        end
      end
      summary["grid_measurement"] = "mix_level_onset_proxy_not_drum_transcription"
      summary
    end

    def median_value(values)
      sorted = values.sort
      return if sorted.empty?

      middle = sorted.length / 2
      sorted.length.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
    end

    def summarize_rhythm_envelope(samples, bpm:, sample_rate: 100)
      return {} if samples.size < sample_rate * 4 || !bpm.to_f.between?(50.0, 200.0)

      novelty = Array.new(samples.size, 0.0)
      (1...samples.size).each do |index|
        rise = samples[index] - samples[index - 1]
        novelty[index] = rise if rise.positive? && rise.finite?
      end
      positive = novelty.select(&:positive?)
      return {} if positive.size < 8

      positive.sort!
      threshold = [positive[(positive.size * 0.80).floor.clamp(0, positive.size - 1)], positive[-1] * 0.08].max
      refractory = [(sample_rate * 0.06).round, 1].max
      peaks = []
      (1...(novelty.size - 1)).each do |index|
        next unless novelty[index] >= threshold && novelty[index] >= novelty[index - 1] && novelty[index] > novelty[index + 1]

        if peaks.empty? || index - peaks[-1] >= refractory
          peaks << index
        elsif novelty[index] > novelty[peaks[-1]]
          peaks[-1] = index
        end
      end
      return {} if peaks.size < 8

      subdivision = sample_rate * 60.0 / bpm.to_f / 4.0
      phase_best = 0
      matches_best = -1
      error_best = Float::MAX
      (0...[subdivision.ceil, 1].max).each do |phase|
        errors = peaks.map { |position| position - (phase + ((position - phase) / subdivision).round * subdivision) }
        matches = errors.count { |error| error.abs <= sample_rate * 0.045 }
        mean_error = errors.sum(&:abs) / errors.size
        if matches > matches_best || (matches == matches_best && mean_error < error_best)
          phase_best = phase
          matches_best = matches
          error_best = mean_error
        end
      end

      errors = peaks.map { |position| position - (phase_best + ((position - phase_best) / subdivision).round * subdivision) }
      timing_spread_ms = errors.sum(&:abs).to_f / errors.size * 1000.0 / sample_rate
      total_strength = peaks.sum { |index| novelty[index] }
      offbeat_strength = peaks.each_with_index.sum do |position, index|
        grid_step = ((position - phase_best) / subdivision).round
        grid_step % 4 == 0 ? 0.0 : novelty[position]
      end
      duration = samples.size.to_f / sample_rate
      bars = duration * bpm.to_f / 240.0
      grid_hits = Array.new(16, 0)
      grid_strength = Array.new(16, 0.0)
      peaks.each do |position|
        grid_position = (((position - phase_best) / subdivision).round % 16)
        grid_hits[grid_position] += 1
        grid_strength[grid_position] += novelty[position]
      end
      sixteenth_grid_hits_per_bar = grid_hits.map { |count| (count / [bars, 0.001].max).round(2) }
      sixteenth_grid_strength_share = grid_strength.map do |strength|
        (strength / total_strength).round(4)
      end
      features = {
        "timing_spread_ms" => timing_spread_ms.round(1),
        "onset_density_per_bar" => (peaks.size / [bars, 0.001].max).round(2),
        "sixteenth_cell_ms" => (60_000.0 / bpm.to_f / 4.0).round(2),
        "sixteenth_grid_hits_per_bar" => sixteenth_grid_hits_per_bar,
        "sixteenth_grid_strength_share" => sixteenth_grid_strength_share,
        "grid_measurement" => "mix_level_onset_proxy_not_drum_transcription",
      }
      features["offbeat_onset_share"] = (offbeat_strength / total_strength).round(3) if total_strength.positive?
      features
    end

    # Summarize complete 4-, 8- and 16-bar windows. This is a zoomed view of the
    # low-rate mix/stem envelope, not a note transcription. Partial windows are
    # omitted so every row compares the same number of bars.
    def rhythm_zoom_summaries(samples, bpm:, sample_rate: 100, time_offset: 0.0)
      return [] if samples.size < sample_rate * 4 || !bpm.to_f.between?(50.0, 200.0)

      [4, 8, 16].flat_map do |bar_count|
        window_size = (bar_count * 240.0 / bpm.to_f * sample_rate).round
        next [] if window_size <= 0

        count = samples.size / window_size
        Array.new(count) do |window_index|
          offset = window_index * window_size
          window = samples.slice(offset, window_size) || []
          features = summarize_rhythm_envelope(window, bpm:, sample_rate:)
          next if features.empty?

          start_seconds = time_offset.to_f + offset.to_f / sample_rate
          { "bars" => bar_count,
            "start_seconds" => start_seconds.round(3),
            "end_seconds" => (start_seconds + window.size.to_f / sample_rate).round(3),
            "features" => features }
        end.compact
      end.sort_by { |window| [window.fetch("start_seconds"), window.fetch("bars")] }
    end

    # Demucs gives broad source roles rather than isolated kick/snare/hats.
    # Compare their measured RMS powers, but omit roles without usable evidence.
    def stem_energy_features(tracks)
      roles = %w[drums bass vocals other]
      energies = roles.to_h do |role|
        metrics = tracks[role]
        rms = numeric_value(metrics["rms_db"]) if metrics.is_a?(Hash)
        [role, rms && (10.0**(rms / 10.0))]
      end.compact
      total = energies.values.sum
      return {} unless total.positive? && total.finite?

      energies.to_h { |role, energy| ["#{role}_energy_share", (energy / total).round(3)] }
    end

    def numeric_mean(values)
      return if values.empty?

      values.sum / values.size
    end

    def active_style_path(root: REFERENCE_ROOT)
      File.join(root, "active_style.json")
    end

    def active_style(root: REFERENCE_ROOT)
      value = JSON.parse(File.read(active_style_path(root:)))
      key = style_key(value["style_key"])
      %w[j_dilla industrial_techno].include?(key) ? key : "general"
    rescue Errno::ENOENT, JSON::ParserError, TypeError, NoMethodError
      "general"
    end

    def write_active_style(style, root: REFERENCE_ROOT)
      key = style_key(style)
      return key unless %w[j_dilla industrial_techno].include?(key)

      FileUtils.mkdir_p(root)
      File.write(active_style_path(root:), JSON.pretty_generate({ "style_key" => key }) + "\n")
      key
    end

    def profile_for(mix, style: "general")
      bands = mix.fetch("spectral_bands_db", {})
      level = ->(name, fallback) { numeric_value(bands[name]) || fallback }
      low = ((level.call("sub_25_120_hz", -36.0) - level.call("low_mid_120_500_hz", -36.0) + 8.0) / 24.0).clamp(0.0, 1.0)
      bright = ((level.call("high_4000_plus_hz", -36.0) - level.call("mid_500_4000_hz", -36.0) + 10.0) / 24.0).clamp(0.0, 1.0)
      bpm = numeric_value(mix.dig("tempo", "bpm"))
      stable_bpm = numeric_value(mix.dig("tempo", "segment_median_bpm")) || bpm
      key = style_key(style)
      common = { "style_key" => key, "measured_bpm" => bpm,
                 "tempo_confidence" => mix.dig("tempo", "confidence"), "meter" => "4/4",
                 "features" => { "low_frequency_weight" => low.round(3), "brightness" => bright.round(3) } }
      case key
      when "industrial_techno"
        common.merge("genre" => key, "target_bpm" => bpm ? bpm.clamp(118, 160).round : 138,
          "parameters" => {
            "rumble_level" => (0.09 + 0.10 * low).round(3), "rumble_duck_depth" => (0.70 + 0.20 * low).round(3),
            "hat_probability" => (0.46 + 0.30 * bright).round(3), "metal_probability" => (0.07 + 0.13 * bright).round(3),
            "distortion_drive" => (1.6 + 0.9 * bright).round(2)
          }, "production" => "straight four-on-the-floor; distorted rumble; metallic hits; evolving industrial textures; no hip-hop swing")
      when "j_dilla"
        common.merge("genre" => "hip_hop", "target_bpm" => stable_bpm ? stable_bpm.clamp(70, 110).round : 88,
          "groove_profile" => "dilla_shadow",
          "production" => "sample-led hip-hop reference; laid-back pocket; syncopated boom-bap drums; warm, slightly imperfect texture")
      else
        common.merge("genre" => "general", "target_bpm" => bpm&.round,
          "production" => "use measured tempo, spectral balance, loudness and duration as broad reference cues; do not infer unmeasured groove or instrumentation")
      end
    end

    def write_report(path, tracks, separation, profile, learned = profile,
                     temporal_energy: {}, essentia: {}, libsonare: {}, tempo_crosscheck: {},
                     libsonare_tempo_crosscheck: {}, rhythm_analysis: {}, source: {})
      lines = ["# Audio reference analysis", "", "## Source",
               JSON.pretty_generate(source), "",
               "Estimated tempo: #{tracks.dig('mix', 'tempo', 'bpm') || 'unknown'} BPM",
               "Style hint: #{profile['style_key']} (provided by the user, not automatically classified)",
               "References in learned profile: #{learned['reference_count'] || 1}",
               "Stem separation: #{separation['status']}", "", "## Parts"]
      tracks.each { |name, row| lines << "- #{name}: #{row['duration_seconds'] || '?'} s; RMS #{row['rms_db'] || 'unknown'} dB" }
      lines.concat(["", "## Frequency bands"])
      tracks.each do |track_name, row|
        bands = row.fetch("spectral_bands_db", {})
        next if bands.empty?

        lines << "### #{track_name}"
        bands.each { |name, value| lines << "- #{name}: #{value || 'not measured'} dB" }
      end
      tempo_data = tracks.dig("mix", "tempo") || {}
      tempo_windows = tempo_data.fetch("segments", [])
      lines.concat(["", "## Local tempo windows",
                    "Window size: 60 seconds; valid windows: #{tempo_windows.size}",
                    "Global tempo estimate: #{tempo_data['bpm'] || 'unknown'} BPM",
                    "Window median: #{tempo_data['segment_median_bpm'] || 'unknown'} BPM",
                    "Window range: #{tempo_data['segment_bpm_range'] || 'unknown'} BPM"])
      tempo_windows.each do |segment|
        first = segment.fetch("start_seconds").to_i
        last = segment.fetch("end_seconds").to_i
        lines << format("- %02d:%02d-%02d:%02d: %.1f BPM (confidence %.3f)",
                        first / 60, first % 60, last / 60, last % 60,
                        segment.fetch("bpm"), segment.fetch("confidence"))
      end
      energy_summary = temporal_energy.fetch("summary", {})
      lines.concat(["", "## Temporal energy overview",
                    "Status: #{temporal_energy['status'] || 'not measured'}",
                    "Window count: #{temporal_energy['window_count'] || 0}; window size: #{temporal_energy['window_seconds'] || '?'} seconds"])
      energy_summary.each { |name, value| lines << "- #{name}: #{value}" }
      essentia_summary = essentia.fetch("summary", {})
      lines.concat(["", "## Independent tempo, tonal and groove analysis",
                    "Essentia status: #{essentia['status'] || 'not measured'}"])
      essentia_summary.each { |name, value| lines << "- essentia.#{name}: #{value}" }
      libsonare_summary = libsonare.fetch("summary", {})
      lines << "Libsonare status: #{libsonare['status'] || 'not measured'}"
      libsonare_summary.each { |name, value| lines << "- libsonare.#{name}: #{value}" }
      lines.concat(["", "## Tempo cross-check: FFmpeg versus Essentia"])
      tempo_crosscheck.each { |name, value| lines << "- #{name}: #{value}" }
      lines.concat(["", "## Tempo cross-check: FFmpeg versus libsonare"])
      libsonare_tempo_crosscheck.each { |name, value| lines << "- #{name}: #{value}" }
      lines.concat(["", "## Rhythm analysis source",
                    "Source: #{rhythm_analysis['source'] || 'not measured'}",
                    "Grid positions, accent shares and timing spread are mix/stem-envelope proxies; they do not identify isolated kick, snare or hat hits."])
      rhythm_analysis.fetch("features", {}).each { |name, value| lines << "- #{name}: #{value}" }
      zoom_windows = rhythm_analysis.fetch("zoom_windows", [])
      lines.concat(["", "## Four-, eight- and sixteen-bar rhythm windows",
                    "Each row is a complete window; times are offsets in the source audio.",
                    "| Bars | Start (s) | End (s) | Timing spread (ms) | Onsets/bar | Offbeat share | Sixteenth-grid strength share (cells 1–16) |",
                    "|---:|---:|---:|---:|---:|---:|---|"])
      zoom_windows.each do |window|
        features = window.fetch("features", {})
        spread = features["timing_spread_ms"] || "unknown"
        density = features["onset_density_per_bar"] || "unknown"
        offbeat = features["offbeat_onset_share"] || "unknown"
        shares = features["sixteenth_grid_strength_share"]
        shares_text = shares.is_a?(Array) ? shares.map { |value| format("%.3f", value) }.join(", ") : "unavailable"
        lines << "| #{window['bars']} | #{window['start_seconds']} | #{window['end_seconds']} | #{spread} | #{density} | #{offbeat} | #{shares_text} |"
      end
      lines << "No complete 4-, 8- or 16-bar window had enough onset evidence." if zoom_windows.empty?
      lines.concat(["", "## Tempo cross-check"])
      tempo_crosscheck.each { |name, value| lines << "- #{name}: #{value}" }
      lines.concat(["", "## This reference", JSON.pretty_generate(profile),
                    "", "## Learned style profile", JSON.pretty_generate(learned),
                    "", "Audio only was analyzed. The renderer creates new material and does not use source audio or stems.", ""])
      File.write(path, lines.join("\n"))
    end

    def probe_duration(path, ffprobe)
      out, = capture!("ffprobe duration", ffprobe, "-v", "error", "-show_entries", "format=duration",
                      "-of", "default=noprint_wrappers=1:nokey=1", path)
      Float(out.strip)
    rescue Error, ArgumentError
      nil
    end

    # Give long-form references longer tool budgets while retaining a strict cap.
    # At the two-hour input ceiling each individual analysis pass is capped at one hour.
    def analysis_timeout(max_duration)
      [[max_duration.to_f.ceil / 2, 120].max, 3_600].min
    end

    def capture!(label, *command, timeout: 120)
      stdout, stderr, status = Studio::Subprocess.capture3(*command, timeout:)
      return [stdout, stderr] if status.success?

      raise Error, "#{label} exited #{status.exitstatus}: #{stderr.lines.last(5).join.strip}"
    rescue Errno::ENOENT => error
      raise Error, "#{label}: executable missing (#{error.message})"
    rescue Studio::Subprocess::TimeoutError => error
      raise Error, "#{label} timed out after #{timeout}s (#{error.message})"
    end

    def executable(env, name)
      name = ENV[env].to_s.strip.then { |value| value.empty? ? name : value }
      if name.include?(File::SEPARATOR)
        File.file?(name) && File.executable?(name) ? name : nil
      else
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }
           .find { |path| File.file?(path) && File.executable?(path) }
      end
    end

    def number(text, pattern)
      match = text.match(pattern)
      match && Float(match[1])
    rescue ArgumentError
      nil
    end
  end
end

# --- industrial_techno.rb ---
module Dilla
  # A separate, original industrial-techno engine. The existing Dilla showcase is untouched.
  module IndustrialTechno
    TAU = Math::PI * 2
    ROOTS = [43.65, 46.25, 49.0, 51.91, 55.0].freeze
    MAX_BARS = 32
    module_function

    def run(argv)
      # MASTER selects bars from reference duration and creates a fresh internal seed.
      # Both remain overridable for repeatable, deliberate renders, but need no user input.
      opts = { bpm: nil, bars: nil, seed: nil }
      OptionParser.new do |parser|
        parser.banner = "Usage: ruby dilla.rb industrial-techno [options]"
        parser.on("--bpm N", Float) { |v| opts[:bpm] = v }
        parser.on("--bars N", Integer) { |v| opts[:bars] = v }
        parser.on("--seed N", Integer) { |v| opts[:seed] = v }
        parser.on("--out PATH") { |v| opts[:out] = v }
        parser.on("--reference DIR_OR_JSON") { |v| opts[:reference] = v }
        parser.on("-h", "--help") { puts parser; return 0 }
      end.parse!(argv)
      raise ArgumentError, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?
      profile = read_profile(opts[:reference])
      bpm = (opts[:bpm] || profile&.fetch("target_bpm", nil) || 138).to_f
      raise ArgumentError, "BPM must be 90..190" unless bpm.finite? && bpm.between?(90, 190)
      plan = generation_plan(profile:, bpm:, bars: opts[:bars], seed: opts[:seed])
      bars, seed = plan.values_at(:bars, :seed)
      raise ArgumentError, "bars must be 1..#{MAX_BARS}" unless bars.between?(1, MAX_BARS)
      default_output = File.join(Studio::OutputPaths.dilla_render_directory,
                                  "industrial-techno-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.wav")
      path = File.expand_path(opts[:out] || default_output)
      raise ArgumentError, "refusing to overwrite existing output: #{path}" if File.exist?(path)
      render(path, bpm:, bars:, seed:, profile:)
      puts "dilla0: wrote original industrial techno #{path} (#{bpm.round(1)} BPM, #{bars} bars, seed #{seed})"
      puts "dilla0: reference profile applied" if profile
      0
    rescue ArgumentError, JSON::ParserError => error
      warn "dilla0: #{error.message}"
      2
    rescue StandardError => error
      warn "dilla0: render failed (#{error.class}: #{error.message})"
      1
    end

    # Infer arrangement length from the measured source duration. A full reference
    # can be longer than this renderer's cap, so keep the plan within safe limits.
    # The seed is generated inside Dilla and printed in the render log for traceability.
    def generation_plan(profile:, bpm:, bars: nil, seed: nil)
      duration = begin
        Float(profile&.fetch("source_duration_seconds", nil))
      rescue ArgumentError, TypeError
        nil
      end
      inferred_bars = duration&.positive? ? (duration * bpm.to_f / 240.0).round.clamp(8, MAX_BARS) : 16
      { bars: (bars || inferred_bars).to_i, seed: seed.nil? ? (Random.new_seed & 0xffff_ffff) : seed.to_i }
    end

    def render(path, bpm: 138, bars: nil, seed: nil, profile: nil)
      plan = generation_plan(profile:, bpm:, bars:, seed:)
      bars, seed = plan.values_at(:bars, :seed)
      raise ArgumentError, "bars must be 1..#{MAX_BARS}" unless bars.between?(1, MAX_BARS)
      beat = 60.0 / bpm.to_f
      step = beat / 4.0
      frames = (bars * 4 * beat * SAMPLE_RATE).round
      rng = Random.new(seed)
      root = ROOTS.sample(random: rng)
      pattern = events(bars, rng, root:, step:, profile:)
      p = profile&.fetch("parameters", {}) || {}
      rumble_level = Float(p.fetch("rumble_level", 0.14)).clamp(0.05, 0.35)
      duck_depth = Float(p.fetch("rumble_duck_depth", 0.82)).clamp(0.3, 0.95)
      drive = Float(p.fetch("distortion_drive", 2.0)).clamp(1.0, 4.0)
      break_start = bars >= 8 ? (bars * 0.72).floor : bars + 1
      break_end = bars >= 8 ? [(bars * 0.84).floor, break_start + 1].max : break_start
      brown = 0.0
      prev_noise = 0.0
      FileUtils.mkdir_p(File.dirname(path))
      WAV.write_stream(path, frames:, channels: 2, bits: 24, block_size: 8192) do |offset, count|
        left = Array.new(count, 0.0)
        right = Array.new(count, 0.0)
        count.times do |local|
          i = offset + local
          time = i.to_f / SAMPLE_RATE
          beat_i = (time / beat).floor
          beat_age = time - beat_i * beat
          bar = beat_i / 4
          step_i = (time / step).floor
          step_age = time - step_i * step
          noise = rng.rand * 2.0 - 1.0
          gap = bars >= 8 && bar >= break_start && bar < break_end
          kick_env = gap ? 0.0 : Math.exp(-beat_age * 10.5)
          phase = TAU * (45 * beat_age + 105.0 / 24 * (1.0 - Math.exp(-24 * beat_age)))
          kick = gap ? 0.0 : Math.sin(phase) * kick_env * 0.82 + Math.sin(TAU * 2100 * beat_age) * Math.exp(-beat_age * 190) * 0.12
          brown = brown * 0.997 + noise * 0.025
          duck = 1.0 - kick_env * duck_depth
          rumble = (Math.sin(TAU * root * time) * rumble_level +
                    Math.sin(TAU * root * 1.4142 * time) * rumble_level * 0.39 + brown * rumble_level) * duck
          level = gap ? 0.18 : (bar < 4 ? 0.35 : (bar < 8 ? 0.58 : (bar < 12 ? 0.92 : 1.0)))
          drone = level * (Math.sin(TAU * root * 1.4983 * time) * 0.07 +
                           Math.sin(TAU * root * 2.003 * time) * 0.045 +
                           Math.sin(TAU * root * 2.997 * time) * 0.026) * duck
          bass = 0.0
          if (event = pattern[:bass][step_i]) && step_age < event[:length]
            bphase = TAU * event[:frequency] * step_age
            saw = 2.0 * ((bphase / TAU) % 1.0) - 1.0
            bass = (Math.sin(bphase) * 0.6 + saw * 0.4) * Math.exp(-step_age * event[:decay]) * event[:gain] * level * duck
          end
          clang = 0.0
          pan_m = 0.0
          if (event = pattern[:metal][step_i]) && step_age < event[:decay] * 5
            env = Math.exp(-step_age / event[:decay])
            mphase = TAU * (event[:frequency] * step_age + event[:sweep] * (1.0 - Math.exp(-step_age * 18)) / 18)
            clang = event[:gain] * env * (Math.sin(mphase) + 0.45 * Math.sin(mphase * 1.414) + 0.22 * Math.sin(mphase * 2.31))
            pan_m = event[:pan]
          end
          hat = 0.0
          pan_h = 0.0
          if (event = pattern[:hats][step_i]) && step_age < 0.09
            hat = (noise - prev_noise) * event[:gain] * Math.exp(-step_age * event[:decay])
            pan_h = event[:pan]
          end
          prev_noise = noise
          mono = Math.tanh((kick + rumble + drone + bass + clang + hat + noise * level * 0.012) * drive) / Math.tanh(drive)
          side = clang * pan_m * 0.42 + hat * pan_h * 0.65
          left[local] = ((mono - side) * 0.78).clamp(-0.98, 0.98)
          right[local] = ((mono + side) * 0.78).clamp(-0.98, 0.98)
        end
        [left, right]
      end
      path
    end

    def events(bars, rng, root:, step:, profile:)
      p = profile&.fetch("parameters", {}) || {}
      metal_chance = Float(p.fetch("metal_probability", 0.15)).clamp(0.02, 0.45)
      hat_chance = Float(p.fetch("hat_probability", 0.68)).clamp(0.1, 0.98)
      metal, hats, bass = {}, {}, {}
      motif = [0, 3, 5, 8, 10, 7, 5, 2, 0, 3, 6, 10, 8, 5, 3, 2]
      (bars * 16).times do |index|
        bar = index / 16
        pos = index % 16
        next if bar.zero?
        if pos.even? || rng.rand < hat_chance
          hats[index] = { gain: pos % 8 == 0 ? 0.15 : 0.085, pan: rng.rand * 1.5 - 0.75, decay: 42 + rng.rand * 34 }
        end
        if [0, 6, 10].include?(pos) || (pos == 14 && rng.rand < 0.55)
          midi = motif[(bar * 3 + pos) % motif.size]
          bass[index] = { frequency: root * 2.0**(midi / 12.0), gain: 0.10 + rng.rand * 0.09,
                          decay: 5.0 + rng.rand * 5.0, length: step }
        end
        next if bar < 2
        next unless rng.rand < metal_chance || pos == 14
        metal[index] = { frequency: [277.0, 311.0, 419.0, 503.0, 613.0, 827.0, 1103.0, 1451.0].sample(random: rng),
                         sweep: 90.0 + rng.rand * 820.0, gain: 0.12 + rng.rand * 0.13,
                         pan: rng.rand * 1.7 - 0.85, decay: 0.16 + rng.rand * 0.42 }
      end
      { metal:, hats:, bass: }
    end

    def read_profile(path)
      if path
        expanded = File.expand_path(path)
        candidate = File.directory?(expanded) ? File.join(expanded, "profile.json") : expanded
        raise ArgumentError, "profile genre must be industrial_techno" unless File.file?(candidate) && profile_matches_industrial_techno?(candidate)
        return JSON.parse(File.read(candidate))
      end

      candidate = [Reference.profile_path("industrial_techno"), File.join(Reference::REFERENCE_ROOT, "latest_profile.json")]
                  .find { |file| File.file?(file) && profile_matches_industrial_techno?(file) }
      candidate ? JSON.parse(File.read(candidate)) : nil
    end

    def profile_matches_industrial_techno?(path)
      profile = JSON.parse(File.read(path))
      profile.is_a?(Hash) && profile["genre"] == "industrial_techno"
    rescue JSON::ParserError, Errno::ENOENT, TypeError
      false
    end
  end
end

module Dilla
  # The bed MASTER keeps under a session: a low hum, the surface of a record (hiss, dust, crackle and the
  # odd pop) and slow space tones, put through dilla's own chain (Sonitex, space echo, plate, tape and the
  # master) so it sits in the same room as the beats. Every number is in data/dilla.json under "ambient".
  # A render's tail is folded into its start, so a player can loop it with no seam.
  module Ambient
    TAU = Math::PI * 2
    USAGE = "Usage: ruby dilla.rb ambient [--seconds N] [--seed N] [--out PATH] [--replace]"
    module_function

    # Every sample is plain Ruby, so YJIT is on before the first one.
    def run(argv)
      RubyVM::YJIT.enable if defined?(RubyVM::YJIT) && !RubyVM::YJIT.enabled?
      write(JSON.parse(File.read(File.join(__dir__, "data", "dilla.json"))), options(argv))
    rescue ArgumentError, KeyError, OptionParser::ParseError => error
      warn "dilla0: #{error.message}"
      2
    end

    def options(argv)
      chosen = { seed: Random.new_seed & 0xffff_ffff, replace: false }
      parser = OptionParser.new(USAGE)

      parser.on("--seconds N", Integer) { |value| chosen[:seconds] = value }
      parser.on("--seed N", Integer) { |value| chosen[:seed] = value }
      parser.on("--out PATH") { |value| chosen[:out] = value }
      parser.on("--replace") { chosen[:replace] = true }

      parser.parse!(argv)
      chosen
    end

    def write(data, chosen)
      settings = data.fetch("ambient")
      seconds = chosen.fetch(:seconds) { settings.fetch("seconds") }.clamp(20, 600)
      path = destination(chosen)
      WAV.write(path, render(settings, data, seconds:, seed: chosen[:seed]), replace: chosen[:replace])
      puts "dilla0: wrote ambient #{path} (#{seconds}s, seed #{chosen[:seed]})"
      0
    end

    def destination(chosen)
      named = "ambient-#{Time.now.utc.strftime("%Y%m%dT%H%M%SZ")}.wav"
      path = File.expand_path(chosen.fetch(:out) { File.join(Studio::OutputPaths.dilla_render_directory, named) })
      raise ArgumentError, "refusing to overwrite #{path}; pass --replace" if File.exist?(path) && !chosen[:replace]

      path
    end

    # The hum, the space tones and the surface, each added into the frame.
    def layer(frame, settings, random:)
      hum(frame, spec: settings.fetch("hum"), random:)
      space(frame, spec: settings.fetch("space"), random:)
      surface(frame, spec: settings.fetch("surface"), random:)
    end

    def render(settings, data, seconds:, seed:)
      random = Random.new(seed)
      fade = (settings.fetch("loop_fade_s") * SAMPLE_RATE).round
      frame = Array.new(2) { Array.new((seconds * SAMPLE_RATE).round + fade, 0.0) }
      layer(frame, settings, random:)
      seam(treat(frame, settings:, data:, seed:), fade)
    end

    # A low drone: the partials of one root, the right a few cents above the left so the two beat slowly
    # against each other, over a lowpassed rumble.
    def hum(frame, spec:, random:)
      rumble = rumble(spec, random, frames: frame[0].size)
      spreads = [1.0, 2.0**(spec.fetch("detune_cents") / 1200.0)]
      frame.zip(spreads) { |channel, spread| drone(channel, partials: partials(spec, spread), rumble:) }
    end

    def drone(channel, partials:, rumble:)
      channel.each_index { |i| channel[i] += partials.sum { |step, gain| gain * Math.sin(step * i) } + rumble[i] }
    end

    def partials(spec, spread)
      root = TAU * spec.fetch("hz") * spread / SAMPLE_RATE
      spec.fetch("partials").map { |ratio, gain| [root * ratio, gain * spec.fetch("level")] }
    end

    def rumble(spec, random, frames:)
      noise = Array.new(frames) { (random.rand * 2.0) - 1.0 }
      level = spec.fetch("rumble_level")
      Stream::SmoothLowpass.new(spec.fetch("rumble_hz")).process(noise).map { |sample| sample * level }
    end

    def space(frame, spec:, random:)
      Array.new(spec.fetch("voices")) { Tone.new(spec, random) }.each { |tone| tone.add(frame) }
    end

    # The record's surface: a quiet hiss under three kinds of click.
    def surface(frame, spec:, random:)
      layers = [Hiss.new(spec.fetch("hiss"), random)]
      layers += %w[dust crackle pops].map { |name| Clicks.new(spec.fetch(name), random) }

      frame[0].each_index do |i|
        left, right = layers.map(&:sample).transpose.map(&:sum)
        frame[0][i] += left
        frame[1][i] += right
      end
    end

    # dilla's chain: the Sonitex colour on each side, the ping-pong space echo, a plate, then the tape
    # stack, imager, loudness and limiter of master_frame.
    def treat(frame, settings:, data:, seed:)
      effects = settings.fetch("effects")
      stages = [colour(effects, data:, seed:), echo(effects), plate(effects, seed)]
      coloured = stages.reduce(frame) { |signal, stage| stage.process(signal) }
      master_frame(coloured, data, { lufs: settings.fetch("lufs") }, seed:, bpm: 60, channels: 2).first
    end

    def colour(effects, data:, seed:)
      preset = data.dig("sonitex", "presets").fetch(effects.fetch("sonitex"))
      count = effects.fetch("sonitex_instances")
      Stream::Pair.new(*Array.new(2) { |side| Stream::SonitexStack.new(preset, count, seed + (side * 104_729)) })
    end

    def echo(effects)
      Stream::PingPongEcho.new(delay: effects.fetch("echo_s"), heads: effects.fetch("echo_heads"),
                               intensity: effects.fetch("echo_intensity"), volume: effects.fetch("echo_volume"),
                               lowpass: effects.fetch("echo_lowpass_hz"))
    end

    def plate(effects, seed)
      Stream::Pair.new(*Array.new(2) { |side| Stages::Plate.new(effects.fetch("room"), seed, side) })
    end

    # The tail past the loop length is crossfaded, equal power, into the start; then cut off. The last
    # sample of the result runs straight on into its first.
    def seam(frame, fade)
      length = frame[0].size - fade

      frame.map do |channel|
        head = channel.first(length)

        fade.times do |i|
          angle = Math::PI * 0.5 * i / fade
          head[i] = (head[i] * Math.sin(angle)) + (channel[length + i] * Math.cos(angle))
        end

        head
      end
    end

    # A tone that glides toward a new pitch every so often and fades in or out as it goes, placed somewhere
    # across the field. Drawn from the seed, so nothing in it repeats on a clock.
    class Tone
      def initialize(spec, random)
        @spec = spec
        @random = random
        @glide = (spec.fetch("glide_s") * SAMPLE_RATE).round

        @hz = pitch
        @target = pitch
        @amp = @goal = @phase = 0.0

        pan = random.rand(-0.8..0.8)
        @gains = [(1.0 - pan) * 0.5, (1.0 + pan) * 0.5].map { |gain| gain * spec.fetch("level") }
        @offset = random.rand(@glide)
      end

      def add(frame)
        left, right = @gains

        frame[0].each_index do |i|
          retarget if ((i + @offset) % @glide).zero?
          advance
          sample = Math.sin(@phase) * @amp
          frame[0][i] += sample * left
          frame[1][i] += sample * right
        end
      end

      private

      def pitch = @random.rand(@spec.fetch("low_hz")..@spec.fetch("high_hz"))

      def retarget
        @target = pitch
        @goal = @random.rand < @spec.fetch("presence") ? 1.0 : 0.0
      end

      def advance
        @hz += (@target - @hz) * 4.0 / @glide
        @amp += (@goal - @amp) * 3.0 / @glide
        @phase += TAU * @hz / SAMPLE_RATE
      end
    end

    # A quiet hiss: independent noise on each side through its own lowpass.
    class Hiss
      def initialize(spec, random)
        @random = random
        @level = spec.fetch("level")
        @filters = Array.new(2) { Stream::Lowpass.new(spec.fetch("lowpass_hz")) }
      end

      def sample = @filters.map { |filter| filter.step((@random.rand * 2.0) - 1.0) * @level }
    end

    # One kind of click (fine dust, crackle, the odd pop): a decaying impulse at random moments through its
    # own lowpass, landing a little more in one ear. Most are faint and a few loud (the cube of a uniform
    # draw), with either sign.
    class Clicks
      def initialize(spec, random)
        @random = random
        @chance = spec.fetch("rate") / SAMPLE_RATE.to_f
        @level = spec.fetch("level")

        @decay = Math.exp(-1000.0 / (spec.fetch("decay_ms") * SAMPLE_RATE))
        @filter = Stream::Lowpass.new(spec.fetch("lowpass_hz"))
        @value = @balance = 0.0
      end

      def sample
        strike if @random.rand < @chance
        @value *= @decay
        out = @filter.step(@value)
        [out * (1.0 - @balance), out * (1.0 + @balance)]
      end

      private

      def strike
        @value += @level * (@random.rand**3) * (@random.rand < 0.5 ? -1.0 : 1.0)
        @balance = @random.rand(-0.6..0.6)
      end
    end
  end
end

# ---------------------------------------------------------------- sound events
# Short, manifest-driven lifecycle cues. They use the same sample rate, WAV writer,
# Sonitex colour, dub echo, plate, tape and master chain as Dilla's music. No speech
# samples or external sound-effect runtime is required.
module Dilla
  module SoundFx
    module_function

    EVENTS = %w[start submit complete error notification precompact session_end].freeze
    MANIFEST_PATH = File.join(__dir__, "data", "sound_fx.json")
    ENGINE_DATA_PATH = File.join(__dir__, "data", "dilla.json")
    USAGE = "Usage: ruby dilla.rb sound-fx EVENT [--play | --out PATH] [--seed N] [--volume 0..100]"

    def run(argv)
      event = argv.shift
      sound_data = JSON.parse(File.read(MANIFEST_PATH))
      return list(sound_data) if event == "list"
      raise ArgumentError, USAGE unless EVENTS.include?(event)

      options = { seed: Random.new_seed & 0xffff_ffff, play: false, replace: false, volume: 45 }
      OptionParser.new(USAGE) do |parser|
        parser.on("--out PATH", "Write a WAV to PATH rather than the default render directory") { |value| options[:out] = value }
        parser.on("--seed N", Integer, "Deterministic synthesis seed") { |value| options[:seed] = value }
        parser.on("--play", "Play the cue locally without keeping a WAV") { options[:play] = true }
        parser.on("--volume N", Integer, "Player volume, 0..100 (default 45)") { |value| options[:volume] = value }
        parser.on("--player CMD", "Explicit player command, passed as argv (no shell)") { |value| options[:player] = value }
        parser.on("--replace", "Allow replacing an existing --out WAV") { options[:replace] = true }
      end.parse!(argv)
      raise ArgumentError, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?
      raise ArgumentError, "--volume must be 0..100" unless (0..100).cover?(options[:volume])
      raise ArgumentError, "--replace requires --out" if options[:replace] && !options[:out]
      raise ArgumentError, "choose either --play or --out, not both" if options[:play] && options[:out]

      engine_data = JSON.parse(File.read(ENGINE_DATA_PATH))
      frame = render(event, sound_data:, engine_data:, seed: options[:seed])
      if options[:play]
        play_temporary(frame, event, options)
      else
        path = destination(event, options)
        WAV.write(path, frame, replace: options[:replace])
        puts JSON.generate(result_payload(event, frame, options[:seed]).merge("path" => path, "played" => false))
      end
      0
    rescue ArgumentError, KeyError, OptionParser::ParseError, JSON::ParserError, SystemCallError => error
      warn "dilla-fx0: #{error.class}: #{error.message}"
      2
    end

    def list(sound_data = JSON.parse(File.read(MANIFEST_PATH)))
      validate_manifest!(sound_data)
      puts JSON.generate(status: "ready", events: EVENTS)
      0
    rescue ArgumentError, KeyError, JSON::ParserError, SystemCallError => error
      warn "dilla-fx0: #{error.class}: #{error.message}"
      2
    end

    # Public for deterministic unit tests and other Ruby callers. Returns stereo Float samples
    # in [-1, 1], already coloured and peak-controlled through Dilla's own mastering path.
    def render(event, sound_data: JSON.parse(File.read(MANIFEST_PATH)),
               engine_data: JSON.parse(File.read(ENGINE_DATA_PATH)), seed: 0)
      validate_manifest!(sound_data)
      raise ArgumentError, "unknown sound event #{event.inspect}" unless EVENTS.include?(event.to_s)

      spec = sound_data.fetch("events").fetch(event.to_s)
      validate_event!(spec)
      note_end_ms = spec.fetch("notes").map do |note|
        note.fetch("at_ms") + note.fetch("duration_ms") + note.fetch("release_ms")
      end.max
      click_end_ms = Array(spec["transients"]).map do |click|
        click.fetch("at_ms") + (click.fetch("decay_ms") * 7)
      end.max || 0
      duration_ms = [note_end_ms, click_end_ms].max + spec.fetch("tail_ms", sound_data.fetch("tail_ms"))
      raise ArgumentError, "cue duration exceeds 3 seconds" unless duration_ms.between?(100, 3000)

      frames = (duration_ms * SAMPLE_RATE / 1000.0).ceil
      frame = Array.new(2) { Array.new(frames, 0.0) }
      spec.fetch("notes").each_with_index { |note, index| add_note(frame, note, index) }
      Array(spec["transients"]).each_with_index do |click, index|
        add_transient(frame, click, Random.new(seed.to_i + ((index + 1) * 10_007)))
      end

      # Dilla's own colour → ping-pong echo → plate → tape/mastering chain.
      treated = Ambient.treat(frame, settings: engine_data.fetch("ambient"), data: engine_data, seed: seed.to_i)
      peak_control(treated, target_dbfs: sound_data.fetch("target_peak_dbfs", -13.0))
    end

    def validate_manifest!(sound_data)
      raise ArgumentError, "sound FX manifest schema must be 1" unless sound_data.fetch("schema") == 1
      raise ArgumentError, "sound FX events must exactly match the lifecycle contract" unless
        sound_data.fetch("events").keys.sort == EVENTS.sort
      true
    end
    private_class_method :validate_manifest!

    def validate_event!(spec)
      notes = spec.fetch("notes")
      raise ArgumentError, "event needs at least one note" unless notes.is_a?(Array) && !notes.empty?
      notes.each do |note|
        midi = Integer(note.fetch("midi"))
        raise ArgumentError, "MIDI note must be 24..96" unless (24..96).cover?(midi)
        validate_range!(note.fetch("at_ms"), 0, 1800, "note at_ms")
        validate_range!(note.fetch("duration_ms"), 20, 600, "note duration_ms")
        validate_range!(note.fetch("release_ms"), 20, 900, "note release_ms")
        validate_range!(note.fetch("attack_ms", 5), 1, 100, "note attack_ms")
        validate_range!(note.fetch("gain"), 0.0, 1.0, "note gain")
        validate_range!(note.fetch("pan", 0.0), -1.0, 1.0, "note pan")
        validate_range!(note.fetch("overtone", 0.0), 0.0, 0.5, "note overtone")
      end
      Array(spec["transients"]).each do |click|
        validate_range!(click.fetch("at_ms"), 0, 1800, "transient at_ms")
        validate_range!(click.fetch("decay_ms"), 2, 120, "transient decay_ms")
        validate_range!(click.fetch("gain"), 0.0, 0.2, "transient gain")
        validate_range!(click.fetch("lowpass_hz"), 400, 12_000, "transient lowpass_hz")
        validate_range!(click.fetch("pan", 0.0), -1.0, 1.0, "transient pan")
      end
      true
    end
    private_class_method :validate_event!

    def validate_range!(value, minimum, maximum, label)
      number = Float(value)
      raise ArgumentError, "#{label} must be within #{minimum}..#{maximum}" unless number.finite? && (minimum..maximum).cover?(number)
      number
    end
    private_class_method :validate_range!

    def add_note(frame, note, order)
      start = (note.fetch("at_ms") * SAMPLE_RATE / 1000.0).round
      held = [(note.fetch("duration_ms") * SAMPLE_RATE / 1000.0).round, 1].max
      release = [(note.fetch("release_ms") * SAMPLE_RATE / 1000.0).round, 1].max
      attack = [(note.fetch("attack_ms", 5) * SAMPLE_RATE / 1000.0).round, 1].max
      hz = Chords.hz(note.fetch("midi"))
      gain = note.fetch("gain").to_f
      pan = note.fetch("pan", 0.0).to_f
      overtone = note.fetch("overtone", 0.0).to_f
      left = Math.cos((pan + 1.0) * Math::PI / 4.0)
      right = Math.sin((pan + 1.0) * Math::PI / 4.0)
      count = [held + release, frame.first.size - start].min
      return unless count.positive?

      count.times do |offset|
        envelope = if offset < attack
                     0.5 - (0.5 * Math.cos(Math::PI * offset / attack))
                   elsif offset < held
                     1.0
                   else
                     Math.exp(-5.0 * (offset - held).to_f / release)
                   end
        phase = (2.0 * Math::PI * hz * offset / SAMPLE_RATE) + (order * 0.017)
        sample = gain * envelope * (Math.sin(phase) + (overtone * Math.sin(phase * 2.0)))
        index = start + offset
        frame[0][index] += sample * left
        frame[1][index] += sample * right
      end
    end
    private_class_method :add_note

    def add_transient(frame, click, random)
      start = (click.fetch("at_ms") * SAMPLE_RATE / 1000.0).round
      decay = [(click.fetch("decay_ms") * SAMPLE_RATE / 1000.0).round, 1].max
      finish = [start + (decay * 7), frame.first.size].min
      return if start >= finish

      filters = Array.new(2) { Stream::Lowpass.new(click.fetch("lowpass_hz")) }
      pan = click.fetch("pan", 0.0).to_f
      gains = [Math.cos((pan + 1.0) * Math::PI / 4.0), Math.sin((pan + 1.0) * Math::PI / 4.0)]
      (start...finish).each do |index|
        elapsed = index - start
        impulse = ((random.rand * 2.0) - 1.0) * click.fetch("gain").to_f * Math.exp(-5.0 * elapsed / decay)
        filters.each_with_index do |filter, channel|
          frame[channel][index] += filter.step(impulse) * gains[channel]
        end
      end
    end
    private_class_method :add_transient

    def peak_control(frame, target_dbfs:)
      target = Float(target_dbfs)
      raise ArgumentError, "target peak must be -24..-6 dBFS" unless target.finite? && (-24.0..-6.0).cover?(target)
      peak = frame.flatten.map(&:abs).max.to_f
      raise ArgumentError, "sound FX render is silent or invalid" unless peak.positive? && peak.finite?
      gain = (10.0**(target / 20.0)) / peak
      frame.map { |channel| channel.map { |sample| sample * gain } }
    end
    private_class_method :peak_control

    def destination(event, options)
      stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
      filename = "dilla-fx-#{event}-#{stamp}-#{options.fetch(:seed)}.wav"
      path = File.expand_path(options.fetch(:out) { File.join(Studio::OutputPaths.dilla_render_directory, filename) })
      raise ArgumentError, "refusing to overwrite existing take: #{path}; pass --replace" if File.exist?(path) && !options[:replace]
      path
    end
    private_class_method :destination

    def play_temporary(frame, event, options)
      Dir.mktmpdir("dilla-sound-fx-") do |directory|
        path = File.join(directory, "#{event}.wav")
        playback = frame.map { |channel| channel.map { |sample| sample * (options.fetch(:volume) / 100.0) } }
        WAV.write(path, playback)
        playback_exit = if termux_player?(options)
                          play_termux(path, duration_s: frame.first.size.fdiv(SAMPLE_RATE))
                        else
                          play_local(path, options)
                        end

        puts JSON.generate(result_payload(event, frame, options[:seed]).merge("path" => nil, "played" => true,
                                                                               "playback_exit" => playback_exit,
                                                                               "playback_volume_percent" => options.fetch(:volume)))
      end
    end
    private_class_method :play_temporary

    def termux_player?(options)
      options[:player].nil? && termux_host? && !executable_path("termux-media-player").nil?
    end
    private_class_method :termux_player?

    def termux_host?
      RUBY_PLATFORM.downcase.include?("android") || ENV.fetch("PREFIX", "").include?("/com.termux/")
    end
    private_class_method :termux_host?

    # Termux:API starts media in an Android service and its command may exit before the
    # file is consumed. Keep the temporary file alive for the cue duration, then stop
    # the service so an API/player failure cannot leave a looping or stale sound behind.
    def play_termux(path, duration_s:)
      player = executable_path("termux-media-player")
      raise ArgumentError, "Termux:API media player is not installed" unless player

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      pid = Process.spawn(player, "play", path, out: File::NULL, err: File::NULL, pgroup: true)
      begin
        _waited_pid, status = Timeout.timeout([duration_s + 1.0, 4.0].min) { Process.wait2(pid) }
      rescue Timeout::Error
        terminate_player(pid)
        raise ArgumentError, "Termux:API player command exceeded its time budget"
      end
      raise ArgumentError, "Termux:API player exited with status #{status.exitstatus || status.termsig}" unless status.success?

      remaining = duration_s + 0.18 - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      sleep(remaining) if remaining.positive?
      stop_termux(player)
      0
    end
    private_class_method :play_termux

    def stop_termux(player)
      pid = Process.spawn(player, "stop", out: File::NULL, err: File::NULL, pgroup: true)
      _waited_pid, status = Timeout.timeout(1) { Process.wait2(pid) }
      raise ArgumentError, "Termux:API could not stop the cue player" unless status.success?
    rescue Timeout::Error
      terminate_player(pid) if pid
      raise ArgumentError, "Termux:API stop command exceeded its time budget"
    rescue Errno::ENOENT, Errno::ECHILD => error
      raise ArgumentError, "Termux:API stop command unavailable: #{error.message}"
    end
    private_class_method :stop_termux

    def play_local(path, options)
      command = player_argv(path, options)
      pid = Process.spawn(*command, out: File::NULL, err: File::NULL, pgroup: true)
      begin
        _waited_pid, status = Timeout.timeout(4) { Process.wait2(pid) }
      rescue Timeout::Error
        terminate_player(pid)
        raise ArgumentError, "audio player exceeded the 4-second cue budget"
      end
      raise ArgumentError, "audio player exited with status #{status.exitstatus || status.termsig}" unless status.success?

      status.exitstatus || 0
    end
    private_class_method :play_local

    def player_argv(path, options)
      if options[:player]
        command = Shellwords.split(options[:player].to_s)
        raise ArgumentError, "--player must name a command" if command.empty?
        return [*command, path]
      end

      if RUBY_PLATFORM.include?("darwin") && (player = executable_path("afplay"))
        [player, path]
      elsif (player = executable_path("ffplay"))
        [player, "-nodisp", "-autoexit", "-loglevel", "quiet", path]
      elsif (player = executable_path("play"))
        [player, "-q", path]
      else
        raise ArgumentError, "no supported audio player found; install afplay, ffplay, SoX play, or Termux:API"
      end
    end
    private_class_method :player_argv

    def terminate_player(pid)
      Process.kill("TERM", -pid)
      sleep 0.1
      Process.kill("KILL", -pid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    ensure
      Process.wait(pid) rescue nil
    end
    private_class_method :terminate_player

    # Only execute players found at an explicit absolute PATH entry. Passing the resolved
    # executable path to spawn prevents an earlier relative PATH component from shadowing
    # the checked binary. The explicit --player option remains an operator-owned override.
    def executable_path(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
        next if directory.empty? || !directory.start_with?(File::SEPARATOR)

        candidate = File.join(directory, name)
        return candidate if File.file?(candidate) && File.executable?(candidate)
      end
      nil
    end
    private_class_method :executable_path

    def result_payload(event, frame, seed)
      metrics = Mastering.report(frame)
      { status: "rendered", event:, seed:, sample_rate: SAMPLE_RATE, frames: frame.first.size,
        duration_s: frame.first.size.fdiv(SAMPLE_RATE).round(3),
        sample_peak_dbfs: peak_dbfs(frame),
        true_peak_db: metrics.fetch(:true_peak_db), integrated_lufs: metrics.fetch(:lufs),
        style_chain: "dilla_ambient_colour_echo_plate_master" }
    end
    private_class_method :result_payload

    def peak_dbfs(frame)
      peak = frame.flatten.map(&:abs).max.to_f
      peak.positive? ? 20.0 * Math.log10(peak) : -Float::INFINITY
    end
    private_class_method :peak_dbfs
  end
end

# --- engine.rb ---
# Reference analysis and industrial-techno generation stay in their own modules.

# Stable machine-readable path surface for MASTER/contracts/studio.rb. The
# path policy itself stays in STUDIO/output_paths.rb; MASTER never imports it.
def dilla_output_path(argv)
  kind = argv.shift
  path = case kind
         when "reference-root"
           raise ArgumentError, "reference-root takes no arguments" unless argv.empty?

           Studio::OutputPaths.reference_root
         when "dilla-render-directory"
           at_text = argv.shift
           raise ArgumentError, "dilla-render-directory requires one ISO 8601 timestamp" if at_text.to_s.empty?
           raise ArgumentError, "unexpected output-path arguments" unless argv.empty?

           Studio::OutputPaths.dilla_render_directory(at: Time.iso8601(at_text))
         else
           raise ArgumentError, "unknown output path #{kind.inspect}; use reference-root or dilla-render-directory"
         end
  raise ArgumentError, "STUDIO output path is not absolute" unless path.start_with?(File::SEPARATOR)

  puts path
  0
rescue ArgumentError => error
  warn "dilla0: output-path: #{error.message}"
  2
end

# ---------------------------------------------------------------------- CLI
def run(argv)
  subcommand, *rest = argv
  return Dilla::Reference.run(rest) if subcommand == "reference"
  return Dilla::IndustrialTechno.run(rest) if subcommand == "industrial-techno"
  return Dilla::Ambient.run(rest) if subcommand == "ambient"
  return Dilla::SoundFx.run(rest) if subcommand == "sound-fx"
  return dilla_output_path(rest) if subcommand == "output-path"
  RubyVM::YJIT.enable if defined?(RubyVM::YJIT) && !RubyVM::YJIT.enabled? && !ENV.key?("DILLA_NO_YJIT") # about a third off every render
  live_argument = argv.first == "live"
  argv = argv.drop(1) if live_argument
  options = {}
  OptionParser.new do |o|
    o.banner = "Usage: ruby dilla.rb [options] | reference URL_OR_AUDIO | industrial-techno [options]"
    o.on("--showcase", "Render the default showcase: the Blue Hour suite and the rest of the room") { options[:showcase] = true }
    o.on("--arrangement PATH", "With --showcase: play the sections of this JSON file, not data/showcase.json") do |v|
      options[:arrangement] = v
      options[:showcase] = true
    end
    o.on("--video PATH", "Write the matching MP4 visualizer at PATH") { |v| options[:video] = v }
    o.on("--no-video", "Render only the WAV; do not encode an MP4") { options[:video] = false }
    o.on("--video-preset NAME", "Postpro video preset (default dilla_heavy)") { |v| options[:video_preset] = v }
    o.on("--effect-rig NAME", "Apply a named bus-effects rig from data/dilla.json") { |v| options[:effect_rig] = v }
    o.on("--live", "Loop the showcase through the system audio player") { options[:live] = true }
    o.on("--render", "Write one random take to a new file under the renders folder instead of playing live") { options[:render] = true }
    o.on("--map", "Print the table of contents of this file: every module and class with its line number") { options[:map] = true }
    o.on("--list", "List progressions, drum patterns, groove profiles, voicings and harmonic languages") { options[:list] = true }
    o.on("--voicing STYLE", Chords::STYLES, "Lay every chord out as #{Chords::STYLES.join(', ')} (default: voice-led)") { |v| Chords.use(v) }
    o.on("--progression N", Integer, "Progression index (see --list)") { |v| options[:prog] = v }
    o.on("--random", "Random progression and drum pattern (the default groove profile)") { options[:random] = true }
    o.on("--drums NAME", "Drum pattern name, or rotate to change the pattern every phrase") { |v| options[:drums] = v }
    o.on("--kit NAME", "The drum kit (see kits in dilla.json)") { |v| options[:kit] = v }
    o.on("--profile NAME", "Groove profile name") { |v| options[:profile] = v }
    o.on("--groove N", Float, "pd_amount, 0 to 1.5: how far the profile pulls from the grid") { |v| options[:groove] = v }
    o.on("--bpm N", Float, "Tempo (default 88)") { |v| options[:bpm] = v }
    o.on("--beats N", Float, "Beats per chord (default 8, two bars)") { |v| options[:beats] = v }
    o.on("--gate N", Float, "Note gate as a share of its step, 0.05 to 1.5") { |v| options[:gate] = v.clamp(0.05, 1.5) }
    o.on("--seed N", Integer, "Seed: the same seed plays the same render") { |v| options[:seed] = v }
    o.on("--out PATH", "Output WAV path") { |v| options[:out] = v }
    o.on("--replace", "Explicitly replace an existing WAV or MIDI take") { options[:replace] = true }
    o.on("--midi PATH", "Also write a Standard MIDI File") { |v| options[:midi] = v }
    o.on("--no-voice-search", "Voice each chord by nearest tones only, without the octave search") { options[:plain] = true }
    o.on("--arp [PATTERN]", "Play each chord one note at a time: up, down, updown, converge, spiral, pendulum, flow and more; --arp list names them") { |v| options[:arp] = v || true }
    o.on("--strum [MS]", Float, "Stagger the notes of each chord, lowest first, by MS milliseconds (default from the data)") { |v| options[:strum] = v || true }
    o.on("--pad", "A soft sustained pad under the arpeggio") { options[:pad] = true }
    o.on("--echo [HEADS]", "Tape space echo; heads such as 1 or 1,2 or 1,2,3") { |v| options[:echo] = v || true }
    o.on("--echo-mix N", Float, "Echo volume against the dry sound") { |v| options[:echo_mix] = v }
    o.on("--echo-feedback N", Float, "Echo intensity, 0 to 0.9: how much of each repeat comes round again") { |v| options[:echo_feedback] = v }
    o.on("--echo-time MS", Float, "Echo base delay in milliseconds (default a dotted eighth)") { |v| options[:echo_time] = v }
    o.on("--play", "--endless", "Never stop: stream pass after pass into the player, each beginning under the last beat of the one before") { options[:play] = true }
    o.on("--player CMD", "The player: for live it is given the wav path (default afplay, else ffplay); for --play it reads raw 16-bit mono PCM on stdin (default ffplay, else sox play)") { |v| options[:player] = v }
    o.on("--decks N", Integer, "With --play: 2 decks cross over eight to sixteen bars (the default), 1 plays pass after pass under a one-beat crossfade") { |v| options[:decks] = v.clamp(1, 2) }
    o.on("--moves N", Float, "With --play: live moves a minute on average, 0 for none (default 3 with two decks)") { |v| options[:moves] = v }
    o.on("--passes N", Integer, "With --play, stop after N progressions") { |v| options[:passes] = v }
    o.on("--voice NAME", "The voice that plays the notes (see data/dilla.json): pure_tone, sine, moog_*, rhodes_*, dfam") { |v| options[:voice] = v }
    o.on("--repeat [STYLE]", "--comp [STYLE]", "Strike the whole chord again on the steps of a style instead of arpeggiating") { |v| options[:repeat] = v || true }
    o.on("--patch-per-chord", "In pad mode, give every chord its own patch, drawn from the one bag of all patches") { options[:patch_per_chord] = true }
    o.on("--mode MODE", "arp, repeat, pad or organ: force how the chords are played") { |v| options[:mode] = v }
    o.on("--key NAME", "With --mode organ: the tonic, such as D or Bb (else drawn from the seed)") { |v| options[:key] = v }
    o.on("--scale NAME", "With --mode organ: harmonic_minor, natural_minor, major or dorian (else drawn from the seed)") { |v| options[:scale] = v }
    o.on("--bars N", Integer, "With --mode organ: bars of improvisation, one chord a bar (default from the data)") { |v| options[:bars] = v }
    o.on("--arp-rate N", "Sixteenths per arp note: 2 eighth, 3 dotted eighth, 4 quarter, 6, 8; 3T for triplets") { |v| options[:arp_rate] = v }
    o.on("--arp-style NAME", "A row of arp.styles in data/dilla.json") { |v| options[:arp_style] = v }
    o.on("--lufs N", Float, "Integrated loudness the master brings the sound to (default -14)") { |v| options[:lufs] = v.clamp(-40.0, -3.0) }
    o.on("--no-master", "Leave out the mixing and mastering chain: no EQ, multiband, glue, loudness or true-peak limiter") { options[:master] = false }
    o.on("--bits N", Integer, "Bit depth of a written wav, 16 (dithered) or 24") { |v| options[:bits] = v == 24 ? 24 : 16 }
    o.on("--mono", "One channel, with no panning, no ping-pong echo and no stereo imager (the default is stereo)") { options[:mono] = true }
    o.on("--tape N", Integer, "Tape machines in series as the last stage, 0 to 8; 0 leaves the sound untouched (default from the data)") { |v| options[:tape] = v.clamp(0, 8) }
    o.on("--tape-drive X", Float, "How hard the first tape machine is driven, 0.1 to 4; later machines step up from it") { |v| options[:tape_drive] = v.clamp(0.1, 4.0) }
    o.on("--sonitex [PRESET]", "The 12-bit sampler colour chain on the voice bus") { |v| options[:sonitex] = v || true }
    o.on("--sonitex-instances N", Integer, "Run it 1 to 3 times: one is a colour, three are a sound") { |v| options[:sonitex_instances] = v }
    o.on("--drum-tape LEVEL", %w[light medium heavy], "Analogue tape saturation on the drum bus") { |v| options[:drum_tape] = v }
    o.on("--vcs [AMOUNT]", Float, "The summing colour, 0 to 1, on each bus and the master") { |v| options[:vcs] = v || true }
    o.on("--key-lock NOTE", "Bring every progression to rest on NOTE (e.g. Bb), keeping its chord qualities") { |v| options[:key_lock] = v }
    o.on("--improvise", "Add a lead and a bass worked out from the chords (curated sections)") { options[:improvise] = true }
    o.on("--takes N", Integer, "With --showcase: render each section N times from different seeds and keep the one the critic scores nearest the target") { |v| options[:takes] = v.clamp(1, 9) }
    o.on("--transpose N", Integer, "Move every note N semitones before synthesis; tempo and echo timing stay") { |v| options[:transpose] = v }
    o.on("--octaves N", Integer, "Sugar for --transpose 12*N") { |v| options[:transpose] = 12 * v }
    o.on("--transpose-wrap", "Fold any note still above 14 kHz down by octaves") { options[:wrap] = true }
    o.on("--kick-db N", Float, "Kick level in dB (default from the data)") { |v| (options[:mix] ||= {})["kick"] = v }
    o.on("--snare-db N", Float, "Snare and clap level in dB") { |v| (options[:mix] ||= {}).merge!("snare" => v, "clap" => v) }
    o.on("--hat-db N", Float, "Hat level in dB") { |v| (options[:mix] ||= {})["hat"] = v }
    o.on("--chords-db N", Float, "Chord and arp level in dB when drums play") { |v| (options[:mix] ||= {})["chords"] = v }
    o.on("--drum-balance DB", Float, "Reference-derived dB shift to all drum roles, bounded to +/-2 dB") { |v| options[:drum_balance] = v.clamp(-2.0, 2.0) }
    o.on("--chord-balance DB", Float, "Reference-derived dB shift to chords, bounded to +/-2 dB") { |v| options[:chord_balance] = v.clamp(-2.0, 2.0) }
    o.on("--pool POOL", %w[essential all], "With --play: essential progressions (default) or all") { |v| options[:pool] = v }
    o.on("--quick", "Render the first progression as a smoke test") { options[:quick] = true }
  end.parse!(argv)
  options[:live] = true if live_argument

  data = JSON.parse(File.read(File.join(__dir__, "data", "dilla.json")))
  apply_effect_rig!(options, data) if options[:effect_rig]
  if bare_run?(options)
    if options[:render]
      randomize_take!(data, options)
    else
      # The no-argument contract is a complete, finite WAV + MP4 composition.
      # Endless random playback stays explicit as "live" or --play.
      options[:showcase] = true
    end
  end

  # A render to the default location is replaceable; an explicit --out still refuses.
  options[:replace] = true if options[:out].nil?

  if options[:showcase]
    defaults = Dilla::Video.default_paths(root: __dir__)
    options[:out] ||= defaults.fetch(:audio)
    options[:video] = Dilla::Video.paired_path(options[:out]) if options[:video].nil?
  end

  return puts(Studio::SourceMap.render(__FILE__)) if options[:map]

  unless options[:replace] || options[:play] || options[:live] || options[:list] || options[:arp] == "list"
    outputs = []
    if options[:out]
      outputs << options[:out]
    elsif options[:quick]
      outputs << "out/quick.wav"
    elsif options[:showcase] || (options[:prog].nil? && !options[:random] && !options[:quick] && options[:mode] != "organ")
      outputs << File.join(__dir__, "dilla.wav")
    end
    outputs << options[:midi] if options[:midi]
    outputs << options[:video] if options[:video].is_a?(String)
    existing = outputs.find { |path| File.exist?(path) || File.symlink?(path) }
    abort "studio0: refusing to overwrite existing take #{existing.inspect}; choose a new path or pass --replace" if existing
  end

progressions = data.fetch("progressions")

if options[:arp] == "list"
  puts "Arp patterns: #{data.dig('arp', 'patterns').join(', ')}"
  puts "Arp styles: #{data.dig('arp', 'styles').keys.join(', ')}"
  puts "Arp modifiers: #{(data.fetch('arp').keys & %w[euclidean probability note_repeat ratchet humanize grace]).join(', ')}"
elsif options[:play]
    play_forever(data, options)
  elsif options[:live]
    play_showcase(data, options)
  elsif options[:list]
    puts "Progressions:"
    progressions.each_with_index do |chords, i|
      puts format("%4d  %s%s", i, chords.join(" "), options[:key_lock] ? format("  [fit %.2f]", ModalFamily.fit(chords, options[:key_lock])) : "")
    end
    puts
    puts "Drum patterns: #{data['drum_patterns'].keys.join(', ')}"
    puts "Groove profiles: #{data['groove_profiles'].keys.join(', ')}"
    puts "Voicings (--voicing): #{Chords::STYLES.join(', ')}"
    puts
    puts "Harmonic languages (a progression written from rules, in Bb):"
    Languages.all.each { |language, chords| puts format("  %-24s %s", language, chords.join(" ")) }
  elsif options[:showcase] || (options[:prog].nil? && !options[:random] && !options[:quick] && options[:mode] != "organ")
    render_showcase(data, options)
  elsif options[:effect_rig]
    render_effect_rig_take(data, options)
  else
    render(data, options)
  end
end

# Apply one canonical bus-effects row to an ordinary progression render. Explicit CLI values
# retain precedence; data/dilla.json remains the single source for each rig's defaults.
def apply_effect_rig!(options, data)
  name = options[:effect_rig]
  return options unless name

  rig = data.fetch("bus_effects").fetch(name) { abort "studio0: unknown effect rig #{name.inspect}" }
  {
    drum_sonitex: "drum_sonitex",
    drum_sonitex_instances: "drum_sonitex_instances",
    drum_tape: "drum_tape",
    drum_vcs: "drum_vcs",
    drum_dub_echo: "drum_dub_echo",
    drum_crystallizer: "drum_crystallizer",
    instrument_dub_echo: "instrument_dub_echo",
    instrument_crystallizer: "instrument_crystallizer",
  }.each do |option, key|
    options[option] = rig.fetch(key) unless options.key?(option)
  end
  options
end

# Flags that choose what is played. A run that names none of them is a bare run, and a bare

# run is a new take every time; --showcase is the way to the fixed Blue Hour piece.
CONTENT_FLAGS = %i[showcase live list prog random drums kit profile arp arp_style repeat voice mode play quick
                   patch_per_chord].freeze

def bare_run?(options) = (options.keys & CONTENT_FLAGS).empty?

# A random take from the whole of the data: any progression, mode, arp or repeat style, patch,
# groove profile, kit and drum pattern, each from its own shuffle bag so a bare run never plays
# the same thing twice running within a cycle. It writes under the renders folder, outside the
# repo, and never over an earlier take.
def randomize_take!(data, options)
  seed = options[:seed] || Random.new_seed % 1_000_000
  playlist = Playlist.new(data, Random.new(seed), pool: "all")
  profile = data.fetch("groove_profiles").keys.sort.sample(random: Random.new(seed))
  pick = playlist.draw(profile:, mode: nil)
  options.merge!(prog: pick[:prog], seed:, profile:, voice: pick[:voice], mode: pick[:mode], random: true,
                 kit: pick[:kit], chord_voices: pick[:voices])
  options[:arp_style] = pick[:style] if pick[:mode] == "arp"
  options[:repeat] = pick[:style] if pick[:mode] == "repeat"
  options[:drums] = data.fetch("groove_profiles").fetch(profile)["drums"] || pick[:drums]
  now = Time.now.utc
  options[:out] ||= File.join(Studio::OutputPaths.dilla_render_directory(at: now),
                              "dilla-#{now.strftime('%H%M%S')}-#{seed}.wav")
  puts "studio0: new take, seed #{seed}, progression #{pick[:prog]}, #{pick[:mode]}#{pick[:style] ? " #{pick[:style]}" : ''}, " \
       "voice #{pick[:voice]}, profile #{profile}, kit #{pick[:kit]}"
  options
end

# Apply bounded, relative dB moves after loading Dilla's own mix defaults. MASTER
# passes these only when a separated reference supplies usable stem-energy evidence.
def apply_reference_mix_balance(levels, drum_balance: nil, chord_balance: nil)
  adjusted = levels.dup
  unless drum_balance.nil?
    offset = Float(drum_balance).clamp(-2.0, 2.0)
    %w[kick snare clap hat perc].each do |role|
      adjusted[role] = adjusted.fetch(role, 0.0).to_f + offset
    end
  end
  unless chord_balance.nil?
    offset = Float(chord_balance).clamp(-2.0, 2.0)
    adjusted["chords"] = adjusted.fetch("chords", 0.0).to_f + offset
  end
  adjusted
end

# How the chords are played: the flags, else what the profile carries, else a held pad.
def play_mode(options, seq)
  return options[:mode] if options[:mode]
  return "repeat" if options[:repeat] || (!options[:arp] && seq.comp_settings(nil))
  return "arp" if options[:arp] || options[:arp_style] || seq.arp_settings(nil)

  "pad"
end

def parse_rate(text)
  return unless text

  text.to_s.match(/\A(\d+(?:\.\d+)?)(T?)\z/) or abort "Bad --arp-rate: #{text}"
  Regexp.last_match(2).empty? ? Regexp.last_match(1).to_f : Regexp.last_match(1).to_f * 2 / 3
end

# Everything about a pass except the processing after the parts: the progression, the sequencer,
# the tempo, and the source part of the sound. With `capture` the parts are not synthesised but
# kept as notes with their voices, for the streamer to play block by block.
Plan = Struct.new(:index, :names, :profile, :profile_row, :drums, :seq, :bpm, :beats, :voice, :mode, :search, :piece,
                  :chord_voices, :seed, :buf, :parts, :pick, keyword_init: true)

# Sounds melody events ([beat, midi, length in beats, gain]) into the buffer with one voice.
def play_line(seq, buf, events, bpm, voice_name)
  beat_seconds = 60.0 / bpm
  plucks = events.map do |beat, midi, length, gain|
    Pluck.new(beat.to_f * beat_seconds, 0.0, midi.to_i, length.to_f * beat_seconds, gain.to_f)
  end
  seq.sound(buf, plucks, seq.voice_spec(voice_name))
end

def plan_pass(data, options, capture: false)
  progressions = data.fetch("progressions")
  seed = options[:seed] || Random.new_seed % 1_000_000
  pick = Random.new(seed)
  index = options[:section_index] || (options[:quick] ? 0 : (options[:prog] || pick.rand(progressions.size)))
  names = options[:names] || progressions.fetch(index) { abort "No progression: #{index}" }
  names = KeyLock.lock(names, options[:key_lock]) if options[:key_lock]
  profile = options[:profile] || data.fetch("default_profile")
  profile_row = data["groove_profiles"].fetch(profile) { abort "No groove profile: #{profile}" }
  drums = options[:drums] || profile_row["drums"] || (options[:random] ? data["drum_patterns"].keys.sample(random: pick) : nil)

  seq = Sequencer.new(data, profile_name: profile, pd_amount: options[:groove], seed:,
                            transpose: options[:transpose] || 0, wrap: options[:wrap], kit: options[:kit])
  seq.capture = [] if capture
  bpm = options[:bpm] || seq.bpm
  seq.tempo = bpm
  beats = options[:beats] || seq.beats
  voice = seq.voice_spec(options[:voice])
  search = !options[:plain]
  mode = play_mode(options, seq)
  validate_scale!(names, options[:melody], options[:scale_pcs]) if options[:scale_pcs]
  warn_past_nyquist(names, search, options)
  chord_voices = piece = nil
  buf =
    case mode
    when "arp"
      arp = seq.arp_settings(options[:arp] || true, style: options[:arp_style], rate: parse_rate(options[:arp_rate]))
      arp["gate"] = options[:gate] if options[:gate]
      seq.render_arp(names, bpm, beats, arp, search:, pad: options[:pad], voice:)
    when "organ"
      piece = Organ.compose(seed:, config: data.fetch("organ"), bars: options[:bars], key: options[:key], scale: options[:scale])
      names = piece.names
      beats = 4.0
      seq.render_organ(piece, bpm, seq.voice_spec("organ"))
    when "repeat"
      comp = seq.comp_settings(options[:repeat] || true)
      comp["gate"] = options[:gate] if options[:gate]
      seq.render_repeat(names, bpm, beats, comp, search:, voice:)
    else
      chord_voices = options[:chord_voices] || (options[:patch_per_chord] ? Playlist.new(data, Random.new(seed)).voices_for(names.size) : nil)
      seq.render_chords(names, bpm, beats, search:, strum: seq.strum(options[:strum]), voice:,
                        voices: chord_voices && seq.voice_specs(chord_voices))
    end
melody = options[:melody] || (options[:improvise] ? Lines.lead(names, beats:, seed:) : nil)
play_line(seq, buf, melody, bpm, options[:melody_voice] || "rhodes_mark1") if melody
play_line(seq, buf, Lines.bass(names, beats:, seed:), bpm, "moog_bass") if options[:improvise]
  render_layers(buf, seq, names, bpm, beats, options, search:)
  Plan.new(index:, names:, profile:, profile_row:, drums:, seq:, bpm:, beats:, voice:, mode:, search:, piece:, chord_voices:, seed:, buf:,
           parts: seq.capture, pick:)
end

# A section of the showcase: one pass rendered whole and mono by the functional effects, kept
# in memory for the arrangement to join. Every other render is streamed (see render_stream).
def render_section(data, options, plan: nil)
  plan ||= plan_pass(data, options)
  names, profile, drums, seq, bpm, beats, buf = plan.to_h.values_at(:names, :profile, :drums, :seq, :bpm, :beats, :buf)
  # Progression buffers reserve a full second for arbitrary note tails. A curated section
  # has a known gate and a short echo, so discard that unused second before rendering drums.
  musical_samples = (names.size * beats * 60.0 / bpm * SAMPLE_RATE).round
  buf = buf.first([musical_samples + (0.36 * SAMPLE_RATE).round, buf.size].min)
  vcs = seq.vcs_amount(options[:vcs])
  sonitex = seq.sonitex_settings(options[:sonitex], instances: options[:sonitex_instances])
  drum_sonitex = seq.sonitex_settings(options[:drum_sonitex], instances: options[:drum_sonitex_instances]) || sonitex
  buf = seq.colour(buf, sonitex, vcs)
  echo = seq.echo_settings(flag: options[:echo], mix: options[:echo_mix], feedback: options[:echo_feedback], time_ms: options[:echo_time])
  echo["tail"] = options[:echo_tail] if echo && options[:echo_tail]
  echo["reverb"] = options[:echo_reverb] unless !echo || options[:echo_reverb].nil?
  buf = seq.echo(buf, echo, bpm, resets: (1...names.size).map { |i| (i * beats * 60.0 / bpm * SAMPLE_RATE).round }) if echo
  buf = FX.dub_echo(buf, options[:instrument_dub_echo]) if options[:instrument_dub_echo]
  buf = FX.crystallizer(buf, options[:instrument_crystallizer]) if options[:instrument_crystallizer]
  drum_seconds = names.size * beats * 60.0 / bpm
  rotation = drums == "rotate" ? data.fetch("drum_patterns").keys : drums
  hits = drums ? seq.drum_hits(rotation, bpm, drum_seconds) : []
  levels = seq.mix(options[:mix])
  levels = apply_reference_mix_balance(levels, drum_balance: options[:drum_balance], chord_balance: options[:chord_balance])
  buf = seq.scale(buf, levels.fetch("chords")) unless hits.empty?
  buf = seq.duck(buf, hits)
  buf = FX.apply(buf, data["groove_profiles"].fetch(profile))
  buf = seq.overlay_drums(
    buf, hits, levels, vcs,
    sonitex: drum_sonitex,
    tape: options[:drum_tape],
    dub_echo: options[:drum_dub_echo],
    crystallizer: options[:drum_crystallizer],
    drum_vcs: options[:drum_vcs]
  ) if drums
  buf
end

# One pass run through the streamer a bar at a time, as --play does: the profile's own stages,
# noise, drums and echo, in stereo unless --mono. Returns the frame and the streamer.
def stream_frame(data, options)
  streamer = Streamer.new(data, options, ring: true)
  frame = Stereo.zeros(streamer.channels, 0)
  bar = streamer.beat * 4
  until streamer.finished?
    part = streamer.next_block(bar)
    Stereo.concat!(frame, streamer.channels == 1 ? [part] : part)
  end
  [frame, streamer]
end

# The master stage of a whole programme: the tape stack, the master chain (EQ, multiband, glue,
# loudness, true-peak), the stereo imager and the dither. Returns the frame, the loudness report
# (nil with --no-master) and the tape instance count.
def master_frame(frame, data, options, seed:, bpm:, channels:)
  tape = data.fetch("tape")
  instances = options.fetch(:tape, tape.fetch("instances"))
  args = { drive: options[:tape_drive] || tape.fetch("drive"), config: tape }
  # the stack is level matched against the programme itself, which a whole render has to hand
  stack = instances.positive? ? ->(sample) { Tape::Stack.new(instances:, seed:, sample:, **args) } : nil
  chain = options[:master] == false ? nil : Mastering::Chain.new(data.fetch("master"), channels:, bpm:, whole: true)
  chain&.target = options[:lufs] if options[:lufs]
  master = Moves::Master.new(tape: stack, ceiling: tape.fetch("ceiling", 0.97), preset: nil, seed:, instances:, tape_args: args,
                             imager: options[:mono] ? nil : data.dig("stereo", "imager"), chain:)
  frame = master.process(frame)
  if (tail = master.flush)
    frame = frame.each_with_index.map { |channel, c| channel.drop(chain.latency) + tail[c].first(chain.latency) } # the limiter's delay taken out
  end
  frame = Mastering::Dither.new(seed).process(frame) if chain && options.fetch(:bits, 16) == 16
  [frame, (Mastering.report(frame) if chain), instances]
end

# One render, streamed whole: the pass is run through the same streamer as --play, a bar at a
# time, then the master stage, and written as a stereo wav (or mono with --mono). Returns the path.
def render_stream(data, options)
  frame, streamer = stream_frame(data, options)
  plan = streamer.plan
  frame, report, instances = master_frame(frame, data, options, seed: plan.seed, bpm: plan.bpm, channels: streamer.channels)
  bits = options.fetch(:bits, 16)
  out = options[:out] || (options[:quick] ? "out/quick.wav" : "out/progression_#{plan.index}#{plan.drums ? "_#{Array(plan.drums).join('+')}" : ''}.wav")
  FileUtils.mkdir_p(File.dirname(out))
  WAV.write_stream(out, frames: frame.first.size, channels: streamer.channels, bits:, replace: options[:replace]) do |offset, count|
    frame.map { |channel| channel.slice(offset, count) }
  end
  if options[:midi]
    FileUtils.mkdir_p(File.dirname(options[:midi]))
    MIDI.write(options[:midi], plan.names, plan.bpm, plan.beats, streamer.hits, search: plan.search, replace: options[:replace])
  end
  piece = plan.piece
  label = piece ? "organ in #{piece.key} #{piece.scale}, #{piece.phrases.size} phrases, #{piece.suspensions} suspensions" : "progression #{plan.index}"
  puts "Wrote #{out} (#{(frame.first.size / SAMPLE_RATE.to_f).round(2)}s, #{streamer.channels == 1 ? 'mono' : 'stereo'}) #{label}: #{plan.names.join(' ')}"
  puts "  drums=#{plan.drums ? Array(plan.drums).join(',') : 'none'} profile=#{plan.profile} mode=#{plan.mode} " \
       "voice=#{piece ? 'organ' : (plan.chord_voices&.join('>') || plan.voice['name'])} groove=#{plan.seq.pd_amount} bpm=#{plan.bpm} tape=#{instances} seed=#{plan.seed}"
  puts Mastering.report_line(report) if report
  out
end

# A render: a showcase section stays whole and mono in memory, anything else is streamed.
def render(data, options) = options[:buffer_only] ? render_section(data, options) : render_stream(data, options)

# A rigged standalone pass uses the same complete per-bus processors as a showcase section,
# followed by the same final tape stack and ceiling.
def render_effect_rig_take(data, options)
  plan = plan_pass(data, options)
  buf = render_section(data, options, plan:)
  buf = tape_stage(buf, data, options, plan.seed)
  fade = [SAMPLE_RATE / 25, buf.size / 2].min
  fade.times do |i|
    buf[i] *= i.to_f / [fade, 1].max
    buf[-fade + i] *= (fade - i - 1).to_f / [fade, 1].max
  end
  peak = buf.map(&:abs).max || 0.0
  buf.map! { |sample| sample * (0.92 / peak) } if peak > 0.92
  out = options[:out] || Dilla::Video.default_paths(root: __dir__).fetch(:audio)
  FileUtils.mkdir_p(File.dirname(out))
  WAV.write(out, buf, bits: options[:bits] || 16, replace: options[:replace])
  if options[:midi]
    drum_seconds = plan.names.size * plan.beats * 60.0 / plan.bpm
    rotation = plan.drums == "rotate" ? data.fetch("drum_patterns").keys : plan.drums
    hits = plan.drums ? plan.seq.drum_hits(rotation, plan.bpm, drum_seconds) : []
    MIDI.write(options[:midi], plan.names, plan.bpm, plan.beats, hits, search: plan.search, replace: options[:replace])
  end
  puts format("Wrote %s (%.2fs, 44.1 kHz mono) — effect rig %s", out, buf.size / SAMPLE_RATE.to_f, options.fetch(:effect_rig))
  puts format("  bpm=%g profile=%s drums=%s kit=%s voice=%s", plan.bpm, plan.profile, plan.drums || "-", options[:kit] || plan.profile_row["kit"] || "-", options[:voice] || plan.profile_row["voice"] || "-")
  out
end

# The last colour before the file: the tape stack, and the ceiling that follows it.
def tape_stage(buf, data, options, seed)
  config = data.fetch("tape")
  Tape.apply(buf, instances: options.fetch(:tape, config.fetch("instances")), drive: options[:tape_drive] || config.fetch("drive"), seed:, config:)
end

# Reject a line whose notes drift out of the arrangement's named scale.
# This keeps every added layer tied to the same harmonic source.
def validate_scale!(names, melody, scale_pcs)
  allowed = scale_pcs.map(&:to_i).uniq
  chord_pcs = names.flat_map do |name|
    chord = Chords.parse(name)
    (chord[:tones].map { |tone| (chord[:pc] + tone) % 12 } + [chord[:bass]].compact).uniq
  end.uniq
  chord_outside = chord_pcs - allowed
  melody_outside = Array(melody).filter_map do |event|
    midi = event[1].to_i
    midi % 12 unless allowed.include?(midi % 12)
  end.uniq
  return if chord_outside.empty? && melody_outside.empty?

  abort "Scale mismatch: chord pitch classes #{chord_outside.inspect}, melody pitch classes #{melody_outside.inspect}, allowed #{allowed.inspect}"
end

# `count` notes of a chord, the lowest and the highest and the ones between spaced evenly: a thin
# layer that still spans the voicing.
def spread(notes, count)
  return notes if count >= notes.size

  Array.new(count) { |i| notes[(i * (notes.size - 1) / [count - 1, 1].max.to_f).round] }.uniq
end

# Add deliberate layers behind and above the main instrument part without modulation effects.
# Held layers use the very same chord voicings; patterned layers share the same tempo and groove.
def render_layers(buf, seq, names, bpm, beats, options, search:)
  # An explicit organ mode is a composed solo unless the caller names layers itself.
  return buf if options[:mode] == "organ" && !options.key?(:layers)

  Array(options.fetch(:layers) { seq.profile_layers }).each do |layer|
    voice = seq.voice_spec(layer.fetch("voice"))
    gate = layer.fetch("gate", 0.9).to_f.clamp(0.05, 1.5)
    mode = layer.fetch("mode", "held")
    layer_buf = nil
    seq.with_part(gain: 10.0**(layer.fetch("gain_db", -12.0).to_f / 20.0)) do
    layer_buf =
      case mode
      when "held"
        layer_buffer = Array.new(buf.size, 0.0)
        beat_seconds = 60.0 / bpm
        chords = Chords.midi_notes(names, search:, transpose: (options[:transpose] || 0) + layer.fetch("transpose", 0).to_i, wrap: options[:wrap])
        chords = chords.map { |notes| notes.first(1) } if layer["notes"] == "bass"
        chords = chords.map { |notes| spread(notes, layer["count"]) } if layer["count"]
        plucks = chords.each_with_index.map do |notes, index|
          Pluck.new(index * beats * beat_seconds, 0.0, notes, beats * beat_seconds * gate,
                    layer.fetch("velocity", 0.55).to_f.clamp(0.0, 1.0))
        end
        seq.sound(layer_buffer, plucks, voice)
        layer_buffer
      when "repeat"
        style = layer.fetch("pattern", "half_note_pulse")
        comp = seq.comp_settings(style).merge("gate" => gate, "modifiers" => [])
        seq.render_repeat(names, bpm, beats, comp, search:, voice:)
      when "arp"
        pattern = layer.fetch("pattern", "updown")
        arp = seq.arp_settings(pattern, rate: layer.fetch("rate", 4).to_f)
        arp["gate"] = gate
        arp["octaves"] = layer.fetch("octaves", 1).to_i.clamp(1, 2)
        arp["modifiers"] = []
        shift = layer.fetch("transpose", 0).to_i
        if shift.zero?
          seq.render_arp(names, bpm, beats, arp, search:, voice:)
        else
          chord_events = seq.note_events(names, bpm, beats, arp, "arp", search:)
          chord_events.each do |plucks|
            plucks.each do |pluck|
              pluck.midi = Array(pluck.midi).map { |midi| midi + shift }.then { |notes| pluck.midi.is_a?(Array) ? notes : notes.first }
            end
          end
          layer_buffer = Array.new(buf.size, 0.0)
          chord_events.each { |plucks| seq.sound(layer_buffer, plucks, voice) }
          layer_buffer
        end
      else
        abort "Unknown synth layer mode: #{mode}"
      end
    end

    next if seq.capture

    gain = 10.0**(layer.fetch("gain_db", -12.0).to_f / 20.0)
    layer_buf.each_with_index do |sample, index|
      buf[index] += sample * gain if index < buf.size
    end
  end
  buf
end

# Keep a broad but finite tempo palette. A seed makes section tempos repeatable, while
# different sections avoid the "every bar at one machine tempo" demo feel.
SHOWCASE_TEMPOS = [92, 100, 108, 96, 116, 104, 112].freeze

def showcase_tempos(seed:, count:)
  order = SHOWCASE_TEMPOS.rotate(seed.to_i.abs % SHOWCASE_TEMPOS.size)
  order.reverse! if seed.to_i.odd?
  Array.new(count) { |index| order[index % order.size] }
end

# One section of the showcase as a stereo frame. A section marked "engine": "stream" runs through
# the streamer, so its profile's own voices, stages, noise, drums and echo all play; any other
# section is the curated mono pass rendered whole by render_section, as it always was.
def showcase_section(data, options, section, index:, seed:, bpm:)
  stream = section["engine"] == "stream"
  mode = options[:mode] || ((options[:arp] || options[:arp_style] || options[:arp_rate]) ? "arp" : (options[:repeat] ? "repeat" : section["mode"]))
  mode ||= "repeat" unless stream
  section_options = {
    names: section.fetch("progression"),
    section_index: index,
    bpm:,
    beats: options[:beats] || section.fetch("beats_per_chord", 2.0),
    gate: options[:gate] || section["gate"],
    voice: options[:voice] || section["voice"],
    mode:,
    repeat: options[:repeat].is_a?(String) ? options[:repeat] : section["repeat"],
    arp: options[:arp] || (mode == "arp" ? true : nil),
    arp_style: options[:arp_style] || section["arp_style"],
    arp_rate: options[:arp_rate] || section["arp_rate"],
    pad: options[:pad] || section["pad"],
    strum: options[:strum] || section["strum"],
    profile: options[:profile] || section["profile"],
    drums: options[:drums] || section["drums"],
    kit: options[:kit] || section["kit"],
    key: section["organ_key"],
    scale: section["scale"],
    bars: section["bars"],
    chord_voices: section["chord_voices"],
    patch_per_chord: section["patch_per_chord"],
    echo: options[:echo] || section["echo"],
    echo_mix: options[:echo_mix] || section["echo_mix"],
    echo_feedback: options[:echo_feedback] || section["echo_feedback"],
    echo_time: options[:echo_time] || section["echo_time_ms"],
    echo_tail: section["echo_tail_seconds"],
    echo_reverb: section["echo_reverb"],
    mix: section.fetch("mix", {}).merge(options[:mix] || {}),
    scale_pcs: section["scale_pcs"],
    melody: section["melody"],
    melody_voice: section["melody_voice"],
    improvise: options[:improvise] || section["improvise"],
    layers: section["layers"],
    seed: seed + (index * 97),
    groove: options[:groove] || section["groove"],
    transpose: options[:transpose] || section["transpose"],
    wrap: options[:wrap],
    plain: options[:plain],
    sonitex: options[:sonitex] || section["sonitex"],
    sonitex_instances: options[:sonitex_instances] || section["sonitex_instances"],
    vcs: options[:vcs].nil? ? section["vcs"] : options[:vcs],
  }
  if stream
    frame, = stream_frame(data, section_options.reject { |_key, value| value.nil? })
    return frame
  end

  effect_rig = data.fetch("bus_effects").fetch(options[:effect_rig] || section.fetch("effect_rig"))
  section_options = {
    **section_options,
    gate: section_options[:gate] || 0.88,
    voice: section_options[:voice] || section.fetch("voice"),
    repeat: section_options[:repeat] || "half_note_pulse",
    profile: section_options[:profile] || "soft_swing",
    drums: section_options[:drums] || section.fetch("drums"),
    kit: section_options[:kit] || "kit_dust",
    echo: section_options[:echo] || false,
    drum_sonitex: options[:drum_sonitex] || effect_rig.fetch("drum_sonitex"),
    drum_sonitex_instances: options[:drum_sonitex_instances] || effect_rig.fetch("drum_sonitex_instances"),
    drum_tape: options[:drum_tape] || effect_rig.fetch("drum_tape"),
    drum_vcs: effect_rig.fetch("drum_vcs"),
    drum_dub_echo: effect_rig.fetch("drum_dub_echo"),
    drum_crystallizer: effect_rig.fetch("drum_crystallizer"),
    instrument_dub_echo: effect_rig.fetch("instrument_dub_echo"),
    instrument_crystallizer: effect_rig.fetch("instrument_crystallizer"),
    buffer_only: true,
  }.reject { |_key, value| value.nil? }
  buffer = render(data, section_options)
  [buffer, buffer.dup]
end

# Render the curated arrangement from the same patches, chord voicer, sequencer, effects,
# and drum synthesiser used by ordinary progression renders.
# Renders `count` takes of one thing, each from its own seed (the first is `seed` itself), and keeps
# the one the Critic finds nearest the target. One take is returned untouched and unmeasured.
def best_take(count, seed:)
  takes = Array.new(count) { |attempt| yield(seed + (attempt * 7919)) }
  return takes.first if takes.one?

  scored = takes.map { |frame| [Critic.score(Critic.measure(frame)), frame] }
  puts "  takes: #{scored.map { |score, _| format('%.1f', score) }.join(' / ')} dB off, keeping #{format('%.1f', scored.map(&:first).min)}"
  scored.min_by(&:first).last
end

def render_showcase(data, options)
  arrangement_path = options.fetch(:arrangement) { File.join(__dir__, "data", "showcase.json") }
  arrangement = JSON.parse(File.read(arrangement_path))
  sections = arrangement.fetch("sections")
  seed = options[:seed] || 261_013
  tempos = showcase_tempos(seed:, count: sections.size)
  default_crossfade = arrangement.fetch("crossfade_seconds", 0.18)
  combined = nil
  bpms = []

  sections.each_with_index do |section, index|
    section_bpm = options[:bpm] || section["bpm"] || tempos.fetch(index)
    bpms << section_bpm
frame = best_take(options[:takes] || 1, seed:) do |take_seed|
  Chords.styled(options[:voicing] || section["voicing"]) { showcase_section(data, options, section, index:, seed: take_seed, bpm: section_bpm) }
end
    if combined.nil?
      combined = frame
    else
      overlap = [((section["crossfade_seconds"] || default_crossfade) * SAMPLE_RATE).round, combined.first.size, frame.first.size].min
      combined.each_index do |c|
        left = combined[c].pop(overlap)
        overlap.times do |i|
          phase = overlap <= 1 ? 1.0 : i.to_f / (overlap - 1)
          combined[c] << (left[i] * (1.0 - phase)) + (frame[c][i] * phase)
        end
        combined[c].concat(frame[c].drop(overlap))
      end
    end
    puts format("section %d/%d: %s — %d BPM, %s", index + 1, sections.size,
                section.fetch("name"), section_bpm, section["voice"] || section["profile"])
  end

  fade = [SAMPLE_RATE / 25, combined.first.size / 2].min
  combined.each do |channel|
    fade.times do |i|
      channel[i] *= i.to_f / [fade, 1].max
      channel[-fade + i] *= (fade - i - 1).to_f / [fade, 1].max
    end
  end
  combined, report, = master_frame(combined, data, options, seed:, bpm: bpms.first, channels: 2)

  out = options[:out] || Dilla::Video.default_paths(root: __dir__).fetch(:audio)
  FileUtils.mkdir_p(File.dirname(out))
  WAV.write(out, combined, bits: options.fetch(:bits, 16), replace: options[:replace])
  puts format("Wrote %s (%.2fs, 44.1 kHz stereo) — %s", out, combined.first.size / SAMPLE_RATE.to_f,
              arrangement.fetch("title"))
  puts "  seed=#{seed}; sections=#{sections.size}; tempos=#{bpms.join(',')}"
  puts Mastering.report_line(report) if report
  puts Critic.line(Critic.measure(combined))
  unless options[:video] == false
    video_out = options[:video] || Dilla::Video.paired_path(out)
    begin
      Dilla::Video.render(audio: out, output: video_out, preset: options[:video_preset] || "dilla_heavy",
                          replace: options[:replace])
    rescue Dilla::Video::Error => e
      abort "studio0: WAV ready at #{out}; MP4 FAILED at #{video_out}: #{e.message}"
    end
  end
  out
end

# Live mode loops the same approved arrangement instead of switching to unrelated progressions.
def play_showcase(data, options)
  # Live uses the exact curated arrangement but renders to a disposable file; it
  # never touches the tracked audition WAV or writes an incidental MP4.
  Dir.mktmpdir("dilla-live-") do |directory|
    path = render_showcase(
      data, options.merge(out: File.join(directory, "dilla.wav"), video: false, replace: false)
    )
    command = player_command(options)
    passes = 0
    loop do
      pid = Process.spawn(*command, path)
      _waited, status = Process.wait2(pid)
      unless status.success?
        warn "player exited with status #{status.exitstatus}"
        break
      end
      passes += 1
      break if options[:passes] && passes >= options[:passes]
    end
  end
end

# A transposed note above the sample rate's limit cannot be played; say so rather than fake it.
def warn_past_nyquist(names, search, options)
  return unless options[:transpose]&.nonzero?

  notes = Chords.midi_notes(names, search:, transpose: options[:transpose], wrap: options[:wrap]).flatten
  over = notes.count { |n| !Voices.audible?(Chords.hz(n)) }
  return if over.zero?

  warn format("warning: %<over>d of %<all>d notes are above %<limit>d Hz and are dropped (silence); --transpose-wrap folds them down",
              over:, all: notes.size, limit: SAMPLE_RATE * NYQUIST_SHARE)
end

# The player command for a wav: --player, else afplay on a Mac, else ffplay.
def player_command(options)
  return Shellwords.split(options[:player]) if options[:player]

  RUBY_PLATFORM.include?("darwin") ? ["afplay"] : %w[ffplay -nodisp -autoexit -loglevel quiet]
end

# Never stops: each pass is drawn from the bags and streamed into the player, one beginning under
# the last beat of the one before. The bags are saved beside the output folder, so a restart
# goes on with the cycle. The player reads raw 16-bit mono PCM on stdin.
def play_forever(data, options)
  player = Player.new(Player.command(options))
  show = Show.new(data, options, player:)
  %w[INT TERM].each { |signal| trap(signal) { show.stop! } }
  show.run
  stats = show.stats
  puts format("played %<audio>.1fs of audio, rendered in %<render>.1fs (%<ratio>.2fx real time), %<under>d late blocks",
              audio: stats[:audio], render: stats[:render], ratio: stats[:render] / [stats[:audio], 1e-9].max, under: stats[:underruns])
end

# The executable dispatch lives here; requiring this file only defines the engine.
run(ARGV) if $PROGRAM_NAME == __FILE__
